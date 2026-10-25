#!/bin/sh
# store-roundtrip.sh -- mkstore builds a store, lsstore verifies it, and a
# corrupted member is caught.  Run from the repository root after `make tools`.
set -e
B=${B:-build}
T=$B/rt
rm -rf $T && mkdir -p $T
head -c 1267397 /dev/urandom > $T/unix
# a compressible module, stored deflated
yes "amix z3660scsi module text" | head -c 45678 > $T/z3660scsi
head -c 20000 /dev/urandom > $T/boot2.bin
head -c 1008 /dev/zero > $T/b1.bin
$B/bbframe $T/b1.bin $T/boot1.img >/dev/null
cat > $T/g12.spec <<SPEC
generation 12
state pristine
line k30
rootfs ufs
kernel unix $T/unix
SPEC
cat > $T/g41.spec <<SPEC
generation 41
state good
line k46
kabi k46.1.0
rootfs ufs
root sd id=144b0100 base=00000000 unit=6 slice=1
arena 0x001f2000 0x00080000
kernel unix $T/unix
module z3660scsi root $T/z3660scsi z=deflate match=zorro:144b:01
module z3660eth boot 30212 path=/stand/gen/41/mod/z3660eth
SPEC
# an image with the store at a partition offset of 1 MiB
$B/mkstore -o $T/disk.img -p 1048576 -s 16777216 -1 $T/boot1.img -2 $T/boot2.bin $T/g12.spec $T/g41.spec
$B/lsstore $T/disk.img 1048576
# corrupt one byte of the kernel of generation 12 and expect a failure
off=$((1048576 + 65536 + 100))
printf '\377' | dd of=$T/disk.img bs=1 seek=$off conv=notrunc 2>/dev/null
if $B/lsstore $T/disk.img 1048576 >/dev/null; then
	echo "store-roundtrip: corruption NOT detected" >&2; exit 1
fi
echo "store-roundtrip: ok"

# a floppy pair: packed layout, a member that does not fit volume 1 moves
# to volume 2, and lsstore reads both volumes
head -c 600000 /dev/urandom > $T/fkernel
head -c 500000 /dev/urandom > $T/miniroot
cat > $T/f1.spec <<SPEC
generation 1
state pristine
line k30
rootfs ufs
root ramdisk
swap none
kernel unix $T/fkernel
ramdisk miniroot $T/miniroot
SPEC
$B/mkstore -f -o $T/boot1.adf -o $T/boot2.adf -1 $T/boot1.img -2 $T/boot2.bin $T/f1.spec
[ "$(wc -c < $T/boot1.adf)" -eq 901120 ] && [ "$(wc -c < $T/boot2.adf)" -eq 901120 ]
$B/lsstore $T/boot1.adf 0 $T/boot2.adf | tee $T/f.out
grep -q "ramdisk miniroot .* at 2:0x800" $T/f.out
grep -q "header A: seq 1, store 901120 bytes, flags 0x6, volume 1/2" $T/f.out
echo "store-roundtrip: floppy pair ok"

# a CD tree (spec 10 §4.4): one generation per line directory, members as
# file= names, the manifest as G<id>.GMF; a corrupted member is caught and
# a trial generation is refused on read-only media
C=$T/cd
sed 's/^state good/state pristine/' $T/g41.spec > $T/c41.spec
cat > $T/c12.spec <<SPEC
generation 12
state pristine
line k30
rootfs ufs
root ramdisk
swap none
kernel unix $T/fkernel
ramdisk miniroot $T/miniroot z=deflate
SPEC
# a stand-in for amix-cdboot: the tree only checks the load-file magic
printf '\000\000\003\363' > $T/cdboot && head -c 60 /dev/zero >> $T/cdboot
$B/mkstore -C $C -x $T/cdboot $T/c12.spec $T/c41.spec
$B/lsstore -C $C | tee $T/c.out
grep -q "kernel  unix .* file G12K.BIN  crc .* ok" $T/c.out
grep -q "ramdisk miniroot .* file G12R.BIN (deflate)  crc .* ok" $T/c.out
grep -q "module  z3660scsi .* file G41M01.BIN (deflate)  crc .* ok" $T/c.out
[ -f $C/BOOT/K30/G12.GMF ] && [ -f $C/BOOT/K46/G41.GMF ] && [ -f $C/BOOT/amix-cdboot ]
grep -q "^SYS:BOOT/amix-cdboot$" $C/S/Startup-Sequence
grep -q "^kernel unix 600000 file=G12K.BIN crc32=" $C/BOOT/K30/G12.GMF
printf '\377' | dd of=$C/BOOT/K46/G41K.BIN bs=1 seek=100 conv=notrunc 2>/dev/null
if $B/lsstore -C $C >/dev/null; then
	echo "store-roundtrip: CD corruption NOT detected" >&2; exit 1
fi
sed 's/^state pristine/state trial/' $T/c12.spec > $T/ct.spec
if $B/mkstore -C $T/cdt $T/ct.spec 2>/dev/null; then
	echo "store-roundtrip: trial generation accepted on a CD" >&2; exit 1
fi
echo "store-roundtrip: CD tree ok"
