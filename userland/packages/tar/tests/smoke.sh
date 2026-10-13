#!/bin/sh
#
# smoke.sh -- prove GNU tar's over-stock features work, ON THE BOX, as root.
#
#     sh smoke.sh [/opt/amix/bin/tar]
#
# Run from a scratch directory holding fixture.tar (made host-side by
# mkfixture.py).  Leaves out.tar behind so the host can extract it with its own
# tar (the interop half of the test).  Written for the 1992 pre-POSIX Bourne
# shell (PORTING.md 3.6): backticks, `expr`, no `grep -q`, no printf(1), no awk
# number printing (awk prints numbers through _doprnt's FP path).
#
# Each check inspects OUTPUT or the resulting FILESYSTEM, never an exit status.

TAR=$1
if [ -z "$TAR" ]; then
	TAR=/opt/amix/bin/tar
fi

fails=0
bad() { echo "FAIL $*"; fails=`expr $fails + 1`; }

echo "== GNU tar on-box smoke =="
echo "-- tar: $TAR"
if [ ! -x "$TAR" ]; then
	echo "FAIL $TAR is not executable"
	exit 1
fi
if [ ! -f fixture.tar ]; then
	echo "FAIL fixture.tar missing (run from the fixture directory)"
	exit 1
fi

echo "-- tar --version"
"$TAR" --version | sed -n 1p

# 1. BASE-256: -tv of a host archive whose uid 3000000 does not fit octal.
echo "-- tar -tvf fixture.tar  (base-256 uid, long name, symlink)"
"$TAR" -tvf fixture.tar > t.list 2> t.err
sed 's/^/     /' t.list
cat t.err
# big.txt has an EMPTY user name, so -tv prints "/" for it; the NUMERIC view is
# the proof that the base-256 field decoded.
"$TAR" -tv --numeric-owner -f fixture.tar fx/big.txt > t.num 2>&1
sed 's/^/     /' t.num
grep '3000000/3000000' t.num > /dev/null 2>&1 && echo "ok   base-256 uid/gid 3000000 decoded" \
	|| bad "base-256 uid not decoded"
grep 'd08-abcdefgh/leaf.txt' t.list > /dev/null 2>&1 && echo "ok   GNU long name (128 bytes) listed" \
	|| bad "long name not listed"
grep 'link -> target.txt' t.list > /dev/null 2>&1 && echo "ok   symlink listed" \
	|| bad "symlink not listed"

# 2. EXTRACT AS ROOT -- same-owner maps NAMES back through getpwnam()/getgrnam()
#    (D3: the executable's own parsers, not the stock libc's first-call crash).
echo "-- tar -xf fixture.tar -C x  (as root: name -> uid via getpwnam)"
rm -rf x; mkdir x
"$TAR" -xf fixture.tar -C x 2> x.err
echo "     rc=$? (2 expected: see big.txt below)"
sed 's/^/     /' x.err
# SVR4.0's uid_t tops out far below 3000000, so chown(2) refuses it with EINVAL
# and tar reports it and exits 2 -- the expected outcome, and a second proof
# that the base-256 value arrived intact.
grep 'uid 3000000, gid 3000000' x.err > /dev/null 2>&1 \
	&& echo "ok   chown of base-256 uid 3000000 refused by the kernel (EINVAL), as expected" \
	|| bad "no chown refusal for uid 3000000 -- was the base-256 value decoded?"
binuid=`grep '^bin:' /etc/passwd | cut -d: -f3`
got=`ls -ln x/fx/own-bin.txt | sed 's/  */ /g' | cut -d' ' -f3`
if [ -n "$binuid" ] && [ "$got" = "$binuid" ]; then
	echo "ok   uname 'bin' mapped to the box's bin uid $binuid (not the archive's 4242)"
else
	bad "own-bin.txt uid is '$got', expected bin's uid '$binuid'"
fi
got=`ls -ln x/fx/own-nobody | sed 's/  */ /g' | cut -d' ' -f3`
[ "$got" = "1234" ] && echo "ok   unknown uname kept numeric uid 1234" \
	|| bad "own-nobody uid is '$got', expected 1234"
got=`ls -ln x/fx/big.txt | sed 's/  */ /g' | cut -d' ' -f3`
echo "     big.txt extracted with uid '$got' (archive: 3000000; SVR4.0 uid_t range decides)"
if [ -h x/fx/link ]; then
	echo "ok   symlink extracted as a symlink"
else
	bad "x/fx/link is not a symlink"
fi
[ "`cat x/fx/d00-abcdefgh/d01-abcdefgh/d02-abcdefgh/d03-abcdefgh/d04-abcdefgh/d05-abcdefgh/d06-abcdefgh/d07-abcdefgh/d08-abcdefgh/leaf.txt`" = "deep leaf" ] \
	&& echo "ok   long-name file extracted with its content" || bad "long-name file content wrong"

# 3. CREATE ON THE BOX -- lstat (the ac_cv_func_lstat seed) and uid -> name
#    (getpwuid, D3).  Also exercises -b (strtoull) and --totals (human.c): the
#    two code paths the D4 patches rewrote.
echo "-- tar -b 20 --totals -cf out.tar x"
"$TAR" -b 20 --totals -cf out.tar x 2> c.err
sed 's/^/     /' c.err
grep 'Total bytes written' c.err > /dev/null 2>&1 && echo "ok   --totals printed" \
	|| bad "--totals printed nothing"
"$TAR" -tvf out.tar > o.list 2>&1
grep '^l.*x/fx/link -> target.txt' o.list > /dev/null 2>&1 \
	&& echo "ok   symlink archived AS a symlink (lstat, not stat)" \
	|| { bad "symlink not archived as a symlink"; sed 's/^/     /' o.list; }
grep 'bin/' o.list > /dev/null 2>&1 && echo "ok   owner NAME recorded (getpwuid)" \
	|| bad "no owner name recorded"

# 4. -z, when a gzip is on the PATH (the gzip package).  Optional by design.
if [ -x /opt/amix/bin/gzip ]; then
	echo "-- tar -czf / -tzf with /opt/amix/bin/gzip"
	PATH=/opt/amix/bin:$PATH; export PATH
	"$TAR" -czf out.tgz x && n=`"$TAR" -tzf out.tgz | wc -l`
	n=`echo $n`
	if [ -n "$n" ] && [ "$n" -gt 5 ]; then
		echo "ok   -z round trip listed $n entries"
	else
		bad "-z round trip listed '$n' entries"
	fi
else
	echo "SKIP -z (no /opt/amix/bin/gzip installed)"
fi

rm -f t.list t.err t.num x.err c.err o.list out.tgz
echo ""
if [ $fails -eq 0 ]; then
	echo "tar smoke: PASS"
	exit 0
fi
echo "tar smoke: $fails FAILED"
exit 1
