# build.sh -- x11contrib hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tree is X11R6's contrib-2
# (package.sh's URL); each client is built from its programs/<name> directory
# by its Imakefile's sources and libraries, compiled and linked apart so the
# gates see each compile.

# X11R6.3 as the x11r6.3 recipe built it (BUILD_DEPENDS): its headers and
# static libraries, and its source's LABEL and Xlib.h for the notice
XBUILD="$AMIX_BUILD_ROOT/x11r6.3"
XROOT="$XBUILD/dest/opt/amix/X11R6"
X11_LABEL_SHA=8cc171df9c3a9a000ec23e0804c0a0c05d83c4187dec2baf2d50182f0140bf64
XSYSLIBS="-lSM -lICE -lXext -lX11 -lsocket -lnsl"
# the platform defines imake gives every client in the x11r6.3 tree (STD_DEFINES)
XDEFS="-DAMIX -Dm68k -DSVR4"

# cprog <name> <libs> <sources...>: programs/<name>/<name> from its sources
cprog() {
	_n=$1 _l=$2; shift 2
	_o=
	for _s in "$@"; do
		$CC $AMIX_CFLAGS $XDEFS -I"$XROOT/include" -Iprograms/$_n -c programs/$_n/$_s.c \
			-o programs/$_n/$_s.o || return 1
		_o="$_o programs/$_n/$_s.o"
	done
	$CC $AMIX_CFLAGS -o programs/$_n/$_n $_o -L"$XROOT/lib" $_l $XSYSLIBS -lm
}

build() {
	for l in Xaw Xmu Xt SM ICE Xext X11; do
		[ -f "$XROOT/lib/lib$l.a" ] || { echo "[FAIL] x11r6.3 has no lib$l.a ($XROOT/lib)" >&2; exit 1; }
	done
	{
		set -x
		cprog xeyes "-lXmu -lXt" xeyes Eyes transform &&
		cprog xedit "-lXaw -lXmu -lXt" xedit commands util
	} >> "$BUILD/make.log" 2>&1 || { tail -20 "$BUILD/make.log" >&2; echo "[FAIL] the clients did not build" >&2; exit 1; }
}

# the x11r6.3 recipe's gate: 1994 K&R code keeps its implicit-int and missing-return
# warnings, but no call without a declaration and no pointer/integer conversion
post_build() {
	! grep 'implicit declaration\|pointer from integer\|integer from pointer' "$BUILD/make.log" >/dev/null || {
		echo "[FAIL] implicit declarations or pointer/integer conversions in the build:" >&2
		grep 'implicit declaration\|pointer from integer\|integer from pointer' "$BUILD/make.log" >&2; exit 1; }
	echo "  x11contrib: no implicit declarations, no pointer/integer conversions"
}

# notice <source> <out>: a source's licence comment, from its second line
# (the first is the $XConsortium id) to the comment's end
notice() {
	awk 'NR == 1 { next } { print } /\*\/ *$/ { exit }' "$1" > "$2"
}

stage() {
	_d="$DEST$PREFIX/doc/x11contrib"
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/lib/X11/app-defaults" "$_d"
	for c in xeyes xedit; do
		cp programs/$c/$c "$DEST$PREFIX/bin/$c"
		chmod 0755 "$DEST$PREFIX/bin/$c"
	done
	cp programs/xedit/Xedit.ad "$DEST$PREFIX/lib/X11/app-defaults/Xedit"
	chmod 0644 "$DEST$PREFIX/lib/X11/app-defaults/Xedit"
	# each client's notice, as its sources carry it; X11R6.3's holders (LABEL)
	# and the X Consortium notice its libraries carry (Xlib.h's), as the
	# clients link them statically
	notice programs/xeyes/xeyes.c "$_d/xeyes-NOTICE"
	notice programs/xedit/xedit.c "$_d/xedit-NOTICE"
	grep -q '^Copyright (c) 1991  X Consortium$' "$_d/xeyes-NOTICE" || {
		echo "[FAIL] xeyes.c's notice is not the X Consortium's" >&2; exit 1; }
	grep -q 'DIGITAL EQUIPMENT CORPORATION$' "$_d/xedit-NOTICE" || {
		echo "[FAIL] xedit.c's notice is not DEC's" >&2; exit 1; }
	amix_verify "$XBUILD/work/xc/LABEL" "$X11_LABEL_SHA"
	cp "$XBUILD/work/xc/LABEL" "$_d/X11R6.3-LABEL"
	awk 'NR > 1 && /^\/\* *$/ { on = 1; next } on && /^\*\/$/ { exit } on' \
		"$XBUILD/work/xc/lib/X11/Xlib.h" > "$_d/X11R6.3-NOTICE"
	grep -q '^Copyright (c) 1985, 1986, 1987, 1991  X Consortium$' "$_d/X11R6.3-NOTICE" || {
		echo "[FAIL] Xlib.h's notice is not the X Consortium's" >&2; exit 1; }
	chmod 0644 "$_d"/*
	# man pages: /opt/amix/man/1 and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man programs/xeyes/xeyes.man 1 xeyes
	amix_man programs/xedit/xedit.man 1 xedit
	amix_man_whatis
}
