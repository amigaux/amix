#!/usr/bin/env python3
"""kmemwake030.py -- every kmem give-back wakes the oversize sleepers (the linked 68030 kernel).

  kmemwake030.py UNIX           patch the linked ET_REL kernel in place (idempotent)
  kmemwake030.py --check UNIX   verify, write nothing; exit 1 unless both sites are patched
  kmemwake030.py --stock UNIX   verify, write nothing; exit 1 unless both sites are stock

A kmem_alloc over 4 KiB that finds no run in the kernel map sleeps on Km_OsizeWanted, which holds the smallest size
asked for, in bytes.  Stock wakes it from two places, each only if the one block just freed is at least that size:

  kmem_freepool  compares the clicks of the pool it retired (8 or 2) with those bytes: never true, every oversize
                 request being over 4096, so a retirement wakes nobody;
  kmem_free      compares the bytes of a direct free: true only if that one free alone is large enough.

So a sleeper whose run appears when a free joins the room beside it sleeps on.  And kmem_alloc sets Km_OsizeWanted
before it calls sleep, with no spl held: an interrupt-level free between the two clears it and wakes nobody, and from
then on the test of the variable skips every wake.  Both sites are the same sequence, and both branches become nops:

  tstl Km_OsizeWanted; ble.w out; cmpl Km_OsizeWanted,%dn; bcs.w out; clrl Km_OsizeWanted; ...
    ->  tstl Km_OsizeWanted; nop; nop; cmpl Km_OsizeWanted,%dn; nop; nop; clrl Km_OsizeWanted; ...

Every retirement and every direct free over 4 KiB wakes the channel; each sleeper retries in kmem_alloc and sleeps
again if its run is still not there.  A wake with nobody asleep costs a walk of an empty sleep queue.  Frees that do
not go through kmem (bp_mapout, unkseg) still wake nobody.  Both sites are found by function, instruction pattern and
relocations against Km_OsizeWanted, and must match exactly once.
"""
import struct
import sys

SHT_SYMTAB, SHT_RELA = 2, 4
SITES = (('kmem_freepool', 0xb4b9), ('kmem_free', 0xb8b9))    # cmpl <abs32>,%d2 and ...,%d4
NOPS = bytes.fromhex('4e714e71')


def die(msg):
    sys.exit('kmemwake030: ' + msg)


def load(path):
    b = bytearray(open(path, 'rb').read())
    if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or struct.unpack_from('>H', b, 16)[0] != 1:
        die('%s is not an ELF32 big-endian ET_REL' % path)
    shoff, = struct.unpack_from('>I', b, 32)
    shentsize, shnum, shstrndx = struct.unpack_from('>HHH', b, 46)
    sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
    names = sh[shstrndx][4]
    secname = [bytes(b[names + s[0]:b.index(0, names + s[0])]).decode() for s in sh]
    return b, sh, secname


def site(b, sh, secname, fn, cmp_op):
    """(file offset of the sequence's first address word, whether it is still stock) of fn's one sequence"""
    text = secname.index('.text')
    st = [s for s in sh if s[1] == SHT_SYMTAB]
    if len(st) != 1:
        die('%d symbol tables' % len(st))
    strs = sh[st[0][6]][4]
    syms = []
    for i in range(st[0][5] // 16):
        name, value, size, info, other, shndx = struct.unpack_from('>IIIBBH', b, st[0][4] + 16 * i)
        syms.append((bytes(b[strs + name:b.index(0, strs + name)]).decode(), value, size, info, shndx))
    hits = [s for s in syms if s[0] == fn and s[4] == text and s[3] & 15 == 2]
    if len(hits) != 1:
        die('%d functions named %s' % (len(hits), fn))
    lo, hi = hits[0][1], hits[0][1] + hits[0][2]
    want = [i for i, s in enumerate(syms) if s[0] == 'Km_OsizeWanted']
    rel = [s for s in sh if s[1] == SHT_RELA and s[7] == text]
    if len(want) != 1 or len(rel) != 1:
        die('Km_OsizeWanted %d times, %d .rela.text' % (len(want), len(rel)))
    off = {}
    for o in range(rel[0][4], rel[0][4] + rel[0][5], 12):
        r, info, add = struct.unpack_from('>IIi', b, o)
        if info >> 8 == want[0] and lo <= r < hi:
            off[r] = add
    base = sh[text][4]
    found = []
    for r in sorted(off):
        # tstl <abs32> (4ab9) at r - 2; ble.w (6f00) at r + 4; cmpl <abs32>,%dn at r + 8; bcs.w (6500) at r + 14;
        # clrl <abs32> (42b9) at r + 18
        p = base + r
        if (struct.unpack_from('>H', b, p - 2)[0] == 0x4ab9 and struct.unpack_from('>H', b, p + 8)[0] == cmp_op
                and struct.unpack_from('>H', b, p + 18)[0] == 0x42b9
                and r + 10 in off and r + 20 in off and off[r] == off[r + 10] == off[r + 20] == 0):
            found.append(p)
    if len(found) != 1:
        die('%s: %d tstl/ble/cmpl/bcs/clrl sequences on Km_OsizeWanted (want 1)' % (fn, len(found)))
    p = found[0]
    ble, bcs = bytes(b[p + 4:p + 8]), bytes(b[p + 14:p + 18])
    if ble == NOPS and bcs == NOPS:
        return p, False
    if ble[:2] == b'\x6f\x00' and bcs[:2] == b'\x65\x00':
        return p, True
    die('%s: %s and %s where the ble.w and bcs.w should be' % (fn, ble.hex(), bcs.hex()))


def main():
    mode = sys.argv[1] if sys.argv[1:2] in (['--check'], ['--stock']) else None
    path = sys.argv[2] if mode and len(sys.argv) == 3 else (sys.argv[1] if not mode and len(sys.argv) == 2 else None)
    if not path:
        sys.exit(__doc__)
    b, sh, secname = load(path)
    st = {fn: site(b, sh, secname, fn, op) for fn, op in SITES}
    desc = ' '.join('%s=%s' % (fn, 'stock' if st[fn][1] else 'nops') for fn in sorted(st))
    if mode:
        ok = all(s[1] == (mode == '--stock') for s in st.values())
        print('kmemwake030: %s -- %s' % (desc, 'OK' if ok else 'NOT ' + mode[2:]))
        sys.exit(0 if ok else 1)
    todo = [s[0] for s in st.values() if s[1]]
    if not todo:
        print('kmemwake030: already patched')
        return
    if len(todo) != len(SITES):
        die('a kernel half way: %s' % desc)
    for at in todo:
        b[at + 4:at + 8] = NOPS
        b[at + 14:at + 18] = NOPS
    with open(path, 'wb') as f:
        f.write(b)
    print('kmemwake030: %d sites: the ble and the bcs around each compare with Km_OsizeWanted -> nops' % len(todo))


if __name__ == '__main__':
    main()
