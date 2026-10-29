#!/usr/bin/env python3
# mkmodobj.py -- test helper: a module object as kbootset reads it, with no
# cross compiler: an ELF32 big-endian 68k relocatable holding some .text
# and a .moddata section of type 13 with the given keys (C3-1 section 3).
# kbootset reads the ELF header, the section headers, .moddata and, for its
# import check, the global symbols; the object has no relocations, so the
# module core would refuse it, kbootset's gates do not look further.
#
#   mkmodobj.py OUT key=value ... [U:name ...] [D:name ...]
#       e.g. name=monsw class=demand ... U:printf D:monsw_hook
#
# U:name is an undefined global (an import), D:name a global defined in
# .text; without either the object has no symbol table.  kabi= and cc=
# default to k46.1.0 and the pin; cpu= to 68040.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
import struct, sys

out, args = sys.argv[1], sys.argv[2:]
undef = [a[2:] for a in args if a.startswith('U:')]
defs = [a[2:] for a in args if a.startswith('D:')]
keys = [a for a in args if not a.startswith(('U:', 'D:'))]
names = [a.split('=', 1)[0] for a in keys]
for k, v in (('kabi', 'k46.1.0'), ('cc', 'gcc-2.7.2.3-8949028'), ('cpu', '68040')):
    if k not in names:
        keys.append('%s=%s' % (k, v))
md = b'\0\0\0\0MD2\0' + b''.join(k.encode() + b'\0' for k in keys) + b'\0'
md += b'\0' * (-len(md) % 4)
text = b'\x4e\x75' * 8 + out.encode()[-8:].ljust(8, b'\0')    # rts..., and a tag
shstr = b'\0.text\0.moddata\0.shstrtab\0.symtab\0.strtab\0'
strtab = b'\0' + b''.join(n.encode() + b'\0' for n in undef + defs)
syms = b'\0' * 16
at = 1
for n in undef + defs:
    shndx = 0 if n in undef else 1
    syms += struct.pack('>IIIBBH', at, 0, 0, 0x10, 0, shndx)   # STB_GLOBAL, STT_NOTYPE
    at += len(n) + 1
withsym = bool(undef or defs)
off_text = 52
off_md = off_text + len(text)
off_str = off_md + len(md)
off_sym = (off_str + len(shstr) + 3) & ~3
off_strtab = off_sym + (len(syms) if withsym else 0)
end = off_strtab + (len(strtab) if withsym else 0)
shoff = (end + 3) & ~3
sh = [(0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
      (1, 1, 6, 0, off_text, len(text), 0, 0, 2, 0),
      (7, 13, 3, 0, off_md, len(md), 0, 0, 4, 0),
      (16, 3, 0, 0, off_str, len(shstr), 0, 0, 1, 0)]
if withsym:
    sh += [(26, 2, 0, 0, off_sym, len(syms), 5, 1, 4, 16),
           (34, 3, 0, 0, off_strtab, len(strtab), 0, 0, 1, 0)]
hdr = b'\x7fELF\x01\x02\x01' + b'\0' * 9 + struct.pack('>HHIIIIIHHHHHH', 1, 4, 1, 0, 0, shoff, 0,
                                                     52, 0, 0, 40, len(sh), 3)
body = hdr + text + md + shstr
body += b'\0' * (off_sym - len(body))
if withsym:
    body += syms + strtab
body += b'\0' * (shoff - len(body))
body += b''.join(struct.pack('>10I', *s) for s in sh)
open(out, 'wb').write(body)
