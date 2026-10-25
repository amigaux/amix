#!/bin/sh
# m-fp1.sh -- M-FP1 (static) and M-NET1d: build the RAM-disk-profile floppy
# pair per line with mkstore -f from the real static floppy kernels and the
# netinstall miniroot archives of m-net1.py, verify each pair with lsstore
# and with boot2's own reader (b2medium), and print what is left on volume 2.
# See docs/measurements/2026-10-25-m-fp1.md.
#
# usage: m-fp1.sh <workspace> <netdir> <outdir>
#   <workspace>  the Amix project workspace (holds amix-kerntools/ and
#                amix-installng/)
#   <netdir>     as for m-net1.py
#   <outdir>     scratch for the archives, kernels and images
# Run from the repository root after `make tools build/b2medium boot1 boot2`.
set -e
WS=$1 NET=$2 F=$3
B=${B:-build}
K=$WS/amix-kerntools/work/k0-chains
mkdir -p "$F"
python3 -I tools/measure/m-net1.py "$WS" "$NET" "$F" > "$F/m-net1.json"
python3 -I "$WS/amix-kerntools/tools/elf2brel.py" "$K/KD060-FD/KD060-FD-fd0" "$F/k46.brel" >/dev/null
cp "$K/K030-U-FD/K030-U-FD-c0-u6" "$F/k30.brel"
ls -l "$B/boot2.bin" | awk '{print "boot2", $5, "bytes"}'
for line in k30 k46; do
	for set in trim full; do
		c=$line-$set
		cat > "$F/$c.spec" <<SPEC
generation 1
state pristine
line $line
rootfs ufs
root ramdisk
swap none
kernel unix $F/$line.brel z=deflate
ramdisk miniroot $F/miniroot-$c.tar z=deflate
SPEC
		if ! $B/mkstore -f -o "$F/$c-1.adf" -o "$F/$c-2.adf" -1 $B/boot1.img -2 $B/boot2.bin \
		    "$F/$c.spec" > "$F/$c.mkstore" 2>&1; then
			echo "$c: does not fit ($(cat "$F/$c.mkstore"))"
			continue
		fi
		$B/lsstore "$F/$c-1.adf" 0 "$F/$c-2.adf" > "$F/$c.lsstore"
		used=$(sed -n 's/.* \([0-9]*\) bytes used on the last volume/\1/p' "$F/$c.mkstore")
		echo "$c: fits, $((901120 - used)) bytes free on volume 2"
		grep -E "kernel|ramdisk" "$F/$c.lsstore"
	done
done
# boot2's reader on each fitting trimmed pair, the other line's volume 1 as
# the foreign disk
[ -f "$F/k30-trim-1.adf" ] && [ -f "$F/k46-trim-1.adf" ]
$B/b2medium "$F/k30-trim-1.adf" "$F/k30-trim-2.adf" "$F/k46-trim-1.adf" | grep '^b2medium'
$B/b2medium "$F/k46-trim-1.adf" "$F/k46-trim-2.adf" "$F/k30-trim-1.adf" | grep '^b2medium'
