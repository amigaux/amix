#!/bin/sh
# bss-of.sh -- the bss= of a brel kernel (docs/contracts/C2-3-packages.md
# §2): the bytes past its image to the kernel's end, which the brel does
# not record.  Both forms are relocated at 0 by the loader's own
# relocator (build/axrel): the ET_REL's end minus the brel's.
#
# usage: bss-of.sh ETREL BREL       prints the number
# Run from the repository root after `make test` (build/axrel).
set -e
B=${B:-build}
T=${TMPDIR:-/tmp}/bss-of.$$
e=$($B/axrel "$1" 0 $T.e 1 | sed -n 's/.*end \(0x[0-9a-f]*\).*/\1/p')
b=$($B/axrel "$2" 0 $T.b | sed -n 's/.*end \(0x[0-9a-f]*\).*/\1/p')
rm -f $T.e $T.b
[ -n "$e" ] && [ -n "$b" ] || { echo "bss-of: cannot relocate $1 or $2" >&2; exit 1; }
echo $((e - b))
