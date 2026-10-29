#!/bin/sh
# knamelist.sh -- `kbootset namelist`, `mark-good` and `status` on the box's
# /stand/unix (40 §4.2, C2-4 §9, §12), on the host: the cut kernels
# committed into a store, a version-3 kinfo record giving the bind address
# (C2-1), the namelist written, found current, found stale, and refused
# for each reason C2-4 §12 names.  A /stand/unix that is a hard link to
# /stand/2.1_unix (as 1.0 left it) must leave that file as it was.
# The kernels are optional inputs (namelist.sh's NL_K46, NL_K30_*);
# without them the cases are skipped.
# Run from the repository root after `make tools` and store-roundtrip.sh.
set -e
B=${B:-build}
WS=$(cd "$(dirname "$0")/../../.." && pwd)
K46=${NL_K46:-$WS/tmp/2026-10-26-s3-20d/out/m/unix}
K30E=${NL_K30_ETREL:-$WS/tmp/2026-10-26-s3-21e/dlm/usr/sys/unix}
K30B=${NL_K30_BREL:-$WS/tmp/2026-10-26-s3-21e/dlm/usr/sys/unix.brel}
T=$B/knamelist
rm -rf $T && mkdir -p $T
sha() { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }

# kinfo VERSION GEN LAYOUTFILE [FLAGS]: a kinfo record whose bootdata block
# is where nlmake laid the kernel out (its "text <vaddr> <size>" lines)
cat > $T/kinfo.py <<'EOF'
import struct, sys
ver, gen, lay = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
extra = int(sys.argv[5], 0) if len(sys.argv) > 5 else 0
medium = sys.argv[6] if len(sys.argv) > 6 else ''     # cd or floppy: AXL1 flag 0x08
l = {w[0]: (int(w[1], 16), int(w[2])) for w in (x.split() for x in open(lay))}
ml = 576 if ver == 3 else 536
r = bytearray(ml + 4)
struct.pack_into('>II', r, 0, 0x4b494631, (ver << 16) | len(r))
struct.pack_into('>III', r, 12, 60, 46, 0x000f)
r[24:31] = b'k46.1.0'; r[48:63] = b'68060-261026-56'
a = 84
struct.pack_into('>I', r, a, 0x41584c31)
struct.pack_into('>IIIIII', r, a + 12, 2, 0, 60, 0xf, gen, 2)
if medium:
    struct.pack_into('>II', r, a + 32, 3, 0x08)      # pristine, a read-only medium
    if medium == 'cd':
        struct.pack_into('>I', r, a + 44, 0xffffffff) # no boot node: started by AmigaDOS
s = sum(struct.unpack('>31I', r[a:a + 124])) & 0xffffffff
struct.pack_into('>I', r, a + 8, (-s) & 0xffffffff)
struct.pack_into('>I', r, 80, 1 | extra)
if ver == 3:
    t, ro, d = l['text'], l['rodata'], l['data']
    struct.pack_into('>10I', r, 536, t[0], t[0], 0, t[1], ro[0], 0, ro[1], d[0], 0, d[1])
s = sum(struct.unpack('>%dI' % (len(r) // 4), r)) & 0xffffffff
struct.pack_into('>I', r, 8, (-s) & 0xffffffff)
open(sys.argv[1], 'wb').write(r)
EOF
# store LINE KERNEL [bss=N]: a fresh store, one generation of KERNEL
store() {
	head -c $((8 << 20)) /dev/zero > $T/store
	$B/kbootset --image $T/store create $((8 << 20)) $B/rt/boot2.bin > /dev/null
	printf 'line %s\nkabi %s.1.0\nloader-min 1\nrootfs ufs\nroot sd id=144b0100 base=00000000 unit=6 slice=1\nkernel unix %s%s\n' \
		"$1" "$1" "$2" "${3:+ $3}" > $T/spec
	$B/kbootset --image $T/store commit --spec $T/spec > /dev/null 2>&1
}
KB="$B/kbootset -R $T/root --image $T/store"
# no RC PATTERN command...: it exits RC, saying PATTERN
no() {
	want=$1 pat=$2; shift 2
	set +e; "$@" > $T/out 2>&1; got=$?; set -e
	[ $got = $want ] && grep -q "$pat" $T/out ||
		{ echo "knamelist: expected status $want and \"$pat\", got $got:" >&2; cat $T/out >&2; exit 1; }
}
export KBOOTSET_KINFO=$T/kinfo

if [ -f "$K46" ]; then
	R=$T/root
	mkdir -p $R/stand/k46
	store k46 "$K46"
	$B/nlmake "$K46" 0x08000000 $T/n46 > $T/lay46
	# /stand/unix as 1.0 left it: a hard link to the stock kernel
	echo "the stock kernel" > $R/stand/2.1_unix
	ln $R/stand/2.1_unix $R/stand/unix
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46
	$KB status > $T/out
	grep -q "^namelist: /stand/unix is not the booted kernel's: run kbootset namelist$" $T/out
	(umask 0; $KB namelist) > $T/out			# rc2's umask on the box
	grep -q "^kbootset: namelist /stand/unix written for generation 1, bound at 0x08000000$" $T/out
	cmp -s $R/stand/unix $T/n46				# what nlmake makes at that bind
	[ "$(stat -c %a $R/stand/unix)" = 644 ]			# never 0666
	[ "$(cat $R/stand/2.1_unix)" = "the stock kernel" ]	# the link's file is untouched
	[ "$(stat -c %h $R/stand/2.1_unix)" = 1 ]
	[ ! -e $R/stand/unix.new ]
	$KB namelist | grep -q "^kbootset: namelist for generation 1 is current$"
	$KB status | grep -q "^namelist: /stand/unix is generation 1's, bound at 0x08000000$"
	# mark-good writes it on every boot (here generation 1 is not a trial)
	rm $R/stand/unix
	$KB status | grep -q "^namelist: /stand/unix is missing: run kbootset namelist$"
	$KB mark-good > $T/out
	grep -q "^kbootset: namelist /stand/unix written for generation 1" $T/out
	$KB mark-good > $T/out
	! grep -q namelist $T/out				# current: mark-good says nothing of it
	# refusals, each with its reason; /stand/unix stays as it is
	cp $R/stand/unix $T/keep
	python3 -I $T/kinfo.py $T/kinfo 2 1 $T/lay46
	no 3 "no namelist: kinfo version 2 gives no bind address" $KB namelist
	$KB status | grep -q "^namelist: none (kinfo version 2 gives no bind address)$"
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46 8
	no 3 "kinfo flags a loader fault (0x8)" $KB namelist
	awk '$1 == "data" { $2 = sprintf("0x%08x", strtonum($2) + 4) } { print }' $T/lay46 > $T/laybad
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/laybad
	no 3 "the layout does not match kinfo" $KB namelist
	python3 -I $T/kinfo.py $T/kinfo 3 7 $T/lay46
	no 3 "generation 7's kernel cannot be read from the store" $KB namelist
	cmp -s $R/stand/unix $T/keep
	# another bind: a new namelist
	$B/nlmake "$K46" 0x07f00000 $T/n46b > $T/lay46b
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46b
	$KB namelist | grep -q "bound at 0x07f00000$" && cmp -s $R/stand/unix $T/n46b
	echo "knamelist: k46 (written over a link to 2.1_unix, current, stale, missing, mark-good, refusals) ok"
	# a CD boot (C2-4 section 13): the store did not boot; the namelist comes
	# from the installed kernel when its build id is kinfo's
	cp "$K46" $R/stand/k46/unix
	echo "build=68060-261026-56" > $R/stand/k46/kabi
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46 0 cd
	rm -f $R/stand/unix
	$KB status > $T/out
	grep -q "^booted: generation 1 of a read-only medium (a CD), not of this box's store; kernel 68060-261026-56" $T/out
	$KB namelist | grep -q "^kbootset: namelist /stand/unix written for the medium's kernel (68060-261026-56), bound at 0x08000000$"
	cmp -s $R/stand/unix $T/n46
	$KB status | grep -q "^namelist: /stand/unix is the medium's kernel's (68060-261026-56), bound at 0x08000000$"
	$B/lsstore $T/store 0 > $T/before
	$KB mark-good > $T/out
	grep -q "^kbootset: booted from a read-only medium (generation 1 of a CD): nothing to mark$" $T/out
	! grep -q "namelist" $T/out				# current
	$B/lsstore $T/store 0 | cmp -s - $T/before		# the store is untouched
	[ -z "$($KB retry)" ]
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46 0 floppy
	$KB mark-good | grep -q "(generation 1 of a floppy pair): nothing to mark"
	echo "build=68060-261026-57" > $R/stand/k46/kabi
	no 3 "booted from a read-only medium whose kernel (68060-261026-56) is not the one installed here (68060-261026-57)" $KB namelist
	echo "knamelist: k46 booted from a read-only medium (status, namelist from the installed kernel, no mark-good, no retry) ok"
	rm -rf $R
else
	echo "knamelist: no k46 kernel, skipped"
fi

if [ -f "$K30E" ] && [ -f "$K30B" ]; then
	R=$T/root
	mkdir -p $R/stand/k30
	cp "$K30B" $R/stand/k30/unix
	store k30 $R/stand/k30/unix bss=349324
	$B/nlmake "$K30E" 0 $R/stand/k30/unix.sym > /dev/null	# bind 0: a unix.sym (C2-3 §2.1)
	$B/nlmake -s $R/stand/k30/unix.sym 0x00200000 $T/n30 > $T/lay30
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay30
	sidecar() {
		printf 'kabi=k30.1.0\nline=k30\nsize=%s\nsha256=%s\nbss=349324\n' \
			"$(size $R/stand/k30/unix)" "${1:-$(sha $R/stand/k30/unix)}" > $R/stand/k30/kabi
		[ -z "$2" ] || echo "$2" >> $R/stand/k30/kabi
	}
	SYM="sym=unix.sym $(size $R/stand/k30/unix.sym) $(sha $R/stand/k30/unix.sym)"
	sidecar "" ""
	no 3 "the kernel has no symbols (no unix.sym)" $KB namelist
	sidecar 0000000000000000000000000000000000000000000000000000000000000000 "$SYM"
	no 3 "generation 1's kernel is not the installed one" $KB namelist
	sidecar "" "sym=unix.sym $(size $R/stand/k30/unix.sym) 0000000000000000000000000000000000000000000000000000000000000000"
	no 3 "unix.sym differs from its sidecar's sym=" $KB namelist
	sidecar "" "$SYM"
	$KB namelist | grep -q "^kbootset: namelist /stand/unix written for generation 1, bound at 0x00200000$"
	cmp -s $R/stand/unix $T/n30
	echo "knamelist: k30 brel through unix.sym (written; no sym=, another kernel, a changed unix.sym refused) ok"
else
	echo "knamelist: no k30 kernels, skipped"
fi
