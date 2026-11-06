#!/usr/bin/env python3
"""rwippc030.py -- ufs rwip's segmap_pagecreate call given the address the write starts at.

  rwippc030.py OBJ           patch the ufs object (ELF32 big-endian ET_REL) in place; refuses unless the bytes are
                             exactly the stock ones or already patched
  rwippc030.py --check OBJ   verify, write nothing; exit 1 unless patched
  rwippc030.py --selftest    patch a synthetic object: stock -> fixed, idempotent, an unknown rwip and changed
                             contexts refused

THE BUG.  For a write that covers whole pages, rwip maps the file's 8 KiB window (segmap_getmap returns its base)
and asks segmap_pagecreate to create the pages it will overwrite, so that they are not read from disk first.  The
stock object passes the window's base as the address:

    jsr   segmap_getmap         ; a0 = base
    movel a0,fp@(-108)          ; 2d48 ff94
    addaw #12,sp                ; defc 000c
    tstl  fp@(-28)              ; 4aae ffe4   the pagecreate flag
    beqw  ...                   ; 6700 xxxx
    clrl  sp@-                  ; 42a7        softlock 0
    movel fp@(-116),sp@-        ; 2f2e ff8c   n
    movel fp@(-108),sp@-        ; 2f2e ff94   base            <- base + mapon wanted
    movel segkmap,sp@-          ; 2f39 ....
    jsr   segmap_pagecreate     ; 4eb9 ....

while the copy that follows is uiomove(base + mapon, n, ...) (2a6e ff94, 4875 3800: d3 is mapon).  Every other
caller of segmap_pagecreate in the kernel (spec_write, s5's writei, nfs's rwvp, fbzero) passes base + offset, as
SVR4's own ufs_rwip does (segmap_pagecreate(segkmap, base + mapon, (u_int)n, 0)); the stock binary differs.  So a
write of whole pages that does not start at the window's start creates the pages at window offsets [0, n) instead of
[mapon, mapon + n): each one not in the cache is taken from the free list, entered under (vnode, block start) and
mapped with no read, keeps its frame's previous contents, and is never modified.  The disk stays right; reads of the
block's first n bytes return the old frame contents (an earlier block of the file, zeros, another file's data).

THE FIX.  The push of the address becomes pea a0@(0,d3:l) (4870 3800), the same length: a0 still holds getmap's
return there (only the store, the addaw, the tstl and the branch lie between) and d3 is the mapon uiomove adds.
Both hold only for the stock instruction stream, so the tool checks it: the bytes around the call, the four
relocations, d3 set once to uio_offset & 8191 before getmap, and the whole of rwip against the stock code's digest
(its code with relocated fields and the 4 bytes zeroed, and its relocations, with tools/bmaphf030.py's ufs_bmap_hf
counted as ufs_bmap; the same in 2.1 and 2.1c, in fs/ufs/exp, a carved module and a linked unix).
"""
import hashlib, struct, sys

STOCK = bytes.fromhex('2f2eff94')
FIXED = bytes.fromhex('48703800')
D3_MAPON = bytes.fromhex('262d0008028300001fff')   # movel a5@(8),d3; andil #8191,d3: d3 = uio_offset & MAXBOFFSET
# rwip as the stock ufs object has it (rwip_digest: its code with relocated fields and the 4 patched bytes zeroed, and
# its relocations): the same in fs/ufs/exp, the carved module and a linked unix.  Any other rwip is refused: the fix
# leans on a0 and d3 holding getmap's return and mapon at the push, which only the stock instruction stream guarantees.
KNOWN_RWIP = {'a249a12a434f9af89ea875a2f58ea7d7298fc1071218d7ceaa5d749a00a4b8a4'}   # 2.1 and 2.1c


def fail(msg):
    sys.exit('rwippc030: ' + msg)


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


def rwip_digest(b, text, start, end, rels, siteoff):
    """sha256 of rwip's bytes with relocated fields and the site zeroed, then of its relocations: offset, type and,
    for a named symbol, the name and addend (a section-relative one's addend moves with the link, so it is left out)"""
    c = bytearray(b[text + start:text + end])
    for off, typ, name, add in rels:
        c[off - start:off - start + 4] = bytes(4)
    c[siteoff - text - start:siteoff - text - start + 4] = bytes(4)
    r = ''.join('%x:%d:%s:%s;' % (off - start, typ, name or '.', add if name else '.') for off, typ, name, add in sorted(rels))
    return hashlib.sha256(bytes(c) + r.encode()).hexdigest()


def site(b, sh, syms, known=KNOWN_RWIP):
    """file offset of the 4 bytes to patch, and whether they are patched already"""
    rw = [s for s in syms if s[0] == 'rwip' and s[2] not in (0, 0xfff1, 0xfff2)]
    if len(rw) != 1:
        fail('%d definitions of rwip' % len(rw))
    _, start, sec, _ = rw[0]
    later = sorted(v for n, v, x, info in syms if x == sec and v > start and (info & 15) == 2)
    end = later[0] if later else sh[sec][5]
    text = sh[sec][4]
    rel, allrel = {}, []
    for s in sh:
        if s[1] != 4 or s[7] != sec:
            continue
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if start <= off < end:
                n, v, x, i = syms[info >> 8]
                n = 'ufs_bmap' if n == 'ufs_bmap_hf' else n     # tools/bmaphf030.py's retarget is not a change
                allrel.append((off, info & 0xff, n if (i & 15) != 3 else '', add))
            if start <= off < end and info & 0xff == 1:
                rel.setdefault(syms[info >> 8][0], []).append((off, add))
    for name in ('segmap_getmap', 'segkmap', 'segmap_pagecreate', 'uiomove'):
        if any(a for o, a in rel.get(name, [])):
            fail('a relocation of rwip names %s with an addend (the stock ones have none)' % name)
    pc = rel.get('segmap_pagecreate', [])
    gm = rel.get('segmap_getmap', [])
    if len(pc) != 1:
        fail('rwip names segmap_pagecreate %d times (want 1)' % len(pc))
    jsr = pc[0][0] - 2                                   # the reloc is the jsr's operand
    km = [o for o, a in rel.get('segkmap', []) if o == jsr - 4]
    if not km:
        fail('no segkmap push right before rwip\'s segmap_pagecreate call')
    p = text + jsr
    # jsr segmap_getmap ends 16 bytes before the clrl: store (4), addaw (4), tstl (4), beqw xxxx (4)
    gend = jsr - 16 - 16
    if not any(o == gend - 4 for o, a in gm):
        fail('segmap_getmap is not called right before the pagecreate block (layout differs from stock)')
    if bytes(b[text + gend:text + gend + 14]) != bytes.fromhex('2d48ff94defc000c4aaeffe46700'):
        fail('bytes after segmap_getmap differ from stock: %s' % bytes(b[text + gend:text + gend + 14]).hex())
    if bytes(b[p - 16:p - 10]) != bytes.fromhex('42a72f2eff8c'):
        fail('the softlock and length pushes differ from stock: %s' % bytes(b[p - 16:p - 10]).hex())
    if bytes(b[p - 6:p - 4]) != bytes.fromhex('2f39') or bytes(b[p:p + 2]) != bytes.fromhex('4eb9'):
        fail('the segkmap push or the jsr differ from stock')
    cur = bytes(b[p - 10:p - 6])
    if cur not in (STOCK, FIXED):
        fail('the address push is %s (stock %s, patched %s)' % (cur.hex(), STOCK.hex(), FIXED.hex()))
    # the copy: uiomove(base + d3, ...), base reloaded from fp@(-108) into a5
    um = rel.get('uiomove', [])
    if not um or bytes.fromhex('2a6eff9448753800') not in bytes(b[text + jsr:text + um[0][0]]):
        fail('rwip\'s uiomove is not given fp@(-108) + d3 (movea fp@(-108),a5; pea a5@(0,d3:l)) after pagecreate')
    # d3: set to mapon once, before getmap (the stock code writes it nowhere else in rwip; the digest below pins that)
    code = bytes(b[text + start:text + end])
    if code.count(D3_MAPON) != 1 or code.index(D3_MAPON) >= gend - start:
        fail('rwip does not set d3 = uio_offset & 8191 exactly once before segmap_getmap')
    if known is not None:
        d = rwip_digest(b, text, start, end, allrel, p - 10)
        if d not in known:
            fail('rwip is not the stock code (digest %s)' % d)
    return p - 10, cur == FIXED


def synth(path, mutate=None, relocs=((16, 2, 0), (48, 3, 0), (54, 4, 0), (72, 5, 0)), extra=None):
    """a minimal ET_REL whose rwip holds the stock sequence, with its four relocations"""
    t = bytearray.fromhex(
        '4e560000' '262d0008' '028300001fff'               # 0: link; 4: d3 = uio_offset; 8: & 8191
        '4eb900000000'                                     # 14: jsr segmap_getmap (reloc at 16)
        '2d48ff94' 'defc000c' '4aaeffe4' '67000042'        # 20: store a0, addaw, tstl, beqw
        '42a7' '2f2eff8c' '2f2eff94'                       # 36: softlock, n, base
        '2f3900000000' '4eb900000000'                      # 46: segkmap (reloc 48); 52: jsr pagecreate (reloc 54)
        'defc0010' '2a6eff94' '48753800'                   # 58: addaw; 62: base into a5, pea a5@(0,d3:l)
        '4eb900000000' '4e5e4e75')                         # 70: jsr uiomove (reloc 72); unlk, rts
    if mutate:
        mutate(t)
    names = ['rwip', 'segmap_getmap', 'segkmap', 'segmap_pagecreate', 'uiomove'] + ([extra] if extra else [])
    strtab = b'\0' + b''.join(n.encode() + b'\0' for n in names)
    off = [1]
    for n in names[:-1]:
        off.append(off[-1] + len(n) + 1)
    sym = bytes(16) + struct.pack('>IIIBBH', off[0], 0, len(t), 0x12, 0, 1)
    sym += b''.join(struct.pack('>IIIBBH', off[i], 0, 0, 0x10, 0, 0) for i in range(1, len(names)))
    rela = b''.join(struct.pack('>IIi', o, (s << 8) | 1, a) for o, s, a in relocs)
    if extra:
        rela += struct.pack('>IIi', 10, (6 << 8) | 1, 0)          # a call of EXTRA (symbol 6) relocated at 10, as rwip's ufs_bmap
    shstr = b'\0.text\0.rela.text\0.symtab\0.strtab\0.shstrtab\0'
    body = [bytes(t), rela, sym, strtab, shstr]
    pos, offs = 52, []
    for x in body:
        offs.append(pos)
        pos += (len(x) + 3) & ~3
    shoff = pos
    data = bytearray(struct.pack('>4sBBBB8xHHIIIIIHHHHHH', b'\x7fELF', 1, 2, 1, 0, 1, 4, 1, 0, 0, shoff, 0, 52,
                                 0, 0, 40, 6, 5))
    for x in body:
        data += x + bytes(((len(x) + 3) & ~3) - len(x))
    sh = [(0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
          (1, 1, 6, 0, offs[0], len(body[0]), 0, 0, 2, 0),
          (7, 4, 0, 0, offs[1], len(rela), 3, 1, 4, 12),
          (18, 2, 0, 0, offs[2], len(sym), 4, 1, 4, 16),
          (26, 3, 0, 0, offs[3], len(strtab), 0, 0, 1, 0),
          (34, 3, 0, 0, offs[4], len(shstr), 0, 0, 1, 0)]
    for s in sh:
        data += struct.pack('>IIIIIIIIII', *s)
    open(path, 'wb').write(data)


SYNTH = {'f9cb0500771b286fa87a63eaf3e356a22cb2850ab9dbb0d9f4d1225c46335f34'}   # synth()'s rwip under rwip_digest, pinned so that a change to the digest itself is seen


def selftest():
    import os, tempfile
    want = bytes.fromhex('48703800')          # pea a0@(0,d3:l), written out here independently of FIXED

    def run(args, known):
        import contextlib, io
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                main(args, known)
            return 0
        except SystemExit as e:
            return 1 if e.code else 0
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'ufs.exp')
        synth(p)
        stock = open(p, 'rb').read()
        assert run(['--check', p], SYNTH) == 1, 'the stock object passed --check'
        assert run([p], set()) == 1 and open(p, 'rb').read() == stock, 'an rwip of unknown digest was patched'
        assert run([p], SYNTH) == 0, 'the stock object was not patched'
        fixed = open(p, 'rb').read()
        diff = [i for i in range(len(stock)) if stock[i] != fixed[i]]
        assert len(diff) == 4 and fixed[diff[0]:diff[0] + 4] == want, 'the patch is not pea a0@(0,d3:l) in 4 bytes'
        assert run(['--check', p], SYNTH) == 0, 'the patched object failed --check'
        assert run([p], SYNTH) == 0 and open(p, 'rb').read() == fixed, 'a second run changed the object'
        cases = (('the length push', 38, '2f2eff88'), ('the address push (a foreign value)', 42, '48703000'),
                 ('the uiomove operand', 66, '48754800'), ('a0\'s source (the store after getmap)', 20, '2d40ff94'),
                 ('d3\'s mask', 10, '00000fff'), ('the segkmap push', 46, '2f3a'), ('the pagecreate flag test', 28, '4aaeffe0'))
        for what, at, hexb in cases:
            v = bytes.fromhex(hexb)
            synth(p, lambda t: t.__setitem__(slice(at, at + len(v)), v))
            before = open(p, 'rb').read()
            assert run([p], None) != 0 and open(p, 'rb').read() == before, 'a changed %s was not refused' % what
        rcases = (('getmap not right before the block', ((16, 5, 0), (48, 3, 0), (54, 4, 0), (72, 2, 0))),
                  ('no segkmap relocation at the push', ((16, 2, 0), (48, 2, 0), (54, 4, 0), (72, 5, 0))),
                  ('an addend on the getmap relocation', ((16, 2, 16), (48, 3, 0), (54, 4, 0), (72, 5, 0))))
        for what, relocs in rcases:
            synth(p, relocs=relocs)
            before = open(p, 'rb').read()
            assert run([p], None) != 0 and open(p, 'rb').read() == before, 'an rwip with %s was not refused' % what
        digs = {}
        for name in ('ufs_bmap', 'ufs_bmap_hf', 'ufs_bmap_xyz'):
            synth(p, extra=name)
            b, sh, syms = load(p)
            try:
                site(b, sh, syms, set())
            except SystemExit as e:
                digs[name] = str(e.code).split('digest ')[-1].rstrip(')')
        assert len(digs) == 3 and digs['ufs_bmap'] == digs['ufs_bmap_hf'] != digs['ufs_bmap_xyz'], \
            'ufs_bmap_hf is not counted as ufs_bmap in the digest (or any name is): %r' % digs
        synth(p, lambda t: t.__setitem__(slice(2, 4), bytes.fromhex('fff0')))
        before = open(p, 'rb').read()
        assert run([p], None) == 0, 'the frame change alone tripped a context check'
        synth(p, lambda t: t.__setitem__(slice(2, 4), bytes.fromhex('fff0')))
        assert run([p], SYNTH) != 0 and open(p, 'rb').read() == before, 'a change only the digest sees was not refused'
    print('rwippc030 selftest: stock patched to pea a0@(0,d3:l) (4 bytes), idempotent, --check both ways, an unknown '
          'rwip, %d changed contexts, %d changed relocations and a change only the digest sees refused; ufs_bmap_hf counted '
          'as ufs_bmap in the digest, another name not'
          % (len(cases), len(rcases)))


def main(args=None, known=KNOWN_RWIP):
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
            fail('%s: rwip still passes the window base to segmap_pagecreate' % args[0])
        print('rwippc030: %s: rwip passes base + mapon to segmap_pagecreate (file offset 0x%x)' % (args[0], off))
        return
    if done:
        print('rwippc030: %s: already patched (file offset 0x%x)' % (args[0], off))
        return
    b[off:off + 4] = FIXED
    open(args[0], 'wb').write(b)
    print('rwippc030: %s: rwip\'s segmap_pagecreate address push %s -> %s (pea a0@(0,d3:l)) at file offset 0x%x'
          % (args[0], STOCK.hex(), FIXED.hex(), off))


if __name__ == '__main__':
    main()
