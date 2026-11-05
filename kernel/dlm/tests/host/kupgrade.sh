#!/bin/sh
# kupgrade.sh -- what kbootset says after an upgrade (C2-4 §3, §19): check
# names the generation that already holds the installed kernel, build says
# when a good one holds its members, `default` makes a good generation the
# default again, and commit, status and check name a loader in /stand/loader
# that the store does not hold.  Run from the repository root after
# `make tools` and store-roundtrip.sh (its build/rt files are reused).
set -e
TP=$(dirname "$0")/../../toolchain.pin
KPIN=gcc-$(awk '$1 == "gcc" {print $2}' "$TP")-$(awk '$1 == "commit" {print $2}' "$TP")
B=${B:-build}
T=$B/kupgrade
R=$T/root
rm -rf "${T:?}" && mkdir -p $R/stand/k46 $R/stand/loader $R/var/apkg/kpkg
KB="$B/kbootset -R $R --image $T/disk.img --offset 65536"
FACTS="--line 46 --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs --mem 16777216"
K=/stand/k46/unix
sha() { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }
fail() { echo "kupgrade: $1" >&2; cat $T/out >&2; exit 1; }
# says PATTERN: a whole line of the last output
says() { grep -qx "$1" $T/out || fail "expected \"$1\""; }
lacks() { ! grep -q "$1" $T/out || fail "did not expect \"$1\""; }
# kernel: a new kernel in the package's place, its sidecar and apkg's record
kernel() {
	head -c 700000 /dev/urandom > $R/stand/k46/unix
	cat > $R/stand/k46/kabi <<EOF
kabi=static
family=KD060-A
line=k46
pin=$KPIN
build=68060-260928-52
size=$(size $R/stand/k46/unix)
sha256=$(sha $R/stand/k46/unix)
loader-min=1
root=zorro:0202:54,zorro:144b:01
rootfs=ufs
EOF
	cat > $R/var/apkg/kpkg/kernel-kd060a <<EOF
name kernel-kd060a
version 1.1.0
role kernel
line k46
kabi static
pin $KPIN
sha256 0000000000000000000000000000000000000000000000000000000000000000
source /mnt/cdrom
installed 1761400000
verified no
file /stand/k46/unix $(size $R/stand/k46/unix) $(sha $R/stand/k46/unix)
file /stand/k46/kabi $(size $R/stand/k46/kabi) $(sha $R/stand/k46/kabi)
EOF
}
# refused CMD...: exits 3
refused() {
	set +e; "$@" > $T/out 2>&1; rc=$?; set -e
	[ $rc = 3 ] || fail "$* exited $rc, not 3"
}
LOADER="the loader in /stand/loader is not on the boot store yet: kbootset loader-install /stand/loader/boot2"
PKG="$K (package kernel-kd060a)"

kernel
head -c 8454144 /dev/zero > $T/disk.img
$KB create 8388608 $B/rt/boot2.bin > /dev/null
$KB build $FACTS --root "sd id=02025400 base=00000000 unit=6 slice=1" > /dev/null
$KB commit > $T/out 2>&1
cp $B/rt/boot2.bin $R/stand/loader/boot2

# the installed kernel: no generation holds it, then each state of the one
# that does
kernel
$KB check > $T/out
says ".*$PKG differs from the default generation 1: kbootset build and commit compose it"
$KB build $FACTS > $T/out
lacks "already holds"
$KB commit > $T/out 2>&1
[ "$(tail -1 $T/out)" = "kbootset: generation 2 committed; power-cycle to boot it" ] || fail "commit's line"
$KB check > $T/out
says ".*$PKG is generation 2's kernel, on trial: power-cycle to boot it"
lacks "build and commit compose it"
$KB mark-good --booted 2 > /dev/null
$KB check > $T/out
says ".*$K is the default generation 2's kernel"
$KB rollback > $T/out
says "kbootset: the default is generation 1 (was 2); kbootset default 2 goes back"
$KB check > $T/out
says ".*$PKG is generation 2's kernel, not the default: kbootset default 2 boots it again"
lacks "build and commit compose it"
echo "kupgrade: check names who holds the installed kernel (none, on trial, default, good) ok"

# build says so, and commit still composes: a trigger never silently keeps
# the older default
$KB build $FACTS > $T/out
grep -q "; good generation 2 already holds this: kbootset default 2 makes it the default without a new generation$" $T/out ||
	fail "no build hint"
$KB commit > $T/out 2>&1
[ "$(tail -1 $T/out)" = "kbootset: generation 3 committed; power-cycle to boot it" ] || fail "the commit after the hint"
$KB check > $T/out
says ".*$PKG is generation 3's kernel, on trial: power-cycle to boot it"	# the trial first
# the verb's refusals, each writing nothing
cp $T/disk.img $T/before.img
refused $KB default 99
says "kbootset: no such generation"
refused $KB default 3
says "kbootset: generation 3 is on trial: power-cycle to boot it"
refused $KB default 2
says "kbootset: generation 3 is on trial: boot it, or kbootset mark-bad 3, first"
set +e; $KB default > $T/out 2>&1; rc=$?; set -e
[ $rc = 2 ] || fail "default with no id exited $rc, not 2"
cmp -s $T/disk.img $T/before.img || fail "a refused default wrote the store"
$KB mark-bad 3 > /dev/null
$KB default 1 > $T/out
says "kbootset: generation 1 is already the default"
$KB default 2 > $T/out
says "kbootset: the default is generation 2 (was 1); power-cycle to boot it"
$B/axsim $T/disk.img 65536 1 | grep -q "generation 2, kernel"
$KB default 1 > $T/out					# the pristine one too
says "kbootset: the default is generation 1 (was 2); power-cycle to boot it"
$KB default 2 > /dev/null
$KB check > $T/out
says ".*$K is the default generation 2's kernel"
$B/lsstore $T/disk.img 65536 | grep -q "lsstore: ok"
echo "kupgrade: build's hint, kbootset default and its refusals ok"

# a loader the store does not hold: the clause ends commit's line, the one
# apkg repeats; byte-identical says nothing
$KB status > $T/out
lacks "the loader in"
$KB check > $T/out
lacks "the loader in"
{ cat $B/rt/boot2.bin; printf x; } > $R/stand/loader/boot2	# another length
$KB status > $T/out
says "note: $LOADER"
$KB check > $T/out
says ".*$LOADER"
grep -q "check: 0 problem(s)" $T/out || fail "a new loader counted as a problem"
cp $B/rt/boot2.bin $R/stand/loader/boot2			# the same length, another byte
v=$(od -An -tu1 -j 100 -N1 $R/stand/loader/boot2 | tr -d ' ')
printf "\\$(printf %03o $((255 - v)))" | dd of=$R/stand/loader/boot2 bs=1 seek=100 conv=notrunc 2>/dev/null
$KB status > $T/out
says "note: $LOADER"
$KB build $FACTS > /dev/null
$KB commit > $T/out 2>&1
[ "$(tail -1 $T/out)" = "kbootset: the default generation 2 already has these members; nothing to commit; $LOADER" ] ||
	fail "the unchanged commit's line"
kernel
$KB build $FACTS > /dev/null
$KB commit > $T/out 2>&1
[ "$(tail -1 $T/out)" = "kbootset: generation 4 committed; power-cycle to boot it; $LOADER" ] || fail "commit's line"
$KB loader-install $R/stand/loader/boot2 > /dev/null
$KB status > $T/out
lacks "the loader in"
rm "${R:?}"/stand/loader/boot2				# no package: nothing to say
$KB status > $T/out
lacks "the loader in"
echo "kupgrade: the loader in /stand/loader (commit's last line, status, check; none when equal or absent) ok"
