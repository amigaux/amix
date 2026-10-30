# styles/make.sh: a plain Makefile, no configure step. Sourced by pkgbuild.sh.
#
# MIT licence, see LICENSE at the top of the repository.
# CC, AR, RANLIB and CFLAGS are given on make's command line; the recipe's
# make_args adds to them. cwd: the source tree.

style_configure() { :; }

style_make() {
	make CC="$CC" AR="$AR" RANLIB="$RANLIB" \
		CFLAGS="$AMIX_CFLAGS $EXTRA_CFLAGS $MAKE_CFLAGS" $(make_args)
}
