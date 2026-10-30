# build.sh -- make hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

EXTRA_CFLAGS=-D_POSIX_SOURCE

configure_args() {
	echo --disable-largefile
}

pre_configure() {
	# _sys_siglist is not in libc.so.1; SA_RESTART cannot be run-tested
	export ac_cv_have_decl__sys_siglist=no make_cv_sa_restart=yes
	# GCC 14 links the SVR4 way (static libc members): the period answers
	export ac_cv_lib_elf_elf_begin=no ac_cv_func_vfork=no ac_cv_header_stdint_h=no \
		ac_cv_func_lstat=no
}

post_configure() {
	grep '^#define HAVE_DECL__SYS_SIGLIST 0' config.h >/dev/null || {
		echo "[FAIL] HAVE_DECL__SYS_SIGLIST is not 0 -- _sys_siglist is not in libc.so.1" >&2; exit 1; }
	echo "  HAVE_DECL__SYS_SIGLIST 0 (make's own signal-name table)"
	grep '^#define HAVE_SA_RESTART 1' config.h >/dev/null || {
		echo "[FAIL] HAVE_SA_RESTART is not 1 -- the make_cv_sa_restart seed did not land" >&2; exit 1; }
	echo "  HAVE_SA_RESTART 1"
	grep '^#define MAKE_JOBSERVER 1' config.h >/dev/null || {
		echo "[FAIL] the jobserver is not enabled" >&2; exit 1; }
	echo "  MAKE_JOBSERVER 1"
	grep '^#define environ _environ' config.h >/dev/null || {
		echo "[FAIL] patches/01's environ alias is not in config.h" >&2; exit 1; }
	echo "  environ -> _environ"
	for h in STRINGS_H STDINT_H INTTYPES_H; do
		! grep "^#define HAVE_$h 1" config.h >/dev/null || {
			echo "[FAIL] config.h defines HAVE_$h -- a probe reached the host's headers" >&2; exit 1; }
	done
	echo "  HAVE_STRINGS_H/STDINT_H/INTTYPES_H absent (target headers were read)"
}

post_build() {
	[ -f make ] || { echo "[FAIL] make binary not built" >&2; exit 1; }
	needed=$("$OBJDUMP" -p make | awk '$1=="NEEDED" {print $2}' | tr '\n' ' ')
	[ "$needed" = "/usr/lib/libc.so.1 " ] || {
		echo "[FAIL] DT_NEEDED is '$needed', expected only /usr/lib/libc.so.1" >&2; exit 1; }
	echo "  DT_NEEDED ok  $needed"
	# the load average must not come from nlist()/kmem
	! "$NM" -u make | awk '{print $NF}' | grep -E '^(nlist|kvm_open|kstat_open)$' >/dev/null || {
		echo "[FAIL] make reads kernel symbols via nlist -- the COMMON-avenrun trap" >&2; exit 1; }
	! strings make | grep -x '/dev/kmem' >/dev/null || {
		echo "[FAIL] make opens /dev/kmem for the load average" >&2; exit 1; }
	echo "  LOADAVG ok  no nlist(), no /dev/kmem (make -l degrades to a warning)"
	# the box has no fnmatch/glob: make's bundled glob/ must be in the binary
	for s in glob fnmatch; do
		"$NM" make | awk -v s="$s" '$NF==s && $(NF-1)=="T" {f=1} END {exit !f}' || {
			echo "[FAIL] $s is not defined in the binary -- the bundled glob/ was not linked" >&2; exit 1; }
	done
	echo "  GLOB ok  bundled glob()/fnmatch() linked in (T)"
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/man/man1" "$DEST$PREFIX/doc/make"
	cp make "$DEST$PREFIX/bin/make"
	cp make.1 "$DEST$PREFIX/man/man1/make.1"
	cp COPYING glob/COPYING.LIB NEWS README "$DEST$PREFIX/doc/make/"
	chmod 0755 "$DEST$PREFIX/bin/make"
	chmod 0644 "$DEST$PREFIX/man/man1/make.1" "$DEST$PREFIX/doc/make"/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man_relayout
	amix_man_whatis
}
