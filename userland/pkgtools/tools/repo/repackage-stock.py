#!/usr/bin/env python3
# repackage-stock.py - repackage the Amix 2.1 factory install-tape packages
# (amixpkg media format: one plain cpio-newc archive per tape file, .Z
# compressed where the tape List says zcat=y) into proper SVR4 datastream
# packages built with the HOST heirloom pkgmk/pkgtrans (newc members).
#
# The tape archives were created by root on Amix; extracting them as a
# normal user loses ownership and cannot create device nodes.  This tool
# therefore parses every cpio newc member HEADER itself (mode, uid, gid,
# rdev major/minor, symlink targets, hardlinks) and emits a prototype(5)
# that carries the true metadata; the extracted work tree supplies file
# DATA only.
#
# Usage:
#   repackage-stock.py --scan                  census only, no build
#   repackage-stock.py                         build all 27 packages
#   repackage-stock.py --only core,lp          build a subset
#   repackage-stock.py --install-test lp,core,amigasrc
#                                              build + host pkgadd -R test
#   repackage-stock.py --keep                  keep per-package work dirs
#   repackage-stock.py --member Cdev:usr/ccs/bin/m4 --out <file>
#                                              extract ONE regular-file
#                                              member (data + mtime) and
#                                              print its prototype fields
#                                              "<perm> <owner> <group>
#                                              <size> <mtime>" (the m4
#                                              package's source; see
#                                              build-packages.sh --m4)
#
# MIT License
#
# Copyright (c) 2026 Jussi Alanärä
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import argparse
import os
import re
import shutil
import stat
import subprocess
import sys

import altroot_attest  # Gate 11: canonical digest + name resolution

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                    "..", ".."))
TAPE_DIR = os.path.join(REPO, "hdf", "tape21")
LIST_FILE = os.path.join(TAPE_DIR, "x00", "List")
PASSWD_FILE = os.path.join(REPO, "heirloom", "compat", "tests",
                           "amix-passwd.txt")
GROUP_FILE = os.path.join(REPO, "heirloom", "compat", "tests",
                          "amix-group.txt")
HOSTBIN = os.path.join(REPO, "heirloom", "build-host", "bin")
PKGMK = os.path.join(HOSTBIN, "pkgmk")
PKGTRANS = os.path.join(HOSTBIN, "pkgtrans")
PKGADD = os.path.join(HOSTBIN, "pkgadd")
STAGING = os.path.join(REPO, "build", "repo-staging", "stock")
VERSION = "2.1"
ARCH = "Amiga"
CATEGORY = "system"

NEWC_MAGIC = b"070701"
HDR_LEN = 110
TRAILER = "TRAILER!!!"

# tape data files 02..28 carry the List's packages in order (verified
# against first-member paths and .Z magic vs the zcat=y flags)
FIRST_PKG_TAPE_FILE = 2


# ---------------------------------------------------------------- List

class PkgSpec(object):
    def __init__(self, name, blocks, longname, zcat, opt, tapefile):
        self.name = name          # tape package name == PKG
        self.blocks = blocks      # 512-byte blocks, installed size (List)
        self.longname = longname  # quoted name from List
        self.zcat = zcat
        self.opt = opt
        self.tapefile = tapefile  # absolute path to hdf/tape21/NN


def parse_list(path):
    rx = re.compile(r'pkg=(\S+)\s+size=(\d+)\s+name="([^"]*)"(.*)$')
    specs = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            m = rx.match(line)
            if not m:
                raise SystemExit("List: unparsable line: %r" % line)
            rest = m.group(4)
            n = len(specs) + FIRST_PKG_TAPE_FILE
            specs.append(PkgSpec(m.group(1), int(m.group(2)), m.group(3),
                                 "zcat=y" in rest, "opt=y" in rest,
                                 os.path.join(TAPE_DIR, "%02d" % n)))
    return specs


# ------------------------------------------------------- uid/gid names

def load_idmap(path, uid_field):
    m = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split(":")
            name, num = parts[0], parts[uid_field]
            try:
                num = int(num)
            except ValueError:
                continue
            if num not in m:        # first entry wins (root, uucp, ...)
                m[num] = name
    return m


# ------------------------------------------------------- newc streaming

class Member(object):
    __slots__ = ("name", "ino", "mode", "uid", "gid", "nlink", "mtime",
                 "filesize", "devmajor", "devminor", "rdevmajor",
                 "rdevminor", "target", "hardlink_to", "index")

    def __init__(self):
        self.target = None       # symlink target
        self.hardlink_to = None  # path of the data-carrying twin


class Reader(object):
    """Exact-read wrapper over a file / pipe."""

    def __init__(self, f):
        self.f = f
        self.pos = 0

    def read(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.f.read(n - len(buf))
            if not chunk:
                break
            buf += chunk
        self.pos += len(buf)
        return buf

    def skip(self, n):
        # pipes are not seekable - read and discard in chunks
        left = n
        while left > 0:
            chunk = self.f.read(min(left, 1 << 16))
            if not chunk:
                break
            left -= len(chunk)
        self.pos += n - max(left, 0)


def open_archive(spec):
    """Return (Reader, proc-or-None) for the (possibly .Z) tape file."""
    with open(spec.tapefile, "rb") as probe:
        magic = probe.read(2)
    f = open(spec.tapefile, "rb")
    if magic == b"\x1f\x9d":            # compress(1) LZW
        proc = subprocess.Popen(["zcat"], stdin=f, stdout=subprocess.PIPE)
        f.close()
        return Reader(proc.stdout), proc
    return Reader(f), None


def pad4(n):
    return (4 - n % 4) % 4


def safe_relpath(name):
    """Normalize an archive member path; None if unsafe/unusable."""
    n = name
    while n.startswith("./"):
        n = n[2:]
    n = n.lstrip("/")
    if n in ("", "."):
        return None
    for comp in n.split("/"):
        if comp in ("", ".", ".."):
            return None
    return n


def scan_archive(spec, treedir=None):
    """Parse every newc header; optionally extract regular-file data.

    Returns (members, anomalies, excluded, databytes).
    members    ordered list of Member (trailer excluded)
    anomalies  list of strings
    excluded   list of (path, reason) unrepresentable in prototype(5)
    databytes  total regular-file + symlink data bytes
    """
    members = []
    anomalies = []
    excluded = []
    databytes = 0
    seen_paths = {}
    # hardlink bookkeeping: (devmajor, devminor, ino) -> group members
    linkgroups = {}

    rd, proc = open_archive(spec)
    try:
        while True:
            hdr = rd.read(HDR_LEN)
            if len(hdr) < HDR_LEN:
                anomalies.append("archive ended without TRAILER!!!")
                break
            if hdr[:6] != NEWC_MAGIC:
                anomalies.append("bad member magic %r at offset %d"
                                 % (hdr[:6], rd.pos - HDR_LEN))
                break
            fld = [int(hdr[6 + i * 8: 14 + i * 8], 16) for i in range(13)]
            (ino, mode, uid, gid, nlink, mtime, filesize, devmajor,
             devminor, rdevmajor, rdevminor, namesize, _check) = fld
            raw = rd.read(namesize)
            name = raw.split(b"\0", 1)[0].decode("latin-1")
            rd.skip(pad4(HDR_LEN + namesize))
            if name == TRAILER:
                rd.skip(pad4(filesize) + filesize)
                break

            m = Member()
            m.index = len(members)
            m.ino, m.mode, m.uid, m.gid = ino, mode, uid, gid
            m.nlink, m.mtime, m.filesize = nlink, mtime, filesize
            m.devmajor, m.devminor = devmajor, devminor
            m.rdevmajor, m.rdevminor = rdevmajor, rdevminor

            path = safe_relpath(name)
            if path is None:
                anomalies.append("skipping unsafe/empty member path %r"
                                 % name)
                rd.skip(filesize + pad4(filesize))
                continue
            m.name = path

            if path in seen_paths:
                anomalies.append("duplicate member path %r "
                                 "(keeping first occurrence)" % path)
                rd.skip(filesize + pad4(filesize))
                continue
            seen_paths[path] = m

            ftype = stat.S_IFMT(mode)
            consumed = False

            if ftype == stat.S_IFLNK:
                m.target = rd.read(filesize).decode("latin-1")
                rd.skip(pad4(filesize))
                databytes += filesize
                consumed = True
                if not m.target:
                    anomalies.append("symlink %r has empty target" % path)
            elif ftype == stat.S_IFREG:
                databytes += filesize
                key = (devmajor, devminor, ino)
                if nlink > 1:
                    linkgroups.setdefault(key, []).append(m)
                if filesize > 0 or nlink <= 1:
                    if treedir is not None:
                        dest = os.path.join(treedir, path)
                        d = os.path.dirname(dest)
                        if d and not os.path.isdir(d):
                            os.makedirs(d)
                        with open(dest, "wb") as out:
                            left = filesize
                            while left > 0:
                                chunk = rd.f.read(min(left, 1 << 16))
                                if not chunk:
                                    raise SystemExit(
                                        "%s: short data for %s"
                                        % (spec.tapefile, path))
                                out.write(chunk)
                                left -= len(chunk)
                        rd.pos += filesize
                        os.utime(dest, (mtime, mtime))
                        rd.skip(pad4(filesize))
                        consumed = True
            elif ftype in (stat.S_IFDIR, stat.S_IFCHR, stat.S_IFBLK,
                           stat.S_IFIFO):
                if filesize:
                    anomalies.append("%r: unexpected data (%d bytes) on "
                                     "non-file member" % (path, filesize))
            else:
                anomalies.append("%r: unsupported file type 0%o (skipped)"
                                 % (path, ftype))
                rd.skip(filesize + pad4(filesize))
                seen_paths.pop(path)
                continue

            if not consumed:
                rd.skip(filesize + pad4(filesize))

            # prototype(5) is whitespace-delimited and expands $... and
            # splits path1=path2 - such paths cannot be represented
            bad = [c for c in ("\t", " ", "\n", "=", "$") if c in path]
            if bad:
                excluded.append((path, "char(s) %s in path"
                                 % ",".join(repr(c) for c in bad)))
            members.append(m)
    finally:
        if proc is not None:
            proc.stdout.close()
            proc.wait()
            if proc.returncode not in (0, None):
                anomalies.append("zcat exit status %d" % proc.returncode)
        else:
            rd.f.close()

    # resolve hardlink groups: the data-carrying member is canonical
    # (SVR4 cpio stores the data with the LAST link written).  A
    # zero-size nlink>1 member whose twins are outside the archive is
    # indistinguishable from an empty file - extract it as empty.
    for key, group in linkgroups.items():
        canon = None
        for m in group:
            if m.filesize > 0:
                canon = m
        if canon is None:
            canon = group[0]     # genuinely empty (or truncated) file
            if treedir is not None:
                dest = os.path.join(treedir, canon.name)
                d = os.path.dirname(dest)
                if d and not os.path.isdir(d):
                    os.makedirs(d)
                open(dest, "wb").close()
                os.utime(dest, (canon.mtime, canon.mtime))
            if len(group) == 1:
                anomalies.append("%r: nlink=%d but no data in archive "
                                 "(extracted empty)"
                                 % (canon.name, canon.nlink))
        for m in group:
            if m is not canon:
                m.hardlink_to = canon.name
    return members, anomalies, excluded, databytes


def extract_member(spec, want, dest):
    """Stream the tape archive and write the ONE regular-file member whose
    normalized path is `want` to `dest`, mtime from the cpio header.

    Returns the Member (true mode/uid/gid/size/mtime from the header).
    Fails closed: no such member, a non-regular member, a hardlink twin
    without data, or a short read all exit non-zero, and a partial `dest`
    is removed.  Used by build-packages.sh --m4 to carve one stock file
    out of a factory package without repackaging the whole set.
    """
    rd, proc = open_archive(spec)
    found = None
    try:
        while True:
            hdr = rd.read(HDR_LEN)
            if len(hdr) < HDR_LEN or hdr[:6] != NEWC_MAGIC:
                break
            fld = [int(hdr[6 + i * 8: 14 + i * 8], 16) for i in range(13)]
            (ino, mode, uid, gid, nlink, mtime, filesize, devmajor,
             devminor, rdevmajor, rdevminor, namesize, _check) = fld
            raw = rd.read(namesize)
            name = raw.split(b"\0", 1)[0].decode("latin-1")
            rd.skip(pad4(HDR_LEN + namesize))
            if name == TRAILER:
                break
            if safe_relpath(name) != want:
                rd.skip(filesize + pad4(filesize))
                continue
            if stat.S_IFMT(mode) != stat.S_IFREG:
                raise SystemExit("%s: %s is not a regular file (mode 0%o)"
                                 % (spec.tapefile, want, mode))
            if filesize == 0 and nlink > 1:
                raise SystemExit("%s: %s is a data-less hardlink twin"
                                 % (spec.tapefile, want))
            data = rd.read(filesize)
            if len(data) != filesize:
                raise SystemExit("%s: short data for %s"
                                 % (spec.tapefile, want))
            with open(dest, "wb") as out:
                out.write(data)
            os.utime(dest, (mtime, mtime))
            m = Member()
            m.name, m.mode, m.uid, m.gid = want, mode, uid, gid
            m.nlink, m.mtime, m.filesize = nlink, mtime, filesize
            found = m
            break
    finally:
        if proc is not None:
            proc.stdout.close()
            proc.wait()
        else:
            rd.f.close()
    if found is None:
        raise SystemExit("%s: no member %s" % (spec.tapefile, want))
    return found


# --------------------------------------------------------- prototype

def owner_name(idmap, num, misses):
    if num in idmap:
        return idmap[num]
    misses.add(num)
    return str(num)


def write_prototype(path, members, treedir, uidmap, gidmap, excluded_set):
    """Emit prototype(5); returns (counts-by-ftype, unmapped-ids)."""
    counts = {}
    misses = set()

    def bump(t):
        counts[t] = counts.get(t, 0) + 1

    lines = ["i pkginfo"]
    for m in members:
        if m.name in excluded_set:
            continue
        perm = "%04o" % (m.mode & 0o7777)
        own = owner_name(uidmap, m.uid, misses)
        grp = owner_name(gidmap, m.gid, misses)
        ftype = stat.S_IFMT(m.mode)
        p = "/" + m.name
        if ftype == stat.S_IFDIR:
            lines.append("d none %s %s %s %s" % (p, perm, own, grp))
            bump("d")
        elif ftype == stat.S_IFLNK:
            lines.append("s none %s=%s" % (p, m.target))
            bump("s")
        elif ftype == stat.S_IFREG:
            if m.hardlink_to is not None:
                lines.append("l none %s=/%s" % (p, m.hardlink_to))
                bump("l")
            else:
                src = os.path.join(treedir, m.name)
                lines.append("f none %s=%s %s %s %s"
                             % (p, src, perm, own, grp))
                bump("f")
        elif ftype == stat.S_IFCHR:
            lines.append("c none %s %d %d %s %s %s"
                         % (p, m.rdevmajor, m.rdevminor, perm, own, grp))
            bump("c")
        elif ftype == stat.S_IFBLK:
            lines.append("b none %s %d %d %s %s %s"
                         % (p, m.rdevmajor, m.rdevminor, perm, own, grp))
            bump("b")
        elif ftype == stat.S_IFIFO:
            lines.append("p none %s %s %s %s" % (p, perm, own, grp))
            bump("p")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return counts, misses


def write_pkginfo(path, spec):
    with open(path, "w") as f:
        f.write("PKG=%s\n" % spec.name)
        f.write("NAME=%s\n" % spec.longname)
        f.write("ARCH=%s\n" % ARCH)
        f.write("VERSION=%s\n" % VERSION)
        f.write("CATEGORY=%s\n" % CATEGORY)
        f.write("CLASSES=none\n")
        f.write("APKG_DESC=%s (Amix 2.1 stock)\n" % spec.longname)


# ------------------------------------------------------------- build

def run(cmd, **kw):
    p = subprocess.run(cmd, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, **kw)
    return p.returncode, p.stdout.decode("utf-8", "replace")


def cpio_list_count(spec):
    """Member count via external cpio -it (independent cross-check)."""
    with open(spec.tapefile, "rb") as f:
        if spec.zcat:
            z = subprocess.Popen(["zcat"], stdin=f, stdout=subprocess.PIPE)
            c = subprocess.Popen(["cpio", "-it", "--quiet"], stdin=z.stdout,
                                 stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL)
            z.stdout.close()
            out, _ = c.communicate()
            z.wait()
        else:
            c = subprocess.Popen(["cpio", "-it", "--quiet"], stdin=f,
                                 stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL)
            out, _ = c.communicate()
    return len(out.splitlines())


def build_package(spec, workbase, uidmap, gidmap, keep=False):
    """Extract + prototype + pkgmk + pkgtrans; returns a result dict."""
    res = {"pkg": spec.name, "longname": spec.longname, "ok": False}
    work = os.path.join(workbase, spec.name)
    tree = os.path.join(work, "tree")
    spool = os.path.join(work, "spool")
    if os.path.isdir(work):
        shutil.rmtree(work)
    os.makedirs(tree)
    os.makedirs(spool)

    members, anomalies, excluded, databytes = scan_archive(spec, tree)
    res["members"] = members
    res["files"] = len(members)
    res["bytes"] = databytes
    res["anomalies"] = anomalies
    res["excluded"] = excluded
    res["blocks"] = spec.blocks

    # independent member-count cross-check with external cpio
    ext = cpio_list_count(spec)
    res["cpio_count"] = ext
    dup_or_skipped = sum(1 for a in anomalies
                         if "duplicate member path" in a
                         or "unsupported file type" in a
                         or "unsafe/empty member path" in a)
    if ext != len(members) + dup_or_skipped:
        res["error"] = ("member count mismatch: parsed %d (+%d skipped) "
                        "vs cpio -it %d"
                        % (len(members), dup_or_skipped, ext))
        return res

    excluded_set = set(p for p, _ in excluded)
    counts, misses = write_prototype(os.path.join(work, "prototype"),
                                     members, tree, uidmap, gidmap,
                                     excluded_set)
    res["counts"] = counts
    res["unmapped_ids"] = misses
    write_pkginfo(os.path.join(work, "pkginfo"), spec)

    rc, out = run([PKGMK, "-o", "-d", spool, "-f", "prototype"], cwd=work)
    if rc != 0:
        res["error"] = "pkgmk rc=%d:\n%s" % (rc, out[-4000:])
        return res

    outpkg = os.path.join(STAGING, "%s-%s.pkg" % (spec.name, VERSION))
    if os.path.exists(outpkg):
        os.unlink(outpkg)
    rc, out = run([PKGTRANS, "-s", spool, outpkg, spec.name])
    if rc != 0:
        res["error"] = "pkgtrans rc=%d:\n%s" % (rc, out[-4000:])
        return res

    with open(outpkg, "rb") as f:
        f.seek(512)
        magic = f.read(6)
    if magic != NEWC_MAGIC:
        res["error"] = ("datastream member magic %r != 070701 "
                        "(stock Amix pkgadd would reject)" % magic)
        return res

    res["pkgfile"] = outpkg
    res["pkgsize"] = os.path.getsize(outpkg)
    res["ok"] = True
    if not keep:
        shutil.rmtree(work)
    return res


# ------------------------------------------------------ install test

ADMIN = """mail=
instance=overwrite
partial=nocheck
runlevel=nocheck
idepend=nocheck
rdepend=nocheck
space=nocheck
setuid=nocheck
conflict=nocheck
action=nocheck
basedir=default
"""


def install_test(spec, res, testbase, uidmap, gidmap):
    """pkgadd -R <fakeroot> and compare disk state vs parsed manifest.

    NOTE: fakeroot path must stay well under ~110 chars (heirloom
    fpkginst has a fixed 128-byte path buffer, see research FIXLOG [8]).

    The fakeroot is SEEDED with etc/passwd + etc/group before pkgadd
    runs.  This is not cosmetic: libpkg/ncgrpw.c clgrnam()/clpwnam()
    open "<root>/etc/group" and return NULL the moment that fopen
    fails, so an empty fakeroot silently skips the entire alternate-root
    group/passwd resolution path (clgrnam -> dup_gr_ent) that -R exists
    to exercise.  Without the seed this test could never have covered
    the code that SIGSEGVs on the box (AMIX-PORT.md item 0).

    amix-passwd.txt is the live box file, larger than the one `core`
    ships (1445 vs 1339); amix-group.txt is a fixture of ours with the
    stock group names and gids (amix may not carry the stock file:
    system/MANIFEST.sha256 lists etc/group).  Both are class `none` in
    core, so pkgadd overwrites them to exactly the manifest state and
    the comparison below is unaffected.
    """
    report = {"pkg": spec.name, "ok": False, "mismatches": [],
              "device_skips": [], "notes": [], "unresolved": [],
              "digest": None, "inconclusive": False}
    root = os.path.join(testbase, spec.name)
    if os.path.isdir(root):
        shutil.rmtree(root)
    os.makedirs(root)
    os.makedirs(os.path.join(root, "etc"), exist_ok=True)
    shutil.copyfile(PASSWD_FILE, os.path.join(root, "etc", "passwd"))
    shutil.copyfile(GROUP_FILE, os.path.join(root, "etc", "group"))
    admin = os.path.join(testbase, "admin")
    if not os.path.exists(admin):
        with open(admin, "w") as f:
            f.write(ADMIN)

    rc, out = run([PKGADD, "-R", root, "-n", "-a", admin,
                   "-d", res["pkgfile"], spec.name])
    report["pkgadd_rc"] = rc
    report["pkgadd_tail"] = out[-2500:]

    # Gate 11: resolve the owner/group NAMES through the TARGET root's own
    # /etc/passwd + /etc/group (the seeded copies) - exactly as the engine's
    # clgrnam/clpwnam do under -R.  Only root can chown(), so uid/gid are
    # meaningful (and attestable) only at euid 0; otherwise INCONCLUSIVE.
    uid_by_name, gid_by_name = altroot_attest.load_name_ids(
        os.path.join(root, "etc", "passwd"),
        os.path.join(root, "etc", "group"))
    euid0 = (os.geteuid() == 0)
    report["inconclusive"] = not euid0

    excluded_set = set(p for p, _ in res["excluded"])
    mm = report["mismatches"]
    records = []
    checked = 0
    for m in res["members"]:
        if m.name in excluded_set:
            continue
        p = os.path.join(root, m.name)
        ftype = stat.S_IFMT(m.mode)
        want_perm = m.mode & 0o7777

        # expected uid/gid: the prototype owner/group NAMES resolved
        # through the TARGET root name service (build the digest record).
        own_name = owner_name(uidmap, m.uid, set())
        grp_name = owner_name(gidmap, m.gid, set())
        exp_uid = altroot_attest.resolve(own_name, uid_by_name)
        exp_gid = altroot_attest.resolve(grp_name, gid_by_name)
        if exp_uid is None:
            report["unresolved"].append((m.name, "owner", own_name))
        if exp_gid is None:
            report["unresolved"].append((m.name, "group", grp_name))
        if ftype == stat.S_IFDIR:
            records.append(altroot_attest.canon_record(
                m.name, "d", m.mode, exp_uid, exp_gid, None, None, None))
        elif ftype == stat.S_IFLNK:
            records.append(altroot_attest.canon_record(
                m.name, "s", None, None, None, None, m.target, None))
        elif ftype == stat.S_IFREG and m.hardlink_to is not None:
            records.append(altroot_attest.canon_record(
                m.name, "l", None, None, None, None,
                "/" + m.hardlink_to, None))
        elif ftype == stat.S_IFREG:
            records.append(altroot_attest.canon_record(
                m.name, "f", m.mode, exp_uid, exp_gid, m.filesize, None, None))
        elif ftype == stat.S_IFCHR:
            records.append(altroot_attest.canon_record(
                m.name, "c", m.mode, exp_uid, exp_gid, None, None,
                (m.rdevmajor, m.rdevminor)))
        elif ftype == stat.S_IFBLK:
            records.append(altroot_attest.canon_record(
                m.name, "b", m.mode, exp_uid, exp_gid, None, None,
                (m.rdevmajor, m.rdevminor)))
        elif ftype == stat.S_IFIFO:
            records.append(altroot_attest.canon_record(
                m.name, "p", m.mode, exp_uid, exp_gid, None, None, None))

        if ftype in (stat.S_IFCHR, stat.S_IFBLK):
            if not os.path.exists(p):
                report["device_skips"].append(m.name)
            elif euid0:
                st = os.lstat(p)
                mj, mn = os.major(st.st_rdev), os.minor(st.st_rdev)
                if (mj, mn) != (m.rdevmajor, m.rdevminor):
                    mm.append("%s: rdev %d,%d want %d,%d"
                              % (m.name, mj, mn, m.rdevmajor, m.rdevminor))
                _check_ugid(mm, m.name, st, exp_uid, exp_gid)
            checked += 1
            continue
        try:
            st = os.lstat(p)
        except OSError:
            mm.append("%s: missing" % m.name)
            continue
        checked += 1
        if ftype == stat.S_IFDIR:
            if not stat.S_ISDIR(st.st_mode):
                mm.append("%s: not a directory" % m.name)
            elif stat.S_IMODE(st.st_mode) != want_perm:
                mm.append("%s: dir mode %04o want %04o"
                          % (m.name, stat.S_IMODE(st.st_mode), want_perm))
            _check_ugid(mm, m.name, st, exp_uid, exp_gid, euid0)
        elif ftype == stat.S_IFLNK:
            if not stat.S_ISLNK(st.st_mode):
                mm.append("%s: not a symlink" % m.name)
            elif os.readlink(p) != m.target:
                mm.append("%s: symlink -> %r want %r"
                          % (m.name, os.readlink(p), m.target))
        elif ftype == stat.S_IFREG:
            if m.hardlink_to is not None:
                canon = os.lstat(os.path.join(root, m.hardlink_to))
                if st.st_ino != canon.st_ino:
                    mm.append("%s: not hardlinked to %s"
                              % (m.name, m.hardlink_to))
                continue
            if not stat.S_ISREG(st.st_mode):
                mm.append("%s: not a regular file" % m.name)
                continue
            if st.st_size != m.filesize:
                mm.append("%s: size %d want %d"
                          % (m.name, st.st_size, m.filesize))
            if stat.S_IMODE(st.st_mode) != want_perm:
                mm.append("%s: mode %04o want %04o"
                          % (m.name, stat.S_IMODE(st.st_mode), want_perm))
            _check_ugid(mm, m.name, st, exp_uid, exp_gid, euid0)
        elif ftype == stat.S_IFIFO:
            if not stat.S_ISFIFO(st.st_mode):
                mm.append("%s: not a fifo" % m.name)
            _check_ugid(mm, m.name, st, exp_uid, exp_gid, euid0)
    report["checked"] = checked
    report["digest"] = altroot_attest.digest(records)
    report["ok"] = (rc in (0, 2)) and not mm
    if rc == 2:
        report["notes"].append("pkgadd rc=2 (partial: expected when "
                               "device mknod fails as non-root)")
    if report["inconclusive"]:
        report["notes"].append("euid != 0: ownership (uid/gid) NOT attested "
                               "- INCONCLUSIVE; attest on the box at euid 0")
    return report


def _check_ugid(mm, name, st, exp_uid, exp_gid, euid0=True):
    """Attest realised ownership - only meaningful at euid 0 (chown ran)."""
    if not euid0:
        return
    if exp_uid is not None and st.st_uid != exp_uid:
        mm.append("%s: uid %d want %d" % (name, st.st_uid, exp_uid))
    if exp_gid is not None and st.st_gid != exp_gid:
        mm.append("%s: gid %d want %d" % (name, st.st_gid, exp_gid))


# ------------------------------------------------------------- main

def fmt_size(n):
    return "{:,}".format(n)


def main():
    ap = argparse.ArgumentParser(description="repackage Amix 2.1 factory "
                                 "tape packages as SVR4 datastreams")
    ap.add_argument("--scan", action="store_true",
                    help="census only - parse headers, no build")
    ap.add_argument("--only", help="comma-separated package subset")
    ap.add_argument("--install-test",
                    help="comma-separated packages to pkgadd -R verify")
    ap.add_argument("--keep", action="store_true",
                    help="keep per-package work trees")
    ap.add_argument("--member",
                    help="PKG:path - extract one regular-file member")
    ap.add_argument("--out", help="destination file for --member")
    args = ap.parse_args()

    specs = parse_list(LIST_FILE)
    for s in specs:
        if len(s.name) > 9:
            raise SystemExit("PKG %r longer than 9 chars" % s.name)
        if not os.path.exists(s.tapefile):
            raise SystemExit("missing tape file %s" % s.tapefile)
    if args.only:
        want = set(args.only.split(","))
        unknown = want - set(s.name for s in specs)
        if unknown:
            raise SystemExit("unknown package(s): %s" % ",".join(unknown))
        specs = [s for s in specs if s.name in want]

    uidmap = load_idmap(PASSWD_FILE, 2)
    gidmap = load_idmap(GROUP_FILE, 2)

    if args.member:
        if not args.out or ":" not in args.member:
            raise SystemExit("--member PKG:path needs --out <file>")
        pkg, want = args.member.split(":", 1)
        spec = [s for s in specs if s.name == pkg]
        if not spec:
            raise SystemExit("unknown package %r" % pkg)
        want = safe_relpath(want)
        if want is None:
            raise SystemExit("bad member path %r" % args.member)
        try:
            m = extract_member(spec[0], want, args.out)
        except SystemExit:
            if os.path.exists(args.out):
                os.unlink(args.out)
            raise
        misses = set()
        print("%04o %s %s %d %d" % (m.mode & 0o7777,
                                    owner_name(uidmap, m.uid, misses),
                                    owner_name(gidmap, m.gid, misses),
                                    m.filesize, m.mtime))
        if misses:
            raise SystemExit("unmapped uid/gid %s" % sorted(misses))
        return

    if args.scan:
        for s in specs:
            members, anomalies, excluded, databytes = scan_archive(s, None)
            counts = {}
            devs, links, miss = [], 0, set()
            for m in members:
                t = stat.S_IFMT(m.mode)
                counts[t] = counts.get(t, 0) + 1
                if t in (stat.S_IFCHR, stat.S_IFBLK):
                    devs.append(m.name)
                if m.hardlink_to:
                    links += 1
                if m.uid not in uidmap:
                    miss.add(("uid", m.uid))
                if m.gid not in gidmap:
                    miss.add(("gid", m.gid))
            tn = {stat.S_IFREG: "f", stat.S_IFDIR: "d", stat.S_IFLNK: "s",
                  stat.S_IFCHR: "c", stat.S_IFBLK: "b", stat.S_IFIFO: "p"}
            cstr = " ".join("%s=%d" % (tn.get(k, "?%o" % k), v)
                            for k, v in sorted(counts.items()))
            print("%-9s members=%-5d data=%-11d %s hardlinks=%d "
                  "devices=%d unmapped=%s"
                  % (s.name, len(members), databytes, cstr, links,
                     len(devs), sorted(miss) or "-"))
            for a in anomalies:
                print("          anomaly: %s" % a)
            for p, r in excluded:
                print("          EXCLUDE: %s (%s)" % (p, r))
        return

    for tool in (PKGMK, PKGTRANS):
        if not os.access(tool, os.X_OK):
            raise SystemExit("%s missing - run heirloom/build-host.sh" % tool)
    os.makedirs(STAGING, exist_ok=True)
    workbase = os.path.join(STAGING, ".work")
    testbase = os.path.join(STAGING, ".t")

    results = []
    for s in specs:
        sys.stderr.write("== %s (%s)\n" % (s.name, s.longname))
        sys.stderr.flush()
        res = build_package(s, workbase, uidmap, gidmap, keep=args.keep)
        results.append(res)
        if not res["ok"]:
            sys.stderr.write("FAILED %s: %s\n" % (s.name,
                                                  res.get("error", "?")))

    # ------------------------------------------------ install tests
    itests = []
    if args.install_test:
        want = args.install_test.split(",")
        os.makedirs(testbase, exist_ok=True)
        bypkg = dict((r["pkg"], r) for r in results)
        for name in want:
            r = bypkg.get(name)
            if r is None or not r["ok"]:
                itests.append({"pkg": name, "ok": False,
                               "mismatches": ["package not built"],
                               "device_skips": [], "notes": []})
                continue
            spec = [s for s in specs if s.name == name][0]
            itests.append(install_test(spec, r, testbase, uidmap, gidmap))

    # ------------------------------------------------------- report
    print()
    print("package    files      bytes  d     f    s   l  c  b  "
          "blocks(List)    .pkg size  status")
    print("-" * 95)
    tf = tb = tp = 0
    for r in results:
        c = r.get("counts", {})
        status = "OK" if r["ok"] else "FAIL"
        print("%-9s %6d %10s %4d %5d %4d %3d %2d %2d %9d %13s  %s"
              % (r["pkg"], r.get("files", 0), fmt_size(r.get("bytes", 0)),
                 c.get("d", 0), c.get("f", 0), c.get("s", 0),
                 c.get("l", 0), c.get("c", 0), c.get("b", 0),
                 r.get("blocks", 0), fmt_size(r.get("pkgsize", 0)), status))
        tf += r.get("files", 0)
        tb += r.get("bytes", 0)
        tp += r.get("pkgsize", 0)
    print("-" * 95)
    print("%-9s %6d %10s %48s" % ("TOTAL", tf, fmt_size(tb), fmt_size(tp)))

    bad = False
    for r in results:
        if not r["ok"]:
            bad = True
            print("\nFAIL %s: %s" % (r["pkg"], r.get("error")))
        for p, reason in r.get("excluded", []):
            print("\nEXCLUDED from %s: %r (%s) - unrepresentable in "
                  "prototype(5)" % (r["pkg"], p, reason))
        for a in r.get("anomalies", []):
            print("anomaly %s: %s" % (r["pkg"], a))
        if r.get("unmapped_ids"):
            print("unmapped ids in %s: %s (numeric strings used)"
                  % (r["pkg"], sorted(r["unmapped_ids"])))

    inconclusive_any = False
    for t in itests:
        print("\ninstall-test %s: rc=%s checked=%s devices-skipped=%d "
              "digest=%s %s"
              % (t["pkg"], t.get("pkgadd_rc"), t.get("checked"),
                 len(t["device_skips"]), t.get("digest"),
                 "PASS" if t["ok"] else "FAIL"))
        for n in t["notes"]:
            print("  note: %s" % n)
        for u in t.get("unresolved", [])[:20]:
            print("  UNRESOLVED %s <%s> for %s" % (u[1], u[2], u[0]))
        for mmm in t["mismatches"][:40]:
            print("  mismatch: %s" % mmm)
        if len(t["mismatches"]) > 40:
            print("  ... %d more" % (len(t["mismatches"]) - 40))
        if not t["ok"]:
            bad = True
        if t.get("inconclusive"):
            inconclusive_any = True

    if bad:
        sys.exit(1)
    if inconclusive_any:
        # Gate 11: a non-root host run cannot attest ownership - do NOT
        # exit 0 (that would silently green-light uid/gid).  The tree
        # digest(s) above are still valid references.
        print("\nINCONCLUSIVE: install-test ran as euid %d (not root); "
              "ownership (uid/gid) was NOT attested. Re-run at euid 0 "
              "(the bench box) to attest ownership." % os.geteuid())
        sys.exit(3)
    sys.exit(0)


if __name__ == "__main__":
    main()
