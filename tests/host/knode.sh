#!/bin/sh
# knode.sh -- `kbootset nodes`, the sd disk nodes of a four-card kernel
# (C4-1 §2.4, C2-4 §14), on the host: device nodes are plain files and the
# host build writes nothing, so what it would do is compared with C4-1
# §2.1's minor, computed here independently.  Covered: a root with no
# four-card kernel; core's stock set (c0-cf d0 and d1) under sdcards=4,
# every node to make and every d1 node to remove; a complete set; a set
# made under -R whose registration in core is still to do.  `check`'s line
# is kbox.sh's.  Run from the repository root after `make tools`.
set -e
B=${B:-build}
T=$B/knode
rm -rf $T && mkdir -p $T
R=$T/root

# tree ROOT FIRST LAST D1: c<FIRST>..c<LAST> d0 s0-s7 as files, and the d1
# names of c0-cf when D1 is y
tree() {
	mkdir -p $1/dev/dsk $1/dev/rdsk $1/stand/k46 $1/var/sadm/install
	python3 -I - "$@" <<'EOP'
import sys, os
root, first, last, d1 = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16), sys.argv[4]
for d in ('dsk', 'rdsk'):
    for n in range(first, last + 1):
        for s in range(8):
            open('%s/dev/%s/c%xd0s%d' % (root, d, n, s), 'w').close()
    if d1 == 'y':
        for n in range(16):
            for s in range(8):
                open('%s/dev/%s/c%xd1s%d' % (root, d, n, s), 'w').close()
EOP
}

# 1. no four-card kernel: nothing
tree $R 0 f y
printf 'kabi=k46.1.2\nline=46\n' > $R/stand/k46/kabi
$B/kbootset -R $R nodes > $T/out
grep -qx "kbootset: nodes: no four-card kernel installed (no sdcards=4 in /stand/k30/kabi or /stand/k46/kabi): core's nodes stand" $T/out
printf 'kabi=k46.1.2\nsdcards=2\n' > $R/stand/k46/kabi
$B/kbootset -R $R nodes | grep -q "core's nodes stand"

# 2. core's stock set under a four-card kernel: c10-c1f to make, the d1
# names to remove, the minors as C4-1 §2.1 gives them; core still names d1
printf 'kabi=k46.1.2\nsdcards=4\n' > $R/stand/k46/kabi
printf '/dev/dsk/c0d0s0 b none 18 0 0600 root root core\n/dev/dsk/c6d1s0 b none 18 134 0600 root root core\n' \
	> $R/var/sadm/install/contents
$B/kbootset -R $R nodes > $T/out
python3 -I - > $T/want <<'EOP'
def minor(card, unit, s):
    return (card & 1) << 3 | (card >> 1) << 7 | s << 4 | unit
for n in range(16):
    for s in range(8):
        for d in ('dsk', 'rdsk'):
            print('would remove /dev/%s/c%xd1s%d' % (d, n, s))
for card in (2, 3):
    for unit in range(8):
        for s in range(8):
            n = card * 8 + unit
            print('would make /dev/dsk/c%xd0s%d b 18 %d' % (n, s, minor(card, unit, s)))
            print('would make /dev/rdsk/c%xd0s%d c 40 %d' % (n, s, minor(card, unit, s)))
EOP
grep '^would ' $T/out | sort > $T/got
sort $T/want | cmp -s - $T/got || { echo "knode: the planned nodes differ from C4-1 §2.1"; diff $T/want $T/got | head; exit 1; }
grep -qx "would make /dev/rdsk/c16d0s0 c 40 134" $T/out
grep -qx "would make /dev/rdsk/c15d0s0 c 40 133" $T/out
grep -qx "would make /dev/dsk/c1fd0s7 b 18 255" $T/out
grep -qx "kbootset: nodes: the host build writes nothing: 256 to make, 256 d1 nodes to remove, core's registration left to the booted box" $T/out

# 3. the complete set, registered: nothing to do
rm -rf $R/dev && tree $R 0 1f n
printf '/dev/dsk/c0d0s0 b none 18 0 0600 root root core\n/dev/rdsk/c1fd0s7 c none 40 255 0600 root root core\n' \
	> $R/var/sadm/install/contents
$B/kbootset -R $R nodes > $T/out
grep -qx "kbootset: nodes: the four-card set is complete (c0-c1f d0 s0-s7, no d1 nodes)" $T/out

# 4. the nodes made under -R, core not yet told: the registration is left
printf '/dev/dsk/c0d0s0 b none 18 0 0600 root root core\n/dev/rdsk/c3d1s5 c none 40 211 0600 root root core\n' \
	> $R/var/sadm/install/contents
$B/kbootset -R $R nodes > $T/out
grep -qx "kbootset: nodes: the host build writes nothing: 0 to make, 0 d1 nodes to remove, core's registration left to the booted box" $T/out
! grep -q '^would ' $T/out
echo "knode: no four-card kernel, core's stock set (256 to make, 256 d1 to remove, C4-1 §2.1 minors), complete, registration left ok"
