#!/bin/sh
# build.sh -- cross-build dlpi-mac with GCC 14 (gcc14-cross-amix, the pin
# in toolchain/), T-56 D6.
#
#   userland/base/net/dlpi-mac/build.sh [--out FILE]   (default out/base/dlpi-mac)
#
# dlpi-mac is a /usr/sbin boot-path tool: it links only the stock
# /usr/lib/libc.so.1 and needs nothing from /opt/amix. The flags are the
# harness's (AMIX_CFLAGS: -m68020-60, one binary for the 030, 040 and 060).
#
# MIT licence, see LICENSE at the top of the repository.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../../.." && pwd)
out="$top/out/base/dlpi-mac"
[ "${1:-}" = --out ] && out="$2"

export AMIX_TOP="$top" AMIX_TOOLCHAIN=gcc14 AMIX_RECIPE_TOOLCHAINS=gcc14
. "$top/build/pkg/layout.sh"
. "$top/build/pkg/common/amix-env.sh" > /dev/null

mkdir -p "$(dirname "$out")"
rm -f "$out"
$CC $AMIX_CFLAGS -o "$out" "$here/dlpi-mac.c" >&2
[ -s "$out" ] || { echo "build.sh: link failed" >&2; exit 1; }

needed=$("$AMIX_GCC14_PREFIX/bin/m68k-elf-objdump" -p "$out" | awk '$1 == "NEEDED" { print $2 }' | tr '\n' ' ')
echo "build.sh: $out $(wc -c < "$out") B sha256 $(sha256sum "$out" | cut -c1-16)  NEEDED: $needed"
