#!/bin/sh
# m-ld1.sh -- vehicles for M-LD1: which bootblock fields the Kickstart strap
# checks, on a floppy and on an RDB UNI\0 partition, per Kickstart version
# (docs/spec/10-boot-loader.md §2.1; docs/plan/stage-1.md S1-20).
#
# Seven bootblocks: the good one and six that each differ in one field
# (bbframe -x).  For DF0, a one-volume floppy store per line and per
# bootblock.  For a disk, the same bootblock written over the first 1024
# bytes of the boot slice of a copy of a proven vehicle (rows N19-N26):
# the script prints the dd line, so the slot's own copy is patched and the
# 0.5-0.9 GB vehicle is not copied seven times.
#
# usage: m-ld1.sh <workspace> <outdir>
# Writes <outdir>/bb-<variant>.img, fd-<line>-<variant>.adf and EXPECTED.
# Run from the repository root after `make tools boot1 boot2`.
set -e
WS=$1 OUT=$2
B=${B:-build}
K=$WS/amix-kerntools/work/k0-chains
V="good dos1 uni0 nodos sum third0 notrailer"
mkdir -p "$OUT"
cp $B/boot1.img "$OUT/bb-good.img"
for v in $V; do
	[ $v = good ] || $B/bbframe -x $v $B/boot1.img "$OUT/bb-$v.img" >/dev/null
done
cp "$K/K030-U-FD/K030-U-FD-c0-u6" "$OUT/k30.brel"
python3 -I "$WS/amix-kerntools/tools/elf2brel.py" "$K/KD060-FD/KD060-FD-fd0" "$OUT/k46.brel" >/dev/null
for line in k30 k46; do
	printf 'generation 1\nstate good\nline %s\nrootfs ufs\nkernel unix %s z=deflate\n' \
		$line "$OUT/$line.brel" > "$OUT/fd-$line.spec"
	$B/mkstore -f -o "$OUT/fd-$line-good.adf" -1 "$OUT/bb-good.img" -2 $B/boot2.bin \
		"$OUT/fd-$line.spec" >/dev/null
	for v in $V; do	# the good floppy with only its first 1024 bytes replaced
		[ $v = good ] && continue
		cp "$OUT/fd-$line-good.adf" "$OUT/fd-$line-$v.adf"
		dd if="$OUT/bb-$v.img" of="$OUT/fd-$line-$v.adf" bs=1024 count=1 conv=notrunc 2>/dev/null
	done
done
cat > "$OUT/EXPECTED" <<EOF
# M-LD1 rows: one boot per bootblock variant, per medium, per Kickstart
# (3.1 and 3.2.x), serial captured, boot frames kept.
#
# Variants (each differs from good in one field; all but sum re-checksummed):
#   good       the control: must boot (amix-boot 1: on the serial log)
#   dos1       magic "DOS\\1" instead of "DOS\\0"
#   uni0       magic "UNI\\0" (the partition's DosType) instead of "DOS\\0"
#   nodos      magic "BAD\\0"
#   sum        checksum off by one (the strap is documented to refuse it)
#   third0     the third longword 0 instead of 0x370
#   notrailer  the last longword 0 instead of the 0x03010401 trailer
#
# The result per row is one word: ACCEPTED when the serial log shows the
# loader's "amix-boot 1:" banner (boot1 never checks its own framing, so
# if the strap runs it, the boot proceeds as with good), REFUSED when it
# does not.  Then the frame shows what Kickstart did instead: the
# insert-disk screen, the next boot node, or the boot menu.
#
# DF0: fd-<line>-<variant>.adf (one volume; the 1.0 floppy kernel deflated;
# a loader-only row: it ends at the kernel stage).  Each variant is the good
# floppy with its first 1024 bytes replaced, identical otherwise.
#
# Disks: a fresh slot copy of the controller's proven vehicle, then
#   dd if=$OUT/bb-<variant>.img of=<slot copy> bs=1024 seek=<slice offset / 1024> conv=notrunc
# with the S1-19 vehicles' boot slices:
#   ld-a3000-030, ld-gayle-030   seek=521280   (slice at 533790720)
#   ld-a4091-030, ld-a4091-060   seek=870464   (slice at 891355136)
# The store header after the bootblock is untouched; the rest of the row
# is the vehicle's own (generation 1 boots to login when ACCEPTED).
EOF
for f in "$OUT"/bb-*.img; do printf '%s: ' "${f##*/}"; $B/bbframe -c "$f" 2>&1 | sed 's/^bbframe: [^:]*: //'; done
ls "$OUT"/fd-*.adf | wc -l | sed 's/$/ floppy vehicles/'
