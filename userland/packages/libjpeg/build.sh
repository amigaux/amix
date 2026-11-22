# build.sh -- libjpeg hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

# transupp.c (jpegtran's transforms) is compiled with -fno-jump-tables: its
# three GCC 14 switch tables have backward entries that the 68060 gate's
# scan060.py cannot size, so it lost step in the stripped jpegtran
# (README.md).  The other files keep their tables.
NOJT="transupp.o"

build() {
	{
		set -x
		CC="$CC" CPP="$AMIX_CPP" CFLAGS="$AMIX_CFLAGS $AMIX_CONFIGURE_LENIENT" \
		./configure --host="$AMIX_HOST_TRIPLET" --prefix="$PREFIX" --mandir="$PREFIX/man" \
			--enable-static --enable-shared --disable-ld-version-script --disable-dependency-tracking --disable-silent-rules
	} > "$BUILD/configure.log" 2>&1 || { tail -20 "$BUILD/configure.log" >&2; echo "[FAIL] configure" >&2; exit 1; }
	{
		make CFLAGS="-fno-jump-tables $AMIX_CFLAGS" $NOJT && make CFLAGS="$AMIX_CFLAGS"
	} >> "$BUILD/make.log" 2>&1 || { tail -30 "$BUILD/make.log" >&2; echo "[FAIL] make" >&2; exit 1; }
	# the shared library's gates (gcc14-cross-amix tools): no sym+N@GOT in its PIC
	# objects (libtool keeps them in .libs), its names first in .dynstr, no text
	# relocations
	_t=$AMIX_GCC14_PREFIX/../../tools
	_so=$(ls .libs/libjpeg.so.*.*.* | head -1)
	python3 -I "$_t/check-got-addend.py" .libs/*.o > "$BUILD/got-addend.log" 2>&1 &&
	python3 -I "$_t/check-dynstr-order.py" "$_so" > "$BUILD/dynstr.log" 2>&1 &&
	! "$READELF" -d "$_so" | grep TEXTREL || {
		cat "$BUILD/got-addend.log" "$BUILD/dynstr.log" >&2; echo "[FAIL] shared library gates" >&2; exit 1; }
	echo "  SO   $(basename "$_so"): check-got-addend, check-dynstr-order, no TEXTREL"
}

stage() {
	make DESTDIR="$DEST" install > "$BUILD/install.log" 2>&1 || {
		tail -20 "$BUILD/install.log" >&2; echo "[FAIL] make install" >&2; exit 1; }
	# libtool's .la names the build tree and serves only libtool links
	rm -f -- "${DEST:?}${PREFIX:?}/lib/libjpeg.la"
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
	# libtool's .so links are relative: the stock pkgadd mangles those
	for _l in $(cd "$DEST" && find ".$PREFIX/lib" -type l); do
		_t=$(readlink "$DEST/$_l"); case $_t in /*) continue;; esac
		rm -- "${DEST:?}/${_l:?}" && ln -s "$(dirname "${_l#.}")/$_t" "$DEST/$_l"
	done
	# a pkg-config file, for a tool Amix does not have
	rm -f -- "${DEST:?}${PREFIX:?}/lib/pkgconfig/libjpeg.pc"; rmdir -- "${DEST:?}${PREFIX:?}/lib/pkgconfig"
	d="$DEST$PREFIX/doc/libjpeg"
	mkdir -p "$d"
	cp README change.log libjpeg.txt usage.txt "$d/"
	chmod 0644 "$d"/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	amix_man_whatis
}
