# build.sh -- rdate hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.  Four C files, compiled here:
# upstream's autotools want libbsd for arc4random, which patch 01 no
# longer calls, and nothing else of configure's answers is used.

RD_INCS="-include $AMIX_GCC14_DECLS -include $HERE/port/amix-rdate.h"

cc_one() {	# cc_one <source> <object>
	echo "$CC $RD_INCS $AMIX_CFLAGS -c $1 -o $2" >> "$BUILD/make.log"
	$CC $RD_INCS $AMIX_CFLAGS -c "$1" -o "$2" 2> "$2.warn" || {
		echo "[FAIL] compiling $1" >&2; cat "$2.warn" >&2; exit 1; }
	cat "$2.warn" >> "$BUILD/make.log"
}

build() {
	for f in rdate ntp rfc868time; do
		cc_one "src/$f.c" "src/$f.o"
	done
	cc_one "$HERE/port/amix-rdate.c" amix-rdate.o
	# the resolver and the sockets: libsocket, then libnsl
	echo "$CC -o rdate src/rdate.o src/ntp.o src/rfc868time.o amix-rdate.o -lsocket -lnsl" >> "$BUILD/make.log"
	$CC -o rdate src/rdate.o src/ntp.o src/rfc868time.o amix-rdate.o -lsocket -lnsl >> "$BUILD/make.log" 2>&1 || {
		echo "[FAIL] rdate did not link" >&2; tail -20 "$BUILD/make.log" >&2; exit 1; }
}

post_build() {
	# no floating point: the program must run on an FPU-less 68LC040/060
	# without the kernel's emulator
	if $OBJDUMP -d rdate | grep -E '	f(s|d)?(move|add|sub|mul|div|cmp|tst|int|abs|neg|sqrt)' > /dev/null; then
		echo "[FAIL] rdate carries FPU instructions" >&2; exit 1
	fi
	echo "  fpu       none"
	# the clock is stepped by libc's settimeofday (stime) and slewed by adjtime
	for s in settimeofday adjtime getaddrinfo; do
		$NM rdate | grep " T _\{0,1\}$s\$" > /dev/null || {
			echo "[FAIL] rdate does not define or link $s" >&2; exit 1; }
	done
	echo "  clock     settimeofday (stime), adjtime; getaddrinfo from port/"
}

stage() {
	mkdir -p "$DEST$PREFIX/sbin" "$DEST$PREFIX/doc/rdate"
	cp rdate "$DEST$PREFIX/sbin/rdate"
	chmod 0755 "$DEST$PREFIX/sbin/rdate"
	# the licences: rdate.c and rfc868time.c (Zoulas, BSD 4-clause), ntp.c
	# (Maclaren/Cambridge, BSD 3-clause), and ours (MIT) for port/ and the patch
	d=$DEST$PREFIX/doc/rdate
	{ for f in src/rdate.c src/rfc868time.c src/ntp.c; do
		echo "==== $f"; sed -n '1,/^ \*\/$/p' "$f"; echo; done; } > "$d/LICENSE"
	cp LICENSE "$d/LICENSES"
	cp "$HERE/../LICENSE" "$d/LICENSE.amix"
	cp NEWS "$d/NEWS"
	chmod 0644 "$d"/*
	. "$HERE/../tools/manpages.sh"
	amix_man "$HERE/man/rdate.1m" 1m rdate
	amix_man_whatis
}
