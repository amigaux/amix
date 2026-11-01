# build.sh -- xztop hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tree is the git archive of
# amix-z3660rtg at kernel/drivers/z3660rtg/z3660rtg.pin (FORKPIN).

# X11R6.3 as the x11r6.3 recipe built it (BUILD_DEPENDS): its headers and
# static libraries, and its source's LABEL and Xlib.h for the notice
XBUILD="$AMIX_BUILD_ROOT/x11r6.3"
XROOT="$XBUILD/dest/opt/amix/X11R6"
X11_LABEL_SHA=8cc171df9c3a9a000ec23e0804c0a0c05d83c4187dec2baf2d50182f0140bf64
ZZ9K=overlay/usr/sys/amiga/driver/zz9000

build() {
	for l in Xaw Xmu Xt SM ICE Xext X11; do
		[ -f "$XROOT/lib/lib$l.a" ] || { echo "[FAIL] x11r6.3 has no lib$l.a ($XROOT/lib)" >&2; exit 1; }
	done
	# the fork's x11/xztop/Makefile line, compile and link apart so the
	# gates see the compile
	{
		set -x
		$CC $AMIX_CFLAGS -I"$XROOT/include" -I"$ZZ9K" -c x11/xztop/xztop.c -o xztop.o
		$CC $AMIX_CFLAGS -o xztop xztop.o -L"$XROOT/lib" \
			-lXaw -lXmu -lXt -lSM -lICE -lXext -lX11 -lsocket -lnsl
	} >> "$BUILD/make.log" 2>&1 || { tail -20 "$BUILD/make.log" >&2; echo "[FAIL] xztop did not build" >&2; exit 1; }
}

post_build() {
	! grep 'warning:' "$BUILD/make.log" >/dev/null || {
		echo "[FAIL] xztop compiled with warnings" >&2; grep 'warning:' "$BUILD/make.log" >&2; exit 1; }
	echo "  xztop warning-clean"
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/doc/xztop"
	cp xztop "$DEST$PREFIX/bin/xztop"
	chmod 0755 "$DEST$PREFIX/bin/xztop"
	# the fork's licence and notice; X11R6.3's holders (LABEL) and the X
	# Consortium notice its libraries carry (Xlib.h's, the same in Xt, Xaw,
	# Xmu, SM, ICE and Xext), as xztop links them statically
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
