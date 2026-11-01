#!/bin/sh
#
# smoke.sh -- the Pth runtime, ON THE BOX.
#
#     sh smoke.sh
#
# The C tests built with the package (t-errno: each thread's errno across
# switches; t-once: pthread_once contended, recursive and cancelled), run
# from beside them.  1992 Bourne shell.  Result lines start with "RES "; the
# last is "RES smoke PASS" or "RES smoke FAIL <n>".

fails=0
for t in t-errno t-once; do
	if [ -x ./$t ]; then
		./$t > $t.out 2>&1; rc=$?
		cat $t.out
		[ $rc -eq 0 ] || fails=`expr $fails + 1`
	else
		echo "RES FAIL $t missing"; fails=`expr $fails + 1`
	fi
done
[ $fails -eq 0 ] && echo "RES smoke PASS" || echo "RES smoke FAIL $fails"
