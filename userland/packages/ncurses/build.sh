# build.sh -- ncurses hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

configure_args() {
	echo --without-shared --with-normal --without-debug --without-ada \
		--without-cxx-binding --without-progs --without-tests --without-manpages \
		--disable-widec --disable-big-core --with-fallbacks= --disable-db-install \
		--with-default-terminfo-dir=/usr/share/lib/terminfo \
		--with-terminfo-dirs=/usr/share/lib/terminfo --with-build-cc=gcc
}

pre_configure() {
	# AMIX's twalk takes void (*)(void *, VISIT, int), POSIX const void *: the
	# tsearch cache would not compile strict; ncurses keeps its own list instead
	export ac_cv_func_tsearch=no
}

post_configure() {
	! grep '^#define HAVE_TSEARCH 1' include/ncurses_cfg.h >/dev/null || {
		echo "[FAIL] HAVE_TSEARCH is set (ac_cv_func_tsearch did not reach configure)" >&2; exit 1; }
	echo "  HAVE_TSEARCH unset (ncurses' own tparm cache)"
}

stage() {
	make DESTDIR="$DEST" install.libs install.includes > /dev/null
	# ncurses6-config is a build-host helper (it names the build's flags), not payload
	rm -f "$DEST$PREFIX/bin/ncurses6-config"; rmdir "$DEST$PREFIX/bin"
	mkdir -p "$DEST$PREFIX/doc/ncurses"
	cp COPYING NEWS README "$DEST$PREFIX/doc/ncurses/"
	chmod 0644 "$DEST$PREFIX"/lib/*.a "$DEST$PREFIX"/include/ncurses/*.h "$DEST$PREFIX"/doc/ncurses/*
}

# select is in libc.so.1 but no AMIX header declares it (amix-decls.h)
MAKE_CFLAGS="-include $AMIX_GCC14_DECLS"
