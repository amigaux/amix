# manpages.sh -- put a package's man pages where the Amix man front-end
# (the base package) and stock man(1) read them.  Sourced by a build.sh's
# stage hook; DEST and PKG are the driver's.
#
# MIT licence, see LICENSE in userland/packages.
#
# The layout (docs/man-pages.md, agreed with the base station):
#   /opt/amix/man/<sect>/<name>      the troff source, -man macros, no suffix,
#                                    plain, 0644; <name> within 14 bytes
#   /opt/amix/man/whatis.d/<PKG>     one stock whatis line per page file:
#                                    "name(sect)", padded to 16, a space,
#                                    then "names - description"
# An alias is a one-line page, ".so /opt/amix/man/<sect>/<target>".
#
#     amix_man <source> <sect> [<name>]     install a page (name: the source's
#                                           basename less its .N suffix)
#     amix_man_alias <name> <sect> <target> an alias of <sect>/<target>
#     amix_man_relayout                     move pages staged the upstream way
#                                           ($PREFIX/man/manN/x.N) into the layout
#     amix_man_whatis                       write whatis.d/<PKG> from the NAME
#                                           section of every page staged (last)

AMIX_MANDIR=/opt/amix/man

amix_man() {
	_m_name=${3:-$(basename "$1" | sed 's/\.[0-9][a-zA-Z]*$//')}
	[ ${#_m_name} -le 14 ] || { echo "[FAIL] man page name over 14 bytes: $_m_name" >&2; exit 1; }
	mkdir -p "$DEST$AMIX_MANDIR/$2"
	cp "$1" "$DEST$AMIX_MANDIR/$2/$_m_name"
	chmod 0644 "$DEST$AMIX_MANDIR/$2/$_m_name"
}

amix_man_alias() {
	[ ${#1} -le 14 ] || { echo "[FAIL] man page name over 14 bytes: $1" >&2; exit 1; }
	[ -f "$DEST$AMIX_MANDIR/$2/$3" ] || { echo "[FAIL] alias $1: no page $2/$3" >&2; exit 1; }
	mkdir -p "$DEST$AMIX_MANDIR/$2"
	echo ".so $AMIX_MANDIR/$2/$3" > "$DEST$AMIX_MANDIR/$2/$1"
	chmod 0644 "$DEST$AMIX_MANDIR/$2/$1"
}

# the NAME entry of a page for <name> ("grep, egrep \- print ..."), troff
# stripped to "grep, egrep - print ..."; a section with several entries
# (bzip2's) gives the one whose names include <name>, else the first; an
# alias takes its target's
_amix_man_desc() {
	_d_f=$1
	_d_so=$(sed -n '1s/^\.so  *//p' "$_d_f")
	[ -n "$_d_so" ] && _d_f="$DEST$_d_so"
	awk '
		/^\.SH[ \t]+"?NAME"?[ \t]*$/ { on = 1; next }
		on && /^\.(SH|SS)/ { exit }
		on && /^\./ && !/^\.(B|I|BR|IR|RB|RI|BI|IB|SM)[ \t]/ { next }
		on { sub(/^\.[A-Z][A-Z]?[ \t]+/, ""); print }
	' "$_d_f" | sed 's/\\-/-/g; s/\\f[BIRP]//g; s/\\f(..//g; s/\\(em/--/g; s/\\(lq/"/g; s/\\(rq/"/g; s/\\&//g; s/\\e/\\/g; s/"//g; s/[ 	][ 	]*/ /g; s/^ //; s/ $//' |
	awk -v name="$2" '
		/ - / { n++; e[n] = $0; split(substr($0, 1, index($0, " - ") - 1), w, /[ ,]+/)
			for (i in w) if (w[i] == name && !hit) hit = n
			next }
		n { e[n] = e[n] " " $0 }
		END { x = e[hit ? hit : 1]; sub(/ +$/, "", x); print x }'
}

amix_man_whatis() {
	_w_dir="$DEST$AMIX_MANDIR/whatis.d"
	mkdir -p "$_w_dir"
	( cd "$DEST$AMIX_MANDIR" && find . -type f ! -path './whatis.d/*' | sed 's|^\./||' | LC_ALL=C sort ) |
	while read -r _w_p; do
		_w_sect=${_w_p%%/*}; _w_name=${_w_p#*/}
		_w_desc=$(_amix_man_desc "$DEST$AMIX_MANDIR/$_w_p" "$_w_name")
		case $_w_desc in
		*" - "*) ;;
		*) echo "[FAIL] $_w_p: no \"names - description\" NAME line ($_w_desc)" >&2; exit 1 ;;
		esac
		# an alias lists its own name first
		[ -n "$(sed -n '1s/^\.so  *//p' "$DEST$AMIX_MANDIR/$_w_p")" ] &&
			_w_desc="$_w_name - ${_w_desc#* - }"
		echo "$_w_name($_w_sect) $_w_desc" | awk '{ i = index($0, " "); printf "%-16s %s\n", substr($0, 1, i - 1), substr($0, i + 1) }'
	done > "$_w_dir/$PKG" || exit 1
	chmod 0644 "$_w_dir/$PKG"
	echo "  MAN ok    $(grep -c . "$_w_dir/$PKG") page(s) under $AMIX_MANDIR, whatis.d/$PKG written"
}

# amix_man_relayout -- the pages a stage hook staged the upstream way,
# $DEST$PREFIX/man/man<N>/<name>.<N>, moved to $AMIX_MANDIR/<N>/<name>; a
# relative ".so manN/x.N" alias becomes the absolute form.  The stage hook
# then adds its own pages and aliases, and ends with amix_man_whatis.
amix_man_relayout() {
	_r_old="$DEST$PREFIX/man"
	if [ -d "$_r_old" ]; then
		for _r_d in "$_r_old"/man*; do
			[ -d "$_r_d" ] || continue
			_r_sect=${_r_d##*/man}
			for _r_f in "$_r_d"/*; do
				[ -f "$_r_f" ] || continue
				_r_name=$(basename "$_r_f" | sed 's/\.[0-9][a-zA-Z]*$//')
				_r_so=$(sed -n '1s/^\.so  *man\([0-9][a-zA-Z]*\)\/\(.*\)\.[0-9][a-zA-Z]*$/\1 \2/p' "$_r_f")
				if [ -n "$_r_so" ] && [ "$(grep -c . "$_r_f")" = 1 ]; then
					set -- $_r_so
					mkdir -p "$DEST$AMIX_MANDIR/$_r_sect"
					echo ".so $AMIX_MANDIR/$1/$2" > "$DEST$AMIX_MANDIR/$_r_sect/$_r_name"
					chmod 0644 "$DEST$AMIX_MANDIR/$_r_sect/$_r_name"
				else
					amix_man "$_r_f" "$_r_sect" "$_r_name"
				fi
				rm -f "$_r_f"
			done
			rmdir "$_r_d"
		done
		# under PREFIX=/opt/amix the upstream man dir is the new tree itself
		[ "$_r_old" = "$DEST$AMIX_MANDIR" ] || rmdir "$_r_old"
	fi
}
