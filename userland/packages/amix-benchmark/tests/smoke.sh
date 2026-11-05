#!/bin/sh
#
# smoke.sh -- prove the amix-benchmark package works, ON THE BOX, with the
# package installed:
#
#     sh smoke.sh [<scratch directory, default /var/tmp>]
#
# Runs the default suite to its end, checks that every row that can run says
# status=ok, then one disk read row and one disk write row on a scratch file,
# which it removes.  Exits 0 only if every step passed.  Result lines start
# "RES "; the suite's own TEST lines are repeated, so the numbers stay with
# the result.  The default suite takes minutes where FP is emulated.
#
# Written for the 1992 Bourne shell: backticks, expr, no grep -q, no printf.

B=/opt/amix/bin/amix-bench
K=/opt/amix/lib/amix-bench
D=${1:-/var/tmp}
T=$D/amixbench.$$
fails=0
ok() { echo "RES ok   $*"; }
no() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }

# status <file> <row> <want>
status() {
	s=`grep "^TEST $2 " $1 | sed -n 's/^TEST [^ ]* status=\([a-z]*\).*/\1/p' | head -1`
	[ "$s" = "$3" ] && ok "$2 status=$3" || no "$2 status=${s:-none}, not $3"
}

[ -x $B ] && ok "$B is executable" || no "$B is not executable"
$B --help > $T.out 2>&1 && ok "--help" || no "--help failed"
n=`$B --list | wc -l | tr -d ' '`
[ "$n" = 24 ] && ok "--list: 24 rows" || no "--list: $n rows"
[ ! -f $K/whet ] && ok "whet is not installed" || no "whet is installed"
grep '^built_' $K/BUILD-INFO > /dev/null && no "BUILD-INFO names a build host or date" || ok "BUILD-INFO names no build host or date"

# the default suite, to its end: no disk row runs, none needs a target
$B > $T.def 2> $T.err; rc=$?
[ $rc = 0 ] && ok "default suite: status $rc" || no "default suite: status $rc: `tail -1 $T.err`"
grep '^build_cc_version=' $T.def | sed 's/^/RES /'
grep '^TEST ' $T.def | sed 's/^/RES /'
for r in cpu.dhry fpu.dhry fpu.paranoia mem.bw vm.fork vm.ctx vm.fault; do
	status $T.def $r ok
done
status $T.def fpu.whet skipped
status $T.def disk.seq.read.512 skipped
status $T.def disk.seq.write.512 skipped

# one write row and one read row on a scratch file (never a device)
S=$T.dat
$B --write-target $S --create-scratch --no-header --only disk.seq.write.16384 > $T.w 2>> $T.err; rc=$?
grep '^TEST ' $T.w | sed 's/^/RES /'
status $T.w disk.seq.write.16384 ok
$B --read-target $S --no-header --only disk.seq.read.16384 > $T.r 2>> $T.err; rc=$?
grep '^TEST ' $T.r | sed 's/^/RES /'
status $T.r disk.seq.read.16384 ok
[ -s $T.err ] && sed 's/^/RES stderr: /' $T.err | head -8

rm -f $T.out $T.def $T.err $T.w $T.r $S
[ $fails = 0 ] && echo "RES PASS" || echo "RES $fails failed"
[ $fails = 0 ]
