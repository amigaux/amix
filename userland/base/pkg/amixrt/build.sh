# amixrt build hooks. Nothing is compiled: libamixrt.so.1 is the pinned gcc14
# prefix's, and the source tree holds the licence texts (libamixc99's MIT,
# and GCC's runtime library exception with the GPL it grants on).

build() {
	:
}

stage() {
	mkdir -p "$DEST/usr/lib" "$DEST/opt/amix/doc/amixrt"
	cp "$AMIX_GCC14_PREFIX/m68k-elf/lib/amixrt/libamixrt.so.1" "$DEST/usr/lib/libamixrt.so.1"
	chmod 0755 "$DEST/usr/lib/libamixrt.so.1"
	for f in LICENSE.libamixc99 COPYING.RUNTIME COPYING3; do
		cp "$f" "$DEST/opt/amix/doc/amixrt/$f"
		chmod 0644 "$DEST/opt/amix/doc/amixrt/$f"
	done
}
