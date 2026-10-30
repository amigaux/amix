# build.sh -- gzip hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

configure_args() {
	# the C longest-match path: no imported match.S
	echo --disable-largefile gzip_cv_assembler=no
}

pre_configure() {
	export SHELL=/bin/sh
	# GCC 14 links the SVR4 way (usr/ccs/lib/libc.so: libc.so.1 plus static
	# members), so the lstat probe finds a static lstat.o the period link
	# never saw: pinned to the period answer.  gnulib's ABSOLUTE_ headers
	# are pinned to the sysroot's, not the toolchain's include_next wrappers.
	export ac_cv_func_lstat=no
	export gl_cv_absolute_fcntl_h="$AMIX_SYSROOT/usr/include/fcntl.h"
	export gl_cv_absolute_sys_time_h="$AMIX_SYSROOT/usr/include/sys/time.h"
}

post_configure() {
	! grep '^#define ASMV' lib/config.h >/dev/null || {
		echo "[FAIL] ASMV is defined: the assembler match.S slipped in" >&2; exit 1; }
	echo "  ASMV undefined (C longest-match)"
	# an ABSOLUTE_*_H that names a header with include_next would loop
	for f in $(sed -n 's/^#define ABSOLUTE_[A-Z_]*_H "\(.*\)"$/\1/p' lib/config.h); do
		! grep include_next "$f" >/dev/null 2>&1 || {
			echo "[FAIL] ABSOLUTE_ header $f uses include_next" >&2; exit 1; }
	done
	for want in 'HAVE_UTIME_H:present' 'HAVE_WORKING_UTIMES:absent' 'HAVE_LSTAT:absent'; do
		sym=${want%:*}; exp=${want#*:}
		if grep "^#define $sym 1\$" lib/config.h >/dev/null; then got=present; else got=absent; fi
		[ "$got" = "$exp" ] || { echo "[FAIL] $sym is $got, expected $exp" >&2; exit 1; }
		echo "  $sym $got"
	done
}

post_build() {
	[ -f gzip ] || { echo "[FAIL] gzip binary not built" >&2; exit 1; }
	# gunzip/zcat are generated with the BUILD host's #!/bin/bash
	for s in gunzip zcat; do
		sed '1s|^#!.*|#!/bin/sh|' "$s" > "$s.fixed"
		mv "$s.fixed" "$s"
		chmod 0755 "$s"
		echo "  $s: $(head -1 "$s")"
	done
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/man/man1" "$DEST$PREFIX/doc/gzip"
	for p in gzip gunzip zcat; do
		cp "$p" "$DEST$PREFIX/bin/$p"
		cp "$p.1" "$DEST$PREFIX/man/man1/$p.1"
	done
	cp COPYING NEWS README "$DEST$PREFIX/doc/gzip/"
	chmod 0755 "$DEST$PREFIX/bin"/*
	chmod 0644 "$DEST$PREFIX/man/man1"/*.1 "$DEST$PREFIX/doc/gzip"/*
}
