# build.sh -- less hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

EXTRA_CFLAGS=-DUSE_TERMCAP

configure_args() {
	# HAVE_STAT must be on, or every struct stat is incomplete
	echo ac_cv_func_stat=yes
}

pre_configure() {
	# less ships its sources read-only (mode 444)
	chmod -R u+w .
	export LDFLAGS="-L$AMIX_SYSROOT/usr/ccs/lib"
	export LIBS="-lc"
}

post_configure() {
	# the SVR4 regcmp backend, via libgen, is the one the box provides
	grep -E 'regular expression library:[[:space:]]*regcmp' "$BUILD/configure.log" >/dev/null || {
		echo "[FAIL] configure did not pick the regcmp regex backend:" >&2
		grep -iE 'regular expression|regcmp' "$BUILD/configure.log" >&2
		exit 1
	}
	echo "  regex: regcmp (libgen)"
	grep -E 'terminal libraries\.\.\. using -lcurses' "$BUILD/configure.log" >/dev/null || {
		echo "[FAIL] configure did not pick -lcurses for termcap" >&2; exit 1; }
	echo "  terminal library: -lcurses (termcap API)"
	grep '^#define HAVE_STAT 1' defines.h >/dev/null || {
		echo "[FAIL] HAVE_STAT is not defined" >&2; exit 1; }
	echo "  HAVE_STAT 1"
	# the real link set, ending in -lc; LIBSAN (-lasan -lubsan) goes, the
	# target has no sanitizers
	sed -i 's/^LIBS = .*/LIBS = -lgen -lcurses -lc/' Makefile
	grep '^LIBS = -lgen -lcurses -lc$' Makefile >/dev/null || {
		echo "[FAIL] Makefile LIBS not set" >&2; exit 1; }
}

make_args() {
	echo LIBSAN=
}

post_build() {
	for b in less lesskey lessecho; do
		[ -f "$b" ] || { echo "[FAIL] $b not built" >&2; exit 1; }
	done
	# 'makes pointer' is a GCC 2.7 spelling of an int/pointer conversion
	! grep 'makes pointer' "$BUILD/make.log" >/dev/null || {
		echo "[FAIL] pointer/integer conversions in the build" >&2; exit 1; }
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/man/man1" "$DEST$PREFIX/doc/less"
	for b in less lesskey lessecho; do
		cp "$b" "$DEST$PREFIX/bin/$b"
		cp "$b.man" "$DEST$PREFIX/man/man1/$b.1"
	done
	cp LICENSE COPYING NEWS "$DEST$PREFIX/doc/less/"
	chmod 0755 "$DEST$PREFIX/bin"/*
	chmod 0644 "$DEST$PREFIX/man/man1"/*.1 "$DEST$PREFIX/doc/less"/*
}
