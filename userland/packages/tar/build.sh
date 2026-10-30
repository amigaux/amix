# build.sh -- tar hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

configure_args() {
	echo --disable-largefile
}

pre_configure() {
	# lstat exists (tar would otherwise follow links); valloc is not in
	# libc.so.1; the cross default would wrap gettimeofday
	export ac_cv_func_lstat=yes ac_cv_have_decl_valloc=no jm_cv_func_gettimeofday_clobber=no
	# GCC 14 links the SVR4 way: the period answers for ftruncate (keep
	# gnulib's F_FREESP replacement) and stdint.h (all three cache names)
	export ac_cv_func_ftruncate=no ac_cv_header_stdint_h=no gl_cv_header_stdint_h=no \
		jm_ac_cv_header_stdint_h=no
}

post_configure() {
	grep '^#define HAVE_LSTAT 1' config.h >/dev/null || {
		echo "[FAIL] HAVE_LSTAT is not 1 -- tar would '#define lstat stat' and follow links" >&2; exit 1; }
	echo "  HAVE_LSTAT 1"
	grep '^#define HAVE_DECL_VALLOC 0' config.h >/dev/null || {
		echo "[FAIL] HAVE_DECL_VALLOC is not 0 -- valloc is not in libc.so.1" >&2; exit 1; }
	echo "  HAVE_DECL_VALLOC 0"
	! grep '^#define GETTIMEOFDAY_CLOBBERS_LOCALTIME_BUFFER' config.h >/dev/null || {
		echo "[FAIL] the gettimeofday clobber wrapper is still selected" >&2; exit 1; }
	echo "  GETTIMEOFDAY_CLOBBERS_LOCALTIME_BUFFER unset"
	for h in STRINGS_H STDINT_H INTTYPES_H; do
		! grep "^#define HAVE_$h 1" config.h >/dev/null || {
			echo "[FAIL] config.h defines HAVE_$h -- a probe reached the host's headers" >&2; exit 1; }
	done
	echo "  HAVE_STRINGS_H/STDINT_H/INTTYPES_H absent (target headers were read)"
	# D3: the executable defines getpwnam/getpwuid/getgrnam/getgrgid itself
	$CC $AMIX_CFLAGS -c "$COMMON/amix-pwgr.c" -o "$BUILD/amix-pwgr.o" > "$BUILD/pwgr.log" 2>&1 || {
		echo "[FAIL] amix-pwgr.c did not compile" >&2; cat "$BUILD/pwgr.log" >&2; exit 1; }
	! grep 'warning' "$BUILD/pwgr.log" | grep -v "^$AMIX_SYSROOT/" | grep -v '/include-fixed/' >/dev/null || {
		echo "[FAIL] amix-pwgr.c compiled with warnings:" >&2; cat "$BUILD/pwgr.log" >&2; exit 1; }
	echo "  amix-pwgr.o built (D3)"
	# every Makefile's LIBS: the D3 object, and a link trace proving where
	# gettimeofday comes from (usr/ccs/lib/libc.so's static member)
	for m in $(find . -name Makefile); do
		sed -i "s|^LIBS = .*|LIBS = $BUILD/amix-pwgr.o -Wl,-y,gettimeofday|" "$m"
	done
	grep "^LIBS = $BUILD/amix-pwgr.o -Wl,-y,gettimeofday\$" src/Makefile >/dev/null || {
		echo "[FAIL] src/Makefile LIBS not set" >&2; exit 1; }
}

post_build() {
	grep 'libc\.so(gettimeofday\.o): definition of gettimeofday$' "$BUILD/make.log" >/dev/null || {
		echo "[FAIL] gettimeofday is not defined by usr/ccs/lib/libc.so(gettimeofday.o)" >&2
		grep gettimeofday "$BUILD/make.log" | grep -v '^[^ ]*gcc ' >&2
		exit 1; }
	echo "  gettimeofday from usr/ccs/lib/libc.so(gettimeofday.o)"
	[ -f src/tar ] || { echo "[FAIL] tar binary not built" >&2; exit 1; }
	for s in getpwnam getpwuid getgrnam getgrgid; do
		"$NM" src/tar | awk -v s="$s" '$NF==s && $(NF-1)=="T" {f=1} END {exit !f}' || {
			echo "[FAIL] D3: $s is not defined (T) in the executable" >&2; exit 1; }
		! "$NM" -u src/tar | awk '{print $NF}' | grep -x "$s" >/dev/null || {
			echo "[FAIL] D3: $s is still UNDEFINED -- libc's copy would be called" >&2; exit 1; }
	done
	echo "  D3 ok  getpwnam/getpwuid/getgrnam/getgrgid defined in the executable"
	needed=$("$OBJDUMP" -p src/tar | awk '$1=="NEEDED" {print $2}' | tr '\n' ' ')
	[ "$needed" = "/usr/lib/libc.so.1 " ] || {
		echo "[FAIL] DT_NEEDED is '$needed', expected only /usr/lib/libc.so.1" >&2; exit 1; }
	echo "  DT_NEEDED ok  $needed"
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/doc/tar"
	cp src/tar "$DEST$PREFIX/bin/tar"
	cp COPYING NEWS README "$DEST$PREFIX/doc/tar/"
	chmod 0755 "$DEST$PREFIX/bin/tar"
	chmod 0644 "$DEST$PREFIX/doc/tar"/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	amix_man "$HERE/man/tar.1" 1
	amix_man_whatis
}
