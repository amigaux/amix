#!/bin/sh
# MIT licence, see LICENSE at the top of the repository.
#
# Build the host gencat, write test.msg in both modes, compare the
# bytes with tests/expect/ (or print them when no reference is there)
# and decode every output back, checking each message.
#
#   sh tests/run.sh            (CC=... to pick the compiler)

set -eu

here=$(cd "$(dirname "$0")" && pwd)
src=$here/..
cc=${CC:-cc}
fail=0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

# the build must be warning-free
if ! $cc -O2 -Wall -Wextra -o "$tmp/gencat" "$src/gencat.c" \
    2>"$tmp/cc.log" || [ -s "$tmp/cc.log" ]; then
	cat "$tmp/cc.log"
	echo "FAIL build"
	exit 1
fi
echo "ok   build"

cd "$tmp"
cp "$here/test.msg" .
./gencat -m test.cat.m-mode test.msg
./gencat test.cat test.msg

for f in test.cat.m-mode test.cat test.cat.m; do
	if [ -f "$here/expect/$f" ]; then
		if cmp -s "$f" "$here/expect/$f"; then
			echo "ok   bytes $f"
		else
			echo "FAIL bytes $f"
			fail=1
		fi
	else
		echo "--   no reference for $f; its bytes:"
		od -A x -t x1z "$f"
	fi
done

# every message of test.msg, as catgets would return it
cat >want <<'EOF'
1 1 "Default set message one"
1 2 "Default set message two"
1 3 "Default set message three"
2 1 "One\tTab escape"
2 2 "Newline\nescape"
2 3 "Vertical\vtab backspace\b cr\r ff\f end"
2 4 "Backslash \\ escaped"
2 5 "Five comes first in the file"
2 6 "Octal \007 0 A four-digit \r hex A"
2 7 "Unknown q escape drops the backslash"
2 8 "This line continues on the next line"
2 9 ""
2 12 "Gap before me"
5 1 "Tab separator"
5 2 "Two spaces after the number"
5 3 "Quoted with trailing spaces   "
5 4 ""
5 5 "Quoted "inner" quotes"
5 6 "Unquoted after quote is set"
5 7 "Quote char "off" again"
12 1 "Last set"
EOF

check() {	# check <label> <catfile> <want-file> <header>
	./gencat --dump "$2" >got.all
	if [ "$(head -n 1 got.all)" != "$4" ]; then
		echo "FAIL $1: header $(head -n 1 got.all), want $4"
		fail=1
	fi
	tail -n +2 got.all >got
	if cmp -s got "$3"; then
		echo "ok   $1"
	else
		echo "FAIL $1"
		diff "$3" got || true
		fail=1
	fi
}

check "decode -m" test.cat.m-mode want "format malloc sets 4"
check "decode default" test.cat want "format mkmsgs sets 12 strings 23"

# merge a second source over the existing catalogues
printf '$set 2\n1 One replaced\n12\n$set 3\n2 New in set three\n' >merge.msg
printf '$delset 5\n' >>merge.msg
cp test.cat.m-mode merged.m-mode
cp test.cat merged
cp test.cat.m merged.m
./gencat -m merged.m-mode merge.msg
./gencat merged merge.msg
cat >want.merge <<'EOF'
1 1 "Default set message one"
1 2 "Default set message two"
1 3 "Default set message three"
2 1 "One replaced"
2 2 "Newline\nescape"
2 3 "Vertical\vtab backspace\b cr\r ff\f end"
2 4 "Backslash \\ escaped"
2 5 "Five comes first in the file"
2 6 "Octal \007 0 A four-digit \r hex A"
2 7 "Unknown q escape drops the backslash"
2 8 "This line continues on the next line"
2 9 ""
3 2 "New in set three"
12 1 "Last set"
EOF
check "merge -m" merged.m-mode want.merge "format malloc sets 4"
check "merge default" merged want.merge "format mkmsgs sets 12 strings 15"

if command -v sha256sum >/dev/null 2>&1; then
	sha256sum test.cat.m-mode test.cat test.cat.m
fi

if [ $fail -ne 0 ]; then
	echo "FAILED"
	exit 1
fi
echo "all ok"
