# build.sh -- libzz9k hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tree is a copy of src/ with patches/
# applied; tests/ and man/ are read from the package directory, the zz9ksvc interface
# header (sys/zz9ksvc.h) from kernel/modules in this checkout, zlib from its build.

ZL="$AMIX_BUILD_ROOT/zlib/dest$PREFIX"
ZZSVC="$REPO/kernel/modules/zz9ksvc/include"
HEADERS="amix host abi crypto text compression"

build() {
	# the host test first: the library against kernel/modules' zz9ksvc and its stand-in
	# runtimes, in seconds
	sh "$HERE/tests/hosttest.sh" > "$BUILD/hosttest.log" 2>&1 || {
		tail -20 "$BUILD/hosttest.log" >&2
		echo "[FAIL] the host test failed; log $BUILD/hosttest.log" >&2
		exit 1; }
	sed 's/^/  /' "$BUILD/hosttest.log"
	[ -f "$ZL/lib/libz.a" ] || {
		echo "[FAIL] no $ZL/lib/libz.a: build zlib first (BUILD_DEPENDS)" >&2; exit 1; }
	[ -f "$ZZSVC/sys/zz9ksvc.h" ] || { echo "[FAIL] no $ZZSVC/sys/zz9ksvc.h" >&2; exit 1; }
	cflags="$AMIX_CFLAGS -DZZ9K_HOST_AMIX=1 -Iinclude -I$ZZSVC -I$ZL/include"
	# a section per function: a program linked with -Wl,--gc-sections keeps only the
	# SDK calls it makes (zz9k_host.c is the whole host API in one file)
	for s in zz9k_host zz9k_amix; do
		echo "$CC $cflags -ffunction-sections -fdata-sections -c $s.c -o $s.o" >> "$BUILD/make.log"
		$CC $cflags -ffunction-sections -fdata-sections -c "$s.c" -o "$s.o" >> "$BUILD/make.log" 2>&1 || {
			echo "[FAIL] compiling $s.c" >&2; tail -20 "$BUILD/make.log" >&2; exit 1; }
	done
	rm -f libzz9k.a
	$AR rc libzz9k.a zz9k_host.o zz9k_amix.o
	$RANLIB libzz9k.a
	echo "  AR   libzz9k.a ($(wc -c < libzz9k.a) bytes)"
	# the on-box check, linked against exactly this archive
	echo "$CC $cflags -DLIBZZ9K_VERSION=\"$VERSION-$PKGREV\" -o zz9k-test zz9k-test.c -Wl,--gc-sections -L. -lzz9k -L$ZL/lib -lz" >> "$BUILD/make.log"
	$CC $cflags -DLIBZZ9K_VERSION="\"$VERSION-$PKGREV\"" -o zz9k-test zz9k-test.c \
		-Wl,--gc-sections -L. -lzz9k -L"$ZL/lib" -lz >> "$BUILD/make.log" 2>&1 || {
		echo "[FAIL] zz9k-test did not link" >&2; tail -20 "$BUILD/make.log" >&2; exit 1; }
}

post_build() {
	# the library reaches the board only through the channel: no ring of its own
	undef=$($NM libzz9k.a 2>/dev/null | awk '$1=="U"{print $2}' | sort -u)
	for sym in open ioctl mmap munmap close; do
		echo "$undef" | grep "^$sym\$" >/dev/null || {
			echo "[FAIL] libzz9k.a does not call $sym: the Amix branch is missing" >&2; exit 1; }
	done
	echo "  libzz9k.a calls open, ioctl, mmap, munmap, close (the zz9ksvc channel)"
}

stage() {
	mkdir -p "$DEST$PREFIX/lib" "$DEST$PREFIX/include/zz9k" "$DEST$PREFIX/bin" \
		"$DEST$PREFIX/doc/libzz9k"
	cp libzz9k.a "$DEST$PREFIX/lib/libzz9k.a"
	for h in $HEADERS; do
		cp "include/zz9k/$h.h" "$DEST$PREFIX/include/zz9k/$h.h"
	done
	cp zz9k-test "$DEST$PREFIX/bin/zz9k-test"
	cp "$HERE/LICENSE" "$DEST$PREFIX/doc/libzz9k/LICENSE"
	cp PROVENANCE "$DEST$PREFIX/doc/libzz9k/PROVENANCE"
	chmod 0644 "$DEST$PREFIX/lib/libzz9k.a" "$DEST$PREFIX/include/zz9k"/*.h \
		"$DEST$PREFIX/doc/libzz9k"/*
	chmod 0755 "$DEST$PREFIX/bin/zz9k-test"
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man "$HERE/man/libzz9k.3" 3
	amix_man "$HERE/man/zz9k-test.1" 1
	amix_man_alias zz9k_inflate 3 libzz9k
	amix_man_alias zz9k_pool 3 libzz9k
	amix_man_whatis
}
