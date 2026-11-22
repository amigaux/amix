# cxxrt build hooks. Nothing is compiled: libstdc++.so.6 is the pinned gcc14
# prefix's, and the source tree holds the licence texts (GCC's runtime
# library exception with the GPL it grants on).

build() {
	:
}

stage() {
	mkdir -p "$DEST/usr/lib" "$DEST/opt/amix/doc/cxxrt"
	cp "$AMIX_GCC14_PREFIX/m68k-elf/lib/cxxrt/libstdc++.so.6" "$DEST/usr/lib/libstdc++.so.6"
	chmod 0755 "$DEST/usr/lib/libstdc++.so.6"
	for f in COPYING.RUNTIME COPYING3; do
		cp "$f" "$DEST/opt/amix/doc/cxxrt/$f"
		chmod 0644 "$DEST/opt/amix/doc/cxxrt/$f"
	done
}
