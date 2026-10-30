#!/bin/sh
#
# build.sh -- build the amix-bench suite with GCC 14 and roll the
# amix-benchmark-gcc14 package (PKG amixbch14).
#
#     sh recipes/amix-benchmark-gcc14/build.sh       (TOOLCHAIN=gcc14 implied)
#
# Outputs under the gitignored build/ tree:
#
#     build/gcc14/amix-benchmark-gcc14/src/    the pinned sources (git archive)
#     build/gcc14/amix-benchmark-gcc14/dest/   the staged install tree
#     build/gcc14/pkg/amixbch14-1.3-4.pkg      the datastream
#
# ---------------------------------------------------------------------------
# WHAT THIS PACKAGE IS FOR.  amix-benchmark (PKG amixbench, recipes/
# amix-benchmark) ships the validated fieldkit binaries, built with gcc 2.7.2.3,
# verbatim -- they are the reference the published results were measured with,
# and they stay exactly as they are.  This package is the same benchmark
# compiled with GCC 14 (owner decision 2026-10-27: the userland switch; ship
# both, side by side), so one box can run both and compare the compilers:
#
#   - the same five benchmark sources the period binaries were built from
#     (pin.sh says how that commit was identified) and the same runbench.sh
#     driver file the period package ships -- the binaries are the only
#     difference;
#   - its own names everywhere a file lands: entry command amix-bench-g14, kit
#     /opt/amix/lib/amix-bench-g14, doc /opt/amix/doc/amix-bench-g14.  No file
#     is shared with amixbench, so either installs and removes without the
#     other noticing.  Inside the kit the binaries keep their names (dhry,
#     iobench, ...): runbench.sh finds them by those names beside itself, and
#     keeping the driver byte-identical to the period package's is what makes
#     the two sets of numbers comparable.  (-gcc14 suffixes would also not fit
#     the entry command: amix-bench-gcc14 is 16 bytes, s5 keeps 14.)
#   - BUILD-INFO names the compiler; runbench.sh prints every BUILD-INFO key in
#     each results header (build_cc_version=GCC: (GNU) 14.2.0 here, 2.7.2.3 in
#     the period package), so every report says which build produced it.
#
# FLAGS.  The period flags, with what GCC 14 needs to mean the same thing:
#   dhry      -std=gnu89 -O2 -fno-inline -DHZ=60 -Dfloat=double.  dhry.c is the
#             1988 netlib source, kept byte-pristine; it calls its own Proc_*
#             before defining them, which C89 allows and GCC 14's default
#             dialect rejects -- gnu89 is the dialect gcc 2.7 compiled it in
#             (build-fieldkit.sh's host build uses -std=c89 for the same
#             reason).  The period build's -fno-inline-functions meant "nothing
#             is inlined" on gcc 2.7, whose -O2 inlines nothing unasked; GCC
#             14's -O2 inlines small and called-once functions, which would put
#             Proc_* into the measured loop, so -fno-inline says it here.
#             -Dfloat=double stays: it is a gcc 2.7 assembler workaround that
#             changes nothing timed, and keeping it keeps the source identical.
#   fpbench   -O0 -Wall, load-bearing (constant folding; build-fieldkit.sh), and
#             the build counts its FP instructions against the same floor.
#   iobench, membench, vmbench   -O2 -Wall.
# All with gcc14-env.sh's AMIX_ARCH_FLAGS, -m68020-60 -mno-strict-align (one
# binary for the 030 and 060 lines; no 040/060-only FPU form, which the FPU
# gate re-checks).  build-fieldkit.sh's
# no-fcmp gate is a gcc 2.7 + SGS-operand-order defect gate; GCC 14 hands gas
# its compares in gas's own order, so it does not apply (the emulator smoke
# runs fpu.paranoia, which checks comparisons).

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

export AMIX_PREFIX=/opt/amix
# This package IS the GCC 14 build; there is no period variant of it.
TOOLCHAIN="${TOOLCHAIN:-gcc14}"
export TOOLCHAIN
AMIX_RECIPE_TOOLCHAINS="gcc14"

. "$REPO/recipes/common/amix-env.sh"
. "$REPO/recipes/common/fetch.sh"
. "$REPO/recipes/common/pkgroll.sh"
. "$REPO/recipes/common/gates.sh"
. "$HERE/pin.sh"

PKG=amixbch14
CATALOG_NAME=amix-benchmark-gcc14
VERSION=$AMIXBENCH_G14_VERSION

BUILD="$AMIX_BUILD_ROOT/amix-benchmark-gcc14"
SRC="$BUILD/src"
OBJ="$BUILD/obj"
DEST="$BUILD/dest"
PKGOUT="$AMIX_BUILD_ROOT/pkg"
KITDIR="$DEST/opt/amix/lib/amix-bench-g14"

DHRY_CFLAGS="$AMIX_ARCH_FLAGS -std=gnu89 -O2 -fno-inline -DHZ=60 -Dfloat=double"
IOBENCH_CFLAGS="$AMIX_ARCH_FLAGS -O2 -Wall"
FPBENCH_CFLAGS="$AMIX_ARCH_FLAGS -O0 -Wall"
MEMBENCH_CFLAGS="$AMIX_ARCH_FLAGS -O2 -Wall"
VMBENCH_CFLAGS="$AMIX_ARCH_FLAGS -O2 -Wall"
FP_FLOOR=20

echo "=== amix-benchmark-gcc14 $VERSION (PKG=$PKG, catalog=$CATALOG_NAME) ==="
amix_env_banner
echo "  sources   : $AMIX_KERNTOOLS @ ${AMIXBENCH_SRC_COMMIT%${AMIXBENCH_SRC_COMMIT#???????}} (benchmarks), ${AMIXBENCH_KIT_COMMIT%${AMIXBENCH_KIT_COMMIT#???????}} (driver)"
echo

# ---------------------------------------------------------------------------
# 1. Sources: git archive of the two pinned commits, every file verified.
# ---------------------------------------------------------------------------
echo "--- sources ---"
[ -d "$AMIX_KERNTOOLS/.git" ] || {
	echo "[FAIL] amix-kerntools not found at $AMIX_KERNTOOLS (set AMIX_KERNTOOLS)" >&2; exit 1; }
rm -rf "$SRC" "$OBJ" "$DEST"
mkdir -p "$SRC/bench" "$SRC/kit" "$OBJ" "$PKGOUT"
for c in "$AMIXBENCH_SRC_COMMIT" "$AMIXBENCH_KIT_COMMIT"; do
	git -C "$AMIX_KERNTOOLS" cat-file -e "$c^{commit}" 2>/dev/null || {
		echo "[FAIL] amix-kerntools has no commit $c" >&2; exit 1; }
done
git -C "$AMIX_KERNTOOLS" archive "$AMIXBENCH_SRC_COMMIT" \
	$(echo "$AMIXBENCH_SRC_PINS" | awk '{print $1}') | tar -x -C "$SRC/bench"
git -C "$AMIX_KERNTOOLS" archive "$AMIXBENCH_KIT_COMMIT" \
	$(echo "$AMIXBENCH_KIT_PINS" | awk '{print $1}') | tar -x -C "$SRC/kit"
echo "$AMIXBENCH_SRC_PINS" | while read p want; do
	[ -n "$p" ] || continue
	amix_verify "$SRC/bench/$p" "$want"
done
echo "$AMIXBENCH_KIT_PINS" | while read p want; do
	[ -n "$p" ] || continue
	amix_verify "$SRC/kit/$p" "$want"
done
S="$SRC/bench/tools/amix-bench/src"
K="$SRC/kit/tools/amix-bench/fieldkit"
echo

# ---------------------------------------------------------------------------
# 2. Compile.  Warnings are kept per binary; an error stops the build.
# ---------------------------------------------------------------------------
echo "--- compile (GCC 14) ---"
mkdir -p "$KITDIR"
build_one() {	# build_one <name> <source> <cflags>
	echo "  CC   $1  ($3)"
	( cd "$S" && $CC $3 -o "$KITDIR/$1" "$2" ) > "$OBJ/$1.log" 2>&1 || {
		echo "[FAIL] $1 did not build:" >&2; cat "$OBJ/$1.log" >&2; exit 1; }
	if [ -s "$OBJ/$1.log" ]; then
		grep 'warning:' "$OBJ/$1.log" | sed 's/^/         /'
	fi
}
build_one dhry     dhry.c     "$DHRY_CFLAGS"
build_one iobench  iobench.c  "$IOBENCH_CFLAGS"
build_one fpbench  fpbench.c  "$FPBENCH_CFLAGS"
build_one membench membench.c "$MEMBENCH_CFLAGS"
build_one vmbench  vmbench.c  "$VMBENCH_CFLAGS"
# dhry is vendored, warnings tolerated (build-fieldkit.sh); the other four are
# ours and must be warning-clean.
for b in iobench fpbench membench vmbench; do
	if grep 'warning:' "$OBJ/$b.log" >/dev/null 2>&1; then
		echo "[FAIL] $b compiled with warnings (ours; must be clean)" >&2; exit 1
	fi
done
echo "  iobench, fpbench, membench, vmbench warning-clean"
nfp=$("$OBJDUMP" -d "$KITDIR/fpbench" | grep -cE '\bf(add|sub|mul|div)' || true)
[ "$nfp" -ge "$FP_FLOOR" ] || {
	echo "[FAIL] fpbench has only $nfp FP add/sub/mul/div (floor $FP_FLOOR): constant-folded" >&2; exit 1; }
echo "  -O0 gate: fpbench contains $nfp FP instructions (floor $FP_FLOOR)"
echo

# ---------------------------------------------------------------------------
# 3. The kit: the period driver verbatim, BUILD-INFO naming the compiler.
# ---------------------------------------------------------------------------
echo "--- kit ---"
cp "$K/runbench.sh" "$KITDIR/runbench.sh"
mkdir -p "$DEST/opt/amix/bin" "$DEST/opt/amix/doc/amix-bench-g14"
cp "$HERE/files/amix-bench-g14" "$DEST/opt/amix/bin/amix-bench-g14"
cp "$K/README-FIELD.txt" "$DEST/opt/amix/doc/amix-bench-g14/README.txt"

# The compiler's own .ident, read from a stub's assembly (as build-fieldkit.sh).
printf 'int amix_bench_version_probe;\n' > "$OBJ/v.c"
$CC -S -o "$OBJ/v.s" "$OBJ/v.c"
CC_VERSION=$(grep -ao 'GCC: ([^)]*)[^"]*' "$OBJ/v.s" | head -1)
[ -n "$CC_VERSION" ] || { echo "[FAIL] could not read the compiler's .ident" >&2; exit 1; }
# the PINNED toolchain commit (gcc14-env.sh verified the prefix against it)
G14_COMMIT=$(echo "$AMIX_GCC14_COMMIT" | cut -c1-7)
BENCH_VERSION_SRC=$(sed -n 's/^#define BENCH_VERSION "\(.*\)"/\1/p' "$S/bench-compat.h" | head -1)
sum256() { sha256sum "$1" | cut -d' ' -f1; }
{
	echo "AMIX-BENCH-BUILD 1"
	echo "tool_version=$BENCH_VERSION_SRC"
	echo "target=m68k-cbm-sysv4"
	echo "mode=cross"
	echo "cc=m68k-elf-gcc"
	echo "cc_version=$CC_VERSION"
	echo "toolchain=gcc14-cross-amix $G14_COMMIT (package $CATALOG_NAME $VERSION)"
	echo "dhry_cflags=$DHRY_CFLAGS"
	echo "iobench_cflags=$IOBENCH_CFLAGS"
	echo "fpbench_cflags=$FPBENCH_CFLAGS"
	echo "membench_cflags=$MEMBENCH_CFLAGS"
	echo "vmbench_cflags=$VMBENCH_CFLAGS"
	echo "whet=not-built"
	echo "dhry_hz=60"
	echo "dhry_sha256=$(sum256 "$S/dhry.c")"
	echo "iobench_sha256=$(sum256 "$S/iobench.c")"
	echo "fpbench_sha256=$(sum256 "$S/fpbench.c")"
	echo "membench_sha256=$(sum256 "$S/membench.c")"
	echo "vmbench_sha256=$(sum256 "$S/vmbench.c")"
	echo "sources=amix-kerntools $AMIXBENCH_SRC_COMMIT"
} > "$KITDIR/BUILD-INFO"
sed 's/^/  /' "$KITDIR/BUILD-INFO"
echo

# ---------------------------------------------------------------------------
# 4. Gates -- object code, not exit status (pkgroll adds the whole gcc14 set).
# ---------------------------------------------------------------------------
echo "--- gates ---"
BINS="$KITDIR/dhry $KITDIR/iobench $KITDIR/fpbench $KITDIR/membench $KITDIR/vmbench"
amix_gate_elf $BINS
amix_gate_d4 $BINS || { echo "[FAIL] D4 gate: a benchmark binary SIGKILLs on a 68LC060." >&2; exit 1; }
for b in $BINS; do amix_gate_undef "$b"; done
for b in $BINS; do
	if "$NM" "$b" | awk '$2 == "T" {print $3}' | grep -xE 'sin|cos|tan|atan|atan2|exp|log|log10|sqrt|matherr' >/dev/null; then
		echo "[FAIL] $(basename "$b") defines libm symbols -- stock SVR4 libm must not ship" >&2; exit 1
	fi
done
echo "  no libm object code in any binary"
echo

# ---------------------------------------------------------------------------
# 5. PROVENANCE, stripped binaries, pinned mtimes.
# ---------------------------------------------------------------------------
# Unlike the period kit (shipped verbatim, unstripped, to keep its pins), these
# binaries are built here, so they are stripped; their digests are recorded in
# PROVENANCE after the strip.
for b in $BINS; do $STRIP "$b"; done
chmod 0755 "$DEST/opt/amix/bin/amix-bench-g14" "$KITDIR/runbench.sh" $BINS
chmod 0644 "$KITDIR/BUILD-INFO" "$DEST/opt/amix/doc/amix-bench-g14/README.txt"
{
	echo "AMIX-BENCHMARK-GCC14 PACKAGE PROVENANCE"
	echo "======================================="
	echo "package        : $CATALOG_NAME (SVR4 PKG instance: $PKG)"
	echo "version        : $VERSION"
	echo "recipe         : amix-packages recipes/amix-benchmark-gcc14"
	echo "compiler       : $CC_VERSION, gcc14-cross-amix $G14_COMMIT"
	echo "benchmarks     : amix-kerntools $AMIXBENCH_SRC_COMMIT tools/amix-bench/src"
	echo "                 (the sources amix-benchmark's gcc 2.7.2.3 binaries were"
	echo "                 built from; their sha256s match that kit's BUILD-INFO)"
	echo "driver, README : amix-kerntools $AMIXBENCH_KIT_COMMIT tools/amix-bench/fieldkit"
	echo "                 (byte-identical to the files amix-benchmark ships)"
	echo
	echo "The two packages differ only in the compiler.  Each results header"
	echo "carries the BUILD-INFO keys, so build_cc_version names it."
	echo
	echo "whet (Whetstone) is not built: it would statically link the stock SVR4"
	echo "libm.a, which this repository does not ship; fpu.whet reports skipped."
	echo
	echo "sha256 of each shipped file:"
	for f in runbench.sh dhry iobench fpbench membench vmbench BUILD-INFO; do
		printf '  %-14s %s\n' "$f" "$(sum256 "$KITDIR/$f")"
	done
} > "$KITDIR/PROVENANCE"
chmod 0644 "$KITDIR/PROVENANCE"
find "$DEST" -exec touch -h -d "@$AMIXBENCH_SOURCE_EPOCH" {} +

echo "--- payload identity (sum -r, the only digest the box can compute) ---"
for b in $BINS; do
	printf '  %-10s %s  %s bytes\n' "$(basename "$b")" "$(sum -r "$b" | awk '{print $1}')" "$(stat -c%s "$b")"
done
echo

# ---------------------------------------------------------------------------
# 6. Roll the datastream.
# ---------------------------------------------------------------------------
echo "--- package ---"
WORK="$BUILD/pkgwork"
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_pkgroll "$WORK" "$DEST" "$PKG" "$VERSION" "$PKGOUT/$PKG-$VERSION.pkg"
echo
echo "=== amix-benchmark-gcc14 $VERSION built: $PKGOUT/$PKG-$VERSION.pkg ==="
