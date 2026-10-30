#!/bin/sh
# man -- one manual command for the add-on userland's pages and the stock ones.
#
#   man [section] name ...       our page if we have one, else the stock page
#   man -k keyword ...           both indexes: ours (whatis.d), then stock's
#   man -f name ...              the same, by name
#
# Installed as /usr/amix/bin/man, ahead of /usr/bin on PATH. The stock
# /usr/bin/man is never changed; every name we have no page for, and every
# option we do not know, goes to it unchanged.
#
# Our pages: /opt/amix/man/<sect>/<name>, plain troff with the -man macros; an
# alias is a one-line ".so <path>" file. The index: /opt/amix/man/whatis.d/<pkg>,
# lines in the stock whatis format, read directly (nothing assembles them).
# Formatted pages are cached in /var/opt/amix/catman/<sect>/<name>, and only
# where the invoking user may write (root, as shipped); never in /usr/catman.
#
# Bourne sh of 1991: no $(...), no test -nt, no local.
#
# MIT licence, see LICENSE at the top of the repository.

TREE=${AMIX_MANTREE:-/opt/amix/man}
CATS=${AMIX_CATTREE:-/var/opt/amix/catman}
STOCK=${AMIX_STOCKMAN:-/usr/bin/man}
NROFF=${AMIX_NROFF:-/usr/ucb/nroff}
TBL=${AMIX_TBL:-/usr/ucb/tbl}
EQN=${AMIX_EQN:-/usr/ucb/eqn}
SECTS="1 1m 8 2 3 4 5 6 7"

# A MANPATH aimed at our tree would make the stock man cache our pages in
# /usr/catman; the stock man only ever gets its own tree.
case "${MANPATH:-}" in
/opt/amix*|"$TREE"*)
	unset MANPATH CATPATH
	;;
esac

stock() {
	exec "$STOCK" "$@"
}

# the sections to try: the fixed order, then any other directory in the tree
sections() {
	echo $SECTS
	for d in "$TREE"/*
	do
		s=`basename "$d"`
		case " $SECTS whatis.d " in
		*" $s "*) ;;
		*) [ -d "$d" ] && echo "$s" ;;
		esac
	done
}

# find <sect|""> <name>: print "<sect> <file>" of our page, or nothing
find_page() {
	if [ -n "$1" ]
	then
		[ -f "$TREE/$1/$2" ] && echo "$1 $TREE/$1/$2"
		return
	fi
	for s in `sections`
	do
		if [ -f "$TREE/$s/$2" ]
		then
			echo "$s $TREE/$s/$2"
			return
		fi
	done
}

# format <file>: the formatted page on stdout, by the stock man's pipeline.
# A ".so" alias formats its target; a relative one is read from the tree top.
format() {
	f=$1
	t=`sed -n '1s/^\.so[ 	][ 	]*//p' "$f"`
	if [ -n "$t" ]
	then
		case "$t" in
		/*) f=$t ;;
		*) f=$TREE/$t ;;
		esac
	fi
	(cd "$TREE" && "$TBL" "$f" | "$EQN" | "$NROFF" -man -T37 | col)
}

# show <sect> <file> <name>: from the cache when it is current, else format
# (and cache, where allowed)
show() {
	c=$CATS/$1/$3
	if [ -f "$c" ] && [ -z "`find "$2" -newer "$c" -print 2>/dev/null`" ]
	then
		cat "$c"
		return
	fi
	if [ -d "$CATS/$1" ] && [ -w "$CATS/$1" ]
	then
		tmp=$CATS/$1/T$$
		if format "$2" > "$tmp" && [ -s "$tmp" ]
		then
			mv "$tmp" "$c"
			cat "$c"
			return
		fi
		rm -f "$tmp"
	fi
	format "$2"
}

# index <egrep pattern>: our whatis lines that match
index() {
	cat "$TREE"/whatis.d/* 2>/dev/null | egrep -i "$1"
}

page() {
	if [ -t 1 ]
	then
		${PAGER:-/usr/bin/more}
	else
		cat
	fi
}

case "${1:-}" in
"")
	stock
	;;
-k)
	shift
	for k in "$@"
	do
		index "$k"
	done
	"$STOCK" -k "$@"
	exit
	;;
-f)
	shift
	for n in "$@"
	do
		index "(^$n[^a-zA-Z0-9]| $n[^a-zA-Z0-9]).*-"
	done
	"$STOCK" -f "$@"
	exit
	;;
-*)
	stock "$@"
	;;
esac

# a first argument naming one of our section directories, or looking like a
# section (a digit first), is the section
sect=
case "$1" in
[0-9]*)
	sect=$1
	shift
	;;
*)
	if [ $# -gt 1 ] && [ -d "$TREE/$1" ] && [ "$1" != whatis.d ]
	then
		sect=$1
		shift
	fi
	;;
esac
[ $# -gt 0 ] || stock ${sect:+"$sect"}

rc=0
for n in "$@"
do
	hit=`find_page "$sect" "$n"`
	if [ -n "$hit" ]
	then
		set -- $hit
		show "$1" "$2" "$n" | page
	else
		"$STOCK" ${sect:+"$sect"} "$n" || rc=1
	fi
done
exit $rc
