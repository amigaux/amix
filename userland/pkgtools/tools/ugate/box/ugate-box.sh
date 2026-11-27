#!/bin/sh
# ugate-box.sh URL -- ON THE BOX, run from its own directory (the host hook pushes it there with ./cmds).
#
# The user-path gate's box side. A released system, installed and first-booted as a user has it, runs the row's
# commands exactly as typed at a root prompt, against the candidate repository at URL:
#   1. state before: uname -a, apkg version, pkginfo, df -k + swap -l, pkgchk -n;
#   2. /etc/apkg.conf's repo= line set to URL (the one change made to the box; the original is kept as
#      ./apkg.conf.orig, the line before and after are recorded);
#   3. each line of ./cmds, in order: "RC<TAB>command" (RC = the exit status the row expects), run as
#      sh -c 'command' after /etc/profile, stdin /dev/null; output in ./out.N, status in ./results;
#   4. /etc/apkg.conf put back, state after (the same set, pkgchk -n again);
#   5. ./READY: "READY ugate <n> commands" when every command ran, whatever their status.
# The host judges: nothing here decides pass or fail.
# Bourne shell of 1992: no $( ), no local, no functions with return values beyond status.
D=`pwd`; U=$1
[ -n "$U" ] || { echo "usage: ugate-box.sh URL" >&2; exit 2; }
now() { date '+%H:%M:%S'; }
note() { echo "`now` $*" >> $D/steps.log; }
PC=/usr/sbin/pkgchk; [ -x /usr/apkg/bin/pkgchk ] && PC=/usr/apkg/bin/pkgchk
state() {	# state TAG
	uname -a > $D/uname-$1.txt 2>&1
	pkginfo > $D/pkginfo-$1.txt 2>&1
	df -k > $D/df-$1.txt 2>&1; swap -l >> $D/df-$1.txt 2>&1
	/usr/apkg/bin/apkg version > $D/apkg-$1.txt 2>&1
	$PC -n > $D/pkgchk-$1.txt 2>&1; echo "rc=$?" >> $D/pkgchk-$1.txt
	note "$1: `cat $D/uname-$1.txt`; `cat $D/apkg-$1.txt`; `pkginfo | wc -l` packages; pkgchk -n `grep -c '^ERROR' $D/pkgchk-$1.txt` ERROR"
}
rm -f $D/READY $D/steps.log $D/results $D/out.*
note "ugate box: repo $U; pkgchk is $PC"
state before
cp /etc/apkg.conf $D/apkg.conf.orig || { echo "READY ugate FAILED: no /etc/apkg.conf" > $D/READY; exit 1; }
note "repo before: `grep '^repo=' /etc/apkg.conf`"
sed "s|^repo=.*|repo=$U|" $D/apkg.conf.orig > /etc/apkg.conf
note "repo set: `grep '^repo=' /etc/apkg.conf`"
n=0
# the command lines are read on fd 3, so a command that reads stdin cannot eat the list
exec 3< $D/cmds
while read want cmd <&3; do
	[ -n "$cmd" ] || continue
	n=`expr $n + 1`
	note "cmd $n: $cmd"
	sh -c ". /etc/profile > /dev/null 2>&1; $cmd" < /dev/null > $D/out.$n 2>&1; rc=$?
	echo "$n	$rc	$want	$cmd" >> $D/results
	note "cmd $n rc=$rc (expected $want): `tail -1 $D/out.$n`"
done
exec 3<&-
cp $D/apkg.conf.orig /etc/apkg.conf
note "repo restored: `grep '^repo=' /etc/apkg.conf`"
state after
sync
echo "READY ugate $n commands `now`" > $D/READY
note "`cat $D/READY`"
