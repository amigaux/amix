#!/bin/sh
#
# smoke.sh -- prove GNU make's over-stock features work, ON THE BOX.
#
#     sh smoke.sh [/opt/amix/bin/make]
#
# Run from the directory holding proj/ (a small multi-directory project).  The
# C build uses the ON-BOX compiler when one is installed (`cc`, the stock SGS
# compiler in cdev), and is SKIPPED otherwise -- make itself is what is under
# test, so every other check uses plain shell recipes.  Written for the 1992
# pre-POSIX Bourne shell (PORTING.md 3.6): backticks, `expr`, no `grep -q`.
#
# Each check inspects OUTPUT or FILES, never only an exit status.

MAKE=$1
if [ -z "$MAKE" ]; then
	MAKE=/opt/amix/bin/make
fi

fails=0
bad() { echo "FAIL $*"; fails=`expr $fails + 1`; }

echo "== GNU make on-box smoke =="
echo "-- make: $MAKE"
if [ ! -x "$MAKE" ]; then
	echo "FAIL $MAKE is not executable"
	exit 1
fi
if [ ! -d proj ]; then
	echo "FAIL proj/ missing (run from the fixture directory)"
	exit 1
fi

echo "-- make --version"
"$MAKE" --version | sed -n 1p

cd proj
"$MAKE" clean > /dev/null 2>&1

# 1. Pattern rules + VPATH + $(shell) + $(eval) + order-only, one run.
echo "-- make all  (pattern rules, VPATH, \$(shell), \$(eval), order-only)"
"$MAKE" all > ../m.out 2>&1
echo "     rc=$?"
sed 's/^/     /' ../m.out
[ "`cat out/a.up`" = "ALPHA" ] && echo "ok   pattern rule %.up: %.txt found src/a.txt via VPATH" \
	|| bad "out/a.up wrong: '`cat out/a.up 2>/dev/null`'"
[ "`cat out/b.up`" = "BRAVO" ] && echo "ok   second pattern-rule target via VPATH" \
	|| bad "out/b.up wrong"
grep 'shell-says-amix' out/info.txt > /dev/null 2>&1 && echo "ok   \$(shell) expanded" \
	|| bad "\$(shell) did not expand"
grep 'eval-made-rule' out/info.txt > /dev/null 2>&1 && echo "ok   \$(eval) generated a rule that ran" \
	|| bad "\$(eval) rule did not run"
[ -d out ] && echo "ok   order-only prerequisite created out/" || bad "out/ not created"

# 2. Up to date: nothing is rebuilt the second time (timestamps work).
"$MAKE" all > ../m2.out 2>&1
# (no \| alternation: the stock grep that may run this has none)
if grep 'Nothing to be done' ../m2.out > /dev/null 2>&1 || grep 'is up to date' ../m2.out > /dev/null 2>&1; then
	echo "ok   second run rebuilt nothing"
else
	bad "second run rebuilt"; sed 's/^/     /' ../m2.out
fi

# 3. Recursive make with -j2: the jobserver (SA_RESTART seed) and SIGCHLD.
echo "-- make -j2 sub  (recursive, jobserver)"
"$MAKE" -j2 sub > ../m3.out 2>&1
echo "     rc=$?"
sed 's/^/     /' ../m3.out
[ -f sub/done1 ] && [ -f sub/done2 ] && echo "ok   -j2 recursive make built both targets" \
	|| bad "-j2 recursive make did not finish"
if grep 'jobserver unavailable' ../m3.out > /dev/null 2>&1 || grep 'Interrupted system call' ../m3.out > /dev/null 2>&1; then
	bad "jobserver/EINTR trouble under -j2"
else
	echo "ok   no jobserver warning, no EINTR"
fi

# 4. make -l: no load average on Amix -- must warn, not misbehave.
"$MAKE" -l 2 all > ../m4.out 2>&1
echo "     make -l 2: `sed -n 1p ../m4.out`"

# 5. A real C build with the on-box compiler, when there is one.
if [ -x /usr/ccs/bin/cc ] || [ -x /bin/cc ]; then
	echo "-- make hello  (C build via the on-box cc)"
	"$MAKE" hello > ../m5.out 2>&1
	sed 's/^/     /' ../m5.out
	[ "`./hello`" = "hello from make" ] && echo "ok   C program built and ran" \
		|| bad "hello did not build/run"
else
	echo "SKIP C build (no on-box cc)"
fi

"$MAKE" clean > /dev/null 2>&1
cd ..
rm -f m.out m2.out m3.out m4.out m5.out
echo ""
if [ $fails -eq 0 ]; then
	echo "make smoke: PASS"
	exit 0
fi
echo "make smoke: $fails FAILED"
exit 1
