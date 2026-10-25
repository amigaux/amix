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

# a floppy pair: packed layout, the manifest ahead of its members on
# volume 1, a member that runs past the end of volume 1 continues on volume
# 2 (§4.3), and lsstore reads both volumes
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
grep -q "generation 1 (pristine), manifest .* at 0x6000" $T/f.out
grep -q "ramdisk miniroot .* at 1:0x.* (on to the next volume)  crc .* ok" $T/f.out
grep -q "header A: seq 1, store 901120 bytes, flags 0x6, volume 1/2" $T/f.out
# boot2's own reader on the pair: one change (volume 1 -> 2 inside the
# miniroot), with a blank disk, a disk of another set and volume 1 again
# refused first; the other set holds another generation (the set id is
# the build time and the control block's CRC)
sed 's/^generation 1/generation 2/' $T/f1.spec > $T/f2.spec
$B/mkstore -f -o $T/other1.adf -o $T/other2.adf -1 $T/boot1.img -2 $T/boot2.bin $T/f2.spec >/dev/null
$B/b2medium $T/boot1.adf $T/boot2.adf $T/other1.adf | tee $T/m.out
grep -q "1 volume change(s), 2 foreign/blank and 1 wrong-volume disks refused, motor on for 0 waiting frames: ok" $T/m.out
# the same on a device without a change counter (re-read every half second)
$B/b2medium -n $T/boot1.adf $T/boot2.adf $T/other1.adf | grep -q "disks refused, motor on for 0 waiting frames: ok"
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
[ "$(stat -c %a $C/BOOT/amix-cdboot)" = 755 ]
# SOURCE_DATE_EPOCH makes the tree reproducible
SOURCE_DATE_EPOCH=1761400000 $B/mkstore -C $T/cdr1 $T/c12.spec >/dev/null
SOURCE_DATE_EPOCH=1761400000 $B/mkstore -C $T/cdr2 $T/c12.spec >/dev/null
diff -r $T/cdr1 $T/cdr2
echo "store-roundtrip: CD tree ok"

# the loader's writes over boots (axsim, the rules of loader/common): a
# trial generation is attempted, then marked bad (L8); a one-shot request
# is consumed; a loader trial records its start, then falls back (B4)
W=$T/w
mkdir -p $W
sed 's/^state pristine/state good/' $T/g12.spec > $W/g12.spec
sed -e 's/^generation 12/generation 13/' -e 's/^state pristine/state trial/' $T/g12.spec > $W/g13.spec
sed -e 's/^generation 12/generation 14/' -e 's/^state pristine/state good/' $T/g12.spec > $W/g14.spec
$B/mkstore -o $W/try.img -s 8388608 -1 $T/boot1.img -2 $T/boot2.bin -d 12 $W/g12.spec $W/g13.spec >/dev/null
$B/axsim $W/try.img 0 2 > $W/try.out
grep -q "generation 13, kernel" $W/try.out
grep -q "L8 trial generation did not reach multi-user (generation 13)" $W/try.out
$B/lsstore $W/try.img | grep -q "generation 13 (bad, 1 attempt(s))"
$B/mkstore -o $W/one.img -s 8388608 -1 $T/boot1.img -2 $T/boot2.bin -d 14 -n 12 $W/g12.spec $W/g14.spec >/dev/null
$B/lsstore $W/one.img | grep -q "one-shot 2 (generation 12)"
$B/axsim $W/one.img 0 2 | grep "kernel" | tr '\n' ' ' | grep -q "generation 12, kernel .* generation 14, kernel"
$B/lsstore $W/one.img | grep -q "seq 2, default 14, trial 0, one-shot 0,"
$B/mkstore -o $W/ldr.img -s 8388608 -1 $T/boot1.img -2 $T/boot2.bin -b $T/boot2.bin -T $W/g12.spec >/dev/null
$B/axsim $W/ldr.img 0 2 | grep -q "B4 new loader already started once"
$B/lsstore $W/ldr.img | grep -q "tally: header seq 1, 1 start(s)"
if $B/mkstore -f -o $W/x.adf -1 $T/boot1.img -2 $T/boot2.bin -n 12 $W/g12.spec 2>/dev/null; then
	echo "store-roundtrip: one-shot accepted on a read-only floppy" >&2; exit 1
fi
echo "store-roundtrip: loader writes ok"

# M-LD1 bootblock variants: each fails bbframe's check on its own field
for v in dos1 uni0 nodos third0 notrailer; do
	$B/bbframe -x $v $T/boot1.img $W/bb-$v.img >/dev/null
	$B/bbframe -c $W/bb-$v.img 2>&1 | grep -q "framing longwords wrong"
done
$B/bbframe -x sum $T/boot1.img $W/bb-sum.img >/dev/null
$B/bbframe -c $W/bb-sum.img 2>&1 | grep -q "checksum wrong"
[ "$(cmp -l $T/boot1.img $W/bb-sum.img | wc -l)" -eq 1 ]
echo "store-roundtrip: bootblock variants ok"

# kbootset on an image: create, pristine, commit, mark-good, rollback, the
# exit codes of a rule (3) and of a gate (4); the loader's rules read it
KB="$B/kbootset --image $W/kb.img --offset 65536 --journal $W/kb.journal"
head -c 8454144 /dev/zero > $W/kb.img
$KB create 8388608 $T/boot2.bin --boot1 $T/boot1.img >/dev/null
printf 'line k30\nrootfs ufs\nkernel unix %s\n' $T/fkernel > $W/kb.spec
$KB commit --spec $W/kb.spec | grep -q "generation 1 written as the pristine generation"
$KB commit --spec $W/kb.spec | grep -q "generation 2 committed"
$B/axsim $W/kb.img 65536 1 | grep -q "generation 2, kernel"
$KB mark-good --booted 2 | grep -q "generation 2 is good and the default"
$KB rollback | grep -q "the default is generation 1"
set +e
$KB mark-bad 1 >/dev/null; r1=$?
head -c 9000000 /dev/urandom > $W/kb.big
printf 'line k30\nkernel unix %s\n' $W/kb.big > $W/kb.bigspec
$KB commit --spec $W/kb.bigspec >/dev/null; r2=$?
set -e
[ $r1 -eq 3 ] && [ $r2 -eq 4 ]
$B/lsstore $W/kb.img 65536 | grep -q "lsstore: ok"
echo "store-roundtrip: kbootset ok"
