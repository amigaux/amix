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
# a build of the same packages (a loader-only transaction, say): the root,
# swap and filesystem come from the default generation, so it equals it;
# build says so, commit writes nothing and exits 0, and the next build
# still gets id 2 (C2-4 §3)
$KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --mem 16777216 > $T/out
grep -q "generation 2 built" $T/out
grep -q "equals the default generation 1: kbootset commit will write nothing (commit --again writes it)" $T/out
grep -q "^root sd id=02025400" $R/stand/gen/2/build
grep -q "^rootfs ufs$" $R/stand/gen/2/build
cp $T/disk.img $T/before.img
$KB commit > $T/out 2>&1 || { echo "kbuild: the unchanged commit failed" >&2; cat $T/out >&2; exit 1; }
tail -1 $T/out | grep -qx "kbootset: the default generation 1 already has these members; nothing to commit"
cmp -s $T/disk.img $T/before.img || { echo "kbuild: the unchanged commit wrote the store" >&2; exit 1; }
[ ! -d $R/stand/gen/2 ] || { echo "kbuild: the unchanged build was left behind" >&2; exit 1; }
# commit --again writes it all the same (a repair, a bench row); then the
# generation counts as an upgrade
$KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --mem 16777216 | grep -q "generation 2 built"
$KB commit --again 2>/dev/null | grep -q "generation 2 committed"
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
sidecar 3; record
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
# a <name>.new left by an interrupted apkg write is not a record
sed 's/^file \/stand\/k46\/unix .*/file \/stand\/k46\/unix 1 0000/' \
	$R/var/apkg/kpkg/kernel-kd060a > $R/var/apkg/kpkg/kernel-kd060a.new
$KB build $FACTS > $T/out && grep -q "built" $T/out
rm -f $R/var/apkg/kpkg/kernel-kd060a.new
# two records naming one file: ambiguous, refused
cp $R/var/apkg/kpkg/kernel-kd060a $R/var/apkg/kpkg/kernel-other
refused 1 $KB build $FACTS
grep -q "named by two apkg records" $T/out
rm -f $R/var/apkg/kpkg/kernel-other
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

# a brel kernel (ELF type 0xff00) records no bss: its sidecar must give
# bss=, gate 6 counts it, and the manifest carries it for the loader
cp $R/stand/k46/unix $T/unix.keep
printf '\177ELF' | dd of=$R/stand/k46/unix bs=1 conv=notrunc 2>/dev/null
printf '\377\000' | dd of=$R/stand/k46/unix bs=1 seek=16 conv=notrunc 2>/dev/null
sidecar; record
refused 2 $KB build $FACTS
grep -q "brel, whose bss is not recorded" $T/out
echo "bss=283445" >> $R/stand/k46/kabi; record
# 700 000 + 283 445 bytes need about 1.97 MB: 1.5 MB is too little
refused 6 $KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs --mem 1500000
$KB build $FACTS | grep -q "built"
$KB commit 2>/dev/null | grep -q "committed"
$B/lsstore $T/disk.img 65536 > $T/ls
$B/kbootset --image $T/disk.img --offset 65536 status | grep -q "trial"
grep -a -q "^kernel unix 700000 at=0x[0-9a-f]* crc32=[0-9a-f]* sha256=[0-9a-f]* bss=283445$" $T/disk.img
cp $T/unix.keep $R/stand/k46/unix; sidecar; record
echo "kbuild: brel bss (gate 2, gate 6, the manifest) ok"

# an ET_REL kernel's bss is in its section headers: gate 6 counts it
python3 -c '
import struct, sys
text = b"\x4e\x75" * 350000                       # 700 000 bytes of image
shstr = b"\0.text\0.bss\0.shstrtab\0"
shoff = 52 + len(text) + len(shstr)
shoff += -shoff % 4
sh = [(0,) * 10,
      (1, 1, 6, 0, 52, len(text), 0, 0, 2, 0),
      (7, 8, 3, 0, 52 + len(text), 1048576, 0, 0, 4, 0),    # 1 MiB NOBITS
      (12, 3, 0, 0, 52 + len(text), len(shstr), 0, 0, 1, 0)]
h = b"\x7fELF\x01\x02\x01" + b"\0" * 9 + struct.pack(">HHIIIIIHHHHHH", 1, 4, 1, 0, 0, shoff, 0, 52, 0, 0, 40, 4, 3)
body = h + text + shstr
body += b"\0" * (shoff - len(body))
body += b"".join(struct.pack(">10I", *x) for x in sh)
open(sys.argv[1], "wb").write(body)' $R/stand/k46/unix
sidecar; record
# 700 000 + 1 048 576 bytes need about 3.5 MB: 3 MB is too little
refused 6 $KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs --mem 3000000
$KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs --mem 3600000 | grep -q "built"
rm -rf "${R:?}/stand/gen/$(ls $R/stand/gen | sort -n | tail -1)"
cp $T/unix.keep $R/stand/k46/unix; sidecar; record
echo "kbuild: ET_REL bss (gate 6) ok"

# a module kernel (sidecar version 5, C3-3 §3): arena=, ident= and
# loader-min=2 together; the manifest gets its arena and ident records
ABI=abi=7a90c7d92c2e0882f546d38543b8921d55a42ffd72801449a89b8e70a702dc0b
msidecar() {	# msidecar CAP [LOADER-MIN] [ident=...] [abi=...]
	sed -e 's/^kabi=static$/kabi=k46.1.0/' -e 's/^family=KD060-A$/family=generic/' \
	    -e "s/^loader-min=.*/loader-min=${2:-2}/" $T/kabi.static > $R/stand/k46/kabi
	echo "arena=0x0009a000 $1" >> $R/stand/k46/kabi
	[ "${3-x}" = "" ] || echo "${3:-ident=0x00099fc0}" >> $R/stand/k46/kabi
	[ "${4-x}" = "" ] || echo "${4:-$ABI}" >> $R/stand/k46/kabi
	record; sed -i 's/^kabi static$/kabi k46.1.0/' $R/var/apkg/kpkg/kernel-kd060a
}
cp $R/stand/k46/kabi $T/kabi.static
msidecar 0x00060000 2 ""
refused 2 $KB build $FACTS
grep -q "arena=, ident= and loader-min=2 together" $T/out
msidecar 0x00060000 1
refused 2 $KB build $FACTS
# gate 6 counts the arena: 700 000 + 393 216 bytes need about 2.19 MB
msidecar 0x00060000
refused 6 $KB build --line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs --mem 2100000
$KB build $FACTS | grep -q "built"
grep -q "^arena 0x0009a000 0x00060000$" $R/stand/gen/*/build
grep -q "^ident 0x00099fc0$" $R/stand/gen/*/build
grep -q "^loader-min 2$" $R/stand/gen/*/build
$KB commit 2>/dev/null | grep -q "committed"
grep -a -q "^ident 0x00099fc0$" $T/disk.img
$B/lsstore $T/disk.img 65536 | grep -q "lsstore: ok"
# the manifest copy must fit the arena behind its directory (C3-4 §4)
# abi= (C3-3 section 4): a module kernel's sidecar carries it, a SHA-256
msidecar 0x00060000 2 ident=0x00099fc0 ""
refused 2 $KB build $FACTS
grep -q "a module kernel's sidecar gives no abi=" $T/out
msidecar 0x00060000 2 ident=0x00099fc0 abi=not-a-fingerprint
refused 2 $KB build $FACTS
grep -q "abi= is not a fingerprint" $T/out
msidecar 0x00000100
$KB build $FACTS | grep -q "built"
refused 4 $KB commit
grep -q "the manifest copy needs" $T/out
# a store whose loader is version 1 boots no module kernel (gate 7)
head -c 8454144 /dev/zero > $T/v1.img
$B/kbootset -R $R --image $T/v1.img --offset 65536 create 8388608 $B/rt/boot2.bin --version 1 >/dev/null
msidecar 0x00060000
refused 7 $B/kbootset -R $R --image $T/v1.img --offset 65536 build $FACTS
cp $T/kabi.static $R/stand/k46/kabi; record
rm -rf $R/stand/gen/[0-9]*
echo "kbuild: module kernel (gates 2, 4, 6, 7, the arena and ident records) ok"

# module members (C3-5): the installed module packages go into the
# generation, gates 1-3, the depend order, the modreg.d parameters, the
# records and the copies under /stand/gen/<id>/mod/
MD=$R/etc/conf/mod.d
mkdir -p $MD $R/etc/conf/modreg.d $R/etc/conf/modreg.local.d
modpkg() {	# modpkg NAME key=value ...: a module object and its apkg record
	n=$1; shift
	python3 tests/host/mkmodobj.py $MD/$n name=$n "$@"
	cat > $R/var/apkg/kpkg/mod-$n <<EOF
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
EOF
}
three() {	# the stage-3 set as C3-6 describes it
	rm -f "${MD:?}"/* "${R:?}"/var/apkg/kpkg/mod-* "${R:?}"/etc/conf/modreg.d/* "${R:?}"/etc/conf/modreg.local.d/*
	modpkg z3660eth class=boot match=zorro:144b:01,mobo:z3660-window majors=c:51 \
		param=intr:int:0:0:6 param=intrl2:int:1:0:1
	modpkg z3660rtg class=demand majors=c:49 depend=monsw unload=allowed \
		param=blit:bool:1 param=maxarea:int:0:0:3686400
	modpkg monsw class=demand majors=c:52 param=config:int:-1:-1:51
}
msidecar 0x00060000
three
# a static kernel takes no module: gate 2 on the kabi family
cp $T/kabi.static $R/stand/k46/kabi; record
refused 2 $KB build $FACTS
grep -q "is built for kabi k46.1.0, the kernel is static" $T/out
msidecar 0x00060000
echo "param intr=6" > $R/etc/conf/modreg.d/z3660eth
echo "param blit=off   # the administrator's" > $R/etc/conf/modreg.local.d/z3660rtg
$KB build $FACTS > $T/out && id=$(sed -n 's/^kbootset: generation \([0-9]*\) built.*/\1/p' $T/out)
[ -n "$id" ] || { echo "kbuild: the module generation was not built" >&2; cat $T/out >&2; exit 1; }
B5=$R/stand/gen/$id/build
grep -A9 '^kernel unix' $B5 > $T/mods
# boot class first, then demand class with monsw before the z3660rtg that depends on it
sed -n 2p $T/mods | grep -q "^module z3660eth boot $(size $MD/z3660eth) path=/stand/gen/$id/mod/z3660eth sha256=$(sha $MD/z3660eth) match=zorro:144b:01,mobo:z3660-window$"
sed -n 3p $T/mods | grep -q "^module monsw demand $(size $MD/monsw) path=/stand/gen/$id/mod/monsw sha256=[0-9a-f]* majors=c:52$"
sed -n 4p $T/mods | grep -q "^module z3660rtg demand [0-9]* path=/stand/gen/$id/mod/z3660rtg sha256=[0-9a-f]* majors=c:49 depend=monsw$"
for p in "z3660eth.intr=6" "z3660eth.intrl2=1" "monsw.config=-1" "z3660rtg.blit=0" "z3660rtg.maxarea=0"; do
	grep -qx "param $p" $B5 || { echo "kbuild: no param $p" >&2; cat $B5 >&2; exit 1; }
done
cmp -s $MD/z3660rtg $R/stand/gen/$id/mod/z3660rtg
$KB commit 2>/dev/null | grep -q "committed"
grep -a -q "^module z3660rtg demand .* depend=monsw$" $T/disk.img
grep -a -qx "param z3660rtg.blit=0" $T/disk.img
$B/lsstore $T/disk.img 65536 | grep -q "lsstore: ok"
$KB check > $T/out
grep -q "module z3660rtg: /stand/gen/$id/mod/z3660rtg ok" $T/out
# check: a module copy changed, then gone
cp $R/stand/gen/$id/mod/monsw $T/monsw.keep
printf 'Z' | dd of=$R/stand/gen/$id/mod/monsw bs=1 seek=4 conv=notrunc 2>/dev/null
! $KB check > $T/out
grep -q "module monsw: /stand/gen/$id/mod/monsw SHA-256 BAD" $T/out
rm $R/stand/gen/$id/mod/monsw
! $KB check > $T/out
grep -q "module monsw: /stand/gen/$id/mod/monsw missing" $T/out
cp $T/monsw.keep $R/stand/gen/$id/mod/monsw
$KB check > $T/out
# what build refuses
modpkg monsw class=demand majors=c:52 kabi=k46.1.1
refused 2 $KB build $FACTS			# a minor above the kernel's
three; modpkg monsw class=demand majors=c:52 kabi=k46.2.0
refused 2 $KB build $FACTS			# another major
grep -q "module monsw is built for kabi k46.2.0, the kernel is k46.1.0" $T/out
three; modpkg monsw class=demand majors=c:52 kabi=k30.1.0
refused 2 $KB build $FACTS			# another family
grep -q "module monsw is built for kabi k30.1.0, the kernel is k46.1.0" $T/out
three; modpkg monsw class=demand majors=c:52 tier=core build=68060-260101-1
refused 2 $KB build $FACTS			# core tier, another kernel build
grep -q "core-tier module monsw is built for kernel 68060-260101-1, this one is 68060-260928-52" $T/out
three; modpkg monsw class=demand majors=c:52 cc=gcc-2.95.3-0000000
refused 2 $KB build $FACTS			# another compiler
three; echo "param speed=9" > $R/etc/conf/modreg.d/monsw
refused 2 $KB build $FACTS			# a parameter the module does not declare
grep -q "declares no parameter speed" $T/out
three; echo "param blit=maybe" > $R/etc/conf/modreg.d/z3660rtg
refused 2 $KB build $FACTS			# not a bool
three; echo "param maxarea=4000000" > $R/etc/conf/modreg.d/z3660rtg
refused 2 $KB build $FACTS			# above its max
three; echo "param intr=-1" > $R/etc/conf/modreg.d/z3660eth
refused 2 $KB build $FACTS			# below its min
grep -q "intr=-1 is not a valid int value for module z3660eth" $T/out
three; echo "intr=6" > $R/etc/conf/modreg.d/z3660eth
refused 2 $KB build $FACTS			# a malformed line
grep -q "neither param <name>=<value> nor disable" $T/out
three; modpkg monsw class=demand majors=c:52 param=base:hex:0x10:0:0xff param=tag:str:mon
echo "param base=0x100" > $R/etc/conf/modreg.d/monsw
refused 2 $KB build $FACTS			# hex above its max
echo "param tag=$(printf '%064d' 0)" > $R/etc/conf/modreg.d/monsw
refused 2 $KB build $FACTS			# a str over 63 characters
grep -q "is not a valid str value for module monsw" $T/out
printf 'param base=32\nparam tag=mon2\n' > $R/etc/conf/modreg.d/monsw
$KB build $FACTS | grep -q "built"		# hex takes decimal, written as hex
id=$(ls $R/stand/gen | sort -n | tail -1)
grep -qx "param monsw.base=0x20" $R/stand/gen/$id/build
grep -qx "param monsw.tag=mon2" $R/stand/gen/$id/build
rm -rf "${R:?}/stand/gen/${id:?}"
three; modpkg monsw class=demand majors=c:52 tier=core build=68060-260928-52
$KB build $FACTS | grep -q "built"		# core tier for this kernel build
id=$(ls $R/stand/gen | sort -n | tail -1)
grep -q "^module monsw demand .* majors=c:52 tier=core build=68060-260928-52$" $R/stand/gen/$id/build
rm -rf "${R:?}/stand/gen/${id:?}"
three; echo "disable" > $R/etc/conf/modreg.d/monsw
refused 3 $KB build $FACTS			# z3660rtg depends on the disabled monsw
grep -q "depends on monsw, which is not in the generation" $T/out
three; modpkg z3660eth class=boot majors=c:51
refused 3 $KB build $FACTS			# a boot module without match=
three; modpkg monsw class=demand
refused 3 $KB build $FACTS			# a demand module without majors=
three; modpkg monsw class=demand majors=c:51
refused 3 $KB build $FACTS			# another module's major
grep -q "major c:51 is registered to another module" $T/out
three; modpkg monsw class=demand majors=c:52 depend=z3660rtg
refused 3 $KB build $FACTS			# a depend cycle
three; modpkg z3660eth class=boot match=always majors=c:51 depend=monsw
refused 3 $KB build $FACTS			# a boot module on a demand module
grep -q "module z3660eth: its depend= closure has a cycle or a demand-class dependency" $T/out
three; modpkg monsw class=root match=always
refused 3 $KB build $FACTS			# root class before stage 4
three; printf 'X' | dd of=$MD/monsw bs=1 seek=4 conv=notrunc 2>/dev/null
refused 1 $KB build $FACTS			# changed after apkg installed it
# a copy changed between build and commit
three; $KB build $FACTS | grep -q "built"
id=$(ls $R/stand/gen | sort -n | tail -1)
printf 'Y' | dd of=$R/stand/gen/$id/mod/monsw bs=1 seek=4 conv=notrunc 2>/dev/null
refused 1 $KB commit
grep -q "changed since kbootset build" $T/out
rm -rf "${R:?}/stand/gen/${id:?}"
rm -f "${MD:?}"/* "${R:?}"/var/apkg/kpkg/mod-* "${R:?}"/etc/conf/modreg.d/* "${R:?}"/etc/conf/modreg.local.d/*
cp $T/kabi.static $R/stand/k46/kabi; record
echo "kbuild: module members (gates 1, 2, 3, the order, modreg parameters, commit, check) ok"

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
# a read-only medium's boot controller is its loader's, never the kernel's
# (C2-4 §13): gate 3 checks only the root controller; a --bootdev the
# kernel has no driver for is noted and the spec is the same
RO="--line 46 --rootdev zorro:0202:54 --rootfs ufs --mem 16777216"
$MB media --cd $T/mcd2 $RO > $T/out 2>&1 || { echo "kbuild: media --cd without --bootdev" >&2; cat $T/out >&2; exit 1; }
$MB media --cd $T/mcd3 $RO --bootdev zorro:dead:01 > $T/out 2>&1 ||
	{ echo "kbuild: media --cd with a foreign --bootdev" >&2; cat $T/out >&2; exit 1; }
grep -q "^kbootset: --bootdev is not used for a read-only medium" $T/out
cmp -s $T/mcd2.spec $T/mcd3.spec || [ "$(grep -v '^created' $T/mcd2.spec)" = "$(grep -v '^created' $T/mcd3.spec)" ]
$MB media --floppy $T/r1.adf $T/r2.adf --boot1 $B/rt/boot1.img --boot2 $B/rt/boot2.bin \
	$RO --bootdev zorro:dead:01 > /dev/null 2>&1
set +e
$MB media --cd $T/mcd4 --line 46 --rootfs ufs --mem 16777216 > $T/out 2>&1; rc=$?
set -e
[ $rc -eq 4 ] && grep -q "gate 3.*the root disk's controller is unknown: name --rootdev" $T/out
set +e
head -c 8454144 /dev/zero > $T/media2.img
$MB media --disk $T/media2.img --offset 65536 --size 8388608 --boot1 $B/rt/boot1.img \
	--boot2 $B/rt/boot2.bin $RO --bootdev zorro:dead:01 --root "$ROOTREC" > $T/out 2>&1; rc=$?
set -e
[ $rc -eq 4 ] && grep -q "no driver for the boot disk's controller zorro:dead:01" $T/out
rm -f $T/media2.img
# a refused gate writes no medium
set +e
$MB media --floppy $T/x1.adf $T/x2.adf --boot1 $B/rt/boot1.img --boot2 $B/rt/boot2.bin \
	--line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs > $T/out; rc=$?
set -e
[ $rc -eq 4 ] && grep -q "gate 6" $T/out && [ ! -e $T/x1.adf ]
# a medium's pristine generation takes the installed modules too: their
# records in the spec, their copies under the root's /stand/gen/1/mod/
msidecar 0x00060000
three
$MB media --floppy $T/mm1.adf $T/mm2.adf --boot1 $B/rt/boot1.img --boot2 $B/rt/boot2.bin \
	$FACTS > $T/out || { echo "kbuild: media with modules" >&2; cat $T/out >&2; exit 1; }
grep -q "^module z3660eth boot $(size $MD/z3660eth) path=/stand/gen/1/mod/z3660eth sha256=$(sha $MD/z3660eth) match=" $T/mm1.adf.spec
grep -q "^module z3660rtg demand .* depend=monsw$" $T/mm1.adf.spec
grep -qx "param z3660eth.intr=0" $T/mm1.adf.spec
cmp -s $MD/monsw $R/stand/gen/1/mod/monsw
$B/lsstore $T/mm1.adf 0 $T/mm2.adf | grep -q "lsstore: ok"
rm -f "${MD:?}"/* "${R:?}"/var/apkg/kpkg/mod-* "${R:?}"/etc/conf/modreg.d/* "${R:?}"/etc/conf/modreg.local.d/*
rm -rf "${R:?}/stand/gen/1/mod"
cp $T/kabi.static $R/stand/k46/kabi; record
echo "kbuild: media (disk, floppy pair, CD; a medium with modules) ok"

# commit --spec with z=deflate on the kbootset the box runs (no zlib: its
# own deflate): the member is stored deflated, the store checks, and a
# generation that fits only deflated is accepted (S3-43-4 on a 4 MiB store)
KZ="$B/kbootset-nz --image $T/z.img --offset 0"
head -c 1048576 /dev/zero > $T/z.img
$KZ create 1048576 $B/rt/boot2.bin > /dev/null
{ head -c 300000 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 600000; head -c 600000 /dev/zero; } > $T/zkern
printf 'line k46\nkabi static\nloader-min 1\nrootfs ufs\nroot sd id=144b0100 unit=6 slice=1\nkernel unix %s z=deflate\n' $T/zkern > $T/z.spec
$KZ commit --spec $T/z.spec > $T/out 2>&1 || { echo "kbuild: --spec z=deflate refused" >&2; cat $T/out >&2; exit 1; }
$B/lsstore $T/z.img 0 | grep -q "kernel  unix .*(deflate)  crc .* ok"
$B/lsstore $T/z.img 0 | grep -q "lsstore: ok"
$KZ check | grep -q "check: 0 problem(s)"
sed 's/ z=deflate//' $T/z.spec > $T/zraw.spec
head -c 1048576 /dev/zero > $T/z.img
$KZ create 1048576 $B/rt/boot2.bin > /dev/null
refused 5 $KZ commit --spec $T/zraw.spec			# raw, it does not fit
echo "kbuild: --spec z=deflate on the box's kbootset (its own deflate) ok"

