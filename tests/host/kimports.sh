#!/bin/sh
# kimports.sh -- kbootset's import check (gate 2): every undefined global of
# a module in the generation comes from a module it depends on or from the
# kernel's symbol block (the sidecar's ksym=), a core-tier name only for a
# core-tier module (C3-2).  A synthetic module kernel (mkksymkern.py) with a
# KSYM block and module objects with symbols (mkmodobj.py U:/D:).  Run from
# the repository root after store-roundtrip.sh (its build/rt files are
# reused).
set -e
B=${B:-build}
T=$B/kimports
rm -rf $T && mkdir -p $T/root/stand/k46 $T/root/var/apkg/kpkg $T/root/etc/conf/mod.d
R=$T/root
MD=$R/etc/conf/mod.d
KB="$B/kbootset -R $R --image $T/disk.img --offset 65536"
FACTS="--line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs --mem 16777216"
sha() { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }

ks=$(python3 tests/host/mkksymkern.py $R/stand/k46/unix --build 68060-261027-99 printf:0 kmem_alloc:0 bdevsw:1)
cat > $R/stand/k46/kabi <<EOT
kabi=k46.1.2
family=generic
line=k46
pin=gcc-2.7.2.3-8949028
build=68060-261027-99
size=$(size $R/stand/k46/unix)
sha256=$(sha $R/stand/k46/unix)
loader-min=2
root=zorro:0202:54
rootfs=ufs
arena=0x00000040 0x00010000
ident=0x00000040
ksym=$ks
abi=7a90c7d92c2e0882f546d38543b8921d55a42ffd72801449a89b8e70a702dc0b
EOT
cat > $R/var/apkg/kpkg/kernel-k46 <<EOT
name kernel-k46
version 1.1.0
role kernel
line k46
kabi k46.1.2
pin gcc-2.7.2.3-8949028
sha256 0000000000000000000000000000000000000000000000000000000000000000
source /mnt/cdrom
installed 1761400000
verified no
file /stand/k46/unix $(size $R/stand/k46/unix) $(sha $R/stand/k46/unix)
file /stand/k46/kabi $(size $R/stand/k46/kabi) $(sha $R/stand/k46/kabi)
EOT
modpkg() {	# modpkg NAME key=value ... U:imp ... D:def ...
	n=$1; shift
	python3 tests/host/mkmodobj.py $MD/$n name=$n "$@"
	cat > $R/var/apkg/kpkg/mod-$n <<EOT
name mod-$n
version 1.0.0
role module
line k46
kabi k46.1.0
pin gcc-2.7.2.3-8949028
sha256 0000000000000000000000000000000000000000000000000000000000000000
source /mnt/cdrom
installed 1761400000
verified no
file /etc/conf/mod.d/$n $(size $MD/$n) $(sha $MD/$n)
EOT
}
clean() { rm -f "${MD:?}"/* "${R:?}"/var/apkg/kpkg/mod-*; }
refused() {	# refused TEXT command...: gate 2, the store untouched
	t=$1; shift
	cp $T/disk.img $T/before.img
	set +e
	"$@" > $T/out 2>&1; rc=$?
	set -e
	if [ $rc -ne 4 ] || ! grep -q "gate 2 " $T/out || ! grep -q "$t" $T/out; then
		echo "kimports: not refused as expected (rc $rc, want '$t'):" >&2; cat $T/out >&2; exit 1
	fi
	cmp -s $T/disk.img $T/before.img || { echo "kimports: the refusal wrote the store" >&2; exit 1; }
}
head -c 8454144 /dev/zero > $T/disk.img
$KB create 8388608 $B/rt/boot2.bin > /dev/null

# imports the block exports, and one from a module it depends on: built
modpkg helper class=boot match=always D:helper_fn U:printf
modpkg user class=boot match=always depend=helper U:printf U:kmem_alloc U:helper_fn
$KB build $FACTS > $T/out 2>&1 || { cat $T/out >&2; exit 1; }
grep -q "built" $T/out
rm -rf "${R:?}/stand/gen"
# a name the kernel's block lacks: refused at compose time, named
clean
modpkg lacks class=boot match=always U:printf U:sdqueue U:vn_rele
refused "module lacks imports 2 name(s) kernel 68060-261027-99 (kabi k46.1.2) does not export: sdqueue, vn_rele" \
	$KB build $FACTS
# a core-tier name in a ddi-tier module: refused; in a core-tier one: built
clean
modpkg ddimod class=boot match=always U:bdevsw
refused "module ddimod imports 1 name(s) .*: bdevsw" $KB build $FACTS
clean
modpkg coremod class=boot match=always tier=core build=68060-261027-99 U:bdevsw
$KB build $FACTS > $T/out 2>&1 || { cat $T/out >&2; exit 1; }
grep -q "built" $T/out
rm -rf "${R:?}/stand/gen"
# a helper the module does not depend on does not count
clean
modpkg helper class=boot match=always D:helper_fn
modpkg nodep class=boot match=always U:helper_fn
refused "module nodep imports 1 name(s) .*: helper_fn" $KB build $FACTS
# a dependency absent from the generation: gate 3 names it, not gate 2's
# "a newer kernel cut" (z3660rtg without monsw)
clean
modpkg rtg class=boot match=always depend=monsw U:printf U:monsw_register U:monsw_set
set +e
$KB build $FACTS > $T/out 2>&1; rc=$?
set -e
if [ $rc -ne 4 ] || ! grep -q "gate 3 .*module rtg depends on monsw, which is not in the generation" $T/out ||
   grep -q "newer kernel cut" $T/out; then
	echo "kimports: the absent dependency not named by gate 3 (rc $rc):" >&2; cat $T/out >&2; exit 1
fi
# the sidecar's build= against the kernel's own buildid (C3-3 section 3)
clean
sed -i 's/^build=68060-261027-99$/build=68060-261027-98/' $R/stand/k46/kabi
sed -i "s|^file /stand/k46/kabi .*|file /stand/k46/kabi $(size $R/stand/k46/kabi) $(sha $R/stand/k46/kabi)|" $R/var/apkg/kpkg/kernel-k46
refused "the sidecar's build=68060-261027-98 is not the kernel's own build id 68060-261027-99" $KB build $FACTS
sed -i 's/^build=68060-261027-98$/build=68060-261027-99/' $R/stand/k46/kabi
sed -i "s|^file /stand/k46/kabi .*|file /stand/k46/kabi $(size $R/stand/k46/kabi) $(sha $R/stand/k46/kabi)|" $R/var/apkg/kpkg/kernel-k46
# a name that is both a file static and the global (delay on the k30 cut
# 68030-261027-18): the build id is the global's, whatever comes first
clean
cp $R/stand/k46/unix $T/unix.plain
python3 tests/host/mkksymkern.py $R/stand/k46/unix --build 68060-261027-99 --static 68060-261027-00 \
	printf:0 kmem_alloc:0 bdevsw:1 > /dev/null
sed -i "s|^sha256=.*|sha256=$(sha $R/stand/k46/unix)|; s|^size=.*|size=$(size $R/stand/k46/unix)|" $R/stand/k46/kabi
sed -i "s|^file /stand/k46/unix .*|file /stand/k46/unix $(size $R/stand/k46/unix) $(sha $R/stand/k46/unix)|; \
	s|^file /stand/k46/kabi .*|file /stand/k46/kabi $(size $R/stand/k46/kabi) $(sha $R/stand/k46/kabi)|" $R/var/apkg/kpkg/kernel-k46
$KB build $FACTS > $T/out 2>&1 || { echo "kimports: a static buildid before the global was taken:" >&2; cat $T/out >&2; exit 1; }
grep -q "built" $T/out
rm -rf "${R:?}/stand/gen"
cp $T/unix.plain $R/stand/k46/unix
sed -i "s|^sha256=.*|sha256=$(sha $R/stand/k46/unix)|; s|^size=.*|size=$(size $R/stand/k46/unix)|" $R/stand/k46/kabi
sed -i "s|^file /stand/k46/unix .*|file /stand/k46/unix $(size $R/stand/k46/unix) $(sha $R/stand/k46/unix)|; \
	s|^file /stand/k46/kabi .*|file /stand/k46/kabi $(size $R/stand/k46/kabi) $(sha $R/stand/k46/kabi)|" $R/var/apkg/kpkg/kernel-k46
echo "kimports: the import check (gate 2: the kernel's block, dependencies, the core tier; the global build id over a static) ok"
