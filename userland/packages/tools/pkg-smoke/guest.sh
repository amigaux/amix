#!/bin/sh
# guest.sh -- runs ON THE GUEST (Amix, Bourne sh, as root):  sh guest.sh /tmp/pks
#
# For each PKGLIST line: stock pkgadd from the datastream (admin file, no
# questions), pkginfo + pkgchk, the package's tests/smoke.sh, stock pkgrm,
# and proof that the contents database no longer names the package.
# Written for the 1992 Bourne shell.  Result lines start with "RES ".

D=${1:-/tmp/pks}
cd $D || exit 1
echo "== guest: `uname -a`"
bad=0
while read s n f; do
	got=`sum -r $f 2>/dev/null | awk '{print $1 + 0}'`
	if [ "$got" != "`expr $s + 0`" ]; then echo "PUSH-MISMATCH $f host=$s guest=$got"; bad=1; fi
done < MANIFEST.sum
[ $bad -eq 0 ] && echo "RES push all files match MANIFEST.sum"
C=/var/sadm/install/contents
while read P F N M; do
	echo "== $P ($F)"
	pkgadd -n -a $D/admin -d $D/$F $P > $D/add.$P 2>&1; echo "RES pkgadd $P rc=$?"
	pkginfo -l $P 2>&1 | egrep 'PKGINST|VERSION|STATUS'
	pkgchk $P > $D/chk.$P 2>&1; echo "RES pkgchk $P rc=$?"
	n=`awk '$2 == "f" { for (i = 10; i <= NF; i++) if ($i == "'$P'") n++ } END { print n + 0 }' $C`
	echo "RES files $P $n"
	if [ -f $D/$N/tests/smoke.sh ]; then
		# run from <name>/ (`sh tests/smoke.sh') or, for an older script,
		# from <name>/tests/ beside its fixtures (PKGLIST's fourth field)
		if [ "$M" = tests ]; then W=$D/$N/tests; S=smoke.sh; else W=$D/$N; S=tests/smoke.sh; fi
		( cd $W && sh $S ) > $D/smoke.$P 2>&1; echo "RES smoke-rc $P $?"
		if grep '^RES ' $D/smoke.$P > /dev/null; then
			grep '^RES ' $D/smoke.$P
		else
			# an older script prints ok/FAIL/SKIP lines and a verdict
			echo "RES smoke $P ok=`grep -c '^ok' $D/smoke.$P` fail=`grep -c '^FAIL' $D/smoke.$P` skip=`grep -c '^SKIP' $D/smoke.$P`"
			grep '^FAIL' $D/smoke.$P | sed 's/^/RES /'
			tail -1 $D/smoke.$P | sed 's/^/RES verdict /'
		fi
	else
		echo "RES smoke $P none (the package has no tests/smoke.sh)"
	fi
	pkgrm -n -a $D/admin $P > $D/rm.$P 2>&1; echo "RES pkgrm $P rc=$?"
	if pkginfo $P > /dev/null 2>&1; then echo "RES after-rm $P still installed"; else echo "RES after-rm $P gone"; fi
	# (the header comment names the last package pkgrm touched: skipped)
	n=`awk '$1 !~ /^#/ { for (i = 2; i <= NF; i++) if ($i == "'$P'") n++ } END { print n + 0 }' $C`
	echo "RES after-rm $P contents-lines $n"
	awk '$1 !~ /^#/ { for (i = 2; i <= NF; i++) if ($i == "'$P'") print "RES after-rm line " $0 }' $C
done < PKGLIST
# with what a smoke left for the host side to read (tar's out.tar)
tar cf $D/out.tar add.* chk.* smoke.* rm.* `ls */tests/out.tar 2>/dev/null` 2>/dev/null
echo "RES guest done"
