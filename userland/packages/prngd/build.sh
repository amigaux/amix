# build.sh -- prngd hooks for build/pkg/pkgbuild.sh.
# Hooks only; the reasons are in README.md.

# the config and seed files under /opt/amix (make passes CFLAGS through a
# shell, hence the escaped quotes); socket calls declared (amix-decls.h)
MAKE_CFLAGS="-include $AMIX_GCC14_DECLS -DCONFIGFILE=\\\"$PREFIX/etc/prngd/prngd.conf\\\" -DRANDSAVENAME=\\\"$PREFIX/etc/prngd/prngd-seed\\\""

# prngd and upstream's tools/prngd-ctl (make's built-in rule); -lsocket
# -lnsl in that order (LDFLAGS precedes SYSLIBS on prngd's link line)
make_args() {
	echo LDFLAGS=-lsocket SYSLIBS=-lnsl LDLIBS=-lnsl prngd tools/prngd-ctl
}

post_build() {
	strings prngd | grep "^$PREFIX/etc/prngd/prngd.conf\$" > /dev/null &&
	strings prngd | grep "^$PREFIX/etc/prngd/prngd-seed\$" > /dev/null || {
		echo "[FAIL] prngd's default config/seed paths are not under $PREFIX/etc/prngd" >&2; exit 1; }
	echo "  defaults  $PREFIX/etc/prngd/prngd.conf, prngd-seed"
}

stage() {
	mkdir -p "$DEST$PREFIX/sbin" "$DEST$PREFIX/bin" "$DEST$PREFIX/etc/prngd" \
	         "$DEST$PREFIX/etc/init.d" "$DEST$PREFIX/doc/prngd"
	cp prngd "$DEST$PREFIX/sbin/prngd"
	cp tools/prngd-ctl "$DEST$PREFIX/bin/prngd-ctl"
	cp "$HERE/prngd.conf" "$DEST$PREFIX/etc/prngd/prngd.conf"
	cp "$HERE/prngd.rc" "$DEST$PREFIX/etc/init.d/prngd"
	cp 00README 00DESIGN ChangeLog "$DEST$PREFIX/doc/prngd/"
	cp 00README.gatherers "$DEST$PREFIX/doc/prngd/README.gather"	# s5: <= 14 bytes
	# the binaries carry bsd-daemon.c (4-clause UCB), tools/prngd-ctl.c (BSD)
	# and sha1.c (free): their notices travel with them; 00README has prngd's own
	{ for f in bsd-daemon.c tools/prngd-ctl.c sha1.c; do
		echo "==== $f"; sed -n '1,/\*\//p' "$f"; echo; done; } > "$DEST$PREFIX/doc/prngd/LICENSE"
	chmod 0755 "$DEST$PREFIX/sbin/prngd" "$DEST$PREFIX/bin/prngd-ctl" "$DEST$PREFIX/etc/init.d/prngd"
	chmod 0644 "$DEST$PREFIX/etc/prngd/prngd.conf" "$DEST$PREFIX/doc/prngd"/*
	chmod 0700 "$DEST$PREFIX/etc/prngd"
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man prngd.man 1 prngd
	amix_man "$HERE/man/prngd-ctl.1" 1
	amix_man_whatis
}
