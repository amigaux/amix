#!/bin/sh
# libmod.sh -- modtools/libmod.c (the box's GCC 14 stubs) makes each of the
# core's six system calls with the number the core's sys/mod.h gives it,
# and retries on the ERESTART the core's own assembler stubs retry on.
set -e
B=${B:-build}
sh tools/stagecore.sh "$B/libmod-core"
python3 - "$B/libmod-core/include/sys/mod.h" modtools/libmod.c <<'PY'
import re, sys
want = dict((m.group(1), int(m.group(2))) for m in
            re.finditer(r'#define\s+SYS_(\w+)\s+(\d+)', open(sys.argv[1]).read()))
src = open(sys.argv[2]).read()
got = dict((m.group(1), int(m.group(2))) for m in
           re.finditer(r'\n(\w+)\([^)]*\)[^{]*\{[^}]*?syscall\((\d+)', src))
if want != got:
    sys.exit('libmod: modtools/libmod.c %s differs from sys/mod.h %s' % (got, want))
# ERESTART: the value the core's own assembler stubs retry on
import glob, os
stubs = set(int(n) for f in glob.glob(os.path.join(os.path.dirname(sys.argv[1]), '../../libmod/*.s'))
            for n in re.findall(r'cmpib\s+&(\d+)', open(f).read()))
mine = int(re.search(r'#define\s+ERESTART\s+(\d+)', src).group(1))
if stubs != {mine}:
    sys.exit('libmod: ERESTART %d, the core stubs retry on %s' % (mine, sorted(stubs)))
print('libmod: the six calls match sys/mod.h (%s)' % ', '.join('%s %d' % kv for kv in sorted(want.items())))
PY
