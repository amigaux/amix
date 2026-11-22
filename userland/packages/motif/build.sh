# build.sh -- motif hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.

# the variant pkgbuild builds: static, or shared (prototype.shared)
MOTIF_VARIANT=${VARIANT:-static}
G14TOOLS=${AMIX_GCC14_PREFIX:+$AMIX_GCC14_PREFIX/../../tools}

# X11R6.3 as the x11r6.3 recipe built it (BUILD_DEPENDS): its headers and
# static libraries; the shared variant links x11r6.3's shared build (x11r6.3-shared)
XBUILD="$AMIX_BUILD_ROOT/x11r6.3"
[ "$MOTIF_VARIANT" = shared ] && XBUILD="$AMIX_BUILD_ROOT/x11r6.3-shared"
XROOT="$XBUILD/dest/opt/amix/X11R6"
# the libraries to link: the staged ones; for the shared variant the X build
# tree's exports/lib, whose .so links are relative (the staged ones name the box)
XLIBDIR="$XROOT/lib"
[ "$MOTIF_VARIANT" = shared ] && XLIBDIR="$XBUILD/work/xc/exports/lib"
# the shared variant: libtool's shared libraries beside the static ones, and
# the path of X's and Motif's libraries in every program and library
MOTIF_LIBKIND="--disable-shared --enable-static"
MOTIF_LDFLAGS=
MOTIF_RXLIB=
MOTIF_NOJT_SHARED=
if [ "$MOTIF_VARIANT" = shared ]; then
	MOTIF_LIBKIND="--enable-shared --enable-static"
	# every program its own _XtInherit, ahead of libXt's (x11r6.3-shared's
	# libXtInherit.a, its xtinherit.c says why): a stopgap for the stock runtime linker
	MOTIF_LDFLAGS="-Wl,-rpath,$PREFIX/lib:/opt/amix/lib -Wl,-rpath-link,$XLIBDIR -Wl,-u,_XtInherit -L$XLIBDIR -lXtInherit"
	# POSIX regcomp from the regex package's libregex.so.1 (BUILD_DEPENDS): Amix's
	# libc has none, and the fallback, libgen's regcmp, exists only static and
	# non-PIC, so it would put text relocations into libXm.so
	RXROOT="$AMIX_BUILD_ROOT/regex/dest/opt/amix"
	MOTIF_RXLIB="-lregex"
	# compiled without jump tables in the PIC build only: a switch whose bound is
	# compared in memory and its index reloaded before the jump, a shape the
	# 68060 gate's scan060-g14 cannot size (_XmICCCallbackToICCEvent,
	# CalcNextLocationCursor); the static build's tables size
	MOTIF_NOJT_SHARED="DragICC Container"
fi

# SVR4, as X11R6.3 is compiled (amix.cf's StandardDefines); the toolchain
# leaves it undefined.  select() is in libc.so.1 but no header declares it.
MOTIF_DEFS="-DSVR4"
[ -z "$MOTIF_RXLIB" ] || MOTIF_DEFS="$MOTIF_DEFS -I$RXROOT/include"
# -fno-strict-aliasing is upstream's own (configure.ac adds it for GCC):
# Motif reads its string segments through several record types, and with
# strict aliasing GCC 14 miscompiles XmStringConcatAndFree (uil died on a
# separator).  Make's CFLAGS replaces configure's, so it is given again
# here, before the house flags (the gate wants -mno-strict-align last).
MOTIF_MAKE_CFLAGS="-fno-strict-aliasing $MOTIF_DEFS -include $AMIX_GCC14_DECLS $AMIX_CFLAGS"
# static libXt needs SM and ICE after it; LIBS ends every link line
MOTIF_MAKE_LIBS="-L$XLIBDIR -lSM -lICE -lgen -lsocket -lnsl${MOTIF_RXLIB:+ $MOTIF_RXLIB}"

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
	_xk=a; [ "$MOTIF_VARIANT" = shared ] && _xk=so
	for l in Xmu Xt SM ICE Xp Xext X11; do
		[ -f "$XLIBDIR/lib$l.$_xk" ] || { echo "[FAIL] X11R6.3 has no lib$l.$_xk ($XLIBDIR)" >&2; exit 1; }
	done
	# the shared variant's rpath (and rpath-link), for every link configure writes
	[ -z "$MOTIF_LDFLAGS" ] || export LDFLAGS="$MOTIF_LDFLAGS"
	# libtool knows SVR4 shared libraries by host vendor, and `cbm' is not in its
	# table: its answer for the vendors it knows, pass_all, keeps each library's
	# dependency libraries in the link (else libXm.so records none)
	# and libtool's own -lc would link the static-only parts of libc (select,
	# syslog) into the library: the driver's -shared links libamixrt for those
	if [ "$MOTIF_VARIANT" = shared ]; then
		export lt_cv_deplibs_check_method=pass_all lt_cv_archive_cmds_need_lc=no ac_cv_func_regcomp=yes
		# libregex.so for the link: the staged .so link names the box's path
		mkdir -p "$BUILD/shlib"
		ln -sf "$RXROOT/lib/libregex.so.1" "$BUILD/shlib/libregex.so.1"
		ln -sf "$RXROOT/lib/libregex.so.1" "$BUILD/shlib/libregex.so"
		export LDFLAGS="$LDFLAGS -L$BUILD/shlib -Wl,-rpath-link,$BUILD/shlib"
	fi
	{
		set -x
		CC="$CC" CFLAGS="$AMIX_CFLAGS $MOTIF_DEFS" LIBS="-lgen -lsocket -lnsl${MOTIF_RXLIB:+ $MOTIF_RXLIB}" \
		LEX=false YACC=false ac_cv_prog_lex_root=lex.yy ac_cv_lib_lex="none needed" \
		ac_cv_prog_lex_yytext_pointer=yes ac_cv_func_setpgrp_void=yes lt_cv_xthreads=no \
		ac_cv_file__usr_X_include_X11_X_h=no ac_cv_file__usr_X11R6_include_X11_X_h=no \
		./configure --host="$AMIX_HOST_TRIPLET" --build="$(./config.guess)" \
			--prefix="$PREFIX" --mandir="$PREFIX/man" \
			--x-includes="$XROOT/include" --x-libraries="$XLIBDIR" \
			$MOTIF_LIBKIND --disable-dependency-tracking \
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
		# makestrs includes <X11/Xos.h>: X11R6.3's, as the build host
		# need have no X headers (the build container has none)
		hostmake -C config/util CPPFLAGS="-I$XROOT/include" makestrs || exit 1
		hostmake -C tools/wml wmluiltok_LDADD="$BUILD/flmain.o" wml wmluiltok || exit 1
		! file config/util/makestrs tools/wml/wml tools/wml/wmluiltok | grep m68k || exit 1
		# the payload's directories, in the top Makefile's order (a SUBDIRS
		# override on the command line would reach every sub-make)
		for d in $SUBDIRS_PAYLOAD; do make -C $d CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" || exit 1; done
		# the shared variant: two files' switch tables again without jump tables
		# (MOTIF_NOJT_SHARED), libXm relinked, and the payload's programs with it
		if [ -n "$MOTIF_NOJT_SHARED" ]; then
			for o in $MOTIF_NOJT_SHARED; do
				rm -f -- "lib/Xm/${o:?}.lo" "lib/Xm/${o:?}.o" "lib/Xm/.libs/${o:?}.o"
			done
			make -C lib/Xm CFLAGS="-fno-jump-tables $MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" \
				$(for o in $MOTIF_NOJT_SHARED; do echo "$o.lo"; done) || exit 1
			for d in $SUBDIRS_PAYLOAD; do make -C $d CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" || exit 1; done
		fi
		for d in lib/Xmd lib/Wsm; do make -C demos/$d CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" || exit 1; done
		make -C demos/lib/Exm SUBDIRS= CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" || exit 1
		for d in $DEMOS; do make -C demos/programs/$d CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" || exit 1; done
		for d in $UILDEMOS; do make -C demos/programs/$d CFLAGS="$MOTIF_MAKE_CFLAGS" LIBS="$MOTIF_MAKE_LIBS" $d || exit 1; done
	) >> "$BUILD/make.log" 2>&1 || { tail -40 "$BUILD/make.log" >&2; echo "[FAIL] make" >&2; exit 1; }
	# the shared variant: no PIC object may hold sym+N@GOT, which ld links to sym
	# (gcc14-cross-amix tools/check-got-addend.py); libtool keeps them in .libs
	if [ "$MOTIF_VARIANT" = shared ]; then
		_po=$(find lib -path '*/.libs/*.o' | LC_ALL=C sort)
		[ -n "$_po" ] || { echo "[FAIL] the shared variant built no PIC objects" >&2; exit 1; }
		python3 -I "$G14TOOLS/check-got-addend.py" $_po > "$BUILD/got-addend.log" 2>&1 || {
			tail -20 "$BUILD/got-addend.log" >&2; echo "[FAIL] check-got-addend" >&2; exit 1; }
		echo "  check-got-addend: $(echo "$_po" | wc -l) PIC objects clean"
	fi
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
	# the shared variant: every shared library and dynamic program has its library
	# names first in .dynstr (gcc14-cross-amix tools/check-dynstr-order.py)
	if [ "$MOTIF_VARIANT" = shared ]; then
		# the SVR4 layout for libtool's libraries: the file a program NEEDs (the soname,
		# libfoo.so.N) is the library itself and libfoo.so the one link to it, as
		# libc.so.1; libtool's libfoo.so.N.M.K name goes (the harness and the stock
		# pkgadd both want the NEEDED name to be a file)
		for _f in $(cd "$DEST$PREFIX/lib" && ls lib*.so.*.* 2>/dev/null); do
			[ -f "$DEST$PREFIX/lib/$_f" ] && [ ! -L "$DEST$PREFIX/lib/$_f" ] || continue
			_sn=$("$READELF" -d "$DEST$PREFIX/lib/$_f" | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p')
			[ -n "$_sn" ] && [ "$_sn" != "$_f" ] || continue
			rm -f -- "${DEST:?}${PREFIX:?}/lib/${_sn:?}"
			mv -- "$DEST$PREFIX/lib/$_f" "$DEST$PREFIX/lib/$_sn"
			_b=${_sn%%.so.*}.so
			rm -f -- "${DEST:?}${PREFIX:?}/lib/${_b:?}"
			ln -s "$PREFIX/lib/$_sn" "$DEST$PREFIX/lib/$_b"
		done
		# libtool's .so links are relative: the stock pkgadd mangles those, so
		# they point at their absolute targets
		for _l in $(cd "$DEST" && find ".$PREFIX/lib" -type l); do
			_t=$(readlink "$DEST/$_l"); case $_t in /*) continue;; esac
			rm -- "${DEST:?}/${_l:?}" && ln -s "$(dirname "${_l#.}")/$_t" "$DEST/$_l"
		done
		_dy=$(cd "$DEST" && find . -type f \( -name '*.so.*' -o -perm -u+x \) | while read -r _f; do
			"$READELF" -d "$DEST/$_f" 2>/dev/null | grep -q NEEDED && echo "$DEST/$_f"; done | LC_ALL=C sort)
		[ -n "$_dy" ] || { echo "[FAIL] the shared variant staged no dynamic objects" >&2; exit 1; }
		python3 -I "$G14TOOLS/check-dynstr-order.py" $_dy > "$BUILD/dynstr.log" 2>&1 || {
			tail -20 "$BUILD/dynstr.log" >&2; echo "[FAIL] check-dynstr-order" >&2; exit 1; }
		# and no text relocations: a shared library's text must stay shared
		_tr=$(for _f in $_dy; do "$READELF" -d "$_f" | grep -q TEXTREL && echo "$_f"; done; :)
		[ -z "$_tr" ] || { echo "[FAIL] text relocations (DT_TEXTREL) in:" $_tr >&2; exit 1; }
		echo "  check-dynstr-order: $(echo "$_dy" | wc -l) dynamic objects clean"
	fi
}

# the LABEL of X11R6.3's source, as the x11r6.3 recipe verifies it
X11_LABEL_SHA=8cc171df9c3a9a000ec23e0804c0a0c05d83c4187dec2baf2d50182f0140bf64
