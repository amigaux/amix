# build.sh -- xztop hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tree is the git archive of
# amix-z3660rtg at kernel/drivers/z3660rtg/z3660rtg.pin (FORKPIN).

# the variant pkgbuild builds: static, or shared (prototype.shared)
XZ_VARIANT=${VARIANT:-shared}
G14TOOLS=${AMIX_GCC14_PREFIX:+$AMIX_GCC14_PREFIX/../../tools}

# X11R6.3 as the x11r6.3 recipe built it (BUILD_DEPENDS): its headers and
# libraries, and its source's LABEL and Xlib.h for the notice; the shared
# variant links x11r6.3's shared build (x11r6.3-shared)
XBUILD="$AMIX_BUILD_ROOT/x11r6.3"
[ "$XZ_VARIANT" = shared ] && XBUILD="$AMIX_BUILD_ROOT/x11r6.3-shared"
XROOT="$XBUILD/dest/opt/amix/X11R6"
# the libraries to link: the staged archives; for the shared variant the X
# build tree's exports/lib, whose .so links are relative (the staged ones name
# the box), with X's library path in the program and libXtInherit.a (as
# x11r6.3's own shared clients: the program's own _XtInherit, ahead of
# libXt's; x11r6.3's xtinherit.c says why)
XLIBDIR="$XROOT/lib"
XZ_LDFLAGS=
XZ_LIBEXT=a
if [ "$XZ_VARIANT" = shared ]; then
	XLIBDIR="$XBUILD/work/xc/exports/lib"
	XZ_LDFLAGS="-Wl,-rpath,/opt/amix/X11R6/lib -Wl,-rpath-link,$XLIBDIR -Wl,-u,_XtInherit -L$XLIBDIR -lXtInherit"
	XZ_LIBEXT=so
fi
X11_LABEL_SHA=8cc171df9c3a9a000ec23e0804c0a0c05d83c4187dec2baf2d50182f0140bf64
ZZ9K=overlay/usr/sys/amiga/driver/zz9000

build() {
	echo "  xztop: the $XZ_VARIANT variant"
	for l in Xaw Xmu Xt SM ICE Xext X11; do
		[ -f "$XLIBDIR/lib$l.$XZ_LIBEXT" ] || { echo "[FAIL] x11r6.3 has no lib$l.$XZ_LIBEXT ($XLIBDIR)" >&2; exit 1; }
	done
	[ "$XZ_VARIANT" != shared ] || [ -f "$XLIBDIR/libXtInherit.a" ] || {
		echo "[FAIL] x11r6.3 has no libXtInherit.a ($XLIBDIR)" >&2; exit 1; }
	# the fork's x11/xztop/Makefile line, compile and link apart so the
	# gates see the compile
	{
		set -x
		$CC $AMIX_CFLAGS -I"$XROOT/include" -I"$ZZ9K" -c x11/xztop/xztop.c -o xztop.o
		$CC $AMIX_CFLAGS -o xztop xztop.o $XZ_LDFLAGS -L"$XLIBDIR" \
			-lXaw -lXmu -lXt -lSM -lICE -lXext -lX11 -lsocket -lnsl
	} >> "$BUILD/make.log" 2>&1 || { tail -20 "$BUILD/make.log" >&2; echo "[FAIL] xztop did not build" >&2; exit 1; }
}

post_build() {
	! grep 'warning:' "$BUILD/make.log" >/dev/null || {
		echo "[FAIL] xztop compiled with warnings" >&2; grep 'warning:' "$BUILD/make.log" >&2; exit 1; }
	echo "  xztop warning-clean"
	[ "$XZ_VARIANT" = shared ] || return 0
	# the shared variant: dynamic, its library names first in .dynstr
	# (gcc14-cross-amix tools/check-dynstr-order.py), no text relocations, its
	# own _XtInherit, and X's libraries found at run time
	"$READELF" -d xztop | grep -q 'NEEDED.*libXt\.so' || { echo "[FAIL] xztop: not linked against the shared libXt" >&2; exit 1; }
	! "$READELF" -d xztop | grep -q TEXTREL || { echo "[FAIL] xztop: text relocations (DT_TEXTREL)" >&2; exit 1; }
	"$READELF" -d xztop | grep -q 'RPATH.*\[/opt/amix/X11R6/lib\]' || { echo "[FAIL] xztop: no DT_RPATH /opt/amix/X11R6/lib" >&2; exit 1; }
	"$READELF" -W --dyn-syms xztop | awk '$8 == "_XtInherit" && $7 != "UND" { f = 1 } END { exit !f }' || {
		echo "[FAIL] xztop: no _XtInherit of its own" >&2; exit 1; }
	python3 -I "$G14TOOLS/check-dynstr-order.py" xztop > "$BUILD/dynstr.log" 2>&1 || {
		tail -20 "$BUILD/dynstr.log" >&2; echo "[FAIL] check-dynstr-order" >&2; exit 1; }
	echo "  xztop: dynamic, own _XtInherit, no text relocations, dynstr order clean"
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/doc/xztop"
	cp xztop "$DEST$PREFIX/bin/xztop"
	chmod 0755 "$DEST$PREFIX/bin/xztop"
	# the fork's licence and notice; X11R6.3's holders (LABEL) and the X
	# Consortium notice its libraries carry (Xlib.h's, the same in Xt, Xaw,
	# Xmu, SM, ICE and Xext): the static xztop links them, the shared one
	# loads them; both variants ship them
	cp LICENSE "$DEST$PREFIX/doc/xztop/LICENSE"
	cp NOTICE "$DEST$PREFIX/doc/xztop/NOTICE"
	amix_verify "$XBUILD/work/xc/LABEL" "$X11_LABEL_SHA"
	cp "$XBUILD/work/xc/LABEL" "$DEST$PREFIX/doc/xztop/X11R6.3-LABEL"
	awk 'NR > 1 && /^\/\* *$/ { on = 1; next } on && /^\*\/$/ { exit } on' \
		"$XBUILD/work/xc/lib/X11/Xlib.h" > "$DEST$PREFIX/doc/xztop/X11R6.3-NOTICE"
	grep -q '^Copyright (c) 1985, 1986, 1987, 1991  X Consortium$' "$DEST$PREFIX/doc/xztop/X11R6.3-NOTICE" || {
		echo "[FAIL] Xlib.h's notice is not the X Consortium's" >&2; exit 1; }
	chmod 0644 "$DEST$PREFIX/doc/xztop"/*
	# man page: /opt/amix/man/1/xztop and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man x11/xztop/xztop.1 1
	amix_man_whatis
}
