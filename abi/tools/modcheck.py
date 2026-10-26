#!/usr/bin/env python3
# modcheck.py -- the ABI kit's module checker: a module object against
# docs/contracts/C3-1-module-object.md and the kit's allowlist, before it
# is packaged.  The module core makes the same refusals at load time;
# this makes them at build time, with the rule named.
#
#   modcheck.py [-k KIT] [-d DEPMODULE]... MODULE
#
#   KIT        the kit directory (kit.conf, ddi.list, core.list,
#              registry/); default: the directory above this script
#   DEPMODULE  a module named in depend=; its defined globals count as
#              exported to MODULE (C3-2 section 1)
#
# Checks:
#   - ELF32 big-endian ET_REL EM_68K version 1;
#   - allocated sections PROGBITS, NOBITS or type 13 only; the image at
#     most 256 KiB and the file under 256 KiB (C3-1 section 6);
#   - exactly one .moddata (type 13 once modfix has run), allocated,
#     12..2048 bytes; word 0 an R_68K_32 against <prefix>_wrapper, addend
#     0, the wrapper defined once, globally; "MD2\0"; the key strings
#     (each at most 255 bytes; lowercase keys; once each but param; an
#     unknown key starting with ! refused) and every key's value rule;
#   - name equal to the file name; kabi of the kit's family and major, the
#     minor not above the kit's; cc the kit's pin; majors registered to
#     this name; depend naming every -d module;
#   - no SHT_REL; RELA types R_68K_NONE, 32, 16, 8, PC32, PC16, PC8 only;
#   - every undefined non-weak global in the kit's allowlist for the
#     module's tier, or defined by a -d module;
#   - on k46: the 68060 scan (m68k-cbm-sysv4-scan060) and the 4 KiB page
#     geometry (no shift by 11 of an address, the port's
#     check_page_geometry.sh rule).
#   - parameter defaults (and min, max) in C3-1 section 3's text form;
#   - a driver linkage's drv_cmajor: in majors=, registered to the module;
#   - class root (C4-2 section 1): match= given; no unload=allowed; block
#     majors only (b:, the ramdisk's), and a block major only on root
#     class; rank=, where given, one of z3660 zorro mobo ide and only on
#     root class (C4-1 section 4.1); the object runs in place in the arena
#     (C4-4 section 4): sections and COMMONs aligned to at most 16, each
#     allocated PROGBITS at a file offset that is a multiple of its
#     alignment.
# Warns (exit status unchanged) on each COMMON symbol outside the module's
# own names (its name, its wrapper's prefix): a stock header's tentative
# definition of a kernel name (ifnet, rawintrq) becomes a private copy in
# a module.  Warns when a demand-class module's load working set (the
# core's KM_SLEEP allocations for a load from a file) passes WSET_WARN,
# half of what k46 gives a module in process context (U2, 30 section 8).
# One line per problem; exit status 1 if there is any.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
import os, re, struct, subprocess, sys, tempfile

ALLOC, SHT_RELA, SHT_REL, SHT_SYMTAB = 2, 4, 9, 2
OK_TYPES = (1, 8, 13)                    # PROGBITS, NOBITS, the .moddata type
OK_RELOCS = range(0, 7)                  # R_68K_NONE .. R_68K_PC8
IMAGE_MAX = 256 << 10                    # C3-1 section 6: the image at most this,
FILE_MAX = 256 << 10                     # the file under this (the core reads it whole)
WSET_WARN = 160 << 10                    # half of k46's 320 KiB in process context (U2)
CPUS = ('68020', '68030', '68040', '68060')
RANKS = ('z3660', 'zorro', 'mobo', 'ide')     # the sd rank classes, C4-1 section 4.1
PTYPES = ('int', 'bool', 'str', 'hex')
problems = []


def bad(msg):
    problems.append(msg)


warnings = []


def warn(msg):
    warnings.append(msg)


class Elf:
    def __init__(self, path):
        self.b = b = open(path, 'rb').read()
        if b[:4] != b'\x7fELF' or b[4] != 1 or b[5] != 2 or b[6] != 1:
            raise ValueError('not an ELF32 big-endian version-1 file')
        self.type, self.machine = struct.unpack('>HH', b[16:20])
        shoff, = struct.unpack('>I', b[32:36])
        shnum, shstrndx = struct.unpack('>HH', b[48:52])
        self.sh = [dict(zip(('name', 'type', 'flags', 'addr', 'off', 'size', 'link', 'info',
                             'align', 'entsize'),
                            struct.unpack('>10I', b[shoff + 40 * i:shoff + 40 * i + 40])))
                   for i in range(shnum)]
        so = self.sh[shstrndx]['off']
        for s in self.sh:
            s['nm'] = self.cstr(so + s['name'])
        self.syms = []
        for s in self.sh:
            if s['type'] == SHT_SYMTAB:
                st = self.sh[s['link']]['off']
                for k in range(s['size'] // 16):
                    o = s['off'] + 16 * k
                    nm, val, sz, info, oth, shn = struct.unpack('>IIIBBH', b[o:o + 16])
                    self.syms.append(dict(name=self.cstr(st + nm), value=val, size=sz,
                                          bind=info >> 4, stype=info & 15, shndx=shn))

    def cstr(self, o):
        return self.b[o:self.b.index(b'\0', o)].decode('latin-1')

    def relas(self, target):
        for s in self.sh:
            if s['type'] == SHT_RELA and (target is None or s['info'] == target):
                for k in range(s['size'] // 12):
                    o = s['off'] + 12 * k
                    off, info, add = struct.unpack('>IIi', self.b[o:o + 12])
                    yield s, off, info >> 8, info & 0xff, add

    def defined_globals(self):
        return {y['name'] for y in self.syms if y['bind'] in (1, 2) and y['shndx'] != 0}


def wset(e, image):
    """The core's working set for a load from a file, all held at once
    (docs/measurements/2026-10-26-u2.md): lf_hashload's buffer (the file
    rounded up to a power of two, at least 8 KiB), the section, symbol and
    string tables, the image and the module's symbol table; upper bounds."""
    buf = 8192
    while buf <= len(e.b):
        buf *= 2
    nsym = len(e.syms)
    strsz = sum(e.sh[s['link']]['size'] for s in e.sh if s['type'] == SHT_SYMTAB)
    tables = len(e.sh) * 44 + nsym * 24 + strsz + (101 + nsym) * 4
    modtab = nsym * 16 + strsz + 4 * (103 + nsym)
    return buf + tables + image + 15 + modtab


def conf(kit):
    c = {}
    for line in open(os.path.join(kit, 'kit.conf')):
        if '=' in line and not line.startswith('#'):
            k, v = line.strip().split('=', 1)
            c[k] = v
    return c


def names(path):
    out = set()
    if os.path.exists(path):
        for line in open(path):
            line = line.split('#')[0].split()
            if line:
                out.add(line[0])
    return out


def registry(kit):
    reg = {}
    for line in open(os.path.join(kit, 'registry', 'majors')):
        f = line.split('#')[0].split()
        if len(f) == 3:
            reg[(f[0], int(f[1]))] = f[2]
    return reg


def moddata(e, path, c, reg, kit, depnames):
    md = [i for i, s in enumerate(e.sh) if s['nm'] == '.moddata' or s['type'] == 13]
    if len(md) != 1:
        bad('%d .moddata sections, exactly one wanted' % len(md))
        return {}
    i = md[0]
    s = e.sh[i]
    if not s['flags'] & ALLOC or s['size'] < 12 or s['size'] > 2048:
        bad('.moddata must be allocated and 12..2048 bytes (it is %d)' % s['size'])
        return {}
    data = e.b[s['off']:s['off'] + s['size']]
    w0 = [r for r in e.relas(i) if r[1] == 0]
    if len(w0) != 1 or w0[0][3] != 1 or w0[0][4] != 0:
        bad('.moddata word 0 needs one R_68K_32 relocation with addend 0 (to <prefix>_wrapper)')
    else:
        wname = e.syms[w0[0][2]]['name'] if w0[0][2] < len(e.syms) else ''
        defs = [y for y in e.syms if y['name'] == wname and y['shndx'] != 0]
        if not wname.endswith('_wrapper') or len(defs) != 1 or defs[0]['bind'] != 1:
            bad('word 0 must point at <prefix>_wrapper, defined once and global (it names %r)'
                % wname)
    if data[4:8] != b'MD2\0':
        bad('.moddata is not version 2 (no "MD2\\0" at offset 4)')
        return {}
    keys, params, o = {}, [], 8
    while True:
        if o >= len(data):
            bad('.moddata: the key list does not end with an empty string')
            break
        end = data.find(b'\0', o)
        if end < 0:
            bad('.moddata: a string runs past the section')
            break
        raw = data[o:end].decode('latin-1')
        o = end + 1
        if raw == '':
            break
        if len(raw) > 255:
            bad('.moddata: a string over 255 bytes: %.40s...' % raw)
        if '=' not in raw:
            bad('.moddata: %r is not key=value' % raw)
            continue
        k, v = raw.split('=', 1)
        if k != k.lower():
            bad('.moddata: key %r is not lowercase' % k)
        if k == 'param':
            params.append(v)
        elif k in keys:
            bad('.moddata: key %s given twice' % k)
        else:
            keys[k] = v
    for k in keys:
        if k.startswith('!'):
            bad('.moddata: critical key %s is not understood' % k)
    for k in ('name', 'kabi', 'cc', 'cpu', 'class'):
        if k not in keys:
            bad('.moddata: required key %s missing' % k)
    n = keys.get('name', '')
    if n and not re.fullmatch(r'[a-z0-9_-]{1,14}', n):
        bad('name=%s: 1-14 characters of [a-z0-9_-]' % n)
    if n and n != os.path.basename(path):
        bad('name=%s but the file is %s (the file name is the module name)'
            % (n, os.path.basename(path)))
    m = re.fullmatch(r'(k30|k46)\.(\d+)\.(\d+)', keys.get('kabi', ''))
    km = re.fullmatch(r'(k30|k46)\.(\d+)\.(\d+)', c['KABI'])
    if 'kabi' in keys:
        if not m:
            bad('kabi=%s: <k30|k46>.<major>.<minor>' % keys['kabi'])
        elif m.group(1) != km.group(1) or m.group(2) != km.group(2) or \
                int(m.group(3)) > int(km.group(3)):
            bad('kabi=%s: this kit is %s (same family and major, minor not above)'
                % (keys['kabi'], c['KABI']))
    if 'cc' in keys and keys['cc'] != c['PIN']:
        bad('cc=%s: the kit\'s pin is %s' % (keys['cc'], c['PIN']))
    if 'cpu' in keys and keys['cpu'] not in CPUS:
        bad('cpu=%s: one of %s' % (keys['cpu'], ', '.join(CPUS)))
    cls = keys.get('class')
    if cls is not None and cls not in ('root', 'boot', 'demand'):
        bad('class=%s: root, boot or demand' % cls)
    if 'rank' in keys:
        if cls != 'root':
            bad('rank=%s: only a root-class disk controller has a rank (C4-1 section 4.1)'
                % keys['rank'])
        elif keys['rank'] not in RANKS:
            bad('rank=%s: one of %s (C4-1 section 4.1)' % (keys['rank'], ', '.join(RANKS)))
    if cls == 'root':
        if 'match' not in keys:
            bad('class=root needs match= (C3-1 section 3)')
        if keys.get('unload') == 'allowed':
            bad('class=root with unload=allowed: a root-class module is pinned (C4-2 section 1)')
    mobo = names(os.path.join(kit, 'registry', 'mobo'))
    for key in filter(None, keys.get('match', '').split(',')):
        z = re.fullmatch(r'zorro:([0-9a-f]{4}):([0-9a-f]{2})', key)
        if key == 'always':
            continue
        if z:
            if int(z.group(1), 16) == 0 or int(z.group(2), 16) == 0:
                bad('match key %s: neither the manufacturer nor the product may be zero' % key)
        elif key.startswith('mobo:') and key[5:] in mobo:
            continue
        elif not z:
            bad('match key %s: zorro:MMMM:PP, mobo:<registered probe> or always' % key)
    if 'match' in keys and keys['match'] == '':
        bad('match= is empty')
    for mj in filter(None, keys.get('majors', '').split(',')):
        mm = re.fullmatch(r'([cb]):(\d+)', mj)
        if not mm:
            bad('majors entry %s: c:<n> or b:<n>' % mj)
            continue
        if mm.group(1) == 'c' and cls == 'root':
            bad('major %s: a root-class module registers no character major (C4-2 section 1)'
                % mj)
        if mm.group(1) == 'b' and cls != 'root':
            bad('major %s: a block major needs a root-class module, which is pinned '
                '(C4-2 section 1)' % mj)
        owner = reg.get((mm.group(1), int(mm.group(2))))
        if owner is None:
            bad('major %s is not in the registry' % mj)
        elif owner != n:
            bad('major %s is registered to %s, not %s' % (mj, owner, n))
    deps = [d for d in keys.get('depend', '').split(',') if d]
    for d in deps:
        if not re.fullmatch(r'[a-z0-9_-]{1,14}', d):
            bad('depend name %s is not a module name' % d)
    for d in depnames:
        if d not in deps:
            bad('-d %s: the module uses it but depend= does not name it' % d)
    if keys.get('unload', 'never') not in ('never', 'allowed'):
        bad('unload=%s: never or allowed' % keys['unload'])
    forms = {'int': r'-?\d+', 'hex': r'0x[0-9a-fA-F]+', 'bool': r'[01]', 'str': r'[^\s]{0,63}'}
    for p in params:
        f = p.split(':')
        if len(f) not in (3, 5) or not re.fullmatch(r'[a-z0-9_]{1,31}', f[0]) or \
                f[1] not in PTYPES:
            bad('param=%s: <name>:<int|bool|str|hex>:<default>[:<min>:<max>]' % p)
            continue
        vals = f[2:] if f[1] in ('int', 'hex') else f[2:3]
        if len(f) == 5 and f[1] not in ('int', 'hex'):
            bad('param=%s: only int and hex take a min and max' % p)
        for v in vals:
            if not re.fullmatch(forms[f[1]], v):
                bad('param=%s: %r is not a %s value (C3-1 section 3)' % (p, v, f[1]))
    if keys.get('tier', 'ddi') not in ('ddi', 'core'):
        bad('tier=%s: ddi or core' % keys['tier'])
    if keys.get('tier') == 'core' and not keys.get('build'):
        bad('tier=core needs build= (the kernel build id)')
    return keys


def drvmajors(e, keys, reg, kit):
    """a driver linkage's drv_cmajor and drv_ccount (mod_drv_data, the
    offsets from the kit's fingerprint text) against majors= and the
    registry: the core installs at drv_cmajor, so it must be the module's"""
    offs = {}
    for line in open(os.path.join(kit, 'abi.txt')):
        f = line.split()
        if len(f) == 3 and f[0] == 'offs':
            offs[f[1]] = int(f[2])
    rel = {}                    # (section, offset) -> (symbol, addend)
    for s, off, sym, rtype, add in e.relas(None):
        if rtype == 1:
            rel[(s['info'], off)] = (sym, add)

    def target(sec, off):
        r = rel.get((sec, off))
        if r is None or r[0] >= len(e.syms):
            return None
        y = e.syms[r[0]]
        if y['shndx'] == 0:
            return ('undef', y['name'])
        return (y['shndx'], y['value'] + r[1])

    def word(sec, off):
        s = e.sh[sec]
        return struct.unpack('>I', e.b[s['off'] + off:s['off'] + off + 4])[0]

    w = [y for y in e.syms if y['name'].endswith('_wrapper') and y['shndx'] != 0]
    if len(w) != 1:
        return
    link = target(w[0]['shndx'], w[0]['value'] + 20)          # mw_modlink
    while link and link[0] != 'undef':
        ops = target(link[0], link[1])
        if ops is None:
            break
        if ops == ('undef', 'mod_drvops'):
            td = target(link[0], link[1] + 4)                 # mod_type_data
            dd = td and td[0] != 'undef' and target(td[0], td[1] + 4)  # mtd_pdata
            if not dd or dd[0] == 'undef':
                bad('a mod_drvops linkage whose mod_drv_data cannot be followed')
                return
            mj = struct.unpack('>i', struct.pack('>I', word(dd[0], dd[1] + offs['DRV_CMAJOR'])))[0]
            n = struct.unpack('>i', struct.pack('>I', word(dd[0], dd[1] + offs['DRV_CCOUNT'])))[0]
            declared = [m for m in keys.get('majors', '').split(',') if m]
            for k in range(max(n, 1)):
                if 'c:%d' % (mj + k) not in declared:
                    bad('drv_cmajor %d (count %d): c:%d is not in majors=' % (mj, n, mj + k))
                elif reg.get(('c', mj + k)) != keys.get('name'):
                    bad('drv_cmajor %d: c:%d is not registered to %s' % (mj, mj + k, keys.get('name')))
        link = (link[0], link[1] + 8)                         # the next modlink entry


def inplace(e):
    """A root-class module runs where boot2 places its file (C4-4 section 4):
    each allocated PROGBITS section at a file offset that is a multiple of
    its alignment, and no section or COMMON aligned above 16 (the arena's
    alignment); kbootset's km_tail refuses the same at compose time."""
    for s in e.sh:
        if not s['flags'] & ALLOC:
            continue
        al = max(s['align'], 4)
        if al > 16:
            bad('section %s is aligned to %d: a root-class module runs in the arena, which '
                'aligns to 16' % (s['nm'], al))
        elif s['type'] != 8 and s['off'] % al:
            bad('section %s lies at file offset 0x%x, not a multiple of %d: a root-class '
                'module runs where its file lies' % (s['nm'], s['off'], al))
    for y in e.syms:
        if y['shndx'] == 0xfff2 and max(y['value'], 1) > 16:
            bad('COMMON symbol %s is aligned to %d: the arena aligns to 16'
                % (y['name'], y['value']))


def scan(e, path):
    """the 68060 scan and the page geometry, on a copy whose .moddata is
    PROGBITS again: binutils 2.8.1 (scan060 runs its objdump) cannot read
    a section of type 13, and would scan nothing"""
    b = bytearray(e.b)
    shoff, = struct.unpack('>I', b[32:36])
    for i, s in enumerate(e.sh):
        if s['type'] == 13:
            struct.pack_into('>I', b, shoff + 40 * i + 4, 1)
    code = sum(s['size'] for s in e.sh if s['flags'] & 4)
    with tempfile.TemporaryDirectory() as t:
        tmp = os.path.join(t, os.path.basename(path))
        open(tmp, 'wb').write(b)
        try:
            r = subprocess.run(['m68k-cbm-sysv4-scan060', tmp], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
        except FileNotFoundError:
            bad('m68k-cbm-sysv4-scan060 is not on PATH: the k46 check needs the pinned '
                'gcc-cross-amix bin directory (the one with m68k-cbm-sysv4-gcc) on PATH')
            return
        out = r.stdout.decode('latin-1')
        n = re.search(r'\((\d+) insns', out)
        if r.returncode != 0:
            bad('68060 scan: %s' % ('; '.join(out.strip().splitlines()[-3:]) or 'failed'))
        elif code and (not n or int(n.group(1)) == 0):
            bad('68060 scan inspected no instruction of %d bytes of code' % code)
        try:
            d = subprocess.run(['m68k-cbm-sysv4-objdump', '-d', tmp], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL).stdout.decode('latin-1').splitlines()
        except FileNotFoundError:
            bad('m68k-cbm-sysv4-objdump is not on PATH (the pinned gcc-cross-amix bin '
                'directory)')
            return
    if code and not any(re.match(r'\s+[0-9a-f]+:\s', l) for l in d):
        bad('the page-geometry check disassembled nothing')
    for a, b2 in zip(d, d[1:]):
        mq = re.search(r'moveq #11,(%d\d)', a)
        if mq and re.search(r'\b(lsrl|asrl) ' + mq.group(1) + ',', b2):
            bad('a shift by 11 (2 KiB pages) at: %s -- k46 pages are 4 KiB' % a.strip())


def main(argv):
    kit = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    deps = []
    while len(argv) > 1 and argv[0] in ('-k', '-d'):
        if argv[0] == '-k':
            kit = argv[1]
        else:
            deps.append(argv[1])
        argv = argv[2:]
    if len(argv) != 1:
        sys.exit('usage: modcheck.py [-k KIT] [-d DEPMODULE]... MODULE')
    path = argv[0]
    c = conf(kit)
    try:
        e = Elf(path)
    except (ValueError, OSError) as x:
        print('modcheck: %s: %s' % (path, x))
        return 1
    if e.type != 1 or e.machine != 4:
        bad('not an ET_REL EM_68K object (type %d, machine %d)' % (e.type, e.machine))
    image = 0
    for s in e.sh:
        if s['flags'] & ALLOC:
            if s['type'] not in OK_TYPES:
                bad('allocated section %s has type %d (PROGBITS, NOBITS or 13 only)'
                    % (s['nm'], s['type']))
            al = max(s['align'], 1)
            image = (image + al - 1) // al * al + s['size']
        if s['type'] == SHT_REL:
            bad('section %s is SHT_REL: RELA only' % s['nm'])
    for y in e.syms:            # the core allocates COMMONs into the image too
        if y['shndx'] == 0xfff2:
            al = max(y['value'], 1)
            image = (image + al - 1) // al * al + y['size']
    if image > IMAGE_MAX:
        bad('the allocated image is %d bytes, over 256 KiB' % image)
    if len(e.b) >= FILE_MAX:
        bad('the file is %d bytes, not under 256 KiB' % len(e.b))
    for s, off, sym, rtype, add in e.relas(None):
        if rtype not in OK_RELOCS:
            bad('%s: relocation type %d at 0x%x is outside the list' % (s['nm'], rtype, off))
    depmods = [Elf(d) for d in deps]
    keys = moddata(e, path, c, registry(kit), kit,
                   [os.path.basename(d) for d in deps])
    drvmajors(e, keys, registry(kit), kit)
    if keys.get('class') == 'root':
        inplace(e)
    allow = names(os.path.join(kit, 'ddi.list'))
    if keys.get('tier') == 'core':
        allow |= names(os.path.join(kit, 'core.list'))
    for d in depmods:
        allow |= d.defined_globals()
    for y in e.syms:
        if y['shndx'] == 0 and y['bind'] == 1 and y['name'] and y['name'] not in allow:
            bad('undefined symbol %s is not in the allowlist (%s) nor defined by a dependency'
                % (y['name'], 'ddi' if keys.get('tier', 'ddi') == 'ddi' else 'ddi+core'))
    # a COMMON outside the module's own names: most likely a stock header's
    # tentative definition of a kernel global (ifnet, rawintrq), which
    # becomes a private copy the module sees instead of the kernel's
    own = [keys.get('name', '')]
    own += [y['name'][:-len('wrapper')] for y in e.syms
            if y['name'].endswith('_wrapper') and y['shndx'] != 0]
    for y in e.syms:
        if y['shndx'] == 0xfff2 and y['name'] and \
                not any(o and y['name'].startswith(o) for o in own):
            warn('COMMON symbol %s, outside the module\'s own names: the core gives the '
                 'module a private copy; if a stock header made it a tentative definition '
                 'of a kernel global, the module does not see the kernel\'s' % y['name'])
    if keys.get('class') == 'demand' and wset(e, image) > WSET_WARN:
        warn('a demand-class load holds about %d bytes of kernel memory (file buffer, tables, '
             'image), over 160 KiB, half of what k46 gives a module after multi-user (U2): '
             'make it boot class or, from stage 4, root class (30 section 8)' % wset(e, image))
    if c['LINE'] == 'k46':
        scan(e, path)
    for w in warnings:
        print('modcheck: %s: warning: %s' % (os.path.basename(path), w))
    for p in problems:
        print('modcheck: %s: %s' % (os.path.basename(path), p))
    if not problems:
        print('modcheck: %s: ok (%s, %s, %d bytes)' % (os.path.basename(path), keys.get('kabi'),
                                                       keys.get('class'), image))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
