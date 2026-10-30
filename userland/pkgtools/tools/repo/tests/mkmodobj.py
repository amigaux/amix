#!/usr/bin/env python3
# mkmodobj.py -- write a test module object (kernel/dlm C3-1): an ELF32
# big-endian ET_REL EM_68K file whose .moddata section (type 13) holds a
# zero word, "MD2\0" and NUL-terminated key=value strings ending with an
# empty one.  Only what gen-catalog reads is real; there is no code.
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# usage: mkmodobj.py <out> [--magic M] [--nsec N] [--type T] key=value...
#   --magic  the 4 bytes after word 0 (default "MD2\0"; "MD1" etc. to break it)
#   --nsec   how many type-13 sections (default 1)
#   --type   e_type (default 1, ET_REL)
import struct
import sys

args = sys.argv[1:]
out = args.pop(0)
magic, nsec, etype = b"MD2\0", 1, 1
while args and args[0].startswith("--"):
    opt = args.pop(0)
    val = args.pop(0)
    if opt == "--magic":
        magic = (val.encode() + b"\0\0\0\0")[:4]
    elif opt == "--nsec":
        nsec = int(val)
    elif opt == "--type":
        etype = int(val)
moddata = b"\0\0\0\0" + magic + b"".join(a.encode() + b"\0" for a in args) + b"\0"
shstr = b"\0.moddata\0.shstrtab\0"
body = b"\0" * 4                                  # a token .text
secs = [(0, 0, 0, 0, 0)]                          # name, type, flags, off, size
off = 52 + len(body)
data = body
for _ in range(nsec):
    secs.append((1, 13, 2, off, len(moddata)))    # SHF_ALLOC
    data += moddata
    off += len(moddata)
secs.append((10, 3, 0, off, len(shstr)))
data += shstr
off += len(shstr)
off += (4 - off % 4) % 4
data += b"\0" * (off - 52 - len(data))
ehdr = b"\x7fELF" + bytes([1, 2, 1]) + b"\0" * 9
ehdr += struct.pack(">HHIIIIIHHHHHH", etype, 4, 1, 0, 0, off, 0, 52, 0, 0,
                    40, len(secs), len(secs) - 1)
shdrs = b"".join(struct.pack(">IIIIIIIIII", n, t, f, 0, o, s, 0, 0, 2, 0)
                 for n, t, f, o, s in secs)
with open(out, "wb") as fp:
    fp.write(ehdr + data + shdrs)
