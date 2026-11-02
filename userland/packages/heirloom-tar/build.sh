# build.sh -- heirloom-tar hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tarball is the whole
# Heirloom Toolchest: only tar/ and the libcommon files tar calls are built.

# the default file stock tar reads; sort and uniq for the `u' key from the
# stock /usr/bin; the shell the `u' key runs them with
TAR_DEFS="-DTARDFL='\"/etc/default/tar\"' -DSHELL='\"/sbin/sh\"' -DSV3BIN='\"/usr/bin\"' -DDEFBIN='\"/usr/bin\"'"
TAR_INCS="-include $AMIX_GCC14_DECLS -include $HERE/port/amix-compat.h -I$HERE/port/include -Ilibcommon"
# every %ll conversion goes through libamixc99's snprintf or vsnprintf
# (patches/03-long-long-formats.patch); libc's printf and fprintf get none
AMIX_LL_PRINTF_REVIEWED="every %ll conversion is formatted by libamixc99 snprintf/vsnprintf (patch 03: the header size field, the v messages, the tv size column, pax records)"

# libcommon: the buffered line reader (/etc/default/tar), getdir (getdents),
# the ASCII class table, and the `SYSV3' personality flag
LIBCOMMON="asciitype getdir ib_alloc ib_close ib_free ib_getlin ib_open ib_read sysv3"

cc_one() {	# cc_one <source> <object>
	echo "$CC $TAR_INCS $AMIX_CFLAGS -c $1 -o $2" >> "$BUILD/make.log"
	$CC $TAR_INCS $AMIX_CFLAGS -c "$1" -o "$2" 2> "$2.warn" || {
		echo "[FAIL] compiling $1" >&2; cat "$2.warn" >&2; exit 1; }
	cat "$2.warn" >> "$BUILD/make.log"
}

build() {
	objs=
	for f in $LIBCOMMON; do
		cc_one "libcommon/$f.c" "libcommon/$f.o"
		objs="$objs libcommon/$f.o"
	done
	cc_one "$HERE/port/amix-compat.c" amix-compat.o
	cc_one "$COMMON/amix-pwgr.c" amix-pwgr.o
	echo "$CC $TAR_INCS $TAR_DEFS $AMIX_CFLAGS -c tar/tar.c -o tar/tar.o" >> "$BUILD/make.log"
	eval "\$CC \$TAR_INCS $TAR_DEFS \$AMIX_CFLAGS -c tar/tar.c -o tar/tar.o" 2> tar/tar.warn || {
		echo "[FAIL] compiling tar/tar.c" >&2; cat tar/tar.warn >&2; exit 1; }
	cat tar/tar.warn >> "$BUILD/make.log"
	echo "$CC -o tar/tar tar/tar.o amix-compat.o amix-pwgr.o $objs -lgen" >> "$BUILD/make.log"
	$CC -o tar/tar tar/tar.o amix-compat.o amix-pwgr.o $objs -lgen >> "$BUILD/make.log" 2>&1 || {
		echo "[FAIL] tar did not link" >&2; tail -20 "$BUILD/make.log" >&2; exit 1; }
}

post_build() {
	# the passwd and group lookups are the program's own (amix-pwgr.c)
	for s in getpwnam getgrnam getpwuid getgrgid; do
		$NM tar/tar | grep " T $s\$" > /dev/null || {
			echo "[FAIL] tar does not define $s itself (amix-pwgr.o)" >&2; exit 1; }
	done
	echo "  pwgr      getpwnam/getgrnam/getpwuid/getgrgid defined in tar"
	# the default file and the paths the `u' key uses are the system's
	for s in /etc/default/tar /sbin/sh "PATH=/usr/bin:/usr/bin:"; do
		strings tar/tar | grep -F "$s" > /dev/null || {
			echo "[FAIL] tar lacks the string $s" >&2; exit 1; }
	done
	echo "  paths     /etc/default/tar, /sbin/sh, sort and uniq from /usr/bin"
}

stage() {
	mkdir -p "$DEST/usr/sbin" "$DEST/etc" "$DEST$PREFIX/doc/heirloom-tar"
	cp tar/tar "$DEST/usr/sbin/tar"
	chmod 0755 "$DEST/usr/sbin/tar"	# the driver strips it; 0555 bin bin is the prototype's
	ln -s /usr/sbin/tar "$DEST/etc/tar"
	# the licences: tar.c's own (Caldera), Ritter's zlib-style terms for the
	# libcommon files and his changes, and ours (MIT) for port/
	d=$DEST$PREFIX/doc/heirloom-tar
	{ echo "==== tar/tar.c"; sed -n '1,/^ \*\/$/p' tar/tar.c; echo
	  for f in $LIBCOMMON; do echo "==== libcommon/$f.c"; sed -n '1,/\*\//p' "libcommon/$f.c"; echo; done
	} > "$d/LICENSE"
	cp LICENSE/README "$d/LICENSES"
	cp tar/NOTES "$d/NOTES"
	cp "$HERE/../LICENSE" "$d/LICENSE.amix"
	chmod 0644 "$d"/*
	# the manual page, heirloom-tar(1); replaces.d/<PKG>, from MAN_REPLACES,
	# tells man(1) that it is the page of /usr/sbin/tar (README.md, Manual page)
	. "$HERE/../tools/manpages.sh"
	amix_man "$HERE/man/heirloom-tar.1" 1
	amix_man_whatis
	amix_man_replaces
}
