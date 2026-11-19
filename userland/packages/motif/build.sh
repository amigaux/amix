# build.sh -- motif hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.

# X11R6.3 as the x11r6.3 recipe built it (BUILD_DEPENDS): its headers and
# static libraries
XBUILD="$AMIX_BUILD_ROOT/x11r6.3"
XROOT="$XBUILD/dest/opt/amix/X11R6"

# SVR4, as X11R6.3 is compiled (amix.cf's StandardDefines); the toolchain
# leaves it undefined.  select() is in libc.so.1 but no header declares it.
MOTIF_DEFS="-DSVR4"
# -fno-strict-aliasing is upstream's own (configure.ac adds it for GCC):
# Motif reads its string segments through several record types, and with
# strict aliasing GCC 14 miscompiles XmStringConcatAndFree (uil died on a
# separator).  Make's CFLAGS replaces configure's, so it is given again
# here, before the house flags (the gate wants -mno-strict-align last).
MOTIF_MAKE_CFLAGS="-fno-strict-aliasing $MOTIF_DEFS -include $AMIX_GCC14_DECLS $AMIX_CFLAGS"
# static libXt needs SM and ICE after it; LIBS ends every link line
MOTIF_MAKE_LIBS="-L$XROOT/lib -lSM -lICE -lgen -lsocket -lnsl"

# the build host's compiler, for the tools the build runs (makestrs, wml,
# wmluiltok), compiled from this tree
HOSTCC="gcc -std=gnu89 -w"

# the demos built for the smoke test only (not payload): every demo that
# needs no .uid file at build time (the UIL demos would run the target's uil
# on the build host)
DEMOS="airport drag_and_drop draw earth filemanager getsubres i18ninput panner \
	piano popups sampler2_0 setdate todo workspace tooltips ButtonBox Column \
	FontSel Outline TabStack Tree ColorSel Combo2 Ext18List IconB Paned pixmaps"

# three UIL demos, their programs only: the smoke test compiles their .uil
# files on the box with the package's uil
UILDEMOS="hellomotif periodic fileview"

# everything but demos (README: the payload)
SUBDIRS_PAYLOAD="bindings bitmaps config localized lib include tools clients doc"

build() {
	for l in Xmu Xt SM ICE Xp Xext X11; do
		[ -f "$XROOT/lib/lib$l.a" ] || { echo "[FAIL] x11r6.3 has no lib$l.a ($XROOT/lib)" >&2; exit 1; }
	done
	{
		set -x
		CC="$CC" CFLAGS="$AMIX_CFLAGS $MOTIF_DEFS" LIBS="-lgen -lsocket -lnsl" \
		LEX=false YACC=false ac_cv_prog_lex_root=lex.yy ac_cv_lib_lex="none needed" \
		ac_cv_prog_lex_yytext_pointer=yes ac_cv_func_setpgrp_void=yes lt_cv_xthreads=no \
		ac_cv_file__usr_X_include_X11_X_h=no ac_cv_file__usr_X11R6_include_X11_X_h=no \
		./configure --host="$AMIX_HOST_TRIPLET" --build="$(./config.guess)" \
			--prefix="$PREFIX" --mandir="$PREFIX/man" \
			--x-includes="$XROOT/include" --x-libraries="$XROOT/lib" \
			--disable-shared --enable-static --disable-dependency-tracking \
			--enable-printing --disable-xft --disable-jpeg --disable-png \
			--disable-utf8 --disable-themes --disable-message-catalog
	} > "$BUILD/configure.log" 2>&1 || { tail -30 "$BUILD/configure.log" >&2; echo "[FAIL] configure" >&2; exit 1; }
	# X11R6.3 is built without threads; XTHREADS changes Xlib's structures
	! grep -n 'define XTHREADS\|define XUSE_MTSAFE_API' include/config.h || {
		echo "[FAIL] config.h defines XTHREADS or XUSE_MTSAFE_API" >&2; exit 1; }
	(
		# set -e does not hold in a subshell whose status is tested: each
		# step checks itself
		set -x
		# the build's own tools, for the build host; wmluiltok is flex
		# output without a main (libfl's), so it gets a one-line one
		printf 'int yylex(void);\nint main(void) { return yylex(); }\n' > "$BUILD/flmain.c"
		$HOSTCC -c -o "$BUILD/flmain.o" "$BUILD/flmain.c" || exit 1
		hostmake() { make "CC=$HOSTCC" AR=ar RANLIB=ranlib CFLAGS= X_CFLAGS= LIBS= LDFLAGS= "$@"; }
		hostmake -C config/util makestrs || exit 1
		hostmake -C tools/wml wmluiltok_LDADD="$BUILD/flmain.o" wml wmluiltok || exit 1
		! file config/util/makestrs tools/wml/wml tools/wml/wmluiltok | grep m68k || exit 1
		# the payload's directories, in the top Makefile's order (a SUBDIRS
		# override on the command line would reach every sub-make)
		for d in $SUBDIRS_PAYLOAD; do make -C $d CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" || exit 1; done
		for d in lib/Xmd lib/Wsm; do make -C demos/$d CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" || exit 1; done
		make -C demos/lib/Exm SUBDIRS= CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" || exit 1
		for d in $DEMOS; do make -C demos/programs/$d CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" || exit 1; done
		for d in $UILDEMOS; do make -C demos/programs/$d CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" $d || exit 1; done
	) >> "$BUILD/make.log" 2>&1 || { tail -40 "$BUILD/make.log" >&2; echo "[FAIL] make" >&2; exit 1; }
}

stage() {
	( for d in $SUBDIRS_PAYLOAD; do make -C $d DESTDIR="$DEST" install || exit 1; done ) > "$BUILD/install.log" 2>&1 || {
		tail -20 "$BUILD/install.log" >&2; echo "[FAIL] make install" >&2; exit 1; }
	# libtool's .la files name the build tree and serve only libtool links
	rm -f -- "${DEST:?}${PREFIX:?}"/lib/libXm.la "${DEST:?}${PREFIX:?}"/lib/libMrm.la \
		"${DEST:?}${PREFIX:?}"/lib/libUil.la
	# the notices: Motif's licence and release notes; X11R6.3's holders (LABEL)
	# and the X Consortium notice, as mwm, uil and xmbind link X statically
	d="$DEST$PREFIX/doc/motif"
	mkdir -p "$d"
	cp COPYING README RELNOTES "$d/"
	amix_verify "$XBUILD/work/xc/LABEL" "$X11_LABEL_SHA"
	cp "$XBUILD/work/xc/LABEL" "$d/X11R6.3-LABEL"
	awk 'NR > 1 && /^\/\* *$/ { on = 1; next } on && /^\*\/$/ { exit } on' \
		"$XBUILD/work/xc/lib/X11/Xlib.h" > "$d/X11R6.3-NOTICE"
	grep -q '^Copyright (c) 1985, 1986, 1987, 1991  X Consortium$' "$d/X11R6.3-NOTICE" || {
		echo "[FAIL] Xlib.h's notice is not the X Consortium's" >&2; exit 1; }
	chmod 0644 "$d"/*
	# man pages: sections 1, 4 and 5 into /opt/amix/man (docs/man-pages.md);
	# the section-3 library pages keep upstream's names in $PREFIX/man/man3,
	# as 535 of the 695 are longer than s5's 14 bytes (README.md)
	m3="$DEST$PREFIX/man/man3" k="$BUILD/man3.keep"
	rm -rf -- "${BUILD:?}/man3.keep"
	[ -d "${m3:?}" ] && mv -- "${m3:?}" "${k:?}"
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	amix_man_whatis
	mkdir -p "$DEST$PREFIX/man"
	mv -- "${k:?}" "${m3:?}"
	find "$m3" -type f -exec chmod 0644 {} +
}

# the LABEL of X11R6.3's source, as the x11r6.3 recipe verifies it
X11_LABEL_SHA=8cc171df9c3a9a000ec23e0804c0a0c05d83c4187dec2baf2d50182f0140bf64
