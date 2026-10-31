#!/bin/sh
# rctest.sh -- host test of the boot step random/rc/randseed under sh, with the device and
# the seed file in a scratch directory, stand-ins for dd, date and ps on PATH, and a stand-in
# rc.subr (rc_log as rc.subr(1M) gives it).  Run by hosttest.sh.
#
#   usage: sh random/test/rctest.sh
set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
S=$top/random/rc/randseed
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
n=0
fail() { echo "rctest: FAIL: $*" >&2; exit 1; }
ok() { n=$((n + 1)); }

sh -n "$S" || fail "randseed does not parse"
head -1 "$S" | grep -q '^#!/bin/sh$' || fail "randseed is not a /bin/sh script"
! grep -qE '\$\(|\[\[|function |local |\(\(' "$S" || fail "randseed uses a non-Bourne construct"
! grep -v '^#' "$S" | grep -qE 'mknod|/usr/bin/| /bin/' || fail "randseed makes a node or names a tool's path"
ok

mkdir -p "$tmp/bin" "$tmp/etc"
cat > "$tmp/bin/dd" <<'F'
#!/bin/sh
echo "dd $*" >> "$T/calls"
[ -n "$DD_FAIL" ] && exit 1
for a; do case $a in of=*) o=${a#of=} ;; esac; done
printf '%0512d' 0 | tr 0 n > "$o"
F
printf '#!/bin/sh\necho DATE\n' > "$tmp/bin/date"
printf '#!/bin/sh\necho PS "$@"\n' > "$tmp/bin/ps"
echo 'rc_log() { _s=$1; shift; echo "$_s: $*" >> "$RC_LOG"; }' > "$tmp/rc.subr"
chmod +x "$tmp/bin/dd" "$tmp/bin/date" "$tmp/bin/ps"
export T="$tmp" RC_LOG="$tmp/rc.log" RC_SUBR="$tmp/rc.subr" \
	RANDSEED_FILE="$tmp/etc/random-seed" RANDSEED_DEV="$tmp/urandom"
F="$RANDSEED_FILE" D="$RANDSEED_DEV"
run() { # run <arg>: console -> $out, device -> $dev, log -> $log, dd calls -> $calls
	: > "$tmp/calls"; : > "$RC_LOG"
	set +e
	PATH="$tmp/bin:$PATH" sh "$S" "$1" > "$tmp/out" 2>&1; rc=$?
	set -e
	out=$(cat "$tmp/out"); log=$(cat "$RC_LOG"); calls=$(cat "$tmp/calls")
	dev=$(cat "$D" 2>/dev/null || true)
}
mode() { ls -l "$1" | cut -c1-10; }

# a boot with a saved seed: the seed, then date and ps, go into the device; a new seed at once
echo OLDSEED > "$F"; rm -f "$D"
run start
[ $rc = 0 ] && [ -z "$out" ] || fail "start: rc=$rc out='$out'"
[ "$dev" = "OLDSEED
DATE
PS -ef" ] || fail "start: the device got '$dev'"
[ "$calls" = "dd if=$D of=$F.new bs=512 count=1" ] || fail "start: dd calls '$calls'"
[ "$(wc -c < "$F")" = 512 ] && [ ! -e "$F.new" ] || fail "start: the seed is not the new 512 bytes"
[ "$(mode "$F")" = "-rw-------" ] || fail "start: the seed's mode is $(mode "$F")"
[ "$log" = "randseed: seed from $F written to $D
randseed: seed saved in $F" ] || fail "start: log '$log'"
ok
# the first boot, no seed yet
rm -f "$F" "$D"; run start
[ $rc = 0 ] && [ "$dev" = "DATE
PS -ef" ] && [ "$(wc -c < "$F")" = 512 ] || fail "first boot: rc=$rc dev='$dev'"
[ "$log" = "randseed: seed saved in $F" ] || fail "first boot: log '$log'"
ok
# shutdown: only the save
echo OLDSEED > "$F"; rm -f "$D"; run stop
[ $rc = 0 ] && [ -z "$dev" ] && [ "$(wc -c < "$F")" = 512 ] && [ -z "$out" ] || fail "stop: rc=$rc dev='$dev' out='$out'"
ok
# no module: the device cannot be written; one line, the old seed kept, exit 0
echo OLDSEED > "$F"; RANDSEED_DEV="$tmp/no-such-dir/urandom" run start
[ $rc = 0 ] || fail "no device: rc=$rc"
[ "$out" = "randseed: cannot write $tmp/no-such-dir/urandom (no random module?); $F kept as it was" ] || fail "no device: out '$out'"
[ "$log" = "$out" ] && [ "$(cat "$F")" = OLDSEED ] && [ -z "$calls" ] || fail "no device: log '$log' seed '$(cat "$F")'"
rm -f "$F"; RANDSEED_DEV="$tmp/no-such-dir/urandom" run start
[ $rc = 0 ] && [ "$out" = "randseed: cannot write $tmp/no-such-dir/urandom (no random module?); no seed saved" ] && [ ! -e "$F" ] ||
	fail "no device, no seed: rc=$rc out '$out'"
ok
# the device cannot be read: the old seed kept, no partial file left
echo OLDSEED > "$F"; DD_FAIL=1 run stop
[ $rc = 0 ] && [ "$out" = "randseed: cannot read $D; $F kept as it was" ] || fail "dd fails: rc=$rc out '$out'"
[ "$(cat "$F")" = OLDSEED ] && [ ! -e "$F.new" ] || fail "dd fails: the seed changed or $F.new is left"
ok
# without rc.subr: the log lines on the console
echo OLDSEED > "$F"; rm -f "$D"; RC_SUBR="$tmp/none" run start
[ $rc = 0 ] && [ "$out" = "randseed: seed from $F written to $D
randseed: seed saved in $F" ] && [ -z "$log" ] || fail "no rc.subr: out '$out' log '$log'"
ok
# another argument: usage, exit 1, nothing done
echo OLDSEED > "$F"; run restart
[ $rc = 1 ] && echo "$out" | grep -q usage && [ -z "$calls" ] && [ "$(cat "$F")" = OLDSEED ] || fail "restart: rc=$rc"
ok
echo "rctest: randseed ok ($n groups)"
