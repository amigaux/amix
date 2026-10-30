# build.sh -- rsync hooks for recipes/common/pkgbuild.sh (interim).
# Hooks only; the reasons are in README.md.

# socket calls, select, syslog, gethostname, fchmod, getrlimit: in libsocket/
# libnsl/libc, declared by no AMIX header; make only (configure probes).
# rsync's configure writes -I./zlib -I./popt -DHAVE_CONFIG_H into CFLAGS
# itself (not DEFS/CPPFLAGS), and the driver's make CFLAGS replace it
MAKE_CFLAGS="-include $AMIX_GCC14_DECLS -I./zlib -I./popt -DHAVE_CONFIG_H"

configure_args() {
	echo --disable-largefile --disable-ipv6 --disable-locale \
	     --disable-iconv --disable-iconv-open \
	     --disable-acl-support --disable-xattr-support \
	     --with-included-zlib --with-included-popt \
	     --with-nobody-group=nobody
}

pre_configure() {
	# D3: the binary defines getpwnam/getpwuid/getgrnam/getgrgid itself
	$CC $AMIX_CFLAGS -c "$REPO/recipes/common/amix-pwgr.c" -o "$BUILD/amix-pwgr.o"
	export LIBS="$BUILD/amix-pwgr.o"
	export ac_cv_func_vfork=no
}

post_configure() {
	# configure reads the BUILD host's /etc/group for the daemon's default
	# gid; the box has nobody:60001 and no nogroup
	grep '^#define NOBODY_USER "nobody"$' config.h >/dev/null &&
	grep '^#define NOBODY_GROUP "nobody"$' config.h >/dev/null || {
		echo "[FAIL] NOBODY_USER/NOBODY_GROUP are not nobody/nobody" >&2; exit 1; }
	echo "  daemon default uid/gid nobody/nobody"
}

stage() {
	mkdir -p "$DEST$PREFIX/bin" "$DEST$PREFIX/man/man1" "$DEST$PREFIX/man/man5" \
	         "$DEST$PREFIX/doc/rsync"
	cp rsync "$DEST$PREFIX/bin/rsync"
	cp rsync.1 "$DEST$PREFIX/man/man1/"
	cp rsyncd.conf.5 "$DEST$PREFIX/man/man5/"
	cp COPYING NEWS README "$DEST$PREFIX/doc/rsync/"
	chmod 0755 "$DEST$PREFIX/bin/rsync"
	chmod 0644 "$DEST$PREFIX/man"/man?/* "$DEST$PREFIX/doc/rsync"/*
	# D3: the binary defines the four lookups (T)
	for f in getpwnam getpwuid getgrnam getgrgid; do
		"$NM" "$DEST$PREFIX/bin/rsync" | awk -v f=$f '$NF==f && $(NF-1)=="T" {t=1} END {exit !t}' || {
			echo "[FAIL] D3: $f not defined in rsync" >&2; exit 1; }
	done
	echo "  D3 ok   rsync defines getpwnam/getpwuid/getgrnam/getgrgid (T)"
}
