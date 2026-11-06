#!/usr/bin/env python3
"""segvnprot-retarget.py -- route segvn_fault's call of segvn_faultpage through src/segvnprot030.s, and the calls of
core_seg to src/coreseg030.c.

  segvnprot-retarget.py UNIX           patch the linked ET_REL kernel in place (idempotent)
  segvnprot-retarget.py --check UNIX   verify, write nothing; exit 1 if the kernel is not retargeted

Only .rela entries change, each its symbol index: segvn_fault's call now names segvn_faultpage_prot, the initializer of
segvn_prot_stock now names segvn_faultpage (a call within the assembly file would be pc-relative, with no relocation to
retarget; a pointer's initializer always has one), and the calls of core_seg in coffcore and elfcore now name
core_seg_holes.  The wrapper reads the stock function's arguments and struct fields by offset, so the stock function's first instructions must be the
ones it was read from: its frame, its argument loads and its test of svd->pageprot.
"""
import struct
import sys

SHT_SYMTAB, SHT_RELA = 2, 4


def die(msg):
    sys.exit('segvnprot-retarget: ' + msg)


def main():
    check = sys.argv[1:2] == ['--check']
    path = sys.argv[2] if check and len(sys.argv) == 3 else (sys.argv[1] if len(sys.argv) == 2 else None)
    if not path:
        sys.exit(__doc__)
    b = bytearray(open(path, 'rb').read())
    if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or struct.unpack_from('>H', b, 16)[0] != 1:
        die('%s is not an ELF32 big-endian ET_REL' % path)
    shoff, = struct.unpack_from('>I', b, 32)
    es, n = struct.unpack_from('>HH', b, 46)
    sh = [struct.unpack_from('>10I', b, shoff + i * es) for i in range(n)]
    st = [s for s in sh if s[1] == SHT_SYMTAB]
    if len(st) != 1:
        die('%d symbol tables' % len(st))
    strs = sh[st[0][6]][4]
    syms = []
    for i in range(st[0][5] // 16):
        nm, v, z, info, o, x = struct.unpack_from('>IIIBBH', b, st[0][4] + 16 * i)
        syms.append((bytes(b[strs + nm:b.index(0, strs + nm)]).decode(), v, z, x))

    def index(name):
        hits = [i for i, s in enumerate(syms) if s[0] == name and s[3] != 0]
        if len(hits) != 1:
            die('%d defined symbols named %s' % (len(hits), name))
        return hits[0]
    ix = {k: index(k) for k in ('segvn_faultpage', 'segvn_faultpage_prot', 'segvn_prot_stock', 'segvn_fault', 'core_seg', 'core_seg_holes', 'coffcore', 'elfcore')}
    stock, prot = ix['segvn_faultpage'], ix['segvn_faultpage_prot']
    fl, fz, fsec = syms[ix['segvn_fault']][1], syms[ix['segvn_fault']][2], syms[ix['segvn_fault']][3]
    pv, psec = syms[ix['segvn_prot_stock']][1], syms[ix['segvn_prot_stock']][3]
    if not fz:
        die('segvn_fault has no size')
    # the stock body the wrapper was read from: frame, saves, arguments 1, 2, 3, 4, 5, 9, seg->s_data, svd->pageprot
    text = sh[fsec][4]
    want = bytes.fromhex('4e56fff848e73f3c262e0008282e000c206e00102a6e00142e2e00182c2e002822432869001c42854a2c0002')
    got = bytes(b[text + syms[stock][1]:text + syms[stock][1] + len(want)])
    if got != want:
        die('segvn_faultpage does not begin as the wrapper expects: %s' % got.hex())
    calls, init, others, core = [], [], [], []
    cs, ch = ix['core_seg'], ix['core_seg_holes']
    callers = [(syms[ix[k]][1], syms[ix[k]][2], k) for k in ('coffcore', 'elfcore')]
    if not all(c[1] for c in callers):
        die('coffcore or elfcore has no size')
    for s in sh:
        if s[1] != SHT_RELA:
            continue
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if info >> 8 not in (cs, ch):
                continue
            who = [c[2] for c in callers if s[7] == fsec and c[0] <= off < c[0] + c[1]]
            if not who or bytes(b[text + off - 2:text + off]) != b'\x4e\xb9':
                die('a reference to core_seg at %#x in section %d is not a call in coffcore or elfcore' % (off, s[7]))
            core.append((o, info >> 8))
    if len(core) != 3:
        die('%d calls of core_seg (want three)' % len(core))
    for s in sh:
        if s[1] != SHT_RELA:
            continue
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            t = info >> 8
            if t not in (stock, prot):
                continue
            if s[7] == fsec and fl <= off < fl + fz:
                calls.append((o, t))
            elif s[7] == psec and off == pv:
                init.append((o, t))
            else:
                others.append((s[7], off, t))
    if len(calls) != 1 or len(init) != 1:
        die('%d calls in segvn_fault, %d initializers of segvn_prot_stock (want one each)' % (len(calls), len(init)))
    if others:
        die('%d other references to segvn_faultpage: %s' % (len(others), others[:4]))
    tgts = {c[1] for c in core}
    done = calls[0][1] == prot and init[0][1] == stock and tgts == {ch}
    if check:
        print('segvnprot-retarget: segvn_fault calls %s; segvn_prot_stock holds %s; the core writers call %s -- %s'
              % (syms[calls[0][1]][0], syms[init[0][1]][0], ' '.join(sorted(syms[t][0] for t in tgts)), 'OK' if done else 'NOT RETARGETED'))
        sys.exit(0 if done else 1)
    if done:
        print('segvnprot-retarget: already retargeted')
        return
    if calls[0][1] != stock or init[0][1] != prot or tgts != {cs}:
        die('a kernel half way')
    for (o, t), new in [(calls[0], prot), (init[0], stock)] + [(c, ch) for c in core]:
        off, info, add = struct.unpack_from('>IIi', b, o)
        struct.pack_into('>IIi', b, o, off, (new << 8) | (info & 0xff), add)
    with open(path, 'wb') as f:
        f.write(b)
    print('segvnprot-retarget: 5 relocations: segvn_fault -> segvn_faultpage_prot; segvn_prot_stock -> segvn_faultpage; '
          'coffcore x2, elfcore -> core_seg_holes')


if __name__ == '__main__':
    main()
