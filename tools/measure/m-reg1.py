#!/usr/bin/env python3
# m-reg1.py -- M-REG1 and U5: the registry facts the module core relies on,
# read from each built kernel's ELF relocatable form (the k46 kernels as
# shipped, the k30 kernels' .etrel before elf2brel).  Host-side, read-only.
# See docs/measurements/2026-10-26-m-reg1.md.
#
#   - sysentsize, and whether sysent[64..69] hold nosys (the core's syscalls,
#     20 §6);
#   - cdevsw: rows, and which are empty (ten entry points all nodev or
#     nulldev, no tty, no streamtab) -- the free majors; the owner of the
#     majors the registry names (49, 51, 52, 53), including a row the code
#     fills at boot (a store relocated against cdevsw inside that row, as
#     a STREAMS driver's init sets d_str: the row is empty in the image but
#     taken at run time);
#   - bdevsw rows and the free ones; fmodcnt; nexectype; nfstype;
#   - int2_tbl's handlers;
#   - U5: whether every reference to execsw, fmodsw and vfssw is a
#     relocation against the symbol (so the core can move the table).
#
# usage: m-reg1.py <workspace>
import os, struct, sys

WS = sys.argv[1]
K = os.path.join(WS, 'amix-kerntools/work/k0-chains')
KERNELS = [
    ('K030-U', 'K030-U/K030-U-c0-u6.etrel'),
    ('K030-IDE', 'K030-IDE/K030-IDE-c0-u6.etrel'),
    ('K030-A4091-IDE', 'K030-A4091-IDE/K030-A4091-IDE-c0-u6.etrel'),
    ('K030-U-FD', 'K030-U-FD/K030-U-FD-c0-u6.etrel'),
    ('KD040-A', 'KD040-A/KD040-A-c0-u6'),
    ('KD060-A', 'KD060-A/KD060-A-c0-u6'),
    ('KD060-Z', 'KD060-Z/KD060-Z-c0-u6'),
    ('KD060-ZA', 'KD060-ZA/KD060-ZA-c0-u6'),
    ('KD060-FD', 'KD060-FD/KD060-FD-fd0'),
    ('K060', 'K060/K060-c0-u6'),
]
CDEVSZ = 52         # struct cdevsw: ten entry points, d_ttys, d_str, d_flag
BDEVSZ = 32         # struct bdevsw: seven entry points, d_flag (1024 bytes / 32 rows)
REGISTRY = {49: 'z3660rtg', 51: 'z3660eth', 52: 'monsw', 53: 'kinfo'}


class Elf:
    def __init__(self, path):
        self.b = open(path, 'rb').read()
        b = self.b
        if b[:4] != b'\x7fELF' or struct.unpack('>H', b[16:18])[0] != 1:
            raise SystemExit('%s: not an ELF relocatable' % path)
        shoff, = struct.unpack('>I', b[32:36])
        shnum, shstr = struct.unpack('>HH', b[48:52])
        self.sh = []
        for i in range(shnum):
            o = shoff + 40 * i
            n, t, f, a, off, sz, ln, inf, al, es = struct.unpack('>10I', b[o:o + 40])
            self.sh.append(dict(name=n, type=t, off=off, size=sz, link=ln, info=inf))
        so = self.sh[shstr]['off']
        for s in self.sh:
            s['nm'] = self.cstr(so + s['name'])
        self.syms, self.byname = [], {}
        for s in self.sh:
            if s['type'] == 2:
                st = self.sh[s['link']]['off']
                for k in range(s['size'] // 16):
                    o = s['off'] + 16 * k
                    nm, val, sz, info, oth, shn = struct.unpack('>IIIBBH', self.b[o:o + 16])
                    e = (self.cstr(st + nm), val, sz, shn)
                    self.syms.append(e)
                    if e[0] and shn != 0 and e[0] not in self.byname:
                        self.byname[e[0]] = e
        # relocations per target section: {sec: {offset: (type, symname, addend)}}
        self.rel = {}
        for s in self.sh:
            if s['type'] == 4:
                d = self.rel.setdefault(s['info'], {})
                for k in range(s['size'] // 12):
                    o = s['off'] + 12 * k
                    r_off, r_info, r_add = struct.unpack('>IIi', self.b[o:o + 12])
                    d[r_off] = (r_info & 0xff, self.syms[r_info >> 8][0], r_add, r_info >> 8)

    def cstr(self, o):
        return self.b[o:self.b.index(b'\0', o)].decode('latin-1')

    def sym(self, name):
        return self.byname.get(name)

    def word(self, sec, off):
        s = self.sh[sec]
        return struct.unpack('>I', self.b[s['off'] + off:s['off'] + off + 4])[0]

    def target(self, sec, off):     # the symbol a word is relocated against
        r = self.rel.get(sec, {}).get(off)
        return r[1] if r else None

    def refs(self, name):
        # relocations that reach a table: against its symbol, and (counted
        # apart) against its section's symbol with an addend inside it,
        # which moving the table would not retarget
        nm, val, sz, shn = self.byname[name]
        out, sect = {}, {}
        for sec, d in self.rel.items():
            for off, (t, s, a, si) in d.items():
                if s == name:
                    out.setdefault(self.sh[sec]['nm'], []).append(t)
                elif not s and self.syms[si][3] == shn and val <= a < val + max(sz, 1):
                    sect.setdefault(self.sh[sec]['nm'], []).append(t)
        return out, sect


def intval(e, name):
    s = e.sym(name)
    return e.word(s[3], s[1]) if s else None


def rows(e, table, count, size, empty):
    s = e.sym(table)
    n = intval(e, count)
    if not s or n is None:
        return None, []
    free = [i for i in range(n) if empty(e, s[3], s[1] + size * i)]
    return n, free


def cdev_empty(e, sec, at):
    for k in range(10):
        if e.target(sec, at + 4 * k) not in ('nodev', 'nulldev'):
            return False
    return e.target(sec, at + 40) is None and e.target(sec, at + 44) is None


def bdev_empty(e, sec, at):
    for k in range(7):
        if e.target(sec, at + 4 * k) not in ('nodev', 'nulldev'):
            return False
    return True


def cdev_owner(e, major):
    s = e.sym('cdevsw')
    t = e.target(s[3], s[1] + CDEVSZ * major)
    return t or '-'


def boot_stores(e, major):
    # code that stores into the row at boot: relocations against cdevsw
    # (in a code section) whose addend lies inside the row; named by the
    # function the relocation is in
    s = e.sym('cdevsw')
    lo, hi = s[1] + CDEVSZ * major, s[1] + CDEVSZ * (major + 1)
    funcs = {}
    for sec, d in e.rel.items():
        if e.sh[sec]['nm'] not in ('.text',):
            continue
        for off, (t, name, add, si) in d.items():
            if name == 'cdevsw' and lo <= s[1] + add < hi:
                best = None
                for nm, val, sz, shn in e.syms:
                    if shn == sec and nm and val <= off and (best is None or val > best[1]):
                        best = (nm, val)
                funcs[best[0] if best else '?'] = 1
    return sorted(funcs)


def ranges(l):
    out, i = [], 0
    while i < len(l):
        j = i
        while j + 1 < len(l) and l[j + 1] == l[j] + 1:
            j += 1
        out.append(str(l[i]) if i == j else '%d-%d' % (l[i], l[j]))
        i = j + 1
    return ','.join(out) or 'none'


for fam, rel in KERNELS:
    p = os.path.join(K, rel)
    if not os.path.exists(p):
        print('%s: %s missing' % (fam, rel))
        continue
    e = Elf(p)
    print('== %s (%s)' % (fam, rel))
    se = e.sym('sysent')
    n = intval(e, 'sysentsize')
    nosys = [k for k in range(64, 70) if se and e.target(se[3], se[1] + 8 * k + 4) == 'nosys']
    print('sysentsize %s; sysent[64..69] nosys: %s' % (n, 'all' if len(nosys) == 6 else nosys))
    nc, cfree = rows(e, 'cdevsw', 'cdevcnt', CDEVSZ, cdev_empty)
    print('cdevsw %s rows; empty %s' % (nc, ranges(cfree)))
    def state(m):
        st = boot_stores(e, m)
        if m in cfree and not st:
            return 'free'
        if m in cfree:
            return 'filled at boot by ' + ' '.join(st)
        return 'used by ' + cdev_owner(e, m)
    print('majors of the registry: ' + ', '.join(
        '%d %s (%s)' % (m, state(m), who) for m, who in sorted(REGISTRY.items()) if nc and m < nc))
    nb, bfree = rows(e, 'bdevsw', 'bdevcnt', BDEVSZ, bdev_empty)
    print('bdevsw %s rows; empty %s' % (nb, ranges(bfree)))
    print('fmodcnt %s; nexectype %s; nfstype %s' % (
        intval(e, 'fmodcnt'), intval(e, 'nexectype'), intval(e, 'nfstype')))
    it = e.sym('int2_tbl')
    if it:
        h, k = [], 0
        while True:
            t = e.target(it[3], it[1] + 4 * k)
            if not t:
                break
            h.append(t)
            k += 1
        print('int2_tbl %d handlers: %s' % (len(h), ' '.join(h)))
    for t in ('execsw', 'fmodsw', 'vfssw', 'cdevsw', 'bdevsw'):
        r, sect = e.refs(t)
        print('U5 %s: by symbol %s; by section offset %s' % (
            t, ', '.join('%s %d' % (k, len(v)) for k, v in sorted(r.items())) or 'none',
            ', '.join('%s %d' % (k, len(v)) for k, v in sorted(sect.items())) or 'none'))
