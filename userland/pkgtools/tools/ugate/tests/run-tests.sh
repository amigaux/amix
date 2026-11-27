#!/bin/sh
# run-tests.sh -- the user-path gate's host tests: the rows parser and the judge (fixture cells), the server, and
# the shell scripts' syntax. The rows themselves run in the emulator (README.md).
cd "$(dirname "$0")/.." || exit 1
n=0; fail=0
t() { if "$@" > /dev/null 2>&1; then n=$((n + 1)); else echo "FAIL: $*"; fail=1; fi; }
t python3 -B ugate.py --selftest
t python3 -B ugate-serve.py --selftest
t sh -n box/ugate-box.sh
t bash -n ugate-hook.sh
for r in rows/*.rows; do t python3 -B -c "import sys; sys.path.insert(0, '.'); import ugate; ugate.parse_rows('$r')"; done
[ $fail = 0 ] || exit 1
echo "ugate: $n passed"
