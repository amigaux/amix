#!/usr/bin/env python3
"""tcpclose-retarget.py -- TCP's upper read queue closes through tcpclose_lg (src/tcpclose_lg.c).

  tcpclose-retarget.py UNIX           retarget, in the linked ET_REL kernel, in place; refuses unless tcpclose is
                                      the stock code and the qinit's close is exactly the stock one
  tcpclose-retarget.py --check UNIX   verify, write nothing; exit 1 unless tcpurinit's close names tcpclose_lg,
                                      tcpclose_lg is named from there alone, and tcpclose is named from tcpclose_lg
                                      and the other three qinits only
  tcpclose-retarget.py --selftest     retarget a synthetic object: stock -> retargeted, idempotent, refusals proved

src/tcpclose_lg.c says why: a close without SO_LINGER gets SO_LINGER with a time, so the stock tcpclose waits for
the unsent data and the FIN to be acknowledged instead of dropping the data.  Only one relocation changes (its
symbol index): qi_qclose of tcpurinit, the qinit tcpinfo's st_rdinit names, which is the close STREAMS calls.  The
other three qinits name tcpclose too and are left alone (a lower queue is never closed through them).  No byte of
.text moves.  tcpclose must be the stock code: the digest of its bytes, each relocated field zeroed, and of its
relocations (offset, symbol, addend) is pinned, which pins the inpcb offsets the wrapper writes (inp_protoopt at
+64, inp_linger at +66, q_ptr at +20) as tcpclose itself reads them.

MIT licence, see LICENSE in kernel/k30.
"""
import contextlib, hashlib, io, os, struct, sys, tempfile

SHT_SYMTAB, SHT_RELA = 2, 4
R_68K_32 = 1
KNOWN = {'ed8623d808def0a01bb948265d0f5bc96573249e47415e7733e82af8f500e1c9'}   # tcpclose of the stock 2.1c tcp object, pinned
QI_QOPEN, QI_QCLOSE = 8, 12


def fail(msg):
    sys.exit('tcpclose-retarget: ' + msg)


def load(path):
    b = bytearray(open(path, 'rb').read())
    if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or struct.unpack_from('>H', b, 16)[0] != 1:
        fail('%s is not an ELF32 big-endian ET_REL' % path)
    shoff, = struct.unpack_from('>I', b, 32)
    shentsize, shnum = struct.unpack_from('>HH', b, 46)
    sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
    st = [s for s in sh if s[1] == SHT_SYMTAB]
    if len(st) != 1:
        fail('%d symbol tables' % len(st))
    st = st[0]
    stroff = sh[st[6]][4]
    syms = []
    for i in range(st[5] // 16):
        name, value, size, info, other, shndx = struct.unpack_from('>IIIBBH', b, st[4] + 16 * i)
        syms.append((bytes(b[stroff + name:b.index(0, stroff + name)]).decode(), value, shndx, info))
    rel = []        # (file offset of the entry, target section, r_offset, symbol index, type, addend)
    for s in sh:
        if s[1] == SHT_RELA:
            for o in range(s[4], s[4] + s[5], 12):
                off, info, add = struct.unpack_from('>IIi', b, o)
                rel.append((o, s[7], off, info >> 8, info & 0xff, add))
    return b, sh, syms, rel


def defined(syms, name):
    hits = [i for i, s in enumerate(syms) if s[0] == name and s[2] != 0]
    if len(hits) != 1:
        fail('%d definitions of %s' % (len(hits), name))
    return hits[0]


def span(sh, syms, i):
    """[start, end) of symbol i: up to the next symbol defined in its section, or the section's end"""
    n, v, x, info = syms[i]
    return v, min([s[1] for s in syms if s[2] == x and s[1] > v and s[0]] + [sh[x][5]])


def at(rel, sec, off):
    hits = [r for r in rel if r[1] == sec and r[2] == off]
    if len(hits) != 1:
        fail('%d relocations at section %d offset %#x' % (len(hits), sec, off))
    return hits[0]


def digest(b, sh, syms, rel, i):
    """tcpclose's bytes, each relocated field zeroed, and its relocations by symbol name"""
    lo, hi = span(sh, syms, i)
    x = syms[i][2]
    code = bytearray(b[sh[x][4] + lo:sh[x][4] + hi])
    h = hashlib.sha256()
    for r in sorted((r for r in rel if r[1] == x and lo <= r[2] < hi), key=lambda r: r[2]):
        if r[4] != R_68K_32 or r[2] + 4 > hi:
            fail('tcpclose: an unexpected relocation at %#x' % r[2])
        code[r[2] - lo:r[2] - lo + 4] = bytes(4)
        h.update(b'%x %s %d\n' % (r[2] - lo, syms[r[3]][0].encode(), r[5]))
    h.update(bytes(code))
    return h.hexdigest()


def named(rel, syms, name):
    ti = {i for i, s in enumerate(syms) if s[0] == name}
    return [r for r in rel if r[3] in ti]


def site(b, sh, syms, rel, known):
    """the qi_qclose relocation of the qinit tcpinfo's st_rdinit names, and tcpclose_lg's index"""
    ui = defined(syms, 'tcpurinit')
    ii = defined(syms, 'tcpinfo')
    ci = defined(syms, 'tcpclose')
    li = defined(syms, 'tcpclose_lg')
    x, v = syms[ui][2], syms[ui][1]
    rd = at(rel, syms[ii][2], syms[ii][1])
    if syms[rd[3]][0] != 'tcpurinit' or rd[4] != R_68K_32 or rd[5] != 0:
        fail("tcpinfo's st_rdinit does not name tcpurinit")
    op = at(rel, x, v + QI_QOPEN)
    if syms[op[3]][0] != 'tcpopen' or op[4] != R_68K_32 or op[5] != 0:
        fail("tcpurinit's qi_qopen is not tcpopen: not the stock qinit")
    cl = at(rel, x, v + QI_QCLOSE)
    if syms[cl[3]][0] not in ('tcpclose', 'tcpclose_lg') or cl[4] != R_68K_32 or cl[5] != 0:
        fail("tcpurinit's qi_qclose names %s+%d: not the stock close" % (syms[cl[3]][0], cl[5]))
    d = digest(b, sh, syms, rel, ci)
    if d not in known:
        fail('tcpclose is not the stock code (digest %s)' % d[:16])
    lo, hi = span(sh, syms, li)
    if not [r for r in named(rel, syms, 'tcpclose') if r[1] == syms[li][2] and lo <= r[2] < hi]:
        fail('tcpclose_lg does not call tcpclose')
    return cl, li


def check(b, sh, syms, rel, known):
    cl, li = site(b, sh, syms, rel, known)
    lg = named(rel, syms, 'tcpclose_lg')
    lo, hi = span(sh, syms, li)
    lx = syms[li][2]
    plain = [r for r in named(rel, syms, 'tcpclose') if not (r[1] == lx and lo <= r[2] < hi)]
    errs = []
    if syms[cl[3]][0] != 'tcpclose_lg':
        errs.append("tcpurinit's qi_qclose still names the stock tcpclose")
    if [r[0] for r in lg] != [cl[0]]:
        errs.append('tcpclose_lg is named from %d places, not from tcpurinit alone' % len(lg))
    ii = defined(syms, 'tcpinfo')       # the other three qinits: tcpinfo's st_wrinit, st_muxrinit, st_muxwinit
    others = sorted(syms[at(rel, syms[ii][2], syms[ii][1] + k)[3]][1] + QI_QCLOSE for k in (4, 8, 12))
    if sorted(r[2] for r in plain if r[1] == cl[1]) != others or len(plain) != 3:
        errs.append('tcpclose is named from %d places besides tcpclose_lg, not the other three qinits' % len(plain))
    return errs


def main(args=None, known=None):
    args = sys.argv[1:] if args is None else args
    known = KNOWN if known is None else known
    if args == ['--selftest']:
        return selftest()
    mode = args[0] if len(args) == 2 and args[0] == '--check' else None
    if len(args) != (2 if mode else 1):
        fail(__doc__)
    path = args[-1]
    b, sh, syms, rel = load(path)
    if mode:
        errs = check(b, sh, syms, rel, known)
        if errs:
            fail('%s: NOT RETARGETED: %s' % (path, '; '.join(errs)))
        print('tcpclose-retarget: %s: tcpurinit closes through tcpclose_lg; tcpclose stock -- OK' % path)
        return 0
    cl, li = site(b, sh, syms, rel, known)
    if syms[cl[3]][0] == 'tcpclose_lg':
        print('tcpclose-retarget: %s: already retargeted' % path)
        return 0
    o, x, off, si, typ, add = cl
    struct.pack_into('>IIi', b, o, off, (li << 8) | typ, add)
    open(path, 'wb').write(b)
    print("tcpclose-retarget: %s: tcpurinit's qi_qclose now names tcpclose_lg" % path)
    return 0


def synth(path, code=b'\x4e\x56\x00\x00\x4e\xb9\0\0\0\0\x4e\x5e\x4e\x75', lg=True, lgcall=True, rd='tcpurinit',
          qopen='tcpopen', qclose='tcpclose', extra=None):
    """a minimal ET_REL: tcpclose (CODE, one call), tcpclose_lg calling tcpclose; tcpurinit, tcpuwinit, tcplrinit,
    tcplwinit (28 bytes each) naming tcpopen and tcpclose, and tcpinfo naming the four"""
    names = ['tcpclose', 'tcpclose_lg', 'tcpopen', 'tcpurinit', 'tcpuwinit', 'tcplrinit', 'tcplwinit', 'tcpinfo',
             'sleep', 'tcpclose_xyz']
    strtab = b'\0' + b''.join(n.encode() + b'\0' for n in names)
    so = {n: strtab.index(b'\0' + n.encode() + b'\0') + 1 for n in names}
    w = b'\x4e\x56\x00\x00\x4e\xb9\0\0\0\0\x4e\x5e\x4e\x75'
    t = code + w + b'\x4e\x75'
    lw = len(code)
    d = bytes(28 * 4 + 16)
    ix = {}
    sym = bytes(16)
    defs = [('tcpclose', 0, 1, 0x12), ('tcpclose_lg', lw if lg else 0, 1 if lg else 0, 0x12),
            ('tcpopen', lw + len(w), 1, 0x12), ('tcpurinit', 0, 2, 0x01), ('tcpuwinit', 28, 2, 0x01),
            ('tcplrinit', 56, 2, 0x01), ('tcplwinit', 84, 2, 0x01), ('tcpinfo', 112, 2, 0x11), ('sleep', 0, 0, 0x10),
            ('tcpclose_xyz', 0, 0, 0x10)]
    for k, (n, v, x, info) in enumerate(defs):
        ix[n] = k + 1
        sym += struct.pack('>IIIBBH', so[n], v, 0, info, 0, x)
    rt = struct.pack('>IIi', 6, (ix['sleep'] << 8) | 1, 0)
    if lgcall:
        rt += struct.pack('>IIi', lw + 6, (ix['tcpclose'] << 8) | 1, 0)
    rd_ = b''
    for q, base in (('tcpurinit', 0), ('tcpuwinit', 28), ('tcplrinit', 56), ('tcplwinit', 84)):
        rd_ += struct.pack('>IIi', base + QI_QOPEN, (ix[qopen if q == 'tcpurinit' else 'tcpopen'] << 8) | 1, 0)
        rd_ += struct.pack('>IIi', base + QI_QCLOSE, (ix[qclose if q == 'tcpurinit' else 'tcpclose'] << 8) | 1, 0)
    for k, q in enumerate((rd, 'tcpuwinit', 'tcplrinit', 'tcplwinit')):
        rd_ += struct.pack('>IIi', 112 + 4 * k, (ix[q] << 8) | 1, 0)
    if extra:
        rd_ += struct.pack('>IIi', extra[0], (ix[extra[1]] << 8) | 1, 0)
    shstr = b'\0.text\0.data\0.rela.text\0.rela.data\0.symtab\0.strtab\0.shstrtab\0'
    sn = lambda n: shstr.index(b'\0' + n + b'\0') + 1
    body = [t, d, rt, rd_, sym, strtab, shstr]
    pos, offs = 52, []
    for x in body:
        offs.append(pos)
        pos += (len(x) + 3) & ~3
    data = bytearray(struct.pack('>4sBBBB8xHHIIIIIHHHHHH', b'\x7fELF', 1, 2, 1, 0, 1, 4, 1, 0, 0, pos, 0, 52,
                                 0, 0, 40, 8, 7))
    for x in body:
        data += x + bytes(((len(x) + 3) & ~3) - len(x))
    sh = [(0,) * 10, (sn(b'.text'), 1, 6, 0, offs[0], len(t), 0, 0, 2, 0),
          (sn(b'.data'), 1, 3, 0, offs[1], len(d), 0, 0, 4, 0),
          (sn(b'.rela.text'), 4, 0, 0, offs[2], len(rt), 5, 1, 4, 12),
          (sn(b'.rela.data'), 4, 0, 0, offs[3], len(rd_), 5, 2, 4, 12),
          (sn(b'.symtab'), 2, 0, 0, offs[4], len(sym), 6, 1, 4, 16),
          (sn(b'.strtab'), 3, 0, 0, offs[5], len(strtab), 0, 0, 1, 0),
          (sn(b'.shstrtab'), 3, 0, 0, offs[6], len(shstr), 0, 0, 1, 0)]
    for s in sh:
        data += struct.pack('>IIIIIIIIII', *s)
    open(path, 'wb').write(data)


SYNTH = {'15647f34e06104fe1ecaa9418dae48618f6cd683dd1a6b3b4bb50c531390bddb'}   # synth()'s tcpclose, pinned


def selftest():
    """each check is shown to refuse on its own: every case asserts the refusal's own message"""
    def run(args, known=SYNTH):
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                main(args, known)
            return ''
        except SystemExit as e:
            return str(e.code)

    d = tempfile.mkdtemp()
    p = os.path.join(d, 'unix')
    try:
        synth(p)
        assert 'still names the stock tcpclose' in run(['--check', p]), 'the stock object passed --check'
        assert run([p]) == '', 'the stock object was not retargeted'
        new = open(p, 'rb').read()
        assert run(['--check', p]) == '', 'the retargeted object failed --check'
        assert run([p]) == '' and open(p, 'rb').read() == new, 'a second run changed the object'
        cases = [
            ('not the stock code', dict(code=b'\x4e\x56\x00\x00\x4e\xb9\0\0\0\0\x4e\x5e\x4e\x71')),
            ('definitions of tcpclose_lg', dict(lg=False)),
            ('tcpclose_lg does not call tcpclose', dict(lgcall=False)),
            ('st_rdinit does not name tcpurinit', dict(rd='tcpuwinit')),
            ('qi_qopen is not tcpopen', dict(qopen='tcpclose')),
            ('not the stock close', dict(qclose='tcpclose_xyz')),
        ]
        for msg, kw in cases:
            synth(p, **kw)
            before = open(p, 'rb').read()
            r = run([p])
            assert msg in r and open(p, 'rb').read() == before, 'case %r: %r' % (msg, r)
        synth(p, extra=(4, 'tcpclose_lg'))      # a second name of tcpclose_lg (tcpurinit's qi_srvp)
        run([p])
        assert 'not from tcpurinit alone' in run(['--check', p]), 'a second tcpclose_lg was not refused'
        synth(p, extra=(116 + 16, 'tcpclose'))  # tcpclose named from outside the qinits' closes
        run([p])
        assert 'not the other three qinits' in run(['--check', p]), 'a fourth tcpclose was not refused'
        assert 'not the stock code' in run([p], known=KNOWN), 'the synthetic tcpclose passed as the real one'
    finally:
        if os.path.exists(p):
            os.remove(p)
        os.rmdir(d)
    print('tcpclose-retarget selftest: stock -> retargeted, idempotent; 9 refusals -- OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
