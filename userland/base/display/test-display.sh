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
refuse() { case "$3" in *"$2"*) bad "$1: unwanted [$2] in [$3]" ;; *) ok ;; esac; }

B=$T/bin
mkdir -p "$B" "$T/d" "$T/home" "$T/dev" "$T/log"
for p in Xzz Xnat xinit xdm tool; do
	printf '#!/bin/sh\necho "%s $*" >> %s/calls\n' $p "$T" > "$B/$p"
done
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
	env DISP_SUBR="$here/display.subr" DISP_CONF="$T/display" DISP_D="$T/d" HOME="$T/home" \
	    XINITS="$B/xinit" XDMS="$B/xdm" XSESSION="$T/xsession" MONSWCTL="${MCTL:-$B/monswctl-no}" \
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
rm -f "$T/dev/zz9000"
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
rm -f "$T/home/.xsession" "$T/home/.xinitrc"

# --- a run: xinit with the session and the server's line
conf <<'EOF'
card z3660
mode 640x480
EOF
o=$(run)
same "run: xinit" "xinit $T/xsession -- $B/Xzz :0 -mode 640x480 -w 640 -h 480 -bpp 16 -n 0" "$(cat "$T/calls")"

# --- a card's environment: exported for xinit, in the line for xdm
printf '#!/bin/sh\necho "xinit SG=$SCREEN_GROUP $*" >> %s/calls\n' "$T" > "$B/xinit"
printf 'card native\n' | conf
o=$(run :10)
same "env: exported for xinit" "xinit SG=10 $T/xsession -- $B/Xnat :10" "$(cat "$T/calls")"
o=$(run -xdm :10)
same "env: in xdm's line" "xdm -server :10 local /usr/bin/env SCREEN_GROUP=10 $B/Xnat :10" "$(cat "$T/calls")"
printf '#!/bin/sh\necho "xinit $*" >> %s/calls\n' "$T" > "$B/xinit"

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

# --- mistakes: said by -n, which then exits 1
conf <<'EOF'
card    z3660
mode    big
start   sometimes
colour  blue
EOF
o=$(run -n)
expect "bad mode said" "$T/display:2: mode is W x H" "$o"
expect "bad start said" "$T/display:3: start is manual or xdm" "$o"
expect "unknown key said" "$T/display:4: unknown key \"colour\"" "$o"
echo "colour blue" >> "$T/d/native"
o=$(run -n card=z3660 mode=640x480)
expect "a card file's mistake said" "$T/d/native:7: unknown key \"colour\"" "$o"
expect "mistakes: -n status 1" "rc=1" "$o"
sed -i '$d' "$T/d/native"

# --- no card answers at all
rm -f "$T/dev/console" "$T/dev/zz9000"
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
echo "display=no" > "$T/rc.conf"
boot
same "boot: rc.conf display=no" "" "$(cat "$T/calls")"

echo "test-display: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
