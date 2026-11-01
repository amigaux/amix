#!/bin/sh
#
# smoke.sh -- run libzz9k's acceptance program, ON THE BOX.
#
#     sh smoke.sh [/opt/amix/bin/zz9k-test]
#
# Written for the 1992 pre-POSIX Bourne shell: no $(...), no $(( )), no
# `local`, no printf(1), no `grep -q`.  zz9k-test lists the boards behind
# /dev/zz9ksvcN and checks an inflate of each format in software and, where a
# board offers it, on the board; a machine without a board passes with
# software only.

BIN=$1
if [ -z "$BIN" ]; then
	BIN=/opt/amix/bin/zz9k-test
fi

echo "== libzz9k on-box smoke =="
echo "-- binary: $BIN"

if [ ! -x "$BIN" ]; then
	echo "FAIL $BIN is not executable"
	exit 1
fi

"$BIN"
rc=$?
if [ $rc -ne 0 ]; then
	echo "libzz9k smoke: FAIL (zz9k-test exit $rc)"
	exit 1
fi
echo "libzz9k smoke: PASS"
exit 0
