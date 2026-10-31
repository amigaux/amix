#!/bin/bash
# tooltest.sh -- host test of monswctl (monsw/tool) and of the boot step monsw/rc/monsw,
# without a box.
#
# 1. monswctl's argument handling and call sequence: the shipped monsw/tool/monswctl.c
#    compiled by the host cc against testdouble.c (open/ioctl/close stand-ins that log
#    every call and fail on request; make -C monsw/tool host).  Every usage refusal exits 2
#    before any open; every accepted value reaches SETCFG as the number it was; get/status
#    print what GETCFG returned; the kernel's refusals (EBUSY, EPERM, EINVAL, ENOENT,
#    ENXIO) each map to their own line and exit 1; `rtg cmd` issues RTG, runs cmd while the
#    device is open, then NATIVE and close, and returns the command's status.
# 2. rc/monsw under sh with a fake monswctl and a stand-in rc.subr (rc_log as
#    rc.subr(1M) gives it): the value from /etc/display, else /etc/monsw with its log
#    line, else no call (the card's seed); a refused value or a missing tool is one
#    console line and exit 0; without rc.subr the log lines go to the console.
#
#   usage: bash monsw/test/tooltest.sh        (HOSTCC overrides cc)
set -uo pipefail
TOP="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CHECKS=0
fail() { echo "tooltest: FAIL: $*" >&2; exit 1; }
ok()   { CHECKS=$((CHECKS + 1)); printf '  ok  %s\n' "$*"; }

# ---------------------------------------------------------------- 1. monswctl --
echo "--- 1. monswctl against the test double (host build) ---"
make -s -C "$TOP/monsw/tool" host >"$TMP/build.log" 2>&1 \
  || { cat "$TMP/build.log" >&2; fail "host --testdouble build failed"; }
grep -q "warning" "$TMP/build.log" && { cat "$TMP/build.log" >&2; fail "host build has warnings"; }
ok "host build against testdouble.c, no warnings"
M="$TOP/monsw/build/tool-host/monswctl"
LOG="$TMP/calls.log"
export MONSW_TD_LOG="$LOG"
run() { # run <expected rc> args... ; stdout -> $OUT, stderr -> $ERR, calls -> $LOG
  local want="$1"; shift
  : > "$LOG"
  "$M" "$@" >"$TMP/out" 2>"$TMP/err"; local rc=$?
  OUT="$(cat "$TMP/out")"; ERR="$(cat "$TMP/err")"; CALLS="$(cat "$LOG")"
  [ "$rc" = "$want" ] || fail "monswctl $* exited $rc, wanted $want (stderr: $ERR)"
}
nocall() { [ -z "$CALLS" ] || fail "monswctl $* touched the device: $CALLS"; }

# usage refusals: exit 2, no open
for args in "" "bogus" "get extra" "status x" "native x" "set" "set 1 2" "set 4" "set 8" "set 64" "set 65" "set 52" "set abc" "set 1x" "set -2" "set ''" "-d" "-d /dev/x"; do
  # shellcheck disable=SC2086
  eval run 2 $args
  eval nocall $args
done
ok "18 usage refusals exit 2 without opening the device"
run 0 -h; nocall; [ -n "$ERR" ] || fail "-h printed no usage"
ok "-h prints usage, exit 0"

# accepted values reach SETCFG unchanged
for v in 0 1 2 3 16 17 18 19 32 33 34 35 48 49 50 51 -1; do
  run 0 set "$v"
  [ "$CALLS" = "open /dev/monsw
ioctl SETCFG $v
close" ] || fail "set $v: calls were: $CALLS"
done
ok "17 valid values (every subset of 1|2|16|32, and -1) reach SETCFG as given"
run 0 set 0x22; grep -q "SETCFG 34" <<<"$CALLS" || fail "0x22 did not become 34"
run 0 set 022; grep -q "SETCFG 18" <<<"$CALLS" || fail "octal 022 did not become 18 (strtol base 0)"
ok "0x22 -> 34, 022 -> 18 (C-style number forms)"
run 0 -d /tmp/x/monsw set 34; grep -q "^open /tmp/x/monsw" <<<"$CALLS" || fail "-d not honoured: $CALLS"
run 0 -d/tmp/y/monsw set 34; grep -q "^open /tmp/y/monsw" <<<"$CALLS" || fail "-dDEV not honoured: $CALLS"
ok "-d dev and -ddev select the node"

# get / status print what GETCFG returned
MONSW_TD_INFO="34,2,0,0,1" run 0 get
[ "$OUT" = "config=34 (SEL low=RTG)
source=2 (set)
state=0 (native)
holder=0
ncards=1" ] || fail "get output: $OUT"
[ "$CALLS" = "open /dev/monsw
ioctl GETCFG
close" ] || fail "get calls: $CALLS"
ok "get prints the five monsw_info fields (34 = SEL low=RTG, source set, native)"
MONSW_TD_INFO="19,1,1,1,2" run 0 status
[ "$OUT" = "monsw: value 19 (CTS low=RTG, SEL high=RTG) from seed; state rtg; holder yes; 2 cards" ] || fail "status output: $OUT"
ok "status: one line, both lines decoded, seed, rtg, holder, plural"
MONSW_TD_INFO="0,0,-1,0,0" run 0 status
[ "$OUT" = "monsw: value 0 (no line) from none; state none; holder no; 0 cards" ] || fail "status(0) output: $OUT"
MONSW_TD_INFO="34,3,0,0,1" run 0 status
grep -q "from patched" <<<"$OUT" || fail "status(patched): $OUT"
ok "status: value 0 / state none / patched source decoded"

# the kernel's refusals: exit 1, their own line
MONSW_TD_IOCTL_ERRNO=16 run 1 set 34; grep -q "patched into the kernel" <<<"$ERR" || fail "EBUSY text: $ERR"
MONSW_TD_IOCTL_ERRNO=1  run 1 set 34; grep -q "root only" <<<"$ERR" || fail "EPERM text: $ERR"
MONSW_TD_IOCTL_ERRNO=22 run 1 set 34; grep -q "does not take 34" <<<"$ERR" || fail "EINVAL text: $ERR"
MONSW_TD_IOCTL_ERRNO=5  run 1 set 34; grep -q "SETCFG: " <<<"$ERR" || fail "EIO text: $ERR"
ok "SETCFG refusals EBUSY/EPERM/EINVAL/other -> their own line, exit 1"
MONSW_TD_OPEN_ERRNO=2 run 1 get; grep -q "mknod /dev/monsw c 52 0" <<<"$ERR" || fail "ENOENT text: $ERR"
[ "$CALLS" = "open /dev/monsw" ] || fail "ENOENT: calls after a failed open: $CALLS"
MONSW_TD_OPEN_ERRNO=6 run 1 get; grep -q "kernel without monsw" <<<"$ERR" || fail "ENXIO text: $ERR"
MONSW_TD_OPEN_ERRNO=19 run 1 get; grep -q "kernel without monsw" <<<"$ERR" || fail "ENODEV text: $ERR"
MONSW_TD_OPEN_ERRNO=13 run 1 get; grep -q "Permission denied" <<<"$ERR" || fail "EACCES text: $ERR"
ok "open refusals ENOENT (mknod hint) / ENXIO+ENODEV (no driver) / other -> exit 1, nothing after the open"
MONSW_TD_IOCTL_ERRNO=6 run 1 get; grep -q "GETCFG: " <<<"$ERR" || fail "GETCFG error text: $ERR"
MONSW_TD_IOCTL_ERRNO=6 run 1 native; grep -q "NATIVE: " <<<"$ERR" || fail "NATIVE error text: $ERR"
ok "GETCFG / NATIVE failures reported, exit 1"

# native / rtg
run 0 native
[ "$CALLS" = "open /dev/monsw
ioctl NATIVE 0
close" ] || fail "native calls: $CALLS"
ok "native: NATIVE then close"
run 0 rtg sh -c 'echo child-ran; test -n "$MONSW_TD_LOG" && echo child-sees-open-device'
[ "$OUT" = "child-ran
child-sees-open-device" ] || fail "rtg cmd stdout: $OUT"
[ "$CALLS" = "open /dev/monsw
ioctl RTG 0
ioctl NATIVE 0
close" ] || fail "rtg cmd calls: $CALLS"
ok "rtg cmd: RTG, the command runs, NATIVE, close"
run 3 rtg sh -c 'exit 3'
grep -q "ioctl NATIVE 0" <<<"$CALLS" || fail "rtg after a failing command did not go native: $CALLS"
ok "rtg cmd returns the command's exit status (3) and still goes native"
run 127 rtg /nonexistent/no-such-tool
grep -q "ioctl NATIVE 0" <<<"$CALLS" || fail "rtg after exec failure did not go native: $CALLS"
ok "rtg with an unrunnable command: 127, native"
: > "$LOG"; "$M" rtg </dev/null >"$TMP/out" 2>"$TMP/err"; rc=$?
[ "$rc" = 0 ] || fail "rtg (hold) exited $rc"
grep -q "RTG until end of input" "$TMP/err" || fail "rtg hold banner: $(cat "$TMP/err")"
[ "$(cat "$LOG")" = "open /dev/monsw
ioctl RTG 0
ioctl NATIVE 0
close" ] || fail "rtg hold calls: $(cat "$LOG")"
ok "rtg with no command holds until EOF, then native"
MONSW_TD_IOCTL_ERRNO=6 run 1 rtg true
[ "$CALLS" = "open /dev/monsw
ioctl RTG 0
close" ] || fail "rtg refused: the command must not run: $CALLS"
ok "rtg refused by the kernel: the command does not run, exit 1"
unset MONSW_TD_LOG

# ---------------------------------------------------------------- 2. rc/monsw --
echo "--- 2. rc/monsw under sh with a fake monswctl and rc.subr ---"
S="$TOP/monsw/rc/monsw"
sh -n "$S" || fail "rc/monsw does not parse"
grep -q '^#!/bin/sh' "$S" || fail "rc/monsw is not a /bin/sh script"
grep -qE '\$\(|\[\[|function |local |mknod' "$S" && fail "rc/monsw uses a non-Bourne construct or makes a node"
ok "rc/monsw parses, stays inside the Bourne shell and makes no node (devnodes does)"
FAKE="$TMP/fake"; mkdir -p "$FAKE"
cat > "$FAKE/monswctl" <<'F'
#!/bin/sh
echo "monswctl $*" >> "$FAKE_LOG"
[ -n "$FAKE_RC" ] && { echo "monswctl: SETCFG refused: the value is patched into the kernel" >&2; exit "$FAKE_RC"; }
exit 0
F
cat > "$FAKE/rc.subr" <<'F'
rc_log() { _s=$1; shift; echo "$_s: $*" >> "$RC_LOG"; }
F
chmod +x "$FAKE/monswctl"
export FAKE_LOG="$TMP/fake.log" FAKE_RC="" RC_LOG="$TMP/rc.log" TMPDIR="$TMP/tmp"
mkdir -p "$TMPDIR"
export MONSW_DISPLAY="$TMP/display" MONSW_CONF="$TMP/monsw" MONSW_CTL="$FAKE/monswctl" \
  MONSW_DEV="$TMP/dev-monsw" RC_SUBR="$FAKE/rc.subr"
D="$MONSW_DISPLAY" C="$MONSW_CONF"
rcrun() { # rcrun <arg>: console -> $RCOUT, monswctl calls -> $FCALLS, boot log -> $RLOG
  : > "$FAKE_LOG"; : > "$RC_LOG"
  sh "$S" "$1" >"$TMP/rcout" 2>&1; RC=$?
  RCOUT="$(cat "$TMP/rcout")"; FCALLS="$(cat "$FAKE_LOG")"; RLOG="$(cat "$RC_LOG")"
}
setfiles() { # setfiles <display content|-> <monsw content|->
  rm -f "$D" "$C"
  [ "$1" = - ] || printf '%b' "$1" > "$D"
  [ "$2" = - ] || printf '%b' "$2" > "$C"
}

setfiles - -; rcrun start
[ "$RC" = 0 ] && [ -z "$RCOUT" ] && [ -z "$FCALLS" ] || fail "no files: rc=$RC out='$RCOUT' calls='$FCALLS'"
[ "$RLOG" = "monsw: no value in $D or $C; the card's own value applies" ] || fail "no files: log '$RLOG'"
ok "no /etc/display, no /etc/monsw: no call, silent, one log line (the card's seed applies)"
setfiles 'card auto\nmode 1920x1080\n' -; rcrun start
[ -z "$FCALLS" ] && grep -q "card's own value applies" <<<"$RLOG" || fail "display without monsw: calls='$FCALLS' log='$RLOG'"
ok "/etc/display without monsw and no /etc/monsw: no call"
setfiles 'card auto\nmonsw    34\n' -; rcrun start
[ "$RC" = 0 ] && [ -z "$RCOUT" ] || fail "display 34: rc=$RC out='$RCOUT'"
[ "$FCALLS" = "monswctl -d $MONSW_DEV set 34" ] || fail "display 34: calls '$FCALLS'"
[ "$RLOG" = "monsw: value 34 from $D set" ] || fail "display 34: log '$RLOG'"
ok "/etc/display monsw 34: one 'set 34', silent, logged"
setfiles '# monsw 2\nmonsw 18   # SEL\nmode 640x480\nmonsw 34\n' -; rcrun start
[ "$FCALLS" = "monswctl -d $MONSW_DEV set 34" ] || fail "last line wins: calls '$FCALLS'"
setfiles 'monsw 18   # SEL, high\n' -; rcrun start
[ "$FCALLS" = "monswctl -d $MONSW_DEV set 18" ] || fail "trailing comment: calls '$FCALLS'"
ok "/etc/display as xstart reads it: comments stripped, the last monsw line wins"
setfiles 'monsw 34\n' '18\n'; rcrun start
[ "$FCALLS" = "monswctl -d $MONSW_DEV set 34" ] || fail "display over monsw: calls '$FCALLS'"
grep -q "older file" <<<"$RLOG" && fail "display over monsw: the older file was named: '$RLOG'"
ok "/etc/display wins over /etc/monsw, and the older file is not mentioned"
setfiles 'card auto\n' '  34  \n1\n'; rcrun start
[ "$RC" = 0 ] && [ -z "$RCOUT" ] || fail "older file: rc=$RC out='$RCOUT'"
[ "$FCALLS" = "monswctl -d $MONSW_DEV set 34" ] || fail "older file: calls '$FCALLS'"
[ "$RLOG" = "monsw: value 34 from $C, the older file; set monsw in $D instead
monsw: value 34 from $C set" ] || fail "older file: log '$RLOG'"
ok "no monsw in /etc/display: /etc/monsw's first line, trimmed; the log names the older file"
setfiles - '34\n'; rcrun start
[ "$FCALLS" = "monswctl -d $MONSW_DEV set 34" ] && grep -q "older file" <<<"$RLOG" || fail "no display: calls '$FCALLS' log '$RLOG'"
ok "no /etc/display at all: /etc/monsw, logged as the older file"
setfiles 'monsw\n' '34\n'; rcrun start
[ "$FCALLS" = "monswctl -d $MONSW_DEV set 34" ] || fail "empty display value: calls '$FCALLS'"
ok "a monsw line with no value counts as absent"
setfiles 'monsw SEL\n' -; rcrun start
[ "$RC" = 0 ] && [ -z "$FCALLS" ] || fail "display not digits: rc=$RC calls '$FCALLS'"
[ "$RCOUT" = "monsw: $D monsw 'SEL' is not a bit sum; ignored" ] || fail "display not digits: out '$RCOUT'"
grep -q "is not a bit sum; ignored" <<<"$RLOG" && grep -q "card's own value applies" <<<"$RLOG" || fail "display not digits: log '$RLOG'"
setfiles 'monsw -1\n' '34\n'; rcrun start
[ "$FCALLS" = "monswctl -d $MONSW_DEV set 34" ] && grep -q "not a bit sum" <<<"$RCOUT" || fail "display -1: calls '$FCALLS' out '$RCOUT'"
ok "an /etc/display value that is not digits: one console line, ignored, then /etc/monsw or the seed"
setfiles - '\n'; rcrun start
[ -z "$FCALLS" ] && grep -q "card's own value applies" <<<"$RLOG" || fail "empty /etc/monsw: calls '$FCALLS' log '$RLOG'"
ok "an empty /etc/monsw counts as absent"
setfiles 'monsw 34\n' -; FAKE_RC=1 rcrun start
[ "$RC" = 0 ] || fail "refused: rc=$RC"
[ "$RCOUT" = "monsw: $D value '34' not applied: monswctl: SETCFG refused: the value is patched into the kernel" ] || fail "refused: out '$RCOUT'"
[ "$RLOG" = "monsw: $D value '34' not applied: monswctl: SETCFG refused: the value is patched into the kernel" ] || fail "refused: log '$RLOG'"
ok "a refused value: one console line with the tool's reason, the same in the log, exit 0"
FAKE_RC=2 rcrun start; [ "$RC" = 0 ] && [ "$(wc -l <<<"$RCOUT")" = 1 ] || fail "usage refusal: rc=$RC out='$RCOUT'"
ok "a value the tool refuses (exit 2): one line, exit 0"
MONSW_CTL="$TMP/no-such-monswctl" rcrun start
[ "$RC" = 0 ] && [ "$RCOUT" = "monsw: $D value 34 not applied: $TMP/no-such-monswctl is missing" ] || fail "missing tool: rc=$RC out='$RCOUT'"
[ -z "$FCALLS" ] || fail "missing tool, but a call: $FCALLS"
ok "missing monswctl: one line, exit 0"
RC_SUBR="$TMP/no-rc.subr" rcrun start
[ "$RC" = 0 ] && [ "$RCOUT" = "monsw: value 34 from $D set" ] && [ -z "$RLOG" ] || fail "no rc.subr: rc=$RC out='$RCOUT' log='$RLOG'"
setfiles - '34\n'; RC_SUBR="$TMP/no-rc.subr" FAKE_RC=1 rcrun start
[ "$RC" = 0 ] && [ "$(grep -c '^monsw: ' <<<"$RCOUT")" = 2 ] || fail "no rc.subr, refused: out='$RCOUT'"
ok "without rc.subr the log lines go to the console, each once"
rcrun stop; [ "$RC" = 0 ] && [ -z "$RCOUT" ] && [ -z "$FCALLS" ] && [ -z "$RLOG" ] || fail "stop: rc=$RC out='$RCOUT'"
rcrun bogus; [ "$RC" = 1 ] && grep -q usage <<<"$RCOUT" && [ -z "$FCALLS" ] || fail "bogus: rc=$RC out='$RCOUT'"
ok "stop: nothing; another argument: usage, exit 1"
[ -z "$(ls "$TMPDIR")" ] || fail "rc/monsw left $(ls "$TMPDIR") behind"
ok "no temporary file left behind"

echo "tooltest: ok ($CHECKS checks)"
