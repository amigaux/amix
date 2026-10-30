#!/bin/sh
#
# smoke.sh -- prove GNU patch actually applies a hunk, ON THE BOX.
#
#     sh smoke.sh [/usr/local/bin/patch]
#
# Run from the directory holding orig.txt, change.diff and expect.txt.  Exits 0
# only if every step passed.
#
# ---------------------------------------------------------------------------
# WRITTEN FOR THE 1992 PRE-POSIX BOURNE SHELL.  /bin/sh on Amix predates POSIX,
# so this script uses none of:
#
#     $(...)      -- backticks only
#     $(( ))      -- expr only
#     local       -- no such keyword
#     arrays      -- no such thing
#     printf(1)   -- not installed
#     grep -q     -- redirect to /dev/null and test $?
#
# and it avoids two semantics traps that produce WRONG RESULTS rather than
# errors: `while read ... done < FILE` runs in a subshell (so a counter
# incremented inside reverts at `done` -- state is kept in files here instead),
# and `mkdir -p` is not idempotent (rc=2 on an existing leaf, hence the
# [ -d ] guard).
#
# The test itself is deliberately end-to-end rather than clever: apply a real
# unified diff produced by a modern host diff, byte-compare the result against
# the host's own expected output, then reverse the patch and byte-compare back
# to the original.  Forward-only would pass for a patch that mangles the file
# consistently; the round trip would not.

PATCHBIN=$1
if [ -z "$PATCHBIN" ]; then
	PATCHBIN=/usr/local/bin/patch
fi

fails=0

echo "== GNU patch on-box smoke =="
echo "-- binary: $PATCHBIN"

if [ ! -x "$PATCHBIN" ]; then
	echo "FAIL $PATCHBIN is not executable"
	exit 1
fi

echo "-- patch --version"
"$PATCHBIN" --version
if [ $? -ne 0 ]; then
	echo "FAIL patch --version returned non-zero"
	fails=`expr $fails + 1`
else
	echo "ok   patch --version"
fi

for f in orig.txt change.diff expect.txt; do
	if [ ! -f $f ]; then
		echo "FAIL fixture $f missing (run from the fixture directory)"
		exit 1
	fi
done

# Work on a copy so the fixture stays pristine and the test is re-runnable.
rm -f work.txt
cp orig.txt work.txt

echo "-- applying change.diff to work.txt"
"$PATCHBIN" work.txt < change.diff
if [ $? -ne 0 ]; then
	echo "FAIL patch exited non-zero applying the hunk"
	fails=`expr $fails + 1`
else
	echo "ok   patch applied the hunk"
fi

cmp work.txt expect.txt
if [ $? -ne 0 ]; then
	echo "FAIL patched file does not byte-match the host's expected output"
	echo "---- got ----"
	cat work.txt
	echo "---- want ----"
	cat expect.txt
	fails=`expr $fails + 1`
else
	echo "ok   patched file is byte-identical to the host's expected output"
fi

echo "-- reversing the patch"
"$PATCHBIN" -R work.txt < change.diff
if [ $? -ne 0 ]; then
	echo "FAIL patch -R exited non-zero"
	fails=`expr $fails + 1`
else
	echo "ok   patch -R applied"
fi

cmp work.txt orig.txt
if [ $? -ne 0 ]; then
	echo "FAIL reversed file does not match the original"
	fails=`expr $fails + 1`
else
	echo "ok   round trip returns the original bytes"
fi

# patch leaves work.txt.orig behind on a reverse; tidy up so a re-run is clean.
rm -f work.txt work.txt.orig work.txt.rej

echo ""
if [ $fails -eq 0 ]; then
	echo "patch smoke: PASS"
	exit 0
fi
echo "patch smoke: $fails FAILED"
exit 1
