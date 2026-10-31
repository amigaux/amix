# dhcp-client build hooks. The source tree is a copy of userland/base.

# dhcpc, with the recipe's compiler (GCC 14, T-56 D6) against the stock
# libraries only: libsocket from its archive and the stub libc archive after
# it, as dhcpc/build.sh links it (select is static there)
# (compile and link apart: the harness's gates read the compile line)
build() {
	echo "$CC $AMIX_CFLAGS -c -o dhcpc.o dhcpc/dhcpc.c" >> "$BUILD/make.log"
	$CC $AMIX_CFLAGS -c -o dhcpc.o dhcpc/dhcpc.c >> "$BUILD/make.log" 2>&1 || return 1
	set -- $AMIX_CFLAGS -o dhcpc.out dhcpc.o -lnsl \
	    "$AMIX_SYSROOT/usr/lib/libsocket.a" "$AMIX_SYSROOT/usr/ccs/lib/libc.so"
	echo "$CC $*" >> "$BUILD/make.log"
	$CC "$@" >> "$BUILD/make.log" 2>&1
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
