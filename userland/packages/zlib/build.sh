#!/bin/sh
#
# build.sh -- fetch, cross-build and package zlib 1.2.13 for Amix.
#
#     sh recipes/zlib/build.sh
#
# Outputs, all under the gitignored build/ tree:
#
#     build/zlib/src/zlib-1.2.13.tar.gz   the pinned tarball (cached)
#     build/zlib/work/zlib-1.2.13/        the extracted, configured tree
#     build/zlib/dest/                    the staged install tree pkgmk reads
#     build/pkg/zlib-1.2.13.pkg           the datastream
#
# zlib is BATCH-1's Wave-0 item and the first LIBRARY this line ships.  It is
# shipped STATIC (registry/zlib.yaml, PORTING.md 2.5): the -G/-h SONAME shared
# path is unproven here and a library is the wrong place to debug it.
#
# ---------------------------------------------------------------------------
# WHY configure IS RUN BUT THE OBJECTS ARE COMPILED BY HAND
#
# zlib ships its own hand-written ./configure (no autotools), and it is
# cross-safe here for the one reason that matters: SVR4.0 HAS size_t, so the
# size_t probe passes and configure never reaches its single run-test
# (`sizet=./$test`, configure:502) -- the one probe that would try to execute
# an m68k binary on the build host.  Every other probe is compile-or-LINK only,
# and a link probe links against the TARGET libc.so.1, so a missing symbol
# fails it correctly (off64_t absent, fseeko absent -> -DNO_FSEEKO, exactly
# right for a 1992 SVR4).
#
# But there is ONE probe whose correct answer configure cannot reach: the
# vs[n]printf test (configure:659) links with `$CC $CFLAGS` only -- it never
# threads LDFLAGS/LIBS -- so it cannot see libacompat, concludes vsnprintf is
# absent, and bakes -DNO_vsnprintf -DNO_snprintf into the Makefile.  Those
# switch gzprintf() to the UNBOUNDED vsprintf()/sprintf() path (gzwrite.c:427,
# gzlib.c:215) -- the "silently degrades" failure registry/zlib.yaml's
# SHIM-SNPRINTF blocker names.
#
# So configure is used for what it does correctly -- generate zconf.h and
# report the platform -- and the library objects are compiled by this recipe
# with a flag set it controls, exactly as recipes/libamixcompat does.  With NO
# NO_* macro defined, gzwrite.c/gzlib.c take their DEFAULT branch, the secure
# `vsnprintf(next, state->size, ...)` with a return value, and the two symbols
# resolve from libacompat (which provides real C99 snprintf/vsnprintf) at the
# consumer's final link.  That is the config the blocker asks for, and the nm
# assertion below proves the built archive actually took it -- not the
# configure log.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

# The /opt/amix prefix (COEXISTENCE.md / ROADMAP D11).  Set BEFORE sourcing
# amix-env.sh, whose AMIX_PREFIX default is still the old /usr/local -- moving
# that default is the separate patch/libacompat re-mint, not batch-1's job.
export AMIX_PREFIX=/opt/amix

. "$REPO/recipes/common/amix-env.sh"
. "$REPO/recipes/common/fetch.sh"
. "$REPO/recipes/common/pkgroll.sh"
. "$REPO/recipes/common/gates.sh"
. "$HERE/pin.sh"

PKG=zlib
VERSION=$ZLIB_VERSION
# The PACKAGE version is the source version plus a package revision.  -2 is
# the 68060 re-mint (2026-10-05; no package may rely on kernel emulation of
# 68060-unimplemented instructions): the same source rebuilt through the
# wrapper's 64-bit multiply expansion (gcc-cross-amix 2ab2b22) -- new
# bytes, so a new catalog version; apkg_vercmp orders 1.2.13-2 above 1.2.13.
PKGVERSION=$VERSION-2

BUILD="$REPO/build/zlib"
SRC="$BUILD/src"
WORKDIR="$BUILD/work"
TREE="$WORKDIR/zlib-$VERSION"
DEST="$BUILD/dest"
PKGOUT="$REPO/build/pkg"

# libacompat, built by recipes/libamixcompat (its .a and headers live in that
# recipe's staged dest under the OLD /usr/local prefix -- that is where the
# build tree put them, independent of where either package INSTALLS on the box).
ACOMPAT_LIB="$REPO/build/libamixcompat/dest/usr/local/lib"
ACOMPAT_INC="$REPO/build/libamixcompat/dest/usr/local/include"

echo "=== zlib $VERSION ==="
amix_env_banner
echo

[ -f "$ACOMPAT_LIB/libacompat.a" ] || {
	echo "[FAIL] libacompat.a not found at $ACOMPAT_LIB" >&2
	echo "       Build recipes/libamixcompat first (ROADMAP D10)." >&2
	exit 1
}

mkdir -p "$SRC" "$WORKDIR" "$PKGOUT"

# ---------------------------------------------------------------------------
# 1. Fetch, verified BEFORE extraction.
# ---------------------------------------------------------------------------
echo "--- source ---"
amix_fetch "$ZLIB_URL" "$ZLIB_SHA256" "$SRC/zlib-$VERSION.tar.gz"
rm -rf "$TREE"
tar xzf "$SRC/zlib-$VERSION.tar.gz" -C "$WORKDIR"
[ -d "$TREE" ] || { echo "[FAIL] $TREE not produced by the tarball" >&2; exit 1; }

# zlib's ONLY assembler is contrib/gcc_gvmat64/gvmat64.S -- x86-64, never named
# by the default Makefile.  Remove contrib/ so the no-imported-assembly gate
# reads a tree with no .S in it at all, rather than having to reason about a
# file that is present but unbuilt (SGS-ASM blocker; the '#'-as-comment trap
# makes a mis-assembled .s a valid instruction with exit 0).
rm -rf "$TREE/contrib"
echo "  removed contrib/ (x86-only asm, never built)"
amix_gate_noasm "$TREE" || {
	echo "[FAIL] unexpected assembly in the zlib tree." >&2
	exit 1
}
echo

# ---------------------------------------------------------------------------
# 2. Configure -- to generate zconf.h and report the platform, nothing more.
# ---------------------------------------------------------------------------
echo "--- configure (zconf.h + platform report) ---"
cd "$TREE"
CC="$CC" CFLAGS="$AMIX_CFLAGS" AR="$AR" ARFLAGS="rc" RANLIB="$RANLIB" \
	./configure --static --prefix="$AMIX_PREFIX" \
	> "$BUILD/configure.log" 2>&1 || {
		echo "[FAIL] configure failed; see $BUILD/configure.log" >&2
		tail -20 "$BUILD/configure.log" >&2
		exit 1
	}

# Assert the platform facts a host fallback would have got wrong.  off64_t and
# fseeko are genuinely ABSENT on SVR4.0; if either flips to "Yes" the link
# probe reached a host libc instead of the target's.
echo "  asserting configure's platform findings:"
for want in 'off64_t:No' 'fseeko:No' 'size_t:Yes'; do
	feat=${want%:*}; exp=${want#*:}
	if grep -q "Checking for $feat\\.\\.\\. $exp\\." "$BUILD/configure.log"; then
		echo "    $feat ... $exp"
	else
		echo "[FAIL] configure did not report '$feat ... $exp' -- a probe reached" >&2
		echo "       the build host's libc, not the target's.  See configure.log." >&2
		exit 1
	fi
done
[ -f "$TREE/zconf.h" ] || { echo "[FAIL] configure produced no zconf.h" >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 3. Compile the library objects, by hand, with the secure printf path.
# ---------------------------------------------------------------------------
# The object list is zlib's own (Makefile.in OBJZ + OBJG).  No NO_vsnprintf /
# NO_snprintf is defined, so gzwrite.c/gzlib.c take their default secure branch.
echo "--- compile libz.a objects ---"
OBJZ="adler32 crc32 deflate infback inffast inflate inftrees trees zutil"
OBJG="compress uncompr gzclose gzlib gzread gzwrite"

rm -f "$BUILD/implicit.log"
for o in $OBJZ $OBJG; do
	echo "  CC   $o.c"
	# Warnings captured, not discarded (recipes/README rule 2).  gcc 2.7 turns
	# an implicit declaration into an invented `int f()` and a truncated return
	# value -- a defect for any function whose real return type is not int.
	$CC $AMIX_CFLAGS -c "$o.c" -o "$o.o" 2>"$o.warn" || {
		echo "[FAIL] compiling $o.c" >&2; cat "$o.warn" >&2; exit 1; }
	if [ -s "$o.warn" ]; then
		cat "$o.warn"
		grep 'implicit declaration' "$o.warn" >> "$BUILD/implicit.log" 2>/dev/null || true
	fi
done

# The ONLY implicit declarations tolerated are snprintf and vsnprintf, and only
# because they are correct here: Amix's <stdio.h> does not DECLARE them (the
# symbols live in libacompat, not libc), but their real return type IS int, so
# gcc 2.7's invented `int f()` prototype loses nothing -- the return-truncation
# trap needs a non-int return type to bite.  libacompat supplies the symbols at
# link.  Any OTHER implicit declaration is a genuine defect and stops the build.
if [ -f "$BUILD/implicit.log" ]; then
	unexpected=$(grep -vE "implicit declaration of function .(v?snprintf|_?snprintf)" "$BUILD/implicit.log" || true)
	if [ -n "$unexpected" ]; then
		echo "[FAIL] unexpected implicit declarations (not snprintf/vsnprintf):" >&2
		echo "$unexpected" >&2
		exit 1
	fi
	echo "  (implicit declarations limited to snprintf/vsnprintf -- acompat-provided, int-returning)"
fi
rm -f "$BUILD/implicit.log"

echo "  AR   libz.a"
rm -f "$TREE/libz.a"
$AR rc "$TREE/libz.a" $(for o in $OBJZ $OBJG; do echo "$o.o"; done)
$RANLIB "$TREE/libz.a"
echo

# ---------------------------------------------------------------------------
# 4. Prove the secure printf path was actually taken -- check the ARCHIVE, not
#    the configure log (registry/zlib.yaml SHIM-SNPRINTF).
# ---------------------------------------------------------------------------
echo "--- config check: the secure vsnprintf/snprintf path is compiled in ---"
undef=$($NM "$TREE/libz.a" 2>/dev/null | awk '$1=="U"{print $2}' | sort -u)
for sym in vsnprintf snprintf; do
	if echo "$undef" | grep -q "^$sym\$"; then
		echo "  libz.a references $sym  (secure path; resolved by -lacompat)"
	else
		echo "[FAIL] libz.a does NOT reference $sym -- gzprintf fell back to the" >&2
		echo "       unbounded vsprintf/sprintf path.  See the header comment." >&2
		exit 1
	fi
done
if echo "$undef" | grep -qE '^(vsprintf|_doprnt)$'; then
	echo "[WARN] libz.a also references vsprintf/_doprnt:" >&2
	echo "$undef" | grep -E '^(vsprintf|_doprnt)$' >&2
fi
echo

# ---------------------------------------------------------------------------
# 5. Link the on-box acceptance test against exactly this libz.a.
# ---------------------------------------------------------------------------
# Wrapper link rules (recipes/README, libacompat build.sh), both silent when
# broken: (1) an ARCHIVE named on the command line lands BEFORE the objects, so
# use -L/-l which land after; (2) any -l suppresses implicit libc, so the list
# MUST end in -lc.  Order: -lz then -lacompat then -lc -- libz references
# snprintf/vsnprintf (satisfied by acompat), acompat references libc.
echo "--- link zlib-test ---"
$CC $AMIX_CFLAGS -I"$TREE" -I"$ACOMPAT_INC" \
	-o "$TREE/zlib-test" "$HERE/tests/zlib-test.c" \
	-L"$TREE" -lz -L"$ACOMPAT_LIB" -lacompat -lc
echo

# ---------------------------------------------------------------------------
# 6. Gates -- read the object code, not the exit status.
# ---------------------------------------------------------------------------
echo "--- gates ---"
amix_gate_elf "$TREE/zlib-test"
# D4 on the ARCHIVE too: libz.a is what rsync/wget will link, so a Dh:Dl
# multiply hidden in it propagates.  CRC/adler/deflate are all 32-bit; expected
# clean, run anyway (D4 is a gate on evidence, not expectation).
amix_gate_d4 "$TREE/libz.a" "$TREE/zlib-test" || {
	echo "[FAIL] D4 gate: a shipped object SIGKILLs on a 68LC060." >&2
	exit 1
}
amix_gate_undef "$TREE/zlib-test"
echo

# ---------------------------------------------------------------------------
# 7. Stage.
# ---------------------------------------------------------------------------
echo "--- stage ---"
rm -rf "$DEST"
mkdir -p "$DEST/opt/amix/lib" "$DEST/opt/amix/include" "$DEST/opt/amix/bin" \
         "$DEST/opt/amix/man/man3" "$DEST/opt/amix/doc/zlib"
cp "$TREE/libz.a"   "$DEST/opt/amix/lib/libz.a"
cp "$TREE/zlib.h"   "$DEST/opt/amix/include/zlib.h"
cp "$TREE/zconf.h"  "$DEST/opt/amix/include/zconf.h"
cp "$TREE/zlib-test" "$DEST/opt/amix/bin/zlib-test"
$STRIP "$DEST/opt/amix/bin/zlib-test" 2>/dev/null || true
cp "$TREE/zlib.3"   "$DEST/opt/amix/man/man3/zlib.3"
cp "$TREE/LICENSE"  "$DEST/opt/amix/doc/zlib/LICENSE"
cp "$TREE/README"   "$DEST/opt/amix/doc/zlib/README"
cp "$TREE/ChangeLog" "$DEST/opt/amix/doc/zlib/ChangeLog"
chmod 0644 "$DEST/opt/amix/lib/libz.a" "$DEST/opt/amix/include"/*.h \
           "$DEST/opt/amix/man/man3/zlib.3" "$DEST/opt/amix/doc/zlib"/*
chmod 0755 "$DEST/opt/amix/bin/zlib-test"

echo "--- payload identity (sum -r, the only digest the box can compute) ---"
for f in "$DEST/opt/amix/lib/libz.a" "$DEST/opt/amix/bin/zlib-test"; do
	printf '  %-14s %s  %s bytes\n' "$(basename "$f")" \
	    "$(sum -r "$f" | awk '{print $1}')" "$(stat -c%s "$f")"
done
echo

# ---------------------------------------------------------------------------
# 8. Roll the datastream.
# ---------------------------------------------------------------------------
echo "--- package ---"
WORK="$BUILD/pkgwork"
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_pkgroll "$WORK" "$DEST" "$PKG" "$PKGVERSION" "$PKGOUT/$PKG-$PKGVERSION.pkg"
echo
echo "=== zlib $VERSION built ==="
