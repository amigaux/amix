#!/bin/sh
# l11-seed.sh <pkginst> <path> ... -- run by install.sh (l11_base) under the target's chroot,
# before pkgadd of <pkginst>. A conffile whose size and sum still match its contents record is
# unedited, so its baseline is seeded and the conffile class takes the new default silently; any
# other is left alone (kept, with a .new). The install step of amix userland/base/docs/package-split.md,
# as first tried on a box; the 4.0 mkdir -p fails on a
# directory that exists, so the directory is made only when it is missing.
pkg=$1
shift
C=/var/sadm/install/contents
for p
do
	if [ ! -f "$p" ]
	then
		echo "$p: absent"
		continue
	fi
	r=`grep "^$p f " $C`
	if [ -z "$r" ]
	then
		echo "$p: no f record"
		continue
	fi
	set -- $r
	size=$7
	rsum=$8
	set -- `sum "$p"`
	s=$1
	set -- `wc -c < "$p"`
	z=$1
	if [ "$s" = "$rsum" ] && [ "$z" = "$size" ]
	then
		b=/var/sadm/conffiles/$pkg$p
		d=`dirname "$b"`
		[ -d "$d" ] || mkdir -p "$d"
		cp "$p" "$b" && echo "$p: stock ($z $s), baseline seeded"
	else
		echo "$p: edited ($z $s, record $size $rsum), left"
	fi
done
