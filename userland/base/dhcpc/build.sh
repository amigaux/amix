#!/bin/sh
# build.sh -- cross-build dhcpc with GCC 14 (gcc14-cross-amix, the pin in
# toolchain/), T-56 D6.
#
#   userland/base/dhcpc/build.sh [--out FILE]   (default out/base/dhcpc)
#
# dhcpc is a /usr/sbin boot-path tool: it links only the stock libraries
# (libnsl.so, libsocket.a, libc) and needs nothing from /opt/amix; the
# toolchain's own runtime, libamixc99, is a static archive. libsocket comes
# from its archive and the stub archive after it, because libsocket.so
# leaves select undefined. The flags are the harness's (AMIX_CFLAGS).
#
# MIT licence, see LICENSE at the top of the repository.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../.." && pwd)
out="$top/out/base/dhcpc"
[ "${1:-}" = --out ] && out="$2"

export AMIX_TOP="$top" AMIX_TOOLCHAIN=gcc14 AMIX_RECIPE_TOOLCHAINS=gcc14
. "$top/build/pkg/layout.sh"
. "$top/build/pkg/common/amix-env.sh" > /dev/null

mkdir -p "$(dirname "$out")"
rm -f "$out"
$CC $AMIX_CFLAGS -o "$out" "$here/dhcpc.c" \
	-lnsl "$AMIX_SYSROOT/usr/lib/libsocket.a" "$AMIX_SYSROOT/usr/ccs/lib/libc.so" >&2
[ -s "$out" ] || { echo "build.sh: link failed" >&2; exit 1; }

needed=$("$AMIX_GCC14_PREFIX/bin/m68k-elf-objdump" -p "$out" | awk '$1 == "NEEDED" { print $2 }' | tr '\n' ' ')
echo "build.sh: $out $(wc -c < "$out") B sha256 $(sha256sum "$out" | cut -c1-16)  NEEDED: $needed"
