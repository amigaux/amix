#!/bin/sh
#
# build.sh -- fetch, cross-configure, cross-build and package GNU patch 2.5.9.
#
#     sh recipes/patch/build.sh
#
# Outputs, all under the gitignored build/ tree:
#
#     build/patch/src/patch-2.5.9.tar.gz   the pinned tarball (cached)
#     build/patch/work/patch-2.5.9/        the extracted, configured tree
#     build/patch/dest/                    the staged install tree pkgmk reads
#     build/pkg/patch-2.5.9.pkg            the datastream
#
# THIS IS THE FIRST CROSS-`configure` THIS FAMILY HAS COMPLETED.  PORTING.md
# section 4 said the route was derived from constraints and had never been run.
# It has now, and three things bit that no amount of reading would have found.
# Each is handled below with the evidence attached, because a cached configure
# answer with no justification is a silent miscompile waiting for a rebuild.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

AMIX_RECIPE_TOOLCHAINS="period gcc14"

. "$REPO/recipes/common/amix-env.sh"
. "$REPO/recipes/common/fetch.sh"
. "$REPO/recipes/common/pkgroll.sh"
. "$REPO/recipes/common/gates.sh"
. "$HERE/pin.sh"

PKG=patch
VERSION=$PATCH_VERSION
# The PACKAGE version is the source version plus a package revision.  -2 is
# the 68060 re-mint (2026-10-05; no package may rely on kernel emulation of
# 68060-unimplemented instructions): the same source rebuilt through the
# wrapper's 64-bit multiply expansion (gcc-cross-amix 2ab2b22) -- new
# bytes, so a new catalog version; apkg_vercmp orders 2.5.9-2 above 2.5.9.
# Package revision by toolchain: the period build is -2 (the 68060 re-mint); a
# TOOLCHAIN=gcc14 build is new bytes and so a new revision (the userland
# switch, owner decision D-3 sec 9 and 2026-10-27): -3 was gcc14-cross-amix
# e316f1b (never published: pointers came back in %d0 only), -4 is cf461e3
# (pointers in %a0 and %d0, structs via %a0, as AMIX's compilers and libc),
# -5 the same with -mno-strict-align (owner decision 2026-10-27, gcc14-env.sh);
# pkginfo is retagged in the work copy (amix_pkginfo_retag).
case "$AMIX_TOOLCHAIN" in
gcc14) PKGREV=5 ;;
*)     PKGREV=2 ;;
esac
PKGVERSION=$VERSION-$PKGREV

BUILD="$AMIX_BUILD_ROOT/patch"
SRC="$BUILD/src"
WORKDIR="$BUILD/work"
TREE="$WORKDIR/patch-$VERSION"
DEST="$BUILD/dest"
PKGOUT="$AMIX_BUILD_ROOT/pkg"

echo "=== GNU patch $VERSION ==="
amix_env_banner
echo

mkdir -p "$SRC" "$WORKDIR" "$PKGOUT"

# ---------------------------------------------------------------------------
# 1. Fetch, verified BEFORE extraction.
# ---------------------------------------------------------------------------
echo "--- source ---"
amix_fetch "$PATCH_URL" "$PATCH_SHA256" "$SRC/patch-$VERSION.tar.gz"
rm -rf "$TREE"
tar xzf "$SRC/patch-$VERSION.tar.gz" -C "$WORKDIR"
[ -d "$TREE" ] || { echo "[FAIL] $TREE not produced by the tarball" >&2; exit 1; }
echo

# No patches are applied.  patch 2.5.9 needed none -- see README.md; the
# directory that would hold them does not exist rather than existing empty,
# so nobody has to wonder whether a patch went missing.
echo "--- patches: none required ---"
amix_gate_noasm "$TREE" || {
	echo "[FAIL] the upstream tree contains assembly this recipe has not reviewed." >&2
	exit 1
}
echo

# ---------------------------------------------------------------------------
# 2. Cross-configure.
# ---------------------------------------------------------------------------
#
# ★ TRAP 1 -- CPP.  `m68k-cbm-sysv4-gcc -E` does not preprocess: the fix_asm
# wrapper has no -E case, so -E falls through to its "unrecognised dash
# argument is an ld flag" branch and the wrapper LINKS the file instead.
# Autoconf's "checking how to run the C preprocessor" test therefore rejects
# $CC -E and falls back to /lib/cpp -- THE BUILD HOST'S PREPROCESSOR -- after
# which every AC_CHECK_HEADER presence test reads the host's /usr/include.
# Autoconf 2.5x resolves a presence/usability disagreement by trusting the
# preprocessor, so config.h came out with HAVE_WCHAR_H=1 for a header Amix does
# not have, and the build died in quotearg.c with "wchar.h: No such file or
# directory".  recipes/common/amix-cpp is the fix; see its header comment.
#
# ★ TRAP 2 -- the __STDC__ header gate, and it has THREE keys, not one.
# PORTING.md section 2.4 documents -U__STDC__ and warns against
# -D_POSIX_SOURCE.  Measured on this sysroot, the picture is more specific --
# each key opens and closes a DIFFERENT set of doors:
#
#   feature                              default   -U__STDC__   -D_POSIX_SOURCE  -D_XOPEN_SOURCE
#   fdopen/popen/pclose/fileno           implicit  ok           ok               ok
#   struct sigaction + sigset_t + protos PARSE ERR struct only  ok               PARSE ERR
#   SA_SIGINFO                           hidden    ok           hidden           PARSE ERR
#   struct timeval                       ok        ok           hidden           ok
#   ANSI va_start (gcc's OWN stdarg.h)   ok        BROKEN(K&R)  ok               ok
#   <signal.h> compiles at all           ok        ok           ok               PARSE ERR
#
# The two that matter and were not previously written down:
#
#   - -U__STDC__ IS NOT FREE.  It flips gcc 2.7's own <stdarg.h> to the K&R
#     va_start(ap) form, so every ANSI variadic function in the package stops
#     compiling ("macro `va_start' used with too many (2) args").  patch's
#     util.c needs struct sigaction AND five variadic functions in the same
#     translation unit, so per-file flags cannot rescue it.
#   - -D_XOPEN_SOURCE is never the answer: it makes <signal.h> itself fail to
#     parse.
#
# So this package uses -D_POSIX_SOURCE, against PORTING.md's general advice and
# for a measured reason: it is the only key that opens both the stdio and the
# sigaction doors while leaving ANSI varargs intact.  What it closes --
# SA_SIGINFO and struct timeval -- patch does not use (grep: no source file
# includes <sys/time.h> or names struct timeval).  The general advice stands;
# this is a package where the measurement says otherwise.
#
# ★ TRAP 3 -- host-probed program paths.  AC_PATH_PROG runs on the BUILD host,
# so `checking for ed` found the Linux box's /usr/bin/ed and compiled that path
# into the binary.  It happens to be right -- /usr/bin/ed exists on a stock
# Amix root, verified against the extracted 2.1 install tape -- but it was
# right by coincidence, so it is now stated rather than discovered.
#
# ONE SEEDED CACHE VARIABLE, and only one.  patch's configure has seven
# AC_TRY_RUN sites; six already default correctly when cross-compiling.  The
# seventh, AC_FUNC_CLOSEDIR_VOID, defaults to "yes" (closedir returns void) and
# that is FALSE here: $SYSROOT/usr/include/dirent.h:39 declares
# `extern int closedir(DIR *)`.
#
# NOT seeded, deliberately: ac_cv_func_malloc_0_nonnull and its realloc twin
# default to "no", which makes configure install its own rpl_malloc wrapper
# that turns malloc(0) into malloc(1).  That wrapper is correct whichever way
# SVR4.0's malloc(0) behaves, so the conservative default is also the right
# answer and seeding it would only be a claim we cannot check without the box.
#
# NO libacompat.  Measured, not assumed: patch 2.5.9 bundles its own
# strncasecmp.c and uses mktemp(3) -- which Amix HAS -- plus its own O_EXCL
# create, exactly as its source comment describes.  A build with libacompat on
# the include and library path links ZERO symbols out of it.  See README.md.

echo "--- cross-configure ---"
cd "$TREE"
# TOOLCHAIN=gcc14: no answer needs pinning.  config.h diffed against the period
# build, the drifts accepted: HAVE_STRNCASECMP (libamixc99 owns strncasecmp, so
# the bundled strncasecmp.c is not compiled -- one owner per symbol),
# HAVE_VARARGS_H gone (GCC 14 has no varargs.h; patch takes <stdarg.h> either
# way), HAVE_STDBOOL_H/HAVE__BOOL/HAVE_STDINT_H (compiler and sysroot
# headers).  gnulib's malloc.c/realloc.c draw a builtin-mismatch warning from
# their K&R `char *malloc ()' -- the period build compiles the same wrappers.
CC="$CC" \
CPP="$AMIX_CPP" \
CFLAGS="$AMIX_CFLAGS $AMIX_CONFIGURE_LENIENT" \
CPPFLAGS="-D_POSIX_SOURCE" \
LIBS="-lc" \
./configure \
	--host="$AMIX_HOST_TRIPLET" \
	--prefix="$AMIX_PREFIX" \
	--mandir="$AMIX_PREFIX/man" \
	--disable-nls \
	ac_cv_func_closedir_void=no \
	ed_PROGRAM=/usr/bin/ed \
	> "$BUILD/configure.log" 2>&1 || {
		echo "[FAIL] configure failed; see $BUILD/configure.log" >&2
		tail -20 "$BUILD/configure.log" >&2
		exit 1
	}

# Assert the configure answers that a host fallback would have got wrong.  This
# is the mechanical form of trap 1: if amix-cpp ever stops being used, these
# flip and the build stops instead of producing a binary that will not run.
echo "  asserting the cross-configure answers:"
for want in \
	'HAVE_WCHAR_H:absent' \
	'HAVE_WCTYPE_H:absent' \
	'HAVE_MBSTATE_T:absent' \
	'HAVE_SIGACTION:present' \
	'HAVE_DECL_MKTEMP:present'
do
	sym=${want%:*}
	exp=${want#*:}
	if grep -q "^#define $sym 1\$" config.h; then
		got=present
	else
		got=absent
	fi
	if [ "$got" != "$exp" ]; then
		echo "[FAIL] config.h says $sym is $got, expected $exp." >&2
		echo "       An unexpected answer here almost always means CPP fell back" >&2
		echo "       to the BUILD HOST's preprocessor -- see trap 1 above." >&2
		exit 1
	fi
	echo "    $sym $got"
done
echo

# ---------------------------------------------------------------------------
# 3. Build.
# ---------------------------------------------------------------------------
echo "--- make ---"
# gcc14: configure ran lenient; the build gets the strict CFLAGS back.
set --
[ "$AMIX_TOOLCHAIN" = gcc14 ] && set -- CFLAGS="$AMIX_CFLAGS"
make "$@" > "$BUILD/make.log" 2>&1 || {
	echo "[FAIL] make failed; see $BUILD/make.log" >&2
	tail -20 "$BUILD/make.log" >&2
	exit 1
}

# An implicit declaration is a DEFECT on gcc 2.7, not a style note: the compiler
# invents `int f()` and a function that really returns a pointer has its result
# truncated through an int.  That is how the __STDC__ gate announced itself the
# first time (fdopen and popen, three "makes pointer from integer" warnings),
# and the whole point of trap 2's flag is that the count is now zero.
if grep 'implicit declaration' "$BUILD/make.log" > "$BUILD/implicit.log" 2>/dev/null; then
	echo "[FAIL] implicit declarations in the build:" >&2
	sort -u "$BUILD/implicit.log" >&2
	exit 1
fi
rm -f "$BUILD/implicit.log"
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
echo

# ---------------------------------------------------------------------------
# 4. Gates -- read the object code, not the exit status.
# ---------------------------------------------------------------------------
echo "--- gates ---"
amix_gate_elf "$TREE/patch"
amix_gate_d4 "$TREE/patch" || {
	echo "[FAIL] D4 gate: this binary SIGKILLs on a 68LC060." >&2
	exit 1
}
amix_gate_undef "$TREE/patch"
echo

# ---------------------------------------------------------------------------
# 5. Stage.
# ---------------------------------------------------------------------------
echo "--- stage ---"
rm -rf "$DEST"
mkdir -p "$DEST/usr/local/bin" "$DEST/usr/local/man/man1" "$DEST/usr/local/doc/patch"
cp "$TREE/patch" "$DEST/usr/local/bin/patch"
$STRIP "$DEST/usr/local/bin/patch"
cp "$TREE/patch.man" "$DEST/usr/local/man/man1/patch.1"
cp "$TREE/COPYING"   "$DEST/usr/local/doc/patch/COPYING"
cp "$TREE/NEWS"      "$DEST/usr/local/doc/patch/NEWS"
cp "$TREE/README"    "$DEST/usr/local/doc/patch/README"
chmod 0755 "$DEST/usr/local/bin/patch"
chmod 0644 "$DEST/usr/local/man/man1/patch.1" "$DEST/usr/local/doc/patch"/*

echo "--- payload identity (sum -r, the only digest the box can compute) ---"
printf '  %-12s %s  %s bytes\n' patch \
    "$(sum -r "$DEST/usr/local/bin/patch" | awk '{print $1}')" \
    "$(stat -c%s "$DEST/usr/local/bin/patch")"
echo

# ---------------------------------------------------------------------------
# 6. Roll the datastream.
# ---------------------------------------------------------------------------
echo "--- package ---"
WORK="$BUILD/pkgwork"
rm -rf "$WORK"; mkdir -p "$WORK"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_pkginfo_retag "$WORK/pkginfo" "$VERSION-2" "$PKGVERSION"
amix_pkgroll "$WORK" "$DEST" "$PKG" "$PKGVERSION" "$PKGOUT/$PKG-$PKGVERSION.pkg"
echo
echo "=== GNU patch $VERSION built ==="
