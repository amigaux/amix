# build.sh -- Vim hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

# ncurses from its own build in this build root (BUILD_DEPENDS)
NC="$AMIX_BUILD_ROOT/ncurses/dest$PREFIX"

configure_args() {
	echo --with-features=normal --disable-gui --without-x --enable-gpm=no \
		--disable-netbeans --disable-channel --disable-sysmouse --disable-canberra \
		--disable-libsodium --disable-xsmp --disable-selinux --disable-acl --disable-smack \
		--with-tlib=ncurses --with-compiledby=amix
}

pre_configure() {
	[ -f "$NC/lib/libncurses.a" ] || {
		echo "[FAIL] no $NC/lib/libncurses.a: build userland/packages/ncurses first" >&2; exit 1; }
	# the answers a cross build cannot run for (isoriano's port, as measured on Amix)
	export vim_cv_toupper_broken=no vim_cv_terminfo=yes vim_cv_tgetent=zero \
		vim_cv_getcwd_broken=no vim_cv_stat_ignores_slash=no \
		vim_cv_memmove_handles_overlap=yes vim_cv_bcopy_handles_overlap=yes \
		vim_cv_memcpy_handles_overlap=no vim_cv_tty_group=world vim_cv_tty_mode=0620 \
		vim_cv_uname_output=AMIX vim_cv_uname_r_output=4.0 vim_cv_uname_m_output=m68k
	export CPPFLAGS="-I$NC/include/ncurses -I$NC/include" LDFLAGS="-L$NC/lib"
}

post_configure() {
	grep '^#define TERMINFO 1' src/auto/config.h >/dev/null || {
		echo "[FAIL] TERMINFO is not set (vim_cv_terminfo)" >&2; exit 1; }
	grep -- '-lncurses' src/auto/config.mk >/dev/null || {
		echo "[FAIL] vim does not link ncurses" >&2; exit 1; }
	# two switch tables the 060 gate's scanner cannot bound: compare chains instead
	printf '\nobjects/insexpand.o objects/scriptfile.o: override CFLAGS += -fno-jump-tables\n' >> src/Makefile
	# :version records the compile and link lines (build-host paths) and, without
	# --with-compiledby, the build's user and host name: made now, then neutral
	make -C src auto/pathdef.c > /dev/null
	sed -e 's|^char_u \*all_cflags = .*|char_u *all_cflags = (char_u *)"m68k-elf-gcc (gcc14-cross-amix) -m68020-60 -mno-strict-align -O2";|' \
	    -e 's|^char_u \*all_lflags = .*|char_u *all_lflags = (char_u *)"m68k-elf-gcc (gcc14-cross-amix), ncurses 6.6 static";|' \
	    -e 's|^char_u \*compiled_sys = .*|char_u *compiled_sys = (char_u *)"";|' \
	    src/auto/pathdef.c > src/auto/pathdef.c.new && mv src/auto/pathdef.c.new src/auto/pathdef.c
	grep -E 'compiled_user = \(char_u \*\)"amix"' src/auto/pathdef.c > /dev/null || {
		echo "[FAIL] pathdef.c: compiled_user is not amix" >&2; exit 1; }
	echo "  TERMINFO, -lncurses; insexpand.o and scriptfile.o without jump tables"
}

make_args() {
	echo -C src vim xxd
}

stage() {
	make -C src DESTDIR="$DEST" STRIP=true installvimbin installruntime installlinks \
		installtools > "$BUILD/install.log" 2>&1 || { echo "[FAIL] install; see $BUILD/install.log" >&2; exit 1; }
	make -C src/xxd > /dev/null
	b="$DEST$PREFIX"
	cp src/xxd/xxd "$b/bin/xxd"
	# the stock pkgadd mangles a relative symlink target (docs/porting.md 7): hard links
	for l in ex view vimdiff rvim rview; do rm -f "$b/bin/$l"; ln "$b/bin/vim" "$b/bin/$l"; done
	# no GUI, no NLS; vimtutor needs a POSIX shell (it uses $(...) and mktemp)
	rm -f "$b/bin/vimtutor"
	rm -rf "$b/share/vim/vim91/lang" "$b/share/vim/vim91/tools" "$b/share/man"
	mkdir -p "$b/doc/vim"; cp LICENSE README.md "$b/doc/vim/"
	chmod 0755 "$b"/bin/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man runtime/doc/vim.1 1
	amix_man runtime/doc/vimdiff.1 1
	# xxd.1 splits its NAME entry over two lines: one line for whatis
	sed '/^\.SH NAME/{n;N;s/^\.I xxd\n/xxd /;}' runtime/doc/xxd.1 > "$BUILD/xxd.1"
	amix_man "$BUILD/xxd.1" 1
	for l in ex view rvim rview; do amix_man_alias $l 1 vim; done
	amix_man_whatis
}

# select (amix-decls.h); isinf, C99 math Amix lacks, as gcc's builtin
MAKE_CFLAGS="-include $AMIX_GCC14_DECLS -include $HERE/amix-isinf.h"

# the ll conversions in vim's strings are vim_snprintf formats (messages, :echo);
# vim_snprintf formats each through snprintf, libamixc99's (patches/01); vim
# hands libc printf/fprintf/sprintf no ll format of its own (grep of src/*.c)
AMIX_LL_PRINTF_REVIEWED="vim_snprintf formats ll via libamixc99 snprintf (patches/01); no ll format reaches libc printf"
