#!/bin/sh
#
# build.sh -- fetch, cross-configure, cross-build and package GNU grep 2.5.1a.
#
#     sh recipes/grep/build.sh
#
# Outputs under the gitignored build/ tree:
#
#     build/grep/src/grep-2.5.1a.tar.gz   the pinned tarball (cached)
#     build/grep/work/grep-2.5.1a/        the extracted, patched, built tree
#     build/grep/dest/                    the staged install tree
#     build/pkg/grep-2.5.1a-2.pkg         the datastream (package revision 2)
#
# grep coexists with stock: stock SVR4 grep lives at /usr/bin/grep (->/sbin/grep)
# and this package does NOT touch it (COEXISTENCE.md 2).  Ours installs to
# /opt/amix/bin/grep and wins for interactive users by PATH, adding -r, -o,
# --color and a reliable -E over the feature-poor stock tool.
#
# ---------------------------------------------------------------------------
# FOUR THINGS THAT MADE IT BUILD (all measured, all in patches/ or flags)
#
# 1. THE BUNDLED REGEX, FORCED.  --with-included-regex puts src/regex.c into
#    LIBOBJS.  The box has no POSIX regcomp at all (D8), and a compile-test for
#    one succeeds anyway under gcc 2.7's implicit declarations (PORTING.md 4), so
#    the default "detect the system regex" path is a trap.  Step 3 ASSERTS
#    regex.o is in the link rather than trusting the flag.
#
# 2. strcasecmp FROM libacompat.  grep's --color option parser calls strcasecmp,
#    which is absent from the stock libc.so.1 and declared by no SVR4 header.
#    -lacompat supplies the symbol; patches/01 supplies the declaration (and an
#    S_ISSOCK macro SVR4 omits though S_IFSOCK exists).
#
# 3. ONE MISSING DECL in gnulib's savedir.c (patches/02): it calls isdir()
#    without a prototype, which gcc 2.7 would compile as int-returning implicitly
#    -- harmless here but a defect this line does not wave through.
#
# 4. D4, found 2026-09-26 -- AFTER this package was published (patches/03-04).
#    gnulib's strtoull (strtol.c, QUAD instance) and xstrtoumax's bkm_scale
#    open-code uintmax_t products as MULU.L <reg|mem>,Dh:Dl -- the multiply form
#    the 68060 lacks and the kernel's vector-61 handler does not emulate, so a
#    SIGKILL.  They sit on the -A/-B/-C/-m argument path (xstrtoumax).  The
#    published grep-2.5.1a.pkg (md5 037c3f73...) carries both; it was reported
#    "D4 ok" only because the gate then could not fire (recipes/common/gates.sh).
#    Both products now go through libgcc's __muldi3 (32-bit multiplies only).

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

export AMIX_PREFIX=/opt/amix

. "$REPO/recipes/common/amix-env.sh"
. "$REPO/recipes/common/fetch.sh"
. "$REPO/recipes/common/pkgroll.sh"
. "$REPO/recipes/common/gates.sh"
. "$HERE/pin.sh"

PKG=grep
VERSION=$GREP_VERSION
# The PACKAGE version is the source version plus a package revision.  -2 is the
# D4 re-mint (patches/03-04): same upstream 2.5.1a, different bytes, so it must
# be a different catalog version -- apkg_vercmp orders 2.5.1a-2 above the
# published 2.5.1a (segments split on '.' and '-', a missing one counts as 0),
# which is what makes `apkg upgrade grep` engage on a box holding the old one.
PKGVERSION=$GREP_VERSION-2

BUILD="$REPO/build/grep"
SRC="$BUILD/src"
WORKDIR="$BUILD/work"
TREE="$WORKDIR/grep-$VERSION"
DEST="$BUILD/dest"
PKGOUT="$REPO/build/pkg"

ACOMPAT_LIB="$REPO/build/libamixcompat/dest/usr/local/lib"

echo "=== GNU grep $VERSION ==="
amix_env_banner
echo

[ -f "$ACOMPAT_LIB/libacompat.a" ] || {
	echo "[FAIL] libacompat.a not found at $ACOMPAT_LIB (build libamixcompat first)" >&2
	exit 1
}

mkdir -p "$SRC" "$WORKDIR" "$PKGOUT"

# ---------------------------------------------------------------------------
# 1. Fetch, verified BEFORE extraction.
# ---------------------------------------------------------------------------
echo "--- source ---"
amix_fetch "$GREP_URL" "$GREP_SHA256" "$SRC/grep-$VERSION.tar.gz"
rm -rf "$TREE"
tar xzf "$SRC/grep-$VERSION.tar.gz" -C "$WORKDIR"
[ -d "$TREE" ] || { echo "[FAIL] $TREE not produced by the tarball" >&2; exit 1; }
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
amix_gate_noasm "$TREE" || {
	echo "[FAIL] unexpected .s/.S assembly in the grep tree." >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 3. Cross-configure.
# ---------------------------------------------------------------------------
echo "--- cross-configure ---"
cd "$TREE"
CC="$CC" \
CPP="$REPO/recipes/common/amix-cpp" \
CFLAGS="$AMIX_CFLAGS" \
./configure \
	--host="$AMIX_TARGET" \
	--prefix="$AMIX_PREFIX" \
	--disable-nls \
	--disable-perl-regexp \
	--with-included-regex \
	--disable-largefile \
	> "$BUILD/configure.log" 2>&1 || {
		echo "[FAIL] configure failed; see $BUILD/configure.log" >&2
		tail -20 "$BUILD/configure.log" >&2
		exit 1
	}

echo "  asserting the cross-configure answers:"
# The bundled regex MUST be in the link (REGEX-NONE).  config.status is the
# generated record of what @LIBOBJS@ expands to.
if grep -q 'regex\.o' config.status; then
	echo "    regex.o is in LIBOBJS (bundled GNU regex compiled in)"
else
	echo "[FAIL] regex.o is NOT in LIBOBJS -- configure chose a system regex that" >&2
	echo "       the box does not have (D8/REGEX-NONE).  --with-included-regex slipped." >&2
	exit 1
fi
# Amix has no <strings.h> at all; a HAVE_STRINGS_H here would mean the host CPP
# fallback read the build host's headers (PORTING.md 4.1).
if grep -q '^#define HAVE_STRINGS_H 1' config.h; then
	echo "[FAIL] config.h defines HAVE_STRINGS_H -- Amix has no strings.h; a probe" >&2
	echo "       reached the BUILD host's headers (CPP fallback)." >&2
	exit 1
fi
echo "    HAVE_STRINGS_H absent (target headers were read, not the host's)"
echo

# ---------------------------------------------------------------------------
# 4. Build -- strcasecmp comes from libacompat, threaded through LIBS.
# ---------------------------------------------------------------------------
# LIBS is set at make time, not configure time: grep's configure tests none of
# acompat's symbols, so a clean configure needs only the stock libc, while the
# final link needs -lacompat for strcasecmp.  Wrapper rule (recipes/README): any
# -l suppresses the implicit libc, so the list ENDS in -lc.
echo "--- make ---"
make LIBS="-L$ACOMPAT_LIB -lacompat -lc" > "$BUILD/make.log" 2>&1 || {
	echo "[FAIL] make failed; see $BUILD/make.log" >&2
	tail -25 "$BUILD/make.log" >&2
	exit 1
}
if grep 'implicit declaration' "$BUILD/make.log" >/dev/null 2>&1; then
	echo "[FAIL] implicit declarations in the build:" >&2
	grep 'implicit declaration' "$BUILD/make.log" | sort -u >&2
	exit 1
fi
if grep -E 'pointer from integer|integer from pointer' "$BUILD/make.log" >/dev/null 2>&1; then
	echo "[FAIL] pointer/integer conversion warnings -- a hidden declaration remains:" >&2
	grep -E 'pointer from integer|integer from pointer' "$BUILD/make.log" >&2
	exit 1
fi
echo "  no implicit declarations, no pointer/integer conversions"
[ -f "$TREE/src/grep" ] || { echo "[FAIL] grep binary not built" >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 5. Make egrep/fgrep find OUR grep by absolute path.
# ---------------------------------------------------------------------------
# grep ships egrep/fgrep as `#!/bin/sh; exec grep -E ...` -- a bare `grep` that
# depends on PATH.  /opt/amix/bin is not on the stock PATH out of the box
# (COEXISTENCE.md 3), and this batch is tested by absolute path, so rewrite the
# exec to the absolute /opt/amix/bin/grep.  The scripts stay pure Bourne.
echo "--- fix egrep/fgrep to absolute grep ---"
for s in egrep fgrep; do
	sed 's|exec grep |exec /opt/amix/bin/grep |' "$TREE/src/$s" > "$TREE/src/$s.fixed"
	mv "$TREE/src/$s.fixed" "$TREE/src/$s"
	chmod 0755 "$TREE/src/$s"
	echo "  $(tail -1 "$TREE/src/$s")"
done
echo

# ---------------------------------------------------------------------------
# 6. Gates.
# ---------------------------------------------------------------------------
echo "--- gates ---"
amix_gate_elf "$TREE/src/grep"
amix_gate_d4 "$TREE/src/grep" || {
	echo "[FAIL] D4 gate: this binary SIGKILLs on a 68LC060." >&2
	exit 1
}
amix_gate_undef "$TREE/src/grep"
echo

# ---------------------------------------------------------------------------
# 7. Stage.
# ---------------------------------------------------------------------------
echo "--- stage ---"
rm -rf "$DEST"
mkdir -p "$DEST/opt/amix/bin" "$DEST/opt/amix/man/man1" "$DEST/opt/amix/doc/grep"
cp "$TREE/src/grep"  "$DEST/opt/amix/bin/grep"
$STRIP "$DEST/opt/amix/bin/grep"
cp "$TREE/src/egrep" "$DEST/opt/amix/bin/egrep"
cp "$TREE/src/fgrep" "$DEST/opt/amix/bin/fgrep"
cp "$TREE/doc/grep.1"  "$DEST/opt/amix/man/man1/grep.1"
cp "$TREE/doc/egrep.1" "$DEST/opt/amix/man/man1/egrep.1"
cp "$TREE/doc/fgrep.1" "$DEST/opt/amix/man/man1/fgrep.1"
cp "$TREE/COPYING" "$DEST/opt/amix/doc/grep/COPYING"
cp "$TREE/NEWS"    "$DEST/opt/amix/doc/grep/NEWS"
cp "$TREE/README"  "$DEST/opt/amix/doc/grep/README"
chmod 0755 "$DEST/opt/amix/bin/grep" "$DEST/opt/amix/bin/egrep" "$DEST/opt/amix/bin/fgrep"
chmod 0644 "$DEST/opt/amix/man/man1"/*.1 "$DEST/opt/amix/doc/grep"/*

echo "--- payload identity (sum -r, the only digest the box can compute) ---"
printf '  %-10s %s  %s bytes\n' grep \
    "$(sum -r "$DEST/opt/amix/bin/grep" | awk '{print $1}')" \
    "$(stat -c%s "$DEST/opt/amix/bin/grep")"
echo

# ---------------------------------------------------------------------------
# 8. Roll the datastream.
# ---------------------------------------------------------------------------
echo "--- package ---"
WORK="$BUILD/pkgwork"
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
grep "^VERSION=$PKGVERSION\$" "$WORK/pkginfo" >/dev/null || {
	echo "[FAIL] pkginfo VERSION is not $PKGVERSION -- bump pkginfo with the revision" >&2
	exit 1
}
amix_pkgroll "$WORK" "$DEST" "$PKG" "$PKGVERSION" "$PKGOUT/$PKG-$PKGVERSION.pkg"
echo
echo "=== GNU grep $VERSION (package $PKGVERSION) built ==="
