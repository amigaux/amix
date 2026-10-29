#!/usr/bin/env python3
# m-mod1.py -- M-MOD1: the size of every root-class module per line, from
# today's static driver and filesystem objects, and the arena capacity that
# follows: 2 x the line's root set, rounded up to 64 KiB (10 §5.3, P-28
# D57).  A module's size is its allocated sections (PROGBITS and NOBITS)
# plus its COMMON symbols, each at its alignment.  Host-side, read-only.
# See docs/measurements/2026-10-26-m-reg1-m-abi1.md.
#
# usage: m-mod1.py <workspace>
import os, struct, sys

WS = sys.argv[1]
KT = 'amix-kerntools/work/cross-kernel-k030u-c6s1/usr/sys'
KT4 = 'amix-kerntools/work/cross-kernel-c6s1-r4-rebuild/usr/sys'
PB = 'amix-040-060-port/build'
CDFS = 'amix-cdfs/build/amix-kernel/libcdfskern.o'
# module: (k30 objects, k46 objects, note)
SET = [
    ('z3660scsi', [KT4 + '/amiga/alien/z3660.o'],
     [PB + '/z3660_040.o', PB + '/z3660_glue040.o', PB + '/z3660_cache_arm.o'], ''),
    ('a4091', [KT + '/amiga/alien/a4091.o', KT + '/amiga/alien/a3091.o'],
     [PB + '/a4091_040.o', PB + '/a4091_scsicard.o', PB + '/a3091q040.o',
      PB + '/a3091demux040.o'], ''),
    ('gayle-ide', [KT + '/amiga/alien/ide.o'],
     [PB + '/ide_040.o', PB + '/ide_scsicard.o', PB + '/ide_sd_glue040.o'], ''),
    ('a4000t-710', [KT + '/amiga/alien/a4091.o', KT + '/amiga/alien/a3091.o'],
     [PB + '/a4091_040.o', PB + '/a4091_scsicard.o', PB + '/a3091q040.o'],
     'no driver yet: the A4091 (same 53C710) stands in'),
    ('ufs', [KT + '/fs/ufs/exp'], [KT + '/fs/ufs/exp'],
     'k46: no separate object until M-FS1; the k30 object stands in'),
    ('s5', [KT + '/fs/s5/exp'], [KT + '/fs/s5/exp'], 'as ufs'),
    ('cdfs', [CDFS], [CDFS, PB + '/cdfs_glue040.o'], ''),
    ('ramdisk', [KT + '/amiga/driver/ram.o'], [KT + '/amiga/driver/ram.o'],
     'not written yet: the stock ram driver stands in'),
]
DIRECTORY = 32 + 48 * len(SET) + 2048    # AXA1 + entries + a manifest (C3-4)


def size(path):
    b = open(os.path.join(WS, path), 'rb').read()
    shoff, = struct.unpack('>I', b[32:36])
    shnum, = struct.unpack('>H', b[48:50])
    total = 0
    for i in range(shnum):
        n, t, f, a, off, sz, ln, inf, al, es = struct.unpack('>10I', b[shoff + 40 * i:shoff + 40 * i + 40])
        if f & 2 and t in (1, 8):           # SHF_ALLOC, PROGBITS or NOBITS
            total += sz
        if t == 2:
            for k in range(sz // 16):
                o = off + 16 * k
                nm, val, ssz, info, oth, shn = struct.unpack('>IIIBBH', b[o:o + 16])
                if shn == 0xfff2:           # COMMON: value is the alignment
                    total = (total + val - 1) // max(val, 1) * max(val, 1) + ssz
    return total


def up16(n):
    return (n + 15) & ~15


tot = {'k30': 0, 'k46': 0}
print('%-11s %9s %9s  %s' % ('module', 'k30', 'k46', 'note'))
for name, o30, o46, note in SET:
    s30 = sum(size(p) for p in o30)
    s46 = sum(size(p) for p in o46)
    tot['k30'] += up16(s30)
    tot['k46'] += up16(s46)
    print('%-11s %9d %9d  %s' % (name, s30, s46, note))
for line in ('k30', 'k46'):
    t = tot[line] + DIRECTORY
    cap = (2 * t + 0xffff) & ~0xffff
    print('%s: root set %d bytes with the directory and a 2 KiB manifest; '
          'arena capacity 2 x set rounded to 64 KiB = %d (0x%x)' % (line, t, cap, cap))
