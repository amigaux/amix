#!/usr/bin/env python3
"""growsdt030.py -- hat_growsdt frees the tail of a shrunk segment table where the tail is.

  growsdt030.py UNIX           patch the linked kernel (ELF32 big-endian ET_REL) in place; refuses unless hat_growsdt
                               and hat_sdtfree are exactly the stock code, or hat_growsdt is already patched
  growsdt030.py --check UNIX   verify, write nothing; exit 1 unless patched
  growsdt030.py --selftest     patch a synthetic object: stock -> fixed, idempotent, an unknown hat_growsdt and
                               changed contexts refused

THE BUG.  The 030 hat keeps each address space's second-level (segment) tables in 64-byte units carved out of kernel
pages: hat_sdtalloc hands out runs of units, hat_sdtfree(addr, n) takes them back (the unit is (addr & 2047) >> 6, and
the page's p_sdtbits -- the word that is p_mapping on a data page -- loses the run's bits; a page left with none is
freed).  hat_growsdt(hat, l1index, nentries) resizes one table; when it shrinks it to fewer units (d6 new, d5 old) it
gives back the tail:

    movel %d6,%d0 ; asll #6,%d0 ; asll #3,%d0 ; addl %fp@(-4),%d0 ; ... jsr hat_sdtfree   (table + d6 * 512, d5 - d6)

The tail starts d6 * 64 bytes in (d6 units of 64 bytes, as hat_growsdt itself counts them: d6 = (nentries * 8 + 63)
>> 6, and its clearing loop stops at d6 * 8 entries).  The second shift frees 8 times too far: hat_sdtfree then clears
bits in whatever page that address falls in.  On a data page that is its mapping chain's head, which loses its low
bits (the chain walks of hat_unload and hat_swapout then never end); a page whose bits all go is freed while still
mapped; and the real tail is never given back.  hat_swapout shrinks tables to the last segment in use, so it happens
whenever processes are swapped out, which a 16 MiB machine does all the time.  There is no 68k hat source to compare
with; the unit is the one hat_sdtalloc and hat_sdtfree use (bit << 6 bytes, (addr & 2047) >> 6).

THE FIX.  The second shift (e780, asll #3,%d0) becomes a nop (4e71): hat_sdtfree(table + d6 * 64, d5 - d6).
"""
import hashlib, struct, sys

STOCK = bytes.fromhex('e780')
FIXED = bytes.fromhex('4e71')
SITE = 0xbe                                    # offset of the shift in hat_growsdt
# hat_growsdt+0xb4..+0xc6: movel d5,d0; subl d6,d0; movel d0,sp@-; movel d6,d0; asll #6,d0; [asll #3,d0];
# addl fp@(-4),d0; movel d0,sp@-; jsr <hat_sdtfree, relocated at +0xc8>
CONTEXT = (0xb4, bytes.fromhex('200590862f002006ed80'), 0xc0, bytes.fromhex('d0aefffc2f004eb9'))
# hat_growsdt+0x6e..+0x80: d5 = (old entries * 8 + 63) >> 6; d6 = (new entries * 8 + 63) >> 6 -- 64-byte units
UNITS = (0x6e, bytes.fromhex('2a03e785723fda81ec852c02e786723fdc81ec86'))
# hat_sdtfree: page offset of the address (andiw #-2048), the unit (lsrl #6) and the clearing and
SDTFREE = bytes.fromhex('0240f800262e00089680ec8b')
# the stock functions under func_digest (code with relocated fields and the site zeroed, then the relocations)
KNOWN = {'hat_growsdt': {'81ee995f5cb7570028fa4ba6c94deda7e0ffb7b5bb6dafa5e6f146cd1bfb4853'},
         'hat_sdtfree': {'1fb11ebbc17fd9ab99da50532bc771439973e73da17c59cdc031602d5fd5cf5a'}}   # 2.1 and 2.1c


def fail(msg):
    sys.exit('growsdt030: ' + msg)


def load(path):
    b = bytearray(open(path, 'rb').read())
    if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or struct.unpack_from('>H', b, 16)[0] != 1:
        fail('%s is not an ELF32 big-endian ET_REL' % path)
    shoff, = struct.unpack_from('>I', b, 32)
    shentsize, shnum = struct.unpack_from('>HH', b, 46)
    sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
    st = [s for s in sh if s[1] == 2]
    if len(st) != 1:
        fail('%d symbol tables' % len(st))
    st = st[0]
    stroff = sh[st[6]][4]
    syms = []
    for i in range(st[5] // 16):
        name, value, size, info, other, shndx = struct.unpack_from('>IIIBBH', b, st[4] + 16 * i)
        syms.append((bytes(b[stroff + name:b.index(0, stroff + name)]).decode(), value, shndx, info))
    return b, sh, syms


def func(b, sh, syms, name):
    """(file offset of the code, start, end, relocations [(off, type, symbol name or '', addend)])"""
    f = [s for s in syms if s[0] == name and s[2] not in (0, 0xfff1, 0xfff2)]
    if len(f) != 1:
        fail('%d definitions of %s' % (len(f), name))
    _, start, sec, _ = f[0]
    later = sorted(v for n, v, x, info in syms if x == sec and v > start and (info & 15) == 2)
    end = later[0] if later else sh[sec][5]
    rels = []
    for s in sh:
        if s[1] != 4 or s[7] != sec:
            continue
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if start <= off < end:
                n, v, x, i = syms[info >> 8]
                rels.append((off, info & 0xff, n if (i & 15) != 3 else '', add))
    return sh[sec][4], start, end, rels


def func_digest(b, text, start, end, rels, zero=()):
    c = bytearray(b[text + start:text + end])
    for off, typ, name, add in rels:
        c[off - start:off - start + 4] = bytes(4)
    for o, n in zero:
        c[o:o + n] = bytes(n)
    r = ''.join('%x:%d:%s:%s;' % (off - start, typ, name or '.', add if name else '.') for off, typ, name, add in sorted(rels))
    return hashlib.sha256(bytes(c) + r.encode()).hexdigest()


def site(b, sh, syms, known=KNOWN):
    text, start, end, rels = func(b, sh, syms, 'hat_growsdt')
    code = bytes(b[text + start:text + end])
    if end - start < SITE + 0x20:
        fail('hat_growsdt is too short to be the stock one')
    if code[CONTEXT[0]:CONTEXT[0] + len(CONTEXT[1])] != CONTEXT[1] or code[CONTEXT[2]:CONTEXT[2] + len(CONTEXT[3])] != CONTEXT[3]:
        fail('the instructions around the shrink path\'s hat_sdtfree call differ from stock')
    if code[UNITS[0]:UNITS[0] + len(UNITS[1])] != UNITS[1]:
        fail('hat_growsdt does not count its table in 64-byte units as stock does')
    call = [r for r in rels if r[0] - start == 0xc8]
    if len(call) != 1 or call[0][2] != 'hat_sdtfree' or call[0][1] != 1 or call[0][3]:
        fail('the call at hat_growsdt+0xc6 is not jsr hat_sdtfree')
    cur = code[SITE:SITE + 2]
    if cur not in (STOCK, FIXED):
        fail('the shift at hat_growsdt+0x%x is %s (stock %s, patched %s)' % (SITE, cur.hex(), STOCK.hex(), FIXED.hex()))
    ft, fs, fe, fr = func(b, sh, syms, 'hat_sdtfree')
    if bytes(b[ft + fs:ft + fe]).count(SDTFREE) != 1:
        fail('hat_sdtfree does not take its unit as (addr & 2047) >> 6 as stock does')
    if known is not None:
        g = func_digest(b, text, start, end, rels, ((SITE, 2),))
        f = func_digest(b, ft, fs, fe, fr)
        if g not in known['hat_growsdt']:
            fail('hat_growsdt is not the stock code (digest %s)' % g)
        if f not in known['hat_sdtfree']:
            fail('hat_sdtfree is not the stock code (digest %s)' % f)
    return text + start + SITE, cur == FIXED


def main(args=None, known=KNOWN):
    args = sys.argv[1:] if args is None else args
    if args == ['--selftest']:
        return selftest()
    check = args[:1] == ['--check']
    if check:
        args = args[1:]
    if len(args) != 1:
        sys.exit(__doc__)
    b, sh, syms = load(args[0])
    off, done = site(b, sh, syms, known)
    if check:
        if not done:
            fail('%s: hat_growsdt still frees a shrunk table\'s tail 8 times too far' % args[0])
        print('growsdt030: %s: hat_growsdt frees the tail at table + units * 64 (file offset 0x%x)' % (args[0], off))
        return
    if done:
        print('growsdt030: %s: already patched (file offset 0x%x)' % (args[0], off))
        return
    b[off:off + 2] = FIXED
    open(args[0], 'wb').write(b)
    print('growsdt030: %s: hat_growsdt+0x%x %s -> %s (asll #3 -> nop) at file offset 0x%x' % (args[0], SITE, STOCK.hex(),
                                                                                           FIXED.hex(), off))


def synth(path, gmut=None, fmut=None, relocs=None, glen=0xe0):
    """a minimal ET_REL: hat_growsdt (0xe0 bytes, the stock bytes at the checked offsets, the call relocated to
    hat_sdtfree) and hat_sdtfree (the unit sequence)"""
    g = bytearray(glen)
    g[0:4] = bytes.fromhex('4e56ffd0')
    g[UNITS[0]:UNITS[0] + len(UNITS[1])] = UNITS[1]
    g[CONTEXT[0]:CONTEXT[0] + len(CONTEXT[1])] = CONTEXT[1]
    g[SITE:SITE + 2] = STOCK
    g[CONTEXT[2]:CONTEXT[2] + len(CONTEXT[3])] = CONTEXT[3]
    g[glen - 4:glen] = bytes.fromhex('4e5e4e75')
    f = bytearray.fromhex('4e56fff8202e0008' + SDTFREE.hex() + '4e5e4e75')
    if gmut:
        gmut(g)
    if fmut:
        fmut(f)
    t = bytes(g) + bytes(f)
    names = ['hat_growsdt', 'hat_sdtfree']
    strtab = b'\0hat_growsdt\0hat_sdtfree\0'
    sym = bytes(16) + struct.pack('>IIIBBH', 1, 0, len(g), 0x12, 0, 1) + struct.pack('>IIIBBH', 13, len(g), len(f), 0x12, 0, 1)
    rela = b''.join(struct.pack('>IIi', o, (s << 8) | ty, a) for o, s, ty, a in (relocs or ((0xc8, 2, 1, 0),)))
    shstr = b'\0.text\0.rela.text\0.symtab\0.strtab\0.shstrtab\0'
    body = [t, rela, sym, strtab, shstr]
    pos, offs = 52, []
    for x in body:
        offs.append(pos)
        pos += (len(x) + 3) & ~3
    data = bytearray(struct.pack('>4sBBBB8xHHIIIIIHHHHHH', b'\x7fELF', 1, 2, 1, 0, 1, 4, 1, 0, 0, pos, 0, 52,
                                 0, 0, 40, 6, 5))
    for x in body:
        data += x + bytes(((len(x) + 3) & ~3) - len(x))
    sh = [(0, 0, 0, 0, 0, 0, 0, 0, 0, 0), (1, 1, 6, 0, offs[0], len(t), 0, 0, 2, 0), (7, 4, 0, 0, offs[1], len(rela), 3, 1, 4, 12),
          (18, 2, 0, 0, offs[2], len(sym), 4, 1, 4, 16), (26, 3, 0, 0, offs[3], len(strtab), 0, 0, 1, 0),
          (34, 3, 0, 0, offs[4], len(shstr), 0, 0, 1, 0)]
    for s in sh:
        data += struct.pack('>IIIIIIIIII', *s)
    open(path, 'wb').write(data)


SYNTH = {'hat_growsdt': {'00fa096261b336f4379f8b29999de11cd954b631868ad454b3d24a692c9ce638'},
         'hat_sdtfree': {'30effb603b4fa881c7b28171baf7f058c8d23e903817b726ae477d9990140a19'}}   # synth()'s, pinned


def selftest():
    import contextlib, io, os, tempfile
    want = bytes.fromhex('4e71')               # nop, written here independently of FIXED

    def runm(args, known):
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                main(args, known)
            return ''
        except SystemExit as e:
            return str(e.code or '')

    def run(args, known):
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                main(args, known)
            return 0
        except SystemExit as e:
            return 1 if e.code else 0
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'unix')
        synth(p)
        stock = open(p, 'rb').read()
        assert run(['--check', p], SYNTH) == 1, 'the stock object passed --check'
        assert run([p], {'hat_growsdt': set(), 'hat_sdtfree': SYNTH['hat_sdtfree']}) == 1 \
            and open(p, 'rb').read() == stock, 'an unknown hat_growsdt was patched'
        assert run([p], {'hat_growsdt': SYNTH['hat_growsdt'], 'hat_sdtfree': set()}) == 1 \
            and open(p, 'rb').read() == stock, 'an unknown hat_sdtfree was let through'
        assert run([p], SYNTH) == 0, 'the stock object was not patched'
        fixed = open(p, 'rb').read()
        diff = [i for i in range(len(stock)) if stock[i] != fixed[i]]
        assert len(diff) == 2 and fixed[diff[0]:diff[0] + 2] == want, 'the patch is not a nop in 2 bytes'
        assert run(['--check', p], SYNTH) == 0, 'the patched object failed --check'
        assert run([p], SYNTH) == 0 and open(p, 'rb').read() == fixed, 'a second run changed the object'
        cases = (('the shift itself (a foreign value)', 'g', SITE, 'e580'), ('the shift before it', 'g', 0xbc, 'eb80'),
                 ('the tail count', 'g', 0xb6, '9087'), ('the base add', 'g', 0xc0, 'd0aefff8'),
                 ('the units of the old size', 'g', 0x72, '721f'), ('the units of the new size', 'g', 0x7e, 'dc80'),
                 ('hat_sdtfree\'s unit', 'f', 8 + 10, 'ea8b'))
        for what, which, at, hexb in cases:
            v = bytes.fromhex(hexb)
            m = lambda t: t.__setitem__(slice(at, at + len(v)), v)
            synth(p, gmut=m if which == 'g' else None, fmut=m if which == 'f' else None)
            before = open(p, 'rb').read()
            assert run([p], None) != 0 and open(p, 'rb').read() == before, 'a changed %s was not refused' % what
        rcases = (('no relocation at the call', dict(relocs=((0xc4, 2, 1, 0),))), ('the call relocated to hat_growsdt', dict(relocs=((0xc8, 1, 1, 0),))),
                  ('an addend on the call', dict(relocs=((0xc8, 2, 1, 4),))), ('a PC-relative call', dict(relocs=((0xc8, 2, 5, 0),))),
                  ('a hat_growsdt too short to be the stock one', dict(glen=0xd0)))
        for what, kw in rcases:
            synth(p, **kw)
            before = open(p, 'rb').read()
            r = runm([p], None)
            want = 'too short' if 'glen' in kw else 'is not jsr hat_sdtfree'
            assert want in r and open(p, 'rb').read() == before, 'a hat_growsdt with %s was not refused (%r)' % (what, r)
        synth(p, gmut=lambda t: t.__setitem__(slice(2, 4), bytes.fromhex('ffc0')))
        before = open(p, 'rb').read()
        assert run([p], None) == 0, 'the frame change alone tripped a context check'
        synth(p, gmut=lambda t: t.__setitem__(slice(2, 4), bytes.fromhex('ffc0')))
        assert run([p], SYNTH) != 0 and open(p, 'rb').read() == before, 'a change only the digest sees was not refused'
    print('growsdt030 selftest: stock patched to a nop (2 bytes), idempotent, --check both ways, unknown hat_growsdt and '
          'hat_sdtfree, %d changed contexts, %d changed relocations and a change only the digest sees refused'
          % (len(cases), len(rcases)))


if __name__ == '__main__':
    main()
