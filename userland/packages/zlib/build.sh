# build.sh -- zlib hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.

# contrib/ holds x86-only assembly; build removes it before anything runs
ASM_REVIEWED="contrib/ (x86-only, removed by the build hook, never compiled)"

OBJZ="adler32 crc32 deflate infback inffast inflate inftrees trees zutil"
OBJG="compress uncompr gzclose gzlib gzread gzwrite"

build() {
	rm -rf contrib
	echo "  removed contrib/ (x86-only asm, never built)"
	# zlib's own configure: zconf.h and the platform report only
	CC="$CC" CFLAGS="$AMIX_CFLAGS" AR="$AR" ARFLAGS="rc" RANLIB="$RANLIB" \
		./configure --static --prefix="$PREFIX" > "$BUILD/configure.log" 2>&1 || {
			echo "[FAIL] configure failed; see $BUILD/configure.log" >&2
			tail -20 "$BUILD/configure.log" >&2
			exit 1
		}
	for want in 'off64_t:No' 'fseeko:No' 'size_t:Yes'; do
		feat=${want%:*}; exp=${want#*:}
		grep "Checking for $feat\\.\\.\\. $exp\\." "$BUILD/configure.log" >/dev/null || {
			echo "[FAIL] configure did not report '$feat ... $exp': a probe reached the host's libc" >&2
			exit 1; }
		echo "  $feat ... $exp"
	done
	[ -f zconf.h ] || { echo "[FAIL] configure produced no zconf.h" >&2; exit 1; }
	# the objects, with no NO_* macro: gzprintf keeps the bounded vsnprintf path
	for o in $OBJZ $OBJG; do
		echo "$CC $AMIX_CFLAGS -c $o.c -o $o.o" >> "$BUILD/make.log"
		$CC $AMIX_CFLAGS -c "$o.c" -o "$o.o" 2>"$o.warn" || {
			echo "[FAIL] compiling $o.c" >&2; cat "$o.warn" >&2; exit 1; }
		cat "$o.warn" >> "$BUILD/make.log"
	done
	rm -f libz.a
	$AR rc libz.a $(for o in $OBJZ $OBJG; do echo "$o.o"; done)
	$RANLIB libz.a
	echo "  AR   libz.a ($(echo $OBJZ $OBJG | wc -w) objects)"
	# the on-box acceptance program
	echo "$CC $AMIX_CFLAGS -I. -o zlib-test $HERE/tests/zlib-test.c -L. -lz" >> "$BUILD/make.log"
	$CC $AMIX_CFLAGS -I. -o zlib-test "$HERE/tests/zlib-test.c" -L. -lz >> "$BUILD/make.log" 2>&1 || {
		echo "[FAIL] zlib-test did not link" >&2; tail -20 "$BUILD/make.log" >&2; exit 1; }
}

post_build() {
	undef=$($NM libz.a 2>/dev/null | awk '$1=="U"{print $2}' | sort -u)
	for sym in vsnprintf snprintf; do
		echo "$undef" | grep "^$sym\$" >/dev/null || {
			echo "[FAIL] libz.a does NOT reference $sym: gzprintf fell back to unbounded vsprintf" >&2
			exit 1; }
		echo "  libz.a references $sym (the bounded path)"
	done
	! echo "$undef" | grep -E '^(vsprintf|_doprnt)$' >/dev/null ||
		echo "[WARN] libz.a also references vsprintf/_doprnt" >&2
}

stage() {
	mkdir -p "$DEST$PREFIX/lib" "$DEST$PREFIX/include" "$DEST$PREFIX/bin" \
		"$DEST$PREFIX/man/man3" "$DEST$PREFIX/doc/zlib"
	cp libz.a "$DEST$PREFIX/lib/libz.a"
	cp zlib.h zconf.h "$DEST$PREFIX/include/"
	cp zlib-test "$DEST$PREFIX/bin/zlib-test"
	cp zlib.3 "$DEST$PREFIX/man/man3/zlib.3"
	cp LICENSE README ChangeLog "$DEST$PREFIX/doc/zlib/"
	chmod 0644 "$DEST$PREFIX/lib/libz.a" "$DEST$PREFIX/include"/*.h \
		"$DEST$PREFIX/man/man3/zlib.3" "$DEST$PREFIX/doc/zlib"/*
	chmod 0755 "$DEST$PREFIX/bin/zlib-test"
}
