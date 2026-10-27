#!/bin/sh
#
# build.sh -- fetch, cross-configure, cross-build and package GNU gzip 1.3.12.
#
#     sh recipes/gzip/build.sh
#
# Outputs under the gitignored build/ tree:
#
#     build/gzip/src/gzip-1.3.12.tar.gz   the pinned tarball (cached)
#     build/gzip/work/gzip-1.3.12/        the extracted, patched, built tree
#     build/gzip/dest/                    the staged install tree
#     build/pkg/gzip-1.3.12.pkg           the datastream
#
# gzip is the highest day-one user value in batch 1: it is the first tool on the
# box that reads and writes the universal .gz format, which stock cannot touch
# (stock compression is 1985 LZW .Z only).  Its deflate is integer-only C; it
# links NOTHING from libacompat (measured: every undefined symbol resolves from
# the stock libc.so.1) -- so, like patch, it ships standalone.
#
# ---------------------------------------------------------------------------
# THE TWO THINGS THAT MADE IT BUILD (both in patches/, both measured)
#
# 1. match.S DISABLED.  gzip probes for an assembler it can use for the longest
#    -match inner loop; seeding gzip_cv_assembler=no forces the C path.  The SGS
#    '#'-is-a-comment trap (PORTING.md 2.2) means a mis-assembled .s is a valid
#    instruction with a clean exit, so imported asm is banned here.
#
# 2. THE gnulib HEADER WRAPPERS ARE BYPASSED BY THE CROSS WRAPPER.  gzip 1.3.12
#    ships lib/fcntl.h and lib/time.h -- gnulib replacements that add O_BINARY=0,
#    O_NOFOLLOW=0 and struct timespec on a system that lacks them.  They are
#    meant to shadow the system headers via the package's -I./lib.  But the
#    m68k-cbm-sysv4-gcc wrapper hard-codes -I<sysroot>/usr/include at the FRONT
#    of every compile (its common_cflags), AHEAD of -I./lib, so <fcntl.h> and
#    <time.h> resolve to the 1992 SVR4 headers and the gnulib wrappers never
#    win.  gzip therefore sees a pure SVR4 libc, and patches/01 fills the four
#    gaps that opens in gzip's own gzip.h, patches/02 the one in lib/utimens.h.
#    (Cross-repo note: the wrapper putting the sysroot include dir before the
#    package's own -I defeats gnulib header replacement for EVERY such package;
#    worth a gcc-cross-amix look.)

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

export AMIX_PREFIX=/opt/amix
AMIX_RECIPE_TOOLCHAINS="period gcc14"

. "$REPO/recipes/common/amix-env.sh"
. "$REPO/recipes/common/fetch.sh"
. "$REPO/recipes/common/pkgroll.sh"
. "$REPO/recipes/common/gates.sh"
. "$HERE/pin.sh"

PKG=gzip
VERSION=$GZIP_VERSION
# The PACKAGE version is the source version plus a package revision.  -2 is
# the 68060 re-mint (2026-10-05; no package may rely on kernel emulation of
# 68060-unimplemented instructions): the same source rebuilt through the
# wrapper's 64-bit multiply expansion (gcc-cross-amix 2ab2b22) -- new
# bytes, so a new catalog version; apkg_vercmp orders 1.3.12-2 above 1.3.12.
# Package revision by toolchain: the period build is -2 (the 68060 re-mint); a
# TOOLCHAIN=gcc14 build is new bytes and so a new revision (the userland
# switch, owner decision D-3 sec 9 and 2026-10-27): -3 was gcc14-cross-amix
# e316f1b (never published: pointers came back in %d0 only), -4 is cf461e3
# (pointers in %a0 and %d0, structs via %a0, as AMIX's compilers and libc);
# pkginfo is retagged in the work copy (amix_pkginfo_retag).
case "$AMIX_TOOLCHAIN" in
gcc14) PKGREV=4 ;;
*)     PKGREV=2 ;;
esac
PKGVERSION=$VERSION-$PKGREV

BUILD="$AMIX_BUILD_ROOT/gzip"
SRC="$BUILD/src"
WORKDIR="$BUILD/work"
TREE="$WORKDIR/gzip-$VERSION"
DEST="$BUILD/dest"
PKGOUT="$AMIX_BUILD_ROOT/pkg"

echo "=== GNU gzip $VERSION ==="
amix_env_banner
echo

mkdir -p "$SRC" "$WORKDIR" "$PKGOUT"

# ---------------------------------------------------------------------------
# 1. Fetch, verified BEFORE extraction.
# ---------------------------------------------------------------------------
echo "--- source ---"
amix_fetch "$GZIP_URL" "$GZIP_SHA256" "$SRC/gzip-$VERSION.tar.gz"
rm -rf "$TREE"
tar xzf "$SRC/gzip-$VERSION.tar.gz" -C "$WORKDIR"
[ -d "$TREE" ] || { echo "[FAIL] $TREE not produced by the tarball" >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 2. Patches -- applied in stated order (recipes/README).
# ---------------------------------------------------------------------------
echo "--- patches ---"
for p in "$HERE"/patches/*.patch; do
	echo "  applying $(basename "$p")"
	( cd "$TREE" && patch -p0 --batch --fuzz=0 < "$p" ) || {
		echo "[FAIL] patch $(basename "$p") did not apply cleanly" >&2; exit 1; }
done
# No .s/.S imported.  gzip's foreign-port dirs (msdos/*.asm, amiga/match.a) are
# never compiled and carry neither extension the gate scans for.
# TOOLCHAIN=gcc14 only: fixes for what GCC 14 reads that gcc 2.7 never did
# (gnulib's lib/time.h).  Applied after the shared patches; the period build
# never sees them.
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	for p in "$HERE"/patches-gcc14/*.patch; do
		echo "  applying gcc14 $(basename "$p")"
		( cd "$TREE" && patch -p0 --batch --fuzz=0 < "$p" ) || {
			echo "[FAIL] patch $(basename "$p") did not apply cleanly" >&2; exit 1; }
	done
fi
amix_gate_noasm "$TREE" || {
	echo "[FAIL] unexpected .s/.S assembly in the gzip tree." >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 3. Cross-configure.
# ---------------------------------------------------------------------------
# CPP=amix-cpp: the wrapper cannot preprocess (-E links instead), so autoconf
# would fall back to the BUILD host's /lib/cpp and read the host's headers
# (PORTING.md 4.1 / patch trap 1).  --disable-largefile: SVR4.0 has no LFS, and
# the probe is the kind that misfires under cross; disable it deterministically.
# gzip_cv_assembler=no: force the C longest_match, never the asm one.  DEFAULT
# __STDC__ view (no -D_POSIX_SOURCE): gzip uses plain signal() when the sigaction
# machinery is hidden (both struct sigaction and SA_NOCLDSTOP sit behind the same
# gate), which is the smaller, proven path.
echo "--- cross-configure ---"
cd "$TREE"
# TOOLCHAIN=gcc14 pins one configure answer to the period build's: GCC 14 links
# the SVR4 way (usr/ccs/lib/libc.so is libc.so.1 plus static members), so the
# lstat probe finds the static lstat.o the period link never saw.  With
# HAVE_LSTAT gzip would treat symbolic links differently from the bench-proven
# period build; pinned no (the assertion below requires it).  Accepted as GCC 14
# finds them, config.h diffed against the period build: HAVE_STDBOOL_H and
# HAVE__BOOL (the compiler's own C99 bool), HAVE_STDINT_H (the sysroot's compat
# stdint.h) and `restrict' left a keyword -- compiler features, no behaviour.
#
# And two gnulib header paths.  gnulib's replacement lib/fcntl.h includes the
# system header by its ABSOLUTE path (ABSOLUTE_FCNTL_H, found by preprocessing).
# GCC 14's include-fixed/fcntl.h and sys/time.h are C++-linkage wrappers that
# reach AMIX's header with #include_next -- and an #include_next in a file
# included by absolute path behaves as a plain #include, which finds gnulib's
# own lib/fcntl.h again (include-guarded), so AMIX's fcntl.h is never read and
# creat() is undeclared.  For C the wrapper adds nothing, so the two paths are
# pinned to the sysroot headers the wrappers forward to; the assertion after
# configure refuses any ABSOLUTE_ header that is an #include_next wrapper.
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	export ac_cv_func_lstat=no
	export gl_cv_absolute_fcntl_h="$AMIX_SYSROOT/usr/include/fcntl.h"
	export gl_cv_absolute_sys_time_h="$AMIX_SYSROOT/usr/include/sys/time.h"
fi
CC="$CC" \
CPP="$AMIX_CPP" \
CFLAGS="$AMIX_CFLAGS $AMIX_CONFIGURE_LENIENT" \
SHELL=/bin/sh \
./configure \
	--host="$AMIX_HOST_TRIPLET" \
	--prefix="$AMIX_PREFIX" \
	--disable-nls \
	--disable-largefile \
	gzip_cv_assembler=no \
	> "$BUILD/configure.log" 2>&1 || {
		echo "[FAIL] configure failed; see $BUILD/configure.log" >&2
		tail -20 "$BUILD/configure.log" >&2
		exit 1
	}

# Assert the answers a host CPP fallback or an enabled asm probe would get wrong.
echo "  asserting the cross-configure answers:"
if grep -q '^#define ASMV' lib/config.h; then
	echo "[FAIL] ASMV is defined -- the assembler match loop crept in (SGS-ASM)." >&2
	exit 1
fi
echo "    ASMV undefined (C longest_match)"
for f in $(sed -n 's/^#define ABSOLUTE_[A-Z_]*_H "\(.*\)"$/\1/p' lib/config.h); do
	if grep include_next "$f" >/dev/null 2>&1; then
		echo "[FAIL] config.h names $f as an absolute header; it is an #include_next" >&2
		echo "       wrapper, so the real header would never be read (see above)." >&2
		exit 1
	fi
done
echo "    no ABSOLUTE_*_H is an #include_next wrapper"
for want in 'HAVE_UTIME_H:present' 'HAVE_WORKING_UTIMES:absent' 'HAVE_LSTAT:absent'; do
	sym=${want%:*}; exp=${want#*:}
	if grep -q "^#define $sym 1\$" lib/config.h; then got=present; else got=absent; fi
	if [ "$got" != "$exp" ]; then
		echo "[FAIL] config.h says $sym is $got, expected $exp -- a probe may have" >&2
		echo "       read the BUILD host's headers (CPP fallback, PORTING.md 4.1)." >&2
		exit 1
	fi
	echo "    $sym $got"
done
echo

# ---------------------------------------------------------------------------
# 4. Build.
# ---------------------------------------------------------------------------
echo "--- make ---"
# gcc14: configure ran lenient; the build gets the strict CFLAGS back.
set --
[ "$AMIX_TOOLCHAIN" = gcc14 ] && set -- CFLAGS="$AMIX_CFLAGS"
make "$@" > "$BUILD/make.log" 2>&1 || {
	echo "[FAIL] make failed; see $BUILD/make.log" >&2
	tail -25 "$BUILD/make.log" >&2
	exit 1
}
if grep 'implicit declaration' "$BUILD/make.log" >/dev/null 2>&1; then
	echo "[FAIL] implicit declarations in the build (gcc 2.7 invents int f()):" >&2
	grep 'implicit declaration' "$BUILD/make.log" | sort -u >&2
	exit 1
fi
if grep -E 'pointer from integer|integer from pointer' "$BUILD/make.log" >/dev/null 2>&1; then
	echo "[FAIL] pointer/integer conversion warnings -- a hidden declaration remains:" >&2
	grep -E 'pointer from integer|integer from pointer' "$BUILD/make.log" >&2
	exit 1
fi
echo "  no implicit declarations, no pointer/integer conversions"
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	amix_gate_g14_strict "$BUILD/make.log" || exit 1
	amix_gate_g14_compat "$BUILD/make.log" || exit 1
fi
[ -f "$TREE/gzip" ] || { echo "[FAIL] gzip binary not built" >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 5. Fix the wrapper-script shebangs.
# ---------------------------------------------------------------------------
# configure's AC_PROG_SHELL baked the BUILD host's `#!/bin/bash` into the gunzip
# and zcat wrapper scripts.  Amix has /bin/sh (pre-POSIX) but not necessarily
# /bin/bash, and the scripts are trivial (`PATH=...:$PATH; exec gzip -d "$@"`) --
# pure Bourne, safe under the 1992 sh.  Rewrite the shebang to /bin/sh.  (gzip's
# own argv[0] mode-detection is compiled out under the default GNU_STANDARD=1, so
# gunzip/zcat MUST be these wrappers, not symlinks.)
echo "--- fix wrapper shebangs ---"
for s in gunzip zcat; do
	sed '1s|^#!.*|#!/bin/sh|' "$TREE/$s" > "$TREE/$s.fixed"
	mv "$TREE/$s.fixed" "$TREE/$s"
	chmod 0755 "$TREE/$s"
	echo "  $(head -1 "$TREE/$s")   $s"
done
echo

# ---------------------------------------------------------------------------
# 6. Gates -- read the object code, not the exit status.
# ---------------------------------------------------------------------------
echo "--- gates ---"
amix_gate_elf "$TREE/gzip"
amix_gate_d4 "$TREE/gzip" || {
	echo "[FAIL] D4 gate: this binary SIGKILLs on a 68LC060." >&2
	exit 1
}
amix_gate_undef "$TREE/gzip"
echo

# ---------------------------------------------------------------------------
# 7. Stage.
# ---------------------------------------------------------------------------
echo "--- stage ---"
rm -rf "$DEST"
mkdir -p "$DEST/opt/amix/bin" "$DEST/opt/amix/man/man1" "$DEST/opt/amix/doc/gzip"
cp "$TREE/gzip"   "$DEST/opt/amix/bin/gzip"
$STRIP "$DEST/opt/amix/bin/gzip"
cp "$TREE/gunzip" "$DEST/opt/amix/bin/gunzip"
cp "$TREE/zcat"   "$DEST/opt/amix/bin/zcat"
cp "$TREE/gzip.1"   "$DEST/opt/amix/man/man1/gzip.1"
cp "$TREE/gunzip.1" "$DEST/opt/amix/man/man1/gunzip.1"
cp "$TREE/zcat.1"   "$DEST/opt/amix/man/man1/zcat.1"
cp "$TREE/COPYING"  "$DEST/opt/amix/doc/gzip/COPYING"
cp "$TREE/NEWS"     "$DEST/opt/amix/doc/gzip/NEWS"
cp "$TREE/README"   "$DEST/opt/amix/doc/gzip/README"
chmod 0755 "$DEST/opt/amix/bin/gzip" "$DEST/opt/amix/bin/gunzip" "$DEST/opt/amix/bin/zcat"
chmod 0644 "$DEST/opt/amix/man/man1"/*.1 "$DEST/opt/amix/doc/gzip"/*

echo "--- payload identity (sum -r, the only digest the box can compute) ---"
printf '  %-10s %s  %s bytes\n' gzip \
    "$(sum -r "$DEST/opt/amix/bin/gzip" | awk '{print $1}')" \
    "$(stat -c%s "$DEST/opt/amix/bin/gzip")"
echo

# ---------------------------------------------------------------------------
# 8. Roll the datastream.
# ---------------------------------------------------------------------------
echo "--- package ---"
WORK="$BUILD/pkgwork"
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_pkginfo_retag "$WORK/pkginfo" "$VERSION-2" "$PKGVERSION"
amix_pkgroll "$WORK" "$DEST" "$PKG" "$PKGVERSION" "$PKGOUT/$PKG-$PKGVERSION.pkg"
echo
echo "=== GNU gzip $VERSION built ==="
