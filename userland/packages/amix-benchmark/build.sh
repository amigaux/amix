#!/bin/sh
#
# build.sh -- assemble the amix-benchmark SVR4 .pkg from the amix-bench fieldkit.
#
#     sh recipes/amix-benchmark/build.sh
#
# Outputs under the gitignored build/ tree:
#
#     build/amix-benchmark/dest/          the staged install tree (/opt/amix/...)
#     build/pkg/amixbench-1.2.pkg         the datastream
#
# ---------------------------------------------------------------------------
# WHAT THIS RECIPE DOES DIFFERENTLY, AND WHY.
#
# Every other recipe here fetches an upstream tarball and CROSS-BUILDS it.  This
# one does not build anything: amix-bench is our own suite and its prebuilt m68k
# SVR4 binaries (the "fieldkit", in ../amix-kerntools/tools/amix-bench/fieldkit)
# ARE the validated reference artifacts.  Rebuilding them would risk a silent
# codegen difference on gcc 2.7.2.3 that cannot be caught without running the
# result on a 68k -- and a benchmark that miscompiles reports WRONG NUMBERS,
# which is worse than not shipping (the sources carry deliberate gcc-2.7.2.3
# workarounds this recipe must not disturb).  So the package ships the exact,
# validated bytes, verified against the sha256 pins in pin.sh before staging.
# See pin.sh for the full argument.
#
# The recipe still ends where every recipe here ends: the object-code gates on
# the shipped binaries (ELF machine, D4 68LC060 multiply, undefined-symbol
# surface).  "Verify the artifact, never the exit status" applies to a binary
# you ship verbatim exactly as much as to one you built.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

export AMIX_PREFIX=/opt/amix

. "$REPO/recipes/common/amix-env.sh"
. "$REPO/recipes/common/fetch.sh"
. "$REPO/recipes/common/pkgroll.sh"
. "$REPO/recipes/common/gates.sh"
. "$HERE/pin.sh"

PKG=amixbench
CATALOG_NAME=amix-benchmark
VERSION=$AMIXBENCH_VERSION

BUILD="$REPO/build/amix-benchmark"
DEST="$BUILD/dest"
PKGOUT="$REPO/build/pkg"
KITDIR="$DEST/opt/amix/lib/amix-bench"

FIELDKIT="$AMIX_BENCH_FIELDKIT"

echo "=== amix-benchmark $VERSION (PKG=$PKG, catalog=$CATALOG_NAME) ==="
amix_env_banner
echo "  fieldkit  : $FIELDKIT"
echo

[ -d "$FIELDKIT" ] || {
	echo "[FAIL] amix-bench fieldkit not found: $FIELDKIT" >&2
	echo "       It lives in ../amix-kerntools/tools/amix-bench/fieldkit; set" >&2
	echo "       AMIX_BENCH_FIELDKIT if your workspace layout differs." >&2
	exit 1
}

# ---------------------------------------------------------------------------
# 1. Verify every pinned file BEFORE it is staged (fetch.sh discipline).
# ---------------------------------------------------------------------------
echo "--- verify fieldkit sources against the pins ---"
echo "$AMIXBENCH_PINS" | while read name want; do
	[ -n "$name" ] || continue
	[ -f "$FIELDKIT/$name" ] || {
		echo "[FAIL] fieldkit file missing: $FIELDKIT/$name" >&2; exit 1; }
	amix_verify "$FIELDKIT/$name" "$want"
done
echo

# ---------------------------------------------------------------------------
# 2. Stage the tree (verbatim copies -- NOT stripped; see pin.sh).
# ---------------------------------------------------------------------------
echo "--- stage ---"
rm -rf "$DEST"
mkdir -p "$DEST/opt/amix/bin" "$KITDIR" \
         "$DEST/opt/amix/man/man1" "$DEST/opt/amix/doc/amix-benchmark"

# the entry command + the man page come from the recipe (ours)
cp "$HERE/files/amix-bench"   "$DEST/opt/amix/bin/amix-bench"
cp "$HERE/files/amix-bench.1" "$DEST/opt/amix/man/man1/amix-bench.1"

# the kit -- driver, binaries, BUILD-INFO -- verbatim from the fieldkit
cp "$FIELDKIT/runbench.sh" "$KITDIR/runbench.sh"
for b in dhry iobench fpbench membench vmbench; do
	cp "$FIELDKIT/$b" "$KITDIR/$b"
done
cp "$FIELDKIT/BUILD-INFO" "$KITDIR/BUILD-INFO"

# field README -> doc (renamed to a <= 14-byte basename for s5)
cp "$FIELDKIT/README-FIELD.txt" "$DEST/opt/amix/doc/amix-benchmark/README.txt"

chmod 0755 "$DEST/opt/amix/bin/amix-bench" "$KITDIR/runbench.sh" \
           "$KITDIR/dhry" "$KITDIR/iobench" "$KITDIR/fpbench" \
           "$KITDIR/membench" "$KITDIR/vmbench"
chmod 0644 "$KITDIR/BUILD-INFO" "$DEST/opt/amix/man/man1/amix-bench.1" \
           "$DEST/opt/amix/doc/amix-benchmark/README.txt"
echo "  staged $DEST/opt/amix"
echo

# ---------------------------------------------------------------------------
# 3. Gates -- read object code out of the shipped binaries.
# ---------------------------------------------------------------------------
echo "--- gates ---"
BINS="$KITDIR/dhry $KITDIR/iobench $KITDIR/fpbench $KITDIR/membench $KITDIR/vmbench"
amix_gate_elf $BINS
amix_gate_d4  $BINS || {
	echo "[FAIL] D4 gate: a benchmark binary SIGKILLs on a 68LC060." >&2
	exit 1; }
for b in $BINS; do amix_gate_undef "$b"; done
echo

# ---------------------------------------------------------------------------
# 4. Generate PROVENANCE into the kit -- so the shipped numbers are attributable.
# ---------------------------------------------------------------------------
echo "--- provenance ---"
{
	echo "AMIX-BENCHMARK PACKAGE PROVENANCE"
	echo "================================="
	echo "package        : $CATALOG_NAME (SVR4 PKG instance: $PKG)"
	echo "version        : $VERSION"
	echo "recipe         : amix-packages recipes/amix-benchmark"
	echo "source         : amix-bench fieldkit, amix-kerntools tools/amix-bench"
	echo "                 (pinned; see the sha256 list below)"
	echo
	echo "This file is a pure function of the pinned inputs -- no build"
	echo "timestamp or host name -- so the package builds reproducibly and its"
	echo "md5 is stable for the catalog."
	echo
	echo "The five packaged benchmark binaries and the runbench.sh driver are shipped"
	echo "VERBATIM (unstripped) from the amix-bench fieldkit -- the validated"
	echo "reference artifacts.  They were NOT rebuilt for this package.  Their"
	echo "own build provenance is in BUILD-INFO beside this file; the toolchain"
	echo "it records:"
	echo
	sed -n 's/^/  /p' "$KITDIR/BUILD-INFO"
	echo
	echo "sha256 of each file shipped (verified before staging):"
	echo "$AMIXBENCH_PINS" | while read name want; do
		[ -n "$name" ] || continue
		printf '  %-16s %s\n' "$name" "$want"
	done
	echo
	echo "All five binaries: m68k SVR4 ELF, DT_NEEDED = [/usr/lib/libc.so.1] only,"
	echo "and pass the D4 gate (no mulu.l/muls.l with a Dh:Dl destination), so they"
	echo "run on the 68030 and the 68LC060 lanes alike.  runbench.sh reports"
	echo "BENCH_FORMAT=1 / TOOL_VERSION=1.0 (the results-format version); the"
	echo "fieldkit is 1.2 and this package is version $VERSION."
	echo
	echo "WHY THERE IS NO 'whet' (Whetstone) IN THIS PACKAGE"
	echo "--------------------------------------------------"
	echo "The fieldkit's sixth benchmark, whet, statically links the stock SVR4"
	echo "math library: nm shows it defining sin, cos, tan, atan, atan2, exp,"
	echo "log, log10, sqrt and matherr, and those objects come from the sysroot's"
	echo "/usr/ccs/lib/libm.a -- Commodore/AT&T object code, not ours.  This"
	echo "repository ships only our own builds, so whet is omitted for licence."
	echo "The other five binaries embed no libm at all."
	echo
	echo "Consequence, and it is harmless: runbench.sh reports"
	echo "  TEST fpu.whet status=skipped reason=no-whet-in-this-kit"
	echo "by design, and the results header's tools= line records which binaries"
	echo "this kit carried.  Every other row runs normally."
} > "$KITDIR/PROVENANCE"
chmod 0644 "$KITDIR/PROVENANCE"
echo "  wrote $KITDIR/PROVENANCE"
echo

# ---------------------------------------------------------------------------
# 4b. Normalise mtimes -> reproducible datastream.
# ---------------------------------------------------------------------------
# heirloom pkgmk records each staged file's mtime in the pkgmap and the cpio
# member header, so a plain `cp` (which stamps the copy time) makes every
# payload member's timestamp -- and thus the .pkg md5 -- move on each rebuild
# for no content change.  Pin every staged PAYLOAD path to one fixed epoch (the
# kit's last-change date, 2026-09-15) so all 22 payload members are a pure
# function of their contents.
#
# The ONE member this cannot fix is the `i pkginfo` control file: pkgmk writes
# its own processed copy into the spool and stamps it with the build wall-clock,
# so that single member's mtime still moves across builds >1 s apart.  That is a
# pkgmk property shared by every package in this repo (all go through the same
# pkgmk), and the payload checksums never depended on it -- so the CONTENT is
# reproducible and only that one metadata timestamp drifts.  The as-built .pkg
# md5 is recorded in the catalog at publish time, the family convention.
echo "--- normalise payload mtimes ($AMIXBENCH_SOURCE_EPOCH) ---"
find "$DEST" -exec touch -h -d "@$AMIXBENCH_SOURCE_EPOCH" {} +
echo

# ---------------------------------------------------------------------------
# 5. Roll the datastream.
# ---------------------------------------------------------------------------
echo "--- package ---"
WORK="$BUILD/pkgwork"
rm -rf "$WORK"; mkdir -p "$WORK" "$PKGOUT"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_pkgroll "$WORK" "$DEST" "$PKG" "$VERSION" "$PKGOUT/$PKG-$VERSION.pkg"
echo
echo "=== amix-benchmark $VERSION built: $PKGOUT/$PKG-$VERSION.pkg ==="
