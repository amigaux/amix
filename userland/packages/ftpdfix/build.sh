# build.sh -- ftpdfix hooks: nothing is compiled.  The stage hook takes the
# stock /usr/sbin/in.ftpd from amix-system, checks it against
# system/MANIFEST.sha256, checks the bytes it changes, changes them, reads
# them back, and checks the result's sha256.  The reasons and the assembly
# of the new routine are in README.md.  Text file offsets are the addresses
# less 0x80000000.

STOCK_SHA=29048aef103a02d5975b1ce4571d770ad88c0cb1b7a5efdc76cd9c6a1bb3940d
FIXED_SHA=6a7c40211733b6847efe1d5bdf75c0a58b9d00a77eff3bee430a941e59487de2

build() {
	:
}

# fd_at OFFSET-HEX HEX: the file's bytes at OFFSET are HEX, or stop
fd_at() {
	got=$(od -An -tx1 -j $((0x$1)) -N $((${#2} / 2)) "$FD" | tr -d ' \n')
	[ "$got" = "$2" ] || { echo "[FAIL] in.ftpd at 0x$1: $got, not $2" >&2; exit 1; }
}

# fd_put OFFSET-HEX HEX: write HEX at OFFSET, in place, and read it back
fd_put() {
	h=$2; : > "$BUILD/fd.bytes"
	while [ -n "$h" ]; do
		printf "\\$(printf '%03o' "0x$(echo "$h" | cut -c1-2)")" >> "$BUILD/fd.bytes"
		h=${h#??}
	done
	[ "$(wc -c < "$BUILD/fd.bytes")" -eq $((${#2} / 2)) ] || { echo "[FAIL] fd_put 0x$1: byte count" >&2; exit 1; }
	dd if="$BUILD/fd.bytes" of="$FD" bs=1 seek=$((0x$1)) conv=notrunc 2>/dev/null || exit 1
	fd_at "$1" "$2"
}

stage() {
	src="${AMIX_SYSTEM:-}/usr/sbin/in.ftpd"
	[ -n "${AMIX_SYSTEM:-}" ] && [ -f "$src" ] && [ ! -L "$src" ] || {
		echo "[FAIL] no stock in.ftpd at $src: AMIX_SYSTEM names an amix-system checkout" >&2; exit 1; }
	want=$(awk 'substr($0, 67) == "usr/sbin/in.ftpd" { print substr($0, 1, 64) }' "$AMIX_REPO_ROOT/system/MANIFEST.sha256")
	got=$(sha256sum < "$src" | cut -c1-64)
	[ "$got" = "$want" ] && [ "$got" = "$STOCK_SHA" ] || {
		echo "[FAIL] $src is $got; system/MANIFEST.sha256 says ${want:-<none>}, this recipe patches $STOCK_SHA" >&2; exit 1; }
	FD=$BUILD/in.ftpd
	cp "$src" "$FD" && chmod u+w "$FD" || exit 1
	# 1. retrieve: the close of the data connection, fclose(dout) between
	#    the two sigset(SIGPIPE) calls, becomes dclose(dout):
	#    jsr fclose@plt -> jsr 0x80008106
	fd_at 286c 2d48ff542f2efff44eb98000181872ff23c18000
	fd_put 2874 4eb980008106
	# 2. dclose at 0x80008106, over _putspent (422 bytes, which nothing in
	#    the program calls): fflush; ioctl(fd, I_STR, {SI_SHUTDOWN, -1, 4,
	#    &1}); fcntl O_NONBLOCK; until time(0) + 60: read(256), ending at
	#    end of file or an error other than EAGAIN, a nap of
	#    _poll(NULL, 0, 20) after each EAGAIN; fclose.  Through the PLT:
	#    fflush 1944, ioctl 16c4, _fcntl 1d68, time 1a0c, read 18f4,
	#    _poll 1c78, fclose 1818; errno at 0x8000f39c
	fd_at 8106 4e56000048e70038
	fd_at 82ac 4e56dff0
	fd_put 8106 4e56feec48e730002f2e00084eb980001944584f206e000874001428000d70012d40ffec2d7c00004966fff070ff2d40fff470042d40fff841eeffec2d48fffc486efff02f3c000053082f024eb9800016c44fef000c4a806d00008a42a7487800032f024eb980001d684fef000c4a806d0000720080000000802f00487800042f024eb980001d684fef000c4a806d00005442a74eb980001a0c584f763cd68048780100486efeec2f024eb9800018f44fef000c4a80672c6e1c700bb0b98000f39c66204878001442a742a74eb980001c784fef000c42a74eb980001a0c584fb0836dbc2f2e00084eb980001818584f4cdf000c4e5e4e75
	# 3. dataconn, active mode: the SO_LINGER {1, 60} setsockopt is skipped;
	#    the SO_SNDBUF and SO_RCVBUF calls' 40 bytes of arguments are still
	#    popped: addaw #40,%sp; bras 0x80002e1a (the connect)
	fd_at 2de6 72012d41ffc8723c2d41ffccdefc00284878000870c8d08e2f00487800802f3c0000ffff2f398000f3d44eb98000169cdefc0014
	fd_at 2e1a 48780010
	fd_put 2de6 defc0028602e
	got=$(sha256sum < "$FD" | cut -c1-64)
	[ "$got" = "$FIXED_SHA" ] || { echo "[FAIL] the patched in.ftpd is $got, not $FIXED_SHA" >&2; exit 1; }
	mkdir -p "$DEST/usr/sbin" "$DEST$PREFIX/doc/ftpdfix"
	cp "$FD" "$DEST/usr/sbin/in.ftpd"
	chmod 0555 "$DEST/usr/sbin/in.ftpd"
	cp "$HERE/README.md" "$DEST$PREFIX/doc/ftpdfix/README.md"
	cp "$HERE/../LICENSE" "$DEST$PREFIX/doc/ftpdfix/LICENSE.amix"	# the patch bytes and this recipe: MIT
	chmod 0644 "$DEST$PREFIX/doc/ftpdfix/README.md" "$DEST$PREFIX/doc/ftpdfix/LICENSE.amix"
	# ftpdfix(1M); replaces.d/<PKG>, from MAN_REPLACES, tells man(1) that it
	# is the page of /usr/sbin/in.ftpd
	. "$HERE/../tools/manpages.sh"
	amix_man "$HERE/man/ftpdfix.1m" 1m
	amix_man_whatis
	amix_man_replaces
	echo "  in.ftpd: stock $STOCK_SHA, patched $FIXED_SHA"
}
