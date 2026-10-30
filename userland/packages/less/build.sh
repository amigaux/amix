#!/bin/sh
#
# build.sh -- fetch, cross-configure, cross-build and package less 704.
#
#     sh recipes/less/build.sh
#
# Outputs under the gitignored build/ tree:
#
#     build/less/src/less-704.tar.gz   the pinned tarball (cached)
#     build/less/work/less-704/        the extracted, patched, built tree
#     build/less/dest/                 the staged install tree
#     build/pkg/less-704.pkg           the datastream
#
# less fills a genuine gap: stock Amix has only more/pg/page.  It is integer-only
# and, measured, links NOTHING from libacompat -- everything resolves from the
# stock libc.so.1, libgen.a (regcmp) and libcurses.a (termcap).
#
# ---------------------------------------------------------------------------
# THE FOUR THINGS THAT MADE IT BUILD (all measured; details in patches/)
#
# 1. THE ccs/lib LINK PATH.  regcmp is in libgen.a and the termcap API in
#    libcurses.a, both under /usr/ccs/lib -- not the wrapper's default
#    /usr/lib -- so -L<sysroot>/usr/ccs/lib goes on LDFLAGS (configure) and the
#    same libs go in LIBS (link).  And LIBS ends in -lc: the wrapper drops the
#    implicit libc the moment any explicit -l appears (recipes/README), which is
#    exactly why the stock configure's curses/regcmp probes first failed here.
#
# 2. -DUSE_TERMCAP.  less would otherwise pull the SVR4 <term.h>, whose TERMINAL
#    struct has a `struct termio' field that stays INCOMPLETE because <termios.h>
#    (which less includes for tcgetattr) defines VINTR, which makes <curses.h>
#    skip its own <termio.h> include.  The termcap path avoids <term.h> entirely;
#    on SVR4 the termcap tgetent reads the terminfo database, so it works (D2).
#
# 3. ac_cv_func_stat=yes.  SVR4 `stat' is a static-inline wrapper over _xstat, so
#    autoconf's link-test for a bare `stat' symbol FAILS and HAVE_STAT comes out
#    unset -- after which edit.c/cmdbuf.c/filename.c skip <sys/stat.h> and every
#    `struct stat' is incomplete.  stat works; the probe just cannot see it.
#
# 4. THREE SOURCE PATCHES for the strict-ANSI SVR4 header gaps: ssize_t and the
#    __STDC__-gated / header-less function decls (patches/01 less.h), less's own
#    stale variadic-wrong regcmp/regex prototypes (patches/02 pattern.h), and one
#    strdup decl for the one TU that does not include less.h (patches/03).

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

PKG=less
VERSION=$LESS_VERSION
# The PACKAGE version is the source version plus a package revision.  -2 is
# the 68060 re-mint (2026-10-05; no package may rely on kernel emulation of
# 68060-unimplemented instructions): the same source rebuilt through the
# wrapper's 64-bit multiply expansion (gcc-cross-amix 2ab2b22) -- new
# bytes, so a new catalog version; apkg_vercmp orders 704-2 above 704.
# Package revision by toolchain: the period build is -2 (the 68060 re-mint);
# a TOOLCHAIN=gcc14 build is new bytes and so a new revision (phase 2 of the
# userland switch, owner decision D-3 sec 9): -3 was -mcpu=68060 (never
# published; its FPU forms kill make on a 68882), -4 is -m68020-60, -5 the
# same on gcc14-cross-amix cf461e3 (pointers returned in %a0 and %d0, structs
# via %a0, as AMIX's compilers and libc do), -6 the same with -mno-strict-align
# (owner decision 2026-10-27, gcc14-env.sh).  pkginfo is retagged in the work
# copy (amix_pkginfo_retag).
# -7: the same objects relinked on gcc14-cross-amix b51ff39 (the public pin,
# owner Y3, 2026-10-29): only the runtime it links (libgcc, libamixc99) differs.
case "$AMIX_TOOLCHAIN" in
gcc14) PKGREV=7 ;;
*)     PKGREV=2 ;;
esac
PKGVERSION=$VERSION-$PKGREV

BUILD="$AMIX_BUILD_ROOT/less"
SRC="$BUILD/src"
WORKDIR="$BUILD/work"
TREE="$WORKDIR/less-$VERSION"
DEST="$BUILD/dest"
PKGOUT="$AMIX_BUILD_ROOT/pkg"

CCSLIB="$AMIX_SYSROOT/usr/ccs/lib"

echo "=== less $VERSION ==="
amix_env_banner
echo

mkdir -p "$SRC" "$WORKDIR" "$PKGOUT"

# ---------------------------------------------------------------------------
# 1. Fetch, verified BEFORE extraction.
# ---------------------------------------------------------------------------
echo "--- source ---"
amix_fetch "$LESS_URL" "$LESS_SHA256" "$SRC/less-$VERSION.tar.gz"
rm -rf "$TREE"
tar xzf "$SRC/less-$VERSION.tar.gz" -C "$WORKDIR"
[ -d "$TREE" ] || { echo "[FAIL] $TREE not produced by the tarball" >&2; exit 1; }
# less ships its source files read-only (mode 444); make them writable so the
# patches and the build can touch them.
chmod -R u+w "$TREE"
echo

# ---------------------------------------------------------------------------
# 2. Patches.
# ---------------------------------------------------------------------------
echo "--- patches ---"
for p in "$HERE"/patches/*.patch; do
	echo "  applying $(basename "$p")"
	( cd "$TREE" && patch -p0 --batch --fuzz=0 < "$p" ) || {
		echo "[FAIL] patch $(basename "$p") did not apply cleanly" >&2; exit 1; }
done
# TOOLCHAIN=gcc14 only: type fixes gcc 2.7 merely warned about and GCC 14
# rejects.  Applied after the shared patches; the period build never sees them.
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	for p in "$HERE"/patches-gcc14/*.patch; do
		echo "  applying gcc14 $(basename "$p")"
		( cd "$TREE" && patch -p0 --batch --fuzz=0 < "$p" ) || {
			echo "[FAIL] patch $(basename "$p") did not apply cleanly" >&2; exit 1; }
	done
fi
amix_gate_noasm "$TREE" || {
	echo "[FAIL] unexpected .s/.S assembly in the less tree." >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 3. Cross-configure.
# ---------------------------------------------------------------------------
echo "--- cross-configure ---"
cd "$TREE"
CC="$CC" \
CPP="$AMIX_CPP" \
CFLAGS="$AMIX_CFLAGS -DUSE_TERMCAP $AMIX_CONFIGURE_LENIENT" \
LDFLAGS="-L$CCSLIB" \
LIBS="-lc" \
./configure \
	--host="$AMIX_HOST_TRIPLET" \
	--prefix="$AMIX_PREFIX" \
	ac_cv_func_stat=yes \
	> "$BUILD/configure.log" 2>&1 || {
		echo "[FAIL] configure failed; see $BUILD/configure.log" >&2
		tail -20 "$BUILD/configure.log" >&2
		exit 1
	}

echo "  asserting the cross-configure answers:"
# The SVR4 regcmp backend, via libgen, is the one the box can actually provide.
if grep -qE 'regular expression library:[[:space:]]*regcmp' "$BUILD/configure.log"; then
	echo "    regex backend = regcmp (SVR4 libgen; D8/REGEX-NONE)"
else
	echo "[FAIL] configure did not choose the regcmp regex backend." >&2
	grep -iE 'regular expression|regcmp' "$BUILD/configure.log" >&2
	exit 1
fi
if grep -qE 'terminal libraries\.\.\. using -lcurses' "$BUILD/configure.log"; then
	echo "    terminal library = -lcurses (termcap API, D2)"
else
	echo "[FAIL] configure did not settle on -lcurses for the terminal library." >&2
	exit 1
fi
# HAVE_STAT must be on, or every struct stat is incomplete (see header comment).
grep -q '^#define HAVE_STAT 1' defines.h || {
	echo "[FAIL] HAVE_STAT is not defined -- struct stat will be incomplete." >&2; exit 1; }
echo "    HAVE_STAT defined"
echo

# ---------------------------------------------------------------------------
# 4. Build.
# ---------------------------------------------------------------------------
# LIBSAN is cleared (the Makefile defaults it to the -lasan/-lubsan sanitizer
# libs, which do not exist for this target); LIBS carries the real link set,
# ending in -lc.
echo "--- make ---"
# gcc14: configure ran lenient; the build gets the strict CFLAGS back.
set --
[ "$AMIX_TOOLCHAIN" = gcc14 ] && set -- CFLAGS="$AMIX_CFLAGS -DUSE_TERMCAP"
make LIBSAN= LIBS="-lgen -lcurses -lc" "$@" > "$BUILD/make.log" 2>&1 || {
	echo "[FAIL] make failed; see $BUILD/make.log" >&2
	tail -25 "$BUILD/make.log" >&2
	exit 1
}
if grep 'implicit declaration' "$BUILD/make.log" >/dev/null 2>&1; then
	echo "[FAIL] implicit declarations in the build:" >&2
	grep 'implicit declaration' "$BUILD/make.log" | sort -u >&2
	exit 1
fi
if grep -E 'pointer from integer|integer from pointer|makes pointer' "$BUILD/make.log" >/dev/null 2>&1; then
	echo "[FAIL] pointer/integer conversion -- a hidden pointer-returning decl remains:" >&2
	grep -E 'pointer from integer|integer from pointer|makes pointer' "$BUILD/make.log" | sort -u >&2
	exit 1
fi
echo "  no implicit declarations, no pointer/integer conversions"
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	amix_gate_g14_strict "$BUILD/make.log" || exit 1
	amix_gate_g14_compat "$BUILD/make.log" || exit 1
fi
for b in less lesskey lessecho; do
	[ -f "$TREE/$b" ] || { echo "[FAIL] $b not built" >&2; exit 1; }
done
echo

# ---------------------------------------------------------------------------
# 5. Gates.
# ---------------------------------------------------------------------------
echo "--- gates ---"
amix_gate_elf "$TREE/less" "$TREE/lesskey" "$TREE/lessecho"
amix_gate_d4 "$TREE/less" "$TREE/lesskey" "$TREE/lessecho" || {
	echo "[FAIL] D4 gate: a shipped binary SIGKILLs on a 68LC060." >&2
	exit 1
}
amix_gate_undef "$TREE/less"
echo

# ---------------------------------------------------------------------------
# 6. Stage.
# ---------------------------------------------------------------------------
echo "--- stage ---"
rm -rf "$DEST"
mkdir -p "$DEST/opt/amix/bin" "$DEST/opt/amix/man/man1" "$DEST/opt/amix/doc/less"
for b in less lesskey lessecho; do
	cp "$TREE/$b" "$DEST/opt/amix/bin/$b"
	$STRIP "$DEST/opt/amix/bin/$b"
	chmod 0755 "$DEST/opt/amix/bin/$b"
done
cp "$TREE/less.man"     "$DEST/opt/amix/man/man1/less.1"
cp "$TREE/lesskey.man"  "$DEST/opt/amix/man/man1/lesskey.1"
cp "$TREE/lessecho.man" "$DEST/opt/amix/man/man1/lessecho.1"
cp "$TREE/LICENSE" "$DEST/opt/amix/doc/less/LICENSE"
cp "$TREE/COPYING" "$DEST/opt/amix/doc/less/COPYING"
cp "$TREE/NEWS"    "$DEST/opt/amix/doc/less/NEWS"
chmod 0644 "$DEST/opt/amix/man/man1"/*.1 "$DEST/opt/amix/doc/less"/*

echo "--- payload identity (sum -r, the only digest the box can compute) ---"
printf '  %-10s %s  %s bytes\n' less \
    "$(sum -r "$DEST/opt/amix/bin/less" | awk '{print $1}')" \
    "$(stat -c%s "$DEST/opt/amix/bin/less")"
echo

# ---------------------------------------------------------------------------
# 7. Roll the datastream.
# ---------------------------------------------------------------------------
echo "--- package ---"
WORK="$BUILD/pkgwork"
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_pkginfo_retag "$WORK/pkginfo" "$VERSION-2" "$PKGVERSION"
amix_pkgroll "$WORK" "$DEST" "$PKG" "$PKGVERSION" "$PKGOUT/$PKG-$PKGVERSION.pkg"
echo
echo "=== less $VERSION built ==="
