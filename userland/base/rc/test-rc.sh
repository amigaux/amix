#!/bin/sh
# test-rc.sh -- host tests of rc.subr against a scratch rc.conf, a fake
# kbootset and a fake mknod.
#
#   sh userland/base/rc/test-rc.sh [shell]     (default sh)
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-rc.XXXXXX")
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

mkdir -p "$T/bin" "$T/dev"
cat > "$T/rc.conf" <<'EOF'
# /etc/rc.conf
syslogd=no
syslogd=yes
xdm=no		# graphical login off
cron=maybe
  indented=yes
# commented=yes
ifup_timeout=60
ifup_log="/var/adm/ifup.log"
ifup_quoted='a b'
ifup_empty=
ifup_hash=a#b
EOF
# kbootset: "major <module>" as dlm will give it; z3660eth says 51, ramdisk b 20,
# monsw disagrees with what the test passes, anything else is unknown
cat > "$T/bin/kbootset" <<'EOF'
#!/bin/sh
[ "$1" = major ] || exit 2
case "$2" in
z3660eth) echo "c 51" ;;
monsw) echo "c 52" ;;
ramdisk) echo "b 20" ;;
*) echo "kbootset: no module $2" >&2; exit 1 ;;
esac
EOF
# kbootset of today: no "major" subcommand yet
printf '#!/bin/sh\necho "usage: kbootset ..." >&2\nexit 2\n' > "$T/bin/oldkbootset"
# mknod: record the call, make a plain file (a real node needs root)
printf '#!/bin/sh\necho "$*" >> "%s/mknod.log"\n: > "$1"\n' "$T" > "$T/bin/mknod"
chmod +x "$T/bin/"*

# run <kbootset> <shell commands>: rc.subr sourced, the result on stdout
run() {
	k=$1
	shift
	env RC_CONF="$T/rc.conf" RC_LOG="$T/rc.log" RC_KBOOTSET="$k" PATH="$T/bin:$PATH" \
	    $SH -c ". '$here/rc.subr'; $*" 2>&1
}
R() { run "$T/bin/kbootset" "$@"; }

# rc_enabled: the last line wins, the default when absent or bad
same "on, last line wins" 0 "$(R 'rc_enabled syslogd no; echo $?')"
same "off" 1 "$(R 'rc_enabled xdm yes; echo $?')"
same "trailing comment" 1 "$(R 'rc_enabled xdm yes; echo $?')"
same "absent, default yes" 0 "$(R 'rc_enabled nfs yes; echo $?')"
same "absent, default no" 1 "$(R 'rc_enabled nfs no; echo $?')"
same "absent, no default" 1 "$(R 'rc_enabled nfs; echo $?')"
same "indented line" 0 "$(R 'rc_enabled indented no; echo $?')"
same "commented line ignored" 1 "$(R 'rc_enabled commented no; echo $?')"
same "bad value, default yes" 0 "$(R 'rc_enabled cron yes; echo $?')"
same "bad value, default no" 1 "$(R 'rc_enabled cron no; echo $?')"
expect "bad value logged" "cron=maybe is neither yes nor no; using no" "$(cat "$T/rc.log")"
same "prefix is not a match" 1 "$(R 'rc_enabled sys no; echo $?')"
same "no rc.conf" 0 "$(env RC_CONF="$T/none" RC_LOG="$T/rc.log" $SH -c ". '$here/rc.subr'; rc_enabled syslogd yes; echo \$?")"

# rc_conf
same "value" 60 "$(R 'rc_conf ifup timeout 30')"
same "default" 30 "$(R 'rc_conf ifup bound 30')"
same "double quotes" /var/adm/ifup.log "$(R 'rc_conf ifup log x')"
same "single quotes" "a b" "$(R 'rc_conf ifup quoted x')"
same "empty value is a value" "[]" "$(R 'echo "[`rc_conf ifup empty x`]"')"
same "hash without a blank" "a#b" "$(R 'rc_conf ifup hash x')"
same "service name alone is not a key" "d" "$(R 'rc_conf syslogd "" d')"

# rc_log
: > "$T/rc.log"
R 'rc_log inet "lo0 up"' > /dev/null
expect "log line" " inet: lo0 up" "$(cat "$T/rc.log")"
grep '^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] inet: ' "$T/rc.log" > /dev/null && ok || bad "log time stamp"

# rc_bg: returns at once; a slow command is stopped at the bound (TERM, and
# KILL after the grace when TERM is held); output in a file per service
: > "$T/rc.log"
mkdir -p "$T/run"
B="RC_BGLOG=$T/rclog RC_GRACE=1 RC_RUN=$T/run"
t0=$(date +%s)
R "$B; rc_bg 2 slow sh -c 'echo started; sleep 30; echo never'" > /dev/null
t1=$(date +%s)
[ $((t1 - t0)) -le 1 ] && ok || bad "rc_bg returned after $((t1 - t0)) s"
R "$B; rc_bg 5 quick sh -c 'echo quick out; exit 3'" > /dev/null
R "$B; rc_bg 2 stubborn sh -c 'trap \"\" 15; echo held; sleep 30'" > /dev/null
R "$B; rc_bg 5 args echo 'two  words' three" > /dev/null
sleep 5
l=$(cat "$T/rc.log")
expect "start logged" "quick: started, bound 5 s: sh -c echo quick out; exit 3" "$l"
expect "status logged" "quick: finished, status 3" "$l"
expect "output in its own file" "quick out" "$(cat "$T/rclog/quick")"
grep -x "quick out" "$T/rc.log" > /dev/null && bad "command output in rc.log" || ok
expect "slow output" "started" "$(cat "$T/rclog/slow")"
expect "slow stopped" "slow: still running after 2 s; stopped" "$l"
expect "slow ends, killed" "slow: finished, status 143" "$l"
case "$(cat "$T/rclog/slow")" in *never*) bad "slow command ran past its bound" ;; *) ok ;; esac
expect "TERM held: KILL" "stubborn: finished, status 137" "$l"
case "$l" in *"quick: still running"*) bad "quick command's timer fired" ;; *) ok ;; esac
same "arguments kept" "two  words three" "$(cat "$T/rclog/args")"
same "no pid file left" "" "$(ls "$T/run")"

# rc_mknod (the fake mknod makes a plain file, so every call makes one)
: > "$T/rc.log"; : > "$T/mknod.log"
R "rc_mknod $T/dev/zen0 c 51 0 z3660eth 0600" > /dev/null
same "made with the given major" "$T/dev/zen0 c 51 0" "$(cat "$T/mknod.log")"
expect "made logged" "made $T/dev/zen0 c 51 0" "$(cat "$T/rc.log")"
: > "$T/mknod.log"
o=$(R "rc_mknod $T/dev/monsw c 50 0 monsw")
same "registry wins on a mismatch" "$T/dev/monsw c 52 0" "$(cat "$T/mknod.log")"
expect "mismatch on the console" "packaging error" "$o"
expect "mismatch logged" "given major 50, but the registry gives monsw c 52" "$(cat "$T/rc.log")"
: > "$T/mknod.log"
R "rc_mknod $T/dev/kinfo c 53 0 kinfo 0444" > /dev/null
same "unknown module: the given major" "$T/dev/kinfo c 53 0" "$(cat "$T/mknod.log")"
: > "$T/mknod.log"
run "$T/bin/oldkbootset" "rc_mknod $T/dev/monsw2 c 50 0 monsw" > /dev/null
same "kbootset without major: the given major" "$T/dev/monsw2 c 50 0" "$(cat "$T/mknod.log")"
: > "$T/mknod.log"
run "$T/none" "rc_mknod $T/dev/zz c 49 0 z3660rtg" > /dev/null
same "no kbootset: the given major" "$T/dev/zz c 49 0" "$(cat "$T/mknod.log")"
: > "$T/mknod.log"
R "rc_mknod $T/dev/ram0 b 99 0 ramdisk" > /dev/null
same "block major from the registry" "$T/dev/ram0 b 20 0" "$(cat "$T/mknod.log")"

# no major given ("-"): the registry's, quietly; none there, no node
: > "$T/rc.log"; : > "$T/mknod.log"
o=$(R "rc_mknod $T/dev/zen1 c - 1 z3660eth 0600")
same "no major: the registry's" "$T/dev/zen1 c 51 1" "$(cat "$T/mknod.log")"
same "no major: no packaging error" "" "$o$(grep 'packaging' "$T/rc.log")"
: > "$T/mknod.log"
o=$(R "rc_mknod $T/dev/aen0 c - 0 aen; echo \$?")
same "no major, unknown module: not made" "" "$(cat "$T/mknod.log")"
same "no major, unknown module: status 1" "1" "$o"
expect "no major, unknown module: logged" "cannot make $T/dev/aen0: the registry gives aen no major" "$(cat "$T/rc.log")"

# _rc_node reads ls -l; a fake ls shows a node already right, one wrong
cat > "$T/bin/ls" <<'EOF'
#!/bin/sh
case "$2" in
*right) echo "crw-r--r--   1 root     sys       51,  0 Oct 30 12:00 $2" ;;
*wide) echo "crw-r--r--   1 root     sys       51,255 Oct 30 12:00 $2" ;;
*) echo "crw-r--r--   1 root     sys       50,  0 Oct 30 12:00 $2" ;;
esac
EOF
chmod +x "$T/bin/ls"
mkfifo "$T/dev/right" "$T/dev/wide" "$T/dev/wrong" 2>/dev/null
# a FIFO is not a device to [ -c ]; parse the ls line directly instead
same "ls parse" "c 51 0" "$(R "ls -l $T/dev/right | awk '{ t = substr(\$1, 1, 1); if (\$5 ~ /,\$/) { ma = substr(\$5, 1, length(\$5) - 1); mi = \$6 } else { split(\$5, a, \",\"); ma = a[1]; mi = a[2] } print t, ma, mi }'")"
if [ -c /dev/null ]; then
	same "a real node" "c $(stat -c %t /dev/null | sed 's/^/0x/' | xargs printf %d) $(stat -c %T /dev/null | sed 's/^/0x/' | xargs printf %d)" \
	    "$(env PATH=/usr/bin:/bin $SH -c ". '$here/rc.subr'; _rc_node /dev/null")"
fi

echo "test-rc: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
