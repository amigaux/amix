# build.sh -- x11contrib hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tree is X11R6's contrib-2
# (package.sh's URL); each client is built from its programs/<name> directory
# by its Imakefile's sources and libraries, compiled and linked apart so the
# gates see each compile.

# the variant pkgbuild builds: static, or shared (prototype.shared)
XC_VARIANT=${VARIANT:-shared}
G14TOOLS=${AMIX_GCC14_PREFIX:+$AMIX_GCC14_PREFIX/../../tools}

# X11R6.3 as the x11r6.3 recipe built it (BUILD_DEPENDS): its headers and
# libraries, and its source's LABEL and Xlib.h for the notice; the shared
# variant links x11r6.3's shared build (x11r6.3-shared)
XBUILD="$AMIX_BUILD_ROOT/x11r6.3"
[ "$XC_VARIANT" = shared ] && XBUILD="$AMIX_BUILD_ROOT/x11r6.3-shared"
XROOT="$XBUILD/dest/opt/amix/X11R6"
# the libraries to link: the staged archives; for the shared variant the X
# build tree's exports/lib, whose .so links are relative (the staged ones name
# the box), with X's library path in the programs and libXtInherit.a (as
# x11r6.3's own shared clients: every program its own _XtInherit, ahead of
# libXt's; x11r6.3's xtinherit.c says why)
XLIBDIR="$XROOT/lib"
XC_LDFLAGS=
XC_LIBEXT=a
if [ "$XC_VARIANT" = shared ]; then
	XLIBDIR="$XBUILD/work/xc/exports/lib"
	XC_LDFLAGS="-Wl,-rpath,$PREFIX/lib -Wl,-rpath-link,$XLIBDIR -Wl,-u,_XtInherit -L$XLIBDIR -lXtInherit"
	XC_LIBEXT=so
fi
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
	$CC $AMIX_CFLAGS -o programs/$_n/$_n $_o $XC_LDFLAGS -L"$XLIBDIR" $_l $XSYSLIBS -lm
}

build() {
	echo "  x11contrib: the $XC_VARIANT variant"
	for l in Xaw Xmu Xt SM ICE Xext X11; do
		[ -f "$XLIBDIR/lib$l.$XC_LIBEXT" ] || { echo "[FAIL] x11r6.3 has no lib$l.$XC_LIBEXT ($XLIBDIR)" >&2; exit 1; }
	done
	[ "$XC_VARIANT" != shared ] || [ -f "$XLIBDIR/libXtInherit.a" ] || {
		echo "[FAIL] x11r6.3 has no libXtInherit.a ($XLIBDIR)" >&2; exit 1; }
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
	[ "$XC_VARIANT" = shared ] || return 0
	# the shared variant: each program dynamic, its library names first in
	# .dynstr (gcc14-cross-amix tools/check-dynstr-order.py), no text
	# relocations, its own _XtInherit, and X's libraries found at run time
	_p="programs/xeyes/xeyes programs/xedit/xedit"
	for _f in $_p; do
		"$READELF" -d "$_f" | grep -q 'NEEDED.*libXt\.so' || { echo "[FAIL] $_f: not linked against the shared libXt" >&2; exit 1; }
		! "$READELF" -d "$_f" | grep -q TEXTREL || { echo "[FAIL] $_f: text relocations (DT_TEXTREL)" >&2; exit 1; }
		"$READELF" -d "$_f" | grep -q "RPATH.*\[$PREFIX/lib\]" || { echo "[FAIL] $_f: no DT_RPATH $PREFIX/lib" >&2; exit 1; }
		"$READELF" -W --dyn-syms "$_f" | awk '$8 == "_XtInherit" && $7 != "UND" { f = 1 } END { exit !f }' || {
			echo "[FAIL] $_f: no _XtInherit of its own" >&2; exit 1; }
	done
	python3 -I "$G14TOOLS/check-dynstr-order.py" $_p > "$BUILD/dynstr.log" 2>&1 || {
		tail -20 "$BUILD/dynstr.log" >&2; echo "[FAIL] check-dynstr-order" >&2; exit 1; }
	echo "  x11contrib: xeyes, xedit dynamic, own _XtInherit, no text relocations, dynstr order clean"
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
	# and the X Consortium notice its libraries carry (Xlib.h's): the static
	# clients link them, the shared ones load them; both variants ship them
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
