#!/bin/sh
# test-display.sh -- host tests of xstart, display.subr and the display boot
# step against a scratch /etc/display, card files whose nodes are plain files
# (open = there), and fake servers, xinit, xdm and switch tools.
#
#   sh userland/base/display/test-display.sh [shell]     (default sh)
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-display.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { # same <name> <want> <got>
	[ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"
}
expect() { # expect <name> <want-substring> <got>
	case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac
}
refuse() { case "$3" in *"$2"*) bad "$1: unwanted [$2] in [$3]" ;; *) ok ;; esac; }

B=$T/bin
mkdir -p "$B" "$T/d" "$T/home" "$T/dev" "$T/log" "$T/tmp"
for p in Xzz Xnat xinit xdm dtlogin tool; do
	printf '#!/bin/sh\necho "%s $*" >> %s/calls\n' $p "$T" > "$B/$p"
done
# ps -ef as Amix prints it: a header, then st/ps's lines while st/ps-left
# (polls still to answer) is above 0; each call counts one down
mkdir -p "$T/st"
{
	echo '#!/bin/sh'
	echo 'echo "     UID   PID  PPID  C    STIME TTY      TIME COMD"'
	echo "n=\`cat $T/st/ps-left 2>/dev/null || echo 0\`"
	echo '[ "$n" -gt 0 ] || exit 0'
	echo "cat $T/st/ps"
	echo "echo \`expr \$n - 1\` > $T/st/ps-left"
} > "$B/ps"
# xinit: the session, then the server's line as the pid wrapper runs it (the
# wrapper's exec line), the wrapper itself kept as st/lastwrap
cat > "$B/xinit" <<EOF
#!/bin/sh
c=\$1; shift; [ "\$1" = -- ] && shift
w=\$1; shift
case \$w in
*/xstart.*.server) cp "\$w" $T/st/lastwrap; w=\`sed -n 's/^exec \\([^ ]*\\) .*/\\1/p' "\$w"\` ;;
esac
echo "xinit \$c -- \$w \$*" >> $T/calls
EOF
printf '#!/bin/sh\nexit 1\n' > "$B/monswctl-no"
printf '#!/bin/sh\nexit 0\n' > "$B/monswctl-yes"
chmod +x "$B/"*
cat > "$T/d/z3660" <<EOF
# the RTG card
node     $T/dev/zz9000
module   z3660rtg
server   $B/Xzz
modes    1024x768 640x480 1920x1080
depths   16
args     -mode %m -w %w -h %h -bpp %d -n %n
limits   vmem=131072 data=65536
monsw    yes
monswtool $B/tool
EOF
cat > "$T/d/native" <<EOF
node     $T/dev/console
server   $B/Xnat
modes    auto
depths   1
env      SCREEN_GROUP=%n
monsw    no
EOF
: > "$T/dev/console"

conf() { cat > "$T/display"; }
run() { # run <args...>: xstart, its output and status
	: > "$T/calls"
	env DISP_SUBR="$here/display.subr" DISP_CONF="$T/display" DISP_D="${D_:-$T/d}" HOME="$T/home" \
	    XINITS="${XI:-$B/xinit}" XDMS="$B/xdm" DTLOGINS="${DTL:-$B/dtlogin}" XSESSION="${XS:-$T/xsession}" \
	    MONSWCTL="${MCTL:-$B/monswctl-no}" XSTART_TMP="$T/tmp" \
	    R6DIR="$T/r6" STOCKXDIR="$T/stockx" XSTART_PS="${PS_:-$B/ps}" XSTART_WAIT="${WAIT_:-60}" XSTART_KILLWAIT="${KW_:-10}" \
	    $SH "$here/xstart" "$@" 2>&1
	echo "rc=$?"
}
echo '#!/bin/sh' > "$T/xsession"

# --- auto: the RTG card when its node is there, the native one otherwise
conf <<'EOF'
card auto
EOF
o=$(run -n)
expect "auto, no RTG: native" "card     native" "$o"
expect "native: the server's mode" "mode     chosen by the server, depth 1" "$o"
expect "native: the server's line" "server   $B/Xnat :0" "$o"
expect "native: its environment" "env      SCREEN_GROUP=0" "$o"
: > "$T/dev/zz9000"
o=$(run -n)
expect "auto, RTG there: z3660" "card     z3660" "$o"
expect "z3660: its first mode" "server   $B/Xzz :0 -mode 1024x768 -w 1024 -h 768 -bpp 16 -n 0" "$o"
expect "-n: status 0" "rc=0" "$o"
same "-n: nothing run" "" "$(cat "$T/calls")"

# --- the mode: /etc/display's, an argument's, and a wrong one
conf <<'EOF'
card    z3660
mode    1920x1080   # the big one
EOF
o=$(run -n :1)
expect "mode from the file, display :1" "server   $B/Xzz :1 -mode 1920x1080 -w 1920 -h 1080 -bpp 16 -n 1" "$o"
o=$(run -n 640x480)
expect "mode from the argument" "-mode 640x480" "$o"
o=$(run -n 1280x1024)
expect "a mode the card lacks" "z3660 has no mode 1280x1024 (it has: 1024x768 640x480 1920x1080)" "$o"
expect "a mode the card lacks: status 1" "rc=1" "$o"
o=$(run -n depth=8)
expect "a depth the card lacks" "z3660 has no depth 8" "$o"
o=$(run -n card=native mode=800x600)
expect "native ignores a mode" "native picks its own mode; mode 800x600 ignored" "$o"

# --- a card by name whose node is not there; a card that does not exist
rm -f "${T:?}/dev/zz9000"
o=$(run -n)
expect "named card absent" "z3660: its node $T/dev/zz9000 does not open" "$o"
o=$(run -n card=va2000)
expect "no such card file" "no card file $T/d/va2000" "$o"
: > "$T/dev/zz9000"

# --- the session: ~/.xsession, ~/.xinitrc, /etc/display's, the system's
o=$(run -n)
expect "session: the system's" "session  $T/xsession" "$o"
echo '#!/bin/sh' > "$T/mysession"
printf 'card z3660\nsession %s\n' "$T/mysession" | conf
o=$(run -n)
expect "session: /etc/display's" "session  $T/mysession" "$o"
: > "$T/home/.xinitrc"
o=$(run -n)
expect "session: ~/.xinitrc" "session  $T/home/.xinitrc" "$o"
: > "$T/home/.xsession"
o=$(run -n)
expect "session: ~/.xsession first" "session  $T/home/.xsession" "$o"
rm -f "${T:?}/home/.xsession" "${T:?}/home/.xinitrc"

# --- a run: xinit with the session and the server's line
conf <<'EOF'
card z3660
mode 640x480
EOF
o=$(run)
same "run: xinit" "xinit $T/xsession -- $B/Xzz :0 -mode 640x480 -w 640 -h 480 -bpp 16 -n 0" "$(cat "$T/calls")"

# --- a card's environment reaches the server alone; restore after a crash.
# A live xinit: the server in the background, then the session, then the
# server stopped -- as the real one does
cat > "$B/xlive" <<EOF
#!/bin/sh
c=\$1; shift; [ "\$1" = -- ] && shift
echo "xinit \$c -- \$*" >> $T/calls
"\$@" &
sp=\$!
sleep 1
"\$c"
kill \$sp 2>/dev/null
exit 0
EOF
cat > "$B/Xlive" <<EOF
#!/bin/sh
echo "server SG=\${SCREEN_GROUP-unset} \$*" >> $T/calls
[ -f $T/die ] && exit 1
exec sleep 20
EOF
printf '#!/bin/sh\necho "client SG=${SCREEN_GROUP-unset}" >> %s/calls\n' "$T" > "$T/livesession"
printf '#!/bin/sh\necho restore >> %s/calls\n' "$T" > "$B/kbdback"
chmod +x "$B/xlive" "$B/Xlive" "$B/kbdback" "$T/livesession"
cat > "$T/d/live" <<EOF
node     $T/dev/console
server   $B/Xlive
modes    auto
env      SCREEN_GROUP=%n
restore  $B/kbdback
EOF
printf 'card live\n' | conf
rm -f "${T:?}/die"
o=$(XI=$B/xlive XS=$T/livesession run :10)
expect "env: the server has it" "server SG=10 :10" "$(cat "$T/calls")"
expect "env: the session does not" "client SG=unset" "$(cat "$T/calls")"
refuse "normal end: no restore" "restore" "$(cat "$T/calls")"
same "normal end: nothing said" "rc=0" "$o"
: > "$T/die"
o=$(XI=$B/xlive XS=$T/livesession run :10)
expect "server died: restore ran" "restore" "$(cat "$T/calls")"
expect "server died: said" "the server ended on its own; running $B/kbdback" "$o"
refuse "server died: not taken for a killed xinit" "xinit ended" "$o"
rm -f "${T:?}/die"
same "wrappers removed" "" "$(ls "$T/tmp")"
o=$(run -n card=live)
expect "-n: env for the server only" "(env for the server only)" "$o"
expect "-n: the restore command" "restore  $B/kbdback, when the server ends on its own" "$o"
# no env, no restore: the server still runs through the wrapper that records
# its pid, and the wrapper only execs it
printf 'card z3660\nmode 640x480\n' | conf
o=$(run)
same "no env or restore: the server's line" "xinit $T/xsession -- $B/Xzz :0 -mode 640x480 -w 640 -h 480 -bpp 16 -n 0" "$(cat "$T/calls")"
expect "no env or restore: the wrapper records its pid" "echo \$\$ > $T/tmp/xstart." "$(cat "$T/st/lastwrap")"
expect "no env or restore: then execs the server" "exec $B/Xzz \"\$@\"" "$(cat "$T/st/lastwrap")"
refuse "no env or restore: no environment" "export" "$(cat "$T/st/lastwrap")"
# --- xinit dies with the server still running (killed by TERM: it takes no
# shutdown then). A server that lists itself in ps -ef while it lives, as the
# box prints it; ps2 shows the live ones and st/ps-extra
mkdir -p "$T/st/run"
cat > "$B/ps2" <<EOF
#!/bin/sh
echo "     UID   PID  PPID  C    STIME TTY      TIME COMD"
for f in $T/st/run/*; do [ -f "\$f" ] && kill -0 \`basename "\$f"\` 2>/dev/null && cat "\$f"; done
cat $T/st/ps-extra 2>/dev/null
exit 0
EOF
cat > "$B/Xkeep" <<EOF
#!/bin/sh
echo "server \$*" >> $T/calls
echo "    root \$\$     1  0 14:03:22 ?        0:05 \$0 \$*" > $T/st/run/\$\$
if [ -f $T/st/ignore-term ]; then trap '' 15
else trap 'echo "server TERM" >> $T/calls; rm -f $T/st/run/\$\$; exit 0' 15; fi
while :; do sleep 1; done
EOF
# xinit killed: the server started, then TERM to itself, no shutdown
cat > "$B/xkill" <<EOF
#!/bin/sh
c=\$1; shift; [ "\$1" = -- ] && shift
echo "xinit \$c -- \$*" >> $T/calls
"\$@" &
i=0
while [ -z "\`ls $T/st/run\`" ] && [ \$i -lt 50 ]; do sleep 0.1; i=\`expr \$i + 1\`; done
kill -15 \$\$
EOF
# xinit whose server died (status 0, as xinit exits then), with the pid file
# naming another process by now
cat > "$B/xstale" <<EOF
#!/bin/sh
c=\$1; shift; [ "\$1" = -- ] && shift
echo "xinit \$c -- \$*" >> $T/calls
w=\`echo "\$1" | sed 's/\.server\$//'\`
sleep 30 < /dev/null > /dev/null 2>&1 &
echo \$! > "\$w.pid"
echo \$! > $T/st/stalepid
printf '    root %5d     1  0 14:03:22 ?        0:00 /usr/bin/sleep 30\n' \$! > $T/st/ps-extra
exit 0
EOF
# xinit that caught a signal: it stops the server (TERM), then exits 1
cat > "$B/xsig" <<EOF
#!/bin/sh
c=\$1; shift; [ "\$1" = -- ] && shift
echo "xinit \$c -- \$*" >> $T/calls
"\$@" &
i=0
while [ -z "\`ls $T/st/run\`" ] && [ \$i -lt 50 ]; do sleep 0.1; i=\`expr \$i + 1\`; done
kill -15 \`ls $T/st/run\`
i=0
while [ -n "\`ls $T/st/run\`" ] && [ \$i -lt 50 ]; do sleep 0.1; i=\`expr \$i + 1\`; done
exit 1
EOF
chmod +x "$B/ps2" "$B/Xkeep" "$B/xkill" "$B/xstale" "$B/xsig"
cat > "$T/d/keep" <<EOF
node     $T/dev/console
server   $B/Xkeep
modes    auto
restore  $B/kbdback
EOF
printf 'node %s/dev/console\nserver %s/Xkeep\nmodes auto\n' "$T" "$B" > "$T/d/keepnr"
printf 'card keep\n' | conf
rm -f "$T/st/run/"* "$T/st/ps-extra" "$T/st/ignore-term"
# the server ends on TERM: said once, ended, then the restore
o=$(XI=$B/xkill PS_=$B/ps2 KW_=3 run :10)
expect "xinit killed: said" "xinit ended while the server (pid " "$o"
expect "xinit killed: and what follows" "still ran; ending it, then running $B/kbdback" "$o"
same "xinit killed: one line" 1 "$(echo "$o" | grep -c xstart:)"
refuse "xinit killed: not taken for a crash" "ended on its own" "$o"
refuse "xinit killed: TERM was enough" "killing it" "$o"
same "xinit killed: the server, its TERM, then the restore" "server :10
server TERM
restore" "$(grep -v '^xinit' "$T/calls")"
same "xinit killed: no server left" "" "$(ls "$T/st/run")"
same "xinit killed: wrappers removed" "" "$(ls "$T/tmp")"
expect "xinit killed: status 0" "rc=0" "$o"
# a server that ignores TERM: KILL after the wait, then the restore
: > "$T/st/ignore-term"
o=$(XI=$B/xkill PS_=$B/ps2 KW_=2 run :10)
sp=$(ls "$T/st/run")
expect "TERM ignored: said" "the server (pid $sp) did not end in 2 s; killing it" "$o"
kill -0 "$sp" 2>/dev/null && bad "TERM ignored: the server still runs" || ok
same "TERM ignored: the restore after it" "server :10
restore" "$(grep -v '^xinit' "$T/calls")"
expect "TERM ignored: status 0" "rc=0" "$o"
rm -f "$T/st/run/"* "$T/st/ignore-term"
# the recorded pid is another process now: never signalled; the server is
# gone, so it ended on its own
o=$(XI=$B/xstale PS_=$B/ps2 KW_=2 run :10)
sp=$(cat "$T/st/stalepid")
kill -0 "$sp" 2>/dev/null && ok || bad "stale pid: another process was signalled"
expect "stale pid: the server ended on its own" "the server ended on its own; running $B/kbdback" "$o"
refuse "stale pid: not taken for the server" "still ran" "$o"
kill "$sp" 2>/dev/null
# the same pid running this server, but on another display (another
# session's): not ours either
sleep 30 < /dev/null > /dev/null 2>&1 & sp=$!
printf '    root %5d     1  0 14:03:22 ?        0:00 %s/Xkeep :5\n' "$sp" "$B" > "$T/st/ps-extra"
cat > "$B/xstale5" <<EOF
#!/bin/sh
c=\$1; shift; [ "\$1" = -- ] && shift
echo "xinit \$c -- \$*" >> $T/calls
echo $sp > \`echo "\$1" | sed 's/\.server\$//'\`.pid
exit 1
EOF
chmod +x "$B/xstale5"
o=$(XI=$B/xstale5 PS_=$B/ps2 KW_=2 run :10)
kill -0 "$sp" 2>/dev/null && ok || bad "another display's server was signalled"
refuse "another display's server: not ours" "still ran" "$o"
kill "$sp" 2>/dev/null
rm -f "$T/st/ps-extra"
# xinit caught a signal and stopped the server itself (status 1): not taken
# for a crash, and the restore runs after the server is gone
o=$(XI=$B/xsig PS_=$B/ps2 KW_=2 run :10)
expect "xinit stopped it on a signal: said" "xinit ended the session (status 1) and the server is gone; running $B/kbdback" "$o"
refuse "xinit stopped it on a signal: not a crash" "ended on its own" "$o"
refuse "xinit stopped it on a signal: nothing to end" "still ran" "$o"
same "xinit stopped it on a signal: the server's TERM, then the restore" "server :10
server TERM
restore" "$(grep -v '^xinit' "$T/calls")"
# a card with no restore: the server still ended, nothing else run
printf 'card keepnr\n' | conf
o=$(XI=$B/xkill PS_=$B/ps2 KW_=3 run :10)
expect "no restore: said" "still ran; ending it" "$o"
refuse "no restore: no restore named" "then running" "$o"
same "no restore: no server left" "" "$(ls "$T/st/run")"
o=$(run -n card=keep)
expect "-n: when the restore runs" "restore  $B/kbdback, when the server ends on its own or xstart ends it" "$o"
rm -f "${T:?}/d/keep" "${T:?}/d/keepnr"
# xdm keeps the env in its line
printf 'card native\n' | conf
o=$(run -xdm :10)
same "env: in xdm's line" "xdm -server :10 local /usr/bin/env SCREEN_GROUP=10 $B/Xnat :10" "$(cat "$T/calls")"
rm -f "${T:?}/d/live"
# a restore that is not a full path is a mistake
printf 'server %s\nrestore kbdback\n' "$B/Xnat" > "$T/d/zbad"
o=$(run -n card=native)
expect "restore not a full path: said" "$T/d/zbad:2: restore is a command by its full path" "$o"
rm -f "${T:?}/d/zbad"

# --- once: the card's, else -terminate for an X11R6 server, -once for the
# stock one, nothing for another; never on xdm's line
mkdir -p "$T/r6/bin" "$T/stockx/bin"
for x in "$T/r6/bin/Xr6" "$T/stockx/bin/X"; do
	printf '#!/bin/sh\necho "server $*" >> %s/calls\n' "$T" > "$x"
	chmod +x "$x"
done
printf 'node %s/dev/console\nserver %s/r6/bin/Xr6\nmodes auto\n' "$T" "$T" > "$T/d/r6"
printf 'node %s/dev/console\nserver %s/stockx/bin/X\nmodes auto\n' "$T" "$T" > "$T/d/stock"
printf 'card r6\n' | conf
o=$(run)
same "once: X11R6 server, -terminate" "xinit $T/xsession -- $T/r6/bin/Xr6 :0 -terminate" "$(cat "$T/calls")"
o=$(run -n)
expect "once: -n shows it" "-- $T/r6/bin/Xr6 :0 -terminate" "$o"
o=$(run -xdm)
same "once: never on xdm's line" "xdm -server :0 local $T/r6/bin/Xr6 :0" "$(cat "$T/calls")"
o=$(run card=stock)
same "once: stock server, -once" "xinit $T/xsession -- $T/stockx/bin/X :0 -once" "$(cat "$T/calls")"
echo "once none" >> "$T/d/r6"
o=$(run)
same "once none: no option" "xinit $T/xsession -- $T/r6/bin/Xr6 :0" "$(cat "$T/calls")"
sed -i '$d' "$T/d/r6"; echo "once -kill-at-end" >> "$T/d/r6"
o=$(run)
same "once: the card's own" "xinit $T/xsession -- $T/r6/bin/Xr6 :0 -kill-at-end" "$(cat "$T/calls")"
sed -i '$d' "$T/d/r6"; echo "once sometimes" >> "$T/d/r6"
o=$(run -n)
expect "once: a bad value said" "$T/d/r6:4: once is the server's option, as -terminate, or none" "$o"
sed -i '$d' "$T/d/r6"
o=$(run card=z3660 mode=640x480)
same "once: another server, nothing" "xinit $T/xsession -- $B/Xzz :0 -mode 640x480 -w 640 -h 480 -bpp 16 -n 0" "$(cat "$T/calls")"
printf 'node %s/dev/console\nserver %s/r6/bin/Xr6\nmodes auto\nenv SCREEN_GROUP=%%n\n' "$T" "$T" > "$T/d/r6env"
o=$(run card=r6env)
expect "once: the env wrapper exports" 'SCREEN_GROUP="0"; export SCREEN_GROUP' "$(cat "$T/st/lastwrap")"
same "once: the wrapper's line ends with it" "xinit $T/xsession -- $T/r6/bin/Xr6 :0 -terminate" "$(cat "$T/calls")"
# the wrapper cannot be written (XSTART_TMP a file): said, status 1, no
# session (the box's sh would lose the status to an EXIT trap)
mv "$T/tmp" "$T/tmp.d"; : > "$T/tmp"
o=$(run card=r6env)
expect "no wrapper: said" "cannot write $T/tmp/xstart." "$o"
expect "no wrapper: status 1" "rc=1" "$o"
same "no wrapper: no session" "" "$(cat "$T/calls")"
rm -f "${T:?}/tmp"; mv "$T/tmp.d" "$T/tmp"
rm -f "${T:?}/d/r6env"
same "native card file: once -once" "-once" "$(sh -c ". '$here/display.subr'; disp_val '$here/display.d/native' once")"

# --- an X server still on the display: wait for it, or refuse
printf 'card r6\n' | conf
printf '    root   612     1  0 14:03:22 ?        0:05 %s/r6/bin/Xr6 :0 -terminate\n' "$T" > "$T/st/ps"
echo 1 > "$T/st/ps-left"
o=$(run -n)
expect "-n: a running server reported" "running  an X server on :0 (pid 612); xstart waits up to 60 s for it to end" "$o"
echo 2 > "$T/st/ps-left"
o=$(run)
expect "ending server: waited, said" "an X server on :0 (pid 612) is still running; waiting up to 60 s for it to end" "$o"
same "ending server: said once" 1 "$(echo "$o" | grep -c 'waiting up to')"
same "ending server: then started" "xinit $T/xsession -- $T/r6/bin/Xr6 :0 -terminate" "$(cat "$T/calls")"
echo 99 > "$T/st/ps-left"
o=$(WAIT_=2 run)
expect "a server that stays: refused" "an X server on :0 is still running (pid 612); not starting another" "$o"
expect "a server that stays: status 1" "rc=1" "$o"
same "a server that stays: nothing started" "" "$(cat "$T/calls")"
echo 99 > "$T/st/ps-left"
o=$(WAIT_=2 run -xdm)
expect "-xdm waits as well" "not starting another" "$o"
same "-xdm refused: no xdm" "" "$(cat "$T/calls")"
printf '    root   612     1  0   Nov  2 ?        0:05 %s/r6/bin/Xr6 :1 -terminate\n' "$T" > "$T/st/ps"
echo 99 > "$T/st/ps-left"
o=$(WAIT_=2 run)
refuse "a server on :1 does not block :0" "still running" "$o"
o=$(WAIT_=2 run :1)
expect "it blocks :1 (STIME two fields)" "an X server on :1 is still running (pid 612)" "$o"
printf '    root   600     1  0 14:03:20 ?        0:00 %s/r6/bin/xinit /x -- %s/r6/bin/Xr6 :0\n' "$T" "$T" > "$T/st/ps"
echo 99 > "$T/st/ps-left"
o=$(WAIT_=2 run)
refuse "xinit's own line is not a server" "still running" "$o"
rm -f "${T:?}/st/ps-left" "${T:?}/d/r6" "${T:?}/d/stock"

# --- the monitor switch: the tool around the session when no monsw module
printf 'card z3660\nmonsw 34\n' | conf
o=$(run)
same "monsw: the tool, then back" "tool 34 rtg
xinit $T/xsession -- $B/Xzz :0 -mode 1024x768 -w 1024 -h 768 -bpp 16 -n 0
tool 34 off" "$(cat "$T/calls")"
o=$(MCTL=$B/monswctl-yes run)
refuse "monsw module answers: no tool" "tool" "$(cat "$T/calls")"
printf 'card native\nmonsw 34\n' | conf
o=$(run)
refuse "a card without monsw: no tool" "tool" "$(cat "$T/calls")"

# --- -xdm: xdm with the server line, no session
printf 'card z3660\nmode 1920x1080\n' | conf
o=$(run -xdm)
same "-xdm" "xdm -server :0 local $B/Xzz :0 -mode 1920x1080 -w 1920 -h 1080 -bpp 16 -n 0" "$(cat "$T/calls")"

# --- -dtlogin: CDE's dtlogin with the same server line; absent, said
o=$(run -dtlogin)
same "-dtlogin" "dtlogin -server :0 local $B/Xzz :0 -mode 1920x1080 -w 1920 -h 1080 -bpp 16 -n 0" "$(cat "$T/calls")"
o=$(run -n -dtlogin)
expect "-n -dtlogin" "dtlogin  $B/dtlogin -server" "$o"
o=$(DTL=$T/none run -dtlogin)
expect "no dtlogin: said" "start dtlogin needs CDE's dtlogin ($T/none); not started" "$o"
expect "no dtlogin: status 1" "rc=1" "$o"
same "no dtlogin: nothing run" "" "$(cat "$T/calls")"
printf 'card z3660\nstart dtlogin\n' | conf
o=$(run -n)
refuse "start dtlogin is a valid value" "start is manual" "$o"

# --- mistakes: said by -n, which then exits 1
conf <<'EOF'
card    z3660
mode    big
start   sometimes
colour  blue
EOF
o=$(run -n)
expect "bad mode said" "$T/display:2: mode is W x H" "$o"
expect "bad start said" "$T/display:3: start is manual, xdm or dtlogin" "$o"
expect "unknown key said" "$T/display:4: unknown key \"colour\"" "$o"
echo "colour blue" >> "$T/d/native"
o=$(run -n card=z3660 mode=640x480)
expect "a card file's mistake said" "$T/d/native:7: unknown key \"colour\"" "$o"
expect "mistakes: -n status 1" "rc=1" "$o"
sed -i '$d' "$T/d/native"

# --- the probe: exit 0 = the card is here; its node, modes and depths
# lines replace the file's; %p is the node in use
cat > "$B/pr" <<EOF
#!/bin/sh
echo "pr \$*" >> $T/calls
[ -f $T/st/pr-out ] && cat $T/st/pr-out
exit \`cat $T/st/pr-rc 2>/dev/null || echo 0\`
EOF
chmod +x "$B/pr"
cat > "$T/d/aprobe" <<EOF
node     $T/dev/zz9000
server   $B/Xzz
modes    1024x768
depths   16
probe    $B/pr one two
args     -mode %m -dev %p
env      CARD=%p
EOF
printf 'card auto\n' | conf
echo 1 > "$T/st/pr-rc"
o=$(run -n)
expect "probe fails: auto takes the next" "card     z3660" "$o"
expect "probe: given its args" "pr one two" "$(cat "$T/calls")"
refuse "probe fails: not a fault" "aprobe:" "$o"
o=$(run -n card=aprobe)
expect "probe fails, named card: said" "aprobe: its probe $B/pr one two finds no card" "$o"
expect "probe fails, named card: status 1" "rc=1" "$o"
echo 0 > "$T/st/pr-rc"
o=$(run -n)
expect "probe answers: auto takes it" "card     aprobe" "$o"
expect "-n shows the probe" "probe    $B/pr one two" "$o"
expect "no lines: the file's node" "node     $T/dev/zz9000" "$o"
expect "%p in args" "server   $B/Xzz :0 -mode 1024x768 -dev $T/dev/zz9000" "$o"
expect "%p in env" "env      CARD=$T/dev/zz9000" "$o"
same "probe run once" 1 "$(grep -c '^pr ' "$T/calls")"
: > "$T/dev/zz9001"
printf 'node %s/dev/zz9001\nmodes 800x600 1920x1080\ndepths 8 16\n' "$T" > "$T/st/pr-out"
o=$(run -n depth=8)
expect "probe's node" "node     $T/dev/zz9001" "$o"
expect "probe's modes, the first the default" "-mode 800x600 -dev $T/dev/zz9001" "$o"
expect "probe's depths" "depth 8" "$o"
o=$(run -n 1024x768)
expect "probe's modes replace the file's" "aprobe has no mode 1024x768 (it has: 800x600 1920x1080)" "$o"
o=$(run)
expect "run: the probe ran first" "pr one two
xinit $T/xsession -- " "$(cat "$T/calls")"
expect "run: the server's line has the probe's node" "-mode 800x600 -dev $T/dev/zz9001" "$(cat "$T/calls")"
printf 'node %s/dev/zz9001\nflavour mild\n' "$T" > "$T/st/pr-out"
o=$(run -n)
expect "probe's unknown line: warned" "aprobe: its probe printed \"flavour\", ignored" "$o"
expect "probe's unknown line: card still used" "card     aprobe" "$o"
printf 'node dev/zz9001\n' > "$T/st/pr-out"
o=$(run -n)
expect "probe's bad line: said in auto" "aprobe: its probe printed a bad line: node dev/zz9001" "$o"
expect "probe's bad line: auto takes the next" "card     z3660" "$o"
printf 'modes big\n' > "$T/st/pr-out"
o=$(run -n card=aprobe)
expect "probe's bad modes, named card" "aprobe: its probe printed a bad line: modes big" "$o"
expect "probe's bad line, named card: status 1" "rc=1" "$o"
printf 'node %s/dev/zz9009\n' "$T" > "$T/st/pr-out"
o=$(run -n card=aprobe)
expect "probe's node does not open" "aprobe: its node $T/dev/zz9009 does not open" "$o"
rm -f "${T:?}/st/pr-out" "${T:?}/dev/zz9001"
sed -i "s|^probe .*|probe    $T/none|" "$T/d/aprobe"
o=$(run -n)
expect "no probe: said" "aprobe: no probe $T/none" "$o"
expect "no probe: auto takes the next" "card     z3660" "$o"
sed -i "s|^probe .*|probe    pr|" "$T/d/aprobe"
o=$(run -n card=z3660)
expect "probe not a full path: said" "$T/d/aprobe:5: probe is a command by its full path" "$o"
expect "a mistake in a card not used: status 0" "rc=0" "$o"
o=$(run -n card=aprobe)
expect "a mistake in the card used: status 1" "rc=1" "$o"
rm -f "${T:?}/d/aprobe" "${T:?}/st/pr-rc"

# --- keys this base does not know: warned, never fatal
printf 'card z3660\ncolour blue\n' | conf
echo "sparkle yes" >> "$T/d/z3660"
o=$(run -n)
expect "unknown key in /etc/display: warned" "$T/display:2: unknown key \"colour\", ignored" "$o"
expect "unknown key in the card used: warned" "$T/d/z3660:11: unknown key \"sparkle\", ignored" "$o"
expect "unknown keys: -n status 0" "rc=0" "$o"
o=$(run)
expect "unknown keys: the session runs" "xinit $T/xsession -- $B/Xzz :0" "$(cat "$T/calls")"
sed -i '$d' "$T/d/z3660"
printf 'server %s/Xnat\nmodes big\n' "$B" > "$T/d/zother"
o=$(run -n)
expect "bad value in another card: said" "$T/d/zother:2: mode \"big\" is not W x H" "$o"
expect "bad value in another card: status 0" "rc=0" "$o"
o=$(run -n card=zother)
expect "bad value in the card used: status 1" "rc=1" "$o"
rm -f "${T:?}/d/zother"

# --- three cards as their packages would ship them: the Z3660 RTG and a
# ZZ9000 both behind zz9000 (unit 0, or 1 beside a Z3660; told apart by
# zorro/product on the info node), the VA2000 by its node alone
D3=$T/d3
mkdir -p "$D3"
cat > "$B/zz9k_probe" <<EOF
#!/bin/sh
# a model: the info node's text stands for GETINFO's zorro/product
info() { cat $T/dev/zz900\${1}i 2>/dev/null; }
case \$1 in
z3660) [ "\`info 0\`" = 3/1 ] ;;
zz9000)
	for u in 0 1; do
		case \`info \$u\` in
		2/3) echo "node $T/dev/zz900\$u"; exit 0 ;;
		3/4) echo "node $T/dev/zz900\$u"; echo "modes 1024x768 1920x1080"; exit 0 ;;
		esac
	done
	exit 1 ;;
*) exit 2 ;;
esac
EOF
chmod +x "$B/zz9k_probe"
printf 'node %s/dev/zz9000\nserver %s/Xzz\nmodes 1024x768\nprobe %s/zz9k_probe z3660\nargs -dev %%p\n' "$T" "$B" "$B" > "$D3/z3660"
printf 'node %s/dev/zz9000\nserver %s/Xzz\nmodes 1024x768\nprobe %s/zz9k_probe zz9000\nargs -dev %%p\n' "$T" "$B" "$B" > "$D3/zz9000"
printf 'node %s/dev/va2000\nserver %s/Xzz\nmodes 640x480\n' "$T" "$B" > "$D3/va2000"
cp "$T/d/native" "$D3/native"
rm -f "${T:?}/dev/zz9000"*
printf 'card auto\n' | conf
o=$(D_=$D3 run -n)
expect "three cards, none there: native" "card     native" "$o"
: > "$T/dev/zz9000"; echo 2/3 > "$T/dev/zz9000i"
o=$(D_=$D3 run -n)
expect "ZZ9000 alone (Zorro II): zz9000" "card     zz9000" "$o"
expect "ZZ9000 alone: unit 0, no 1920x1080" "server   $B/Xzz :0 -dev $T/dev/zz9000" "$o"
o=$(D_=$D3 run -n 1920x1080)
expect "ZZ9000 Zorro II: no 1920x1080" "zz9000 has no mode 1920x1080" "$o"
echo 3/4 > "$T/dev/zz9000i"
o=$(D_=$D3 run -n 1920x1080)
expect "ZZ9000 Zorro III: 1920x1080" "server   $B/Xzz :0 -dev $T/dev/zz9000" "$o"
o=$(D_=$D3 run -n card=z3660)
expect "ZZ9000 alone: the z3660 card refuses" "z3660: its probe $B/zz9k_probe z3660 finds no card" "$o"
echo 3/1 > "$T/dev/zz9000i"; : > "$T/dev/zz9001"; echo 3/4 > "$T/dev/zz9001i"
o=$(D_=$D3 run -n)
expect "both boards: auto takes the Z3660" "card     z3660" "$o"
o=$(D_=$D3 run -n card=zz9000)
expect "both boards: the ZZ9000 on unit 1" "server   $B/Xzz :0 -dev $T/dev/zz9001" "$o"
: > "$T/dev/va2000"
o=$(D_=$D3 run -n)
expect "a VA2000 too: first by name" "card     va2000" "$o"
rm -f "${T:?}/dev/zz900"* "${T:?}/dev/va2000"
: > "$T/dev/zz9000"

# --- no card answers at all
rm -f "${T:?}/dev/console" "${T:?}/dev/zz9000"
conf < /dev/null
o=$(run -n)
expect "nothing answers" "no display card answers" "$o"
: > "$T/dev/console"

# --- usage
o=$(run -q)
expect "usage" "usage: xstart" "$o"
expect "usage: status 2" "rc=2" "$o"

# --- the boot step: off by default, on with start xdm, off by rc.conf
printf '#!/bin/sh\necho "xstart $*" >> %s/calls\n' "$T" > "$B/xstart"
chmod +x "$B/xstart"
boot() {
	: > "$T/calls"
	env RC_SUBR="$here/../rc/rc.subr" RC_CONF="$T/rc.conf" RC_LOG="$T/rc.log" RC_BGLOG="$T/log" \
	    DISP_SUBR="$here/display.subr" DISP_CONF="$T/display" DISP_D="$T/d" XSTART="$B/xstart" \
	    $SH "$here/display" start 2>&1
	sleep 1
}
: > "$T/rc.conf"
printf 'card z3660\n' | conf
boot
same "boot: manual, nothing" "" "$(cat "$T/calls")"
printf 'card z3660\nstart xdm\n' | conf
boot
expect "boot: start xdm" "xstart -xdm" "$(cat "$T/calls")"
printf 'card z3660\nstart dtlogin\n' | conf
: > "$T/rc.conf"
boot
expect "boot: start dtlogin" "xstart -dtlogin" "$(cat "$T/calls")"
echo "display=no" > "$T/rc.conf"
boot
same "boot: rc.conf display=no" "" "$(cat "$T/calls")"

echo "test-display: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
