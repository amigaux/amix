#!/usr/bin/env python3
"""btwalk030.py -- hook the port's backtrace frame test (btwalk.s, bt_frame_ok) into k30's panic backtrace.

  btwalk030.py UNIX           patch the linked ET_REL kernel in place (idempotent; re-run after every ld -r)
  btwalk030.py --check UNIX   verify, write nothing; exit 1 if the kernel is not patched as below
  btwalk030.py --selftest     the cases below on synthetic ELF images

The stock backtrace (0x208 bytes, the same in 2.1c) accepts a frame pointer only inside [0x40000000, 0x4000FFFF]
and then reads the frame's return address and the call instruction at [ret-6, ret).  The outermost frame's return
slot was never written: it reads 0, and the walk reads 0xFFFFFFFA..0xFFFFFFFF, which on a real 68030 bus is a bus
error inside the panic printer, so a panic becomes a second one.  The port's btwalk.s (taken byte for byte) is a
frame test that also bounds the return address to the kernel's text, orders the frames and caps the walk.

The 26 bytes of the stock test at backtrace+0x6a,

    0cae 3fff ffff fffc   cmpil #0x3FFFFFFF,%fp@(-4)
    6300 0010             blsw  (the tstl below)
    0cae 4000 ffff fffc   cmpil #0x4000FFFF,%fp@(-4)
    6200 0004             bhiw  (the tstl below)
    7001                  moveq #1,%d0

become `bsr.l bt_frame_ok` and ten NOPs; the `tstl %d0 / beqw` after them is kept, so bt_frame_ok's contract is
the old test's: d0 = 1 continue, d0 = 0 stop.  No branch in the stock body targets the inside of those bytes (the
two inside it target the tstl), and none of them is relocated.  bsr.l is PC-relative: the displacement depends on
where the link put bt_frame_ok, so the patch is redone after every ld -r, and the check recomputes it.  Every
other byte of the body is checked against the stock bytes.
"""
import hashlib, struct, sys

SHT_SYMTAB, SHT_RELA = 2, 4
FUNC = 'backtrace'
ISLAND = 'bt_frame_ok'
BODY_LEN = 0x208
BODY_SHA = 'e6fe69ac3f9977ab207186c8cf8061233d86851627721ba71d0c6b2a325f3100'
SITE = 0x6a
OLD = bytes.fromhex('0cae3ffffffffffc630000100cae4000fffffffc620000047001')
NOP = b'\x4e\x71'


def die(msg):
    raise SystemExit('btwalk030: ' + msg)


def load(b):
    if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or struct.unpack_from('>H', b, 16)[0] != 1:
        die('not an ELF32 big-endian ET_REL')
    shoff, = struct.unpack_from('>I', b, 32)
    shentsize, shnum = struct.unpack_from('>HH', b, 46)
    sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
    symtab = [s for s in sh if s[1] == SHT_SYMTAB]
    if len(symtab) != 1:
        die('%d symbol tables' % len(symtab))
    st = symtab[0]
    stroff = sh[st[6]][4]
    syms = []
    for i in range(st[5] // 16):
        name, value, size, info, other, shndx = struct.unpack_from('>IIIBBH', b, st[4] + 16 * i)
        syms.append((bytes(b[stroff + name:b.index(0, stroff + name)]).decode(), value, shndx, info))
    return sh, syms


def sym(syms, name):
    hits = [s for s in syms if s[0] == name and s[2] != 0]
    if len(hits) != 1:
        die('%d defined symbols named %s' % (len(hits), name))
    return hits[0]


def new_bytes(site_va, island_va):
    return b'\x61\xff' + struct.pack('>i', island_va - (site_va + 2)) + NOP * 10


def relocated(b, sh, shndx, lo, hi):
    """True when a .rela entry for section shndx patches a byte in [lo, hi)."""
    for s in sh:
        if s[1] == SHT_RELA and s[7] == shndx:
            for o in range(s[4], s[4] + s[5], 12):
                off, = struct.unpack_from('>I', b, o)
                if lo - 3 <= off < hi:
                    return True
    return False


def run(b, check):
    sh, syms = load(b)
    name, fva, fsec, info = sym(syms, FUNC)
    iname, iva, isec, iinfo = sym(syms, ISLAND)
    if isec != fsec:
        return False, '%s is not in the section of %s' % (ISLAND, FUNC), False
    fo = sh[fsec][4] + fva
    body = bytes(b[fo:fo + BODY_LEN])
    want = new_bytes(fva + SITE, iva)
    stock = hashlib.sha256(body).hexdigest() == BODY_SHA
    patched = body[SITE:SITE + len(OLD)] == want and \
        hashlib.sha256(body[:SITE] + OLD + body[SITE + len(OLD):]).hexdigest() == BODY_SHA
    if relocated(b, sh, fsec, fva + SITE, fva + SITE + len(OLD)):
        return False, 'a relocation patches the test bytes', False
    if check:
        return patched, '%s+0x%x: bsr.l %s @0x%x, rest of the body stock -- %s' % (
            FUNC, SITE, ISLAND, iva, 'OK' if patched else 'NOT PATCHED'), False
    if patched:
        return True, 'already patched (bsr.l %s @0x%x)' % (ISLAND, iva), False
    old_hook = body[SITE:SITE + 2] == b'\x61\xff' and body[SITE + 6:SITE + len(OLD)] == NOP * 10 and \
        hashlib.sha256(body[:SITE] + OLD + body[SITE + len(OLD):]).hexdigest() == BODY_SHA
    if not stock and not old_hook:
        return False, 'the %s body is neither the stock 0x%x bytes nor this hook' % (FUNC, BODY_LEN), False
    b[fo + SITE:fo + SITE + len(OLD)] = want
    return True, '%s+0x%x: the stock frame test -> bsr.l %s @0x%x (%s)' % (
        FUNC, SITE, ISLAND, iva, 'was stock' if stock else 'displacement redone'), True


def synth(body, island_va, island_sec=1, rela_off=None):
    text = bytearray(0x400)
    text[0x40:0x40 + BODY_LEN] = body
    strtab = bytearray(b'\0')
    syms = [(0, 0, 0, 0, 0, 0)]
    for n, v, sec in ((FUNC, 0x40, 1), (ISLAND, island_va, island_sec)):
        syms.append((len(strtab), v, 0, 0x12, 0, sec))
        strtab += n.encode() + b'\0'
    rela = struct.pack('>IIi', rela_off, (1 << 8) | 1, 0) if rela_off is not None else b''
    symb = b''.join(struct.pack('>IIIBBH', *s) for s in syms)
    shstr = b'\0.text\0.rela.text\0.symtab\0.strtab\0.shstrtab\0.data\0'
    parts = [bytes(text), rela, symb, bytes(strtab), shstr, bytes(16)]
    offs, o = [], 0x34
    for p in parts:
        offs.append(o)
        o += len(p)
    shoff = (o + 3) & ~3
    sh = [(0,) * 10,
          (1, 1, 6, 0, offs[0], len(text), 0, 0, 4, 0),
          (7, SHT_RELA, 0, 0, offs[1], len(rela), 3, 1, 4, 12),
          (18, SHT_SYMTAB, 0, 0, offs[2], len(symb), 4, 1, 4, 16),
          (26, 3, 0, 0, offs[3], len(strtab), 0, 0, 1, 0),
          (34, 3, 0, 0, offs[4], len(shstr), 0, 0, 1, 0),
          (44, 1, 3, 0, offs[5], 16, 0, 0, 4, 0)]
    hdr = bytearray(0x34)
    hdr[:7] = b'\x7fELF\x01\x02\x01'
    struct.pack_into('>HHIIIIIHHHHHH', hdr, 16, 1, 4, 1, 0, 0, shoff, 0, 0x34, 0, 0, 40, len(sh), 5)
    img = bytearray(hdr) + b''.join(parts)
    img += bytes(shoff - len(img))
    img += b''.join(struct.pack('>IIIIIIIIII', *s) for s in sh)
    return img


def selftest():
    # a body with the stock hash is not reproducible here without the stock bytes, so the cases rebind the hash
    global BODY_SHA
    saved = BODY_SHA
    body = bytearray(range(256)) * 2 + bytearray(BODY_LEN - 512)
    body[SITE:SITE + len(OLD)] = OLD
    BODY_SHA = hashlib.sha256(bytes(body)).hexdigest()
    fails = 0

    def case(name, img, check, want_ok, want_changed=None):
        nonlocal fails
        try:
            ok, msg, changed = run(img, check)
        except SystemExit as e:
            ok, msg, changed = False, str(e), False
        good = ok == want_ok and (want_changed is None or changed == want_changed)
        print('  %s %s: %s' % ('PASS' if good else 'FAIL', name, msg))
        fails += not good
        return img

    try:
        case('stock kernel fails the check', synth(bytes(body), 0x300), True, False)
        img = case('patch writes bsr.l and NOPs', synth(bytes(body), 0x300), False, True, True)
        fo = 0x34 + 0x40
        assert img[fo + SITE:fo + SITE + 6] == b'\x61\xff' + struct.pack('>i', 0x300 - (0x40 + SITE + 2))
        case('patched kernel passes the check', img, True, True)
        case('a second run changes nothing', img, False, True, False)
        moved = bytearray(img)
        # the island moved by a relink: the old displacement no longer fits
        s = synth(bytes(moved[fo:fo + BODY_LEN]), 0x320)
        case('a moved island fails the check', bytearray(s), True, False)
        case('a moved island is redone', s, False, True, True)
        case('and then passes', s, True, True)
        bad = bytearray(body)
        bad[0x100] ^= 1
        case('a changed body is refused', synth(bytes(bad), 0x300), False, False)
        case('an island in another section is refused', synth(bytes(body), 0x8, island_sec=6), False, False)
        case('a relocation in the test bytes is refused', synth(bytes(body), 0x300, rela_off=0x40 + SITE + 4), False, False)
    finally:
        BODY_SHA = saved
    print('btwalk030 selftest: %s' % ('PASS' if not fails else '%d FAIL' % fails))
    return 0 if not fails else 1


def main():
    a = sys.argv[1:]
    if a == ['--selftest']:
        sys.exit(selftest())
    check = a[:1] == ['--check']
    path = a[1] if check and len(a) == 2 else (a[0] if len(a) == 1 and not check else None)
    if not path:
        sys.exit(__doc__)
    b = bytearray(open(path, 'rb').read())
    ok, msg, changed = run(b, check)
    print('btwalk030: ' + msg)
    if changed:
        open(path, 'wb').write(b)
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
