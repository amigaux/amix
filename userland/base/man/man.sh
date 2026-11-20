#!/bin/sh
# man -- one manual command for the add-on userland's pages and the stock ones.
#
#   man [section] name ...       one page for each name (which one: below)
#   man -a [section] name ...    both pages, when both trees have one
#   man -k keyword ...           both indexes: ours (whatis.d), then stock's
#   man -f name ...              the same, by name
#
# Which page: a command's page (sections 1, 1m, 8) is the page of the binary
# PATH runs. When a package has replaced that binary (a line for its path in
# replaces.d, below), the package's page for it is shown. Else, when that
# binary is a stock one (outside /opt/amix and /usr/amix) and the stock index
# has the name, the stock page is shown; otherwise ours. A page in any other
# section is ours when we have one. A name only one tree has is shown from
# that tree.
#
# Installed as /usr/amix/bin/man, ahead of /usr/bin on PATH. The stock
# /usr/bin/man is never changed; every name we have no page for, and every
# option we do not know, goes to it unchanged.
#
# Our pages: /opt/amix/man/<sect>/<name>, plain troff with the -man macros; an
# alias is a one-line ".so <path>" file. The index: /opt/amix/man/whatis.d/<pkg>,
# lines in the stock whatis format, read directly (nothing assembles them).
# A package that replaces a stock binary lists it in
# /opt/amix/man/replaces.d/<pkg>: "<binary path> <sect> <page name>" a line,
# "#" lines comments; its page is /opt/amix/man/<sect>/<page name>.
# Formatted pages are cached in /var/opt/amix/catman/<sect>/<name>, and only
# where the invoking user may write (root, as shipped); never in /usr/catman.
#
# MANPATH: unset or one directory, it reaches the stock man as it is (one
# into our tree is dropped, below). A colon-separated list (a CDE session's
# /usr/dt/man:/usr/share/man) is read here, since the stock man takes one
# tree: each tree is handed to it alone, the first whose whatis has the name,
# and the trees' indexes, in order, stand for the stock index.
#
# Bourne sh of 1991: no $(...), no test -nt, no local.
#
# MIT licence: /opt/amix/doc/amix-base/LICENSE (LICENSE at the top of the
# repository).

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
# /usr/catman; the stock man only ever gets its own tree. A list: MTREES
# holds its trees, ours dropped (and CATPATH with it), each once; MANPATH
# itself is unset, and each stock call gets one tree. MTREE0 is the tree
# for a call that names no page: the first with an index, else the first.
MTREES=
MTREE0=
case "${MANPATH:-}" in
*:*)
	for mt in `echo "$MANPATH" | tr ':' ' '`
	do
		case "$mt" in
		/opt/amix*|"$TREE"*)
			unset CATPATH
			;;
		*)
			case " $MTREES " in
			*" $mt "*) ;;
			*) MTREES="$MTREES $mt" ;;
			esac
			;;
		esac
	done
	unset MANPATH
	for mt in $MTREES
	do
		[ -r "$mt/whatis" ] && { MTREE0=$mt; break; }
	done
	[ -n "$MTREE0" ] || MTREE0=`echo $MTREES | awk '{ print $1 }'`
	;;
/opt/amix*|"$TREE"*)
	unset MANPATH CATPATH
	;;
esac

stock() {
	if [ -n "$MTREES" ]
	then
		MANPATH=$MTREE0
		export MANPATH
	fi
	exec "$STOCK" "$@"
}

# the sections to try: the fixed order, then any other directory in the tree
sections() {
	echo $SECTS
	for d in "$TREE"/*
	do
		s=`basename "$d"`
		case " $SECTS whatis.d replaces.d " in
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
		rm -f "${tmp:?}"
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

# replaced <binary>: "<sect> <page name>" of the page a package gives for a
# stock binary it replaced, or nothing
replaced() {
	[ -n "$1" ] || return
	cat "$TREE"/replaces.d/* 2>/dev/null |
		awk '$1 !~ /^#/ && $1 == b && NF >= 3 { print $2, $3; exit }' b="$1"
}

# whatis_sect <index> <name> <sections>: the section of the index's first
# line for <name> in one of <sections> (an egrep alternation), or nothing.
# The name pattern is the stock man's own lookup.
whatis_sect() {
	[ -r "$1" ] || return
	egrep -i "(^$2[^a-zA-Z0-9]| $2[^a-zA-Z0-9]).*-" "$1" 2>/dev/null |
		sed -n 's/^[^ 	(]*(\([^)]*\)).*/\1/p' | egrep -i "^($3)\$" |
		sed -n 1p | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

# stock_sect <name> <sections>: the same over the stock index, or with a
# MANPATH list over its trees' indexes in order
stock_sect() {
	if [ -z "$MTREES" ]
	then
		whatis_sect "$WHATIS" "$1" "$2"
		return
	fi
	for _t in $MTREES
	do
		_s=`whatis_sect "$_t/whatis" "$1" "$2"`
		[ -n "$_s" ] && { echo "$_s"; return; }
	done
}

# stock_tree <name> <sections>: the first tree of the MANPATH list whose
# index has <name> in one of <sections>, or nothing
stock_tree() {
	for _t in $MTREES
	do
		[ -n "`whatis_sect "$_t/whatis" "$1" "$2"`" ] && { echo "$_t"; return; }
	done
}

# stockrun <sect|""> <name>: the stock man for one page, as it is called
# without a list. With one, MANPATH is the first tree whose index has the
# name (in that section, else in any), else MTREE0, whose own answer is then
# "No manual entry".
stockrun() {
	if [ -z "$MTREES" ]
	then
		"$STOCK" ${1:+"$1"} "$2"
		return
	fi
	_st=
	[ -n "$1" ] && _st=`stock_tree "$2" "$1"`
	[ -n "$_st" ] || _st=`stock_tree "$2" "$ANYSECT"`
	[ -n "$_st" ] || _st=$MTREE0
	MANPATH=$_st "$STOCK" ${1:+"$1"} "$2"
}

# stockidx <-k|-f> <word ...>: the stock man's -k or -f; with a list, once
# for each tree that has an index (status 0 when one answered)
stockidx() {
	if [ -z "$MTREES" ]
	then
		"$STOCK" "$@"
		return
	fi
	_rc=1
	_n=
	for _t in $MTREES
	do
		[ -r "$_t/whatis" ] || continue
		_n=1
		MANPATH=$_t "$STOCK" "$@" && _rc=0
	done
	[ -n "$_n" ] || { MANPATH=$MTREE0 "$STOCK" "$@"; return; }
	return $_rc
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
	stockidx -k "$@"
	exit
	;;
-f)
	shift
	for n in "$@"
	do
		index "(^$n[^a-zA-Z0-9]| $n[^a-zA-Z0-9]).*-"
	done
	stockidx -f "$@"
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
	if [ $# -gt 1 ] && [ -d "$TREE/$1" ] && [ "$1" != whatis.d ] && [ "$1" != replaces.d ]
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
	# a stock binary a package replaced: that package's page (cached under
	# the page's own name, apart from another package's page for <name>)
	case "${sect:-1}" in
	1|1m|1M|8)
		rb=`which_bin "$n"`
		rp=`replaced "$rb"`
		;;
	*)
		rp=
		;;
	esac
	if [ -n "$rp" ]
	then
		set -- $rp
		if [ -z "$sect" ] || [ "$sect" = "$1" ]
		then
			hit=`find_page "$1" "$2"`
			if [ -n "$hit" ]
			then
				set -- $hit
				show "$1" "$2" "`basename "$2"`" | page
				ssect=
				[ -n "$all" ] && ssect=`stock_sect "$n" "${sect:-$CMDSECTS}"`
				if [ -n "$ssect" ]
				then
					stockrun "$ssect" "$n" || rc=1
				fi
				continue
			fi
		fi
	fi
	hit=`find_page "$sect" "$n"`
	if [ -z "$hit" ]
	then
		stockrun "$sect" "$n" || rc=1
		continue
	fi
	set -- $hit
	if stock_first "$1" "$n"
	then
		stockrun "$ssect" "$n" || rc=1
		[ -n "$all" ] && show "$1" "$2" "$n" | page
	else
		show "$1" "$2" "$n" | page
		if [ -n "$all" ] && [ -n "`stock_sect "$n" "${sect:-$ANYSECT}"`" ]
		then
			stockrun "$sect" "$n" || rc=1
		fi
	fi
done
exit $rc
