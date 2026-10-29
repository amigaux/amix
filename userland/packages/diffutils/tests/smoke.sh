#!/bin/sh
#
# smoke.sh -- GNU diffutils 2.8.1 acceptance, ON THE BOX.
#
#     sh smoke.sh [bindir]          (default /opt/amix/bin)
#
# Runs in a scratch directory it creates under the current one; fixtures are
# made here with awk, so nothing but this file is pushed.  Every check reads
# OUTPUT or FILES, not only an exit status.  Written for the 1992 pre-POSIX
# Bourne shell (PORTING.md 3.6): backticks, expr, no grep -q, no $(...).
# Result lines start with "RES "; the last one is "RES smoke PASS" or
# "RES smoke FAIL <n>".

B=${1:-/opt/amix/bin}
fails=0
ok()  { echo "RES ok   $*"; }
bad() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }
# has <file> <fixed string>: the string occurs in the file
has() { grep "$2" "$1" > /dev/null 2>&1; }
hasnt() { if grep "$2" "$1" > /dev/null 2>&1; then return 1; fi; return 0; }

for p in diff diff3 sdiff cmp; do
	[ -x $B/$p ] || { echo "RES FAIL $B/$p not executable"; echo "RES smoke FAIL 1"; exit 1; }
done
rm -rf dsmoke; mkdir dsmoke; cd dsmoke || exit 1

echo "== versions"
$B/diff --version | sed -n 1p
$B/cmp --version | sed -n 1p

# --- fixtures ----------------------------------------------------------------
awk 'BEGIN { for (i = 1; i <= 2000; i++) print "line " i }' > a
# b: three hunks -- a change, a deletion, an insertion -- and a new last line
awk '{ if ($2 == 100) print "line one hundred"
       else if ($2 >= 700 && $2 <= 704) next
       else if ($2 == 1500) { print; print "inserted after 1500" }
       else print }
     END { print "tail added" }' a > b
cp a same

# 1. identical files: rc 0, no output
$B/diff a same > o1; rc=$?
[ $rc -eq 0 ] && [ ! -s o1 ] && ok "identical files: rc 0, no output" || bad "identical files rc=$rc"

# 2. unified diff, applied with patch, byte-compared  (diff and patch verify
#    each other; registry/diffutils.yaml smoke)
$B/diff -u a b > u.diff; rc=$?
[ $rc -eq 1 ] && ok "diff -u differing files: rc 1" || bad "diff -u rc=$rc"
has u.diff '^--- a' && has u.diff '^+++ b' && has u.diff '^@@ -97,7 +97,7 @@' \
	&& ok "diff -u headers and first hunk header" || bad "diff -u output: `sed -n 1,3p u.diff`"
n=`grep -c '^@@' u.diff`
[ "$n" -eq 4 ] && ok "diff -u: 4 hunks" || bad "diff -u: $n hunks, expected 4"
PATCH=
for p in /opt/amix/bin/patch /usr/local/bin/patch /usr/public/bin/patch; do
	if [ -x $p ]; then PATCH=$p; break; fi
done
if [ -n "$PATCH" ]; then
	cp a a.p
	$PATCH -s a.p < u.diff > patch.out 2>&1; rc=$?
	$B/cmp a.p b > /dev/null 2>&1 && [ $rc -eq 0 ] \
		&& ok "unified diff applied with $PATCH reproduces b exactly" \
		|| bad "patch ($PATCH) rc=$rc result differs from b: `cat patch.out`"
else
	bad "no patch program found to apply the unified diff"
fi

# 3. context and normal formats
$B/diff -c a b > c.diff
has c.diff '^\*\*\* a' && has c.diff '^--- b' && has c.diff '^! line one hundred' \
	&& ok "diff -c context format" || bad "diff -c output"
$B/diff a b > n.diff
has n.diff '^100c100' && has n.diff '^700,704d699' && has n.diff '^> inserted after 1500' \
	&& ok "normal format (100c100, 700,704d699, insertion)" || bad "normal format: `sed -n 1,4p n.diff`"

# 4. ed script round trip with the stock ed
$B/diff -e a b > e.diff
cp a a.e
( cat e.diff; echo w; echo q ) | ed - a.e > /dev/null 2>&1
$B/cmp a.e b > /dev/null 2>&1 && ok "diff -e script applied with ed reproduces b" || bad "diff -e via ed"

# 5. recursive, new files, Only in, exclude (bundled fnmatch)
mkdir d1 d2 d1/sub d2/sub
cp a d1/f; cp b d2/f; cp a d1/sub/g; cp a d2/sub/g
echo only1 > d1/one; echo only2 > d2/two; echo x > d1/skip.o; echo y > d2/skip.o
$B/diff -r d1 d2 > r.diff; rc=$?
[ $rc -eq 1 ] && has r.diff '^Only in d1: one' && has r.diff '^Only in d2: two' \
	&& has r.diff '^diff -r d1/f d2/f' && hasnt r.diff 'sub/g' \
	&& ok "diff -r: Only in, changed file, identical subdir file silent" || bad "diff -r rc=$rc: `cat r.diff | sed -n 1,5p`"
$B/diff -ruN -x '*.o' d1 d2 > rn.diff
has rn.diff '^+++ d2/two' && hasnt rn.diff 'skip.o' \
	&& ok "diff -ruN -x '*.o': new file as a hunk, pattern excluded" || bad "diff -ruN -x"

# 6. -I regex (bundled regex), -i, -w, -b, -q, -y
( echo '#c1'; echo keep ) > i1; ( echo '#c2'; echo keep ) > i2
$B/diff -I '^#' i1 i2 > /dev/null; rc=$?
[ $rc -eq 0 ] && ok "diff -I '^#' ignores the comment change" || bad "diff -I rc=$rc"
echo 'Hello World' > w1; echo 'hello   world' > w2
$B/diff -i -b w1 w2 > /dev/null; r1=$?
$B/diff -w w1 w2 > /dev/null; r2=$?
[ $r1 -eq 0 ] && [ $r2 -eq 1 ] && ok "diff -i -b equal, -w alone differs (case)" || bad "-i -b rc=$r1, -w rc=$r2"
$B/diff -q a b > q.out
has q.out '^Files a and b differ$' && ok "diff -q" || bad "diff -q: `cat q.out`"
$B/diff -y -W 40 i1 i2 > y.out
has y.out '|' && ok "diff -y side by side" || bad "diff -y: `cat y.out`"

# 7. diff -l pages through pr (PR_PROGRAM /usr/bin/pr, a fork + exec)
$B/diff -l a b > l.out 2>&1; rc=$?
[ $rc -eq 1 ] && has l.out 'Page 1' && has l.out '^100c100' \
	&& ok "diff -l through /usr/bin/pr" || bad "diff -l rc=$rc: `sed -n 1,3p l.out`"

# 8. binary files
# (the box's own executables: stock awk may not write a NUL)
cp /usr/bin/ls bin1; cp /usr/bin/cat bin2
$B/diff bin1 bin2 > bin.out; rc=$?
# (2.8.1 exits 2 here: "differing binary files are considered to cause
# trouble", diff.texi; 3.x changed it to 1)
[ $rc -eq 2 ] && has bin.out '^Binary files bin1 and bin2 differ$' \
	&& ok "binary files: rc 2 (2.8.1 semantics), 'Binary files ... differ'" || bad "binary rc=$rc: `cat bin.out`"

# 9. diff3 -m merge: one clean change from each side, then a conflict
awk 'BEGIN { for (i = 1; i <= 30; i++) print "l" i }' > base
sed 's/^l5$/mine5/' base > mine
sed 's/^l25$/theirs25/' base > theirs
$B/diff3 -m mine base theirs > m.out; rc=$?
[ $rc -eq 0 ] && has m.out '^mine5$' && has m.out '^theirs25$' \
	&& ok "diff3 -m merges non-overlapping changes, rc 0" || bad "diff3 -m rc=$rc"
sed 's/^l10$/mine10/' base > mine2; sed 's/^l10$/theirs10/' base > theirs2
$B/diff3 -m mine2 base theirs2 > m2.out; rc=$?
[ $rc -eq 1 ] && has m2.out '^<<<<<<< mine2' && has m2.out '^>>>>>>> theirs2' \
	&& ok "diff3 -m conflict markers, rc 1" || bad "diff3 conflict rc=$rc"

# 10. sdiff: side by side, and an -o merge driven from stdin -- run with the
#     STOCK directories first on PATH, so the diff it execs must be ours
#     (DEFAULT_DIFF_PROGRAM; stock diff knows no --sdiff-merge-assist)
PATH=/usr/bin:/bin:/usr/sbin; export PATH
$B/sdiff -w 60 i1 i2 > s.out; rc=$?
[ $rc -eq 1 ] && has s.out '#c1' && has s.out '|' && ok "sdiff side by side" || bad "sdiff rc=$rc: `cat s.out`"
echo r | $B/sdiff -o s.merged i1 i2 > /dev/null 2> s.err; rc=$?
$B/cmp s.merged i2 > /dev/null 2>&1 && [ $rc -eq 1 ] && [ ! -s s.err ] \
	&& ok "sdiff -o merge (r) with stock PATH first: merged, rc 1, no stderr" \
	|| bad "sdiff -o merge rc=$rc: `cat s.merged 2>/dev/null` / `cat s.err`"

# 11. cmp: identical, first difference, -l, a difference past 64 KB
$B/cmp a same; rc=$?
[ $rc -eq 0 ] && ok "cmp identical rc 0" || bad "cmp identical rc=$rc"
$B/cmp a b > cm.out; rc=$?
[ $rc -eq 1 ] && has cm.out '^a b differ: char 789, line 100$' \
	&& ok "cmp first difference (char 789, line 100)" || bad "cmp rc=$rc: `cat cm.out`"
awk 'BEGIN { for (i = 1; i <= 7000; i++) print "0123456789" }' > big1
awk 'BEGIN { for (i = 1; i <= 7000; i++) if (i == 6990) print "0123456789X"; else print "0123456789" }' > big2
$B/cmp big1 big2 > cb.out
has cb.out 'differ: char 76890, line 6990$' && ok "cmp offset past 64 KB (char 76890)" || bad "cmp big: `cat cb.out`"
sed 's/^line 50$/line 5X/' a > a1
$B/cmp -l a a1 > cl.out
n=`wc -l < cl.out | tr -d ' '`
[ "$n" -eq 1 ] && has cl.out '^ *390  *60 130$' && ok "cmp -l: 1 differing byte (390: 060 130)" || bad "cmp -l: `cat cl.out`"

# 12. the stock tools, for the record (X6: does stock diff have -u?)
if /usr/bin/diff -u a b > x6.out 2>&1; then :; fi
if has x6.out '^@@'; then echo "RES X6 stock /usr/bin/diff -u: unified output"
else echo "RES X6 stock /usr/bin/diff -u: no unified output (`sed -n 1p x6.out`)"; fi

cd ..
if [ $fails -eq 0 ]; then echo "RES smoke PASS"; else echo "RES smoke FAIL $fails"; fi
[ $fails -eq 0 ]
