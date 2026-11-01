#!/bin/sh
# test-gated.sh -- host tests of mkgated.sh: the four stock scripts behind
# the rc.conf gate.
#
#   sh userland/base/rc/test-gated.sh [shell]     (default sh)
#
# Needs the amix-system checkout: AMIX_SYSTEM, else the one beside the main
# working tree (as build/pkg/layout.sh finds it).
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
top=$(cd "$here/../../.." && pwd)
main=$(cd "$(git -C "$top" rev-parse --git-common-dir)/.." && pwd)
SYS=${AMIX_SYSTEM:-$(dirname "$main")/amix-system}
MAN=$top/system/MANIFEST.sha256
T=$(mktemp -d "${TMPDIR:-/tmp}/test-gated.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { [ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"; }

for n in rpc lp smtpd news; do
	sh "$here/mkgated.sh" "$SYS" "$MAN" $n "$T/$n" && ok || bad "$n: mkgated.sh failed"
	# the stock script is all there, after the gate (its "fi", and the
	# gate line of lp and smtpd)
	g=$(awk '/^fi$/ { print NR; exit }' "$T/$n")
	case $n in lp|smtpd) g=$((g + 1)) ;; esac
	tail -n +$((g + 1)) "$T/$n" > "$T/$n.body"
	case $n in
	rpc|news)
		sed -e 's/rc_enabled [a-z]* && //' "$T/$n.body" | cmp -s - "$SYS/etc/init.d/$n" && ok ||
			bad "$n: more than the gated lines differ from stock"
		;;
	*)
		cmp -s "$T/$n.body" "$SYS/etc/init.d/$n" && ok || bad "$n: the stock script is not intact"
		;;
	esac
	# it parses
	$SH -n "$T/$n" && ok || bad "$n: does not parse"
done
same "rpc: the three daemons gated" "rwalld rusersd sprayd" \
	"$(sed -n 's/.*if rc_enabled \([a-z]*\) && \[ -x .*/\1/p' "$T/rpc" | tr '\n' ' ' | sed 's/ $//')"
same "rpc: rpcbind not gated" "1" "$(grep -c '^		/usr/sbin/rpcbind ' "$T/rpc")"
same "news: mthreads gated, its stop not" "1 1" \
	"$(grep -c 'if rc_enabled mthreads && \[ -x' "$T/news") $(grep -c '^	/usr/public/lib/newsbin/trn/mthreads -k$' "$T/news")"
same "smtpd: gate line" "rc_enabled smtpd || exit 0" "$(sed -n 10p "$T/smtpd")"
same "lp: gate on start only" '[ "$1" != start ] || rc_enabled lpsched || exit 0' "$(sed -n 10p "$T/lp")"

# smtpd: off by default and with smtpd=no, nothing runs; with yes the stock
# start runs (here it reaches the daemon's path, which the host lacks)
run() { env RC_SUBR="$here/rc.subr" RC_CONF="$T/rc.conf" RC_LOG="$T/rc.log" $SH "$T/smtpd" start 2>&1; }
: > "$T/rc.conf"
same "smtpd: no line, nothing" "" "$(run)"
echo "smtpd=no" > "$T/rc.conf"
same "smtpd=no, nothing" "" "$(run)"
echo "smtpd=yes" > "$T/rc.conf"
case "$(run)" in *surrcmd/smtpd*) ok ;; *) bad "smtpd=yes: the stock start did not run" ;; esac
# without rc.subr (no /usr): off
same "no rc.subr: off" "" "$(env RC_SUBR=$T/none RC_CONF="$T/rc.conf" $SH "$T/smtpd" start 2>&1)"
# lp: stop passes the gate (lpshut, absent here: nothing), start does not
: > "$T/rc.conf"
same "lp start, off: nothing" "" "$(env RC_SUBR="$here/rc.subr" RC_CONF="$T/rc.conf" $SH "$T/lp" start 2>&1)"
# a changed stock file is refused
mkdir -p "$T/sys/etc/init.d"; cp "$SYS/etc/init.d/smtpd" "$T/sys/etc/init.d/smtpd"; echo "#" >> "$T/sys/etc/init.d/smtpd"
sh "$here/mkgated.sh" "$T/sys" "$MAN" smtpd "$T/x" 2>/dev/null && bad "a changed stock file was taken" || ok

echo "test-gated: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
