#!/bin/sh
# t_corechk.sh [-head] -- t_corechk.c on the host; -head builds it with the earlier rule, which shows red
set -eu
H=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d); trap 'rm -rf "${T:?}"' EXIT
D=; [ "${1:-}" = -head ] && D=-DHEAD_RULE
cc -w $D -I"$H" -o "$T/t" "$H/t_corechk.c"
"$T/t"
