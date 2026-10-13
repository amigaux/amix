#!/bin/sh
#
# smoke.sh -- prove GNU grep's over-stock features work, ON THE BOX.
#
#     sh smoke.sh [/opt/amix/bin/grep]
#
# Run from the directory holding tree/.  Written for the 1992 pre-POSIX Bourne
# shell (PORTING.md 3.6): backticks, `expr`, no `grep -q` (we redirect and test
# $? -- the very tool under test).
#
# The point is the features stock SVR4 grep lacks -- -r, -o, --color, -E -- so
# each check exercises one and inspects the OUTPUT, not the exit status.

GREP=$1
if [ -z "$GREP" ]; then
	GREP=/opt/amix/bin/grep
fi

fails=0

echo "== GNU grep on-box smoke =="
echo "-- grep: $GREP"

if [ ! -x "$GREP" ]; then
	echo "FAIL $GREP is not executable"
	exit 1
fi

echo "-- grep --version"
"$GREP" --version | sed -n 1p
if [ $? -ne 0 ]; then
	echo "FAIL grep --version returned non-zero"; fails=`expr $fails + 1`
fi

if [ ! -d tree ]; then
	echo "FAIL fixture tree/ missing (run from the fixture directory)"
	exit 1
fi

# 1. Recursive -r with line numbers: ERROR appears in BOTH files.
echo "-- grep -rn ERROR tree  (expect 2 files)"
"$GREP" -rn ERROR tree > out.rn 2>/dev/null
n=`"$GREP" -c . out.rn`
hits=`"$GREP" -l ERROR tree/a.txt tree/sub/b.txt | "$GREP" -c .`
# count matched lines instead (portable): expect 2 lines, one per file
matched=`awk 'END{print NR}' out.rn`
if [ "$matched" = "2" ]; then
	echo "ok   -r found ERROR in 2 files"
else
	echo "FAIL -r produced $matched match lines, expected 2"; cat out.rn; fails=`expr $fails + 1`
fi
# the recursive output must carry file:line: prefixes
echo "grep -rn output:"; sed 's/^/     /' out.rn

# 2. -o prints only the matched text, not the whole line.
echo "-- grep -o 'gamma' tree/a.txt  (expect exactly 'gamma')"
"$GREP" -o gamma tree/a.txt > out.o 2>/dev/null
only=`cat out.o`
if [ "$only" = "gamma" ]; then
	echo "ok   -o printed only the match"
else
	echo "FAIL -o printed '$only', expected 'gamma'"; fails=`expr $fails + 1`
fi

# 3. --color=always wraps the match in an ANSI escape.
echo "-- grep --color=always color tree/a.txt  (expect an ESC sequence)"
"$GREP" --color=always color tree/a.txt > out.color 2>/dev/null
# look for the ESC[ (0x1b 0x5b) introducer; use od since we cannot type ESC
od -c out.color | "$GREP" '033' > /dev/null 2>&1
if [ $? -eq 0 ]; then
	echo "ok   --color emitted an ANSI escape"
else
	echo "FAIL --color produced no escape sequence"; od -c out.color | sed -n 1p; fails=`expr $fails + 1`
fi

# 4. -E extended regex: alternation.
echo "-- grep -E 'beta|epsilon' tree/a.txt  (expect 2 lines)"
ecount=`"$GREP" -E 'beta|epsilon' tree/a.txt | awk 'END{print NR}'`
if [ "$ecount" = "2" ]; then
	echo "ok   -E alternation matched 2 lines"
else
	echo "FAIL -E matched $ecount lines, expected 2"; fails=`expr $fails + 1`
fi

# 5. Context and max-count: -A/-B/-C/-m.  Their numeric arguments are parsed by
#    xstrtoumax -> gnulib strtoull, the path D4 (patches/03-04) moved off the
#    64-bit MULU.L the 68LC060 lacks.  On the published grep-2.5.1a these are the
#    options expected to die on the LC060; the 030 must simply get them right.
#    Fixture: tree/a.txt is 4 lines, ERROR on line 3.
ctx() {
	# ctx <label> <expected-line-count> <grep args...>
	_l=$1; _want=$2; shift; shift
	_got=`"$GREP" "$@" tree/a.txt | awk 'END{print NR}'`
	if [ "$_got" = "$_want" ]; then
		echo "ok   $_l printed $_got lines"
	else
		echo "FAIL $_l printed $_got lines, expected $_want"; fails=`expr $fails + 1`
	fi
}
echo "-- context/max-count: -A 3, -B 2, -C 1, -m 1 on tree/a.txt"
ctx "-A 3 alpha" 4 -A 3 alpha
ctx "-B 2 ERROR" 3 -B 2 ERROR
ctx "-C 1 color" 3 -C 1 color
ctx "-m 1 a"     1 -m 1 a
# and -A's last line must be the file's last line, not just the right count
last=`"$GREP" -A 3 alpha tree/a.txt | sed -n '$p'`
if [ "$last" = "delta epsilon" ]; then
	echo "ok   -A 3 ended on line 4"
else
	echo "FAIL -A 3 ended on '$last', expected 'delta epsilon'"; fails=`expr $fails + 1`
fi

rm -f out.rn out.o out.color

echo ""
if [ $fails -eq 0 ]; then
	echo "grep smoke: PASS"
	exit 0
fi
echo "grep smoke: $fails FAILED"
exit 1
