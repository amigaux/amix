#!/usr/bin/env python3
"""mkfixture.py -- build the HOST-side archive the on-box tar smoke reads.

    python3 recipes/tar/tests/mkfixture.py OUT.tar

Deterministic (fixed mtimes, fixed order), so the fixture is reproducible and
never committed.  Written with Python's tarfile in GNU format because that
gives per-entry control of exactly the fields the smoke is about:

  big.txt     uid 3000000, NO user name -- 3000000 > 07777777 does not fit the
              8-byte octal field, so it is written BASE-256.  tar < 1.13 cannot
              read it; `tar -tv` on the box must print 3000000 (registry: the
              reason 1.14 was chosen).
  own-bin.txt uname "bin"/gname "bin" with a wrong numeric id (4242): extracted
              as root with same-owner, tar maps the NAME back through getpwnam()
              -- the D3 path -- and must land on the box's own bin uid, not 4242.
  own-nobody  uname "nosuchuser" uid 1234: no such name, so tar keeps 1234.
  <deep path> > 100 bytes in total (GNU long-name record), every component
              <= 14 bytes so the s5 dirent limit is not what is being tested.
  link        a symlink -> target.txt (must extract AS a symlink).
"""
import io
import sys
import tarfile

MTIME = 700000000  # 1992-03-08: inside the box's clock range (Y2K-capped)


def add_file(tf, name, data, uid=0, gid=0, uname="root", gname="sys"):
    ti = tarfile.TarInfo(name)
    ti.size = len(data)
    ti.mtime = MTIME
    ti.mode = 0o644
    ti.uid, ti.gid, ti.uname, ti.gname = uid, gid, uname, gname
    tf.addfile(ti, io.BytesIO(data))


def add_dir(tf, name):
    ti = tarfile.TarInfo(name)
    ti.type = tarfile.DIRTYPE
    ti.mode = 0o755
    ti.mtime = MTIME
    ti.uname, ti.gname = "root", "sys"
    tf.addfile(ti)


def main():
    out = sys.argv[1]
    deep = "fx/" + "/".join(["d%02d-abcdefgh" % i for i in range(9)])
    with tarfile.open(out, "w", format=tarfile.GNU_FORMAT) as tf:
        add_dir(tf, "fx")
        add_file(tf, "fx/target.txt", b"target contents\n")
        ln = tarfile.TarInfo("fx/link")
        ln.type = tarfile.SYMTYPE
        ln.linkname = "target.txt"
        ln.mtime = MTIME
        ln.mode = 0o777
        ln.uname, ln.gname = "root", "sys"
        tf.addfile(ln)
        add_file(tf, "fx/big.txt", b"base-256 uid\n", uid=3000000, gid=3000000,
                 uname="", gname="")
        add_file(tf, "fx/own-bin.txt", b"owned by bin\n", uid=4242, gid=4242,
                 uname="bin", gname="bin")
        add_file(tf, "fx/own-nobody", b"no such user\n", uid=1234, gid=1234,
                 uname="nosuchuser", gname="nosuchgroup")
        d = "fx"
        for part in deep.split("/")[1:]:
            d = d + "/" + part
            add_dir(tf, d)
        add_file(tf, deep + "/leaf.txt", b"deep leaf\n")
    print("deep path length:", len(deep + "/leaf.txt"))


if __name__ == "__main__":
    main()
