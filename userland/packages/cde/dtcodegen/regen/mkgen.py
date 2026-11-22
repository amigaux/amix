#!/usr/bin/env python3
# mkgen.py MAKE_N_OUTPUT NAME > gen-NAME.sh: the generation commands of a `make -n`
# listing, in the order make first runs them, as a box script; each dtcodegen run
# is wrapped so its effect on the directory is captured (box: gen-lib.sh's run_cg)
# MIT licence, see LICENSE in userland/packages.
import re, sys
lines = open(sys.argv[1]).read().split('\n')
cmds, cur = [], ''
for l in lines:
    if cur:
        cur += '\n' + l
    else:
        cur = l
    if cur.endswith('\\'):
        continue
    cmds.append(cur); cur = ''
keep, seen = [], set()
for c in cmds:
    s = c.strip()
    if not s or s.startswith(('make', '/opt/amix', 'mv -f .deps')) or 'util/tradcpp/tradcpp' in s:
        continue
    if 'm68k-elf-g' in s or 'libtool' in s:
        continue
    if not re.match(r'^(cp |if \[|NLSPATH=|rm -f |mv |cat |chmod |/usr/bin/sed )', s):
        sys.exit('mkgen: unexpected command: ' + s.split('\n')[0])
    if s in seen:
        continue
    seen.add(s); keep.append(s)
print('#!/bin/sh\n# gen-%s.sh: written by mkgen.py from make -n; run from the directory, after gen-lib.sh' % sys.argv[2])
for s in keep:
    m = re.match(r'^NLSPATH=\S+ \S+/dtcodegen (.*)$', s)
    if m:
        print('run_cg %s || exit 1' % m.group(1))
    else:
        # the stock cp has no -f: remove the target first, as cp -f would
        s = re.sub(r'^cp -f (\S+) (\S+)', r'rm -f \2; cp \1 \2', s)
        # each command checked: the stock sh's set -e also stops at a failing command substitution
        s = s.replace('/usr/bin/sed', 'sed')
        print('%s || { echo "RES FAIL: %s"; exit 1; }' % (s, s.split(chr(10))[0].replace('"', "'").rstrip(' \\')))
