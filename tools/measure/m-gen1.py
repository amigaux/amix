#!/usr/bin/env python3
# m-gen1.py -- M-GEN1: the size of a stage-2 generation per kernel family
# (a static kernel and its manifest), raw and deflated, and what it means
# for the boot store: how many generations a 64 MiB store (the 1.1 layout)
# and the 1.0 layout's 10 MiB boot slice hold.  Host-side, read-only.
# See docs/measurements/2026-10-26-m-gen1-m-gen4.md.
#
# usage: m-gen1.py <workspace>
#   <workspace>  the Amix project workspace (holds amix-kerntools/)
import os, subprocess, sys, tempfile, zlib

WS = sys.argv[1]
K = os.path.join(WS, 'amix-kerntools/work/k0-chains')
ELF2BREL = os.path.join(WS, 'amix-kerntools/tools/elf2brel.py')
FAMILIES = ['K030-U', 'K030-IDE', 'K030-A4091-IDE', 'K030-U-FD',
            'KD040-A', 'KD060-A', 'KD060-FD', 'KD060-Z', 'KD060-ZA', 'K060']
BLK = 2048
MAN = 2048          # a stage-2 manifest is under 2 KiB (one extent)
DATA = 0x10000      # the store's data area starts here
KEPT = 4            # pristine + two good + one trial (40 §1)


def deflate(raw):   # as mkstore: the smaller of zlib memory levels 8 and 9
    best = None
    for ml in (8, 9):
        c = zlib.compressobj(9, zlib.DEFLATED, -15, ml)
        z = c.compress(raw) + c.flush()
        best = z if best is None or len(z) < len(best) else best
    return len(best)


def extent(n):
    return (n + BLK - 1) // BLK * BLK


def kernel(fam):
    d = os.path.join(K, fam)
    for f in sorted(os.listdir(d)):
        if f.startswith(fam + '-c') or f.startswith(fam + '-fd'):
            if not f.endswith(('.map', '.nm', '.etrel')):
                return os.path.join(d, f)
    return None


print('| Family | Form | Raw | Deflated | Generation in a disk store (raw) | In 64 MiB | In 10 MiB |')
print('|---|---|---|---|---|---|---|')
for fam in FAMILIES:
    path = kernel(fam)
    if not path:
        continue
    raw = open(path, 'rb').read()
    forms = []
    if raw[16:18] == b'\x00\x01':                 # ET_REL: also its brel form
        forms.append(('ET_REL', raw))
        with tempfile.TemporaryDirectory() as t:
            out = os.path.join(t, 'k.brel')
            subprocess.run([sys.executable, '-I', ELF2BREL, path, out], check=True,
                           stdout=subprocess.DEVNULL)
            forms.append(('brel', open(out, 'rb').read()))
    else:
        forms.append(('brel', raw))
    for name, data in forms:
        gen = extent(len(data)) + MAN
        print('| %s | %s | %d | %d | %d | %d | %d |' % (
            fam, name, len(data), deflate(data), gen,
            (64 * 2**20 - DATA) // gen, (10 * 2**20 - DATA) // gen))
