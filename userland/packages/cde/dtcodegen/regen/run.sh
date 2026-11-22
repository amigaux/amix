#!/bin/sh
# run.sh -- ON THE BOX: the dtcodegen runs of dtbuilder (src/ab) and ttsnoop (src/tt), as
# make runs them; the results in out.tar.  1992 Bourne shell; "RES" lines.
# Layout under /var/pk: bin/dtcodegen and bin/dtcodegen.cat, gen-lib.sh, gen-ab.sh and
# gen-tt.sh (mkgen.py's), src/ab and src/tt (the two directories of the configured tree).
# MIT licence, see LICENSE in userland/packages.
D=/var/pk; SNAP=$D/snap; CG=$D/bin/dtcodegen; CAT=$D/bin/dtcodegen.cat
. $D/gen-lib.sh
uname -a | sed 's/^/RES uname: /'
ls -l $CG $CAT | sed 's/^/RES   /'
rm -rf $D/out; mkdir $D/out
for d in ab tt; do
	N=0; OUT=$D/out/$d; mkdir -p $OUT
	( cd $D/src/$d && . $D/gen-$d.sh ) > $D/out/$d.log 2>&1
	echo "RES dir $d: `grep -c '^RES cg' $D/out/$d.log` runs, `grep '^RES cg' $D/out/$d.log | grep -vc 'rc=0'` with rc != 0"
	grep '^RES cg' $D/out/$d.log | grep -v 'rc=0' | head -5
done
rm -rf $SNAP
( cd $D && tar cf out.tar out ); echo "RES tar rc=$? `ls -l $D/out.tar | awk '{print $5}'` bytes"
