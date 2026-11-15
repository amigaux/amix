#!/usr/bin/env python3
"""hardbus-retarget.py -- retarget usrxmemflt's call of hardbus to hardbus_z3 (src/hardbus030.c).

  hardbus-retarget.py UNIX           patch the linked ET_REL kernel in place (idempotent)
  hardbus-retarget.py --check UNIX   verify, write nothing; exit 1 if the kernel is not retargeted
  hardbus-retarget.py --selftest     the cases below on synthetic ELF images

The stock hardbus probes a user fault's physical address as a kernel virtual address, which is wrong from
0x40000000 up.  src/hardbus030.c defines hardbus_z3, which calls the stock hardbus below 0x40000000 and probes
through a one-page kernel mapping above.  Every .rela entry naming hardbus is found by symbol, never by a fixed
address, and only its symbol index changes: no byte of .text moves.  The stock kernel names hardbus once, from
usrxmemflt; after the patch the one entry left naming hardbus is hardbus_z3's own call.  The check wants exactly
that: hardbus named only from hardbus_z3, hardbus_z3 named from usrxmemflt and nowhere else, one entry each, and
the stock hardbus body (0x62 bytes, the same in 2.1c) unchanged.
"""
import hashlib, struct, sys

SHT_SYMTAB, SHT_RELA = 2, 4
STOCK = 'hardbus'
GUARD = 'hardbus_z3'
CALLER = 'usrxmemflt'
BODY_LEN = 0x62
BODY_SHA = '3ee5357cf6cc2c070324b1acf7e9d64c8997939966b26f6933431c52fd438b69'


def die(msg):
    raise SystemExit('hardbus-retarget: ' + msg)


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


def index_of(syms, name):
    hits = [i for i, s in enumerate(syms) if s[0] == name and s[2] != 0]
    if len(hits) != 1:
        die('%d defined symbols named %s' % (len(hits), name))
    return hits[0]


def callers(b, sh, syms, target):
    """(rela entry file offset, containing function) for every .rela entry against `target`."""
    out = []
    ti = [i for i, s in enumerate(syms) if s[0] == target]
    for s in sh:
        if s[1] != SHT_RELA:
            continue
        sec = s[7]                                   # sh_info: the section the relocations apply to
        funcs = sorted((v, n) for n, v, x, info in syms if x == sec and n and (info & 15) in (0, 1, 2))
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if info >> 8 in ti:
                fn = [n for v, n in funcs if v <= off]
                out.append((o, fn[-1] if fn else '?'))
    return out


def body_ok(b, sh, syms):
    name, value, shndx, info = syms[index_of(syms, STOCK)]
    o = sh[shndx][4] + value
    return hashlib.sha256(bytes(b[o:o + BODY_LEN])).hexdigest() == BODY_SHA


def run(b, check):
    """Patch b (a bytearray) in place, or check it.  Returns (ok, message, changed)."""
    sh, syms = load(b)
    guard = index_of(syms, GUARD)
    index_of(syms, STOCK)
    if not body_ok(b, sh, syms):
        return False, 'the %s body is not the stock 0x%x bytes' % (STOCK, BODY_LEN), False
    plain = sorted(fn for o, fn in callers(b, sh, syms, STOCK))
    done = sorted(fn for o, fn in callers(b, sh, syms, GUARD))
    if check:
        ok = plain == [GUARD] and done == [CALLER]
        return ok, '%s named from %s; %s from %s, stock body -- %s' % (
            GUARD, done or 'nowhere', STOCK, plain or 'nowhere', 'OK' if ok else 'NOT RETARGETED'), False
    todo = [(o, fn) for o, fn in callers(b, sh, syms, STOCK) if fn != GUARD]
    if not todo:
        return bool(done), 'already retargeted' if done else 'nothing names %s' % STOCK, False
    if [fn for o, fn in todo] != [CALLER]:
        return False, '%s is named from %s, want exactly one entry in %s' % (
            STOCK, ' '.join(fn for o, fn in todo), CALLER), False
    for o, fn in todo:
        off, info, add = struct.unpack_from('>IIi', b, o)
        struct.pack_into('>IIi', b, o, off, (guard << 8) | (info & 0xff), add)
    return True, '1 relocation %s -> %s, in %s' % (STOCK, GUARD, CALLER), True


def synth(names_funcs, relas, body=None):
    """A minimal ET_REL: .text of 0x200 bytes, function symbols at given offsets, one .rela.text whose entries name
    symbols by name.  names_funcs: [(name, value, defined)]."""
    text = bytearray(0x200)
    if body is not None:
        text[0x100:0x100 + BODY_LEN] = body
    strtab = bytearray(b'\0')
    syms = [(0, 0, 0, 0, 0, 0)]
    for name, value, defined in names_funcs:
        syms.append((len(strtab), value, 0, 0x12, 0, 1 if defined else 0))
        strtab += name.encode() + b'\0'
    symidx = {n: i + 1 for i, (n, v, d) in enumerate(names_funcs)}
    rela = b''.join(struct.pack('>IIi', off, (symidx[n] << 8) | 1, 0) for off, n in relas)
    symb = b''.join(struct.pack('>IIIBBH', *s) for s in syms)
    shstr = b'\0.text\0.rela.text\0.symtab\0.strtab\0.shstrtab\0'
    body_off = 0x34
    parts = [bytes(text), rela, symb, bytes(strtab), shstr]
    offs = []
    o = body_off
    for p in parts:
        offs.append(o)
        o += len(p)
    shoff = (o + 3) & ~3
    sh = [(0,) * 10,
          (1, 1, 6, 0, offs[0], len(text), 0, 0, 4, 0),
          (7, SHT_RELA, 0, 0, offs[1], len(rela), 3, 1, 4, 12),
          (18, SHT_SYMTAB, 0, 0, offs[2], len(symb), 4, 1, 4, 16),
          (26, 3, 0, 0, offs[3], len(strtab), 0, 0, 1, 0),
          (34, 3, 0, 0, offs[4], len(shstr), 0, 0, 1, 0)]
    hdr = bytearray(0x34)
    hdr[:6] = b'\x7fELF\x01\x02'
    hdr[6] = 1
    struct.pack_into('>HHIIIIIHHHHHH', hdr, 16, 1, 4, 1, 0, 0, shoff, 0, 0x34, 0, 0, 40, len(sh), 5)
    img = bytearray(hdr) + b''.join(parts)
    img += bytes(shoff - len(img))
    img += b''.join(struct.pack('>IIIIIIIIII', *s) for s in sh)
    return img


def selftest():
    body = bytes.fromhex('4e56fff8206e000c20100240f800222e00080281000007ff2240d3c12d49fffc4878ffff2f2efffc4eb9'
                         '000000002000504f4a80670000202f2efffc2f2e0008487900000000487800024eb900000000700960000008'
                         '42806000000220404e5e4e75')
    assert hashlib.sha256(body).hexdigest() == BODY_SHA
    funcs = [('usrxmemflt', 0x10, True), ('hardbus', 0x100, True), ('hardbus_z3', 0x180, True), ('k_trap', 0x1c0, True)]
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

    stock = synth(funcs, [(0x20, 'hardbus'), (0x190, 'hardbus')], body)
    case('stock kernel fails the check', bytearray(stock), True, False)
    img = bytearray(stock)
    case('patch retargets the one call', img, False, True, True)
    case('patched kernel passes the check', img, True, True)
    case('a second run changes nothing', img, False, True, False)
    case('two stock callers are refused', bytearray(synth(funcs, [(0x20, 'hardbus'), (0x1c4, 'hardbus'), (0x190, 'hardbus')], body)),
         False, False)
    bad = bytearray(body)
    bad[0x30] ^= 1
    case('a changed hardbus body is refused', bytearray(synth(funcs, [(0x20, 'hardbus'), (0x190, 'hardbus')], bytes(bad))),
         False, False)
    case('no hardbus_z3 is refused', bytearray(synth(funcs[:2] + funcs[3:], [(0x20, 'hardbus')], body)), False, False)
    print('hardbus-retarget selftest: %s' % ('PASS' if not fails else '%d FAIL' % fails))
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
    print('hardbus-retarget: ' + msg)
    if changed:
        open(path, 'wb').write(b)
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
