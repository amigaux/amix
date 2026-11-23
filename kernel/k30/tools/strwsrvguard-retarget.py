#!/usr/bin/env python3
"""strwsrvguard-retarget.py -- the stream head write qinit's service procedure strwsrv -> strwsrv_guarded.

  strwsrvguard-retarget.py UNIX           patch the linked ET_REL kernel in place (idempotent)
  strwsrvguard-retarget.py --check UNIX   verify, write nothing; exit 1 unless the kernel is retargeted
  strwsrvguard-retarget.py --stock UNIX   verify, write nothing; exit 1 unless stwdata still names strwsrv (the only
                                          name of it besides strwsrv_guarded's call) and nothing names strwsrv_guarded

src/strwsrvguard030.c defines strwsrv_guarded, which calls the stock strwsrv at splstr and sets QWANTW (QB_WANTW)
again on a forward queue (band) that is full once more after its back-enable.  Stock names strwsrv from exactly
one relocation, stwdata's qi_srvp (the stream head write side's qinit); it is found by symbol, never by a fixed
address, and must be the only one.  Only its symbol index changes: no byte of .text or .data moves.  The check
wants strwsrv named only from strwsrv_guarded's own call and strwsrv_guarded named only from stwdata.
"""
import struct, sys

SHT_SYMTAB, SHT_RELA = 2, 4
NAME = 'strwsrvguard-retarget'


def load(path):
    b = bytearray(open(path, 'rb').read())
    if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or struct.unpack_from('>H', b, 16)[0] != 1:
        sys.exit('%s: %s is not an ELF32 big-endian ET_REL' % (NAME, path))
    shoff, = struct.unpack_from('>I', b, 32)
    shentsize, shnum = struct.unpack_from('>HH', b, 46)
    sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
    symtab = [s for s in sh if s[1] == SHT_SYMTAB]
    if len(symtab) != 1:
        sys.exit('%s: %d symbol tables' % (NAME, len(symtab)))
    st = symtab[0]
    stroff = sh[st[6]][4]
    syms = []
    for i in range(st[5] // 16):
        name, value, size, info, other, shndx = struct.unpack_from('>IIIBBH', b, st[4] + 16 * i)
        syms.append((bytes(b[stroff + name:b.index(0, stroff + name)]).decode(), value, shndx, info))
    return b, sh, syms


def index_of(syms, name, need=True):
    hits = [i for i, s in enumerate(syms) if s[0] == name and s[2] != 0]
    if len(hits) != 1 and (need or hits):
        sys.exit('%s: %d defined symbols named %s' % (NAME, len(hits), name))
    return hits[0] if hits else None


def users(b, sh, syms, target):
    """(rela entry file offset, containing symbol) for every .rela entry against `target`."""
    out = []
    ti = [i for i, s in enumerate(syms) if s[0] == target]
    for s in sh:
        if s[1] != SHT_RELA:
            continue
        sec = s[7]                                   # sh_info: the section the relocations apply to
        named = sorted((v, n) for n, v, x, info in syms if x == sec and n and (info & 15) in (0, 1, 2))
        for o in range(s[4], s[4] + s[5], 12):
            off, info, add = struct.unpack_from('>IIi', b, o)
            if info >> 8 in ti:
                fn = [n for v, n in named if v <= off]
                out.append((o, fn[-1] if fn else '?'))
    return out


def main():
    mode = sys.argv[1] if sys.argv[1:2] in (['--check'], ['--stock']) else None
    rest = sys.argv[2:] if mode else sys.argv[1:]
    if len(rest) != 1:
        sys.exit(__doc__)
    path = rest[0]
    b, sh, syms = load(path)
    index_of(syms, 'strwsrv')
    index_of(syms, 'stwdata')
    guarded = index_of(syms, 'strwsrv_guarded', need=mode != '--stock')
    plain = sorted(fn for o, fn in users(b, sh, syms, 'strwsrv'))
    done = sorted(fn for o, fn in users(b, sh, syms, 'strwsrv_guarded')) if guarded is not None else []
    if mode == '--stock':
        ok = [fn for fn in plain if fn != 'strwsrv_guarded'] == ['stwdata'] and not done
        print('%s: strwsrv named from %s; strwsrv_guarded from %s -- %s'
              % (NAME, plain or 'nowhere', done or 'nowhere', 'STOCK' if ok else 'NOT STOCK'))
        sys.exit(0 if ok else 1)
    if mode == '--check':
        ok = plain == ['strwsrv_guarded'] and done == ['stwdata']
        print('%s: strwsrv_guarded named from %s; strwsrv from %s -- %s'
              % (NAME, done or 'nowhere', plain or 'nowhere', 'OK' if ok else 'NOT RETARGETED'))
        sys.exit(0 if ok else 1)
    todo = [(o, fn) for o, fn in users(b, sh, syms, 'strwsrv') if fn != 'strwsrv_guarded']
    if not todo:
        if done == ['stwdata']:
            print('%s: already retargeted' % NAME)
            return
        sys.exit('%s: nothing names strwsrv outside strwsrv_guarded, and stwdata does not name strwsrv_guarded' % NAME)
    if [fn for o, fn in todo] != ['stwdata']:
        sys.exit('%s: strwsrv named from %s, want exactly stwdata' % (NAME, sorted(fn for o, fn in todo)))
    o = todo[0][0]
    off, info, add = struct.unpack_from('>IIi', b, o)
    struct.pack_into('>IIi', b, o, off, (guarded << 8) | (info & 0xff), add)
    open(path, 'wb').write(b)
    print('%s: 1 relocation strwsrv -> strwsrv_guarded, in stwdata (qi_srvp)' % NAME)


if __name__ == '__main__':
    main()
