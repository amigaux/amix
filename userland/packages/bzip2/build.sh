# build.sh -- bzip2 hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

# The library and the two programs; never `all', whose `test' target runs
# the cross-built bzip2 on the host.  CFLAGS from the driver replaces the
# Makefile's -D_FILE_OFFSET_BITS=64 (no large files on AMIX).
make_args() {
	echo libbz2.a bzip2 bzip2recover
}

post_build() {
	grep -- '_FILE_OFFSET_BITS' "$BUILD/make.log" >/dev/null && {
		echo "[FAIL] -D_FILE_OFFSET_BITS reached the build" >&2; exit 1; }
	echo "  no _FILE_OFFSET_BITS (32-bit off_t, as AMIX)"
}

stage() {
	b="$DEST$PREFIX/bin"; m="$DEST$PREFIX/man/man1"; d="$DEST$PREFIX/doc/bzip2"
	mkdir -p "$b" "$m" "$d" "$DEST$PREFIX/lib" "$DEST$PREFIX/include"
	cp bzip2 bzip2recover bzgrep bzmore bzdiff "$b/"
	# the prototype makes these hard links (l): stock pkgadd mangles a
	# relative symlink target (docs/porting.md 7)
	ln "$b/bzip2" "$b/bunzip2"; ln "$b/bzip2" "$b/bzcat"
	ln "$b/bzgrep" "$b/bzegrep"; ln "$b/bzgrep" "$b/bzfgrep"
	ln "$b/bzmore" "$b/bzless"; ln "$b/bzdiff" "$b/bzcmp"
	cp libbz2.a "$DEST$PREFIX/lib/"
	cp bzlib.h "$DEST$PREFIX/include/"
	cp bzip2.1 bzgrep.1 bzmore.1 bzdiff.1 "$m/"
	echo ".so man1/bzgrep.1" > "$m/bzegrep.1"
	echo ".so man1/bzgrep.1" > "$m/bzfgrep.1"
	echo ".so man1/bzmore.1" > "$m/bzless.1"
	echo ".so man1/bzdiff.1" > "$m/bzcmp.1"
	cp LICENSE README CHANGES "$d/"
	chmod 0755 "$b"/*
	chmod 0644 "$DEST$PREFIX/lib/libbz2.a" "$DEST$PREFIX/include/bzlib.h" "$m"/* "$d"/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	amix_man_alias bunzip2 1 bzip2
	amix_man_alias bzcat 1 bzip2
	amix_man_alias bzip2recover 1 bzip2
	amix_man_whatis
}

# fchmod is in libc.so.1 but no AMIX header declares it (amix-decls.h)
EXTRA_CFLAGS="-include $AMIX_GCC14_DECLS"
