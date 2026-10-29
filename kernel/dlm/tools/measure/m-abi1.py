#!/usr/bin/env python3
# m-abi1.py -- M-ABI1: do the 68040 and 68060 kernels of the k46 family
# export the same ABI?  Compares the defined global symbols (name, kind,
# size of data objects) of pairs of kernels built from the same base, and
# lists which DDI v1 names (docs/contracts/C3-2-symbols-and-ddi.md §3) each
# kernel of record defines today.  Host-side, read-only.
# See docs/measurements/2026-10-26-m-reg1-m-abi1.md.
#
# usage: m-abi1.py <workspace>
import os, struct, sys

WS = sys.argv[1]
K = os.path.join(WS, 'amix-kerntools/work/k0-chains')
PAIRS = [('KD040-A/KD040-A-c0-u6', 'KD060-A/KD060-A-c0-u6')]
KERNELS = ['K030-U/K030-U-c0-u6.etrel', 'K030-IDE/K030-IDE-c0-u6.etrel',
           'KD040-A/KD040-A-c0-u6', 'KD060-A/KD060-A-c0-u6',
           'KD060-Z/KD060-Z-c0-u6', 'K060/K060-c0-u6']
DDI = '''printf cmn_err panic panicstr kmem_alloc kmem_zalloc kmem_free
sptalloc sptfree dma_alloc dma_free vtop dma_prepare dma_complete dev_kvmap
dev_kvunmap bcopy bzero bcmp memcpy strlen strcmp strncmp copyin copyout
uiomove sleep wakeup timeout untimeout lbolt suser drv_priv getmajor getminor
makedevice autocon bprobe spl0 spl1 spl2 spl3 spl4 spl5 spl6 spl7 splx
intr_attach intr_detach allocb freemsg freeb dupmsg copymsg linkb unlinkb
msgdsize putq getq putbq putnext qreply canput flushq OTHERQ RD WR if_attach
if_detach cons_hook_set cons_hook_clear __udivdi3 __umoddi3 __lshrdi3
bootinfo cputype'''.split()
K46_ONLY = {'dma_prepare', 'dma_complete', 'dev_kvmap', 'dev_kvunmap'}


def globals_of(path):
    b = open(path, 'rb').read()
    shoff, = struct.unpack('>I', b[32:36])
    shnum, = struct.unpack('>H', b[48:50])
    sh = [struct.unpack('>10I', b[shoff + 40 * i:shoff + 40 * i + 40]) for i in range(shnum)]
    out = {}
    for s in sh:
        if s[1] != 2:
            continue
        st = sh[s[6]][4]
        for k in range(s[5] // 16):
            o = s[4] + 16 * k
            nm, val, sz, info, oth, shn = struct.unpack('>IIIBBH', b[o:o + 16])
            bind, typ = info >> 4, info & 15
            if bind == 0 or shn == 0:      # locals and undefined
                continue
            name = b[st + nm:b.index(b'\0', st + nm)].decode('latin-1')
            kind = 'func' if typ == 2 else 'data' if typ == 1 else 'other'
            out[name] = (kind, sz if kind == 'data' else 0, shn == 0xfff2)
    return out


for a, c in PAIRS:
    ga, gc = globals_of(os.path.join(K, a)), globals_of(os.path.join(K, c))
    only_a = sorted(set(ga) - set(gc))
    only_c = sorted(set(gc) - set(ga))
    size = sorted(n for n in set(ga) & set(gc) if ga[n][:2] != gc[n][:2])
    print('== %s vs %s: %d and %d defined globals' % (a, c, len(ga), len(gc)))
    print('only in the first (%d): %s' % (len(only_a), ' '.join(only_a)))
    print('only in the second (%d): %s' % (len(only_c), ' '.join(only_c)))
    print('kind or data size differs (%d): %s' % (len(size), ' '.join(
        '%s %s/%s' % (n, ga[n][:2], gc[n][:2]) for n in size)))

print('== DDI v1 names defined in each kernel of record')
tab = {}
for k in KERNELS:
    tab[k] = globals_of(os.path.join(K, k))
for n in DDI:
    have = ['+' if n in tab[k] else ('.' if n in K46_ONLY and k.startswith('K030') else '-')
            for k in KERNELS]
    print('%-16s %s' % (n, ' '.join(have)))
print('columns: ' + ' '.join(k.split('/')[0] for k in KERNELS) +
      '  (+ defined, - missing, . not asked of this line)')
