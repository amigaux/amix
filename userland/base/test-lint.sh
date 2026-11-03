#!/bin/sh
# test-lint.sh -- checks over the files base ships to the box: the source of
# each put and cp in pkg/*/build.sh, less the man pages and documents.
#
#   sh userland/base/test-lint.sh [awk]   (default awk)
#
# mkdir -p: the stock mkdir -p exits 2, "File exists", on a directory that is
# already there, so a script that runs twice breaks. Each mkdir -p stands
# behind [ -d <dir> ] || for the same <dir>, one directory a call. A line
# that is meant to differ carries the marker "# lint: mkdir-p".
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
AWK=${1:-awk}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-lint.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { [ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"; }
expect() { case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac; }

# shipped: one source path a line, relative to userland/base
shipped() {
	cat "$here"/pkg/*/build.sh | $AWK '
	$1 == "put" && NF >= 4 { s = $3; d = $4 }
	$1 == "cp" && NF >= 3 { s = $2; d = $3 }
	$1 == "put" || $1 == "cp" {
		gsub(/"/, "", s)
		gsub(/"/, "", d)
		if (d !~ /\/opt\/amix\/(man|doc)\//)
			print s
	}' | sort -u
}

# lint_mkdir <file>: "<file>:<line>: <text>" for each mkdir -p out of rule
lint_mkdir() {
	$AWK -v f="$1" '
	/^[ \t]*#/ { next }
	index($0, "# lint: mkdir-p") { next }
	{
		line = $0
		pre = ""
		while ((i = index(line, "mkdir -p")) > 0) {
			pre = pre substr(line, 1, i - 1)
			rest = substr(line, i + 8)
			line = rest
			sub(/^[ \t]+/, "", rest)
			arg = rest
			sub(/[ \t;|&)}].*$/, "", arg)
			after = substr(rest, length(arg) + 1)
			sub(/^[ \t]+/, "", after)
			g = "[ -d " arg " ] || "
			guarded = arg != "" && length(pre) >= length(g) && \
			    substr(pre, length(pre) - length(g) + 1) == g
			one = after == "" || after ~ /^([0-9]?>|\|\||&&|;|\)|\})/
			if (!guarded || !one) {
				print f ":" NR ": " $0
				next
			}
			pre = pre "mkdir -p"
		}
	}' "$1"
}

# --- the rule itself, on lines made for it
cat > "$T/sample" <<'EOF'
[ -d "$d" ] || mkdir -p "$d"
[ -d "$RC_BGLOG" ] || mkdir -p "$RC_BGLOG" 2>/dev/null
[ -d "$d" ] || mkdir -p "$d" || exit 1
	# a comment: mkdir -p "$x" is fine here
mkdir -p "$a"
[ -d "$a" ] || mkdir -p "$b"
[ -d "$a" ] || mkdir -p "$a" "$b"
mkdir -p "$TMPD"   # lint: mkdir-p (made fresh by the line before)
x=1; mkdir -p /var/x; y=2
EOF
o=$(lint_mkdir "$T/sample")
same "rule: the flagged lines" "$T/sample:5: mkdir -p \"\$a\"
$T/sample:6: [ -d \"\$a\" ] || mkdir -p \"\$b\"
$T/sample:7: [ -d \"\$a\" ] || mkdir -p \"\$a\" \"\$b\"
$T/sample:9: x=1; mkdir -p /var/x; y=2" "$o"

# --- the shipped set: the box's scripts are in it, the man pages are not
s=$(shipped)
for f in net/ifup net/ifdown net/ifup.subr net/inetinit net/dhcpc-hook rc/rc.subr \
    rc/devnodes rc/swap syslog/syslogd display/xstart display/display.subr man/man.sh; do
	expect "shipped: $f" "$f" "$s"
done
case "$s" in *.1m*|*LICENSE*) bad "shipped: a man page or licence in [$s]" ;; *) ok ;; esac

# --- every shipped file
n=0
for f in $s
do
	[ -f "$here/$f" ] || continue
	n=$((n + 1))
	o=$(lint_mkdir "$here/$f")
	same "mkdir -p behind [ -d ]: $f" "" "$o"
done
[ "$n" -ge 12 ] && ok || bad "only $n shipped files found"

echo "test-lint: $pass passed, $fail failed ($n files, $AWK)"
[ "$fail" -eq 0 ]
