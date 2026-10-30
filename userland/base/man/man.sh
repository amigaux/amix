#!/bin/sh
# man -- one manual command for the add-on userland's pages and the stock ones.
#
#   man [section] name ...       one page for each name (which one: below)
#   man -a [section] name ...    both pages, when both trees have one
#   man -k keyword ...           both indexes: ours (whatis.d), then stock's
#   man -f name ...              the same, by name
#
# Which page: a command's page (sections 1, 1m, 8) is the page of the binary
# PATH runs. When that binary is a stock one (outside /opt/amix and
# /usr/amix) and the stock index has the name, the stock page is shown;
# otherwise ours. A page in any other section is ours when we have one. A
# name only one tree has is shown from that tree.
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
WHATIS=${AMIX_STOCKWHATIS:-/usr/share/man/whatis}
OURBIN=${AMIX_OURBIN:-}
[ -n "$OURBIN" ] || OURBIN="/opt/amix/ /usr/amix/"
SECTS="1 1m 8 2 3 4 5 6 7"
# egrep alternations over the stock index's sections: the command sections,
# and any (kept in variables: the 1991 sh misparses them inside ${...:-...})
CMDSECTS='1[a-z]*|8'
ANYSECT='[^)]*'

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

# which_bin <name>: the file PATH runs for <name>, or nothing
which_bin() {
	for wb in `echo "$PATH" | sed -e 's/^:/.:/' -e 's/::/:.:/g' -e 's/:$/:./' -e 's/:/ /g'`
	do
		if [ -f "$wb/$1" ] && [ -x "$wb/$1" ]
		then
			echo "$wb/$1"
			return
		fi
	done
}

# stock_sect <name> <sections>: the section of the stock index's first line
# for <name> in one of <sections> (an egrep alternation), or nothing. The
# name pattern is the stock man's own lookup.
stock_sect() {
	[ -r "$WHATIS" ] || return
	egrep -i "(^$1[^a-zA-Z0-9]| $1[^a-zA-Z0-9]).*-" "$WHATIS" 2>/dev/null |
		sed -n 's/^[^ 	(]*(\([^)]*\)).*/\1/p' | egrep -i "^($2)\$" |
		sed -n 1p | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

# stock_first <our sect> <name>: show the stock page before ours? If so,
# the section to ask the stock man for is left in ssect.
stock_first() {
	case "$1" in
	1|1m|1M|8) ;;
	*) return 1 ;;
	esac
	sb=`which_bin "$2"`
	[ -n "$sb" ] || return 1
	for sp in $OURBIN
	do
		case "$sb" in
		"$sp"*) return 1 ;;
		esac
	done
	ssect=`stock_sect "$2" "${sect:-$CMDSECTS}"`
	[ -n "$ssect" ]
}

page() {
	if [ -t 1 ]
	then
		${PAGER:-/usr/bin/more}
	else
		cat
	fi
}

all=
case "${1:-}" in
"")
	stock
	;;
-a)
	all=1
	shift
	[ $# -gt 0 ] || stock
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
	if [ -z "$hit" ]
	then
		"$STOCK" ${sect:+"$sect"} "$n" || rc=1
		continue
	fi
	set -- $hit
	if stock_first "$1" "$n"
	then
		"$STOCK" "$ssect" "$n" || rc=1
		[ -n "$all" ] && show "$1" "$2" "$n" | page
	else
		show "$1" "$2" "$n" | page
		if [ -n "$all" ] && [ -n "`stock_sect "$n" "${sect:-$ANYSECT}"`" ]
		then
			"$STOCK" ${sect:+"$sect"} "$n" || rc=1
		fi
	fi
done
exit $rc
