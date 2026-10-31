#!/bin/sh
#
# smoke.sh -- prngd 0.9.29 acceptance, ON THE BOX, as root.
#
#     sh tests/smoke.sh [prefix]          (default /opt/amix)
#
# The daemon on an explicit socket, spoken to with upstream's prngd-ctl in
# the EGD protocol (pid, get, read, readb), its seed file across a restart,
# --kill, the shipped init script on /var/run/egd-pool, and the documented
# caveat: no socket argument.  1992 Bourne shell: backticks, expr, no grep -q,
# no $(...), no `!'.  Result lines start with "RES "; the last is
# "RES smoke PASS" or "RES smoke FAIL <n>".

X=${1:-/opt/amix}
D=$X/sbin/prngd
C=$X/bin/prngd-ctl
fails=0
ok()  { echo "RES ok   $*"; }
bad() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }
eq()  { if [ -z "$3" ]; then bad "$1: nothing to compare (got '$2')"
	elif [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got '$2' want '$3'"; fi; }
# up <socket>: wait up to 120 s for the daemon to answer on it
up() { i=0; while [ $i -lt 60 ]; do $C $1 pid > /dev/null 2>&1 && return 0; sleep 2; i=`expr $i + 1`; done; return 1; }
# seeded <socket>: wait up to 120 s for entropy; leaves the bit count in $bits
seeded() { i=0; bits=0; while [ $i -lt 60 ]; do bits=`$C $1 get 2>/dev/null | tr -d ' '`; [ "${bits:-0}" -gt 0 ] && return 0; sleep 2; i=`expr $i + 1`; done; return 1; }

rm -rf prsmoke; mkdir prsmoke; cd prsmoke || exit 1
T=`pwd`

# --- 1. the binary, and the caveat ----------------------------------------------
$D -v > v.out 2>&1
egrep '0\.9\.29' v.out > /dev/null && ok "prngd -v: `sed -n 1p v.out`" || bad "prngd -v: `sed -n 1p v.out`"
( $D > ns.out 2>&1 ); rc=$?
[ -f core ] && { cored=yes; rm -f core; } || cored=no
ok "no socket argument: rc $rc, core $cored (README: always pass one)"

# --- 2. the daemon on an explicit socket -------------------------------------------
$D -s $T/seed $T/egd > start.out 2>&1; rc=$?
up $T/egd && ok "daemon answers on its socket (rc $rc)" || bad "daemon did not come up (rc $rc): `cat start.out`"
pid=`$C $T/egd pid 2>/dev/null | tr -d ' '`
ps -e | awk '{print $1, $NF}' | egrep "^$pid prngd\$" > /dev/null && ok "prngd-ctl pid = the running prngd ($pid)" || bad "pid '$pid' is not a prngd: `ps -e | grep prngd`"
seeded $T/egd && ok "get: $bits bits of entropy after ~`expr $i \* 2` s" || bad "get: '$bits'"
$C $T/egd read 32 > r1; $C $T/egd read 32 > r2
eq "read 32 bytes" "`wc -c < r1 | tr -d ' '`" 32
cmp r1 r2 > /dev/null 2>&1 && bad "two reads gave the same bytes" || ok "two reads differ"
# the 1992 od: -b, octal bytes after an offset column
n=`cat r1 r2 | od -b | awk '{ for (i = 2; i <= NF; i++) print $i }' | sort -u | wc -l | tr -d ' '`
[ "$n" -gt 32 ] && ok "64 bytes read hold $n distinct byte values" || bad "only $n distinct byte values in 64 bytes"
$C $T/egd readb 16 > r3; eq "readb 16 (blocking)" "`wc -c < r3 | tr -d ' '`" 16

# --- 3. --kill, the seed file, a restart on it ---------------------------------------
$D --kill $T/egd > k.out 2>&1; rc=$?
sleep 2
if [ -n "$pid" ] && [ $rc -eq 0 ] && kill -0 $pid 2>/dev/null; then bad "--kill (rc $rc): $pid still runs"
elif [ -n "$pid" ] && [ $rc -eq 0 ]; then ok "--kill stops it (rc $rc)"; else bad "--kill rc=$rc pid='$pid': `cat k.out`"; fi
[ -s $T/seed ] && ok "seed file written at exit (`wc -c < $T/seed | tr -d ' '` bytes)" || bad "no seed file"
$D -s $T/seed $T/egd > start2.out 2>&1
up $T/egd && b2=`$C $T/egd get 2>/dev/null` || b2=0
[ "${b2:-0}" -gt 0 ] && ok "restart on the seed: $b2 bits at once" || bad "restart on the seed: '$b2'"
$D --kill $T/egd > /dev/null 2>&1; sleep 2

# --- 4. the shipped init script, /var/run/egd-pool --------------------------------------
$X/etc/init.d/prngd start > rc.out 2>&1; rc=$?
up /var/run/egd-pool && ok "init.d/prngd start: /var/run/egd-pool answers (rc $rc)" || bad "init.d start rc=$rc: `cat rc.out`"
p2=`$C /var/run/egd-pool pid 2>/dev/null | tr -d ' '`
seeded /var/run/egd-pool || bad "/var/run/egd-pool never had entropy"
$C /var/run/egd-pool read 16 > r4; eq "read 16 bytes from /var/run/egd-pool" "`wc -c < r4 | tr -d ' '`" 16
$X/etc/init.d/prngd stop > rc2.out 2>&1; rc=$?
sleep 2
if [ -n "$p2" ] && [ $rc -eq 0 ] && kill -0 $p2 2>/dev/null; then bad "init.d stop (rc $rc): $p2 still runs"
elif [ -n "$p2" ] && [ $rc -eq 0 ]; then ok "init.d/prngd stop (rc $rc)"; else bad "init.d stop rc=$rc pid='$p2': `cat rc2.out`"; fi
# runtime state, not payload: pkgrm must find the package's directory empty
rm -f $X/etc/prngd/prngd-seed

cd ..
if [ $fails -eq 0 ]; then echo "RES smoke PASS"; else echo "RES smoke FAIL $fails"; fi
[ $fails -eq 0 ]
