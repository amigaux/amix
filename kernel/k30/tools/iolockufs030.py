#!/usr/bin/env python3
"""iolockufs030.py -- ufs rwip's call of as_iolock goes to as_iolock_ufs (src/as_iolock_ufs.c).

  iolockufs030.py OBJ           retarget, in the ufs object linked with as_iolock_ufs.o (ELF32 big-endian ET_REL), in
                                place; refuses unless rwip is the stock code and the call is exactly the stock one
  iolockufs030.py --check OBJ   verify, write nothing; exit 1 unless retargeted
  iolockufs030.py --selftest    retarget a synthetic object: stock -> retargeted, idempotent, refusals proved

src/as_iolock_ufs.c says why: pagecreate is kept only for writes that start at the 8 KiB window and cover it or run
to the end of the file, so a new block is never allocated alloc-only under a write that leaves part of it unwritten.
Only rwip's relocation changes (its symbol index): nfs's rwvp and every other caller keep the stock as_iolock, and no
byte of .text moves.  rwip must be the stock code: tools/rwippc030.py's digest of it (relocations included, the
rwip fix's 4 bytes zeroed, as_iolock_ufs counted as as_iolock) is required, and the call itself is checked byte for
byte: as_iolock(uio, &iolpl, n, vp, old size, &pagecreate) with pagecreate at fp@(-28), the n it returns stored at
fp@(-116).
"""
import importlib.util, os, struct, sys

_s = importlib.util.spec_from_file_location('rwippc030', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rwippc030.py'))
rw = importlib.util.module_from_spec(_s)
_s.loader.exec_module(rw)

# pea fp@(-28) (&pagecreate); movel d4 (old size); movel d7 (vp); movel fp@(-116) (n); pea fp@(-24) (&iolpl);
# movel fp@(12) (uio); jsr <as_iolock>
BEFORE = bytes.fromhex('486effe42f042f072f2eff8c486effe82f2e000c4eb9')
AFTER = bytes.fromhex('2d40ff8cdefc0018')          # movel d0,fp@(-116); addaw #24,sp
RWSITE = bytes.fromhex('42a72f2eff8c')            # the rwip fix's softlock and length pushes, before its 4 bytes


def fail(msg):
    sys.exit('iolockufs030: ' + msg)


def site(b, sh, syms, known=rw.KNOWN_RWIP):
    """(file offset of the relocation entry's r_info, index of as_iolock_ufs, whether retargeted already)"""
    r = [s for s in syms if s[0] == 'rwip' and s[2] not in (0, 0xfff1, 0xfff2)]
    if len(r) != 1:
        fail('%d definitions of rwip' % len(r))
    _, start, sec, _ = r[0]
    later = sorted(v for n, v, x, info in syms if x == sec and v > start and (info & 15) == 2)
    end = later[0] if later else sh[sec][5]
    text = sh[sec][4]
    ufs = [i for i, s in enumerate(syms) if s[0] == 'as_iolock_ufs' and s[2] not in (0, 0xfff1, 0xfff2)]
    if len(ufs) != 1:
        fail('as_iolock_ufs is defined %d times in the object (link src/as_iolock_ufs.c in first)' % len(ufs))
    if not any(s[0] == 'ufs_pc_magic' and s[2] not in (0, 0xfff1, 0xfff2) for s in syms):
        fail('ufs_pc_magic is not defined in the object')
    rels, calls = [], []
    for s in sh:
        if s[1] != 4 or s[7] != sec:
            continue
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if not start <= off < end:
                continue
            n, v, x, i = syms[info >> 8]
            if n in ('as_iolock', 'as_iolock_ufs'):
                calls.append((o, off, info, add, n))
                n = 'as_iolock'
            rels.append((off, info & 0xff, n if (i & 15) != 3 else '', add))
    if len(calls) != 1:
        fail('rwip names as_iolock %d times (want 1)' % len(calls))
    o, off, info, add, name = calls[0]
    if info & 0xff != 1 or add:
        fail('rwip\'s as_iolock relocation is not R_68K_32 with no addend')
    code = bytes(b[text + start:text + end])
    k = off - start
    if code[k - len(BEFORE):k] != BEFORE or code[k + 4:k + 4 + len(AFTER)] != AFTER:
        fail('the call of as_iolock in rwip differs from stock')
    if code.count(RWSITE) != 1:
        fail('rwip\'s segmap_pagecreate pushes are not there once')
    rs = text + start + code.index(RWSITE) + len(RWSITE)
    if known is not None:
        d = rw.rwip_digest(b, text, start, end, rels, rs)
        if d not in known:
            fail('rwip is not the stock code (digest %s)' % d)
    return o + 4, ufs[0], name == 'as_iolock_ufs'


def callers(b, sh, syms, target):
    """the functions whose code holds a relocation naming target"""
    out = set()
    ti = {i for i, s in enumerate(syms) if s[0] == target}
    for s in sh:
        if s[1] != 4:
            continue
        sec = s[7]
        funcs = sorted((v, n) for n, v, x, info in syms if x == sec and n and (info & 15) == 2)
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if info >> 8 in ti:
                f = [n for v, n in funcs if v <= off]
                out.add(f[-1] if f else '?')
    return out


def main(args=None, known=rw.KNOWN_RWIP):
    args = sys.argv[1:] if args is None else args
    if args == ['--selftest']:
        return selftest()
    check = args[:1] == ['--check']
    if check:
        args = args[1:]
    if len(args) != 1:
        sys.exit(__doc__)
    b, sh, syms = rw.load(args[0])
    at, ufs, done = site(b, sh, syms, known)
    if check:
        if not done:
            fail('%s: rwip still calls the stock as_iolock' % args[0])
        a, u = callers(b, sh, syms, 'as_iolock'), callers(b, sh, syms, 'as_iolock_ufs')
        if a != {'as_iolock_ufs'} or u != {'rwip'}:
            fail('%s: as_iolock is called from %s and as_iolock_ufs from %s (want as_iolock_ufs, rwip)'
                 % (args[0], sorted(a), sorted(u)))
        print('iolockufs030: %s: rwip calls as_iolock_ufs, and only as_iolock_ufs calls as_iolock' % args[0])
        return
    if done:
        print('iolockufs030: %s: already retargeted' % args[0])
        return
    info, = struct.unpack_from('>I', b, at)
    struct.pack_into('>I', b, at, (ufs << 8) | (info & 0xff))
    open(args[0], 'wb').write(b)
    print('iolockufs030: %s: rwip\'s as_iolock relocation now names as_iolock_ufs' % args[0])


def synth(path, mutate=None, call=('as_iolock', 1, 0), defs=('as_iolock_ufs', 'ufs_pc_magic'), wcall=2):
    """a minimal ET_REL: rwip (the stock call of as_iolock and the rwip fix's pushes) and as_iolock_ufs"""
    t = bytearray(bytes.fromhex('4e560000') + BEFORE + bytes(4) + AFTER + RWSITE + bytes.fromhex('2f2eff94') +
                  bytes.fromhex('4e5e4e75'))
    if mutate:
        mutate(t)
    g = bytes.fromhex('4eb900000000' + '4e75' + '55504321')   # as_iolock_ufs: jsr as_iolock; rts; then ufs_pc_magic
    names = ['rwip', 'as_iolock', 'as_iolock_ufs', 'ufs_pc_magic']
    strtab = b'\0' + b''.join(n.encode() + b'\0' for n in names)
    off = [1]
    for n in names[:-1]:
        off.append(off[-1] + len(n) + 1)
    sym = bytes(16) + struct.pack('>IIIBBH', off[0], 0, len(t), 0x12, 0, 1)
    sym += struct.pack('>IIIBBH', off[1], 0, 0, 0x10, 0, 0)
    sym += struct.pack('>IIIBBH', off[2], len(t), 8, 0x12, 0, 1 if 'as_iolock_ufs' in defs else 0)
    sym += struct.pack('>IIIBBH', off[3], len(t) + 8, 4, 0x11, 0, 1 if 'ufs_pc_magic' in defs else 0)
    cs = {'as_iolock': 2, 'as_iolock_ufs': 3}[call[0]]
    rela = struct.pack('>IIi', 4 + len(BEFORE), (cs << 8) | call[1], call[2]) + struct.pack('>IIi', len(t) + 2, (wcall << 8) | 1, 0)
    shstr = b'\0.text\0.rela.text\0.symtab\0.strtab\0.shstrtab\0'
    body = [bytes(t) + g, rela, sym, strtab, shstr]
    pos, offs = 52, []
    for x in body:
        offs.append(pos)
        pos += (len(x) + 3) & ~3
    data = bytearray(struct.pack('>4sBBBB8xHHIIIIIHHHHHH', b'\x7fELF', 1, 2, 1, 0, 1, 4, 1, 0, 0, pos, 0, 52,
                                 0, 0, 40, 6, 5))
    for x in body:
        data += x + bytes(((len(x) + 3) & ~3) - len(x))
    sh = [(0, 0, 0, 0, 0, 0, 0, 0, 0, 0), (1, 1, 6, 0, offs[0], len(body[0]), 0, 0, 2, 0),
          (7, 4, 0, 0, offs[1], len(rela), 3, 1, 4, 12), (18, 2, 0, 0, offs[2], len(sym), 4, 1, 4, 16),
          (26, 3, 0, 0, offs[3], len(strtab), 0, 0, 1, 0), (34, 3, 0, 0, offs[4], len(shstr), 0, 0, 1, 0)]
    for s in sh:
        data += struct.pack('>IIIIIIIIII', *s)
    open(path, 'wb').write(data)


SYNTH = {'4099c352ac277edef3865773bc7fdc6417877a892d2580ba242a6d34967be0a6'}   # synth()'s rwip under rwippc030's digest, pinned


def selftest():
    import contextlib, io, tempfile

    def run(args, known):
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
        assert run([p], set()) == 1 and open(p, 'rb').read() == stock, 'an unknown rwip was retargeted'
        assert run([p], SYNTH) == 0, 'the stock object was not retargeted'
        new = open(p, 'rb').read()
        diff = [i for i in range(len(stock)) if stock[i] != new[i]]
        b, sh, syms = rw.load(p)
        info, = struct.unpack_from('>I', b, sh[2][4] + 4)     # the first entry, rwip's call
        assert syms[info >> 8][0] == 'as_iolock_ufs' and len(diff) == 1, 'the relocation does not name as_iolock_ufs alone'
        assert run(['--check', p], SYNTH) == 0, 'the retargeted object failed --check'
        assert run([p], SYNTH) == 0 and open(p, 'rb').read() == new, 'a second run changed the object'
        cases = (('the pagecreate argument', 4 + 2, 'ffe0'), ('the uio argument', 4 + 18, '0010'),
                 ('the store of n', 4 + len(BEFORE) + 4, '2d41ff8c'), ('the vp argument', 4 + 6, '2f06'))
        for what, at, hexb in cases:
            v = bytes.fromhex(hexb)
            synth(p, lambda t: t.__setitem__(slice(at, at + len(v)), v))
            before = open(p, 'rb').read()
            assert run([p], None) != 0 and open(p, 'rb').read() == before, 'a changed %s was not refused' % what
        rcases = (('an addend on the call', dict(call=('as_iolock', 1, 4))), ('a PC-relative call', dict(call=('as_iolock', 5, 0))),
                  ('no as_iolock_ufs in the object', dict(defs=('ufs_pc_magic',))), ('no ufs_pc_magic', dict(defs=('as_iolock_ufs',))))
        for what, kw in rcases:
            synth(p, **kw)
            before = open(p, 'rb').read()
            assert run([p], None) != 0 and open(p, 'rb').read() == before, 'an object with %s was not refused' % what
        synth(p, wcall=3)
        assert run([p], SYNTH) == 0 and run(['--check', p], SYNTH) != 0, \
            'a wrapper that does not call as_iolock passed --check'
        synth(p, lambda t: t.__setitem__(slice(2, 4), bytes.fromhex('fff0')))
        before = open(p, 'rb').read()
        assert run([p], None) == 0, 'the frame change alone tripped a context check'
        synth(p, lambda t: t.__setitem__(slice(2, 4), bytes.fromhex('fff0')))
        assert run([p], SYNTH) != 0 and open(p, 'rb').read() == before, 'a change only the digest sees was not refused'
    print('iolockufs030 selftest: the stock call retargeted (one relocation), idempotent, --check both ways, an unknown '
          'rwip, %d changed contexts, %d bad relocations or objects, a wrapper not calling as_iolock and a change only the '
          'digest sees refused'
          % (len(cases), len(rcases)))


if __name__ == '__main__':
    main()
