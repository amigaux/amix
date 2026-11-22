# gen-lib.sh -- ON THE BOX, sourced: run_cg ARGS runs dtcodegen in the current directory and
# keeps what that run did, in $OUT/<n>-<module>/: args, log, rc, changed (files it created
# or rewrote), created (the ones absent before), removed, before/ (the earlier contents of
# the rewritten ones), after/ (what it wrote).  1992 Bourne shell.
# MIT licence, see LICENSE in userland/packages.
run_cg() {
	N=`expr $N + 1`
	eval k=\${$#}
	case $k in -main) k=main;; *.bil) k=`basename $k .bil`;; esac
	o=$OUT/$N-$k
	mkdir -p $o/before $o/after
	echo "$*" > $o/args
	rm -rf $SNAP; mkdir $SNAP
	find . -type f -print | cpio -pdm $SNAP 2> /dev/null
	touch $o/ref; sleep 2
	NLSPATH=$CAT $CG "$@" > $o/log 2>&1; echo $? > $o/rc
	find . -type f -newer $o/ref -print | sort > $o/changed
	: > $o/created
	for f in `cat $o/changed`; do
		echo $f | cpio -pdm $o/after 2> /dev/null
		if [ -f $SNAP/$f ]; then ( cd $SNAP && echo $f | cpio -pdm $o/before 2> /dev/null )
		else echo $f >> $o/created; fi
	done
	( cd $SNAP && find . -type f -print ) | sort > $o/snap.lst
	find . -type f -print | sort > $o/now.lst
	comm -23 $o/snap.lst $o/now.lst > $o/removed
	echo "RES cg $N $k rc=`cat $o/rc` changed=`wc -l < $o/changed` created=`wc -l < $o/created` removed=`wc -l < $o/removed`"
	return `cat $o/rc`
}
