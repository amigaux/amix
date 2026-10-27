#!/bin/sh
# l5.sh -- the stage-4 exit row "L5 by root modules" (docs/spec/10-boot-
# loader.md §5.3, C4-4 §4): a store image whose trial generation's root
# set does not fit the kernel's arena, so boot2 refuses it with L5 and
# boots the good generation.  kbootset cannot write it (gate 4 refuses
# such a generation, from `build` and from `commit --spec` alike), so the
# row writes this image over a slot copy's boot slice, as S3-43's l5.img.
#   generation 1 (good)   the box's generation as kbootset composed it
#   generation 2 (trial)  the same, its last root module's bss= raised to
#                         the arena's capacity: the module cannot fit
# The kernel is deflated (z=deflate) so both fit the slice.
#
# usage: l5.sh ROOT BUILD OUTDIR [STORESIZE]
#   ROOT   a copy of the box's root tree (its /stand/<line>/unix and the
#          generation's /stand/gen/<id>/mod/ copies)
#   BUILD  that generation's /stand/gen/<id>/build, from `kbootset build`
#   STORESIZE the vehicle's boot slice in bytes (default 4 MiB)
# Writes OUTDIR/l5.img, its two specs and OUTDIR/expected.txt.
# Needs build/mkstore, build/boot1.img and build/boot2.bin (`make`).
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
ROOT=$1 BUILD=$2 OUT=$3 SSIZE=${4:-4194304}
R=$(cd "$(dirname "$0")/../../.." && pwd)
[ -d "$ROOT" ] && [ -f "$BUILD" ] && [ -n "$OUT" ] ||
	{ echo "usage: l5.sh ROOT BUILD OUTDIR [STORESIZE]" >&2; exit 2; }
CAP=$(awk '$1 == "arena" { print $3 }' "$BUILD")
CAPD=$((CAP))
LAST=$(awk '$1 == "module" && $3 == "root" { n = $2 } END { print n }' "$BUILD")
[ -n "$CAP" ] && [ -n "$LAST" ] ||
	{ echo "l5.sh: $BUILD is not a module generation with root modules" >&2; exit 1; }
mkdir -p "$OUT"
# a build file as a spec: host paths in place of the sizes, the attributes
# mkstore writes itself dropped; BIG names the module whose bss= is raised
spec() {	# spec ID STATE BIG
	printf 'generation %s\nstate %s\n' "$1" "$2"
	awk -v R="$ROOT" -v big="$3" -v cap="$CAPD" '
	$1 == "kernel" { print $1, $2, R $3, "z=deflate"; next }
	$1 == "module" && $3 == "root" {
		p = ""; a = ""
		for (i = 5; i <= NF; i++) {
			f = $i
			if (f ~ /^path=/) { p = substr(f, 6); continue }
			if (f ~ /^(at|crc32|sha256)=/) continue
			if ($2 == big && f ~ /^bss=/) f = "bss=" cap
			a = a " " f
		}
		print $1, $2, $3, R p a; next }
	$1 ~ /^(generation|state|created)$/ { next }
	{ print }' "$BUILD"
}
spec 1 good "" > "$OUT/l5-g1.spec"
spec 2 trial "$LAST" > "$OUT/l5-g2.spec"
grep -q "^module $LAST root .* bss=$((CAP))\( \|$\)" "$OUT/l5-g2.spec" ||
	{ echo "l5.sh: the raised bss= is not in generation 2's spec" >&2; exit 1; }
rm -f "$OUT/l5.img"
"$R/build/mkstore" -o "$OUT/l5.img" -s "$SSIZE" -1 "$R/build/boot1.img" -2 "$R/build/boot2.bin" \
	-d 1 "$OUT/l5-g1.spec" "$OUT/l5-g2.spec" > "$OUT/mkstore.log"
"$R/build/lsstore" "$OUT/l5.img" 0 > "$OUT/lsstore.txt"
grep -q "lsstore: ok" "$OUT/lsstore.txt" || { cat "$OUT/lsstore.txt" >&2; exit 1; }
{
	echo "boot 1 (generation 2, the trial):"
	awk '$1 == "module" && $3 == "root" { print "  amix-boot: module " $2 " <size> bytes" }' "$OUT/l5-g1.spec" |
		sed "/module $LAST /,\$d"
	echo "  amix-boot: the arena needs <more than $((CAP))> bytes, it has $((CAP))"
	echo "  amix-boot: L5 arena overflow (generation 2)"
	echo "  amix-boot: generation 1, kernel ...   (the fallback boots to multi-user)"
	echo "boot 2: amix-boot: L8 trial not confirmed (generation 2); generation 1 boots"
} > "$OUT/expected.txt"
echo "l5.sh: $OUT/l5.img (generation 1 good, 2 trial with $LAST's bss=$((CAP)); $SSIZE bytes)"
