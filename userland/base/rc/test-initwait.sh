#!/bin/sh
# test-initwait.sh -- host tests of initwait against a model init and who -r
# and a sleep that only counts.
#
#   sh userland/base/rc/test-initwait.sh [shell]     (default sh)
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-initwait.XXXXXX")
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

mkdir -p "$T/bin"
# init: each request is a line of $T/calls; it moves the level ($T/level)
# on the request numbered in $T/acts ("0": never), or exits with $T/fail
cat > "$T/init" <<EOF
#!/bin/sh
echo "\$*" >> "$T/calls"
[ -s "$T/fail" ] && exit \`cat "$T/fail"\`
n=\`wc -l < "$T/calls"\`
[ "\$n" -eq "\`cat "$T/acts"\`" ] && echo "\$1" > "$T/level"
exit 0
EOF
# who -r as the stock one prints it; nothing when $T/level is empty
cat > "$T/who" <<EOF
#!/bin/sh
[ "\$1" = -r ] || exit 2
l=\`cat "$T/level"\`
[ -n "\$l" ] && echo "   .       run-level \$l  Nov 14 14:02    \$l    0    S"
exit 0
EOF
# sleep: counted, never slept
printf '#!/bin/sh\necho "$*" >> "%s/sleeps"\n' "$T" > "$T/bin/sleep"
chmod +x "$T/init" "$T/who" "$T/bin/sleep"

# case <level now> <request on which init acts, 0 never> [init's exit]
case_() {
	echo "$1" > "$T/level"
	echo "$2" > "$T/acts"
	rm -f "$T/fail"
	[ -z "${3:-}" ] || echo "$3" > "$T/fail"
	rm -f "$T/calls" "$T/sleeps"
	touch "$T/calls" "$T/sleeps"
}
run() { # run <args>: initwait's output; its status in $st
	out=$(env INITWAIT_INIT="$T/init" INITWAIT_WHO="$T/who" PATH="$T/bin:$PATH" \
	    $SH "$here/initwait" "$@" 2>&1)
	st=$?
}
calls() { wc -l < "$T/calls" | tr -d ' '; }
sleeps() { wc -l < "$T/sleeps" | tr -d ' '; }

# init acts at once: one request, silent, 0, one look
case_ 2 1
run 0
same "at once: status" 0 "$st"
same "at once: silent" "" "$out"
same "at once: one request" 1 "$(calls)"
same "at once: the request" 0 "$(cat "$T/calls")"
same "at once: one look" 1 "$(sleeps)"

# init acts only on the second request: one line, 0
case_ 2 2
run 0
same "second: status" 0 "$st"
same "second: two requests" 2 "$(calls)"
same "second: 30 looks, then one" 31 "$(sleeps)"
expect "second: says it asks again" "init has not acted on the request for run level 0 in 30 seconds: asking again" "$out"
same "second: one line" 1 "$(echo "$out" | wc -l | tr -d ' ')"

# init never acts: two requests, two lines, 1, no loop
case_ 2 0
run 6
same "never: status" 1 "$st"
same "never: two requests" 2 "$(calls)"
same "never: 60 looks" 60 "$(sleeps)"
same "never: two lines" 2 "$(echo "$out" | wc -l | tr -d ' ')"
expect "never: the last line" "init has still not acted on the request for run level 6" "$out"

# init fails: its status, nothing watched
case_ 2 1 3
run 0
same "init fails: its status" 3 "$st"
same "init fails: no look" 0 "$(sleeps)"
same "init fails: silent" "" "$out"

# the level cannot be read: as before, one request, nothing watched
case_ "" 0
run 0
same "no level: status" 0 "$st"
same "no level: one request" 1 "$(calls)"
same "no level: no look" 0 "$(sleeps)"

# already at the level asked: nothing watched
case_ 1 0
run 1
same "same level: status" 0 "$st"
same "same level: no look" 0 "$(sleeps)"
case_ S 0
run s
same "s when at S: no look" 0 "$(sleeps)"

# single user asked, acts at once
case_ 2 1
run s
same "s: status" 0 "$st"
same "s: the request as given" s "$(cat "$T/calls")"

# a shorter watch
case_ 2 0
out=$(env INITWAIT_INIT="$T/init" INITWAIT_WHO="$T/who" INITWAIT_SECS=3 PATH="$T/bin:$PATH" \
    $SH "$here/initwait" 0 2>&1)
same "INITWAIT_SECS=3: 6 looks" 6 "$(sleeps)"
expect "INITWAIT_SECS=3: said" "in 3 seconds" "$out"

# usage
for a in "" 7 q "0 1" -i0
do
	case_ 2 1
	run $a
	same "usage [$a]: status" 1 "$st"
	same "usage [$a]: no request" 0 "$(calls)"
done

echo "test-initwait: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
