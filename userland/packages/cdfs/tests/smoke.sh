#!/bin/sh
#
# smoke.sh -- prove the cdfs package mounts a CD, ON THE BOX, as root, with
# the cdfs package and the cdfs module package of the running kernel's line
# (cdfs-k30 or cdfs-k46) installed and a disc in the drive:
#
#     sh smoke.sh <card>,<unit> [<expected name in the disc's root>]
#
# Mounts the disc on /cdrom, lists it, checks the /etc/mnttab entry, that a
# second mount of the same drive fails with status 1, and that umount
# unmounts it and removes the entry.  Exits 0 only if every step passed.
# Result lines start "RES ".
#
# Written for the 1992 Bourne shell: backticks, expr, no grep -q, no printf.

SPEC=$1
WANT=$2
H=/usr/lib/fs/cdfs/mount
M=/cdrom
T=/tmp/cdfs-smoke.$$
fails=0
ok() { echo "RES ok   $*"; }
no() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }

if [ -z "$SPEC" ]; then
	echo "usage: sh smoke.sh <card>,<unit> [<name>]"; exit 2
fi

# the payload
[ -x $H ] && ok "$H is executable" || no "$H is not executable"
n=`ls -a /usr/lib/fs/cdfs | grep -v '^\.\.*$' | wc -l | tr -d ' '`
[ "$n" = 1 ] && ok "/usr/lib/fs/cdfs holds only mount" || no "/usr/lib/fs/cdfs holds $n files"
[ -d $M ] && ok "$M is a directory" || no "$M is missing"

# the helper's usage status
$H > /dev/null 2>&1; rc=$?
[ $rc = 2 ] && ok "no operands: status 2" || no "no operands: status $rc, not 2"

# nothing mounted there to begin with
grep "	$M	" /etc/mnttab > /dev/null 2>&1 && { no "$M is already in /etc/mnttab"; exit 1; }

# mount and list
mount -F cdfs $SPEC $M > $T.out 2>&1; rc=$?
if [ $rc != 0 ]; then
	no "mount -F cdfs $SPEC $M: status $rc: `cat $T.out`"
	rm -f $T.out; echo "RES $fails failed"; exit 1
fi
ok "mount -F cdfs $SPEC $M"
ls -a $M > $T.ls 2>&1; rc=$?
n=`grep -v '^\.\.*$' $T.ls | wc -l | tr -d ' '`
[ $rc = 0 ] && [ "$n" -gt 0 ] && ok "ls $M: $n entries: `grep -v '^\.\.*$' $T.ls | head -5 | tr '\n' ' '`" ||
	no "ls $M: status $rc, $n entries"
if [ -n "$WANT" ]; then
	grep "^$WANT\$" $T.ls > /dev/null && ok "$WANT is in the disc's root" || no "$WANT is not in the disc's root"
fi

# the mnttab entry: the mount point as the special, type cdfs, ro
e=`grep "^$M	$M	cdfs	ro	" /etc/mnttab | wc -l | tr -d ' '`
[ "$e" = 1 ] && ok "/etc/mnttab: $M $M cdfs ro" || no "/etc/mnttab has $e cdfs entries for $M"
mount | grep "^$M on $M" > /dev/null && ok "mount lists $M" || no "mount does not list $M"

# a second mount of the same drive is refused (EBUSY), status 1
mount -F cdfs $SPEC $M > $T.out 2>&1; rc=$?
[ $rc = 1 ] && ok "second mount: status 1: `cat $T.out`" || no "second mount: status $rc: `cat $T.out`"

# umount unmounts it and removes the entry
umount $M > $T.out 2>&1; rc=$?
[ $rc = 0 ] && ok "umount $M" || no "umount $M: status $rc: `cat $T.out`"
grep "	$M	cdfs	" /etc/mnttab > /dev/null 2>&1 && no "the entry is still in /etc/mnttab" || ok "the entry is gone"
n=`ls -a $M | grep -v '^\.\.*$' | wc -l | tr -d ' '`
[ "$n" = 0 ] && ok "$M is empty again" || no "$M still lists $n entries"

rm -f $T.out $T.ls
[ $fails = 0 ] && echo "RES PASS" || echo "RES $fails failed"
[ $fails = 0 ]
