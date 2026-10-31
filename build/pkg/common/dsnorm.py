#!/usr/bin/env python3
# dsnorm.py: make a rolled .pkg depend only on its inputs and the epoch.
#
# MIT licence, see LICENSE at the top of the repository.
# Python 3 standard library only.
"""Normalise a pkgmk spool and the datastream pkgtrans writes from it.

  dsnorm.py spool SPOOL PKG EPOCH
      every file and directory of SPOOL/PKG: its mode from pkgmap (the
      prototype's), 0644 for a file pkgmap does not list (pkginfo, pkgmap,
      install/*) and 0755 for such a directory; its time EPOCH. pkgmap's
      modtime column says EPOCH too: pkgmk gives its own copy of pkginfo
      the time it wrote it.
  dsnorm.py stream PKGFILE EPOCH [--host PATH]...
      the newc headers of every archive of the datastream, rewritten in
      place: ino renumbered from 1 in archive order (members that share an
      ino share the new one, so hard links stay pairs), uid and gid 0, dev
      0, mtime EPOCH, a directory's nlink 2 plus its subdirectories in the
      archive. Names, sizes, data and padding are not touched. A PATH
      found in the control files (pkginfo, pkgmap, install/) is refused;
      in the payload it is reported. A PATH is found where it starts a
      path (/src, not /usr/src) and ends at a component's end.

The member order is pkgtrans's own: it lists the spool with find, and the
roll puts a sorting find first on its PATH (sortedfind/find beside this file).
Exit status: 0 done, 1 refused, 2 usage.
"""

import os
import re
import stat
import sys

MAGIC = b"070701"
FIELDS = ("ino", "mode", "uid", "gid", "nlink", "mtime", "filesize",
          "devmajor", "devminor", "rdevmajor", "rdevminor", "namesize",
          "check")


class Refused(Exception):
    pass


def pkgmap_modes(path):
    """{path in the spool, relative to PKG: mode} from pkgmap."""
    modes = {}
    with open(path, encoding="latin-1") as fp:
        for line in fp:
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
            if not re.match(r"^[0-7]{3,4}$", mode):
                continue
            rel = ("root" + p) if p.startswith("/") else ("reloc/" + p)
            modes[rel] = int(mode, 8)
    return modes


# The pkgmap lines that end in a modtime: f, e and v objects (part ftype
# class path mode owner group size cksum modtime) and i files (part i name
# size cksum modtime).
MODTIME_RE = re.compile(r"^(\d+\s+(?:[fev]\s+\S+\s+\S+(?:\s+\S+){3}|i\s+\S+)"
                        r"\s+\d+\s+\d+\s+)\d+(\s*)$")


def pkgmap_epoch(path, epoch):
    with open(path, encoding="latin-1") as fp:
        lines = fp.readlines()
    out = [MODTIME_RE.sub(lambda m: "%s%d%s" % (m.group(1), epoch, m.group(2)), l)
           for l in lines]
    with open(path, "w", encoding="latin-1") as fp:
        fp.writelines(out)
    return sum(1 for a, b in zip(lines, out) if a != b)


def spool(spooldir, pkg, epoch):
    top = os.path.join(spooldir, pkg)
    pkgmap_epoch(os.path.join(top, "pkgmap"), epoch)
    modes = pkgmap_modes(os.path.join(top, "pkgmap"))
    n = 0
    for root, dirs, files in os.walk(top):
        for name in dirs + files:
            p = os.path.join(root, name)
            rel = os.path.relpath(p, top)
            st = os.lstat(p)
            if stat.S_ISLNK(st.st_mode):
                os.utime(p, (epoch, epoch), follow_symlinks=False)
                continue
            default = 0o755 if stat.S_ISDIR(st.st_mode) else 0o644
            os.chmod(p, modes.get(rel, default))
            n += 1
    # times last, children before parents: a chmod does not move mtime, but
    # creating nothing more keeps the directories' times as set
    for root, dirs, files in os.walk(top, topdown=False):
        for name in dirs + files:
            os.utime(os.path.join(root, name), (epoch, epoch),
                     follow_symlinks=False)
    os.utime(top, (epoch, epoch))
    print("  dsnorm spool: %d object(s) of %s, modes from pkgmap, time %d"
          % (n, pkg, epoch))


def members(buf, off):
    """(header offset, fields, name, data offset, next offset) of each
    member of the archive at OFF, through its TRAILER!!!."""
    out = []
    while True:
        if buf[off:off + 6] != MAGIC:
            raise Refused("member at %d is not newc 070701 (%r)"
                          % (off, buf[off:off + 6]))
        v = dict(zip(FIELDS, (int(buf[off + 6 + 8 * i: off + 14 + 8 * i], 16)
                              for i in range(13))))
        name = buf[off + 110: off + 110 + v["namesize"] - 1].decode("latin-1")
        data = (off + 110 + v["namesize"] + 3) // 4 * 4
        nxt = (data + v["filesize"] + 3) // 4 * 4
        out.append((off, v, name, data, nxt))
        if name == "TRAILER!!!":
            return out, nxt
        off = nxt


def put(buf, off, field, value):
    i = 6 + 8 * FIELDS.index(field)
    buf[off + i: off + i + 8] = b"%08X" % value


def control(name):
    """Whether a member is a control file rather than payload. The first
    archive names its members <pkginst>/pkginfo; the package's own do not."""
    top = name.split("/", 1)[0]
    if "/" in name and top not in ("root", "reloc", "install"):
        name, top = name.split("/", 1)[1], name.split("/", 1)[1].split("/", 1)[0]
    return top not in ("root", "reloc")


def stream(path, epoch, hosts):
    with open(path, "rb") as fp:
        buf = bytearray(fp.read())
    if not buf.startswith(b"# PaCkAgE DaTaStReAm\n"):
        raise Refused("%s: not a package datastream" % path)
    end = buf.find(b"# end of header\n")
    if end < 0:
        raise Refused("%s: the datastream header has no end" % path)
    off = (end + 16 + 511) // 512 * 512
    archives = 0
    hits = []
    while off < len(buf) and buf[off:off + 6] == MAGIC:
        ms, nxt = members(buf, off)
        archives += 1
        new_ino, subdirs = {}, {}
        pats = [(h, re.compile(rb"(?<![A-Za-z0-9_.+/-])" + re.escape(h.encode())
                               + rb"(?![A-Za-z0-9_.+-])")) for h in hosts]
        for _, v, name, _, _ in ms:
            if stat.S_ISDIR(v["mode"]) and "/" in name:
                parent = name.rsplit("/", 1)[0]
                subdirs[parent] = subdirs.get(parent, 0) + 1
        for hoff, v, name, data, _ in ms:
            if name == "TRAILER!!!":
                continue
            if v["check"] != 0:
                raise Refused("%s: %s has a checksum field; not 070701" % (path, name))
            key = (v["devmajor"], v["devminor"], v["ino"])
            new_ino.setdefault(key, len(new_ino) + 1)
            put(buf, hoff, "ino", new_ino[key])
            for f in ("uid", "gid", "devmajor", "devminor"):
                put(buf, hoff, f, 0)
            put(buf, hoff, "mtime", epoch)
            if stat.S_ISDIR(v["mode"]):
                put(buf, hoff, "nlink", 2 + subdirs.get(name, 0))
            body = bytes(buf[data:data + v["filesize"]])
            for h, pat in pats:
                if pat.search(body):
                    hits.append((control(name), name, h))
        off = (nxt + 511) // 512 * 512
    if not archives:
        raise Refused("%s: no newc archive after the header" % path)
    bad = [h for h in hits if h[0]]
    if bad:
        raise Refused("%s: build-host paths in the control files: %s" % (
            path, "; ".join("%s holds %s" % (n, h) for _, n, h in bad)))
    with open(path + ".norm", "wb") as fp:
        fp.write(buf)
    os.replace(path + ".norm", path)
    print("  dsnorm stream: %d archive(s), headers normalised to time %d"
          % (archives, epoch))
    for _, n, h in hits:
        print("  [WARN] payload %s holds the build-host path %s" % (n, h))


def main(argv):
    if len(argv) >= 4 and argv[0] == "spool" and len(argv) == 4:
        spool(argv[1], argv[2], epoch_arg(argv[3]))
    elif len(argv) >= 3 and argv[0] == "stream":
        hosts, rest = [], argv[3:]
        while rest:
            if rest[0] != "--host" or len(rest) < 2:
                return usage()
            if rest[1]:
                hosts.append(rest[1])
            rest = rest[2:]
        stream(argv[1], epoch_arg(argv[2]), hosts)
    else:
        return usage()
    return 0


def epoch_arg(s):
    if not re.match(r"^[0-9]+$", s):
        raise Refused("epoch %r is not a number of seconds" % s)
    return int(s)


def usage():
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refused as e:
        sys.stderr.write("[FAIL] dsnorm: %s\n" % e)
        sys.exit(1)
