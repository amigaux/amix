#!/bin/sh
# store-roundtrip.sh -- mkstore builds a store, lsstore verifies it, and a
# corrupted member is caught.  Run from the repository root after `make tools`.
set -e
B=${B:-build}
T=$B/rt
rm -rf $T && mkdir -p $T
head -c 1267397 /dev/urandom > $T/unix
head -c 45678 /dev/urandom > $T/z3660scsi
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
module z3660scsi root $T/z3660scsi match=zorro:144b:01
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
