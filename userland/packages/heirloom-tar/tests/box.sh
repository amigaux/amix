#!/sbin/sh
#
# box.sh -- heirloom-tar's acceptance on the box (the system's 1992 sh).
#
#     sh box.sh <dir> [grep|greponly]
#
# <dir> holds what make-archives.sh made (*.tar, expect), heirtar.pkg, a
# pkgadd admin file `admin' (conflict=nocheck, instance=overwrite, the rest
# nocheck), and optionally tar-no03 (tar built without
# patches/03, to show what the patch fixes).  As root.  Writes <dir>/box.log
# (raw facts: check.py judges them on the build host), the listings and
# archives check.py reads, and <dir>/done last.
#
#  1. the stock /usr/sbin/tar, kept as <dir>/stock-tar: every archive
#     extracted (exit status, a core, the files' sums and owners), listed
#     (tf, tvf), and the source tree written back (tar c)
#  2. pkgadd heirtar: the paths, links, pkgchk
#  3. the same with the installed /usr/sbin/tar, plus `o' as root and
#     extraction as user bin, the archive7 entry of /etc/default/tar, and
#     each tar reading the other's archive
#  4. pkgrm heirtar: what stays
#  5. with `grep': every file on the box that names tar as a command (text
#     files whole, binaries through strings), /proc, /dev and tmp dirs aside;
#     `greponly' runs this part alone and writes <dir>/grep.log
# MIT, this repository.

# (the 1992 sh ends ${1:?word} at the first blank: no blanks in the word)
[ -n "$1" ] || { echo "usage: sh box.sh dir [grep|greponly]" >&2; exit 2; }
D=$1
cd $D || exit 1
if [ "$2" = greponly ]; then exec > $D/grep.log 2>&1; else exec > $D/box.log 2>&1; fi
X=$D/x

echo "== uname `uname -a`"
if [ "$2" != greponly ]; then
sed -n 's/^build=//p' /stand/k30/kabi /stand/k46/kabi 2>/dev/null
echo "== passwd `egrep '^(root|bin|jdoe):' /etc/passwd | cut -d: -f1,3,4 | tr '\012' ' '`"
echo "== group `egrep '^(root|sys|bin|users):' /etc/group | cut -d: -f1,3 | tr '\012' ' '`"
echo "== uid1234 `awk -F: '$3 == 1234' /etc/passwd | wc -l`"
pkginfo amxbase 2>&1 | head -1
ls -l /usr/sbin/tar /etc/tar /etc/default/tar
echo "SUM /usr/sbin/tar `sum -r /usr/sbin/tar`"
cp /usr/sbin/tar $D/stock-tar

# xt <label> <tar> <archive>: extract into $X/<label>-<archive>, report
xt() {
	rm -rf "${X:?}/$1-$3"
	mkdir -p $X/$1-$3
	cd $X/$1-$3
	$2 xf $D/$3.tar > $X/$1-$3.out 2>&1
	rc=$?
	c=no
	if [ -f core ]; then c=yes; mv core "${X:?}/$1-$3.core"; fi
	n=`find . -type f -print | wc -l`
	echo "X $1 $3 rc=$rc core=$c files=$n last=`sed -n '$p' $X/$1-$3.out`"
	while read f s; do
		if [ -f "$f" ]; then
			echo "S $1 $3 $f `sum -r $f | awk '{print $1}'` `ls -ln $f | awk '{print $1, $3, $4}'`"
		else
			echo "S $1 $3 $f missing"
		fi
	done < $D/expect
	for f in . d d/sub empty link-to-hello; do
		echo "O $1 $3 $f `ls -lnd $f 2>/dev/null | awk '{print $1, $3, $4}'`"
	done
	l=`ls -ln hard-to-hello hello 2>/dev/null | awk '{print $2}' | tr '\012' ' '`
	echo "L $1 $3 links=$l symlink=`ls -l link-to-hello 2>/dev/null | awk '{print $NF}'`"
	cd $D
}

# lt <label> <tar> <archive>: the listings
lt() {
	$2 tf $D/$3.tar > $D/t-$1-$3.tf 2>&1
	echo "T $1 $3 tf rc=$? lines=`wc -l < $D/t-$1-$3.tf`"
	$2 tvf $D/$3.tar > $D/t-$1-$3.tvf 2>&1
	echo "T $1 $3 tvf rc=$? lines=`wc -l < $D/t-$1-$3.tvf`"
}

# ct <label> <tar>: write the tree laid from ustar-named back to an archive
ct() {
	cd $X/heir-ustar-named || cd $X/stock-ustar-named || return
	$2 cf $D/c-$1.tar . > $D/c-$1.out 2>&1
	echo "C $1 rc=$? bytes=`ls -l $D/c-$1.tar | awk '{print $5}'`"
	$2 cvf $D/cv-$1.tar hello d/m6 > $D/cv-$1.out 2>&1
	echo "C $1 v rc=$?"
	cd $D
}

# padd <file> <pkginst> <log>: install as apkg does.  apkg drives the
# engine's pkgadd when the box has it; the stock pkgadd under -n ignores the
# admin file and stops at a shared path, so without the engine it gets its
# answers on stdin.
padd() {
	if [ -x /usr/apkg/bin/pkgadd ]; then
		/usr/apkg/bin/pkgadd -n -a $D/admin -d $1 $2 > $3 2>&1; rc=$?
		echo "PKGADD $2 engine rc=$rc"
	else
		(echo y; echo y; echo y; echo y) |
			/usr/sbin/pkgadd -a $D/admin -d $1 $2 > $3 2>&1; rc=$?
		echo "PKGADD $2 stock rc=$rc"
	fi
	return $rc
}

ARCH="v7 ustar-named ustar-absent ustar-empty gnu-named gnu-absent gnu-empty pax"
ulimit -c unlimited 2>/dev/null
echo "== 1 stock"
for a in $ARCH; do xt stock $D/stock-tar $a; done
for a in $ARCH; do lt stock $D/stock-tar $a; done

echo "== 2 pkgadd"
padd $D/heirtar.pkg heirtar $D/add.log
echo "RES pkgadd rc=$?"
cat $D/add.log
ls -li /usr/sbin/tar /etc/tar /etc/default/tar
echo "SUM /usr/sbin/tar `sum -r /usr/sbin/tar`"
pkgchk -l -p /usr/sbin/tar 2>&1
pkgchk -l -p /etc/tar 2>&1
pkgchk heirtar > $D/chk.log 2>&1; echo "RES pkgchk rc=$?"; cat $D/chk.log
echo "== type `type tar`"
ls -l /opt/amix/man/1/heirloom-tar /opt/amix/man/replaces.d/heirtar /opt/amix/man/whatis.d/heirtar
# with amxbase.pkg (an amix-base whose man reads replaces.d): man tar
if [ -f $D/amxbase.pkg ]; then
	padd $D/amxbase.pkg amxbase $D/base.log
	echo "RES base pkgadd rc=$?"
	pkginfo -l amxbase | grep VERSION
fi
echo "== man `type man`"
for m in "tar" "-f tar" "heirloom-tar"; do
	man $m 2>&1 | col -b | sed -n '1,6p' | sed "s/^/M $m: /"
done

echo "== 3 heirloom"
H=/usr/sbin/tar
for a in $ARCH; do xt heir $H $a; done
for a in $ARCH; do lt heir $H $a; done
# o as root, then a plain x as user bin
rm -rf "${X:?}/heir-o"; mkdir -p $X/heir-o; cd $X/heir-o
$H xof $D/gnu-absent.tar > $X/heir-o.out 2>&1
echo "X heir-o gnu-absent rc=$? own=`ls -ln hello | awk '{print $3, $4}'`"
rm -rf "${X:?}/heir-u"; mkdir -p $X/heir-u; chmod 777 $X/heir-u
su bin -c "cd $X/heir-u; $H xf $D/gnu-absent.tar" > $X/heir-u.out 2>&1
echo "X heir-u gnu-absent rc=$? own=`ls -ln $X/heir-u/hello | awk '{print $3, $4}'`"
# archive7=./tarfile in /etc/default/tar, with each tar
mkdir -p $X/seven; cd $X/seven; cp $D/v7.tar tarfile
$D/stock-tar t7 > $D/seven-stock.out 2>&1; echo "D stock t7 rc=$? lines=`wc -l < $D/seven-stock.out`"
$H t7 > $D/seven-heir.out 2>&1; echo "D heir t7 rc=$? lines=`wc -l < $D/seven-heir.out`"
cd $D
# writing: stock, Heirloom, and Heirloom without patch 03
ct stock $D/stock-tar
ct heir $H
[ -x $D/tar-no03 ] && ct no03 $D/tar-no03
# each reads the other's archive
cp $D/c-stock.tar $D/fromstock.tar; cp $D/c-heir.tar $D/fromheir.tar
xt heir $H fromstock
xt stock $D/stock-tar fromheir

echo "== 4 pkgrm"
# apkg refuses an essential package; then a plain pkgrm (heirtar has no
# removal scripts, so the stock pkgrm runs under -n)
if [ -x /usr/apkg/bin/apkg ]; then
	/usr/apkg/bin/apkg remove heirtar > $D/apkg-rm.log 2>&1
	echo "D apkg remove rc=$? `sed -n 1p $D/apkg-rm.log`"
fi
pkgrm -n -a $D/admin heirtar > $D/rm.log 2>&1
echo "RES pkgrm rc=$?"
cat $D/rm.log
ls -l /usr/sbin/tar /etc/tar 2>&1
echo "SUM /usr/sbin/tar `sum -r /usr/sbin/tar`"
pkgchk -l -p /usr/sbin/tar 2>&1
ls -d /opt/amix/doc/heirloom-tar /opt/amix/man/1/heirloom-tar 2>&1
fi

if [ "$2" = grep ] || [ "$2" = greponly ]; then
	echo "== 5 grep `type file strings egrep 2>&1 | tr '\012' ' '`"
	n=0
	find / \( -name proc -o -name dev -o -name tmp \) -prune -o -type f -print 2>/dev/null |
	while read f; do
		case `file $f 2>/dev/null` in
		*text*|*script*|*commands*)
			egrep -n '(^|[^a-zA-Z0-9_.-])tar([^a-zA-Z0-9_.-]|$)' $f /dev/null 2>/dev/null |
				sed 's/^/G /' ;;
		*executable*|*object*|*librar*)
			strings $f 2>/dev/null | egrep '(^|[ /"])tar( +-?[crtuxf]| *$)' |
				sed "s|^|B $f: |" ;;
		esac
		n=`expr $n + 1`
		case $n in *000) echo "== grep at $n files: $f" ;; esac
	done
	echo "== grep done"
fi
echo "== end"
echo done > $D/done
