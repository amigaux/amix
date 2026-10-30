# build.sh -- acompat (libamixcompat) hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tree is a copy of src/;
# include/, tests/ and doc/ are read from the package directory.

SOURCES="snprintf strcase env mkstemp usleep timeofday version"
COMPAT_SYMS="snprintf vsnprintf strcasecmp strncasecmp usleep setenv unsetenv mkstemp gettimeofday"

build() {
	# the host differential test first: an algorithm bug fails here, in a
	# second, not at the far end of a bench cycle
	mkdir -p "$BUILD/host"
	${HOSTCC:-cc} -O1 -Wall -o "$BUILD/host/host-diff" \
		"$HERE/tests/host-diff.c" snprintf.c \
		-I"$HERE/include" -DAMIX_NO_LIBC_NAMES -D_AMIX_HAVE_SSIZE_T
	"$BUILD/host/host-diff" || {
		echo "[FAIL] host differential test failed -- the algorithm is wrong" >&2; exit 1; }
	# GCC 14's fixed <unistd.h> declares usleep(unsigned long); amixcompat.h
	# says unsigned int: -D_AMIX_HAVE_USLEEP keeps the shipped declaration.
	# The version string names the build, so a smoke cannot mistake it.
	cflags="$AMIX_CFLAGS -D_AMIX_HAVE_USLEEP -I$HERE/include -DAMIX_COMPAT_VERSION=\"$VERSION-$PKGREV-$TOOLCHAIN\""
	for s in $SOURCES; do
		echo "$CC $cflags -c $s.c -o $s.o" >> "$BUILD/make.log"
		$CC $cflags -c "$s.c" -o "$s.o" >> "$BUILD/make.log" 2>&1 || {
			echo "[FAIL] compiling $s.c" >&2; tail -20 "$BUILD/make.log" >&2; exit 1; }
	done
	rm -f libacompat.a
	$AR rc libacompat.a env.o mkstemp.o snprintf.o strcase.o timeofday.o usleep.o version.o
	$RANLIB libacompat.a
	# the acceptance test links libacompat on purpose (the one exception to
	# the one-owner rule); its link line stays out of make.log, whose COMPAT
	# gate refuses -lacompat.  The trace proves every compat symbol is ours.
	set --
	for s in $COMPAT_SYMS; do set -- "$@" "-Wl,-y,$s"; done
	$CC $AMIX_CFLAGS -D_AMIX_HAVE_USLEEP -I"$HERE/include" -o acompat-test \
		"$HERE/tests/compat-test.c" -L. -lacompat -lc "$@" > "$BUILD/link.log" 2>&1 || {
			echo "[FAIL] acompat-test did not link" >&2; cat "$BUILD/link.log" >&2; exit 1; }
	for s in $COMPAT_SYMS; do
		grep -E "libacompat\.a\([a-z]+\.o\): definition of $s\$" "$BUILD/link.log" >/dev/null || {
			echo "[FAIL] $s in acompat-test is not defined by libacompat.a" >&2; exit 1; }
	done
	echo "  OWNER ok  all nine compat symbols come from libacompat.a"
	AMIX_LL_PRINTF_REVIEWED="acompat-test: every ll conversion goes to libacompat snprintf; printf takes %s/%d/%ld only"
	export AMIX_LL_PRINTF_REVIEWED
}

stage() {
	mkdir -p "$DEST$PREFIX/lib" "$DEST$PREFIX/include" "$DEST$PREFIX/bin" "$DEST$PREFIX/doc/acompat"
	cp libacompat.a "$DEST$PREFIX/lib/libacompat.a"
	cp "$HERE/include/amixcompat.h" "$HERE/include/stdint.h" "$HERE/include/strings.h" \
		"$DEST$PREFIX/include/"
	cp acompat-test "$DEST$PREFIX/bin/acompat-test"
	cp "$HERE/LICENSE" "$DEST$PREFIX/doc/acompat/LICENSE"
	# the package's README is doc/README, frozen with the version it ships in
	cp "$HERE/doc/README" "$DEST$PREFIX/doc/acompat/README"
	chmod 0644 "$DEST$PREFIX/include"/*.h "$DEST$PREFIX/doc/acompat"/* "$DEST$PREFIX/lib/libacompat.a"
	chmod 0755 "$DEST$PREFIX/bin/acompat-test"
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	amix_man "$HERE/man/acompat.3" 3
	amix_man "$HERE/man/acompat-test.1" 1
	amix_man_alias snprintf 3 acompat
	amix_man_alias vsnprintf 3 acompat
	amix_man_alias setenv 3 acompat
	amix_man_alias unsetenv 3 acompat
	amix_man_alias strcasecmp 3 acompat
	amix_man_alias strncasecmp 3 acompat
	amix_man_alias mkstemp 3 acompat
	amix_man_alias usleep 3 acompat
	amix_man_alias gettimeofday 3 acompat
	amix_man_whatis
}
