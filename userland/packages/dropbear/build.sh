# build.sh -- Dropbear hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

PROGRAMS="dropbear dbclient dropbearkey scp"
# upstream's own -fno-strict-overflow and -Wno-pointer-sign: configure puts
# them in the Makefile's CFLAGS, which the driver's make CFLAGS replace
MAKE_CFLAGS="-fno-strict-overflow -Wno-pointer-sign -include $AMIX_GCC14_DECLS -include $HERE/port/amix-compat.h -I$HERE/port/include"

# the one 64-bit conversion, scp's "C%04o %lld %s" file header, is formatted
# by snprintf, which is libamixc99's (defined in the binary); the libc printf
# family prints only that already-formatted string
AMIX_LL_PRINTF_REVIEWED="scp's C%04o %lld %s header goes through libamixc99 snprintf (scp.c, source())"

configure_args() {
	echo --disable-harden --disable-zlib --disable-pam --disable-lastlog \
	     --enable-bundled-libtom --disable-largefile
}

pre_configure() {
	cp "$HERE/localoptions.h" localoptions.h
	# pwgr: the binary defines getpwnam/getpwuid/getgrnam/getgrgid itself
	$CC $AMIX_CFLAGS -c "$COMMON/amix-pwgr.c" -o "$BUILD/amix-pwgr.o"
	$CC $AMIX_CFLAGS -I"$HERE/port/include" -c "$HERE/port/amix-compat.c" -o "$BUILD/amix-compat.o"
	export LIBS="$BUILD/amix-pwgr.o $BUILD/amix-compat.o -lgen -lsocket -lnsl"
}

post_configure() {
	# the one multi-call binary; make takes both from the environment
	# (Makefile.in: ifndef PROGRAMS), since make_args is split on spaces
	export PROGRAMS MULTI=1
	# two switches the 68060 gate's table scanner cannot size (a constant
	# index from clrl in cli_getopts, a byte-table two-level dispatch in
	# chansessionrequest): those files without jump tables, so every
	# instruction is provably decoded; both are cold (options, pty modes)
	printf '%s\n' 'obj/cli-runopts.o obj/svr-chansession.o: override CFLAGS += -fno-jump-tables' >> Makefile
	# configure wrote LIBS into the Makefile, which appends to the
	# environment's (LIBS+=): unset it, or the objects link twice
	unset LIBS
	# libtommath adds its include path to CFLAGS, which the driver's make
	# CFLAGS would replace: append it to them instead
	sed 's/^CFLAGS += /override CFLAGS += /' libtommath/Makefile > libtommath/Makefile.amix &&
		mv libtommath/Makefile.amix libtommath/Makefile
	grep '^override CFLAGS += -I' libtommath/Makefile >/dev/null || {
		echo "[FAIL] libtommath/Makefile: include path not appended" >&2; exit 1; }
}

stage() {
	b=$DEST$PREFIX
	mkdir -p "$b/sbin" "$b/bin" "$b/doc/dropbear" "$DEST/etc/dropbear" \
	         "$DEST/etc/init.d" "$DEST/etc/rc0.d" "$DEST/etc/rc1.d" "$DEST/etc/rc2.d"
	# one binary; the other programs are hard links to it (it runs as the
	# name it is called by)
	cp dropbearmulti "$b/sbin/dropbear"
	for p in dbclient ssh dropbearkey scp; do
		ln "$b/sbin/dropbear" "$b/bin/$p"
	done
	# the boot script: one file under three names (S76 after the network,
	# K40 before syslogd's K50)
	cp "$HERE/files/dropbear" "$DEST/etc/init.d/dropbear"
	ln "$DEST/etc/init.d/dropbear" "$DEST/etc/rc2.d/S76dropbear"
	ln "$DEST/etc/init.d/dropbear" "$DEST/etc/rc0.d/K40dropbear"
	ln "$DEST/etc/init.d/dropbear" "$DEST/etc/rc1.d/K40dropbear"
	cp LICENSE CHANGES "$b/doc/dropbear/"
	chmod 0755 "$b/sbin/dropbear"
	chmod 0444 "$DEST/etc/init.d/dropbear"
	chmod 0644 "$b/doc/dropbear"/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	for m in "$HERE"/man/*.[0-9]; do
		amix_man "$m" "${m##*.}"
	done
	amix_man_alias ssh 1 dbclient
	amix_man_whatis
}
