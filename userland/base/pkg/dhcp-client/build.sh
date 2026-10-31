# dhcp-client build hooks. The source tree is a copy of userland/base.

# dhcpc, with the period compiler; libsocket from its archive and the stub
# libc archive after it, as dhcpc/build.sh links it (select is static there)
build() {
	set -- -O -m68020 -o dhcpc.out dhcpc/dhcpc.c -lnsl \
	    "$AMIX_SYSROOT/usr/lib/libsocket.a" "$AMIX_SYSROOT/usr/ccs/lib/libc.so"
	echo "$CC $*" >> "$BUILD/make.log"
	"$CC" "$@" 2>&1 | grep -v -e 'within comment' -e 'defined but not used' >> "$BUILD/make.log" || :
	[ -f dhcpc.out ] && [ -s dhcpc.out ]
}

put() {
	mkdir -p "$DEST`dirname "$3"`"
	cp "$2" "$DEST$3"
	chmod "$1" "$DEST$3"
}

stage() {
	put 0755 dhcpc.out /usr/sbin/dhcpc
	put 0644 dhcpc/dhcpc.1m /opt/amix/man/1m/dhcpc
	put 0644 dhcpc/dhcpc.whatis /opt/amix/man/whatis.d/dhcpc
	mkdir -p "$DEST/var/inet/dhcpc"
}
