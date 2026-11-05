# build.sh -- libcfix hooks: nothing is compiled.  The stage hook takes the
# stock /usr/lib/libc.so.1 from amix-system, checks it against
# system/MANIFEST.sha256, checks the bytes it changes, changes them, and checks
# the result's sha256.  The reasons are in README.md.

STOCK_SHA=09d52bb3ff5a691c9ec4b057f3b3cad484ba98ce8d057a892082ca2010dda46c
FIXED_SHA=f57f624ba2d325dee8839adb5c7fcf1559f7a11ecdc21d870dcd78f75831cf52

build() {
	:
}

# lc_at OFFSET-HEX HEX: the file's bytes at OFFSET are HEX, or stop
lc_at() {
	got=$(od -An -tx1 -j $((0x$1)) -N $((${#2} / 2)) "$LC" | tr -d ' \n')
	[ "$got" = "$2" ] || { echo "[FAIL] libc.so.1 at 0x$1: $got, not $2" >&2; exit 1; }
}

# lc_put OFFSET-HEX HEX: write HEX at OFFSET, in place, and read it back
lc_put() {
	h=$2; : > "$BUILD/lc.bytes"
	while [ -n "$h" ]; do
		printf "\\$(printf '%03o' "0x$(echo "$h" | cut -c1-2)")" >> "$BUILD/lc.bytes"
		h=${h#??}
	done
	[ "$(wc -c < "$BUILD/lc.bytes")" -eq $((${#2} / 2)) ] || { echo "[FAIL] lc_put 0x$1: byte count" >&2; exit 1; }
	dd if="$BUILD/lc.bytes" of="$LC" bs=1 seek=$((0x$1)) conv=notrunc 2>/dev/null || exit 1
	lc_at "$1" "$2"
}

stage() {
	src="${AMIX_SYSTEM:-}/usr/lib/libc.so.1"
	[ -n "${AMIX_SYSTEM:-}" ] && [ -f "$src" ] && [ ! -L "$src" ] || {
		echo "[FAIL] no stock libc.so.1 at $src: AMIX_SYSTEM names an amix-system checkout" >&2; exit 1; }
	want=$(awk 'substr($0, 67) == "usr/lib/libc.so.1" { print substr($0, 1, 64) }' "$AMIX_REPO_ROOT/system/MANIFEST.sha256")
	got=$(sha256sum < "$src" | cut -c1-64)
	[ "$got" = "$want" ] && [ "$got" = "$STOCK_SHA" ] || {
		echo "[FAIL] $src is $got; system/MANIFEST.sha256 says ${want:-<none>}, this recipe patches $STOCK_SHA" >&2; exit 1; }
	LC=$BUILD/libc.so.1
	cp "$src" "$LC" && chmod u+w "$LC" || exit 1
	# 1. realloc: after _morecore fails, tp = Bottom and Bottom = NULL; the
	#    GOT load before it shortened from 8 bytes to 4 to make room
	lc_at 1cfb6 28750170000003c42654
	lc_put 1cfb6 286d03c4265442944e71
	# 2. malloc: a size with the top bit set goes to the existing return of NULL
	#    (bmi.w 1ce38); the GOT load at the end shortened from 8 bytes to 4
	lc_at 1ce38 42806000
	lc_at 1cc94 242e00087203c2826700000a200258802400948128750170000003b4
	lc_put 1cc94 242e00086b00019e7203c2826700000a2002588024009481286d03b4
	# 3. _morecore: a growth that comes out negative goes to its return of NULL
	#    (bmi.s 1d314); the GOT load at 1d2dc shortened, the 26 bytes after it
	#    moved down 4, their branches relative inside them
	lc_at 1d2dc 28750170000003c8
	lc_at 1d314 42806000
	tail=$(od -An -tx1 -j $((0x1d2e4)) -N 26 "$LC" | tr -d ' \n')
	[ "${tail%e7a2}" != "$tail" ] || { echo "[FAIL] libc.so.1 at 0x1d2fc: not asl.l" >&2; exit 1; }
	lc_put 1d2dc 286d03c8$tail
	lc_put 1d2fa 6b184e71
	got=$(sha256sum < "$LC" | cut -c1-64)
	[ "$got" = "$FIXED_SHA" ] || { echo "[FAIL] the patched libc.so.1 is $got, not $FIXED_SHA" >&2; exit 1; }
	mkdir -p "$DEST/usr/lib" "$DEST$PREFIX/doc/libcfix"
	cp "$LC" "$DEST/usr/lib/libc.so.1"
	chmod 0755 "$DEST/usr/lib/libc.so.1"
	cp "$HERE/README.md" "$DEST$PREFIX/doc/libcfix/README.md"
	cp "$HERE/../LICENSE" "$DEST$PREFIX/doc/libcfix/LICENSE.amix"	# the patch bytes and this recipe: MIT
	chmod 0644 "$DEST$PREFIX/doc/libcfix/README.md" "$DEST$PREFIX/doc/libcfix/LICENSE.amix"
	echo "  libc.so.1: stock $STOCK_SHA, patched $FIXED_SHA"
}
