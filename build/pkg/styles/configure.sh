# styles/configure.sh: ./configure --host, then make. Sourced by pkgbuild.sh.
#
# MIT licence, see LICENSE at the top of the repository.
# The recipe's hooks pre_configure, configure_args and post_configure run
# here; configure is lenient (its probes are decided by the linker), make is
# strict. cwd: the source tree.

style_configure() {
	echo "--- cross-configure ---"
	pre_configure
	CC="$CC" CPP="$AMIX_CPP" \
	CFLAGS="$AMIX_CFLAGS $EXTRA_CFLAGS $AMIX_CONFIGURE_LENIENT" \
	./configure --host="$AMIX_HOST_TRIPLET" --prefix="$AMIX_PREFIX" --disable-nls \
		$(configure_args) > "$BUILD/configure.log" 2>&1 || {
		echo "[FAIL] configure failed; see $BUILD/configure.log" >&2
		tail -20 "$BUILD/configure.log" >&2
		exit 1
	}
	post_configure
	echo
}

# style_make: make with the recipe's make_args; configure chose the tools.
style_make() {
	make CFLAGS="$AMIX_CFLAGS $EXTRA_CFLAGS $MAKE_CFLAGS" $(make_args)
}
