#!/usr/bin/env python3
# sunfont.py -- the stock console's 25x12 Sun font (amiga/console/sunfont.s
# of the Amix 2.1 kernel tree) as an object the cross tools can link, for
# the ABI kit (a driver module that draws the console links it,
# docs/contracts/C3-6-driver-to-module.md section 3).
#
#   sunfont.py CONSOLEDIR OUT.o
#
# The stock file is m4 (with screen.i) over the SVR4 assembler's syntax,
# which GNU as 2.8.1 refuses.  This runs m4, then rewrites the
# directives (text, global, byte, short, long, set), the `;` statement
# separators, the `#` comments and the forward offsets, and assembles the
# result with m68k-cbm-sysv4-as.  The bytes are the stock file's, in .data
# rather than .text; the check at the end compares the font's own length
# field with the assembled size.
#
# The stock source is Commodore's and is read, not copied; the object goes
# into the kit (distribution permission of 2026-09-23), never into
# amix-dlm's history.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
import os, re, struct, subprocess, sys, tempfile

# the stock file puts the font in text; it is data, and in .text the 68060
# scan reads its bytes as instructions (movep), so it goes to .data
DIRECTIVES = {'text': '.data', 'data': '.data', 'global': '.globl', 'byte': '.byte',
              'short': '.short', 'long': '.long', 'set': '.set'}


def translate(src):
    out = []
    for line in src.splitlines():
        line = line.split('#', 1)[0].rstrip()
        for stmt in line.split(';'):
            stmt = stmt.strip()
            if not stmt:
                continue
            label = ''
            m = re.match(r'([A-Za-z_.$][\w.$]*):\s*(.*)', stmt)
            if m:
                label, stmt = m.group(1) + ':', m.group(2)
            if stmt:
                w = stmt.split(None, 1)
                if w[0] not in DIRECTIVES:
                    sys.exit('sunfont: unknown statement %r' % stmt)
                stmt = DIRECTIVES[w[0]] + ('\t' + w[1] if len(w) > 1 else '')
            out.append((label + '\t' + stmt).rstrip() if label else '\t' + stmt)
    # O(x) is off_x, a .set made after its first use, which GNU as 2.8.1
    # does not resolve forward in data: write each use as the label
    # difference itself, which it does
    text = []
    for l in out:
        if re.match(r'(\w+:)?\t\.set\toff_\w+,', l):
            l = l.split('\t')[0]
            if not l:
                continue
        else:
            l = re.sub(r'\boff_(\w+)\b', r'(\1 - font0base)', l)
        text.append(l)
    return '\n'.join(text) + '\n'


def main(cdir, obj):
    src = subprocess.run(['m4', '-I', cdir, os.path.join(cdir, 'sunfont.s')], check=True,
                         stdout=subprocess.PIPE).stdout.decode('latin-1')
    with tempfile.TemporaryDirectory() as t:
        s = os.path.join(t, 'sunfont.s')
        open(s, 'w').write(translate(src))
        subprocess.run(['m68k-cbm-sysv4-as', '-o', obj, s], check=True)
    # .data: four font pointers, then font 0, whose f_length (offset 8 in
    # the font, after four words) is its size in bytes
    b = open(obj, 'rb').read()
    shoff, = struct.unpack('>I', b[32:36])
    shnum, shstr = struct.unpack('>HH', b[48:52])
    sh = [struct.unpack('>10I', b[shoff + 40 * i:shoff + 40 * i + 40]) for i in range(shnum)]
    so = sh[shstr][4]
    text = [x for x in sh if b[so + x[0]:so + x[0] + 6] == b'.data\0'][0]
    body = b[text[4]:text[4] + text[5]]
    flen, = struct.unpack('>I', body[16 + 8:16 + 12])
    if text[5] != 16 + flen:
        sys.exit('sunfont: .data is %d bytes, the font says 16 + %d' % (text[5], flen))
    print('sunfont: %s: builtinfont, %d bytes (font 0: %d)' % (obj, text[5], flen))


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('usage: sunfont.py CONSOLEDIR OUT.o')
    main(sys.argv[1], sys.argv[2])
