#!/bin/sh
# build.sh -- cross-build dhcprobe with gcc-cross-amix (m68k-cbm-sysv4).
#
#   userland/base/dhcpc/probe/build.sh [--out FILE]   (default out/base/dhcprobe)
#
# The period compiler, not GCC 14: the probe is a stand-in for a /usr/sbin
# boot-path tool, so it links only the stock /usr/lib/libc.so.1, libsocket
# and libnsl and needs nothing from /opt/amix. The toolchain is found the way
# build/pkg/layout.sh finds it ($AMIX_CROSS_ENV, else $GCA/env.sh).
#
# MIT licence, see LICENSE at the top of the repository.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../../.." && pwd)
out="$top/out/base/dhcprobe"
[ "${1:-}" = --out ] && out="$2"

AMIX_TOP="$top" . "$top/build/pkg/layout.sh"
[ -f "${AMIX_CROSS_ENV:-}" ] || { echo "build.sh: no gcc-cross-amix env.sh (set AMIX_CROSS_ENV or GCA)" >&2; exit 1; }
. "$AMIX_CROSS_ENV"

mkdir -p "$(dirname "$out")"
# -m68020: one binary for the 030, 040 and 060 lines; no FP is used.
# libsocket.so leaves select, syslog and seteuid undefined: they are static
# members of the stub archive usr/ccs/lib/libc.so, which ld 2.8.1 does not
# search for a shared library's references. So libsocket is linked from its
# archive, and the stub archive after it; libc.so.1 and libnsl.so stay shared.
m68k-cbm-sysv4-gcc -O -m68020 -o "$out" "$here/dhcprobe.c" \
	-lnsl "$AMIX_SYSROOT/usr/lib/libsocket.a" "$AMIX_SYSROOT/usr/ccs/lib/libc.so" 2>&1 |
	grep -v -e 'within comment' -e '^In file included' -e '^  *from ' >&2 || :
[ -s "$out" ] || { echo "build.sh: link failed" >&2; exit 1; }

needed=$(m68k-cbm-sysv4-objdump -p "$out" | awk '$1 == "NEEDED" { print $2 }' | tr '\n' ' ')
echo "build.sh: $out $(wc -c < "$out") B sha256 $(sha256sum "$out" | cut -c1-16)  NEEDED: $needed"
