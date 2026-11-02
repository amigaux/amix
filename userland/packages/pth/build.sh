# build.sh -- GNU Pth hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

# Pth is 1990s C (gnu89)
EXTRA_CFLAGS="-std=gnu89 -fno-strict-aliasing"

configure_args() {
	echo --enable-pthread --disable-shared --enable-static \
		--with-mctx-mth=mcsc --with-mctx-dsp=sc --with-mctx-stk=mc
}

post_configure() {
	grep '^#define PTH_MCTX_MTH_use PTH_MCTX_MTH_mcsc$' pth_acdef.h >/dev/null || {
		echo "[FAIL] the machine context is not mcsc" >&2; exit 1; }
	patch -p1 --batch --fuzz=0 < "$HERE/postconf/0002-amix-public-timespec.patch" >/dev/null || {
		echo "[FAIL] postconf/0002 did not apply to the generated pthread.h" >&2; exit 1; }
	make pth_p.h > /dev/null
	echo "  mcsc machine context; pthread.h patched (public timespec)"
}

# the box tests (tests/smoke.sh): built here against this tree's pthread.h
# and libpthread.a, left in the tree (tests/fixtures), not shipped
post_build() {
	for t in t-errno t-once; do
		echo "$CC $AMIX_CFLAGS -I. -o $t $HERE/tests/$t.c .libs/libpthread.a -lsocket -lnsl" >> "$BUILD/make.log"
		$CC $AMIX_CFLAGS -I. -o "$t" "$HERE/tests/$t.c" .libs/libpthread.a -lsocket -lnsl >> "$BUILD/make.log" 2>&1 || {
			echo "[FAIL] tests/$t.c did not link" >&2; tail -20 "$BUILD/make.log" >&2; exit 1; }
	done
	echo "  box tests built: t-errno t-once"
}

stage() {
	b="$DEST$PREFIX"
	mkdir -p "$b/lib" "$b/include" "$b/doc/pth"
	cp .libs/libpth.a .libs/libpthread.a "$b/lib/"
	cp pth.h pthread.h "$b/include/"
	cp COPYING NEWS README THANKS "$b/doc/pth/"
	chmod 0644 "$b"/lib/*.a "$b"/include/*.h "$b"/doc/pth/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man pth.3 3
	amix_man pthread.3 3
	amix_man_whatis
}

# select, the socket calls, readv/writev (amix-decls.h)
MAKE_CFLAGS="-include $AMIX_GCC14_DECLS"
