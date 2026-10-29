#!/usr/bin/env python3
# prfcheck.py -- the formats kernel-side code may give the Amix kernel's
# printf and cmn_err: %d, %x, %s and %% only.  The 1992 printf has no
# length modifier, so "%ld" prints "d" (the S3-20 boot row's acceptance
# line read "generation d"), and the metal-proven drivers use nothing but
# these three.  Host test harnesses print through the host libc and never
# show the difference, so this checks the source.
#
#   prfcheck.py FILE...      every string literal with a % in each C file,
#                            except on lines with inline assembler
#
# One line per offending literal; exit status 1 if there is any.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
import re, sys

bad = 0
for path in sys.argv[1:]:
    src = open(path, encoding='latin-1').read()
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)
    for n, line in enumerate(src.split('\n'), 1):
        if 'asm' in line:
            continue        # an inline-assembler template, not a format
        for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', line):
            for conv in re.findall(r'%[^a-zA-Z%]*[a-zA-Z%]', lit):
                if conv not in ('%d', '%x', '%s', '%%'):
                    print('prfcheck: %s:%d: %s in "%s": the kernel printf takes %%d, %%x, %%s'
                          % (path, n, conv, lit))
                    bad += 1
sys.exit(1 if bad else 0)
