#!/bin/sh
# run.sh [SWAPGUARD.c] -- t_swapguard.c against src/swapguard030.c, or the file named (a kernel's older copy shows red)
set -eu
H=$(cd "$(dirname "$0")" && pwd); S=${1:-$H/../../src/swapguard030.c}; S=$(cd "$(dirname "$S")" && pwd)/$(basename "$S")
T=$(mktemp -d); trap 'rm -rf "${T:?}"' EXIT
cc -std=gnu89 -w -I"$H" -DSWAPGUARD="\"$S\"" -o "$T/t" "$H/t_swapguard.c"
"$T/t"
