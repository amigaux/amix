#!/bin/sh
# kbuild.sh -- kbootset build and commit against a root tree laid out as the
# agreed contracts say (docs/contracts/C2-2-kpkg.md, C2-3-packages.md): a
# kernel package's files and apkg's record of them.  Each gate is provoked
# once; a refusal exits 4, names its gate and writes nothing.  Run from the
# repository root after `make tools` and store-roundtrip.sh (its build/rt
# files are reused).
set -e
B=${B:-build}
T=$B/kbuild
rm -rf $T && mkdir -p $T/root/stand/k46 $T/root/var/apkg/kpkg
R=$T/root
KB="$B/kbootset -R $R --image $T/disk.img --offset 65536"
sha() { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }

head -c 700000 /dev/urandom > $R/stand/k46/unix
sidecar() {
	cat > $R/stand/k46/kabi <<EOF
kabi=static
family=KD060-A
line=k46
pin=gcc-2.7.2.3-8949028
build=68060-260928-52
size=$(size $R/stand/k46/unix)
sha256=$(sha $R/stand/k46/unix)
loader-min=${1:-1}
root=zorro:0202:54,zorro:144b:01
rootfs=ufs
EOF
}
record() {
	cat > $R/var/apkg/kpkg/kernel-kd060a <<EOF
name kernel-kd060a
version 1.1.0
role kernel
line k46
kabi static
pin gcc-2.7.2.3-8949028
sha256 0000000000000000000000000000000000000000000000000000000000000000
source /mnt/cdrom
installed 1761400000
verified no
file /stand/k46/unix $(size $R/stand/k46/unix) $(sha $R/stand/k46/unix)
file /stand/k46/kabi $(size $R/stand/k46/kabi) $(sha $R/stand/k46/kabi)
EOF
}
sidecar
record
head -c 8454144 /dev/zero > $T/disk.img
$KB create 8388608 $B/rt/boot2.bin >/dev/null
FACTS="--line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs --mem 16777216"
ROOTREC="sd id=02025400 base=00000000 unit=6 slice=1"

# the first generation: built, committed as pristine, readable by the loader
$KB build $FACTS --root "$ROOTREC" | grep -q "generation 1 built in /stand/gen/1"
grep -q "^kernel unix /stand/k46/unix$" $R/stand/gen/1/build
grep -q "^root sd id=02025400 base=00000000 unit=6 slice=1$" $R/stand/gen/1/build
$KB commit 2>/dev/null | grep -q "generation 1 written as the pristine generation"
$B/lsstore $T/disk.img 65536 | grep -q "lsstore: ok"
# an upgrade: the root, swap and filesystem come from the default generation
$KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --mem 16777216 | grep -q "generation 2 built"
grep -q "^root sd id=02025400" $R/stand/gen/2/build
grep -q "^rootfs ufs$" $R/stand/gen/2/build
$KB commit 2>/dev/null | grep -q "generation 2 committed"
$B/axsim $T/disk.img 65536 1 | grep -q "generation 2, kernel"

# each gate refuses with status 4, naming itself, and writes nothing
refused() {	# refused GATE command...
	g=$1; shift
	cp $T/disk.img $T/before.img
	set +e
	"$@" > $T/out 2>&1; rc=$?
	set -e
	if [ $rc -ne 4 ] || ! grep -q "gate $g " $T/out; then
		echo "kbuild: gate $g not refused as expected (rc $rc):" >&2; cat $T/out >&2; exit 1
	fi
	cmp -s $T/disk.img $T/before.img || { echo "kbuild: gate $g wrote the store" >&2; exit 1; }
}
refused 10 $KB build $FACTS --line 30
refused 10 $KB build --bootdev zorro:0202:54 --rootdev zorro:0202:54 --mem 16777216
refused 3 $KB build --line 46 --bootdev mobo:gayle --rootdev zorro:0202:54 --mem 16777216
refused 3 $KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs s5 --mem 16777216
refused 6 $KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --mem 1000000
refused 6 $KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54
sidecar 2; record
refused 7 $KB build $FACTS
sidecar; record
# a kernel changed by hand after apkg installed it
printf 'X' | dd of=$R/stand/k46/unix bs=1 seek=1000 conv=notrunc 2>/dev/null
refused 1 $KB build $FACTS
sidecar; record
# no record at all: placed by hand or by a bare pkgadd
mv $R/var/apkg/kpkg/kernel-kd060a $T/rec
refused 1 $KB build $FACTS
mv $T/rec $R/var/apkg/kpkg/kernel-kd060a
# the record's kabi differs from the sidecar's
sed -i 's/^kabi static$/kabi k46.1.0/' $R/var/apkg/kpkg/kernel-kd060a
refused 2 $KB build $FACTS
record
# the kernel changes between build and commit: commit runs the gates again
$KB build $FACTS | grep -q "generation 3 built"
printf 'Y' | dd of=$R/stand/k46/unix bs=1 seek=2000 conv=notrunc 2>/dev/null
refused 1 $KB commit
sidecar; record
$KB commit 2>/dev/null | grep -q "generation 3 committed"
# a stale build: the store moved on since
$KB build $FACTS | grep -q "generation 4 built"
$B/kbootset --image $T/disk.img --offset 65536 commit --spec $B/rt/f1.spec >/dev/null 2>&1
set +e
$KB commit > $T/out 2>&1; rc=$?
set -e
[ $rc -eq 3 ] || [ $rc -eq 4 ] || { echo "kbuild: a stale build was committed" >&2; exit 1; }
echo "kbuild: build, commit and gates 1, 2, 3, 6, 7, 10 ok"

# check: every member against its manifest, the default generation against
# the installed kernel; a damaged member makes it say BAD and exit 1
$KB check > $T/out
grep -q "generation 1 kernel unix: .* CRC-32 and SHA-256 ok" $T/out
grep -q "check: 0 problem(s)" $T/out
grep -q "differs from the default generation 1" $T/out
cp $T/disk.img $T/before.img
printf 'Z' | dd of=$T/disk.img bs=1 seek=$((65536 + 65536 + 5000)) conv=notrunc 2>/dev/null
set +e
$KB check > $T/out; rc=$?
set -e
[ $rc -eq 1 ] && grep -q "generation 1 kernel unix: CRC-32 BAD" $T/out
cp $T/before.img $T/disk.img
echo "kbuild: check ok"

# media builds (S2-04): the pristine generation of a new medium from the
# same root, every gate run; a disk store by kbootset's core, the floppy
# pair and the CD tree by mkstore's engine
MB="$B/kbootset -R $R"
head -c 8454144 /dev/zero > $T/media.img
$MB media --disk $T/media.img --offset 65536 --size 8388608 --boot1 $B/rt/boot1.img \
	--boot2 $B/rt/boot2.bin $FACTS --root "$ROOTREC" 2>/dev/null | grep -q "pristine generation"
$B/lsstore $T/media.img 65536 | grep -q "lsstore: ok"
$B/kbootset -R $R --image $T/media.img --offset 65536 check | grep -q "check: 0 problem(s)"
$MB media --floppy $T/m1.adf $T/m2.adf --boot1 $B/rt/boot1.img --boot2 $B/rt/boot2.bin \
	$FACTS > /dev/null
$B/lsstore $T/m1.adf 0 $T/m2.adf | grep -q "lsstore: ok"
grep -q "z=deflate" $T/m1.adf.spec
$MB media --cd $T/mcd $FACTS > /dev/null
$B/lsstore -C $T/mcd | grep -q "lsstore: ok"
grep -q "sha256=" $T/mcd/BOOT/K46/G1.GMF
# a refused gate writes no medium
set +e
$MB media --floppy $T/x1.adf $T/x2.adf --boot1 $B/rt/boot1.img --boot2 $B/rt/boot2.bin \
	--line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs > $T/out; rc=$?
set -e
[ $rc -eq 4 ] && grep -q "gate 6" $T/out && [ ! -e $T/x1.adf ]
echo "kbuild: media (disk, floppy pair, CD) ok"
