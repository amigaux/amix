# build.sh -- libsockfix hooks: nothing is compiled.  The stage hook takes the
# stock /usr/lib/libsockhost.so and /usr/lib/libsockdns.so from amix-system,
# checks each against system/MANIFEST.sha256, checks the 60 bytes it rewrites,
# rewrites them, reads them back and checks the result's sha256.  It also
# stages the 60 stock bytes of each file as data (the removal puts them back),
# the libsockfix command, its page and the README.  The reasons are in README.md.

build() {
	:
}

# the two libraries: name, offset of the rewritten range (hex), the stock and
# the fixed sha256, the 60 stock and the 60 fixed bytes
HOST_OFF=b2ee
HOST_STOCK=29975421b4e4cb0066c9877b13b44dcbce0eb9bc41599c3dc79691d92516a67d
HOST_FIXED=f37c4fac4081ae3fda44e2ba02dcd3f7b1fc8945254c94d22e7085bf1453fba9
HOST_OLD=4bfb01700000376c246e0008206e000c7030d0a800082400d4a8000458822f024878000161ffffff9d602548001066000014720c2875017000000010
HOST_NEW=4bfa376c246e00082f2a001061009da0206e000c7030d0a800082400d4a8000458822f024878000161ffffff9d5c2548001066000010720c286d0010
DNS_OFF=e37e
DNS_STOCK=607477a5385db153450d717a02ba7c013ae2fb660768f6a3e5a7988be6bdc816
DNS_FIXED=798b1ae661d9288a66e913d7873df6c0cc9c55eea72170c416c65e1e8bd74832
DNS_OLD=4bfb017000003af4246e0008206e000c7030d0a800082400d4a8000458822f024878000161ffffff80bc2548001066000014720c2875017000000010
DNS_NEW=4bfa3af4246e00082f2a0010610080fc206e000c7030d0a800082400d4a8000458822f024878000161ffffff80b82548001066000010720c286d0010

# ls_at FILE OFFSET-HEX HEX: the file's bytes at OFFSET are HEX, or stop
ls_at() {
	got=$(od -An -tx1 -j $((0x$2)) -N $((${#3} / 2)) "$1" | tr -d ' \n')
	[ "$got" = "$3" ] || { echo "[FAIL] $(basename "$1") at 0x$2: $got, not $3" >&2; exit 1; }
}

# ls_bytes HEX OUT: write the bytes HEX to the file OUT
ls_bytes() {
	h=$1; : > "$2"
	while [ -n "$h" ]; do
		printf "\\$(printf '%03o' "0x$(echo "$h" | cut -c1-2)")" >> "$2"
		h=${h#??}
	done
	[ "$(wc -c < "$2")" -eq $((${#1} / 2)) ] || { echo "[FAIL] ls_bytes $2: byte count" >&2; exit 1; }
}

# ls_fix NAME OFF STOCK FIXED OLD NEW: check, patch and check one library;
# the stock bytes go to $BUILD/NAME.stock
ls_fix() {
	src="${AMIX_SYSTEM:-}/usr/lib/$1"
	[ -n "${AMIX_SYSTEM:-}" ] && [ -f "$src" ] && [ ! -L "$src" ] || {
		echo "[FAIL] no stock $1 at $src: AMIX_SYSTEM names an amix-system checkout" >&2; exit 1; }
	want=$(awk -v p="usr/lib/$1" 'substr($0, 67) == p { print substr($0, 1, 64) }' "$AMIX_REPO_ROOT/system/MANIFEST.sha256")
	got=$(sha256sum < "$src" | cut -c1-64)
	[ "$got" = "$want" ] && [ "$got" = "$3" ] || {
		echo "[FAIL] $src is $got; system/MANIFEST.sha256 says ${want:-<none>}, this recipe patches $3" >&2; exit 1; }
	f=$BUILD/$1
	cp "$src" "$f" && chmod u+w "$f" || exit 1
	ls_at "$f" "$2" "$5"
	ls_bytes "$5" "$BUILD/$1.stock"
	ls_bytes "$6" "$BUILD/$1.fixed"
	dd if="$BUILD/$1.fixed" of="$f" bs=1 seek=$((0x$2)) conv=notrunc 2>/dev/null || exit 1
	ls_at "$f" "$2" "$6"
	got=$(sha256sum < "$f" | cut -c1-64)
	[ "$got" = "$4" ] || { echo "[FAIL] the patched $1 is $got, not $4" >&2; exit 1; }
	echo "  $1: stock $3, patched $4 (60 bytes at 0x$2)"
}

stage() {
	ls_fix libsockhost.so $HOST_OFF $HOST_STOCK $HOST_FIXED $HOST_OLD $HOST_NEW
	ls_fix libsockdns.so $DNS_OFF $DNS_STOCK $DNS_FIXED $DNS_OLD $DNS_NEW
	mkdir -p "$DEST/usr/lib" "$DEST$PREFIX/lib/libsockfix" "$DEST$PREFIX/sbin" "$DEST$PREFIX/doc/libsockfix"
	for n in libsockhost.so libsockdns.so; do
		cp "$BUILD/$n" "$DEST/usr/lib/$n"
		chmod 0444 "$DEST/usr/lib/$n"
	done
	# the stock bytes of each range, which the removal writes back
	cp "$BUILD/libsockhost.so.stock" "$DEST$PREFIX/lib/libsockfix/host.stock"
	cp "$BUILD/libsockdns.so.stock" "$DEST$PREFIX/lib/libsockfix/dns.stock"
	chmod 0444 "$DEST$PREFIX/lib/libsockfix/host.stock" "$DEST$PREFIX/lib/libsockfix/dns.stock"
	cp "$HERE/scripts/libsockfix" "$DEST$PREFIX/sbin/libsockfix"
	chmod 0555 "$DEST$PREFIX/sbin/libsockfix"
	cp "$HERE/README.md" "$DEST$PREFIX/doc/libsockfix/README.md"
	cp "$HERE/../LICENSE" "$DEST$PREFIX/doc/libsockfix/LICENSE.amix"	# the patch bytes and this recipe: MIT
	chmod 0644 "$DEST$PREFIX/doc/libsockfix/README.md" "$DEST$PREFIX/doc/libsockfix/LICENSE.amix"
	. "$HERE/../tools/manpages.sh"
	amix_man "$HERE/man/libsockfix.1m" 1m
	amix_man_whatis
}
