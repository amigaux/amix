#!/usr/bin/env python3
"""rwippc030.py -- ufs rwip's segmap_pagecreate call given the address the write starts at.

  rwippc030.py OBJ           patch the ufs object (ELF32 big-endian ET_REL) in place; refuses unless the bytes are
                             exactly the stock ones or already patched
  rwippc030.py --check OBJ   verify, write nothing; exit 1 unless patched
  rwippc030.py --selftest    patch a synthetic object: stock -> fixed, idempotent, changed contexts refused

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
"""
import struct, sys

STOCK = bytes.fromhex('2f2eff94')
FIXED = bytes.fromhex('48703800')


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


def site(b, sh, syms):
    """file offset of the 4 bytes to patch, and whether they are patched already"""
    rw = [s for s in syms if s[0] == 'rwip' and s[2] not in (0, 0xfff1, 0xfff2)]
    if len(rw) != 1:
        fail('%d definitions of rwip' % len(rw))
    _, start, sec, _ = rw[0]
    later = sorted(v for n, v, x, info in syms if x == sec and v > start and (info & 15) == 2)
    end = later[0] if later else sh[sec][5]
    text = sh[sec][4]
    rel = {}
    for s in sh:
        if s[1] != 4 or s[7] != sec:
            continue
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if start <= off < end and info & 0xff == 1:
                rel.setdefault(syms[info >> 8][0], []).append((off, add))
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
    return p - 10, cur == FIXED


def synth(path, mutate=None):
    """a minimal ET_REL whose rwip holds the stock sequence, with its four relocations"""
    t = bytearray.fromhex(
        '4e560000' '4eb900000000'                          # 0: link; 4: jsr segmap_getmap (reloc at 6)
        '2d48ff94' 'defc000c' '4aaeffe4' '67000042'        # 10: store, addaw, tstl, beqw
        '42a7' '2f2eff8c' '2f2eff94'                       # 26: softlock, n, base
        '2f3900000000' '4eb900000000'                      # 36: segkmap (reloc 38); 42: jsr pagecreate (reloc 44)
        'defc0010' '2a6eff94' '48753800'                   # 48: addaw; 52: base into a5, pea a5@(0,d3:l)
        '4eb900000000' '4e5e4e75')                         # 60: jsr uiomove (reloc 62); unlk, rts
    if mutate:
        mutate(t)
    names = ['rwip', 'segmap_getmap', 'segkmap', 'segmap_pagecreate', 'uiomove']
    strtab = b'\0' + b''.join(n.encode() + b'\0' for n in names)
    off = [1]
    for n in names[:-1]:
        off.append(off[-1] + len(n) + 1)
    sym = bytes(16) + struct.pack('>IIIBBH', off[0], 0, len(t), 0x12, 0, 1)
    sym += b''.join(struct.pack('>IIIBBH', off[i], 0, 0, 0x10, 0, 0) for i in range(1, 5))
    rela = b''.join(struct.pack('>IIi', o, (s << 8) | 1, 0) for o, s in ((6, 2), (38, 3), (44, 4), (62, 5)))
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


def selftest():
    import os, subprocess, tempfile
    me = os.path.abspath(__file__)
    run = lambda *a: subprocess.run([sys.executable, me] + list(a), capture_output=True, text=True)
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'ufs.exp')
        synth(p)
        stock = open(p, 'rb').read()
        assert run('--check', p).returncode == 1, 'the stock object passed --check'
        assert run(p).returncode == 0, 'the stock object was not patched'
        fixed = open(p, 'rb').read()
        diff = [i for i in range(len(stock)) if stock[i] != fixed[i]]
        assert len(diff) == 4 and fixed[diff[0]:diff[0] + 4] == FIXED, 'the patch is not the 4 bytes'
        assert run('--check', p).returncode == 0, 'the patched object failed --check'
        assert run(p).returncode == 0 and open(p, 'rb').read() == fixed, 'a second run changed the object'
        for what, m in (('a context instruction', lambda t: t.__setitem__(slice(28, 32), bytes.fromhex('2f2eff88'))),
                        ('the address push', lambda t: t.__setitem__(slice(32, 36), bytes.fromhex('2f2eff90'))),
                        ('the uiomove operand', lambda t: t.__setitem__(slice(56, 60), bytes.fromhex('48754800')))):
            synth(p, m)
            before = open(p, 'rb').read()
            assert run(p).returncode != 0 and open(p, 'rb').read() == before, 'a changed %s was not refused' % what
    print('rwippc030 selftest: stock patched (4 bytes), idempotent, --check both ways, 3 changed contexts refused')


def main():
    args = sys.argv[1:]
    if args == ['--selftest']:
        return selftest()
    check = args[:1] == ['--check']
    if check:
        args = args[1:]
    if len(args) != 1:
        sys.exit(__doc__)
    b, sh, syms = load(args[0])
    off, done = site(b, sh, syms)
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
