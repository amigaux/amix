#!/usr/bin/env python3
"""mksym030.py -- unix.sym, the symbols of a brel kernel (kernel/dlm C2-3 version 6 §2.1), for the booted kernel's namelist.

    mksym030.py ETREL OUT
    mksym030.py --check ETREL SYM KSYM0      KSYM0: ksymgate.py --extract AXREL ETREL 0 KSYM0 (dlm_ksym bound at 0);
                                             SYM: this tool's file or kernel/dlm's nlmake's (either C2-3 form)
    mksym030.py --selftest

ETREL is the final kernel before elf2brel; the brel is elf2brel's conversion of it, and this tool runs that same
conversion (tools/elf2brel.py) to take every symbol's value as the brel lays it with the kernel bound at 0: text,
rodata and data as the image, bss and COMMON past it as the converter placed them, etext/edata/end as it stamps them.
OUT is an ELF32 big-endian m68k ET_REL with only .symtab, .strtab and .shstrtab: every defined symbol (not the
section and file symbols) SHN_ABS at that value, with the ETREL's name, binding, type and size; undefined names are
left out, but for etext/edata/end as the converter stamps them. --check: `end` is the image size plus elf2brel's bss, and every name of the kernel's symbol block (dlm_ksym,
C3-2), as the loader's relocator leaves it bound at 0, has the value OUT gives it. Exit 0 good, 1 a mismatch.
"""
import importlib.util, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SHN_ABS = 0xfff1
STT_SECTION, STT_FILE = 3, 4


def load_e2b():
    spec = importlib.util.spec_from_file_location('elf2brel', os.path.join(HERE, 'elf2brel.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def bound_symbols(etrel):
    """[(name, value, size, info)] for every defined symbol, with the brel bound at 0; and (image size, bss)"""
    d = open(etrel, 'rb').read()
    c = load_e2b().Elf2Brel(d, whoami='mksym030')
    c.convert()
    out = []
    for k in range(1, c.nsyms):
        info = d[c.symoff + k * 16 + 12]
        name = c._symname(k)
        # undefined names are left out, but for etext/edata/end, which the converter stamps
        if (c.sym_shndx_in[k] == 0 and name not in ('etext', 'edata', 'end')) or (info & 15) in (STT_SECTION, STT_FILE):
            continue
        out.append((name, c.sym_value[k], c.sym_size[k], info))
    return out, c.textsize + c.rodatasize + c.datasize, c.bsssize


def write(syms, path):
    strtab, offs = bytearray(b'\0'), []
    for n, *_ in syms:
        offs.append(len(strtab))
        strtab += n.encode('latin-1') + b'\0'
    symtab = bytearray(16)
    nlocal = 1
    order = sorted(range(len(syms)), key=lambda i: (syms[i][3] >> 4) != 0)   # locals first, as ELF wants
    for i in order:
        n, val, sz, info = syms[i]
        if info >> 4 == 0:
            nlocal += 1
        symtab += struct.pack('>IIIBBH', offs[i], val, sz, info, 0, SHN_ABS)
    shstr = b'\0.symtab\0.strtab\0.shstrtab\0'
    blobs = [bytes(symtab), bytes(strtab), shstr]
    off, at = [], 52
    for b in blobs:
        off.append(at)
        at += len(b)
    at = (at + 3) & ~3
    hdr = bytearray(52)
    hdr[0:16] = b'\x7fELF\x01\x02\x01' + bytes(9)
    struct.pack_into('>HHIIIIIHHHHHH', hdr, 16, 1, 4, 1, 0, 0, at, 0, 52, 0, 0, 40, 4, 3)
    sh = bytes(40)
    sh += struct.pack('>10I', 1, 2, 0, 0, off[0], len(blobs[0]), 2, nlocal, 4, 16)    # .symtab, link .strtab
    sh += struct.pack('>10I', 9, 3, 0, 0, off[1], len(blobs[1]), 0, 0, 1, 0)          # .strtab
    sh += struct.pack('>10I', 17, 3, 0, 0, off[2], len(blobs[2]), 0, 0, 1, 0)         # .shstrtab
    body = bytes(hdr) + b''.join(blobs)
    open(path, 'wb').write(body + bytes(at - len(body)) + sh)


def read(path):
    """name -> (address bound at 0, size, info) from a unix.sym in either C2-3 form: SHN_ABS symbols (this tool's), or
    symbols in NOBITS sections placed at their layout offsets (kernel/dlm's nlmake, an EXEC file: st_value is the
    address already)"""
    b = open(path, 'rb').read()
    shoff, = struct.unpack('>I', b[32:36])
    shnum, = struct.unpack('>H', b[48:50])
    sh = [struct.unpack('>10I', b[shoff + 40 * i:shoff + 40 * i + 40]) for i in range(shnum)]
    tab = next(s for s in sh if s[1] == 2)   # SHT_SYMTAB
    so, ssz, st = tab[4], tab[5], sh[tab[6]][4]
    out = {}
    for k in range(1, ssz // 16):
        nm, val, sz, info, oth, shn = struct.unpack('>IIIBBH', b[so + 16 * k:so + 16 * k + 16])
        if shn == 0:
            continue
        name = b[st + nm:b.index(b'\0', st + nm)].decode('latin-1')
        # a name can be a file's static (t) and the kernel's global (T) at once -- three static delay()s beside the
        # global the core tier exports (S5-10): the global is the one the symbol block names, so it wins over a local
        if name not in out or (out[name][2] >> 4 == 0 and info >> 4 != 0):
            out[name] = (val, sz, info)
    return out


def ksym_names(path):
    """name -> value from a dlm_ksym block (C3-2, version 2) as extracted at bind 0"""
    blk = open(path, 'rb').read()
    u = lambda o: struct.unpack('>I', blk[o:o + 4])[0]
    nsym, so, stro = u(8), u(12), u(16)
    out = {}
    for i in range(1, nsym):
        e = so + 16 * i
        out[blk[stro + u(e):blk.index(b'\0', stro + u(e))].decode()] = u(e + 4)
    return out, u(28), u(32)


def check(etrel, sym, ksym0):
    s = read(sym)
    _, image, bss = bound_symbols(etrel)
    bad = []
    if 'end' not in s or s['end'][0] != image + bss:
        bad.append('end is %s, the image %d + bss %d = %d' % (s.get('end', (None,))[0], image, bss, image + bss))
    names, lo, hi = ksym_names(ksym0)
    for n, v in sorted(names.items()):
        if n not in s:
            bad.append('%s (in dlm_ksym) is not in %s' % (n, sym))
        elif s[n][0] != v:
            bad.append('%s: dlm_ksym 0x%x, %s 0x%x' % (n, v, os.path.basename(sym), s[n][0]))
    if hi != image + bss:
        bad.append('dlm_ksym kh_hi 0x%x is not end 0x%x' % (hi, image + bss))
    for b in bad:
        print('  [FAIL] ' + b)
    print('mksym030: %s: %d symbols; %d dlm_ksym names agree; end 0x%x = image %d + bss %d%s'
          % (sym, len(s), len(names) - sum(1 for b in bad if b.split(':')[0] in names), image + bss, image, bss,
             '' if not bad else ' -- %d MISMATCH(ES)' % len(bad)))
    return 0 if not bad else 1


def selftest():
    import tempfile
    print('mksym030 selftest')
    n = f = 0

    def ok(name, c):
        nonlocal n, f
        n += 1
        f += 0 if c else 1
        print('  %s %s' % ('ok  ' if c else 'FAIL', name))
    d = tempfile.mkdtemp()
    p = os.path.join(d, 'unix.sym')
    syms = [('stext', 0, 0, 0x10), ('main', 0x100, 0x40, 0x12), ('lstat', 0x200, 8, 0x01), ('end', 0x9000, 0, 0x10)]
    write(syms, p)
    r = read(p)
    ok('round trip: every name, value, size and kind', all(r[nm] == (v, s, i) for nm, v, s, i in syms))
    p2 = os.path.join(d, 'dup.sym')
    write([('delay', 0x508c, 4, 0x02), ('delay', 0x10b0e, 4, 0x02), ('delay', 0x3e34e, 8, 0x12), ('end', 0x9000, 0, 0x10)], p2)
    ok('a global wins over same-named locals (the static delay()s, S5-10)', read(p2)['delay'] == (0x3e34e, 8, 0x12))
    b = open(p, 'rb').read()
    ok('ELF32 big-endian m68k, SHN_ABS symbols', b[:6] == b'\x7fELF\x01\x02' and struct.unpack('>H', b[18:20])[0] == 4
       and all(struct.unpack('>H', b[52 + 16 * k + 14:52 + 16 * k + 16])[0] == SHN_ABS for k in range(1, 5)))
    shoff, = struct.unpack('>I', b[32:36])
    nlocal = struct.unpack('>I', b[shoff + 40 + 28:shoff + 40 + 32])[0]
    ok('locals first; .symtab sh_info = the first global', nlocal == 2 and b[52 + 16 + 12] >> 4 == 0)
    blk = bytearray(64)
    for o, v in ((0, 0x4b53594d), (4, 2), (8, 3), (12, 64), (28, 0), (32, 0x9000)):
        struct.pack_into('>I', blk, o, v)
    blk += struct.pack('>IIIBBH', 0, 0, 0, 0, 0, 0) + struct.pack('>IIIBBH', 1, 0x100, 0, 0x12, 0, 0)
    blk += struct.pack('>IIIBBH', 6, 0x200, 0, 0x11, 0, 0) + b'\0main\0lstat\0'
    struct.pack_into(">I", blk, 16, 112)
    kp = os.path.join(d, 'ksym0.bin')
    open(kp, 'wb').write(bytes(blk))
    names, lo, hi = ksym_names(kp)
    ok('a dlm_ksym block is read by name', names == {'main': 0x100, 'lstat': 0x200} and hi == 0x9000)
    print('mksym030: %d checks, %d failed' % (n, f))
    print('mksym030: SELFTEST PASS' if f == 0 else 'mksym030: SELFTEST FAIL')
    return 0 if f == 0 else 1


def main(argv):
    if argv[:1] == ['--selftest']:
        return selftest()
    if argv[:1] == ['--check'] and len(argv) == 4:
        return check(argv[1], argv[2], argv[3])
    if len(argv) != 2:
        raise SystemExit(__doc__)
    syms, image, bss = bound_symbols(argv[0])
    write(syms, argv[1])
    print('mksym030: %s: %d symbols, image %d + bss %d' % (argv[1], len(syms), image, bss))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
