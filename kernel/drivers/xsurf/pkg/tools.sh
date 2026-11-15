#!/bin/sh
#
# tools.sh -- the user program the xsurf packages ship beside the module:
#
#     /usr/sbin/xsf    the driver's boards in words and counters, through
#                      /dev/xsfN and /dev/xsfctl (userland/xsf.c, xsf(1M))
#
#     sh kernel/drivers/xsurf/pkg/tools.sh     (pin.sh's kdrv_prepare runs it)
#
# Built with GCC 14 (gcc14-env.sh: -m68020-60 -mno-strict-align -O2 -Wall)
# from this checkout's userland/xsf.c and the driver's xsurfuser.h and
# xsurfwords.h, and gated as every gcc14 userland program is: the m68k ELF,
# the 68060 scanners, the alignment flag on every compile line and no
# libacompat.  Not stripped: adb on the box needs its symbols.  pin.sh's
# KM_FILES_COMMON pins the output; kmodpkg.sh verifies it there.
#
# Output: out/build/xsurf-tools/out/ under the checkout.
#
# MIT licence, see LICENSE at the top of the repository.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
AMIX_TOP=$(cd "$HERE/../../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
TOOLCHAIN=gcc14 AMIX_RECIPE_TOOLCHAINS=gcc14
. "$AMIX_PKG_COMMON/amix-env.sh"
. "$AMIX_PKG_COMMON/gates.sh"

D=$AMIX_TOP/kernel/drivers/xsurf
W=$AMIX_TOP/out/build/xsurf-tools
OUT=$W/out
LOG=$W/build.log

echo "=== xsurf tools (GCC 14) ==="
rm -rf "${OUT:?}"
mkdir -p "$OUT/bin"
(
	set -ex
	$CC $AMIX_CFLAGS -I"$D/src" -c "$D/userland/xsf.c" -o "$W/xsf.o"
	$CC $AMIX_CFLAGS -o "$OUT/bin/xsf" "$W/xsf.o"
) > "$LOG" 2>&1 || { tail -20 "$LOG" >&2; echo "[FAIL] xsf did not build ($LOG)" >&2; exit 1; }
if grep -E 'warning:' "$LOG" >/dev/null; then
	grep -E 'warning:' "$LOG" >&2
	echo "[FAIL] xsf built with warnings ($LOG)" >&2
	exit 1
fi
echo "  built: xsf, no warnings (log $LOG)"

echo "--- gates ---"
amix_gate_elf "$OUT/bin/xsf"
amix_gate_g14_strict "$LOG"
amix_gate_g14_compat "$LOG"
amix_gate_060_tree "$OUT/bin"
echo "  undefined in xsf: $("$NM" -D -u "$OUT/bin/xsf" | awk '{print $NF}' | sort -u | tr '\n' ' ')"
(cd "$OUT" && find . -type f | LC_ALL=C sort | xargs sha256sum) | sed 's|  \./|  |; s/^/  /'
