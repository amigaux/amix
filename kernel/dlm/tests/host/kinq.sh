#!/bin/sh
# kinq.sh -- `kbootset inquiry CARD UNIT` and `kbootset cards --probe`
# (C2-4 §18): one INQUIRY per unit, read-only, its answer as one line
# "type N VENDOR PRODUCT REVISION".  On the host the answers come from
# KBOOTSET_SCSIDIR (<dir>/<card>.<unit>, 36 bytes or fewer; no file = no
# unit), in place of /dev/scsi.  Covered: a disk and an ATAPI CD; blanks
# and NULs trimmed, inner blanks '_', a blank field '-', unprintable '?';
# the additional length honoured (bytes past it are the kernel iobuf's
# leftovers, never read); qualifier 3 and type 0x1f as no unit; no answer;
# an empty answer; usage; --probe listing only the units that answer,
# under each card, and a card with none.  Run from the repository root
# after `make tools`.
set -e
B=${B:-build}
T=$B/kinq
rm -rf "${T:?}" && mkdir -p $T/scsi
export KBOOTSET_SCSIDIR=$T/scsi KBOOTSET_DEVROOT=$T/dev

# ans FILE TYPE VENDOR PRODUCT REV [ADDLEN] [TAIL]: an INQUIRY answer of 36 bytes
cat > $T/ans.py <<'EOF'
import sys
f, t, v, p, r = sys.argv[1:6]
add = int(sys.argv[6], 0) if len(sys.argv) > 6 else 31
b = bytearray(36)
b[0] = int(t, 0); b[2] = 2; b[3] = 2; b[4] = add
def put(off, n, s):
    s = s.encode('latin-1').replace(b'\\0', b'\0').replace(b'\\x01', b'\x01')
    b[off:off + n] = (s + b' ' * n)[:n]
put(8, 8, v); put(16, 16, p); put(32, 4, r)
open(f, 'wb').write(b)
EOF
ans() { python3 $T/ans.py "$@"; }
expect() {	# expect STATUS STDOUT STDERR-PATTERN ARGS... ('' = stderr empty)
	want=$1 out=$2 err=$3; shift 3
	set +e; $B/kbootset "$@" > $T/out 2> $T/err; got=$?; set -e
	if [ -z "$err" ]; then [ ! -s $T/err ]; else grep -q -- "$err" $T/err; fi && ok=1 || ok=0
	[ $got -eq $want ] && [ "$(cat $T/out)" = "$out" ] && [ $ok = 1 ] ||
		{ echo "kinq: '$*': status $got (want $want), out '$(cat $T/out)', err '$(cat $T/err)'" >&2; exit 1; }
}

# a disk on card 0 unit 6, an ATAPI CD on card 1 unit 1
ans $T/scsi/0.6 0 'ZULUSCSI' 'HARDDRIVE' '2.0'
ans $T/scsi/1.1 5 'hp' 'PLDS DVDRW DU8AESH' '6HSM'
expect 0 'type 0 ZULUSCSI HARDDRIVE 2.0' '' inquiry 0 6
expect 0 'type 5 hp PLDS_DVDRW_DU8AE 6HSM' '' inquiry 1 1
# NUL padding is blank; a blank field is '-'; an unprintable byte is '?'
ans $T/scsi/2.3 0 'IBM\0\0\0\0\0' '' 'A\x011'
expect 0 'type 0 IBM - A?1' '' inquiry 2 3
# the additional length: an old unit sends 5 + 15 = 20 bytes, so the product
# is cut at byte 20 and the revision is blank, whatever the iobuf held there
ans $T/scsi/2.4 0 'QUANTUM' 'LPS240S STALE' 'OLD1' 15
expect 0 'type 0 QUANTUM LPS2 -' '' inquiry 2 4
# not a unit: qualifier 3 (no device on this LUN), type 0x1f, no answer, an empty answer
ans $T/scsi/0.1 0x7f 'X' 'Y' 'Z'
expect 1 '' 'card 0 unit 1: no unit (qualifier 3)' inquiry 0 1
ans $T/scsi/0.2 0x1f 'X' 'Y' 'Z'
expect 1 '' 'no unit (device type 0x1f)' inquiry 0 2
expect 1 '' 'card 3 unit 0: no answer' inquiry 3 0
: > $T/scsi/0.3
expect 1 '' 'the command failed' inquiry 0 3
# usage
expect 2 '' 'a card 0-3 and a unit 0-7' inquiry 4 0
expect 2 '' 'a card 0-3 and a unit 0-7' inquiry 0 8
expect 2 '' 'a card 0-3 and a unit 0-7' inquiry x 1
expect 2 '' 'a card 0-3 and a unit 0-7' inquiry -1 1
expect 2 '' 'usage' inquiry 0
expect 2 '' 'usage' inquiry 0 1 2

# cards --probe: kinfo's cards, each followed by the units that answer
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
python3 $T/kinfo.py $T/kinfo 0,0x144b0100,0x40000000,0/1,2,0,1/2,3,0,1
export KBOOTSET_KINFO=$T/kinfo
printf '%s\n' 'card 0: c0-c7 zorro:144b:01 base 0x40000000' '  unit 6: type 0 ZULUSCSI HARDDRIVE 2.0' \
	'card 1: c8-cf mobo:gayle' '  unit 1: type 5 hp PLDS_DVDRW_DU8AE 6HSM' \
	'card 2: c10-c17 mobo:a4000t-710' '  unit 3: type 0 IBM - A?1' '  unit 4: type 0 QUANTUM LPS2 -' > $T/want
$B/kbootset cards --probe > $T/got 2> $T/err
cmp -s $T/want $T/got || { echo "kinq: probe:" >&2; diff $T/want $T/got >&2; exit 1; }
[ ! -s $T/err ] || { echo "kinq: probe wrote to stderr: $(cat $T/err)" >&2; exit 1; }
# the plain listing is unchanged by the answers
$B/kbootset cards | cmp -s - $T/want && { echo "kinq: cards without --probe listed units" >&2; exit 1; }
[ "$($B/kbootset cards | wc -l)" -eq 3 ]
# a card whose units all fail still lists, and the status is 0
rm -f "${T:?}"/scsi/*
python3 $T/kinfo.py $T/kinfo 3,0x02025400,0x00e90000,0
expect 0 'card 3: c18-c1f zorro:0202:54 base 0x00e90000' '' cards --probe
expect 2 '' 'usage' cards --probe c0d0s1
echo "kinq: a disk and a CD, trimming and '-', unprintable bytes, the additional length, qualifier 3 and type 0x1f, no answer, usage, --probe under each card ok"
