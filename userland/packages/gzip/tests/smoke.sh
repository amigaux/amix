#!/bin/sh
#
# smoke.sh -- prove GNU gzip round-trips and reads a foreign .gz, ON THE BOX.
#
#     sh smoke.sh [/opt/amix/bin]
#
# Run from the directory holding sample.txt and sample.txt.gz.  Written for the
# 1992 pre-POSIX Bourne shell (PORTING.md 3.6): backticks not $(...), `expr` not
# $(( )), no `local`, no `printf(1)`, no `grep -q`.
#
# Two checks that a consistent-but-wrong build could not both pass:
#   1. Round trip -- gzip a file here, gunzip it back, byte-compare to the
#      original.  Catches a deflate/inflate that disagrees with itself.
#   2. Foreign stream -- gunzip a .gz produced by a DIFFERENT machine's gzip
#      (sample.txt.gz, made on the host) and byte-compare to sample.txt.  This
#      is the endianness / bit-packing canary the round trip would hide.

BINDIR=$1
if [ -z "$BINDIR" ]; then
	BINDIR=/opt/amix/bin
fi
GZIP=$BINDIR/gzip
GUNZIP=$BINDIR/gunzip

fails=0

echo "== gzip on-box smoke =="
echo "-- gzip:   $GZIP"

if [ ! -x "$GZIP" ]; then
	echo "FAIL $GZIP is not executable"
	exit 1
fi

echo "-- gzip --version"
"$GZIP" --version
if [ $? -ne 0 ]; then
	echo "FAIL gzip --version returned non-zero"
	fails=`expr $fails + 1`
else
	echo "ok   gzip --version"
fi

for f in sample.txt sample.txt.gz; do
	if [ ! -f $f ]; then
		echo "FAIL fixture $f missing (run from the fixture directory)"
		exit 1
	fi
done

# 1. Round trip: compress a copy, decompress, compare.
rm -f work.txt work.txt.gz
cp sample.txt work.txt
echo "-- round trip: gzip work.txt then gunzip work.txt.gz"
"$GZIP" work.txt
if [ $? -ne 0 ] || [ ! -f work.txt.gz ]; then
	echo "FAIL gzip did not produce work.txt.gz"
	fails=`expr $fails + 1`
else
	"$GUNZIP" work.txt.gz
	if [ $? -ne 0 ]; then
		echo "FAIL gunzip returned non-zero"
		fails=`expr $fails + 1`
	fi
	cmp work.txt sample.txt
	if [ $? -ne 0 ]; then
		echo "FAIL round trip does not byte-match the original"
		fails=`expr $fails + 1`
	else
		echo "ok   round trip returns the original bytes"
	fi
fi

# 2. Foreign stream: decompress the host-produced .gz, compare to plaintext.
rm -f host-out.txt
echo "-- foreign stream: gunzip -c sample.txt.gz (host-produced)"
"$GZIP" -dc sample.txt.gz > host-out.txt
if [ $? -ne 0 ]; then
	echo "FAIL gunzip -c of the host stream returned non-zero"
	fails=`expr $fails + 1`
fi
cmp host-out.txt sample.txt
if [ $? -ne 0 ]; then
	echo "FAIL host .gz did not decompress to sample.txt"
	fails=`expr $fails + 1`
else
	echo "ok   host-produced .gz decompresses byte-exact"
fi

rm -f work.txt work.txt.gz host-out.txt

echo ""
if [ $fails -eq 0 ]; then
	echo "gzip smoke: PASS"
	exit 0
fi
echo "gzip smoke: $fails FAILED"
exit 1
