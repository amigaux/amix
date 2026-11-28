#!/bin/sh
#
# smoke.sh -- prove the libsockfix package works, ON THE BOX, as root, with it
# installed:
#
#     sh smoke.sh [<soak binary> [<N>]]
#
# Checks the two libraries hold the fixed bytes and libsocket.so is one of
# them (the DNS one exactly when it is libsockdns.so's file), that a stock
# client works through it (ping localhost, finger @localhost through inetd),
# and, given the soak program built from tests/soak.c, that N socket(),
# accept() and lookup operations of each kind grow the heap by nothing.
# Exits 0 only if every step passed.  Result lines start "RES ".
#
# Written for the 1992 Bourne shell: backticks, expr, no grep -q, no printf.

SOAK=$1
N=${2:-500}
L=/usr/lib
fails=0
ok() { echo "RES ok   $*"; }
no() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }
sz() { echo "`sum -r $1 | awk '{print $1}'` `ls -l $1 | awk '{print $5}'`"; }
ino() { ls -i $1 | awk '{print $1}'; }

[ "`sz $L/libsockhost.so`" = "64706 54032" ] && ok "libsockhost.so is the fixed file" || no "libsockhost.so is `sz $L/libsockhost.so`"
[ "`sz $L/libsockdns.so`" = "49390 67636" ] && ok "libsockdns.so is the fixed file" || no "libsockdns.so is `sz $L/libsockdns.so`"
s=`ino $L/libsocket.so`
if [ "$s" = "`ino $L/libsockdns.so`" ]; then ok "libsocket.so is libsockdns.so (DNS on)"
elif [ "$s" = "`ino $L/libsockhost.so`" ]; then ok "libsocket.so is libsockhost.so (DNS off)"
else no "libsocket.so (inode $s) is neither library"; fi
/opt/amix/sbin/libsockfix status | sed 's/^/RES      /'

/usr/sbin/ping localhost 5 > /dev/null 2>&1 && ok "ping localhost" || no "ping localhost"
f=`/usr/bin/finger @localhost 2>&1 | wc -l | tr -d ' '`
[ "$f" -gt 0 ] && ok "finger @localhost answered ($f lines)" || no "finger @localhost gave nothing"

if [ -n "$SOAK" ]; then
	for op in udp tcp unix atcp aunix; do
		r=`$SOAK $op $N`; rc=$?
		[ $rc = 0 ] && ok "$r" || no "$r (rc $rc)"
	done
	r=`$SOAK dns $N localhost`; rc=$?
	[ $rc = 0 ] && ok "$r (gethostbyname)" || no "$r (gethostbyname, rc $rc)"
fi

[ $fails = 0 ] && echo "RES smoke: all passed" || echo "RES smoke: $fails failed"
[ $fails = 0 ]
