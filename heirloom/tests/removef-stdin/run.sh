#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# run.sh - regression for `removef PKG -` (the stdin path-list form).
# Upstream removef kept fgets' newline on every stdin line, so no path
# matched contents and nothing was removed, silently (found on the box
# 2026-10-26).  Registers three files with installf, feeds two of them
# to `removef PKG -`, and checks that exactly those two left contents.
# Runs against the host build's compiled-in VSADMDIR (build-host/var/
# sadm); the contents file is saved and restored.  Called from
# build-host.sh.
set -eu
TOP="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$TOP/build-host/bin"
V="$TOP/build-host/var/sadm"
W="$TOP/build-host/rmf"
C="$V/install/contents"
PKG=RMFTEST
U="$(id -un)"; G="$(id -gn)"

rm -rf "$W" "$V/pkg/$PKG"
mkdir -p "$W/f" "$V/pkg/$PKG"
cp "$C" "$W/contents.saved"
trap 'cp "$W/contents.saved" "$C"; rm -rf "$V/pkg/$PKG"' EXIT
printf 'PKG=%s\nNAME=removef stdin regression\nARCH=m68k\nVERSION=1.0\nCATEGORY=application\n' \
	"$PKG" > "$V/pkg/$PKG/pkginfo"
: > "$C"

fail() { echo "removef stdin: FAIL - $*"; exit 1; }
for n in a b c; do
	echo "$n" > "$W/f/$n"
	"$BIN/installf" "$PKG" "$W/f/$n" f 0644 "$U" "$G" || fail "installf $n"
done
"$BIN/installf" -f "$PKG" || fail "installf -f"
[ "$(grep -c " $PKG\$" "$C")" = 3 ] || fail "setup: 3 records expected"

# two paths on stdin, the second line with a trailing blank
printf '%s\n%s \n' "$W/f/a" "$W/f/c" | "$BIN/removef" "$PKG" - \
	> "$W/out" || fail "removef - rc=$?"
"$BIN/removef" -f "$PKG" || fail "removef -f"

grep -q "^$W/f/a " "$C" && fail "a still in contents"
grep -q "^$W/f/c " "$C" && fail "c still in contents"
grep -q "^$W/f/b " "$C" || fail "b was removed too"
[ "$(grep -c " $PKG\$" "$C")" = 1 ] || fail "exactly 1 record expected"
[ "$(wc -l < "$W/out")" = 2 ] || fail "removef should list 2 paths"
echo "removef stdin:     OK (2 of 3 paths removed via 'removef PKG -')"
