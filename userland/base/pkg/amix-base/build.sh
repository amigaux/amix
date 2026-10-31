# amix-base build hooks. The source tree is a copy of userland/base.

# dlpi-mac, with the recipe's compiler (GCC 14, T-56 D6): the boot path
# links only the stock libc.so.1, nothing from /opt/amix
# (compile and link apart: the harness's gates read the compile line)
build() {
	echo "$CC $AMIX_CFLAGS -c -o dlpi-mac.o net/dlpi-mac/dlpi-mac.c" >> "$BUILD/make.log"
	$CC $AMIX_CFLAGS -c -o dlpi-mac.o net/dlpi-mac/dlpi-mac.c >> "$BUILD/make.log" 2>&1 || return 1
	echo "$CC $AMIX_CFLAGS -o dlpi-mac dlpi-mac.o" >> "$BUILD/make.log"
	$CC $AMIX_CFLAGS -o dlpi-mac dlpi-mac.o >> "$BUILD/make.log" 2>&1
}

# put <mode> <source> <payload path>
put() {
	mkdir -p "$DEST`dirname "$3"`"
	cp "$2" "$DEST$3"
	chmod "$1" "$DEST$3"
}

stage() {
	put 0755 dlpi-mac /usr/sbin/dlpi-mac
	put 0755 net/ifup /usr/sbin/ifup
	put 0755 net/ifdown /usr/sbin/ifdown
	put 0444 rc/rc.subr /usr/lib/amix/rc.subr
	put 0444 net/ifup.subr /usr/lib/inet/ifup.subr
	put 0555 net/dhcpc-hook /usr/lib/inet/dhcpc-hook
	put 0555 man/man.sh /usr/amix/bin/man
	# the one script and its hard links, recorded as stock core records them
	# (the file is S69inet, the rest link to it): another shape is an
	# "object type change" stock pkgadd ignores, leaving the old file
	put 0444 net/inetinit /etc/rc2.d/S69inet
	for l in init.d/inetinit rc0.d/K69inet rc1.d/K69inet; do
		mkdir -p "$DEST/etc/`dirname $l`"
		ln "$DEST/etc/rc2.d/S69inet" "$DEST/etc/$l"
	done
	put 0444 rc/devnodes /etc/init.d/devnodes
	mkdir -p "$DEST/etc/rc2.d"
	ln "$DEST/etc/init.d/devnodes" "$DEST/etc/rc2.d/S20devnodes"
	# the swap step in the stock swap script's place and shape (S90swap the
	# file, init.d/swap and K05swap linked to it)
	put 0444 rc/swap /etc/rc2.d/S90swap
	for l in init.d/swap rc0.d/K05swap; do
		mkdir -p "$DEST/etc/`dirname $l`"
		ln "$DEST/etc/rc2.d/S90swap" "$DEST/etc/$l"
	done
	# the display set-up (P-36 W9): /etc/display is the admin's, not here
	put 0444 display/display /etc/init.d/display
	ln "$DEST/etc/init.d/display" "$DEST/etc/rc2.d/S95display"
	put 0444 display/display.d/native /etc/display.d/native
	put 0555 display/xstart /usr/amix/bin/xstart
	put 0444 display/display.subr /usr/lib/amix/display.subr
	put 0555 display/xsession /usr/lib/amix/xsession
	put 0444 net/network-config /etc/inet/network-config
	put 0444 net/rc.inet /etc/inet/rc.inet
	put 0444 net/link.d/aen /etc/inet/link.d/aen
	put 0444 etc/profile.d/amix-base.sh /etc/profile.d/amix-base.sh
	# the stock /etc/profile (amix-system, sha256-checked) plus our lines
	mkdir -p "$DEST/etc"
	sh etc/mkprofile.sh "$AMIX_SYSTEM" "$REPO/system/MANIFEST.sha256" "$DEST/etc/profile"
	chmod 0644 "$DEST/etc/profile"
	# the stock /etc/inittab with the dlm line first among sysinit (C3-5 5)
	sh etc/mkinittab.sh "$AMIX_SYSTEM" "$REPO/system/MANIFEST.sha256" "$DEST/etc/inittab"
	chmod 0664 "$DEST/etc/inittab"
	put 0644 man/man.1 /opt/amix/man/1/man
	put 0644 rc/rc.subr.1m /opt/amix/man/1m/rc.subr
	put 0644 rc/devnodes.1m /opt/amix/man/1m/devnodes
	put 0644 net/dlpi-mac/dlpi-mac.1m /opt/amix/man/1m/dlpi-mac
	put 0644 net/ifup.1m /opt/amix/man/1m/ifup
	put 0644 net/ifdown.1m /opt/amix/man/1m/ifdown
	put 0644 rc/rc.conf.4 /opt/amix/man/4/rc.conf
	put 0644 net/interfaces.4 /opt/amix/man/4/interfaces
	put 0644 net/link.d.4 /opt/amix/man/4/link.d
	put 0644 net/network-config.4 /opt/amix/man/4/network-config
	put 0644 net/rc.inet.4 /opt/amix/man/4/rc.inet
	put 0644 etc/profile.4 /opt/amix/man/4/profile
	put 0644 etc/profile.d.4 /opt/amix/man/4/profile.d
	put 0644 etc/nodename.4 /opt/amix/man/4/nodename
	put 0644 etc/inittab.4 /opt/amix/man/4/inittab
	put 0644 display/display.4 /opt/amix/man/4/display
	put 0644 display/display.d.4 /opt/amix/man/4/display.d
	put 0644 display/xstart.1 /opt/amix/man/1/xstart
	put 0644 man/amxbase.whatis /opt/amix/man/whatis.d/amxbase
	for s in 1 1m 3 4 5 8; do
		mkdir -p "$DEST/var/opt/amix/catman/$s"
	done
	mkdir -p "$DEST/var/adm/rclog" "$DEST/var/inet"
}
