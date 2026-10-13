#!/bin/sh
#
# run.sh - regression suite for the AMIX PORT 14-character mkstemp-template
# fix in pkgcmds/pkginstall/cppath.c (write_file / temp_template).
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# THE DEFECT.  Upstream builds write_file()'s mkstemp template as
# <target> + "XXXXXX".  On Amix's s5 root filesystem a directory entry name is
# truncated to 14 bytes, so when the target's basename is already 14 bytes or
# longer every candidate name truncates back onto the dirent being replaced,
# every O_EXCL create returns EEXIST, and pkgadd dies with
# "unable to create unique temporary file <>".  The branch is only entered when
# the target exists, so this is precisely an UPGRADE / RE-INSTALL defect --
# 572 objects of the `full` set, and shipped files as ordinary as
# /usr/apkg/doc/OPENSOLARIS.LICENSE.  Measured in
# ../../../docs/s5-14char-collisions.md section 2.1.
#
# WHAT IS SIMULATED.  There is no s5 filesystem on the host, so s5sim.so
# (LD_PRELOAD) gives one directory tree s5's naming semantics: every path
# component truncated to 14 bytes on create AND on lookup, plus the box's own
# SVR4-mktemp-based mkstemp() from ../../compat/amixcompat.c, which empties the
# template when it gives up -- the "<>" in the bench log.  See s5sim.c for the
# limits of the simulation.  Everything else is real: the code under test is
# the shipping cppath.c linked against the real host libinst/libpkg.
#
# RED/GREEN.  The suite builds cppath.c TWICE -- once as shipped, once with
# -DAMIX_NO_S5_TEMPLATE_CAP, which restores the upstream template.  The
# "broken" build must reproduce the bench failure; the shipped build must not.
# A suite where only the fixed build ran would prove nothing about the
# simulation being able to see the defect at all.
#
# Prereq: ../../build-host.sh has been run (host libinst/libpkg/libgendb/
# libadm archives + version/version.o).
#
# Exit 0 = all pass, 1 = a failure, 2 = could not run (build first).
#
set -u

D="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$D/../.." && pwd)"
OUT="${OUTDIR:-/tmp/s5-14char}"
CC="${CC:-gcc}"

for lib in libinst/libinst.a libpkg/libpkg.a libgendb/libgendb.a \
	   libadm/libadm.a version/version.o; do
	[ -f "$TOP/$lib" ] || {
		echo "SKIP: $TOP/$lib missing - run ./build-host.sh first"
		exit 2
	}
done

rm -rf "$OUT"; mkdir -p "$OUT"
S5="$OUT/s5"			# the simulated 14-character filesystem
PLAIN="$OUT/plain"		# an ordinary (untruncated) directory
LOG="$OUT/s5sim.log"
SRC="$OUT/src"; mkdir -p "$SRC"
printf 'AAAA the first payload\n'  > "$SRC/a"
printf 'BBBB the second payload\n' > "$SRC/b"

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS: $1"; }
bad() { fail=$((fail+1)); echo "FAIL: $1"; }

# ------------------------------------------------------------------ build ---
INC="-I$TOP/sslstub -I$TOP/hdrs -I$TOP/libpkg -I$TOP/libgendb -I$TOP/libinst
     -I$TOP/libspmizones -I$TOP/libadm -I$TOP/pkgcmds/pkginstall
     -I$TOP/pkgcmds/pkgadm"
LIBS="-L$TOP/libinst -linst -L$TOP/libpkg -lpkg -L$TOP/libgendb -lgendb
      -L$TOP/libadm -ladm"
CFLAGS="-O -std=gnu89 -fcommon -D_GNU_SOURCE"

echo "== building the s5 (14-character) filesystem simulator =="
$CC -shared -fPIC -o "$OUT/s5sim.so" "$D/s5sim.c" -ldl || {
	echo "FAIL: could not build s5sim.so"; exit 2; }

echo "== building test-cppath: shipped cppath.c, and the upstream template =="
# shellcheck disable=SC2086
$CC $CFLAGS $INC "$D/test-cppath.c" "$TOP/pkgcmds/pkginstall/cppath.c" \
	"$TOP/version/version.o" $LIBS -o "$OUT/cppath-fixed" || {
	echo "FAIL: could not build cppath-fixed"; exit 2; }
# shellcheck disable=SC2086
$CC $CFLAGS -DAMIX_NO_S5_TEMPLATE_CAP $INC "$D/test-cppath.c" \
	"$TOP/pkgcmds/pkginstall/cppath.c" "$TOP/version/version.o" $LIBS \
	-o "$OUT/cppath-broken" || {
	echo "FAIL: could not build cppath-broken"; exit 2; }

# ------------------------------------------------------------------ helpers --
fresh_s5() { rm -rf "$S5"; mkdir -p "$S5"; : > "$LOG"; }

# s5run <binary> <src> <dst> -- run under the simulated s5 filesystem
s5run() {
	_bin="$1"; _src="$2"; _dst="$3"
	S5SIM_ROOT="$S5" S5SIM_LOG="$LOG" LD_PRELOAD="$OUT/s5sim.so" \
		"$OUT/$_bin" "$_src" "$_dst" >>"$OUT/log" 2>>"$OUT/log"
	return $?
}

want_rc() {	# want_rc <desc> <expected> <actual>
	if [ "$3" = "$2" ]; then ok "$1 (rc=$3)"; else bad "$1 (rc=$3, want $2)"; fi
}

want_content() {	# want_content <desc> <file> <expected-source>
	if [ -f "$2" ] && cmp -s "$2" "$3"; then ok "$1"
	else bad "$1 ($2 is not $(basename "$3"))"; fi
}

want_grep() {	# want_grep <desc> <pattern> <file>
	if grep -q -- "$2" "$3"; then ok "$1"; else bad "$1 (no match: $2)"; fi
}

want_count() {	# want_count <desc> <dir> <expected number of entries>
	_n="$(ls -a "$2" | grep -vc '^\.\{1,2\}$')"
	if [ "$_n" = "$3" ]; then ok "$1"
	else bad "$1 ($_n entries, want $3: $(ls "$2" | tr '\n' ' '))"; fi
}

: > "$OUT/log"

# --------------------------------------------------------------------- A ----
# The upgrade defect itself: lay a >=14-character basename down, then lay it
# down AGAIN (what `apkg upgrade` and any re-install do).
echo
echo "A. re-install over an existing 17-character basename (the upgrade case)"

fresh_s5
s5run cppath-broken "$SRC/a" "$S5/typescript.stage1"; rc=$?
want_rc   "A1 upstream template: fresh install succeeds" 0 $rc
want_content "A1 landed as the truncated dirent typescript.sta" \
	"$S5/typescript.sta" "$SRC/a"

s5run cppath-broken "$SRC/b" "$S5/typescript.stage1"; rc=$?
want_rc   "A2 upstream template: RE-install FAILS (the defect)" 1 $rc
want_grep "A2 fails with the bench fingerprint: empty template in ERR_MKTEMP" \
	'unable to create unique temporary file <>' "$OUT/log"
want_content "A2 the existing file is left untouched" \
	"$S5/typescript.sta" "$SRC/a"
want_grep "A2 mkstemp exhausted every candidate" \
	'mkstemp   EXHAUSTED' "$LOG"

fresh_s5
s5run cppath-fixed "$SRC/a" "$S5/typescript.stage1"; rc=$?
want_rc   "A3 shipped template: fresh install succeeds" 0 $rc
s5run cppath-fixed "$SRC/b" "$S5/typescript.stage1"; rc=$?
want_rc   "A4 shipped template: RE-install SUCCEEDS (the fix)" 0 $rc
want_content "A4 the dirent now holds the new payload" \
	"$S5/typescript.sta" "$SRC/b"
want_count "A4 no temporary file left behind" "$S5" 1
want_grep "A4 template basename is 14 bytes: typescriXXXXXX" \
	'template=<'"$S5"'/typescriXXXXXX> (basename 14 chars)' "$LOG"

# --------------------------------------------------------------------- B ----
# The exact W6 bench failure: two DIFFERENT names that alias to one dirent.
echo
echo "B. the W6 bench case: typescript.stage1 then typescript.stage2"

fresh_s5
s5run cppath-broken "$SRC/a" "$S5/typescript.stage1"
s5run cppath-broken "$SRC/b" "$S5/typescript.stage2"; rc=$?
want_rc   "B1 upstream template: the second name FAILS (as on the bench)" 1 $rc

fresh_s5
s5run cppath-fixed "$SRC/a" "$S5/typescript.stage1"
s5run cppath-fixed "$SRC/b" "$S5/typescript.stage2"; rc=$?
want_rc   "B2 shipped template: the second name no longer fails ERR_MKTEMP" 0 $rc
# NOTE: the two names still share ONE dirent -- that aliasing is intrinsic to
# s5 and is what docs/s5-14char-collisions.md Option A (drop the colliding
# objects) addresses.  This fix removes the mkstemp failure, not the aliasing:
# the surviving content is the last one written, and pkgadd's own size/cksum
# verification is what reports the loss.
want_content "B2 the shared dirent holds the last write (aliasing remains)" \
	"$S5/typescript.sta" "$SRC/b"

# --------------------------------------------------------------------- C ----
# Short basenames must keep upstream's template byte for byte.
echo
echo "C. short basenames are untouched by the cap"

fresh_s5
s5run cppath-fixed "$SRC/a" "$S5/data.txt"
s5run cppath-fixed "$SRC/b" "$S5/data.txt"; rc=$?
want_rc   "C1 overwrite of an 8-character basename succeeds" 0 $rc
want_grep "C1 template is upstream's exactly: data.txtXXXXXX" \
	'template=<'"$S5"'/data.txtXXXXXX>' "$LOG"
want_content "C1 payload replaced" "$S5/data.txt" "$SRC/b"

# --------------------------------------------------------------------- D ----
# A long-named filesystem must not regress: same code, no simulation.
echo
echo "D. ordinary (255-character) filesystem: no regression"

rm -rf "$PLAIN"; mkdir -p "$PLAIN"
LONG="$PLAIN/a-thirty-character-basename.txt"
"$OUT/cppath-fixed" "$SRC/a" "$LONG" >>"$OUT/log" 2>&1
"$OUT/cppath-fixed" "$SRC/b" "$LONG" >>"$OUT/log" 2>&1; rc=$?
want_rc   "D1 overwrite on a normal filesystem succeeds" 0 $rc
want_content "D1 payload replaced, full name preserved" "$LONG" "$SRC/b"
want_count "D1 no temporary file left behind" "$PLAIN" 1

# --------------------------------------------------------------------- E ----
# The relative-path branch of write_file() ("./" + template).
echo
echo "E. relative destination (write_file's RELATIVE branch)"

fresh_s5
cp "$SRC/a" "$S5/typescript.sta"
( cd "$S5" && S5SIM_ROOT="$S5" S5SIM_LOG="$LOG" \
	LD_PRELOAD="$OUT/s5sim.so" "$OUT/cppath-fixed" "$SRC/b" \
	typescript.stage1 >>"$OUT/log" 2>&1 ); rc=$?
want_rc   "E1 relative overwrite succeeds" 0 $rc
want_grep "E1 template keeps the './' prefix and the 14-byte cap" \
	'template=<./typescriXXXXXX>' "$LOG"
want_content "E1 payload replaced" "$S5/typescript.sta" "$SRC/b"
want_count "E1 no temporary file left behind" "$S5" 1

# ---------------------------------------------------------------------------
echo
echo "$pass passed, $fail failed   (transcript: $OUT/log, shim log: $LOG)"
if [ "$fail" = 0 ]; then
	echo "== s5-14char: ALL PASS =="
	exit 0
fi
echo "== s5-14char: FAILURES =="
exit 1
