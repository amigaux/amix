#!/usr/bin/env python3
# dsnorm.py: check that a rolled .pkg depends only on its inputs and the epoch.
#
# MIT licence, see LICENSE at the top of the repository.
# Python 3 standard library only.
"""Check a datastream for everything but its inputs and the epoch.

  dsnorm.py stream PKGFILE EPOCH [--host PATH]... [--refuse-payload]

pkgmk and pkgtrans write a normalised datastream under SOURCE_DATE_EPOCH
(userland/pkgtools, ad02a5a). This checks that they did, and never writes:
in every archive, every member is newc 070701; the members are in C sort
order; ino runs from 1 in archive order, members that share one (hard
links) sharing the new one; uid, gid and dev are 0 and mtime is EPOCH; a
directory's nlink is 2 plus its subdirectories in the archive; a payload
member's mode is the one pkgmap gives it; an ar archive's member headers
are as `ar D` writes them (arnorm.py); and pkgmap's modtime column says
EPOCH. A PATH found in the control files (pkginfo, pkgmap, install/) is
refused; in the payload it is reported, or refused with --refuse-payload (a
gcc14 build, whose paths the compiler remaps). A PATH is found where it
starts a path (/src, not /usr/src) and ends at a component's end.

Exit status: 0 good, 1 refused (each reason on stderr), 2 usage.
"""

import importlib.util
import os
import re
import stat
import sys

# arnorm.py beside this file: what a deterministic ar archive is (loaded
# without leaving a __pycache__ in the harness)
sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location(
    "arnorm", os.path.join(os.path.dirname(os.path.realpath(__file__)), "arnorm.py"))
arnorm = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(arnorm)

MAGIC = b"070701"
FIELDS = ("ino", "mode", "uid", "gid", "nlink", "mtime", "filesize",
          "devmajor", "devminor", "rdevmajor", "rdevminor", "namesize",
          "check")

# The pkgmap lines that end in a modtime: f, e and v objects (part ftype
# class path mode owner group size cksum modtime) and i files (part i name
# size cksum modtime).
MODTIME_RE = re.compile(r"^\d+\s+(?:[fev]\s+\S+\s+\S+(?:\s+\S+){3}|i\s+\S+)"
                        r"\s+\d+\s+\d+\s+(\d+)\s*$")


class Refused(Exception):
    pass


def pkgmap_modes(text):
    """{member name of a payload object: mode} from pkgmap's text."""
    modes = {}
    for line in text.splitlines():
        f = line.split()
        if len(f) < 4 or not f[0].isdigit():
            continue
        ftype, p = f[1], f[3].split("=", 1)[0]
        if ftype in "fevdx" and len(f) >= 5:
            mode = f[4]
        elif ftype in "cb" and len(f) >= 7:
            mode = f[6]
        else:
            continue
        if re.match(r"^[0-7]{3,4}$", mode):
            modes[("root" + p) if p.startswith("/") else ("reloc/" + p)] = int(mode, 8)
    return modes


def members(buf, off):
    """(fields, name, data) of each member of the archive at OFF, through
    its TRAILER!!!, and the offset after it."""
    out = []
    while True:
        if buf[off:off + 6] != MAGIC:
            raise Refused("member at %d is not newc 070701 (%r)"
                          % (off, bytes(buf[off:off + 6])))
        v = dict(zip(FIELDS, (int(buf[off + 6 + 8 * i: off + 14 + 8 * i], 16)
                              for i in range(13))))
        name = buf[off + 110: off + 110 + v["namesize"] - 1].decode("latin-1")
        data = (off + 110 + v["namesize"] + 3) // 4 * 4
        nxt = (data + v["filesize"] + 3) // 4 * 4
        out.append((v, name, bytes(buf[data:data + v["filesize"]])))
        if name == "TRAILER!!!":
            return out, nxt
        off = nxt


def control(name):
    """Whether a member is a control file rather than payload. The first
    archive names its members <pkginst>/pkginfo; the package's own do not."""
    top = name.split("/", 1)[0]
    if "/" in name and top not in ("root", "reloc", "install"):
        top = name.split("/", 1)[1].split("/", 1)[0]
    return top not in ("root", "reloc")


def check_archive(ms, epoch, bad):
    real = [(v, n, d) for v, n, d in ms if n != "TRAILER!!!"]
    names = [n for _, n, _ in real]
    if names != sorted(names, key=lambda n: n.encode("latin-1")):
        bad.append("members not in sorted order: %s" % " ".join(names))
    subdirs, seen, modes = {}, {}, {}
    for v, n, d in real:
        if stat.S_ISDIR(v["mode"]) and "/" in n:
            parent = n.rsplit("/", 1)[0]
            subdirs[parent] = subdirs.get(parent, 0) + 1
        if n == "pkgmap" or n.endswith("/pkgmap"):
            text = d.decode("latin-1")
            modes.update(pkgmap_modes(text))
            for line in text.splitlines():
                m = MODTIME_RE.match(line)
                if m and int(m.group(1)) != epoch:
                    bad.append("%s: modtime %s, not %d: %s" % (n, m.group(1), epoch, line))
    for v, n, _ in real:
        if v["check"] != 0:
            bad.append("%s: a checksum field; not 070701" % n)
        key = (v["devmajor"], v["devminor"], v["ino"])
        want = seen.setdefault(key, len(seen) + 1)
        if v["ino"] != want:
            bad.append("%s: ino %d, not %d (archive order)" % (n, v["ino"], want))
        for f in ("uid", "gid", "devmajor", "devminor"):
            if v[f]:
                bad.append("%s: %s %d, not 0" % (n, f, v[f]))
        if v["mtime"] != epoch:
            bad.append("%s: mtime %d, not %d" % (n, v["mtime"], epoch))
        if stat.S_ISDIR(v["mode"]) and v["nlink"] != 2 + subdirs.get(n, 0):
            bad.append("%s: nlink %d, not %d" % (n, v["nlink"], 2 + subdirs.get(n, 0)))
        if n in modes and stat.S_IMODE(v["mode"]) != modes[n]:
            bad.append("%s: mode %04o, pkgmap says %04o" % (n, stat.S_IMODE(v["mode"]), modes[n]))
    for v, n, d in real:
        if d.startswith(arnorm.MAGIC):
            try:
                if arnorm.normalise(d) is not None:
                    bad.append("%s: an ar archive whose member headers carry a time, uid or mode"
                               " (not as ar D writes them)" % n)
            except ValueError as e:
                bad.append("%s: %s" % (n, e))


def stream(path, epoch, hosts, refuse_payload=False):
    with open(path, "rb") as fp:
        buf = fp.read()
    if not buf.startswith(b"# PaCkAgE DaTaStReAm\n"):
        raise Refused("%s: not a package datastream" % path)
    end = buf.find(b"# end of header\n")
    if end < 0:
        raise Refused("%s: the datastream header has no end" % path)
    off = (end + 16 + 511) // 512 * 512
    pats = [(h, re.compile(rb"(?<![A-Za-z0-9_.+/-])" + re.escape(h.encode())
                           + rb"(?![A-Za-z0-9_.+-])")) for h in hosts]
    archives, bad, hits = 0, [], []
    while off < len(buf) and buf[off:off + 6] == MAGIC:
        ms, nxt = members(buf, off)
        archives += 1
        check_archive(ms, epoch, bad)
        for _, n, d in ms:
            for h, pat in pats:
                if pat.search(d):
                    hits.append((control(n), n, h))
        off = (nxt + 511) // 512 * 512
    if not archives:
        raise Refused("%s: no newc archive after the header" % path)
    if bad:
        raise Refused("%s: not normalised to the epoch %d:\n  %s"
                      % (path, epoch, "\n  ".join(bad)))
    leaks = [h for h in hits if h[0] or refuse_payload]
    if leaks:
        raise Refused("%s: build-host paths in the %s: %s" % (
            path, "control files" if any(c for c, _, _ in leaks) else "payload",
            "; ".join("%s holds %s" % (n, h) for _, n, h in leaks)))
    print("  dsnorm: %d archive(s) normalised to the epoch %d" % (archives, epoch))
    for _, n, h in hits:
        print("  [WARN] payload %s holds the build-host path %s" % (n, h))


def main(argv):
    if len(argv) < 3 or argv[0] != "stream":
        sys.stderr.write(__doc__)
        return 2
    hosts, rest, refuse = [], argv[3:], False
    while rest:
        if rest[0] == "--refuse-payload":
            refuse, rest = True, rest[1:]
        elif rest[0] == "--host" and len(rest) >= 2:
            if rest[1]:
                hosts.append(rest[1])
            rest = rest[2:]
        else:
            sys.stderr.write(__doc__)
            return 2
    if not re.match(r"^[0-9]+$", argv[2]):
        raise Refused("epoch %r is not a number of seconds" % argv[2])
    stream(argv[1], int(argv[2]), hosts, refuse)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refused as e:
        sys.stderr.write("[FAIL] dsnorm: %s\n" % e)
        sys.exit(1)
