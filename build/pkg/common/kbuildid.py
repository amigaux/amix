#!/usr/bin/env python3
"""kbuildid.py -- the module core's build-id rule, as a packaging gate.

    python3 -I build/pkg/common/kbuildid.py <unix (ET_REL)> <kabi> <module>...

A core-tier module loads only on the kernel build it was made with (C3-1
sec 3).  The module core takes the kernel's build id from the image's own
`buildid` string, skips the leading blanks a stamp writes (the port's
" 68060-..."; amix-dlm 7b07bce, core/plat/amiga.c plat_dmainit:
`while (*bid == ' ') bid++;`) and compares the rest byte for byte with the
module's .moddata build=.  This script applies that rule to the shipped
bytes: the image's buildid with the leading blanks stripped, the sidecar's
build= and every module's .moddata build= must be one string, non-empty,
byte for byte.  It prints the three (or more) values and exits 0 when they
are equal, 1 when any differs, 2 on an unreadable input.

The rule is the core's from 7b07bce on; a core before it compared the
blank too and refused every k46 core-tier module (S5-13).  Which core a cut
links is the recipe's second gate (the cut's dlm-rev against the pin).
"""
import struct
import sys


def elf(d):
    if d[:4] != b"\x7fELF" or d[4] != 1 or d[5] != 2:
        raise ValueError("not a big-endian ELF32 object")
    shoff, = struct.unpack(">I", d[32:36])
    es, n, si = struct.unpack(">HHH", d[46:52])
    return [struct.unpack(">10I", d[shoff + i * es: shoff + i * es + 40]) for i in range(n)], si


def cstr(d, o):
    return d[o: d.index(b"\0", o)]


def image_buildid(path):
    d = open(path, "rb").read()
    sh, _ = elf(d)
    if struct.unpack(">H", d[16:18])[0] != 1:
        raise ValueError("%s is not ET_REL" % path)
    hits = []
    for st in (x for x in sh if x[1] == 2):          # SHT_SYMTAB
        ss = sh[st[6]]
        for j in range(st[5] // 16):
            no, val, sz, info, oth, shn = struct.unpack(">IIIBBH", d[st[4] + j * 16: st[4] + j * 16 + 16])
            if cstr(d, ss[4] + no) == b"buildid":
                hits.append(cstr(d, sh[shn][4] + val))
    if len(hits) != 1:
        raise ValueError("%s: %d buildid symbols, want 1" % (path, len(hits)))
    return hits[0]


def sidecar_build(path):
    v = [l[6:] for l in open(path, "rb").read().split(b"\n") if l.startswith(b"build=")]
    if len(v) != 1:
        raise ValueError("%s: %d build= lines, want 1" % (path, len(v)))
    return v[0]


def module_build(path):
    d = open(path, "rb").read()
    sh, si = elf(d)
    s = [x for x in sh if cstr(d, sh[si][4] + x[0]) == b".moddata"]
    if len(s) != 1:
        raise ValueError("%s: %d .moddata sections, want 1" % (path, len(s)))
    body = d[s[0][4] + 8: s[0][4] + s[0][5]]
    v = [k[6:] for k in body.split(b"\0") if k.startswith(b"build=")]
    if len(v) != 1:
        raise ValueError("%s: %d build= keys in .moddata, want 1" % (path, len(v)))
    return v[0]


def main(argv):
    if len(argv) < 4:
        sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
        return 2
    try:
        raw = image_buildid(argv[1])
        side = sidecar_build(argv[2])
        mods = [(m, module_build(m)) for m in argv[3:]]
    except (OSError, ValueError, IndexError, struct.error) as e:
        print("kbuildid: FAIL: %s" % e)
        return 2
    core = raw
    while core[:1] == b" ":
        core = core[1:]
    print("kbuildid: image buildid %r (%d bytes) -> the core's %r" % (raw, len(raw), core))
    print("kbuildid: sidecar build= %r" % side)
    for m, b in mods:
        print("kbuildid: %s .moddata build= %r" % (m, b))
    bad = [m for m, b in mods if b != core]
    if core and core == side and not bad:
        print("kbuildid: EQUAL: image (stripped) == sidecar build= == %d module(s) build=, byte for byte" % len(mods))
        return 0
    why = []
    if not core:
        why.append("the stripped image buildid is empty")
    if core != side:
        why.append("the sidecar's build= is not the image's")
    if bad:
        why.append("the core refuses %s (EBADVER)" % ", ".join(bad))
    print("kbuildid: MISMATCH: " + "; ".join(why))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
