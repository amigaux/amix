#!/bin/sh
# df0-pair.sh -- the floppy pairs for the DF0 rows (M-FD1, M-FP2; docs/plan/
# stage-1.md S1-27): one per line, the 1.0 static floppy kernel stored
# uncompressed so it is larger than volume 1 and runs on into volume 2.
# The boot then reads about 1.3-1.5 MB through the floppy DMA and asks for
# volume 2 in the middle of the kernel.  A stage-1 loader refuses RAM-disk
# generations (L9), so the pair carries the kernel only; the kernel roots on
# fd0 as in 1.0, so after the hand-off DF0 takes the 1.0 root floppy.
#
# usage: df0-pair.sh <workspace> <outdir>
# Writes <outdir>/df0-k30-{1,2}.adf and df0-k46-{1,2}.adf, each verified
# with lsstore and with boot2's own reader (b2medium).
# Run from the repository root after `make tools build/b2medium boot1 boot2`.
set -e
WS=$1 OUT=$2
B=${B:-build}
K=$WS/amix-kerntools/work/k0-chains
mkdir -p "$OUT"
cp "$K/K030-U-FD/K030-U-FD-c0-u6" "$OUT/k30.brel"
python3 -I "$WS/amix-kerntools/tools/elf2brel.py" "$K/KD060-FD/KD060-FD-fd0" "$OUT/k46.brel" >/dev/null
for line in k30 k46; do
	printf 'generation 1\nstate good\nline %s\nrootfs ufs\nkernel unix %s\n' \
		$line "$OUT/$line.brel" > "$OUT/df0-$line.spec"
	$B/mkstore -f -o "$OUT/df0-$line-1.adf" -o "$OUT/df0-$line-2.adf" -1 $B/boot1.img \
		-2 $B/boot2.bin "$OUT/df0-$line.spec" >/dev/null
	$B/lsstore "$OUT/df0-$line-1.adf" 0 "$OUT/df0-$line-2.adf" | grep -E "kernel|lsstore"
done
$B/b2medium "$OUT/df0-k30-1.adf" "$OUT/df0-k30-2.adf" "$OUT/df0-k46-1.adf" | grep '^b2medium: [0-9]'
$B/b2medium "$OUT/df0-k46-1.adf" "$OUT/df0-k46-2.adf" "$OUT/df0-k30-1.adf" | grep '^b2medium: [0-9]'
sha256sum "$OUT"/df0-*.adf
