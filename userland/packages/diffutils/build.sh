# build.sh -- diffutils hooks for recipes/common/pkgbuild.sh (interim).
# Hooks only; the reasons are in README.md.

configure_args() {
	echo --disable-largefile
}

pre_configure() {
	# The compat stdint.h (gcc14 sysroot) satisfies the intmax_t/uintmax_t
	# probes through autoconf's default includes, but inttostr.h, xstrtol.h,
	# system.h and strtoimax.c include only <inttypes.h>, which AMIX lacks.
	# "no" makes configure define them as long long, as the period build did.
	export ac_cv_header_stdint_h=no
	# Cross answers configure cannot measure, pinned as the make recipe's:
	# vfork is a static member of usr/ccs/lib/libc.so, not libc.so.1's, and
	# fork is what the bench has proven; pr is found on the HOST otherwise.
	export ac_cv_func_vfork=no
	export ac_cv_path_PR_PROGRAM=/usr/bin/pr
}

post_configure() {
	grep '^#define intmax_t long long$' config.h >/dev/null &&
	grep '^#define uintmax_t unsigned long long$' config.h >/dev/null || {
		echo "[FAIL] intmax_t/uintmax_t are not the long long fallbacks" >&2; exit 1; }
	echo "  intmax_t/uintmax_t long long (no stdint.h, no inttypes.h)"
	! grep '^#define HAVE_WORKING_VFORK' config.h >/dev/null || {
		echo "[FAIL] HAVE_WORKING_VFORK is set" >&2; exit 1; }
	echo "  vfork -> fork"
	grep '^#define PR_PROGRAM "/usr/bin/pr"$' config.h >/dev/null || {
		echo "[FAIL] PR_PROGRAM is not /usr/bin/pr" >&2; exit 1; }
	echo "  PR_PROGRAM /usr/bin/pr"
	# sdiff and diff3 exec DEFAULT_DIFF_PROGRAM; upstream's "diff" is a PATH
	# lookup that finds the stock SVR4 diff first on a stock PATH.
	sed -i "s|^#define DEFAULT_DIFF_PROGRAM \"diff\"\$|#define DEFAULT_DIFF_PROGRAM \"$AMIX_PREFIX/bin/diff\"|" config.h
	grep "^#define DEFAULT_DIFF_PROGRAM \"$AMIX_PREFIX/bin/diff\"\$" config.h >/dev/null || {
		echo "[FAIL] DEFAULT_DIFF_PROGRAM not set to $AMIX_PREFIX/bin/diff" >&2; exit 1; }
	echo "  DEFAULT_DIFF_PROGRAM $AMIX_PREFIX/bin/diff"
	# patches 01/03 make diff.c/sdiff.c newer than their man pages; make would
	# regenerate them with help2man, which cannot run a cross binary, and
	# config/missing leaves them EMPTY.  The tarball's pages are current.
	touch man/*.1
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/man/man1" "$DEST$PREFIX/doc/diffutils"
	for p in diff diff3 sdiff cmp; do
		cp "src/$p" "$DEST$PREFIX/bin/$p"
		cp "man/$p.1" "$DEST$PREFIX/man/man1/$p.1"
	done
	cp COPYING NEWS README "$DEST$PREFIX/doc/diffutils/"
	chmod 0755 "$DEST$PREFIX/bin"/*
	chmod 0644 "$DEST$PREFIX/man/man1"/* "$DEST$PREFIX/doc/diffutils"/*
}
