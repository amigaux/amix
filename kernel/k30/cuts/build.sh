#!/bin/sh
# build.sh -- make dist's kernel-k30 hook (P-38 S2.2): the current cut of
# record, cuts/CURRENT's build id, rebuilt by its own cut.sh, its sums
# checked against the record's.
#
# usage: sh kernel/k30/cuts/build.sh [OUT]
#
# OUT (default kernel/k30/build/cuts/<build id>, where kern30m's pin reads
# it) gets cut.sh's output: tree/, cut-<build id>/ and SHA256SUMS-<build
# id>. On standard output one line per file of record, `kernel k30 <path>
# <sha256>` (paths under the cut's usr/sys). Exit status 0 when every sum
# equals the record's, 1 on a failure or a sum that differs (the cut's log's
# tail on standard error), 2 for usage.
#
# Inputs, from the checkout's history and pins, never from beside it:
#   AMIX         this checkout (a full clone: cut.sh archives its pinned
#                commit's kernel/)
#   AMIX_SYSTEM, GCA, G14  as build/pkg/layout.sh resolves them (make dist
#                sets them in the container)
#   PORT         amix-040-060-port at kernel/port/port.pin: unset, the git
#                archive of that commit from AMIX_PORT_REPO, fetched by hash
#                from AMIX_PORT_URL (default port.pin's URL) when it lacks it
#   PAULA        amix-paula at kernel/drivers/paula/paula.pin: the same with
#                AMIX_PAULA_REPO and AMIX_PAULA_URL
# A cut's README names the port and paula commits it was cut with; the
# current pins reproduce its sums when the files the cut reads are the same
# bytes, and the sums are what this checks.
#
# MIT licence, see LICENSE in kernel/k30.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
AMIX_TOP=$(cd "$HERE/../../.." && pwd)
[ $# -le 1 ] || { echo "usage: build.sh [OUT]" >&2; exit 2; }
read -r KB < "$HERE/CURRENT"
REC=$HERE/$KB
[ -f "$REC/cut.sh" ] && [ -f "$REC/SHA256SUMS-$KB" ] || {
	echo "[FAIL] cuts/CURRENT names $KB, which has no cut.sh and SHA256SUMS-$KB" >&2; exit 1; }
OUT=${1:-$AMIX_TOP/kernel/k30/build/cuts/$KB}
SRC=$AMIX_TOP/kernel/k30/build/src
mkdir -p "$(dirname "$OUT")"

. "$AMIX_TOP/build/pkg/layout.sh"
GCA=${GCA:-$(dirname "$AMIX_CROSS_ENV")}
G14=${G14:-$AMIX_G14_BUILD}
export G14
[ -n "${AMIX_SYSTEM:-}" ] && [ -d "$AMIX_SYSTEM/usr/sys" ] || {
	echo "[FAIL] no amix-system at '${AMIX_SYSTEM:-}' (AMIX_SYSTEM)" >&2; exit 1; }
mkdir -p "$SRC"
# the m68k-linux-gnu tools the cut's checks disassemble with: gcc14's
# binutils through toolchain/m68k-gnu-bin, on the host as in the container
"$AMIX_TOP/toolchain/m68k-gnu-bin" "$SRC/gnu-bin" > /dev/null
PATH=$SRC/gnu-bin:$PATH

# fork_at <name> <pin file> <repo> <url> -- the git archive of the pinned
# commit under $SRC/<name>-<commit>/, made once; prints its directory
fork_at() {
	read -r _fa_u _fa_c < "$2"
	_fa_u=${4:-$_fa_u}
	_fa_d=$SRC/$1-$_fa_c
	if [ ! -f "$_fa_d/.complete" ]; then
		_fa_r=${3:-$SRC/$1-repo}
		[ -d "$_fa_r/.git" ] || [ -d "$_fa_r/objects" ] || git init -q "$_fa_r"
		git -C "$_fa_r" cat-file -e "$_fa_c^{commit}" 2>/dev/null ||
			git -C "$_fa_r" fetch -q --depth 1 "$_fa_u" "$_fa_c" 2>/dev/null || :
		git -C "$_fa_r" cat-file -e "$_fa_c^{commit}" 2>/dev/null || {
			echo "[FAIL] $1: no commit $_fa_c in $_fa_r or at $_fa_u" >&2; exit 1; }
		rm -rf "$_fa_d"; mkdir -p "$_fa_d"
		git -C "$_fa_r" archive "$_fa_c" | tar -x -C "$_fa_d"
		: > "$_fa_d/.complete"
	fi
	echo "$_fa_d"
}
mkdir -p "$SRC"
PORT=${PORT:-$(fork_at port "$AMIX_TOP/kernel/port/port.pin" "${AMIX_PORT_REPO:-}" "${AMIX_PORT_URL:-}")}
PAULA=${PAULA:-$(fork_at paula "$AMIX_TOP/kernel/drivers/paula/paula.pin" "${AMIX_PAULA_REPO:-}" "${AMIX_PAULA_URL:-}")}

echo "--- cut $KB (cuts/$KB/cut.sh), port $(basename "$PORT"), paula $(basename "$PAULA")" >&2
AMIX=$AMIX_TOP AMIX_SYSTEM=$AMIX_SYSTEM GCA=$GCA G14=$G14 PORT=$PORT PAULA=$PAULA \
	bash "$REC/cut.sh" "$OUT" > "$OUT.log" 2>&1 || {
	tail -20 "$OUT.log" >&2
	[ -f "$OUT/cut-$KB.log" ] && tail -20 "$OUT/cut-$KB.log" >&2
	echo "[FAIL] kernel-k30: cut $KB did not build; log $OUT.log" >&2
	exit 1; }
if ! cmp -s "$OUT/SHA256SUMS-$KB" "$REC/SHA256SUMS-$KB"; then
	diff "$REC/SHA256SUMS-$KB" "$OUT/SHA256SUMS-$KB" >&2 || :
	echo "[FAIL] kernel-k30: cut $KB does not reproduce cuts/$KB/SHA256SUMS-$KB" >&2
	exit 1
fi
while read -r h f; do
	echo "kernel k30 $f $h"
done < "$OUT/SHA256SUMS-$KB"
