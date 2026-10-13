#!/usr/bin/env python3
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
"""altroot-attest (Gate 11) - attest a `pkgadd -R` tree's ownership and
emit a canonical, reproducible tree digest.

Ownership is the highest-stakes dimension of an alternate-root install:
an object left with the WRONG uid/gid boots fine and fails months later
on setuid/perms semantics.  The installed uid/gid come from resolving the
package's owner/group NAMES through the *TARGET* root's /etc/passwd +
/etc/group (via libpkg clgrnam/clpwnam) - NOT the installing box's name
service.  A miniroot whose name service differs from the build host is
exactly where silent mis-ownership creeps in, so this gate resolves names
through the target root and checks the realised uid/gid.

The canonical tree digest is a pure function of (installed manifest,
target name service): one record per object

    path \\0 ftype \\0 mode \\0 uid \\0 gid \\0 size \\0 linktarget \\0 rdev \\n

sorted bytewise and md5'd.  It is identical whether computed on the host
from a repackage manifest or on the box's own contents DB, so it is the
reference fingerprint recorded for later waves.

euid gate: only root can chown/mknod, so only at euid 0 does an installed
uid/gid (or a device node) mean anything.  Verifying ownership against a
root while euid != 0 is INCONCLUSIVE and exits non-zero - without that a
host run as an ordinary user would silently green-light ownership.

Two front ends:
  * imported by repackage-stock.py install_test() (host repackage gate);
  * standalone, to attest a box-installed tree from its OWN contents DB:

      altroot-attest.py --contents <root>/var/sadm/install/contents \\
          --passwd <root>/etc/passwd --group <root>/etc/group \\
          [--root <root> --verify] [--only PKG,PKG]

    With just --contents/--passwd/--group it prints the digest.  Add
    --root --verify to lstat every object and confirm the realised
    ftype/mode/uid/gid/size/link/rdev (requires euid 0).
"""

import argparse
import hashlib
import os
import stat
import sys

# canonical record field order
FIELDS = ("path", "ftype", "mode", "uid", "gid", "size", "link", "rdev")

# ftypes that carry mode + owner/group
_OWNED = set("dxfevcbp")
# ftypes that are links (no mode/owner/group; carry a target)
_LINKS = set("sl")


class AttestError(Exception):
    pass


# --------------------------------------------------------------- name svc

def load_name_ids(passwd_path, group_path):
    """Parse <root>/etc/passwd + /etc/group -> (uid_by_name, gid_by_name)."""
    uid_by_name = {}
    gid_by_name = {}
    for path, dst, idx in ((passwd_path, uid_by_name, 2),
                           (group_path, gid_by_name, 2)):
        try:
            with open(path, "r") as fp:
                for line in fp:
                    line = line.rstrip("\n")
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split(":")
                    if len(parts) <= idx:
                        continue
                    name = parts[0]
                    try:
                        dst[name] = int(parts[idx])
                    except ValueError:
                        continue
        except OSError as exc:
            raise AttestError("cannot read %s: %s" % (path, exc))
    return uid_by_name, gid_by_name


def resolve(name, by_name):
    """Resolve an owner/group NAME through the target name service.
    Returns int id, or None if the name is not in the table and is not a
    bare numeric id (the silent-mis-ownership hazard)."""
    if name in by_name:
        return by_name[name]
    if name.lstrip("-").isdigit():
        return int(name)
    return None


# --------------------------------------------------------------- records

def _canon_fields(path, ftype, mode, uid, gid, size, link, rdev):
    """Normalise one object's attributes to canonical string fields."""
    p = "/" + path.lstrip("/")
    if len(p) > 1:
        p = p.rstrip("/")
    if ftype in _LINKS:
        return {"path": p, "ftype": ftype, "mode": "", "uid": "", "gid": "",
                "size": "", "link": link or "", "rdev": ""}
    d = {"path": p, "ftype": ftype,
         "mode": "%04o" % (mode & 0o7777) if mode is not None else "",
         "uid": "" if uid is None else str(uid),
         "gid": "" if gid is None else str(gid),
         "size": "" if size is None else str(size),
         "link": "", "rdev": ""}
    if ftype in ("c", "b"):
        d["rdev"] = "%d,%d" % rdev if rdev is not None else ""
        d["size"] = ""
    return d


# public alias (importers build records too)
canon_record = _canon_fields


def canonical_lines(records):
    """records: list of dicts (from _canon_fields).  Returns sorted list
    of NUL-joined, newline-terminated byte lines."""
    lines = []
    for r in records:
        joined = "\0".join(str(r[f]) for f in FIELDS) + "\n"
        lines.append(joined.encode("utf-8"))
    lines.sort()
    return lines


def digest(records):
    h = hashlib.md5()
    for ln in canonical_lines(records):
        h.update(ln)
    return h.hexdigest()


# ------------------------------------------------- expected from contents

def records_from_contents(contents_path, uid_by_name, gid_by_name,
                          only_pkgs=None):
    """Parse a contents(4) DB into expected canonical records, resolving
    owner/group names through the target name service.  Returns
    (records, unresolved) where unresolved lists (path, kind, name)."""
    records = []
    unresolved = []
    try:
        fp = open(contents_path, "r")
    except OSError as exc:
        raise AttestError("cannot read %s: %s" % (contents_path, exc))
    with fp:
        for raw in fp:
            line = raw.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            # symlink / hardlink: "path=target ftype class pkg..."
            head = line.split(None, 1)
            if not head:
                continue
            first = head[0]
            rest = head[1].split() if len(head) > 1 else []
            if "=" in first and rest and rest[0] in _LINKS:
                path, target = first.split("=", 1)
                ftype = rest[0]
                pkgs = rest[2:] if len(rest) > 2 else []
                if only_pkgs and not (set(pkgs) & only_pkgs):
                    continue
                records.append(_canon_fields(path, ftype, None, None, None,
                                             None, target, None))
                continue
            toks = line.split()
            if len(toks) < 2:
                continue
            path, ftype = toks[0], toks[1]
            if ftype in _LINKS:
                # "path ftype class pkg" with target folded in path? skip
                continue
            try:
                if ftype in ("c", "b"):
                    # path ftype class major minor mode owner group pkg...
                    major, minor = int(toks[3]), int(toks[4])
                    mode = int(toks[5], 8)
                    owner, group = toks[6], toks[7]
                    pkgs = toks[8:]
                    rdev = (major, minor)
                    size = None
                elif ftype in ("d", "x", "p"):
                    # path ftype class mode owner group pkg...
                    mode = int(toks[3], 8)
                    owner, group = toks[4], toks[5]
                    pkgs = toks[6:]
                    rdev = None
                    size = None
                elif ftype in ("f", "e", "v"):
                    # path ftype class mode owner group size cksum mtime pkg
                    mode = int(toks[3], 8)
                    owner, group = toks[4], toks[5]
                    size = int(toks[6])
                    pkgs = toks[9:]
                    rdev = None
                else:
                    continue
            except (IndexError, ValueError):
                continue
            if only_pkgs and not (set(pkgs) & only_pkgs):
                continue
            uid = resolve(owner, uid_by_name)
            gid = resolve(group, gid_by_name)
            if uid is None:
                unresolved.append((path, "owner", owner))
            if gid is None:
                unresolved.append((path, "group", group))
            records.append(_canon_fields(path, ftype, mode, uid, gid,
                                         size, None, rdev))
    return records, unresolved


# ------------------------------------------------------- lstat verify

def verify_against_root(records, root, require_euid0=True):
    """lstat each object under <root> and compare the realised attributes
    to the expected canonical record.  Returns (mismatches, inconclusive).
    When euid != 0 the uid/gid/rdev dimensions cannot have been realised
    (no chown/mknod), so they are not checked and the result is flagged
    inconclusive."""
    mismatches = []
    inconclusive = require_euid0 and os.geteuid() != 0
    for r in records:
        rel = r["path"].lstrip("/")
        p = os.path.join(root, rel) if rel else root
        try:
            st = os.lstat(p)
        except OSError:
            mismatches.append("%s: missing" % r["path"])
            continue
        ft = r["ftype"]
        m = st.st_mode
        # ftype
        realised = _stat_ftype(m)
        if ft in _LINKS:
            if ft == "s" and realised != "s":
                mismatches.append("%s: not a symlink" % r["path"])
            if ft == "s" and stat.S_ISLNK(m):
                tgt = os.readlink(p)
                if tgt != r["link"]:
                    mismatches.append("%s: link -> %r want %r"
                                      % (r["path"], tgt, r["link"]))
            continue
        # mode
        if r["mode"] and "%04o" % stat.S_IMODE(m) != r["mode"]:
            mismatches.append("%s: mode %04o want %s"
                              % (r["path"], stat.S_IMODE(m), r["mode"]))
        # size (regular files)
        if ft in ("f", "e", "v") and r["size"] and st.st_size != int(r["size"]):
            mismatches.append("%s: size %d want %s"
                              % (r["path"], st.st_size, r["size"]))
        # ownership + device: only meaningful at euid 0
        if not inconclusive:
            if r["uid"] and st.st_uid != int(r["uid"]):
                mismatches.append("%s: uid %d want %s"
                                  % (r["path"], st.st_uid, r["uid"]))
            if r["gid"] and st.st_gid != int(r["gid"]):
                mismatches.append("%s: gid %d want %s"
                                  % (r["path"], st.st_gid, r["gid"]))
            if r["rdev"]:
                mj, mn = (os.major(st.st_rdev), os.minor(st.st_rdev))
                if "%d,%d" % (mj, mn) != r["rdev"]:
                    mismatches.append("%s: rdev %d,%d want %s"
                                      % (r["path"], mj, mn, r["rdev"]))
    return mismatches, inconclusive


def _stat_ftype(m):
    if stat.S_ISDIR(m):
        return "d"
    if stat.S_ISLNK(m):
        return "s"
    if stat.S_ISCHR(m):
        return "c"
    if stat.S_ISBLK(m):
        return "b"
    if stat.S_ISFIFO(m):
        return "p"
    return "f"


# --------------------------------------------------------------- CLI

def main(argv):
    ap = argparse.ArgumentParser(
        description="Attest a pkgadd -R tree's ownership + emit its "
                    "canonical tree digest (Gate 11).")
    ap.add_argument("--contents", required=True,
                    help="<root>/var/sadm/install/contents")
    ap.add_argument("--passwd", required=True, help="<root>/etc/passwd")
    ap.add_argument("--group", required=True, help="<root>/etc/group")
    ap.add_argument("--root", help="lstat objects under this root and verify")
    ap.add_argument("--verify", action="store_true",
                    help="verify realised attributes (requires --root, euid 0)")
    ap.add_argument("--only", help="restrict to comma-separated PKG list")
    args = ap.parse_args(argv)

    only = set(args.only.split(",")) if args.only else None
    try:
        uid_by_name, gid_by_name = load_name_ids(args.passwd, args.group)
        records, unresolved = records_from_contents(
            args.contents, uid_by_name, gid_by_name, only)
    except AttestError as exc:
        print("altroot-attest: %s" % exc, file=sys.stderr)
        return 3

    dg = digest(records)
    print("altroot-attest: objects=%d digest=%s" % (len(records), dg))
    print("DIGEST %s" % dg)

    rc = 0
    if unresolved:
        rc = 2
        for path, kind, name in unresolved[:40]:
            print("altroot-attest: UNRESOLVED %s <%s> for %s (not in target "
                  "name service)" % (kind, name, path), file=sys.stderr)

    if args.verify:
        if not args.root:
            print("altroot-attest: --verify needs --root", file=sys.stderr)
            return 3
        mism, inconclusive = verify_against_root(records, args.root)
        if inconclusive:
            print("altroot-attest: INCONCLUSIVE - euid %d != 0, ownership "
                  "not attested (chown/mknod could not have run)"
                  % os.geteuid(), file=sys.stderr)
            return 4
        for mm in mism[:60]:
            print("altroot-attest: MISMATCH %s" % mm, file=sys.stderr)
        if mism:
            print("altroot-attest: %d mismatch(es)" % len(mism),
                  file=sys.stderr)
            rc = rc or 1
        else:
            print("altroot-attest: VERIFIED %d object(s) at euid 0"
                  % len(records))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
