#!/usr/bin/env python3
# mkabi.py -- a module kernel's binary fingerprint, abi= in its sidecar
# (docs/contracts/C3-3-kernel-identity.md section 4): the SHA-256 of a
# text, one line per item, sorted:
#   data <name> <st_size>   every DDI-tier data name of abi/<line>/ddi.list
#                           whose minor is at most the kernel's (the kabi
#                           tag in its dlm_ident; every name without one),
#                           with its size in the final link
#   offs <NAME> <value>     the probe's structure-offset table: dlm_offs.h,
#                           written by the core's tools/mkoffs from dlmoffs.c
#                           against the kernel's headers (the brief's step 2)
#
#   mkabi.py --text OUT KERNEL DDILIST OFFS
#       write the text to OUT and print abi=<64 hex>
#   mkabi.py --check REF KERNEL DDILIST OFFS
#       the same, against REF (abi/<line>/abi-<kabi>.txt, the last text of
#       the kernel's kabi tag): print abi= if they agree; otherwise name
#       what moved and the tag change it needs, and exit 1 (20 section 3.1:
#       an added name raises the minor; a removed name, a changed size or
#       a changed offset raises the major)
#
# KERNEL is the final link as an ELF relocatable (on the 030 line, the
# .etrel before elf2brel).
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
import hashlib, re, struct, sys


def sizes(path):
    b = open(path, 'rb').read()
    if b[:4] != b'\x7fELF':
        sys.exit('mkabi: %s is not ELF' % path)
    shoff, = struct.unpack('>I', b[32:36])
    shnum, = struct.unpack('>H', b[48:50])
    sh = [struct.unpack('>10I', b[shoff + 40 * i:shoff + 40 * i + 40]) for i in range(shnum)]
    out, minor = {}, None
    for s in sh:
        if s[1] == 2:
            st = sh[s[6]][4]
            for k in range(s[5] // 16):
                o = s[4] + 16 * k
                nm, val, sz, info, oth, shn = struct.unpack('>IIIBBH', b[o:o + 16])
                name = b[st + nm:b.index(b'\0', st + nm)].decode('latin-1')
                if info >> 4 and shn != 0:
                    out[name] = sz
                if name == 'dlm_ident' and shn < len(sh):    # the kabi tag at 12 (C3-3)
                    tag = b[sh[shn][4] + val + 12:sh[shn][4] + val + 36].split(b'\0')[0]
                    f = tag.decode('latin-1').split('.')
                    if len(f) == 3 and f[2].isdigit():
                        minor = int(f[2])
    return out, minor


def text(kernel, ddilist, offs):
    have, minor = sizes(kernel)
    lines = []
    for line in open(ddilist):
        f = line.split('#')[0].split()
        if len(f) >= 3 and minor is not None and int(f[2]) > minor:
            continue
        if len(f) >= 2 and f[1] == 'data':
            if f[0] not in have:
                sys.exit('mkabi: the DDI data name %s is not defined in %s' % (f[0], kernel))
            lines.append('data %s %d' % (f[0], have[f[0]]))
    n = 0
    for line in open(offs):
        m = re.match(r'#define\s+(\w+)\s+(-?\d+)\s*$', line)
        if m:
            lines.append('offs %s %s' % m.groups())
            n += 1
    if not n:
        sys.exit('mkabi: no offsets in %s (tools/mkoffs output)' % offs)
    return ''.join(l + '\n' for l in sorted(lines))


def table(t):
    return {(l.split()[0], l.split()[1]): l.split()[2] for l in t.splitlines() if l}


def main(a):
    if len(a) != 5 or a[0] not in ('--text', '--check'):
        sys.exit('usage: mkabi.py --text OUT | --check REF  KERNEL DDILIST OFFS')
    t = text(a[2], a[3], a[4])
    abi = hashlib.sha256(t.encode()).hexdigest()
    if a[0] == '--text':
        open(a[1], 'w').write(t)
        print('abi=%s' % abi)
        return 0
    try:
        ref = open(a[1]).read()
    except OSError:
        print('mkabi: no reference %s: a new kabi tag; write it with --text and commit it' % a[1])
        return 1
    if ref == t:
        print('abi=%s' % abi)
        return 0
    old, new = table(ref), table(t)
    major = False
    for k in sorted(set(old) | set(new)):
        if k not in new:
            print('mkabi: %s %s removed: raise the major' % k)
            major = True
        elif k not in old:
            print('mkabi: %s %s added (%s): raise the minor' % (k[0], k[1], new[k]))
        elif old[k] != new[k]:
            print('mkabi: %s %s %s -> %s: raise the major' % (k[0], k[1], old[k], new[k]))
            major = True
    print('mkabi: the fingerprint moved and the kabi tag did not (%s): %s' %
          (a[1], 'a new major' if major else 'a new minor'))
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
