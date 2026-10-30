# build.sh -- patch hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.  No source patches.

configure_args() {
	echo --mandir="$PREFIX/man" ac_cv_func_closedir_void=no ed_PROGRAM=/usr/bin/ed
}

pre_configure() {
	# -D_POSIX_SOURCE, against porting.md's general advice: see README.md
	export CPPFLAGS=-D_POSIX_SOURCE
	export LIBS=-lc
}

post_configure() {
	# an unexpected answer almost always means CPP fell back to the BUILD
	# host's preprocessor
	for want in HAVE_WCHAR_H:absent HAVE_WCTYPE_H:absent HAVE_MBSTATE_T:absent \
		HAVE_SIGACTION:present HAVE_DECL_MKTEMP:present; do
		sym=${want%:*}; exp=${want#*:}
		if grep "^#define $sym 1\$" config.h >/dev/null; then got=present; else got=absent; fi
		[ "$got" = "$exp" ] || { echo "[FAIL] config.h says $sym is $got, expected $exp" >&2; exit 1; }
		echo "  $sym $got"
	done
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/man/man1" "$DEST$PREFIX/doc/patch" "$DEST/usr/bin"
	cp patch "$DEST$PREFIX/bin/patch"
	# the prototype's absolute-target symlink (stock pkgadd mangles a relative one)
	ln -s "$PREFIX/bin/patch" "$DEST/usr/bin/patch"
	cp patch.man "$DEST$PREFIX/man/man1/patch.1"
	cp COPYING NEWS README "$DEST$PREFIX/doc/patch/"
	chmod 0755 "$DEST$PREFIX/bin/patch"
	chmod 0644 "$DEST$PREFIX/man/man1/patch.1" "$DEST$PREFIX/doc/patch"/*
}
