#!/usr/bin/env python3
"""rmwfault030.py -- a read-modify-write's fault is a write fault (the linked 68030 kernel).

  rmwfault030.py UNIX           patch the linked ET_REL kernel in place (idempotent)
  rmwfault030.py --check UNIX   verify, write nothing; exit 1 unless both sites are patched
  rmwfault030.py --stock UNIX   verify, write nothing; exit 1 unless both sites are stock

The read half of a tas or cas checks write permission, so it can fault on a page a read would be allowed on, with the
SSW's RM and RW bits both set.  usrxmemflt decides from RW alone:

  rw      RW set means S_READ, so the page is brought in read-only and no copy on write is done;
  F_PROT  taken only when DF is set and RW clear, so the protection fault goes to hardbus instead, whose bprobe finds a
          good page and returns with no signal.

So the instruction restarts for ever: on a read-only page, where it should get SIGSEGV, and on a private page not yet
written or shared by fork, where it should succeed.  In both places RM now counts as a write, and only a plain read stays
a read.  Each site keeps its length, its branch and its branch's displacement:

  moveq #64,%d0; andl %a0@(72),%d0; addqw #8,%sp; tstl %d0; beqw write
    ->  moveb %a0@(75),%d0; addqw #8,%sp; lsrb #6,%d0; subqb #1,%d0; bnew write      (RM,RW == 0,1 is a read)

  andil #0x140,%d0; cmpil #0x100,%d0; bnew hardbus
    ->  nop; lsrl #6,%d0; moveq #7,%d1; andl %d1,%d0; moveq #-48,%d1; btst %d0,%d1; beqw hardbus
                                                                  (DF,RM,RW of 100, 110 or 111: mask 0xd0)

Neither %d0 nor %d1 is live past either site.  The other SSW values go as stock, so only a fault with RM and RW both set
decides differently, and a chip that reports a read half any other way gets what stock gave it.  The bits as read here are
the emulator's and the manual's; no real 68030 has run this.  Both sites are found by function and
instruction pattern, and must match exactly once.
"""
import struct
import sys

SHT_SYMTAB = 2
FUNC = 'usrxmemflt'
SITES = (
    ('rw', '7040c0a80048504f4a806700000c', '1028004b504fec0853006600000c'),
    ('fprot', '0280000001400c80000001006600008c', '4e71ec887207c08172d001016700008c'),
)


def die(msg):
    sys.exit('rmwfault030: ' + msg)


def area(b):
    """(file offset, bytes) of usrxmemflt"""
    if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or struct.unpack_from('>H', b, 16)[0] != 1:
        die('not an ELF32 big-endian ET_REL')
    shoff, = struct.unpack_from('>I', b, 32)
    shentsize, shnum, shstrndx = struct.unpack_from('>HHH', b, 46)
    sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
    names = sh[shstrndx][4]
    text = [bytes(b[names + s[0]:b.index(0, names + s[0])]).decode() for s in sh].index('.text')
    st = [s for s in sh if s[1] == SHT_SYMTAB]
    if len(st) != 1:
        die('%d symbol tables' % len(st))
    strs = sh[st[0][6]][4]
    hits = []
    for i in range(st[0][5] // 16):
        name, value, size, info, other, shndx = struct.unpack_from('>IIIBBH', b, st[0][4] + 16 * i)
        if bytes(b[strs + name:b.index(0, strs + name)]) == FUNC.encode() and shndx == text and info & 15 == 2:
            hits.append((value, size))
    if len(hits) != 1 or not hits[0][1]:
        die('%d functions named %s, or no size' % (len(hits), FUNC))
    lo = sh[text][4] + hits[0][0]
    return lo, bytes(b[lo:lo + hits[0][1]])


def main():
    mode = sys.argv[1] if sys.argv[1:2] in (['--check'], ['--stock']) else None
    path = sys.argv[2] if mode and len(sys.argv) == 3 else (sys.argv[1] if not mode and len(sys.argv) == 2 else None)
    if not path:
        sys.exit(__doc__)
    b = bytearray(open(path, 'rb').read())
    lo, code = area(b)
    st, edits = {}, []
    for name, stock, new in SITES:
        s, n = bytes.fromhex(stock), bytes.fromhex(new)
        a, c = code.count(s), code.count(n)
        if a + c != 1:
            die('%s: %d x the stock %s site and %d x its patched form (want one)' % (FUNC, a, name, c))
        st[name] = 'stock' if a else 'rmw'
        if a:
            edits.append((lo + code.index(s), n))
    desc = ' '.join('%s=%s' % kv for kv in sorted(st.items()))
    if mode:
        ok = all(v == ('stock' if mode == '--stock' else 'rmw') for v in st.values())
        print('rmwfault030: %s -- %s' % (desc, 'OK' if ok else 'NOT ' + mode[2:]))
        sys.exit(0 if ok else 1)
    if not edits:
        print('rmwfault030: already patched')
        return
    if len(edits) != len(SITES):
        die('a kernel half way: %s' % desc)
    for at, data in edits:
        b[at:at + len(data)] = data
    with open(path, 'wb') as f:
        f.write(b)
    print('rmwfault030: 2 sites in %s: RM counts as a write' % FUNC)


if __name__ == '__main__':
    main()
