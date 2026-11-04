#!/sbin/sh
#
# smoke.sh <sntp-server> [port] -- rdate on the box, after pkgadd.  Reads the
# clock only (-p), except the last check, which sets it from the server
# (root).  Each check prints "ok" or "FAIL"; the last line is
# "RES smoke PASS" or "RES smoke FAIL <n>".
#
# The system's /bin/sh of 1992: backticks, no $(...), no `local', no `!'.

S=$1
O=
[ -n "$2" ] && O="-o $2"
[ -n "$S" ] || { echo "usage: smoke.sh sntp-server [port]" >&2; exit 2; }
R=/opt/amix/sbin/rdate
fails=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fails=`expr $fails + 1`; }
T=/usr/tmp/rdate-smoke.$$
mkdir -p $T || exit 2

[ -x $R ] && ok "$R installed" || bad "no $R"

$R > $T/o 2>&1; rc=$?
[ $rc -eq 2 ] && ok "usage: exit 2" || bad "usage: exit $rc"

$R -n -p -v -t 15 $O $S > $T/o 2> $T/e; rc=$?
if [ $rc -eq 0 ] && grep "^rdate: adjust local clock by -*[0-9]*\.[0-9]* seconds (" $T/o > /dev/null; then
	ok "SNTP from $S: `tail -1 $T/o`"
else
	bad "SNTP from $S: exit $rc, `cat $T/e`"
fi

s=`date +%H%M%S`
$R -n -p -t 3 -r 1 192.0.2.1 > $T/o 2> $T/e; rc=$?
e=`date +%H%M%S`
if [ $rc -eq 4 ] && [ `wc -l < $T/e` -eq 1 ]; then
	ok "no answer: exit 4, one line, $s -> $e (bound 2 x 3 s)"
else
	bad "no answer: exit $rc, `cat $T/e`"
fi

$R -n -p -t 3 -r 1 no.such.host.invalid > $T/o 2> $T/e; rc=$?
if [ $rc -eq 3 ] || [ $rc -eq 4 ]; then
	ok "a name that does not resolve: exit $rc, `cat $T/e`"
else
	bad "a name that does not resolve: exit $rc, `cat $T/e`"
fi

$R -n -p -t 3 -r 0 -6 $O $S > $T/o 2> $T/e; rc=$?
[ $rc -ne 0 ] && ok "-6 refused: exit $rc" || bad "-6 gave a time"

if [ "`id | sed 's/(.*//'`" = "uid=0" ]; then
	$R -n -s -v -t 15 $O $S > $T/o 2> $T/e; rc=$?
	[ $rc -eq 0 ] && ok "clock set: `cat $T/o`" || bad "setting the clock: exit $rc, `cat $T/e`"
fi

rm -rf "${T:?}"
if [ $fails -eq 0 ]; then echo "RES smoke PASS"; else echo "RES smoke FAIL $fails"; fi
exit $fails
