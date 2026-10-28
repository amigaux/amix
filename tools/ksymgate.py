#!/usr/bin/env python3
# ksymgate.py -- the post-link gate of the kernel symbol block
# (docs/contracts/C3-2-symbols-and-ddi.md section 2).  A module kernel's
# build runs it on the final relocatable kernel (ET_REL as shipped; on the
# 030 line the .etrel before elf2brel, which carries the relocations one to
# one, M-ABI2).  It fails unless:
#
#   - every listed name is defined in the kernel, with the listed kind
#     (a function, or data; an untyped assembler symbol passes either);
#     the names listed are those whose minor is at most the kernel's own:
#     the kabi tag in its dlm_ident (mkident.py --asm), all of them in a
#     kernel without one (C3-2 section 2);
#   - dlm_ksym holds exactly the listed names, each with its tier;
#   - bound by the loader's own relocator (axrel, loader/common/rel.c) at
#     each of two addresses, the block passes the core's checks and every
#     name looks up through its hash to its own address at that bind, and
#     kh_lo and kh_hi are stext and end there.
#
# The expected addresses are computed here from the symbol table and the
# loader's layout rule (text, rodata, data, bss in that order, no padding,
# COMMON after bss), independently of the bytes the relocator wrote.
#
# usage: ksymgate.py AXREL KERNEL DDI.LIST [CORE.LIST]
#        ksymgate.py --extract AXREL KERNEL BIND OUT
#   --extract writes dlm_ksym as the loader leaves it at BIND, for tests
#   that resolve modules against it.
# Prints one line per check; exit status 1 if any fails.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
import os, struct, subprocess, sys, tempfile

BINDS = (0x00200000, 0x07F00000)
MAGIC, VERSION = 0x4b53594d, 2
SHN_ABS, SHN_COMMON = 0xfff1, 0xfff2
STT_NOTYPE, STT_OBJECT, STT_FUNC = 0, 1, 2

EXTRACT = len(sys.argv) > 1 and sys.argv[1] == '--extract'
if EXTRACT:
    sys.argv.pop(1)
AXREL, KERNEL = sys.argv[1], sys.argv[2]
LISTS = [] if EXTRACT else sys.argv[3:]
fails = 0


def check(ok, what):
    global fails
    print(('PASS ' if ok else 'FAIL ') + what)
    fails += not ok


def u32(b, o):
    return struct.unpack('>I', b[o:o + 4])[0]


def elfhash(name):
    h = 0
    for c in name.encode():
        h = ((h << 4) + c) & 0xffffffff
        g = h & 0xf0000000
        if g:
            h ^= g >> 24
        h &= ~g & 0xffffffff
    return h


# the kernel: sections, symbols
b = open(KERNEL, 'rb').read()
if b[:4] != b'\x7fELF' or struct.unpack('>H', b[16:18])[0] != 1:
    sys.exit('ksymgate: %s is not an ELF relocatable' % KERNEL)
shoff, = struct.unpack('>I', b[32:36])
shnum, = struct.unpack('>H', b[48:50])
sh = [struct.unpack('>10I', b[shoff + 40 * i:shoff + 40 * i + 40]) for i in range(shnum)]
syms, defs = [], {}
for s in sh:
    if s[1] == 2:
        st = sh[s[6]][4]
        for k in range(s[5] // 16):
            o = s[4] + 16 * k
            nm, val, sz, info, oth, shn = struct.unpack('>IIIBBH', b[o:o + 16])
            name = b[st + nm:b.index(b'\0', st + nm)].decode('latin-1')
            syms.append((name, val, sz, info, shn))
            if name and shn != 0 and info >> 4 != 0:
                defs[name] = (val, sz, info & 15, shn)

# the kernel's kabi tag, at 12 in dlm_ident (C3-3): it lists the names of
# its minor and below
tag = None
if 'dlm_ident' in defs and defs['dlm_ident'][3] < len(sh):
    o = sh[defs['dlm_ident'][3]][4] + defs['dlm_ident'][0] + 12
    tag = b[o:o + 24].split(b'\0')[0].decode('latin-1')
minor = int(tag.split('.')[2]) if tag and tag.count('.') == 2 and \
    tag.split('.')[2].isdigit() else None

# the lists: name -> (kind, tier)
want = {}
for tier, path in enumerate(LISTS):
    for line in open(path):
        f = line.split()
        if f and not f[0].startswith('#') and \
                (minor is None or len(f) < 3 or int(f[2]) <= minor):
            want[f[0]] = (STT_FUNC if f[1] == 'func' else STT_OBJECT, tier)
if not EXTRACT:
    print('kabi %s: %s' % (tag, 'the names of minor %d and below' % minor if minor is not None
                           else 'no tag in dlm_ident, every listed name'))

# the loader's layout (rel.c): the last section of each kind wins
t = r = d = bs = None
for i, s in enumerate(sh):
    typ, flags, size = s[1], s[2], s[5]
    if typ == 1 and size and flags & 2:
        if flags & 4:
            t = i
        elif flags & 1:
            d = i
        else:
            r = i
    elif typ == 8 and flags & 1 and size:
        bs = i


common = {}


def layout(bind):
    base, at = {}, bind
    for i in (t, r, d, bs):
        if i is not None:
            base[i] = at
            at += sh[i][5]
    for name, val, sz, info, shn in syms:      # COMMON after bss, in table order
        if shn == SHN_COMMON:
            al = val or 1
            at = (at + al - 1) & ~(al - 1)
            common[name] = at
            at += sz
    return base, at


def addr(name, base, end):
    if name == 'end':
        return end
    val, sz, typ, shn = defs[name]
    if shn == SHN_COMMON:
        return common[name]
    return val if shn == SHN_ABS else base[shn] + val


def bound(bind):
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, 'mem')
        p = subprocess.run([AXREL, KERNEL, '0x%x' % bind, out, 'pcrel'],
                           capture_output=True, text=True)
        return (open(out, 'rb').read(), '') if p.returncode == 0 else (None, p.stderr.strip())


if EXTRACT:
    bind = int(sys.argv[3], 0)
    kv, ksz, ktyp, kshn = defs['dlm_ksym']
    mem, err = bound(bind)
    if mem is None:
        sys.exit('ksymgate: ' + err)
    o = layout(bind)[0][kshn] + kv - bind
    open(sys.argv[4], 'wb').write(mem[o:o + ksz])
    sys.exit(0)

# 1. every listed name defined, with its kind
missing = sorted(n for n in want if n not in defs)
check(not missing, 'every listed name is defined in the kernel%s' %
      (': missing ' + ' '.join(missing) if missing else ' (%d)' % len(want)))
kinds = sorted(n for n in want if n in defs and defs[n][2] not in (STT_NOTYPE, want[n][0]))
check(not kinds, 'every listed name has the listed kind%s' %
      (': not ' + ' '.join(kinds) if kinds else ''))
if 'dlm_ksym' not in defs or 'stext' not in defs:
    check(False, 'the kernel defines dlm_ksym and stext')
    sys.exit(1)

# 2. and 3. the block, bound twice
kv, ksz, ktyp, kshn = defs['dlm_ksym']
for bind in BINDS:
    base, end = layout(bind)
    mem, err = bound(bind)
    if mem is None:
        check(False, 'bound at 0x%08x by the loader\'s relocator: %s' % (bind, err))
        continue
    o = base[kshn] + kv - bind
    blk = mem[o:o + ksz]
    ok = (len(blk) >= 40 and u32(blk, 0) == MAGIC and u32(blk, 4) == VERSION)
    check(ok, 'at 0x%08x: dlm_ksym is a version-2 block' % bind)
    if not ok:
        continue
    nsym, so, stro, strsz, ho = (u32(blk, 8 + 4 * k) for k in range(5))
    lo, hi, size = u32(blk, 28), u32(blk, 32), u32(blk, 36)
    check(size <= ksz and ho + 8 <= size, 'at 0x%08x: the block lies inside dlm_ksym (%d of %d bytes)'
          % (bind, size, ksz))
    check(lo == addr('stext', base, end) and hi == end,
          'at 0x%08x: kh_lo = stext (0x%08x), kh_hi = end (0x%08x)' % (bind, lo, hi))
    names = {}
    for i in range(1, nsym):
        e = so + 16 * i
        nm = blk[stro + u32(blk, e):blk.index(b'\0', stro + u32(blk, e))].decode()
        names[nm] = (u32(blk, e + 4), blk[e + 12] & 15, blk[e + 13])
    check(set(names) == set(want), 'at 0x%08x: the block holds exactly the %d listed names'
          % (bind, len(want)))
    nb = u32(blk, ho)
    bad = []
    for n, (kind, tier) in want.items():
        i, hops, got = u32(blk, ho + 8 + 4 * (elfhash(n) % nb)), 0, None
        while i and hops < nsym:
            e = so + 16 * i
            if blk[stro + u32(blk, e):blk.index(b'\0', stro + u32(blk, e))].decode() == n:
                got = i
                break
            i, hops = u32(blk, ho + 8 + 4 * (nb + i)), hops + 1
        if got is None:
            bad.append(n + ' (not found by the hash)')
            continue
        e = so + 16 * got
        if n in defs and u32(blk, e + 4) != addr(n, base, end):
            bad.append('%s = 0x%08x, not 0x%08x' % (n, u32(blk, e + 4), addr(n, base, end)))
        if blk[e + 12] & 15 != kind or blk[e + 13] != tier:
            bad.append(n + ' (kind or tier)')
    check(not bad, 'at 0x%08x: every name looks up to its own address, kind and tier%s'
          % (bind, (': ' + '; '.join(bad[:8])) if bad else ''))

print('ksymgate: %d failed' % fails)
sys.exit(1 if fails else 0)
