#!/bin/sh
# t_forkst.sh [forkst.c] -- forkst on the host, briefly: a clean run exits 0, and a run whose parent finds one of its
# own pages wrong at the end (a word overwritten just before the final check) exits 1, and so does one whose child writes
# a page outside its own set.  An older forkst.c shows red.
set -eu
H=$(cd "$(dirname "$0")" && pwd); S=${1:-$H/forkst.c}; T=$(mktemp -d); trap 'rm -rf "${T:?}"' EXIT
cc -w -o "$T/clean" "$S"
sed '/own = check(0\|printf("parent %d: %ld forks/i\
	mem[0] = 12345;' "$S" > "$T/spoil.c"
grep -q 'mem\[0\] = 12345;' "$T/spoil.c"
cc -w -o "$T/spoil" "$T/spoil.c"
# a child that also writes pages 1 and 2 (one at least outside its own set, the parent's pattern expected there)
sed '/= pat(i, 7);$/a\
	mem[1 * (PG / sizeof(long))] = pat(1, 7); mem[2 * (PG / sizeof(long))] = pat(2, 7);' "$S" > "$T/child.c"
grep -q 'mem\[1 \* (PG' "$T/child.c"
cc -w -o "$T/child" "$T/child.c"
fails=0
"$T/clean" 1 1 2 2 > "$T/c.out" 2>&1 && echo "PASS a clean run exits 0" || { echo "FAIL a clean run exits $?"; cat "$T/c.out"; fails=1; }
if "$T/spoil" 1 1 2 2 > "$T/s.out" 2>&1; then echo "FAIL a parent page found wrong at the end still exits 0"; fails=1
else echo "PASS a parent page found wrong at the end exits non-zero"; fi
if "$T/child" 1 1 2 2 > "$T/k.out" 2>&1; then echo "FAIL a child that writes outside its own pages still exits 0"; fails=1
else echo "PASS a child that writes outside its own pages makes it exit non-zero"; fi
exit $fails
