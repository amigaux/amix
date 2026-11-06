#!/usr/bin/env python3
"""arena8m030.py -- kvseg from 4 MiB to 8 MiB in the linked 68030 kernel (2 KiB pages).

  arena8m030.py UNIX           patch the linked ET_REL kernel in place (idempotent)
  arena8m030.py --check UNIX   verify, write nothing; exit 1 unless every site holds the 8 MiB layout
  arena8m030.py --stock UNIX   verify, write nothing; exit 1 unless every site holds the 4 MiB layout

kvseg (syssegs..kvsegmap, handed out through sptmap) is a fixed 4 MiB: kvm_init's page array takes 60 bytes per page
of memory from it, and kmem's pools and every kmem request over 4 KiB take the rest, so at 64 MB little is left.  The
one quantity lives at several sites, which must move together (seed <= page-table extent <= arena), and the segmap
window above it must keep its width:

  mlsetup     mfree(sptmap, 0x800, ...)           -> 0x1000   the map's seed, in pages
  sysseginit  cmpil #2047,%d1                     -> #4095    the page tables behind it: 32 -> 64 tables of 256 bytes,
                                                              8 KiB more low memory; its return value follows
  kvm_init    seg_attach(&kas, syssegs, 0x400000) -> 0x800000 the segment's length, in bytes
  kvsegmap    0x40440000 -> 0x40840000 (SHN_ABS)              the arena's top, the segmap window's floor
  kvsegu      0x48440000 -> 0x48840000 (SHN_ABS)              the window's ceiling: kvm_init sizes segkmap from memory
  ksegtbl     kseg's and unkseg's relocations -> ksegtbl64

ksegtbl holds one byte per kseg run, indexed by (va - syssegs) >> 17: kseg aligns its runs to 64 pages, 128 KiB here.
The stock table has 32 bytes, for 4 MiB, so a run above it would write past the table.  src/arena8m030.c's ksegtbl64
has 64.  The index, the alignment and the code stay as they are.

Every site is found by name and instruction pattern, never by address, and must match exactly once.  The kernel's
virtual map must still fit st_top1: pstart's root descriptor limits it to 1280 entries of 128 KiB, and syssegs itself
must be where the layout says.
"""
import struct
import sys

SHN_ABS = 0xfff1
SHT_SYMTAB, SHT_RELA = 2, 4
ST_TOP1_ENTRIES = 1280
STOP1_MOVEW = bytes.fromhex('30bc')           # movew #limit,%a0@
SYSSEGS = 0x40040000
KSEGTBL_SIZE = 64
SDE_SHIFT = 17

ABS = (('kvsegmap', 0x40440000, 0x40840000), ('kvsegu', 0x48440000, 0x48840000))
TEXT = (
    # function, stock bytes, 8 MiB bytes, what they are
    ('mlsetup', '48780800', '48781000', 'pea 0x800'),
    ('sysseginit', '0c81000007ff', '0c8100000fff', 'cmpil #2047,%d1'),
    ('kvm_init', '2f3c00400000', '2f3c00800000', 'movel #0x400000,%sp@-'),
)
KSEG = ('kseg', 'unkseg')


def die(msg):
    sys.exit('arena8m030: ' + msg)


class Kernel:
    def __init__(self, path):
        self.path = path
        self.b = b = bytearray(open(path, 'rb').read())
        if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or struct.unpack_from('>H', b, 16)[0] != 1:
            die('%s is not an ELF32 big-endian ET_REL' % path)
        shoff, = struct.unpack_from('>I', b, 32)
        shentsize, shnum, shstrndx = struct.unpack_from('>HHH', b, 46)
        self.sh = [struct.unpack_from('>IIIIIIIIII', b, shoff + i * shentsize) for i in range(shnum)]
        names = self.sh[shstrndx][4]
        self.secname = [bytes(b[names + s[0]:b.index(0, names + s[0])]).decode() for s in self.sh]
        self.text = self.secname.index('.text')
        self.data = self.secname.index('.data')
        st = [s for s in self.sh if s[1] == SHT_SYMTAB]
        if len(st) != 1:
            die('%d symbol tables' % len(st))
        self.symoff = st[0][4]
        stroff = self.sh[st[0][6]][4]
        self.syms = []
        for i in range(st[0][5] // 16):
            name, value, size, info, other, shndx = struct.unpack_from('>IIIBBH', b, self.symoff + 16 * i)
            self.syms.append((bytes(b[stroff + name:b.index(0, stroff + name)]).decode(), value, size, info, shndx))

    def index(self, name):
        hits = [i for i, s in enumerate(self.syms) if s[0] == name and s[4] != 0]
        if len(hits) != 1:
            die('%d defined symbols named %s' % (len(hits), name))
        return hits[0]

    def func(self, name):
        hits = [s for s in self.syms if s[0] == name and s[4] == self.text and s[3] & 15 == 2]
        if len(hits) != 1:
            die('%d functions named %s' % (len(hits), name))
        off = self.sh[self.text][4] + hits[0][1]
        return off, off + hits[0][2]

    def text_site(self, func, stock, new, what):
        """the file offset of the one matching site; which layout it holds"""
        lo, hi = self.func(func)
        area = bytes(self.b[lo:hi])
        s, n = bytes.fromhex(stock), bytes.fromhex(new)
        a, c = area.count(s), area.count(n)
        if a + c != 1:
            die('%s: %d x %s and %d x its 8 MiB form (want one site)' % (func, a, what, c))
        return lo + area.index(s if a else n), n if a else None

    def relocs_against(self, names):
        """(rela entry's file offset, containing function, target name) for .rela.text entries against names"""
        want = {i: s[0] for i, s in enumerate(self.syms) if s[0] in names and s[4] != 0}
        funcs = sorted((s[1], s[0]) for s in self.syms if s[4] == self.text and s[3] & 15 == 2)
        out = []
        for s in self.sh:
            if s[1] != SHT_RELA or s[7] != self.text:
                continue
            for o in range(s[4], s[4] + s[5], 12):
                off, info, add = struct.unpack_from('>IIi', self.b, o)
                if info >> 8 in want:
                    fn = [n for v, n in funcs if v <= off]
                    if add != 0:
                        die('a relocation against %s has an addend' % want[info >> 8])
                    out.append((o, fn[-1] if fn else '?', want[info >> 8]))
            return out
        die('no .rela.text')

    def st_top1_limit(self):
        """the entries pstart's root descriptor gives st_top1: its one movew #limit,... before the tc load"""
        lo, hi = self.func('pstart')
        area = bytes(self.b[lo:hi])
        hits = [i for i in range(len(area) - 3) if area[i:i + 2] == STOP1_MOVEW and
                struct.unpack_from('>H', area, i + 2)[0] == ST_TOP1_ENTRIES - 1]
        if len(hits) != 1:
            die('pstart: %d x movew #%d (want one root limit)' % (len(hits), ST_TOP1_ENTRIES - 1))
        return ST_TOP1_ENTRIES

    def segu_end(self):
        """st_top1 entries the map needs: kvsegu's index + susegs, as kvm_init works them out from v.v_proc"""
        kvsegu = self.syms[self.index('kvsegu')][1]
        v = self.syms[self.index('v')]
        if v[4] != self.data:
            die('v is not in .data')
        v_proc, = struct.unpack_from('>I', self.b, self.sh[self.data][4] + v[1] + 8)
        return ((kvsegu >> SDE_SHIFT) & 0x1fff) + ((v_proc * 4 + 63) >> 6)


def state(k, check):
    """{site: 'stock' | '8m'}, and the edits that make it 8 MiB"""
    st, edits = {}, []
    for fn, stock, new, what in TEXT:
        off, repl = k.text_site(fn, stock, new, what)
        st[fn] = 'stock' if repl else '8m'
        if repl:
            edits.append((off, repl))
    for name, old, new in ABS:
        i = k.index(name)
        value, shndx = k.syms[i][1], k.syms[i][4]
        if shndx != SHN_ABS or value not in (old, new):
            die('%s = %#x, section %#x (want SHN_ABS, %#x or %#x)' % (name, value, shndx, old, new))
        st[name] = 'stock' if value == old else '8m'
        if value == old:
            edits.append((k.symoff + 16 * i + 4, struct.pack('>I', new)))
    i = k.index('syssegs')
    if k.syms[i][4] != SHN_ABS or k.syms[i][1] != SYSSEGS:
        die('syssegs = %#x, section %#x (want SHN_ABS, %#x)' % (k.syms[i][1], k.syms[i][4], SYSSEGS))
    k.st_top1_limit()
    t64 = [s for s in k.syms if s[0] == 'ksegtbl64' and s[4] != 0]
    if t64 and t64[0][2] != KSEGTBL_SIZE:
        die('ksegtbl64 has %d bytes (want %d)' % (t64[0][2], KSEGTBL_SIZE))
    rel = k.relocs_against(('ksegtbl', 'ksegtbl64'))
    got = sorted((fn, t) for o, fn, t in rel)
    if got == [(f, 'ksegtbl') for f in KSEG]:
        st['ksegtbl'] = 'stock'
        if not check:                                # a stock kernel has no ksegtbl64 to verify against
            ix = k.index('ksegtbl64')
            for o, fn, t in rel:
                off, info, add = struct.unpack_from('>IIi', k.b, o)
                edits.append((o, struct.pack('>IIi', off, (ix << 8) | (info & 0xff), add)))
    elif got == [(f, 'ksegtbl64') for f in KSEG]:
        st['ksegtbl'] = '8m'
    else:
        die('ksegtbl is named from %s (want kseg and unkseg, one table)' % got)
    return st, edits


def main():
    mode = sys.argv[1] if sys.argv[1:2] in (['--check'], ['--stock']) else None
    path = sys.argv[2] if mode and len(sys.argv) == 3 else (sys.argv[1] if not mode and len(sys.argv) == 2 else None)
    if not path:
        sys.exit(__doc__)
    k = Kernel(path)
    st, edits = state(k, bool(mode))
    desc = ' '.join('%s=%s' % kv for kv in sorted(st.items()))
    if mode:
        want = '8m' if mode == '--check' else 'stock'
        ok = all(v == want for v in st.values())
        end = k.segu_end()
        print('arena8m030: %s; segu ends at st_top1 entry %d of %d -- %s'
              % (desc, end, ST_TOP1_ENTRIES, 'OK' if ok and end <= ST_TOP1_ENTRIES else 'NOT ' + want))
        sys.exit(0 if ok and end <= ST_TOP1_ENTRIES else 1)
    if not edits:
        print('arena8m030: already 8 MiB')
        return
    if set(st.values()) != {'stock'}:
        die('a kernel half way: %s' % desc)
    for off, data in edits:
        k.b[off:off + len(data)] = data
    k2 = open(path, 'wb')
    k2.write(k.b)
    k2.close()
    print('arena8m030: %d sites: seed, page tables, length, kvsegmap, kvsegu; kseg and unkseg -> ksegtbl64' % len(edits))


if __name__ == '__main__':
    main()
