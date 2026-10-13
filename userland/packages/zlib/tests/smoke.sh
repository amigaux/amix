#!/bin/sh
#
# smoke.sh -- run the packaged zlib acceptance test, ON THE BOX.
#
#     sh smoke.sh [/opt/amix/bin/zlib-test]
#
# Written for the 1992 pre-POSIX Bourne shell (PORTING.md 3.6): no $(...), no
# $(( )), no `local`, no `printf(1)`, no `grep -q`.
#
# The real work is in zlib-test.c (shipped as /opt/amix/bin/zlib-test): crc32
# and adler32 canaries against algorithm-defined constants, a multi-megabyte
# deflate -> inflate round trip, and inflate of a stream a DIFFERENT machine's
# zlib produced.  This wrapper just runs it and reports the verdict.

BIN=$1
if [ -z "$BIN" ]; then
	BIN=/opt/amix/bin/zlib-test
fi

echo "== zlib on-box smoke =="
echo "-- binary: $BIN"

if [ ! -x "$BIN" ]; then
	echo "FAIL $BIN is not executable"
	exit 1
fi

"$BIN"
rc=$?
if [ $rc -ne 0 ]; then
	echo "zlib smoke: FAIL (zlib-test exit $rc)"
	exit 1
fi
echo "zlib smoke: PASS"
exit 0
