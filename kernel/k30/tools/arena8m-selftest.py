#!/usr/bin/env python3
"""arena8m-selftest.py -- arena8m030.py, kmemwake030.py and rmwfault030.py on a small made-up ET_REL: each patches a good kernel,
refuses a kernel it does not understand, and its --check tells the states apart.  Needs no input from outside."""
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ARENA, WAKE = os.path.join(HERE, 'arena8m030.py'), os.path.join(HERE, 'kmemwake030.py')
RMW = os.path.join(HERE, 'rmwfault030.py')
fails = 0


def elf(funcs, data=b'', abss=(), locals_=(), commons=(), v_proc=200):
    """funcs: {name: (bytes, [(offset in it, symbol)])}"""
    names, text, rel = {}, b'', []
    syms = [('', 0, 0, 0, 0)]
    for fn, (code, rels) in funcs.items():
        syms.append((fn, len(text), len(code), 0x12, 1))
        rel += [(len(text) + o, s) for o, s in rels]
        text += code + b'\x4e\x71' * ((4 - len(code) % 4) % 4 // 2)
    syms.append(('v', 0, 64, 0x11, 2))
    data = struct.pack('>III', 0, 0, v_proc) + b'\0' * 52 + data
    syms += [(n, v, 0, 0x10, 0xfff1) for n, v in abss]
    syms += [(n, 0, 32, 0x01, 3) for n in locals_]
    syms += [(n, 4, z, 0x11, 0xfff2) for n, z in commons]
    for s in {t for _, t in rel}:
        if not any(x[0] == s for x in syms):
            syms.append((s, 0, 4, 0x11, 3))
    strtab, st = b'\0', b''
    idx = {}
    for i, (n, v, z, info, shndx) in enumerate(syms):
        off = len(strtab) if n else 0
        if n:
            strtab += n.encode() + b'\0'
        idx[n] = i
        st += struct.pack('>IIIBBH', off, v, z, info, 0, shndx)
    rela = b''.join(struct.pack('>IIi', o, (idx[t] << 8) | 1, 0) for o, t in rel)
    secs = [('', 0, b'', 0, 0, 0), ('.text', 1, text, 0, 0, 0), ('.data', 1, data, 0, 0, 0), ('.bss', 8, b'', 0, 0, 0),
            ('.symtab', 2, st, 5, 1, 16), ('.strtab', 3, strtab, 0, 0, 0), ('.rela.text', 4, rela, 4, 1, 12)]
    shstr = b'\0'
    off = 52
    body, sh = b'', []
    for n, t, d, link, info, ent in secs:
        no = len(shstr) if n else 0
        if n:
            shstr += n.encode() + b'\0'
        sh.append(struct.pack('>10I', no, t, 0, 0, off + len(body), len(d), link, info, 4, ent))
        body += d + b'\0' * (-len(d) % 4)
    no = len(shstr)
    shstr += b'.shstrtab\0'
    sh.append(struct.pack('>10I', no, 3, 0, 0, off + len(body), len(shstr), 0, 0, 1, 0))
    body += shstr + b'\0' * (-len(shstr) % 4)
    h = b'\x7fELF\x01\x02\x01' + b'\0' * 9 + struct.pack('>HHIIIIIHHHHHH', 1, 4, 1, 0, 0, off + len(body), 0, 52, 0, 0, 40,
                                                          len(sh), len(sh) - 1)
    return h + body + b''.join(sh)


def arena(**kw):
    o = dict(seed='48780800', ext='0c81000007ff', length='2f3c00400000', kvsegmap=0x40440000, kvsegu=0x48440000,
             kseg=('ksegtbl', 'ksegtbl'), v_proc=200, syssegs=0x40040000, limit='30bc04ff', t64size=64)
    o.update(kw)
    f = {'mlsetup': (bytes.fromhex('4e71' + o['seed'] + '4e71'), []),
         'sysseginit': (bytes.fromhex(o['ext'] + '6f00ffde'), []),
         'kvm_init': (bytes.fromhex(o['length'] + '4e71'), []),
         'pstart': (bytes.fromhex(o['limit'] + '4e71'), []),
         'kseg': (bytes.fromhex('41f900000000'), [(2, o['kseg'][0])]),
         'unkseg': (bytes.fromhex('45f900000000'), [(2, o['kseg'][1])])}
    return elf(f, abss=(('kvsegmap', o['kvsegmap']), ('kvsegu', o['kvsegu']), ('syssegs', o['syssegs'])), locals_=('ksegtbl',),
               commons=(('ksegtbl64', o['t64size']),) if o.get('t64', True) else (), v_proc=o['v_proc'])


def seq(cmp_op, ble='6f000024', bcs='6500001a'):
    return bytes.fromhex('4ab900000000' + ble + cmp_op + '00000000' + bcs + '42b900000000'), \
        [(2, 'Km_OsizeWanted'), (12, 'Km_OsizeWanted'), (22, 'Km_OsizeWanted')]


def wake(**kw):
    a, b = kw.get('fp', seq('b4b9')), kw.get('f', seq('b8b9'))
    return elf({'kmem_freepool': a, 'kmem_free': b}, abss=())


RMW_RW, RMW_FP = '7040c0a80048504f4a806700000c', '0280000001400c80000001006600008c'
RMW_RW2, RMW_FP2 = '1028004b504fec0853006600000c', '4e71ec887207c08172d001016700008c'


def rmw(a=RMW_RW, b=RMW_FP):
    return elf({'usrxmemflt': (bytes.fromhex('4e71' + a + '4e71' + b + '4e71'), [])}, abss=())


def ssw_says(ssw):
    """run the patched sites by hand: (rw, F_PROT taken) for an SSW's DF, RM and RW; the code is checked literally below"""
    low = ssw & 0xff
    d0 = ((low >> 6) - 1) & 0xff
    rw = 1 if d0 == 0 else 2                        # moveb, lsrb #6, subqb #1, bnew to S_WRITE
    fp = bool(0xd0 >> ((ssw >> 6) & 7) & 1)         # lsrl #6, and 7, moveq #-48, btst, beqw to hardbus
    return rw, fp


def run(tool, *args):
    return subprocess.run([sys.executable, '-I', tool] + list(args), capture_output=True, text=True).returncode


def case(name, ok):
    global fails
    print('%s %s' % ('PASS' if ok else 'FAIL', name))
    fails += not ok


with tempfile.TemporaryDirectory() as d:
    p = os.path.join(d, 'unix')

    def put(b):
        with open(p, 'wb') as f:
            f.write(b)

    put(arena())
    case('arena: a stock kernel is --stock, not --check', run(ARENA, '--stock', p) == 0 and run(ARENA, '--check', p) == 1)
    before = open(p, 'rb').read()
    case('arena: patches', run(ARENA, p) == 0 and run(ARENA, '--check', p) == 0 and run(ARENA, '--stock', p) == 1)
    after = open(p, 'rb').read()
    case('arena: the file keeps its size', len(before) == len(after))
    case('arena: patching again changes nothing', run(ARENA, p) == 0 and open(p, 'rb').read() == after)
    # the values themselves, written out here, not taken from the tool's table
    for want, what in ((bytes.fromhex('48781000'), 'the seed is 0x1000 pages'), (bytes.fromhex('0c8100000fff'), 'the page-table bound is 4095'),
                       (bytes.fromhex('2f3c00800000'), 'the length is 8 MiB'), (struct.pack('>I', 0x40840000), 'kvsegmap is 0x40840000'),
                       (struct.pack('>I', 0x48840000), 'kvsegu is 0x48840000')):
        case('arena: ' + what, want in after and want not in before)
    put(arena(seed='48781000'))
    case('arena: a kernel half way is refused', run(ARENA, p) != 0)
    put(arena(kvsegu=0x48840000))
    case('arena: kvsegu moved alone is refused', run(ARENA, p) != 0)
    put(arena(kvsegmap=0x40500000))
    case('arena: an unknown kvsegmap is refused', run(ARENA, p) != 0)
    put(arena(seed='4e714e71'))
    case('arena: no seed site is refused', run(ARENA, p) != 0)
    put(arena(ext='0c810000ffff'))
    case('arena: no page-table bound is refused', run(ARENA, p) != 0)
    put(arena(length='2f3c00200000'))
    case('arena: another length is refused', run(ARENA, p) != 0)
    put(arena(t64=False))
    case('arena: no ksegtbl64 in the link is refused', run(ARENA, p) != 0 and run(ARENA, '--stock', p) == 0)
    put(arena(kseg=('ksegtbl', 'ksegtbl64')))
    case('arena: kseg and unkseg on different tables is refused', run(ARENA, p) != 0)
    put(arena(syssegs=0x40080000))
    case('arena: syssegs elsewhere is refused', run(ARENA, p) != 0)
    put(arena(limit='30bc03e8'))
    case("arena: another root limit in pstart is refused", run(ARENA, p) != 0)
    put(arena(t64size=32))
    case('arena: a 32-byte ksegtbl64 is refused', run(ARENA, p) != 0)
    put(arena(v_proc=20000))
    case('arena: a map past st_top1 fails its check', run(ARENA, p) == 0 and run(ARENA, '--check', p) == 1)

    put(wake())
    case('wake: stock is --stock, not --check', run(WAKE, '--stock', p) == 0 and run(WAKE, '--check', p) == 1)
    before = open(p, 'rb').read()
    case('wake: patches', run(WAKE, p) == 0 and run(WAKE, '--check', p) == 0)
    after = open(p, 'rb').read()
    case('wake: only the two branches change', sum(x != y for x, y in zip(before, after)) <= 16 and len(before) == len(after))
    case('wake: patching again changes nothing', run(WAKE, p) == 0 and open(p, 'rb').read() == after)
    put(wake(fp=seq('b4b9', '4e714e71', '4e714e71')))
    case('wake: one site patched, the other not, is refused', run(WAKE, p) != 0)
    put(wake(fp=seq('b4b9', '4e714e71')))
    case('wake: one branch patched, the other not, is refused', run(WAKE, p) != 0)
    put(wake(fp=seq('b4b9', bcs='60000000')))
    case('wake: something else in a branch is refused', run(WAKE, p) != 0)
    put(wake(f=seq('b4b9')))
    case('wake: another register in the compare is refused', run(WAKE, p) != 0)
    put(wake(fp=(seq('b4b9')[0] * 2, seq('b4b9')[1] + [(o + 26, s) for o, s in seq('b4b9')[1]])))
    case('wake: two sequences in one function are refused', run(WAKE, p) != 0)
    put(rmw())
    case('rmw: a stock kernel is --stock', run(RMW, '--stock', p) == 0 and run(RMW, '--check', p) != 0)
    case('rmw: it patches', run(RMW, p) == 0 and run(RMW, '--check', p) == 0 and run(RMW, '--stock', p) != 0)
    got = open(p, 'rb').read()
    case('rmw: the bytes are as written, no longer and no shorter',
         bytes.fromhex(RMW_RW2) in got and bytes.fromhex(RMW_FP2) in got and len(got) == len(rmw()))
    case('rmw: a second patch changes nothing', run(RMW, p) == 0 and open(p, 'rb').read() == got)
    put(rmw(a=RMW_RW2))
    case('rmw: one site patched, the other not, is refused', run(RMW, p) != 0)
    put(rmw(a='7040c0a80048504f4a806700000e'))
    case('rmw: another displacement is refused', run(RMW, p) != 0)
    put(rmw(b=RMW_RW))
    case('rmw: a site missing is refused', run(RMW, p) != 0)
    case('rmw: a plain read stays a read and goes to hardbus', ssw_says(0x140) == (1, False))
    case('rmw: a plain write is a write, F_PROT', ssw_says(0x100) == (2, True))
    case('rmw: the read half is a write, F_PROT', ssw_says(0x1c0) == (2, True))
    case('rmw: the write half is a write, F_PROT', ssw_says(0x180) == (2, True))
    case('rmw: no data fault never takes F_PROT',
         not any(ssw_says(v)[1] for v in (0, 0x40, 0x80, 0xc0)) and ssw_says(0x40)[0] == 1 and ssw_says(0)[0] == 2)
sys.exit(1 if fails else 0)
