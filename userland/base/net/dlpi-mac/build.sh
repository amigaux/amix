#!/bin/sh
# build.sh -- cross-build dlpi-mac with gcc-cross-amix (m68k-cbm-sysv4).
#
#   userland/base/net/dlpi-mac/build.sh [--out FILE]   (default out/base/dlpi-mac)
#
# The period compiler, not GCC 14: dlpi-mac is a /usr/sbin boot-path tool, so
# it links only the stock /usr/lib/libc.so.1 and needs nothing from /opt/amix.
# The toolchain is found the way build/pkg/layout.sh finds it
# ($AMIX_CROSS_ENV, else $GCA/env.sh).
#
# MIT licence, see LICENSE at the top of the repository.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../../.." && pwd)
out="$top/out/base/dlpi-mac"
[ "${1:-}" = --out ] && out="$2"

AMIX_TOP="$top" . "$top/build/pkg/layout.sh"
[ -f "${AMIX_CROSS_ENV:-}" ] || { echo "build.sh: no gcc-cross-amix env.sh (set AMIX_CROSS_ENV or GCA)" >&2; exit 1; }
. "$AMIX_CROSS_ENV"

mkdir -p "$(dirname "$out")"
# -m68020: one binary for the 030, 040 and 060 lines; no FP is used.
m68k-cbm-sysv4-gcc -O -m68020 -o "$out" "$here/dlpi-mac.c" 2>&1 |
	grep -v -e 'within comment' -e '^In file included' -e '^  *from ' >&2 || :
[ -s "$out" ] || { echo "build.sh: link failed" >&2; exit 1; }

needed=$(m68k-cbm-sysv4-objdump -p "$out" | awk '$1 == "NEEDED" { print $2 }' | tr '\n' ' ')
echo "build.sh: $out $(wc -c < "$out") B sha256 $(sha256sum "$out" | cut -c1-16)  NEEDED: $needed"
