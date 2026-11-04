#!/bin/sh
# test-ntp.sh -- host tests of ntpsync and the ntp boot step against fake
# rdate, crontab, setclk and sleep, in a scratch tree: no network, a DHCP
# time server, servers that do not answer, the hourly run, run twice.
#
#   sh userland/base/net/test-ntp.sh [shell]   (default sh)
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-ntp.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { [ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"; }
expect() { case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac; }
refuse() { case "$3" in *"$2"*) bad "$1: unwanted [$2] in [$3]" ;; *) ok ;; esac; }

B=$T/bin
mkdir -p "$B" "$T/st" "$T/var/dhcpc" "$T/run" "$T/lib"
# mkdir as the stock one: -p on a directory already there exits 2
printf '#!/bin/sh\nif [ "$1" = -p ]; then for d; do [ "$d" != -p ] && [ -d "$d" ] && { echo "mkdir: $d: File exists" >&2; exit 2; }; done; fi\nexec %s "$@"\n' "$(command -v mkdir)" > "$B/mkdir"
# rdate: st/rdate says "ok <address> <offset> [suffix]" or "fail"; each call
# recorded; on failure one line per host, as the real one
cat > "$B/rdate" <<EOF
#!/bin/sh
echo "rdate \$*" >> $T/st/calls
while [ \$# -gt 0 ]; do
	case "\$1" in
	-t|-r) shift 2 ;;
	-*) shift ;;
	*) break ;;
	esac
done
set -- \`cat $T/st/rdate\` "\$@"
case "\$1" in
ok)
	echo "rdate: adjust local clock by \$3 seconds\${4:+ \$4} (\$2)"
	exit 0
	;;
nohost)
	shift
	for h; do echo "rdate: \$h: host not found" >&2; done
	exit 3
	;;
esac
shift
for h; do echo "rdate: \$h: no usable answer in 15 s (2 tries)" >&2; done
exit 4
EOF
# crontab: -l prints st/crontab (none: an error); "crontab <file>" replaces it
cat > "$B/crontab" <<EOF
#!/bin/sh
echo "crontab \$*" >> $T/st/calls
if [ "\$1" = -l ]; then
	[ -f $T/st/crontab ] || { echo "crontab: can't open your crontab file." >&2; exit 1; }
	cat $T/st/crontab
	exit 0
fi
cp "\$1" $T/st/crontab
EOF
printf '#!/bin/sh\necho "setclk $*" >> %s/st/calls\n' "$T" > "$B/setclk"
# dhcpc -q <if>: a lease held while st/held.<if> exists
printf '#!/bin/sh\n[ "$1" = -q ] && [ -f %s/st/held.$2 ]\n' "$T" > "$B/dhcpc"
# sleep: recorded, at once; st/upafter <n>: the network comes after n sleeps
cat > "$B/sleep" <<EOF
#!/bin/sh
echo "sleep \$*" >> $T/st/calls
if [ -f $T/st/upafter ]; then
	n=\`cat $T/st/upafter\`
	n=\`expr \$n - 1\`
	echo \$n > $T/st/upafter
	[ \$n -le 0 ] && echo aen0 > $T/var/ifup.primary && rm -f $T/st/upafter
fi
exit 0
EOF
chmod +x "$B"/*

# dns on|off: the resolver switch, as ifup leaves it (libsocket.so one file
# with libsockdns.so, or not)
dns() {
	rm -f "${T:?}/lib/libsocket.so" "${T:?}/lib/libsockdns.so"
	: > "$T/lib/libsockdns.so"
	if [ "$1" = on ]; then ln "$T/lib/libsockdns.so" "$T/lib/libsocket.so"; else : > "$T/lib/libsocket.so"; fi
}
reset() {
	rm -f "${T:?}/st/calls" "${T:?}/st/upafter" "${T:?}/rc.log" "${T:?}/ntp.state" "${T:?}/var/dhcpc/"* "${T:?}/st/"held.*
	rm -rf "${T:?}/run/ntpsync.lock"
	echo aen0 > "$T/var/ifup.primary"
	echo "ok 192.0.2.123 -12.482113" > "$T/st/rdate"
	dns off
	: > "$T/rc.conf"
}
run() { # run <args...>: ntpsync with the test tree
	env PATH="$B:$PATH" RC_SUBR="$here/../rc/rc.subr" RC_CONF="$T/rc.conf" RC_LOG="$T/rc.log" \
	    RC_RUN="$T/run" RC_BGLOG="$T/rclog" RC_KBOOTSET="$T/none" \
	    NTP_RDATE="${RDATE_:-$B/rdate}" NTP_SETCLK="${SETCLK_:-$B/setclk}" NTP_CRONTAB="$B/crontab" \
	    NTP_STATE="$T/ntp.state" IF_STATE="$T/var" IF_LEASES="$T/var/dhcpc" NTP_DHCPC="$B/dhcpc" IF_LIB="$T/lib" \
	    $SH "$here/ntpsync" "$@"
}
calls() { cat "$T/st/calls" 2>/dev/null; }
log() { cat "$T/rc.log" 2>/dev/null; }
POOL="0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org"

# --- a run by hand: synced, said, logged, the battery clock set
reset
o=$(run 2>&1); r=$?
same "synced: status" 0 "$r"
same "synced: rdate, the pool in turn" "rdate -n -s -v -t 15 -r 1 $POOL" "$(calls | grep '^rdate')"
expect "synced: said" "ntpsync: synced from 192.0.2.123, offset -12.482 s; battery clock set" "$o"
expect "synced: logged" " ntp: synced from 192.0.2.123, offset -12.482 s; battery clock set" "$(log)"
same "synced: one log line" 1 "$(log | wc -l | tr -d ' ')"
same "battery clock: setclk -s" "setclk -s" "$(calls | grep '^setclk')"
expect "battery clock: at a minute's start" "sleep" "$(calls | grep '^sleep' || echo sleep)"
expect "state: ok" "ok " "$(cat "$T/ntp.state")"
same "lock gone" "" "$(ls "$T/run")"
o=$(run 2>&1); r=$?
same "run twice: synced again" 0 "$r"
same "run twice: two lines" 2 "$(log | wc -l | tr -d ' ')"

# --- the suffix -a adds before the address
reset
echo "ok 198.51.100.7 0.031250 (adjtime)" > "$T/st/rdate"
run > /dev/null 2>&1
expect "slew suffix: address and offset read" "synced from 198.51.100.7, offset 0.031 s" "$(log)"

# --- no network: one line, no rdate, status 1
reset
rm -f "${T:?}/var/ifup.primary"
o=$(run 2>&1); r=$?
same "no network: status" 1 "$r"
same "no network: logged once" 1 "$(log | wc -l | tr -d ' ')"
expect "no network: said" "no network (no interface has its address); not synced" "$(log)"
refuse "no network: no rdate" "rdate" "$(calls)"
refuse "no network: no battery clock" "setclk" "$(calls)"

# --- the boot run waits for the network, bounded by ntp_wait
reset
rm -f "${T:?}/var/ifup.primary"
echo "ntp_wait=10" > "$T/rc.conf"
o=$(run -b 2>&1); r=$?
same "boot, no network: status" 1 "$r"
same "boot, no network: two waits of 5 s" "sleep 5
sleep 5" "$(calls | grep '^sleep')"
same "boot, no network: one line" 1 "$(log | wc -l | tr -d ' ')"
reset
rm -f "${T:?}/var/ifup.primary"
echo 3 > "$T/st/upafter"
o=$(run -b 2>&1); r=$?
same "boot, network after 15 s: synced" 0 "$r"
same "boot: three waits" 3 "$(calls | grep -c '^sleep 5$')"
expect "boot: logged" "ntp: synced from" "$(log)"
same "boot: nothing on stdout" "" "$o"
o=$(run -b 2>&1); r=$?
same "boot run twice: synced" 0 "$r"

# --- the DHCP time servers first, the primary interface's lease first, once each
reset
echo aen1 > "$T/var/ifup.primary"
printf 'DHCP_IF=aen0\nDHCP_NTP=192.0.2.123\n' > "$T/var/dhcpc/aen0.lease"
printf 'DHCP_IF=aen1\nDHCP_NTP=198.51.100.7 192.0.2.123\n' > "$T/var/dhcpc/aen1.lease"
: > "$T/st/held.aen0"; : > "$T/st/held.aen1"
run > /dev/null 2>&1
same "DHCP first, primary's first" "rdate -n -s -v -t 15 -r 1 198.51.100.7 192.0.2.123 $POOL" "$(calls | grep '^rdate')"
o=$(run -n)
expect "-n: the servers" "servers, in turn: 198.51.100.7 192.0.2.123 $POOL (2 from DHCP)" "$o"
expect "-n: the command" "would run: $B/rdate -n -s -v -t 15 -r 1 198.51.100.7" "$o"
expect "-n: the last outcome" "last: ok " "$o"
printf 'DHCP_IF=aen0\nDHCP_NTP=\n' > "$T/var/dhcpc/aen0.lease"
rm -f "${T:?}/var/dhcpc/aen1.lease" "${T:?}/st/calls"
run > /dev/null 2>&1
same "an empty DHCP_NTP: the pool" "rdate -n -s -v -t 15 -r 1 $POOL" "$(calls | grep '^rdate')"
# a lease no dhcpc holds (its daemon ended, the file left): not asked
printf 'DHCP_IF=aen0\nDHCP_NTP=192.0.2.123\n' > "$T/var/dhcpc/aen0.lease"
rm -f "${T:?}/st/held.aen0" "${T:?}/st/calls"
run > /dev/null 2>&1
same "a lease not held: not asked" "rdate -n -s -v -t 15 -r 1 $POOL" "$(calls | grep '^rdate')"
: > "$T/st/held.aen0"; rm -f "${T:?}/st/calls"
run > /dev/null 2>&1
same "held again: asked first" "rdate -n -s -v -t 15 -r 1 192.0.2.123 $POOL" "$(calls | grep '^rdate')"

# --- rc.conf's keys
reset
printf 'ntp_servers="time.example 192.0.2.5"\nntp_timeout=20\nntp_retries=0\n' > "$T/rc.conf"
run > /dev/null 2>&1
same "keys: servers, timeout, retries" "rdate -n -s -v -t 20 -r 0 time.example 192.0.2.5" "$(calls | grep '^rdate')"
same "keys: -l bound" "$(expr 120 + 5 \* 22 + 90)" "$(run -l)"
reset
printf 'ntp_timeout=soon\nntp_retries=-1\n' > "$T/rc.conf"
run > /dev/null 2>&1
same "bad keys: the defaults" "rdate -n -s -v -t 15 -r 1 $POOL" "$(calls | grep '^rdate')"
same "default -l bound" "$(expr 120 + 6 \* 32 + 90)" "$(run -l)"
reset
echo 'ntp_servers=' > "$T/rc.conf"
o=$(run 2>&1); r=$?
same "no server at all: status" 1 "$r"
expect "no server at all: said" "no time server named" "$(log)"

# --- servers that do not answer: one line, whatever the number of servers
reset
echo fail > "$T/st/rdate"
o=$(run 2> "$T/err"); r=$?
same "unreachable: status" 1 "$r"
same "unreachable: one log line" 1 "$(log | wc -l | tr -d ' ')"
expect "unreachable: said" "no time server answered (3 tried, rdate status 4)" "$(log)"
same "unreachable: each host on stderr" 3 "$(grep -c 'no usable answer' "$T/err")"
refuse "unreachable: no battery clock" "setclk" "$(calls)"
expect "state: fail" "fail " "$(cat "$T/ntp.state")"

# --- names that cannot be looked up: says why; one line
reset
echo nohost > "$T/st/rdate"
o=$(run 2> "$T/err"); r=$?
same "no name server: status" 1 "$r"
same "no name server: one log line" 1 "$(log | wc -l | tr -d ' ')"
expect "no name server: says why" "names cannot be looked up: no name server; add a dns line to /etc/inet/interfaces, or addresses to ntp_servers in /etc/rc.conf" "$(log)"
refuse "no name server: not \"answered\"" "no time server answered" "$(log)"
expect "no name server: rdate's lines" "0.pool.ntp.org: host not found" "$(cat "$T/err")"
expect "no name server: -n says so" "no name server: a name is looked up in /etc/inet/hosts only; add a dns line to /etc/inet/interfaces, or addresses to ntp_servers in /etc/rc.conf" "$(run -n)"
: > "$T/rc.log"
o=$(run -c 2>&1)
same "no name server, hourly: nothing printed" "" "$o"
same "no name server, hourly: no line while it stays so" 0 "$(log | wc -l | tr -d ' ')"
reset
echo nohost > "$T/st/rdate"
dns on
o=$(run 2> /dev/null); r=$?
same "DNS on, names not found: status" 1 "$r"
expect "DNS on, names not found: said" "time servers not found by name (3 tried, rdate status 3)" "$(log)"
refuse "DNS on: -n has no note" "no name server" "$(run -n)"
reset
echo 'ntp_servers="192.0.2.5 198.51.100.7"' > "$T/rc.conf"
refuse "addresses only: -n has no note" "no name server" "$(run -n)"

# --- the hourly run: slews; quiet; one line only when the outcome changes
reset
echo fail > "$T/st/rdate"
o=$(run -c 2>&1); r=$?
same "hourly: nothing printed" "" "$o"
expect "hourly: slew" "rdate -n -s -v -a -t 15" "$(calls | grep '^rdate')"
same "hourly, offline: one line" 1 "$(log | wc -l | tr -d ' ')"
o=$(run -c 2>&1)
same "hourly, offline again: no new line" 1 "$(log | wc -l | tr -d ' ')"
rm -f "${T:?}/var/ifup.primary"
o=$(run -c 2>&1)
same "hourly, no network after no answer: still quiet" 1 "$(log | wc -l | tr -d ' ')"
echo aen0 > "$T/var/ifup.primary"
echo "ok 192.0.2.123 0.002 (adjtime)" > "$T/st/rdate"
o=$(run -c 2>&1)
same "hourly, back: one line" 2 "$(log | wc -l | tr -d ' ')"
expect "hourly, back: synced" "synced from 192.0.2.123, offset 0.002 s" "$(log)"
o=$(run -c 2>&1)
same "hourly, synced again: no new line" 2 "$(log | wc -l | tr -d ' ')"
same "hourly: the battery clock each time" 2 "$(calls | grep -c '^setclk -s')"

# --- ntp=no: no boot or hourly run; by hand it still runs
reset
echo "ntp=no" > "$T/rc.conf"
run -b > /dev/null 2>&1; r=$?
same "ntp=no: boot status 0" 0 "$r"
run -c > /dev/null 2>&1
same "ntp=no: no rdate" "" "$(calls)"
same "ntp=no: nothing logged" "" "$(log)"
run > /dev/null 2>&1
expect "ntp=no: by hand it runs" "rdate -n -s" "$(calls)"
expect "ntp=no: -n says so" "ntp=no: no boot or hourly run" "$(run -n)"

# --- no rdate: one line
reset
o=$(RDATE_=$T/none run 2>&1); r=$?
same "no rdate: status" 1 "$r"
expect "no rdate: said" "no $T/none; not synced" "$(log)"
same "no rdate: one line" 1 "$(log | wc -l | tr -d ' ')"

# --- the stock setclk is never run (it writes the wrong year)
reset
head -c 7120 /dev/zero > "$T/stockclk"
chmod +x "$T/stockclk"
printf '#!/bin/sh\necho "60596 14 $1"\n' > "$B/sum"
chmod +x "$B/sum"
SETCLK_=$T/stockclk run > /dev/null 2>&1
expect "stock setclk: refused" "battery clock not set: $T/stockclk is the stock one, which writes the wrong year" "$(log)"
rm -f "${B:?}/sum"
reset
SETCLK_=$T/none run > /dev/null 2>&1
expect "no setclk: said" "battery clock not set: no $T/none" "$(log)"

# --- one run at a time
reset
mkdir "$T/run/ntpsync.lock"
echo $$ > "$T/run/ntpsync.lock/pid"
o=$(run 2>&1); r=$?
same "locked: status" 1 "$r"
expect "locked: said" "another run is going (pid $$)" "$o"
o=$(run -c 2>&1); r=$?
same "locked, hourly: quiet, status 0" "0 " "$r $o"
same "locked: no rdate" "" "$(calls)"
echo 999999 > "$T/run/ntpsync.lock/pid"
run > /dev/null 2>&1; r=$?
same "a dead run's lock: taken over" 0 "$r"
same "a dead run's lock: gone after" "" "$(ls "$T/run")"

# --- root's crontab: the hourly line, its own minute, kept; out when ntp=no
reset
rm -f "${T:?}/st/crontab"
run -i
l=$(cat "$T/st/crontab")
case "$l" in
[0-9]" * * * * [ -x /usr/sbin/ntpsync ] && /usr/sbin/ntpsync -c > /dev/null 2>&1" | \
[0-9][0-9]" * * * * [ -x /usr/sbin/ntpsync ] && /usr/sbin/ntpsync -c > /dev/null 2>&1") ok ;;
*) bad "crontab line: [$l]" ;;
esac
m=${l%% *}
[ "$m" -ge 1 ] && [ "$m" -le 58 ] && ok || bad "minute $m not in 1..58"
expect "crontab: logged" "hourly run put in root's crontab, at minute $m" "$(log)"
run -i
same "-i twice: the same one line" "$l" "$(cat "$T/st/crontab")"
printf '0 3 * * * /usr/lib/acct/ckpacct\n%s\n15 4 * * 0 /usr/lib/news/expire' "$l" > "$T/st/crontab"
run -i
same "-i: other lines kept, last one unterminated" "0 3 * * * /usr/lib/acct/ckpacct
$l
15 4 * * 0 /usr/lib/news/expire" "$(cat "$T/st/crontab")"
echo "ntp=no" > "$T/rc.conf"
run -i
same "ntp=no: the line out, the rest kept" "0 3 * * * /usr/lib/acct/ckpacct
15 4 * * 0 /usr/lib/news/expire" "$(cat "$T/st/crontab")"
expect "ntp=no: logged" "ntp=no: hourly run taken out of root's crontab" "$(log)"
: > "$T/st/calls"
run -i
same "ntp=no again: crontab not rewritten" "crontab -l" "$(calls)"

# --- the boot step: crontab line, then ntpsync -b in the background
reset
rm -f "${T:?}/st/crontab"
boot() {
	cat > "$T/ntpsync-wrap" <<EOF
#!/bin/sh
PATH="$B:\$PATH" RC_SUBR="$here/../rc/rc.subr" RC_CONF="$T/rc.conf" RC_LOG="$T/rc.log" \\
RC_RUN="$T/run" RC_BGLOG="$T/rclog" NTP_RDATE="$B/rdate" NTP_SETCLK="$B/setclk" \\
NTP_CRONTAB="$B/crontab" NTP_STATE="$T/ntp.state" IF_STATE="$T/var" IF_LEASES="$T/var/dhcpc" NTP_DHCPC="$B/dhcpc" IF_LIB="$T/lib" \\
exec $SH "$here/ntpsync" "\$@"
EOF
	chmod +x "$T/ntpsync-wrap"
	# rc_bg's own timer is the real sleep: the fake one is ntpsync's only
	env RC_SUBR="$here/../rc/rc.subr" RC_CONF="$T/rc.conf" RC_LOG="$T/rc.log" \
	    RC_RUN="$T/run" RC_BGLOG="$T/rclog" NTPSYNC="$T/ntpsync-wrap" $SH "$here/ntp" "$@"
}
boot start; r=$?
same "boot step: status" 0 "$r"
expect "boot step: started, bounded" "ntp: started, bound 402 s: $T/ntpsync-wrap -b" "$(log)"
expect "boot step: crontab line" "/usr/sbin/ntpsync -c" "$(cat "$T/st/crontab" 2>/dev/null)"
n=0
while [ $n -lt 20 ] && ! grep -q "ntp: finished" "$T/rc.log"; do /bin/sleep 0.5; n=$((n + 1)); done
expect "boot step: synced in the background" "ntp: synced from 192.0.2.123" "$(log)"
expect "boot step: finished" "ntp: finished, status 0" "$(log)"
reset
echo "ntp=no" > "$T/rc.conf"
boot start
refuse "boot step, ntp=no: not started" "started" "$(log)"
same "boot step, ntp=no: no crontab line" "" "$(grep ntpsync "$T/st/crontab")"
same "boot step: stop does nothing" 0 "$(boot stop > /dev/null 2>&1; echo $?)"
same "usage" 1 "$(run -x > /dev/null 2>&1; echo $?)"

echo "test-ntp: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
