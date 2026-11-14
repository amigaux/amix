#!/bin/sh
# module/host/run.sh -- the host tests: the driver's own sources compiled
# for the host against a model kernel and a model DP8390 (mock.c), plus a
# source check that no CPU-timed delay loop is left.  Usage: run.sh
set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
h=$top/module/host
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cc="${HOSTCC:-cc} -std=gnu89 -w -g -DXS_HOSTTEST -I$h -I$top/src"

$cc -o "$tmp/t_core" "$h/t_core.c" "$h/mock.c" "$top/src/xsurf.c" "$top/src/xs_core.c"
$cc -o "$tmp/t_boards" "$h/t_boards.c" "$top/src/xs_boards.c"
"$tmp/t_core"
"$tmp/t_boards"

# delays: only xs_udelay (the CIA, xs_core.c) may wait
if grep -n -E 'DELAY *\(|while *\([^)]*--[^)]*\) *;' "$top"/src/*.c; then
	echo "run.sh: a CPU-timed delay loop in src/"
	exit 1
fi
echo "run.sh: delay check ok"
