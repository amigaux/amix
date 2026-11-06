#!/usr/bin/env python3
"""bmaphf030.py -- ufs rwip's call of ufs_bmap goes to ufs_bmap_hf (src/ufs_bmap_hf.c).

  bmaphf030.py OBJ           retarget, in the ufs object linked with ufs_bmap_hf.o (ELF32 big-endian ET_REL), in
                             place; refuses unless rwip is the stock code and the call is exactly the stock one
  bmaphf030.py --check OBJ   verify, write nothing; exit 1 unless retargeted, ufs_bmap_hf called from rwip alone, and
                             ufs_bmap called from ufs_bmap_hf and not from rwip (the ufs object, the carved module or
                             a linked unix: ufs_bmap's other callers stay as they are)
  bmaphf030.py --selftest    retarget a synthetic object: stock -> retargeted, idempotent, refusals proved

src/ufs_bmap_hf.c says why: alloc-only is kept only for a block that is already allocated, so a new block is never
allocated without being read (zero-filled) under a write that leaves part of it unwritten.  Only rwip's relocation
changes (its symbol index): ufs_bmap's nine other callers in the ufs object keep the stock function, and no byte of
.text moves.  rwip must be the stock code: tools/rwippc030.py's digest of it (relocations included, the rwip fix's 4
bytes zeroed, ufs_bmap_hf counted as ufs_bmap) is required, and the call itself is checked byte for byte:
ufs_bmap(ip, lbn, NULL, NULL, on + n, S_WRITE, pagecreate) with pagecreate at fp@(-28), ip in a3, the inode lock
taken just before, the result kept in d2.
"""
import importlib.util, os, struct, sys

_s = importlib.util.spec_from_file_location('rwippc030', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rwippc030.py'))
rw = importlib.util.module_from_spec(_s)
_s.loader.exec_module(rw)

# movel fp@(-28) (pagecreate); pea 2 (S_WRITE); movel fp@(-100),d5; moveal fp@(-116),a5; pea a5@(0,d5:l) (on + n);
# clrl (rabnp); clrl (bnp); moveal fp@(12),a5 (uio); moveal fp@(-36),a4 (fs); movel a5@(8),d5; movel a4@(80),d6;
# asrl d6,d5 (lbn = uio_offset >> fs_bshift); movel d5 (lbn); movel a3 (ip); jsr <ufs_bmap>
BEFORE = bytes.fromhex('2f2effe4487800022a2eff9c2a6eff8c4875580042a742a72a6e000c286effdc2a2d00082c2c0050eca52f052f0b4eb9')
AFTER = bytes.fromhex('2400536b006edefc001c')     # movel d0,d2; subqw #1,a3@(110) (the lock count); addaw #28,sp
RWSITE = bytes.fromhex('42a72f2eff8c')            # the rwip fix's softlock and length pushes, before its 4 bytes
LOCAL = (0, 0xfff1, 0xfff2)


def fail(msg):
    sys.exit('bmaphf030: ' + msg)


def site(b, sh, syms, known=rw.KNOWN_RWIP):
    """(file offset of the relocation entry's r_info, index of ufs_bmap_hf, whether retargeted already)"""
    r = [s for s in syms if s[0] == 'rwip' and s[2] not in LOCAL]
    if len(r) != 1:
        fail('%d definitions of rwip' % len(r))
    _, start, sec, _ = r[0]
    later = sorted(v for n, v, x, info in syms if x == sec and v > start and (info & 15) == 2)
    end = later[0] if later else sh[sec][5]
    text = sh[sec][4]
    hf = [i for i, s in enumerate(syms) if s[0] == 'ufs_bmap_hf' and s[2] not in LOCAL]
    if len(hf) != 1:
        fail('ufs_bmap_hf is defined %d times in the object (link src/ufs_bmap_hf.c in first)' % len(hf))
    if not any(s[0] == 'ufs_hf_magic' and s[2] not in LOCAL for s in syms):
        fail('ufs_hf_magic is not defined in the object')
    rels, calls = [], []
    for s in sh:
        if s[1] != 4 or s[7] != sec:
            continue
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if not start <= off < end:
                continue
            n, v, x, i = syms[info >> 8]
            if n in ('ufs_bmap', 'ufs_bmap_hf'):
                calls.append((o, off, info, add, n))
                n = 'ufs_bmap'
            rels.append((off, info & 0xff, n if (i & 15) != 3 else '', add))
    if len(calls) != 1:
        fail('rwip names ufs_bmap %d times (want 1)' % len(calls))
    o, off, info, add, name = calls[0]
    if info & 0xff != 1 or add:
        fail('rwip\'s ufs_bmap relocation is not R_68K_32 with no addend')
    code = bytes(b[text + start:text + end])
    k = off - start
    if code[k - len(BEFORE):k] != BEFORE or code[k + 4:k + 4 + len(AFTER)] != AFTER:
        fail('the call of ufs_bmap in rwip differs from stock')
    if code.count(RWSITE) != 1:
        fail('rwip\'s segmap_pagecreate pushes are not there once')
    rs = text + start + code.index(RWSITE) + len(RWSITE)
    if known is not None:
        d = rw.rwip_digest(b, text, start, end, rels, rs)
        if d not in known:
            fail('rwip is not the stock code (digest %s)' % d)
    return o + 4, hf[0], name == 'ufs_bmap_hf'


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
    at, hf, done = site(b, sh, syms, known)
    if check:
        if not done:
            fail('%s: rwip still calls the stock ufs_bmap' % args[0])
        a, u = callers(b, sh, syms, 'ufs_bmap'), callers(b, sh, syms, 'ufs_bmap_hf')
        if u != {'rwip'}:
            fail('%s: ufs_bmap_hf is called from %s (want rwip alone)' % (args[0], sorted(u)))
        if 'ufs_bmap_hf' not in a or 'rwip' in a:
            fail('%s: ufs_bmap is called from %s (want ufs_bmap_hf, and not rwip)' % (args[0], sorted(a)))
        print('bmaphf030: %s: rwip calls ufs_bmap_hf, which rwip alone calls; ufs_bmap_hf calls ufs_bmap' % args[0])
        return
    if done:
        print('bmaphf030: %s: already retargeted' % args[0])
        return
    info, = struct.unpack_from('>I', b, at)
    struct.pack_into('>I', b, at, (hf << 8) | (info & 0xff))
    open(args[0], 'wb').write(b)
    print('bmaphf030: %s: rwip\'s ufs_bmap relocation now names ufs_bmap_hf' % args[0])


def synth(path, mutate=None, call=('ufs_bmap', 1, 0), defs=('ufs_bmap_hf', 'ufs_hf_magic'), wcall=2, other=None,
          dup_rwip=False, rwip_calls=1, rwsite=1):
    """a minimal ET_REL: rwip (the stock call of ufs_bmap and the rwip fix's pushes) and ufs_bmap_hf; optionally a
    function getpage calling OTHER, a second definition of rwip, a second ufs_bmap relocation in rwip, or the rwip fix's
    pushes RWSITE times"""
    t = bytearray(bytes.fromhex('4e560000') + BEFORE + bytes(4) + AFTER + RWSITE * rwsite + bytes.fromhex('2f2eff94') +
                  bytes.fromhex('4e5e4e75'))
    if mutate:
        mutate(t)
    g = bytes.fromhex('4eb900000000' + '4e75' + '55484621')   # ufs_bmap_hf: jsr ufs_bmap; rts; then ufs_hf_magic
    o = bytes.fromhex('4eb900000000' + '4e75')                 # getpage: jsr OTHER; rts
    names = ['rwip', 'ufs_bmap', 'ufs_bmap_hf', 'ufs_hf_magic', 'getpage']
    strtab = b'\0' + b''.join(n.encode() + b'\0' for n in names)
    off = [1]
    for n in names[:-1]:
        off.append(off[-1] + len(n) + 1)
    sym = bytes(16) + struct.pack('>IIIBBH', off[0], 0, len(t), 0x12, 0, 1)
    sym += struct.pack('>IIIBBH', off[1], 0, 0, 0x10, 0, 0)
    sym += struct.pack('>IIIBBH', off[2], len(t), 8, 0x12, 0, 1 if 'ufs_bmap_hf' in defs else 0)
    sym += struct.pack('>IIIBBH', off[3], len(t) + 8, 4, 0x11, 0, 1 if 'ufs_hf_magic' in defs else 0)
    sym += struct.pack('>IIIBBH', off[0] if dup_rwip else off[4], len(t) + 12, len(o), 0x12, 0, 1)
    cs = {'ufs_bmap': 2, 'ufs_bmap_hf': 3}
    rela = struct.pack('>IIi', 4 + len(BEFORE), (cs[call[0]] << 8) | call[1], call[2])
    rela += struct.pack('>IIi', len(t) + 2, (wcall << 8) | 1, 0)
    if other:
        rela += struct.pack('>IIi', len(t) + 14, (cs[other] << 8) | 1, 0)
    if rwip_calls > 1:
        rela += struct.pack('>IIi', len(t) - 8, (2 << 8) | 1, 0)
    shstr = b'\0.text\0.rela.text\0.symtab\0.strtab\0.shstrtab\0'
    body = [bytes(t) + g + o, rela, sym, strtab, shstr]
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


SYNTH = {'a3047ff26dd04dcb0be847a568bbb9bfbf9c1c8d09f353dc340e9cf721377e51'}   # synth()'s rwip under rwippc030's digest, pinned


def selftest():
    """each check is shown to refuse on its own: every case asserts the refusal's own message"""
    import contextlib, io, tempfile

    def run(args, known):
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                main(args, known)
            return ''
        except SystemExit as e:
            return str(e.code or '')
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'ufs.exp')
        synth(p)
        stock = open(p, 'rb').read()
        assert 'still calls the stock ufs_bmap' in run(['--check', p], SYNTH), 'the stock object passed --check'
        assert 'not the stock code' in run([p], set()) and open(p, 'rb').read() == stock, 'an unknown rwip was retargeted'
        assert run([p], SYNTH) == '', 'the stock object was not retargeted'
        new = open(p, 'rb').read()
        diff = [i for i in range(len(stock)) if stock[i] != new[i]]
        b, sh, syms = rw.load(p)
        info, = struct.unpack_from('>I', b, sh[2][4] + 4)     # the first entry, rwip's call
        assert syms[info >> 8][0] == 'ufs_bmap_hf' and len(diff) == 1, 'the relocation does not name ufs_bmap_hf alone'
        assert run(['--check', p], SYNTH) == '', 'the retargeted object failed --check'
        assert run([p], SYNTH) == '' and open(p, 'rb').read() == new, 'a second run changed the object'
        n = 0
        for what, kw, msg in (
                ('the pagecreate argument', dict(mutate=lambda t: t.__setitem__(slice(6, 8), bytes.fromhex('ffe0'))), 'differs from stock'),
                ('the S_WRITE argument', dict(mutate=lambda t: t.__setitem__(slice(10, 12), bytes.fromhex('0001'))), 'differs from stock'),
                ('the ip argument', dict(mutate=lambda t: t.__setitem__(slice(48, 50), bytes.fromhex('2f0c'))), 'differs from stock'),
                ('the lbn shift', dict(mutate=lambda t: t.__setitem__(slice(44, 46), bytes.fromhex('e2a5'))), 'differs from stock'),
                ('the store of the result', dict(mutate=lambda t: t.__setitem__(slice(56, 58), bytes.fromhex('2600'))), 'differs from stock'),
                ('an addend on the call', dict(call=('ufs_bmap', 1, 4)), 'no addend'),
                ('a PC-relative call', dict(call=('ufs_bmap', 5, 0)), 'no addend'),
                ('no ufs_bmap_hf in the object', dict(defs=('ufs_hf_magic',)), 'ufs_bmap_hf is defined 0 times'),
                ('no ufs_hf_magic', dict(defs=('ufs_bmap_hf',)), 'ufs_hf_magic is not defined'),
                ('two definitions of rwip', dict(dup_rwip=True), '2 definitions of rwip'),
                ('rwip naming ufs_bmap twice', dict(rwip_calls=2), 'names ufs_bmap 2 times'),
                ('the rwip fix\'s pushes twice', dict(rwsite=2), 'not there once'),
                ('the rwip fix\'s pushes missing', dict(rwsite=0), 'not there once')):
            synth(p, **kw)
            before = open(p, 'rb').read()
            r = run([p], None)
            assert msg in r and open(p, 'rb').read() == before, 'a changed %s was not refused (%r)' % (what, r)
            n += 1
        m = 0
        for what, kw, msg in (
                ('a wrapper that does not call ufs_bmap', dict(wcall=1), 'ufs_bmap is called from'),
                ('ufs_bmap_hf called from a second function', dict(other='ufs_bmap_hf'), 'ufs_bmap_hf is called from')):
            synth(p, **kw)
            assert run([p], SYNTH) == '', 'could not retarget for the %s case' % what
            r = run(['--check', p], SYNTH)
            assert msg in r, 'the check passed %s (%r)' % (what, r)
            m += 1
        synth(p, other='ufs_bmap')
        run([p], SYNTH)
        assert run(['--check', p], SYNTH) == '', 'another caller of ufs_bmap (as getpage) was refused'
        synth(p, mutate=lambda t: t.__setitem__(slice(2, 4), bytes.fromhex('fff0')))
        before = open(p, 'rb').read()
        assert run([p], None) == '', 'the frame change alone tripped a context check'
        synth(p, mutate=lambda t: t.__setitem__(slice(2, 4), bytes.fromhex('fff0')))
        assert 'not the stock code' in run([p], SYNTH) and open(p, 'rb').read() == before, 'a change only the digest sees was not refused'
    print('bmaphf030 selftest: the stock call retargeted (one relocation), idempotent, --check both ways, an unknown '
          'rwip, %d bad objects and %d bad call graphs refused, each by its own check, ufs_bmap\'s other callers '
          'allowed, and a change only the digest sees refused' % (n, m))


if __name__ == '__main__':
    main()
