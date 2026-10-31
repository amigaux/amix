#!/bin/sh
# build.sh -- make dist's kernel-k46 hook (P-38 S2.3): the port fork's cut of
# record, cuts/CURRENT's build id, rebuilt by its own cut.sh as the fork has
# it at kernel/port/port.pin, its sums checked against the record's.
#
# usage: sh kernel/port/cuts/build.sh [OUT]
#
# OUT (default kernel/port/build/cuts/<build id>, where kern46m's pin reads
# it) is emptied and gets cut.sh's run root: port/, out/c/, ufsmod/, the
# clones and SHA256SUMS-<build id>. On standard output one line per file of
# record, `kernel k46 <path> <sha256>` (paths under the run root). Exit
# status 0 when every sum equals the record's, 1 on a failure or a sum that
# differs (the cut's log's tail on standard error), 2 for usage.
#
# Inputs, from the checkout's history and pins, never from beside it:
#   PORT_GIT     the fork with the whole history of port.pin's commit (the
#                cut archives an older commit and takes its patchers from
#                older ones still); unset, a cache repository under
#                kernel/port/build/src fetched from port.pin's URL
#   AMIX         this checkout (a full clone: the cut takes the module core
#                and kernel/k30's tools from its history)
#   PAULA        amix-paula with the history of kernel/drivers/paula/paula.pin
#                (the cut reads its pinned patchers by git show): the same
#   AMIX_SYSTEM, GCA, G14  as build/pkg/layout.sh resolves them (make dist
#                sets them in the container)
#   NETBSD_SYSSRC  toolchain/netbsd-syssrc.distfile, fetched and checked by
#                toolchain/fetch-distfile into the same cache (AMIX_DISTFILES
#                is read first)
# The m68k-linux-gnu tools the port's scripts run are gcc14's binutils,
# through toolchain/m68k-gnu-bin first on PATH. The cut's optional CONTROL
# kernel is not given: it adds comparisons, not bytes.
#
# MIT licence, see LICENSE at the top of the repository.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
AMIX_TOP=$(cd "$HERE/../../.." && pwd)
[ $# -le 1 ] || { echo "usage: build.sh [OUT]" >&2; exit 2; }
read -r KB < "$HERE/CURRENT"
OUT=${1:-$AMIX_TOP/kernel/port/build/cuts/$KB}
SRC=$AMIX_TOP/kernel/port/build/src
mkdir -p "$SRC" "$(dirname "$OUT")"

. "$AMIX_TOP/build/pkg/layout.sh"
GCA=${GCA:-$(dirname "$AMIX_CROSS_ENV")}
G14=${G14:-$AMIX_G14_BUILD}
export G14
[ -n "${AMIX_SYSTEM:-}" ] && [ -f "$AMIX_SYSTEM/kernels/2.1c/unix" ] || {
	echo "[FAIL] no amix-system with kernels/2.1c/unix at '${AMIX_SYSTEM:-}' (AMIX_SYSTEM)" >&2; exit 1; }
"$AMIX_TOP/toolchain/m68k-gnu-bin" "$SRC/gnu-bin" > /dev/null
PATH=$SRC/gnu-bin:$PATH
# the port's relink-040-dlm.sh reads amix-gcc-wrapper.sh at the pin by git
# from GCA's parent and compares the installed wrapper with it; where that
# parent is no checkout holding the pin (the build container's export), GCA
# becomes build/ in a cache repository at the pin: a real directory (`..`
# must stay in the repository) whose entries link to the real build/'s
read -r _gu _gc < "$AMIX_TOP/toolchain/gcc-cross-amix.pin"
if ! git -C "$GCA/.." cat-file -e "$_gc^{commit}" 2>/dev/null; then
	_gr=$SRC/gcc-cross-amix
	[ -d "$_gr/.git" ] || git init -q "$_gr"
	git -C "$_gr" cat-file -e "$_gc^{commit}" 2>/dev/null ||
		git -C "$_gr" fetch -q --depth 1 "$_gu" "$_gc" 2>/dev/null || :
	git -C "$_gr" cat-file -e "$_gc^{commit}" 2>/dev/null || {
		echo "[FAIL] gcc-cross-amix: no commit $_gc in $_gr or at $_gu" >&2; exit 1; }
	rm -rf "$_gr/build"; mkdir "$_gr/build"
	for _ge in "$GCA"/*; do ln -s "$_ge" "$_gr/build/"; done
	GCA=$_gr/build
fi

# fork_full <name> <pin file> -- a cache repository holding the pinned
# commit with its whole history (fetched by hash, not shallow), its branch
# `pin` and HEAD at that commit so that a clone of it has the history too;
# prints it
fork_full() {
	read -r _ff_u _ff_c < "$2"
	_ff_r=$SRC/$1-repo
	[ -d "$_ff_r/.git" ] || git init -q "$_ff_r"
	git -C "$_ff_r" cat-file -e "$_ff_c^{commit}" 2>/dev/null ||
		git -C "$_ff_r" fetch -q "$_ff_u" "$_ff_c" 2>/dev/null || :
	git -C "$_ff_r" cat-file -e "$_ff_c^{commit}" 2>/dev/null || {
		echo "[FAIL] $1: no commit $_ff_c in $_ff_r or at $_ff_u" >&2; exit 1; }
	git -C "$_ff_r" update-ref refs/heads/pin "$_ff_c"
	git -C "$_ff_r" symbolic-ref HEAD refs/heads/pin
	echo "$_ff_r"
}
read -r _ PORT_PIN < "$AMIX_TOP/kernel/port/port.pin"
PORT_GIT=${PORT_GIT:-$(fork_full port "$AMIX_TOP/kernel/port/port.pin")}
PAULA=${PAULA:-$(fork_full paula "$AMIX_TOP/kernel/drivers/paula/paula.pin")}
NETBSD_SYSSRC=${NETBSD_SYSSRC:-$("$AMIX_TOP/toolchain/fetch-distfile" "$AMIX_TOP/toolchain/netbsd-syssrc.distfile" "$SRC" | tail -n 1)}
[ -f "$NETBSD_SYSSRC" ] || { echo "[FAIL] no NetBSD syssrc.tgz ($NETBSD_SYSSRC)" >&2; exit 1; }

# the record as the fork has it at the pin: cut.sh beside its scripts
REC=$SRC/cut-$PORT_PIN/cuts/$KB
if [ ! -f "$REC/cut.sh" ]; then
	rm -rf "$SRC/cut-$PORT_PIN"; mkdir -p "$SRC/cut-$PORT_PIN"
	git -C "$PORT_GIT" archive "$PORT_PIN" "cuts/$KB" | tar -x -C "$SRC/cut-$PORT_PIN" || {
		echo "[FAIL] the port at $PORT_PIN has no cuts/$KB" >&2; exit 1; }
fi
[ -f "$REC/cut.sh" ] && [ -f "$REC/SHA256SUMS-$KB" ] || {
	echo "[FAIL] the port's cuts/$KB at $PORT_PIN has no cut.sh and SHA256SUMS-$KB" >&2; exit 1; }

echo "--- cut $KB (the port's cuts/$KB/cut.sh at $(echo "$PORT_PIN" | cut -c1-7))" >&2
rm -rf "$OUT"
PORT_GIT=$PORT_GIT AMIX=$AMIX_TOP PAULA=$PAULA GCA=$GCA AMIX_SYSTEM=$AMIX_SYSTEM NETBSD_SYSSRC=$NETBSD_SYSSRC \
	bash "$REC/cut.sh" "$OUT" > "$OUT.log" 2>&1 || {
	tail -20 "$OUT.log" >&2
	echo "[FAIL] kernel-k46: cut $KB did not build; log $OUT.log" >&2
	exit 1; }
if ! cmp -s "$OUT/SHA256SUMS-$KB" "$REC/SHA256SUMS-$KB"; then
	diff "$REC/SHA256SUMS-$KB" "$OUT/SHA256SUMS-$KB" >&2 || :
	echo "[FAIL] kernel-k46: cut $KB does not reproduce the port's cuts/$KB/SHA256SUMS-$KB" >&2
	exit 1
fi
while read -r h f; do
	echo "kernel k46 $f $h"
done < "$OUT/SHA256SUMS-$KB"
