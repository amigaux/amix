#!/usr/bin/env python3
# mkksymkern.py -- test helper: a module kernel as kbootset's import check
# reads it: an ELF32 big-endian 68k ET_REL whose .data starts with a KSYM
# version 2 block (C3-2) of the given names, each name:tier (0 ddi, 1 core).
# Prints the block's image offset and size for the sidecar's ksym= line.
#
#   mkksymkern.py OUT name:tier ...
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
import struct, sys

out, args = sys.argv[1], sys.argv[2:]
ents = [(a.split(':')[0], int(a.split(':')[1])) for a in args]
strs = b'\0'
syms = b'\0' * 16
for n, t in ents:
    syms += struct.pack('>IIIBBH', len(strs), 0, 0, 0x12, t, 1)
    strs += n.encode() + b'\0'
strs += b'\0' * (-len(strs) % 4)
nsym = len(ents) + 1
hdr = struct.pack('>10I', 0x4b53594d, 2, nsym, 40, 40 + len(syms), len(strs), 0, 0, 0,
                  40 + len(syms) + len(strs))
block = hdr + syms + strs
text = b'\x4e\x75' * 32
shstr = b'\0.text\0.data\0.shstrtab\0.symtab\0.strtab\0'
kstr = b'\0stext\0dlm_ksym\0'
ksyms = b'\0' * 16 + struct.pack('>IIIBBH', 1, 0, 0, 0x12, 0, 1) + \
    struct.pack('>IIIBBH', 7, 0, len(block), 0x11, 0, 2)
o_t = 52
o_d = o_t + len(text)
o_s = o_d + len(block)
o_y = (o_s + len(shstr) + 3) & ~3
o_k = o_y + len(ksyms)
shoff = (o_k + len(kstr) + 3) & ~3
sh = [(0,) * 10,
      (1, 1, 6, 0, o_t, len(text), 0, 0, 2, 0),
      (7, 1, 3, 0, o_d, len(block), 0, 0, 4, 0),
      (13, 3, 0, 0, o_s, len(shstr), 0, 0, 1, 0),
      (23, 2, 0, 0, o_y, len(ksyms), 5, 1, 4, 16),
      (31, 3, 0, 0, o_k, len(kstr), 0, 0, 1, 0)]
h = b'\x7fELF\x01\x02\x01' + b'\0' * 9 + struct.pack('>HHIIIIIHHHHHH', 1, 4, 1, 0, 0, shoff, 0,
                                                   52, 0, 0, 40, len(sh), 3)
body = h + text + block + shstr
body += b'\0' * (o_y - len(body)) + ksyms + kstr
body += b'\0' * (shoff - len(body)) + b''.join(struct.pack('>10I', *s) for s in sh)
open(out, 'wb').write(body)
print('0x%08x 0x%08x' % (len(text), len(block)))
