#!/bin/bash
#
# test-pwgr.sh - build + run the compat pw/gr parser regression against
# the real Amix /etc/passwd and /etc/group fixtures.  Extracts the
# parser block from ../amixcompat.c into pwgr-shims.inc (so the test
# always exercises the CURRENT shim code), points the file opens at
# the fixtures, and runs the lookups.  Called from build-host.sh.
#
set -eu
D="$(cd "$(dirname "$0")" && pwd)"

python3 - "$D" <<'PYEOF'
import sys
d = sys.argv[1]
s = open(d + '/../amixcompat.c').read()
start = s.index('#define\tAMIX_PWLINE')
blk = s[start:]
blk = blk.replace('#include <pwd.h>', '').replace('#include <grp.h>', '')
# glibc has no pw_age/pw_comment
blk = blk.replace('\tpw.pw_age = "";', '\t/* pw_age: SVR4-only */')
blk = blk.replace('\tpw.pw_comment = "";', '\t/* pw_comment: SVR4-only */')
# point the parsers at the fixture files
blk = blk.replace('fopen("/etc/passwd", "r")', 'fopen(getenv("PWFILE"), "r")')
blk = blk.replace('fopen("/etc/group", "r")', 'fopen(getenv("GRFILE"), "r")')
open(d + '/pwgr-shims.inc', 'w').write(blk)
PYEOF

gcc -std=gnu89 -O -I"$D" "$D/pwgrtest.c" -o "$D/pwgrtest"
PWFILE="$D/amix-passwd.txt" GRFILE="$D/amix-group.txt" "$D/pwgrtest"
rc=$?
rm -f "$D/pwgrtest" "$D/pwgr-shims.inc"
exit $rc
