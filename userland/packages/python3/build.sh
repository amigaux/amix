# build.sh -- CPython hooks for build/pkg/pkgbuild.sh (STYLE=hooks).
# Hooks only; the reasons are in README.md.

ASM_REVIEWED="libffi and other-platform assembly in the tree; _ctypes is not built"
PTH="$AMIX_BUILD_ROOT/pth/dest$PREFIX"
ZL="$AMIX_BUILD_ROOT/zlib/dest$PREFIX"

# the modules linked into the interpreter (isoriano's set, with zlib)
setup_local() {
	cat <<SL
*static*
math mathmodule.c
_struct _struct.c
binascii binascii.c
_json _json.c
_random _randommodule.c
_datetime _datetimemodule.c
select selectmodule.c
_md5 md5module.c
_sha1 sha1module.c
_sha256 sha256module.c
_sha512 sha512module.c
_sha3 _sha3/sha3module.c
_blake2 _blake2/blake2module.c _blake2/blake2b_impl.c _blake2/blake2s_impl.c
zlib zlibmodule.c -lz
SL
}

cc1() { echo "$CC $*" >> "$BUILD/make.log"; $CC "$@" >> "$BUILD/make.log" 2>&1; }

build() {
	for d in "$PTH/lib/libpthread.a" "$ZL/lib/libz.a"; do
		[ -f "$d" ] || { echo "[FAIL] no $d: build pth and zlib first (BUILD_DEPENDS)" >&2; exit 1; }
	done
	T=$PWD K=$BUILD/compat
	mkdir -p "$K"
	for n in math wide clock time environ; do
		cc1 $AMIX_CFLAGS -fno-strict-aliasing -I"$HERE/port/include" -c "$HERE/port/amix-$n.c" -o "$K/amix-$n.o" || {
			echo "[FAIL] port/amix-$n.c" >&2; exit 1; }
	done
	# a Python for the build host: the cross build runs it (--with-build-python)
	rm -rf "$BUILD/hostpy"; mkdir -p "$BUILD/hostpy"
	( cd "$BUILD/hostpy" && env -u CC -u CXX -u AR -u RANLIB -u LD -u NM -u STRIP -u OBJDUMP -u READELF \
		CC=gcc CFLAGS= "$T/configure" --without-ensurepip --disable-shared > configure.log 2>&1 &&
		env -u AR -u RANLIB make -j8 all > make.log 2>&1 ) || { echo "[FAIL] host python; see $BUILD/hostpy" >&2; exit 1; }
	echo "  host python: $("$BUILD/hostpy/python" -E -S --version)"
	LIBS1="$K/amix-math.o $K/amix-wide.o $K/amix-clock.o $K/amix-time.o $K/amix-environ.o -lz -lm -lpthread -lpth -ldl -lsocket -lnsl"
	rm -rf "$BUILD/x"; mkdir -p "$BUILD/x"; cd "$BUILD/x"
	READELF=$(dirname "$AR")/$AMIX_TARGET-readelf \
	CFLAGS="$AMIX_CFLAGS -fno-strict-aliasing" CPPFLAGS="-I$HERE/port/include -I$PTH/include -I$ZL/include" \
	LDFLAGS="-L$PTH/lib -L$ZL/lib" LIBS="$LIBS1" ac_cv_file__dev_ptmx=yes ac_cv_file__dev_ptc=no \
	"$T/configure" --build=x86_64-pc-linux-gnu --host=m68k-cbm-sysv4 --with-build-python="$BUILD/hostpy/python" \
		--prefix="$PREFIX" --disable-shared --disable-ipv6 --without-ensurepip --without-c-locale-coercion \
		--disable-test-modules > "$BUILD/configure.log" 2>&1 || { echo "[FAIL] configure; see $BUILD/configure.log" >&2; exit 1; }
	setup_local > Modules/Setup.local
	make -j8 python CPPFLAGS="-I$HERE/port/include -I$PTH/include -I$ZL/include -std=gnu11 -include $HERE/port/amix-python.h" \
		CFLAGS="$AMIX_CFLAGS -fno-strict-aliasing -DTHREAD_STACK_SIZE=1048576" LIBS="$LIBS1" LDFLAGS="-L$PTH/lib -L$ZL/lib" \
		>> "$BUILD/make.log" 2>&1 || { echo "[FAIL] make python; see $BUILD/make.log" >&2; exit 1; }
	# the sysconfig data (_sysconfigdata__amigaunix_.py), written by the build python
	make pybuilddir.txt > "$BUILD/pybuilddir.log" 2>&1 || { echo "[FAIL] pybuilddir.txt; see $BUILD/pybuilddir.log" >&2; exit 1; }
	cd "$T"
}

stage() {
	b="$DEST$PREFIX" L=$DEST$PREFIX/lib/python3.11
	mkdir -p "$b/bin" "$L/lib-dynload" "$b/doc/python3"
	cp "$BUILD/x/python" "$b/bin/python3.11"
	# python3: PYTHONHASHSEED=0 only while /dev/urandom cannot be read (README)
	cp "$HERE/python3.sh" "$b/bin/python3"
	# the standard library, less what this build cannot run or does not ship
	( cd Lib && tar cf - . ) | ( cd "$L" && tar xf - )
	( cd "$L" && rm -rf test idlelib tkinter turtledemo turtle.py ensurepip lib2to3/tests \
		distutils/tests unittest/test ctypes sqlite3 venv site-packages/README.txt \
		$(find . -name __pycache__ -o -name 'Makefile*' -o -name '*.exe') )
	mkdir -p "$L/site-packages"
	cp "$BUILD/x/build/lib.amigaunix-m68k-3.11/_sysconfigdata__amigaunix_.py" "$L/"
	# build-host paths out of the sysconfig data (the include and library dirs of this build)
	sed -i -e "s|$AMIX_REPO_ROOT|/build|g" -e "s|$HOME|/build|g" "$L/_sysconfigdata__amigaunix_.py"
	# bytecode: the build host's python is the same 3.11.18; unchecked-hash pycs are
	# byte-reproducible and never rewritten (the directory is root's)
	"$BUILD/hostpy/python" -E -m compileall -q -j0 --invalidation-mode unchecked-hash \
		-d "$PREFIX/lib/python3.11" "$L" > "$BUILD/compileall.log" 2>&1 || {
		echo "[FAIL] compileall; see $BUILD/compileall.log" >&2; exit 1; }
	cp LICENSE README.rst "$b/doc/python3/"
	cp "$HERE/port/LICENSE.PSF" "$b/doc/python3/LICENSE.port"
	find "$L" -type d -exec chmod 0755 {} +; find "$L" -type f -exec chmod 0644 {} +
	chmod 0755 "$b/bin/python3" "$b/bin/python3.11"; chmod 0644 "$b"/doc/python3/*
	# man pages: /opt/amix/man/<sect>/<name> and whatis.d (docs/man-pages.md)
	. "$HERE/../tools/manpages.sh"
	amix_man Misc/python.man 1 python3.11
	amix_man_alias python3 1 python3.11
	amix_man_whatis
}

# upstream's empty files: package markers and a frozen-module test package
ZERO_OK="/opt/amix/lib/python3.11/email/mime/__init__.py /opt/amix/lib/python3.11/urllib/__init__.py /opt/amix/lib/python3.11/pydoc_data/__init__.py /opt/amix/lib/python3.11/__phello__/ham/__init__.py /opt/amix/lib/python3.11/__phello__/ham/eggs.py"
