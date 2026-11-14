#!/bin/sh
# module/host/run.sh -- the STREAMS/DLPI host tests: src/z3660eth.c in its module form, built for the
# host (-DZ3660ETH_HOSTTEST) against a model kernel and the Z3660 firmware's register file and frame
# windows (zmock.c).  inc/ holds the kernel header names, each the model in zhostk.h.  Usage: run.sh
set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
h=$top/module/host
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
${HOSTCC:-cc} -std=gnu89 -w -g -DZ3660ETH_MODULE -DZ3660ETH_HOSTTEST -iquote "$h" -iquote "$h/inc" \
	-o "$tmp/t_dlpi" "$h/t_dlpi.c" "$h/zmock.c" "$top/src/z3660eth.c"
"$tmp/t_dlpi"
