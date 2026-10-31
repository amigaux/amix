#!/usr/bin/env python3
# arnorm.py: ar archives of a staged payload, as `ar D` writes them.
#
# MIT licence, see LICENSE at the top of the repository.
# Python 3 standard library only.
"""Give every ar archive under DIR deterministic member headers.

  arnorm.py DIR

A recipe's make runs `$(AR) rc`, and gcc14's ar is not built to be
deterministic, so each member header of a static library carries the build's
time, the builder's uid and gid and the object's mode. Here every ar archive
(a regular file starting "!<arch>\\n") under DIR gets what `ar D` writes:
date 0, uid 0, gid 0, and mode 644 for a member (the symbol table's and the
long-name table's modes are left as they are). Names, sizes and data are not
touched, so the symbol table's offsets stay right. Prints one line per
archive changed. Exit status: 0 done, 1 an archive that does not parse.
"""

import os
import sys

MAGIC = b"!<arch>\n"
TABLES = (b"/", b"//", b"/SYM64/")


def field(value, width):
    return value.ljust(width)


def normalise(buf):
    """The archive's bytes with deterministic headers (or None if unchanged)."""
    out = bytearray(buf)
    off = len(MAGIC)
    while off < len(buf):
        if off + 60 > len(buf) or buf[off + 58:off + 60] != b"`\n":
            raise ValueError("member header at %d is not an ar header" % off)
        name = bytes(buf[off:off + 16]).rstrip(b" ")
        size = int(buf[off + 48:off + 58].strip() or b"0")
        if buf[off + 16:off + 28].strip():
            out[off + 16:off + 28] = field(b"0", 12)
        if buf[off + 28:off + 34].strip():
            out[off + 28:off + 34] = field(b"0", 6)
        if buf[off + 34:off + 40].strip():
            out[off + 34:off + 40] = field(b"0", 6)
        if name not in TABLES and buf[off + 40:off + 48].strip():
            out[off + 40:off + 48] = field(b"644", 8)
        off += 60 + size + (size & 1)
    return None if out == buf else bytes(out)


def main(argv):
    if len(argv) != 1:
        sys.stderr.write(__doc__)
        return 2
    bad = 0
    for root, dirs, files in os.walk(argv[0]):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(root, f)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            with open(p, "rb") as fp:
                if fp.read(len(MAGIC)) != MAGIC:
                    continue
                fp.seek(0)
                buf = fp.read()
            try:
                new = normalise(buf)
            except ValueError as e:
                sys.stderr.write("[FAIL] arnorm: %s: %s\n" % (p, e))
                bad = 1
                continue
            if new is not None:
                st = os.stat(p)
                with open(p, "wb") as fp:
                    fp.write(new)
                os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))
                print("  AR norm   %s: member headers as ar D writes them"
                      % os.path.relpath(p, argv[0]))
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
