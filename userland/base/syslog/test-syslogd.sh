#!/bin/sh
# test-syslogd.sh -- host tests of the syslogd boot step against a scratch
# syslog.conf, rc.conf and a fake daemon.
#
#   sh userland/base/syslog/test-syslogd.sh [shell]     (default sh)
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-syslogd.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { # same <name> <want> <got>
	[ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"
}
expect() { # expect <name> <want-substring> <got>
	case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac
}

mkdir -p "$T/bin"
# the daemon: says it ran, writes its pid as the real one does
printf '#!/bin/sh\necho started >> %s/calls\necho $$ > %s/syslog.pid\n' "$T" "$T" > "$T/bin/syslogd"
printf '#!/bin/sh\n' > "$T/bin/m4"
chmod +x "$T/bin/"*
{
	echo "# a comment naming $T/log/commented"
	printf 'kern.emerg;kern.err\t%s/log/kernel\n' "$T"
	printf 'auth.debug\t%s/log/security\n' "$T"
	printf '*.notice;kern.none\t%s/log/notice\n' "$T"
	printf 'kern,mark.debug\t/dev/console\n'
	printf '*.emerg\t*\n'
	printf '*.alert\troot\n'
	printf '*.alert\t@loghost\n'
	printf '*.crit\t%s/nodir/critical\n' "$T"
	printf '*.alert\t%s/log/kernel\n' "$T"
} > "$T/syslog.conf"

run() { # run start|stop [rc.conf line]
	: > "$T/calls"
	: > "$T/rc.log"
	echo "${2:-}" > "$T/rc.conf"
	env RC_SUBR="$here/../rc/rc.subr" RC_CONF="$T/rc.conf" RC_LOG="$T/rc.log" \
	    SYSLOGD="${SYSLOGD:-$T/bin/syslogd}" SYSLOG_CONF="$T/syslog.conf" SYSLOG_PID="$T/syslog.pid" \
	    SYSLOG_DIR="$T/log" M4="${M4:-$T/bin/m4}" $SH "$here/syslogd" "$1" 2>&1
}

rm -f "$T/syslog.pid"
o=$(run start)
same "start: the daemon ran" "started" "$(cat "$T/calls")"
same "start: the log files made, each once" "kernel
notice
security" "$(ls "$T/log")"
[ -s "$T/log/kernel" ] && bad "a made file is not empty" || ok
[ -e "$T/log/commented" ] && bad "a commented name was made" || ok
[ -e "$T/nodir" ] && bad "a file in a missing directory was made" || ok
expect "start: said" "syslogd: made $T/log/kernel" "$(cat "$T/rc.log")"

# running already (its pid answers): not started again; files kept
echo "message" > "$T/log/kernel"
echo $$ > "$T/syslog.pid"
o=$(run start)
same "running: not again" "" "$(cat "$T/calls")"
same "running: a file with messages kept" "message" "$(cat "$T/log/kernel")"

# a stale pid: started
echo 999999 > "$T/syslog.pid"
o=$(run start)
same "stale pid: started" "started" "$(cat "$T/calls")"

# rc.conf says no
rm -f "$T/syslog.pid"
o=$(run start "syslogd=no")
same "syslogd=no: nothing" "" "$(cat "$T/calls")"

# no m4: started, and said
o=$(M4=$T/none run start)
same "no m4: started" "started" "$(cat "$T/calls")"
expect "no m4: said" "files nothing" "$(cat "$T/rc.log")"

# no daemon: said
o=$(SYSLOGD=$T/none run start)
expect "no daemon: said" "not started" "$(cat "$T/rc.log")"

# stop: the pid gets a signal
sleep 60 &
p=$!
echo $p > "$T/syslog.pid"
run stop > /dev/null
sleep 1
if kill -0 $p 2>/dev/null
then
	bad "stop: the daemon still runs"
	kill $p
else
	ok
fi

same "usage" "1" "$(env RC_SUBR="$here/../rc/rc.subr" $SH "$here/syslogd" 2>/dev/null; echo $?)"

echo "test-syslogd: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
