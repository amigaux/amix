#!/usr/bin/env python3
"""fpugate-sendsig.py -- retarget sendsig's call of fpu_setup to fpu_setup_gated (grimoire quirk 74).

  fpugate-sendsig.py UNIX           patch the linked ET_REL kernel in place (idempotent)
  fpugate-sendsig.py --check UNIX   verify, write nothing; exit 1 if the kernel is not retargeted

sendsig is the one caller of fpu_setup with no fpu_present gate in front of it; src/fpugate030.s defines
fpu_setup_gated.  The relocation of sendsig's `jsr fpu_setup` is found by symbol (the .rela entry naming
fpu_setup whose offset lies inside sendsig), never by a fixed address, and only its symbol index changes:
no byte of .text moves.  Refuses unless exactly one such relocation exists (or, already patched, exactly one
naming fpu_setup_gated), and the check also wants every other caller of fpu_setup untouched.
"""
import struct, sys

SHT_SYMTAB, SHT_RELA = 2, 4


def load(path):
    b = bytearray(open(path, 'rb').read())
    if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or struct.unpack_from('>H', b, 16)[0] != 1:
        sys.exit('fpugate-sendsig: %s is not an ELF32 big-endian ET_REL' % path)
    shoff, = struct.unpack_from('>I', b, 32)
    shentsize, shnum = struct.unpack_from('>HH', b, 46)
    sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
    symtab = [s for s in sh if s[1] == SHT_SYMTAB]
    if len(symtab) != 1:
        sys.exit('fpugate-sendsig: %d symbol tables' % len(symtab))
    st = symtab[0]
    stroff = sh[st[6]][4]
    syms = []
    for i in range(st[5] // 16):
        name, value, size, info, other, shndx = struct.unpack_from('>IIIBBH', b, st[4] + 16 * i)
        syms.append((bytes(b[stroff + name:b.index(0, stroff + name)]).decode(), value, shndx, info))
    return b, sh, syms


def index_of(syms, name):
    hits = [i for i, s in enumerate(syms) if s[0] == name and s[2] != 0]
    if len(hits) != 1:
        sys.exit('fpugate-sendsig: %d defined symbols named %s' % (len(hits), name))
    return hits[0]


def callers(b, sh, syms, target):
    """(rela entry file offset, containing function) for every .rela entry against `target`."""
    out = []
    ti = [i for i, s in enumerate(syms) if s[0] == target]
    for s in sh:
        if s[1] != SHT_RELA:
            continue
        sec = s[7]                                   # sh_info: the section the relocations apply to
        funcs = sorted((v, n) for n, v, x, info in syms if x == sec and n and (info & 15) in (0, 2))
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if info >> 8 in ti:
                fn = [n for v, n in funcs if v <= off]
                out.append((o, fn[-1] if fn else '?'))
    return out


def main():
    check = sys.argv[1:2] == ['--check']
    path = sys.argv[2] if check else (sys.argv[1] if len(sys.argv) == 2 else None)
    if not path:
        sys.exit(__doc__)
    b, sh, syms = load(path)
    gated = index_of(syms, 'fpu_setup_gated')
    index_of(syms, 'fpu_setup')
    plain = [fn for o, fn in callers(b, sh, syms, 'fpu_setup')]
    to_gate = [(o, fn) for o, fn in callers(b, sh, syms, 'fpu_setup') if fn == 'sendsig']
    done = [fn for o, fn in callers(b, sh, syms, 'fpu_setup_gated')]
    if check:
        ok = done == ['sendsig'] and 'sendsig' not in plain and plain
        print('fpugate-sendsig: fpu_setup_gated called from %s; fpu_setup from %s -- %s'
              % (done or 'nowhere', sorted(plain) or 'nowhere', 'OK' if ok else 'NOT RETARGETED'))
        sys.exit(0 if ok else 1)
    if done == ['sendsig'] and not to_gate:
        print('fpugate-sendsig: already retargeted')
        return
    if len(to_gate) != 1 or done:
        sys.exit('fpugate-sendsig: sendsig has %d relocations against fpu_setup and fpu_setup_gated has callers %s'
                 % (len(to_gate), done))
    o = to_gate[0][0]
    off, info, add = struct.unpack_from('>IIi', b, o)
    struct.pack_into('>IIi', b, o, off, (gated << 8) | (info & 0xff), add)
    open(path, 'wb').write(b)
    print('fpugate-sendsig: sendsig+%#x: jsr fpu_setup -> fpu_setup_gated (relocation symbol %d -> %d)'
          % (off - [v for n, v, x, i in syms if n == 'sendsig'][0], info >> 8, gated))


if __name__ == '__main__':
    main()
