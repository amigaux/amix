#!/bin/sh
#
# smoke.sh -- prove less runs and pages a file, ON THE BOX, non-interactively.
#
#     sh smoke.sh [/opt/amix/bin/less]
#
# Run from the directory holding sample.txt.  Written for the 1992 pre-POSIX
# Bourne shell (PORTING.md 3.6): backticks, `expr`, no `grep -q`.
#
# Interactive paging (search, backward scroll, resize, clean exit) has to be
# eyeballed over a real tty -- that is the reader's manual check.  What this
# script proves automatically is the half a leaked terminal mode or a broken
# regcmp/termcap link would still fail: that less starts, reports its version and
# its regex engine, and reproduces a file's bytes exactly when it pages to a pipe
# (less to a non-tty behaves like cat), i.e. read + output path are sound.

LESS=$1
if [ -z "$LESS" ]; then
	LESS=/opt/amix/bin/less
fi

fails=0

echo "== less on-box smoke =="
echo "-- less: $LESS"

if [ ! -x "$LESS" ]; then
	echo "FAIL $LESS is not executable"
	exit 1
fi

echo "-- less --version"
"$LESS" --version | sed -n 1p
if [ $? -ne 0 ]; then
	echo "FAIL less --version returned non-zero"; fails=`expr $fails + 1`
else
	echo "ok   less --version"
fi

if [ ! -f sample.txt ]; then
	echo "FAIL fixture sample.txt missing (run from the fixture directory)"
	exit 1
fi

# Page to a pipe (stdout is not a tty) -- less then reproduces the file.  -E
# quits at EOF, -F quits if it fits one screen; neither should leave any tty
# state behind when output is not a terminal.
echo "-- less -EF sample.txt | (compare bytes)"
"$LESS" -EF sample.txt > less-out.txt 2>/dev/null
if [ $? -ne 0 ]; then
	echo "FAIL less -EF returned non-zero"; fails=`expr $fails + 1`
fi
cmp less-out.txt sample.txt
if [ $? -ne 0 ]; then
	echo "FAIL less output does not byte-match the input"
	echo "---- got ----"; cat less-out.txt
	fails=`expr $fails + 1`
else
	echo "ok   less reproduced the file byte-exact through the pager"
fi

rm -f less-out.txt

echo ""
if [ $fails -eq 0 ]; then
	echo "less smoke: PASS  (interactive search/scroll/resize is the reader's manual check)"
	exit 0
fi
echo "less smoke: $fails FAILED"
exit 1
