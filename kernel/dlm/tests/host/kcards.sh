#!/bin/sh
# kcards.sh -- `kbootset cards [DEV]` (C2-4 §17): the running kernel's sd
# cards from kinfo's card table (C2-1 §2), each with its controller's match
# key, and one disk node's key.  Covered: the three 1.1 install controllers
# side by side (the Z3660, Gayle IDE, the A4000T's 53C710) and a Zorro
# A4091 with its base; the disk forms (/dev/dsk, /dev/rdsk, the bare name)
# for the first and last unit of a card; a card the kernel lacks; an
# unknown motherboard code; no cards; no kinfo; a damaged kinfo; names that
# are not disk nodes; usage; -R and --image before the command change
# nothing (no store is read).  Run from the repository root after
# `make tools`.
set -e
B=${B:-build}
T=$B/kcards
rm -rf $T && mkdir -p $T/root
export KBOOTSET_DEVROOT=$T/dev

# a version-3 kinfo record with the given cards (k,id,base,flags/...)
cat > $T/kinfo.py <<'EOF'
import struct, sys
cards = [tuple(int(x, 0) for x in c.split(',')) for c in sys.argv[2].split('/') if c]
r = bytearray(580)
struct.pack_into('>II', r, 0, 0x4b494631, (3 << 16) | len(r))
struct.pack_into('>III', r, 12, 60, 46, 0x000f)
r[24:31] = b'k46.1.4'; r[48:63] = b'68060-261031-55'
struct.pack_into('>I', r, 80, 2)
struct.pack_into('>I', r, 460, len(cards))
for i, (k, cid, base, fl) in enumerate(cards):
    struct.pack_into('>IIII', r, 464 + 16 * i, k, cid, base, fl)
struct.pack_into('>II', r, 528, 33554400, 2097152)
s = sum(struct.unpack('>%dI' % (len(r) // 4), r)) & 0xffffffff
struct.pack_into('>I', r, 8, (-s) & 0xffffffff)
open(sys.argv[1], 'wb').write(r)
EOF
kinfo() { python3 $T/kinfo.py $T/kinfo "$1"; }
export KBOOTSET_KINFO=$T/kinfo
expect() {	# expect STATUS STDOUT STDERR-PATTERN ARGS... ('' = stderr empty)
	want=$1 out=$2 err=$3; shift 3
	set +e; $B/kbootset "$@" > $T/out 2> $T/err; got=$?; set -e
	if [ -z "$err" ]; then [ ! -s $T/err ]; else grep -q -- "$err" $T/err; fi && ok=1 || ok=0
	[ $got -eq $want ] && [ "$(cat $T/out)" = "$out" ] && [ $ok = 1 ] ||
		{ echo "kcards: '$*': status $got (want $want), out '$(cat $T/out)', err '$(cat $T/err)'" >&2; exit 1; }
}

# card 0 the Z3660 (Zorro 144b:01 at 0x40000000), card 1 Gayle, card 2 the
# A4000T's 53C710, card 3 an A4091 (0202:54 at 0x00e90000)
kinfo 0,0x144b0100,0x40000000,0/1,2,0,1/2,3,0,1/3,0x02025400,0x00e90000,0
printf '%s\n' 'card 0: c0-c7 zorro:144b:01 base 0x40000000' 'card 1: c8-c15 mobo:gayle' \
	'card 2: c16-c23 mobo:a4000t-710' 'card 3: c24-c31 zorro:0202:54 base 0x00e90000' > $T/want
$B/kbootset cards > $T/got
cmp -s $T/want $T/got || { echo "kcards: list:" >&2; diff $T/want $T/got >&2; exit 1; }
$B/kbootset -R $T/root cards | cmp -s $T/want -
$B/kbootset --image $T/none.img --offset 65536 cards | cmp -s $T/want -
# one disk: its card's key, from any of the three spellings
expect 0 zorro:144b:01 '' cards /dev/dsk/c6d0s1
expect 0 zorro:144b:01 '' cards c0d0s0
expect 0 mobo:gayle '' cards /dev/dsk/c8d0s1
expect 0 mobo:gayle '' cards /dev/rdsk/c15d0s7
expect 0 mobo:a4000t-710 '' cards c22d0s2
expect 0 zorro:0202:54 '' cards /dev/dsk/c30d0s1
# a card the kernel does not have
kinfo 0,0x144b0100,0x40000000,0/1,2,0,1
expect 1 '' 'the running kernel has no card 2' cards /dev/dsk/c16d0s1
expect 1 '' 'has no card 4' cards c33d0s0
# an unknown motherboard code: listed with its id, refused for a disk
kinfo 0,0x144b0100,0x40000000,0/1,9,0,1
$B/kbootset cards | grep -qx 'card 1: c8-c15 unknown controller id 0x00000009'
expect 1 '' 'unknown controller id 0x00000009' cards c8d0s1
# no cards: nothing listed, a line on stderr, status 0
kinfo ''
expect 0 '' 'registered no sd cards' cards
expect 1 '' 'has no card 0' cards c0d0s1
# no kinfo, or a damaged one: status 1, nothing on stdout
KBOOTSET_KINFO=$T/nokinfo expect 1 '' "no kinfo record at $T/nokinfo" cards
KBOOTSET_KINFO=$T/nokinfo expect 1 '' "no kinfo record" cards c0d0s1
kinfo 0,0x144b0100,0x40000000,0
printf 'x' | dd of=$T/kinfo bs=1 seek=470 conv=notrunc 2>/dev/null
expect 1 '' 'no kinfo record' cards
# not disk nodes, and usage
kinfo 0,0x144b0100,0x40000000,0
for d in /dev/dsk/c0 /dev/dsk/c0d0 c0d0s cxd0s1 /dev/kinfo c0d0s1x d0s1; do
	expect 2 '' 'is not a disk node' cards $d
done
expect 2 '' 'usage' cards c0d0s1 c8d0s1
echo "kcards: four controllers, three disk spellings, a missing card, an unknown code, no cards, no or damaged kinfo, bad names, usage ok"
