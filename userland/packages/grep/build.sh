# build.sh -- grep hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

configure_args() {
	echo --disable-perl-regexp --with-included-regex --disable-largefile
}

pre_configure() {
	# The compat stdint.h (gcc14 sysroot) keeps configure's `#define
	# uintmax_t unsigned long long' while later probes include <stdint.h>;
	# the off_t probe then fails and off_t becomes a macro.  The period answer.
	export ac_cv_header_stdint_h=no
}

post_configure() {
	# the bundled regex MUST be in the link: the box has no regcomp (D8)
	grep 'regex\.o' config.status >/dev/null || {
		echo "[FAIL] regex.o is NOT in LIBOBJS: --with-included-regex slipped" >&2; exit 1; }
	echo "  regex.o is in LIBOBJS (bundled GNU regex compiled in)"
	# Amix has no <strings.h>; a HAVE_STRINGS_H means a probe read the host's
	! grep '^#define HAVE_STRINGS_H 1' config.h >/dev/null || {
		echo "[FAIL] config.h defines HAVE_STRINGS_H: a probe read the BUILD host's headers" >&2; exit 1; }
	echo "  HAVE_STRINGS_H absent (target headers were read, not the host's)"
}

make_args() {
	# strcasecmp is libamixc99's, which the specs link: nothing in LIBS
	echo LIBS=
}

post_build() {
	[ -f src/grep ] || { echo "[FAIL] grep binary not built" >&2; exit 1; }
	# egrep/fgrep exec a bare `grep'; /opt/amix/bin is not on the stock PATH
	for s in egrep fgrep; do
		sed 's|exec grep |exec /opt/amix/bin/grep |' "src/$s" > "src/$s.fixed"
		mv "src/$s.fixed" "src/$s"
		chmod 0755 "src/$s"
		echo "  $(tail -1 "src/$s")"
	done
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/man/man1" "$DEST$PREFIX/doc/grep"
	for p in grep egrep fgrep; do
		cp "src/$p" "$DEST$PREFIX/bin/$p"
		cp "doc/$p.1" "$DEST$PREFIX/man/man1/$p.1"
	done
	cp COPYING NEWS README "$DEST$PREFIX/doc/grep/"
	chmod 0755 "$DEST$PREFIX/bin"/*
	chmod 0644 "$DEST$PREFIX/man/man1"/*.1 "$DEST$PREFIX/doc/grep"/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	amix_man_whatis
}
