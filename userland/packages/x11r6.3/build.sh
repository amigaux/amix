# build.sh -- X11R6.3 hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.

ASM_REVIEWED="other platforms' .s files (xfree86, cfb/stip*); none is in an AMIX build"

# the Amiga screen manager (amiga/screen.h, libscreen.so) and libdbm, from the
# stock /usr/amiga and /usr/ucblib: the sysroot links to them but lacks them
AMIX_USR_AMIGA=${AMIX_USR_AMIGA:-$AMIX_SYSROOT/usr}

# the clients built and shipped, beside the libraries and the server
XCLIENTS="xinit xdm twm xterm xclock xdpyinfo xwd xwud xset xsetroot xmodmap xrdb
	xlsfonts xhost xauth iceauth xprop xkill xlsclients xwininfo xkbcomp mkfontdir bdftopcf
	smproxy rstart"

# compiled with -fno-jump-tables, these files only: a GCC 14 switch table in each that
# scan060-g14 (the D4 gate) cannot size, though the code bounds it
XNOJT="lib/font/bitmap/bdfutils.c	bdfSpecialProperty: the bound is on the index before a shift
	lib/Xtst/XTest.c		send_axes: a signed compare before the unsigned bound, table via %an
	programs/xdm/dm.c		WaitForChild: the same shape
	lib/font/Speedo/do_trns.c	sp_proc_outl_data: the index is a byte's high nibble, sign case away
	lib/font/Type1/type1.c		Decode: the bound is set on the only path into the dispatch block
	programs/Xserver/cfb/cfbglblt8.c	cfbPolyGlyphBlt8: the glyph-bit group's switch, bounded by its mask"

xmake() {	# xmake <log> <make args...>: make -k, every compile line into make.log by xcc
	_xm_log=$1; shift
	_xm_rc=0; make -k "$@" > "$BUILD/$_xm_log" 2>&1 < /dev/null || _xm_rc=$?
	echo "  X: $* rc=$_xm_rc"
}

build() {
	# xc-2: the fonts (and docs); xc-3 is hardcopy docs only and is not fetched
	. "$COMMON/fetch.sh"
	amix_fetch https://www.x.org/archive/X11R6.3/tars/xc-2.tar.gz \
		cb9e6725a6f10b345c3dea417821d79a0738c09da0a16fe6b14b2ade878dcb8d "$SRC/xc-2.tar.gz" \
		"https://github.com/amigaux/amix-distfiles/releases/download/$NAME-$VERSION/xc-2.tar.gz" || exit 1
	tar xzf "$SRC/xc-2.tar.gz" -C .. || exit 1
	chmod -R u+w .	# the tarball's modes are read-only
	[ -f "$AMIX_USR_AMIGA/amiga/include/amiga/screen.h" ] && [ -f "$AMIX_USR_AMIGA/amiga/lib/libscreen.so" ] &&
		[ -f "$AMIX_USR_AMIGA/ucblib/libdbm.a" ] || {
		echo "[FAIL] no amiga/include/amiga/screen.h, amiga/lib/libscreen.so and ucblib/libdbm.a" >&2
		echo "       under AMIX_USR_AMIGA=$AMIX_USR_AMIGA (the stock /usr/amiga and /usr/ucblib)" >&2
		exit 1
	}
	# only <amiga/...> from /usr/amiga/include: it also holds an assert.h of its own
	mkdir -p "$BUILD/ainc" && ln -sfn "$AMIX_USR_AMIGA/amiga/include/amiga" "$BUILD/ainc/amiga"
	# the compiler: gcc14, the C library and amix-decls.h force-included, every line logged
	_nojt=$(echo "$XNOJT" | awk -v t="$(pwd -P)" '{printf " %s/%s", t, $1}')
	cat > "$BUILD/xcc" <<XCC
#!/bin/sh
_xf=
for _a in "\$@"; do
	case "\$_a" in *.c) case "$_nojt " in *" \$(realpath -m -- "\$_a") "*) _xf=-fno-jump-tables ;; esac ;; esac
done
echo "$CC -std=gnu89 -fcommon -I$BUILD/ainc -include $HERE/amix-xlibc.h -include $AMIX_GCC14_DECLS \$* \$_xf $AMIX_CFLAGS $AMIX_ARCH_FLAGS" >> "$BUILD/make.log"
exec $CC -std=gnu89 -fcommon -I$BUILD/ainc -include $HERE/amix-xlibc.h -include $AMIX_GCC14_DECLS "\$@" \$_xf $AMIX_CFLAGS $AMIX_ARCH_FLAGS 2>> "$BUILD/make.log"
XCC
	chmod +x "$BUILD/xcc"
	# config files (xinitrc, Xsession, ...) go through a plain host cpp, without xcc's headers
	printf '#!/bin/sh\nexec /usr/bin/cpp -traditional -undef -DAMIX -DSVR4 -Dm68k -Dunix "$@"\n' > "$BUILD/xcpp"
	chmod +x "$BUILD/xcpp"
	_b=$(dirname "$AR")
	sed -e "s|@XCC@|$BUILD/xcc|g" -e "s|@XCPP@|$BUILD/xcpp|g" -e "s|@AR@|$AR|g" -e "s|@RANLIB@|$RANLIB|g" -e "s|@AS@|$_b/$AMIX_TARGET-as|g" \
		-e "s|@LD@|$LD|g" -e "s|@PREFIX@|$PREFIX|g" -e "s|@SYSROOT@|$AMIX_SYSROOT|g" -e "s|@USRAMIGA@|$AMIX_USR_AMIGA|g" \
		"$HERE/host.def.in" > config/cf/host.def
	# build-time tools the tree runs on the build host
	( cd config/imake && make -f Makefile.ini BOOTSTRAPCFLAGS="-DAMIX -DSVR4 -Dm68k" CC="gcc -std=gnu89 -fcommon -w" imake ) > "$BUILD/x-imake.log" 2>&1 || {
		echo "[FAIL] host imake; see $BUILD/x-imake.log" >&2; exit 1; }
	export IMAKECPP="$HERE/imakecpp.sh"
	make Makefile BOOTSTRAPCFLAGS="-DAMIX -DSVR4 -Dm68k" > "$BUILD/x-makefile.log" 2>&1 &&
	make -f xmakefile Makefiles > "$BUILD/x-makefiles.log" 2>&1 || {
		echo "[FAIL] imake Makefiles; see $BUILD/x-makefile*.log" >&2; exit 1; }
	mkdir -p "$BUILD/hinc" && ln -sfn "$PWD/include" "$BUILD/hinc/X11"
	_hcc="gcc -std=gnu89 -fcommon -w -I$BUILD/hinc"
	( cd config/util && $_hcc -c makestrs.c && $_hcc -o makestrs makestrs.o ) &&
	$_hcc -o "$BUILD/makekeys" lib/X11/util/makekeys.c && "$BUILD/makekeys" < include/keysymdef.h > lib/X11/ks_tables.h || {
		echo "[FAIL] host makestrs/makekeys" >&2; exit 1; }
	echo "  X: host imake, makestrs, makekeys (ks_tables.h)"
	make -f xmakefile includes > "$BUILD/x-includes.log" 2>&1 || {
		echo "[FAIL] make includes; see $BUILD/x-includes.log" >&2; exit 1; }
	hostx
	xmake x-lib.log -C lib
	xmake x-server.log -C programs/Xserver
	for c in $XCLIENTS; do
		[ -f programs/$c/Makefile ] || ( cd programs/$c && ../../config/imake/imake -I../../config/cf \
			-DTOPDIR=../.. -DCURDIR=programs/$c ) > "$BUILD/x-$c-imake.log" 2>&1
		if [ $c = xrdb ]; then
			# xrdb runs a cpp on the box: the stock /usr/ccs/lib/cpp, not the build's
			xmake x-$c.log -C programs/$c 'CPP=/usr/ccs/lib/cpp $(STD_CPP_DEFINES)'
		else
			xmake x-$c.log -C programs/$c
		fi
	done
	echo "  X: strict counts: $(grep -c 'implicit declaration' "$BUILD/make.log") implicit," \
		"$(grep -c 'pointer from integer\|integer from pointer' "$BUILD/make.log") pointer/integer," \
		"$(grep -c ' error: ' "$BUILD/make.log") errors"
}

# hostx: this tree's xkbcomp, bdftopcf and mkfontdir for the build host, the install
# steps' own tools (the xkb .dir listings, the fonts), never the host's X install.
# A copy of the configured tree before the cross compile, built with the host cc
# (patches/host/: glibc's stdio is not constant); LONG64, since R6.3's font code
# assumes 32-bit longs otherwise; the font side keeps -DAMIX -Dm68k (servermd.h:
# the target's MSB-first glyphs) and drops the host's own `linux' (its LSB block).
hostx() {
	HX="$BUILD/hostxc"
	rm -rf -- "${HX:?}"; mkdir -p "$HX/programs/Xserver"
	tar cf - --exclude=./fonts --exclude=./doc --exclude=./programs/Xserver . | (cd "$HX" && tar xf -)
	cp -R programs/Xserver/include "${HX:?}/programs/Xserver/"
	for _hp in "$HERE"/patches/host/*.patch; do
		( cd "$HX" && patch -p1 --batch --fuzz=0 < "$_hp" ) > /dev/null || {
			echo "[FAIL] host patch $(basename "$_hp")" >&2; exit 1; }
	done
	_hxcc="gcc -std=gnu89 -fcommon -fpermissive -w -D_GNU_SOURCE -DLONG64"
	( set -e
		for _d in lib/xkbfile lib/Xext lib/X11; do
			make -C "$HX/$_d" "CC=$_hxcc" 'AR=ar cq' RANLIB=ranlib STD_DEFINES= EXTRA_LIBRARIES=
		done
		make -C "$HX/lib/font" "CC=$_hxcc -Ulinux" 'AR=ar cq' RANLIB=ranlib \
			'STD_DEFINES=-DAMIX -Dm68k' EXTRA_LIBRARIES=
		make -C "$HX/programs/xkbcomp" "CC=$_hxcc" STD_DEFINES= EXTRA_LIBRARIES= LDPOSTLIB= xkbcomp
		for _p in bdftopcf mkfontdir; do
			make -C "$HX/programs/$_p" "CC=$_hxcc -Ulinux" 'STD_DEFINES=-DAMIX -Dm68k' \
				EXTRA_LIBRARIES= LDPOSTLIB= $_p
		done
	) > "$BUILD/x-hostx.log" 2>&1 < /dev/null || {
		echo "[FAIL] the build-host xkbcomp/bdftopcf/mkfontdir; see $BUILD/x-hostx.log" >&2; exit 1; }
	echo "  X: build-host xkbcomp, bdftopcf, mkfontdir from this tree"
}

xinst() {	# xinst <log> <dir> <targets...>: an imake install into the payload
	_xi_log=$1 _xi_dir=$2; shift 2
	make -C "$_xi_dir" DESTDIR="$DEST" "$@" > "$BUILD/$_xi_log" 2>&1 < /dev/null &&
	! grep -E 'Usage: install|install: |No such file|cannot (stat|create)|Error [0-9]' "$BUILD/$_xi_log" > /dev/null || {
		echo "[FAIL] install in $_xi_dir; see $BUILD/$_xi_log" >&2; exit 1; }
}

stage() {
	xinst i-include.log include install
	xinst i-lib.log lib install
	xinst i-nls.log nls install
	xinst i-server.log programs/Xserver install install.man
	# X is Xzz9000 under its usual name: a hard link (stock pkgadd mangles a relative symlink)
	rm -f -- "${DEST:?}${PREFIX:?}/bin/X" && ln "$DEST$PREFIX/bin/Xzz9000" "$DEST$PREFIX/bin/X"
	# the XIE and PEX client libraries: their extensions are not built
	rm -f -- "${DEST:?}${PREFIX:?}/lib/libXIE.a" "${DEST:?}${PREFIX:?}/lib/libPEX5.a"
	for c in $XCLIENTS; do
		# xkbcomp's data dirs index themselves with xkbcomp -lfhlpR (hostx's), and
		# rstart's contexts give remote commands the man pages' home after the relayout
		xinst i-$c.log programs/$c install install.man XKBCOMPCMD="$BUILD/hostxc/programs/xkbcomp/xkbcomp" \
			DEFAULT_X_MANPATH=/opt/amix/man:/usr/share/man
	done
	# rstart's aliases (x, x11 for x11r6) are relative symlinks: the stock pkgadd
	# mangles those, so they point at their absolute targets
	for l in $(cd "$DEST" && find ".$PREFIX" -type l); do
		_t=$(readlink "$DEST/$l"); case $_t in /*) continue;; esac
		rm -- "${DEST:?}/${l:?}" && ln -s "$(dirname "${l#.}")/$_t" "$DEST/$l"
	done
	# fonts: compiled and indexed by hostx's bdftopcf and mkfontdir
	for f in misc 75dpi 100dpi; do
		xinst i-font-$f.log fonts/bdf/$f install FONTC="$BUILD/hostxc/programs/bdftopcf/bdftopcf" \
			MKFONTDIR="$BUILD/hostxc/programs/mkfontdir/mkfontdir"
	done
	mkdir -p "$DEST$PREFIX/lib/X11"
	cp programs/rgb/rgb.txt "$DEST$PREFIX/lib/X11/rgb.txt"
	# the system profile drop-in and the /usr/X11R6 link (prototype)
	mkdir -p "$DEST/etc/profile.d" "$DEST/usr"
	cp "$HERE/etc/x11r63.sh" "$DEST/etc/profile.d/x11r63.sh"
	chmod 0444 "$DEST/etc/profile.d/x11r63.sh"
	ln -s "$PREFIX" "$DEST/usr/X11R6"
	echo "  staged: $(cd "$DEST" && find . -type f | wc -l) files"
	# the notices: COPYRIGHT from this tree's compiled sources and fonts,
	# LICENSE (ours), LICENSE.ddx (patch 00's)
	mkdir -p "$DEST$PREFIX/doc/x11r63"
	python3 -I "$HERE/notices.py" "$PWD" > "$DEST$PREFIX/doc/x11r63/COPYRIGHT" || {
		echo "[FAIL] notices.py" >&2; exit 1; }
	cp "$HERE/../LICENSE" "$DEST$PREFIX/doc/x11r63/LICENSE"
	cp "$HERE/LICENSE.ddx" "$DEST$PREFIX/doc/x11r63/LICENSE.ddx"
	chmod 0644 "$DEST$PREFIX/doc/x11r63/COPYRIGHT" "$DEST$PREFIX/doc/x11r63/LICENSE" \
		"$DEST$PREFIX/doc/x11r63/LICENSE.ddx"
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	# Xzz9000 (and X, its link): our own page.  The DDX's Xamix page is the R5
	# Xsun page with the names swapped, and there is no Xamix command
	rm -f -- "${DEST:?}/opt/amix/man/1/Xamix"
	amix_man "$HERE/man/Xzz9000.1" 1
	amix_man "$HERE/man/x11r63.sh.4" 4 x11r63.sh
	amix_man_whatis
}
