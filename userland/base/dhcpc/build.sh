#!/bin/sh
# build.sh -- cross-build dhcpc with gcc-cross-amix (m68k-cbm-sysv4).
#
#   userland/base/dhcpc/build.sh [--out FILE]   (default out/base/dhcpc)
#
# The period compiler, not GCC 14: dhcpc is a /usr/sbin boot-path tool, so it
# links only the stock libraries and needs nothing from /opt/amix. Linked as
# the probe is (probe/build.sh): libsocket from its archive and the stub
# archive after it, because libsocket.so leaves select undefined.
#
# MIT licence, see LICENSE at the top of the repository.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../.." && pwd)
out="$top/out/base/dhcpc"
[ "${1:-}" = --out ] && out="$2"

AMIX_TOP="$top" . "$top/build/pkg/layout.sh"
[ -f "${AMIX_CROSS_ENV:-}" ] || { echo "build.sh: no gcc-cross-amix env.sh (set AMIX_CROSS_ENV or GCA)" >&2; exit 1; }
. "$AMIX_CROSS_ENV"

mkdir -p "$(dirname "$out")"
m68k-cbm-sysv4-gcc -O -m68020 -Wall -o "$out" "$here/dhcpc.c" \
	-lnsl "$AMIX_SYSROOT/usr/lib/libsocket.a" "$AMIX_SYSROOT/usr/ccs/lib/libc.so" 2>&1 |
	grep -v -e 'within comment' -e '^In file included' -e '^  *from ' >&2 || :
[ -s "$out" ] || { echo "build.sh: link failed" >&2; exit 1; }

needed=$(m68k-cbm-sysv4-objdump -p "$out" | awk '$1 == "NEEDED" { print $2 }' | tr '\n' ' ')
echo "build.sh: $out $(wc -c < "$out") B sha256 $(sha256sum "$out" | cut -c1-16)  NEEDED: $needed"
