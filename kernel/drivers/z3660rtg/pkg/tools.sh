#!/bin/sh
#
# tools.sh -- the userland files the z3660rtg packages ship beside the
# module, for X on a Z3660 (amix-base display.d(4)) and the board's sensors:
#
#     /opt/amix/bin/zz9k_monsw    the monitor-switch tool display.d's monswtool
#                                 names (the fork's zz9000/tools/zz9k_monsw.c)
#     /opt/amix/bin/rtg-kbdback   gives the console its keyboard back after a
#                                 server that ended on its own (x11/rtg-kbdback.c)
#     /opt/amix/bin/ztop          the board's temperatures, voltages and CPU
#                                 clock through /dev/zz9000i (zz9000/tools/ztop.c)
#     /opt/amix/bin/startx-rtg    the 1.1 launcher (x11/1.1/startx-rtg)
#     /opt/amix/man/1/ztop and the package's whatis fragment
#     /etc/display.d/z3660        the card's display.d file, the worked example
#                                 of display.d(4) byte for byte
#
# xztop, ztop in an X window, links X11R6.3's libraries and is its own
# userland package (userland/packages/xztop), so this package carries no X.
#
#     sh kernel/drivers/z3660rtg/pkg/tools.sh     (pin.sh's kdrv_prepare runs it)
#
# The programs are built with GCC 14 (gcc14-env.sh: -m68020-60
# -mno-strict-align -O2 -Wall) from the git archive of the fork at
# kernel/drivers/z3660rtg/z3660rtg.pin, the drivers step's copy in
# out/cache/forks/z3660rtg, stripped, and gated as every gcc14 userland
# program is: the m68k ELF, the 68060 scanners, the alignment flag on every
# compile line and no libacompat.  rtg-kbdback links the stock libscreen.so
# (amix-system usr/amiga/lib, pinned): its SONAME is
# /usr/amiga/lib/libscreen.so, the path every stock box has.  pin.sh's
# KM_FILES_COMMON pins every output; kmodpkg.sh verifies them there.
#
# Output: out/build/z3660rtg-tools/out/ under the checkout.
#
# MIT licence, see LICENSE at the top of the repository.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
AMIX_TOP=$(cd "$HERE/../../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
TOOLCHAIN=gcc14 AMIX_RECIPE_TOOLCHAINS=gcc14
. "$AMIX_PKG_COMMON/amix-env.sh"
. "$AMIX_PKG_COMMON/fetch.sh"
. "$AMIX_PKG_COMMON/gates.sh"
. "$HERE/pin.sh"

read -r _ ZR_COMMIT < "$AMIX_TOP/kernel/drivers/z3660rtg/z3660rtg.pin"
FORK=$AMIX_TOP/out/cache/forks/z3660rtg
W=$AMIX_TOP/out/build/z3660rtg-tools
SRC=$W/src
OUT=$W/out
LOG=$W/build.log
SYS=$AMIX_SYSTEM

echo "=== z3660rtg tools (fork $ZR_COMMIT, GCC 14) ==="
git -C "$FORK" cat-file -e "$ZR_COMMIT^{commit}" 2>/dev/null || {
	echo "[FAIL] $FORK has no commit $ZR_COMMIT (make drivers fetches it)" >&2; exit 1; }
rm -rf "${SRC:?}" "${OUT:?}"
mkdir -p "$SRC" "$OUT/bin" "$OUT/man/1" "$OUT/display.d"
Z=overlay/usr/sys/amiga/driver/zz9000
git -C "$FORK" archive "$ZR_COMMIT" \
	x11/rtg-kbdback.c x11/1.1/startx-rtg \
	$Z/tools/zz9k_monsw.c $Z/tools/ztop.c $Z/tools/ztop.1 $Z/zz9000.h | tar -x -C "$SRC"
amix_verify "$SYS/usr/amiga/lib/libscreen.so" "$ZR_LIBSCREEN_SHA"
amix_verify "$SYS/usr/amiga/include/amiga/screen.h" "$ZR_SCREEN_H_SHA"

T="$SRC/$Z/tools"
# rtg-kbdback.c calls ioctl() with only <sys/ioctl.h>, which on AMIX defines
# the requests and no prototype; <unistd.h> declares it (GCC 14 refuses an
# implicit declaration, and -Wno-error would hide it), so it is included
(
	set -ex
	$CC $AMIX_CFLAGS -c "$T/zz9k_monsw.c" -o "$W/zz9k_monsw.o"
	$CC $AMIX_CFLAGS -o "$OUT/bin/zz9k_monsw" "$W/zz9k_monsw.o"
	$CC $AMIX_CFLAGS -include unistd.h -I"$SYS/usr/amiga/include" -c "$SRC/x11/rtg-kbdback.c" -o "$W/rtg-kbdback.o"
	$CC $AMIX_CFLAGS -o "$OUT/bin/rtg-kbdback" "$W/rtg-kbdback.o" "$SYS/usr/amiga/lib/libscreen.so"
	$CC $AMIX_CFLAGS -I"$SRC/$Z" -c "$T/ztop.c" -o "$W/ztop.o"
	$CC $AMIX_CFLAGS -o "$OUT/bin/ztop" "$W/ztop.o"
	$STRIP "$OUT/bin/zz9k_monsw" "$OUT/bin/rtg-kbdback" "$OUT/bin/ztop"
) > "$LOG" 2>&1 || { tail -20 "$LOG" >&2; echo "[FAIL] the tools did not build ($LOG)" >&2; exit 1; }
echo "  built and stripped: zz9k_monsw, rtg-kbdback, ztop (log $LOG)"

echo "--- gates ---"
amix_gate_elf "$OUT/bin/zz9k_monsw" "$OUT/bin/rtg-kbdback" "$OUT/bin/ztop"
amix_gate_g14_strict "$LOG"
amix_gate_g14_compat "$LOG"
amix_gate_060_tree "$OUT/bin"
# the libc and libscreen surface each program takes from the box (stripped:
# the dynamic symbol table)
for _t in zz9k_monsw rtg-kbdback ztop; do
	echo "  undefined in $_t: $("$NM" -D -u "$OUT/bin/$_t" | awk '{print $NF}' | sort -u | tr '\n' ' ')"
done

echo "--- the launcher, the man page and its whatis line ---"
cp "$SRC/x11/1.1/startx-rtg" "$OUT/bin/startx-rtg"
cp "$T/ztop.1" "$OUT/man/1/ztop"
# whatis.d/<PKG> (userland/packages/docs/man-pages.md): one line per page,
# `name(sect)` padded to column 18, then the NAME section's `names - text`
_n=$(awk '/^\.SH NAME/ { getline; print; exit }' "$OUT/man/1/ztop" | sed 's/ \\- / - /')
case "$_n" in "ztop - "*) ;; *) echo "[FAIL] ztop's NAME line is '$_n'" >&2; exit 1 ;; esac
printf '%-17s%s\n' "ztop(1)" "$_n" > "$OUT/man/whatis"
sed 's/^/  /' "$OUT/man/whatis"

echo "--- /etc/display.d/z3660 from userland/base/display/display.d.4 ---"
# the lines between `.ft CW` and `.ft R` of the page's first EXAMPLE block;
# the block has no troff escape, so the page's bytes are the file's
awk '/^\.SH EXAMPLE/ { ex = 1 } ex && /^\.ft CW/ && !done { on = 1; next }
	on && /^\.ft R/ { on = 0; done = 1 } on { print }' \
	"$AMIX_TOP/userland/base/display/display.d.4" > "$OUT/display.d/z3660"
! grep -q '\\' "$OUT/display.d/z3660" || { echo "[FAIL] a troff escape in the example block" >&2; exit 1; }
head -1 "$OUT/display.d/z3660" | grep -q '^# /etc/display.d/z3660 ' || {
	echo "[FAIL] the example block does not start with the z3660 file's comment" >&2; exit 1; }
echo "  $(wc -l < "$OUT/display.d/z3660") lines"
(cd "$OUT" && find . -type f | LC_ALL=C sort | xargs sha256sum) | sed 's|  \./|  |; s/^/  /'
