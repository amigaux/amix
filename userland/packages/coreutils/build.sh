# build.sh -- coreutils hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

# select, getrlimit (sort), fchmod: in libc, declared by no AMIX header;
# make only -- in configure the prototypes break autoconf's function probes
MAKE_CFLAGS="-include $AMIX_GCC14_DECLS"

# seq's floor/rint are local (patches/06), factor never calls sqrt, and
# strtod is libc's (seed below): no stock libm.a in any binary
make_args() {
	echo SEQ_LIBM= POW_LIB= SQRT_LIBM=
}

post_build() {
	if grep -E -- '(^| )-lm( |$)' "$BUILD/make.log" >/dev/null; then
		echo "[FAIL] -lm on a link line: stock libm.a object code would ship" >&2
		grep -E -- '(^| )-lm( |$)' "$BUILD/make.log" | head -3 >&2; exit 1
	fi
	echo "  no -lm on any link line"
}

configure_args() {
	echo --disable-largefile
}

pre_configure() {
	# D3: every program defines getpwnam/getpwuid/getgrnam/getgrgid itself
	$CC $AMIX_CFLAGS -c "$COMMON/amix-pwgr.c" -o "$BUILD/amix-pwgr.o"
	# quirk 90: dd's seek= truncation through an ftruncate that cuts aligned
	$CC $AMIX_CFLAGS -c "$COMMON/amix-ftruncate.c" -o "$BUILD/amix-ftruncate.o"
	export LIBS="$BUILD/amix-pwgr.o $BUILD/amix-ftruncate.o"
	export ac_cv_header_stdint_h=no jm_ac_cv_header_stdint_h=no
	export ac_cv_func_vfork=no
	export ac_cv_lib_elf_elf_begin=no
	# run-tests a cross configure cannot run; libc.so.1's own are used
	export ac_cv_func_getgroups_works=yes ac_cv_func_strtod=yes
	# configure answers "no" to putenv only because it cross-compiles; libc.so.1
	# has a real one (date -u's crash was elsewhere: patches/07)
	export jm_cv_func_svid_putenv=yes
}

post_configure() {
	grep '^#define intmax_t long long$' config.h >/dev/null &&
	grep '^#define uintmax_t unsigned long long$' config.h >/dev/null || {
		echo "[FAIL] intmax_t/uintmax_t are not the long long fallbacks" >&2; exit 1; }
	echo "  intmax_t/uintmax_t long long (no stdint.h, no inttypes.h)"
	! grep '^#define putenv rpl_putenv' config.h >/dev/null || {
		echo "[FAIL] putenv is still replaced" >&2; exit 1; }
	echo "  putenv from libc.so.1"
	# patched sources are newer than their man pages; make would run help2man
	# on the cross binaries.  The tarball's pages are current.
	touch man/*.1
}

stage() {
	make install DESTDIR="$DEST" > "$BUILD/install.log" 2>&1
	# uptime: the load average takes the nlist/kmem route that reads garbage
	# on AMIX (docs/porting.md 3.3); su/hostid are not built; no info reader;
	# charset.alias is an empty table for sysv4
	rm -f "$DEST$PREFIX/bin/uptime" "$DEST$PREFIX/man/man1/uptime.1" \
	      "$DEST$PREFIX/man/man1/su.1" "$DEST$PREFIX/man/man1/hostid.1"
	rm -rf "$DEST$PREFIX/info" "$DEST$PREFIX/lib"
	mkdir -p "$DEST$PREFIX/doc/coreutils"
	cp COPYING NEWS README THANKS "$DEST$PREFIX/doc/coreutils/"
	chmod 0644 "$DEST$PREFIX/doc/coreutils"/* "$DEST$PREFIX/man/man1"/*
	# D3: every executable defines the four lookups (T), none is undefined
	n=0
	for b in $(amix_gate_elfs "$DEST$PREFIX/bin"); do
		for f in getpwnam getpwuid getgrnam getgrgid; do
			"$NM" "$b" | awk -v f=$f '$NF==f && $(NF-1)=="T" {t=1} END {exit !t}' || {
				echo "[FAIL] D3: $f not defined in $(basename "$b")" >&2; exit 1; }
		done
		n=$((n + 1))
	done
	echo "  D3 ok   $n executables define getpwnam/getpwuid/getgrnam/getgrgid (T)"
	# quirk 90: any ftruncate in a binary is amix-ftruncate.c's (T), never
	# libc truncate.o's weak one alone
	n=0
	for b in $(amix_gate_elfs "$DEST$PREFIX/bin"); do
		"$NM" "$b" | awk '$NF=="ftruncate" {f=1; if ($(NF-1)!="T") bad=1} END {exit bad}' || {
			echo "[FAIL] quirk 90: $(basename "$b") links libc's raw ftruncate" >&2; exit 1; }
		"$NM" "$b" | awk '$NF=="ftruncate" {f=1} END {exit !f}' && n=$((n + 1))
	done
	echo "  FREESP ok  $n executables carry the aligned-cut ftruncate (quirk 90)"
}
