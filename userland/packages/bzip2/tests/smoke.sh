#!/bin/sh
#
# smoke.sh -- bzip2 1.0.8 acceptance, ON THE BOX.
#
#     sh tests/smoke.sh [bindir]          (default /opt/amix/bin)
#
# Run from the directory that holds tests/ (tools/pkg-smoke runs it so);
# upstream's test vectors (tests/sample*, listed in tests/fixtures) are
# pushed beside this file.  Every check reads OUTPUT or FILES, not only an
# exit status.  1992 Bourne shell: backticks, expr, no grep -q, no $(...),
# no `!'.  Result lines start with "RES "; the last is "RES smoke PASS" or
# "RES smoke FAIL <n>".

B=${1:-/opt/amix/bin}
T=`pwd`/tests
fails=0
ok()  { echo "RES ok   $*"; }
bad() { echo "RES FAIL $*"; fails=`expr $fails + 1`; }
has() { grep "$2" "$1" > /dev/null 2>&1; }
same() { cmp "$1" "$2" > /dev/null 2>&1; }

for p in bzip2 bunzip2 bzcat bzip2recover bzgrep bzegrep bzfgrep bzmore bzless bzdiff bzcmp; do
	[ -x $B/$p ] || { echo "RES FAIL $B/$p not executable"; echo "RES smoke FAIL 1"; exit 1; }
done
# the wrappers call bzip2 by name
PATH=$B:$PATH; export PATH
rm -rf bsmoke; mkdir bsmoke; cd bsmoke || exit 1

echo "== versions"
$B/bzip2 -V < /dev/null 2>&1 | sed -n 1p

# 1. upstream's own `make test': compress the three references at -1/-2/-3
#    and match upstream's .bz2 BYTE FOR BYTE; decompress upstream's .bz2
n=1
for lvl in 1 2 3; do
	$B/bzip2 -$lvl < $T/sample$n.ref > s$n.rb2
	same s$n.rb2 $T/sample$n.bz2 && ok "sample$n.ref -$lvl compresses byte-identical to upstream's sample$n.bz2" \
		|| bad "sample$n -$lvl compress differs from upstream"
	if [ $n -eq 3 ]; then $B/bzip2 -ds < $T/sample$n.bz2 > s$n.tst; else $B/bzip2 -d < $T/sample$n.bz2 > s$n.tst; fi
	same s$n.tst $T/sample$n.ref && ok "sample$n.bz2 decompresses to sample$n.ref`[ $n -eq 3 ] && echo ' (-s, small memory)'`" \
		|| bad "sample$n decompress differs"
	n=`expr $n + 1`
done

# 2. file round trip, names, modes (fchmod), -k -t -c, and the hard links
awk 'BEGIN { for (i = 1; i <= 30000; i++) printf "%d the quick brown fox %d\n", i, i * 7 }' > big
cp big big.orig
chmod 640 big
$B/bzip2 -1 big; rc=$?
[ $rc -eq 0 ] && [ -f big.bz2 ] && [ ! -f big ] && ok "bzip2 big -> big.bz2, original removed" || bad "bzip2 file rc=$rc"
m=`ls -l big.bz2 | awk '{print $1}'`
[ "$m" = "-rw-r-----" ] && ok "mode 640 carried to big.bz2 (fchmod)" || bad "big.bz2 mode $m"
$B/bzip2 -t big.bz2; rc=$?
[ $rc -eq 0 ] && ok "bzip2 -t integrity rc 0" || bad "bzip2 -t rc=$rc"
$B/bunzip2 -k big.bz2
same big big.orig && [ -f big.bz2 ] && ok "bunzip2 -k restores the original, keeps big.bz2" || bad "bunzip2 -k"
$B/bzcat big.bz2 > big.cat
same big.cat big.orig && ok "bzcat" || bad "bzcat"
i1=`ls -i $B/bzip2 | awk '{print $1}'`; i2=`ls -i $B/bunzip2 | awk '{print $1}'`; i3=`ls -i $B/bzcat | awk '{print $1}'`
[ "$i1" = "$i2" ] && [ "$i1" = "$i3" ] && ok "bunzip2 and bzcat are hard links of bzip2 (inode $i1)" || bad "links: $i1 $i2 $i3"
echo junk > notbz
$B/bzip2 -t notbz > t.out 2>&1; rc=$?
[ $rc -eq 2 ] && ok "bzip2 -t on a non-bzip2 file: rc 2" || bad "bzip2 -t junk rc=$rc: `cat t.out`"

# 3. -v report (the only floating point in bzip2: out of line, patch 04)
$B/bzip2 -1 -v -c big.orig > /dev/null 2> v.out
has v.out ':1, .* bits/byte, .*% saved, 963024 in, ' && ok "bzip2 -v ratio report: `sed 's/^ *//' v.out`" \
	|| bad "bzip2 -v: `cat v.out`"

# 4. bzip2recover on a damaged multi-block file (64-bit offsets, patch 01)
$B/bzip2 -1 -c big.orig > multi.bz2
sz=`ls -l multi.bz2 | awk '{print $5}'`
half=`expr $sz / 2 / 1024`
dd if=multi.bz2 of=cut.bz2 bs=1k count=$half > /dev/null 2>&1
$B/bzip2recover cut.bz2 > rec.out 2>&1; rc=$?
nrec=`ls rec*cut.bz2 2>/dev/null | wc -l | tr -d ' '`
[ "$nrec" -ge 2 ] && has rec.out 'block 1 runs from 80 to ' && ok "bzip2recover: $nrec blocks from a cut file (rc $rc)" \
	|| bad "bzip2recover rc=$rc, $nrec blocks: `cat rec.out`"
grep 'runs from' rec.out | sed -n 1,2p | sed 's/^ */     /'
$B/bzip2 -dc rec*cut.bz2 > rec.data 2>/dev/null
cmp rec.data big.orig > rec.cmp 2>&1
has rec.cmp 'EOF on' && ok "recovered blocks are an exact prefix of the original" \
	|| bad "recovered data: `cat rec.cmp`"

# 5. the wrappers (Bourne patches 02/03)
cp big.bz2 a.bz2
sed 's/^12345 /XXXXX /' big.orig > b; $B/bzip2 b
$B/bzgrep '^12345 ' a.bz2 > g1.out; rc=$?
[ $rc -eq 0 ] && [ "`cat g1.out`" = "12345 the quick brown fox 86415" ] && ok "bzgrep one file" || bad "bzgrep rc=$rc: `cat g1.out`"
$B/bzgrep 'fox 86415$' a.bz2 b.bz2 > g2.out
has g2.out '^a.bz2:12345 the' && has g2.out '^b.bz2:XXXXX the' && ok "bzgrep two files, file: prefixes" || bad "bzgrep 2: `tr '\012' '/' < g2.out`"
$B/bzegrep -c '^(1|2)0000 ' a.bz2 > g3.out
[ "`cat g3.out`" = "2" ] && ok "bzegrep (hard link) uses egrep" || bad "bzegrep: `cat g3.out`"
$B/bzdiff a.bz2 b.bz2 > d.out; rc=$?
[ $rc -eq 1 ] && has d.out '^< 12345 the' && has d.out '^> XXXXX the' && ok "bzdiff two .bz2 files (private temp dir)" \
	|| bad "bzdiff rc=$rc: `sed -n 1,4p d.out`"
ls -d ${TMPDIR:-/tmp}/bzdiff.* > /dev/null 2>&1 && bad "bzdiff left a temp directory" || ok "bzdiff removed its temp directory"
$B/bzcmp a.bz2 a.bz2; rc=$?
[ $rc -eq 0 ] && ok "bzcmp identical rc 0" || bad "bzcmp rc=$rc"
$B/bzmore a.bz2 < /dev/null > m.out 2>&1
has m.out '^30000 the quick brown fox 210000$' && ok "bzmore through more (non-tty)" || bad "bzmore: `sed -n 1,3p m.out`"

cd ..
if [ $fails -eq 0 ]; then echo "RES smoke PASS"; else echo "RES smoke FAIL $fails"; fi
[ $fails -eq 0 ]
