# build.sh -- cdfs hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  The tree is the git archive of
# amix-cdfs at kernel/drivers/cdfs/cdfs.pin (FORKPIN).

build() {
	# the fork's amix-mount rule: mount.c alone, system headers only (no
	# repo includes, no defines of the fork's); compile and link apart so
	# the gates see the compile
	{
		set -x
		$CC $AMIX_CFLAGS -c platform/amix/mount.c -o mount.o
		$CC $AMIX_CFLAGS -o mount mount.o
	} >> "$BUILD/make.log" 2>&1 || { tail -20 "$BUILD/make.log" >&2; echo "[FAIL] mount did not build" >&2; exit 1; }
}

post_build() {
	! grep 'warning:' "$BUILD/make.log" >/dev/null || {
		echo "[FAIL] mount compiled with warnings" >&2; grep 'warning:' "$BUILD/make.log" >&2; exit 1; }
	echo "  mount warning-clean"
}

stage() {
	mkdir -p "$DEST/usr/lib/fs/cdfs" "$DEST/cdrom" "$DEST$PREFIX/doc/cdfs"
	cp mount "$DEST/usr/lib/fs/cdfs/mount"
	chmod 0755 "$DEST/usr/lib/fs/cdfs" "$DEST/cdrom" "$DEST/usr/lib/fs/cdfs/mount"
	# the fork's licence and notice
	cp LICENSE "$DEST$PREFIX/doc/cdfs/LICENSE"
	cp NOTICE "$DEST$PREFIX/doc/cdfs/NOTICE"
	chmod 0644 "$DEST$PREFIX/doc/cdfs"/*
	# man page: /opt/amix/man/1m/mount_cdfs and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man "$HERE/man/mount_cdfs.1m" 1m
	amix_man_whatis
}
