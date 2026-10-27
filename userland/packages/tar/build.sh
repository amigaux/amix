#!/bin/sh
#
# build.sh -- fetch, cross-configure, cross-build and package GNU tar 1.14.
#
#     sh recipes/tar/build.sh
#
# Outputs under the gitignored build/ tree:
#
#     build/tar/src/tar-1.14.tar.gz   the pinned tarball (cached)
#     build/tar/work/tar-1.14/        the extracted, patched, built tree
#     build/tar/dest/                 the staged install tree
#     build/pkg/gtar-1.14.pkg         the datastream (PKG gtar)
#
# tar coexists with stock: stock SVR4 tar lives at /usr/sbin/tar (+ /etc/tar),
# owned by `core`, and this package does NOT touch it (COEXISTENCE.md 2).  Ours
# installs to /opt/amix/bin/tar and wins for interactive users by PATH, adding
# base-256 header reads (archives made this decade), -z, and long names.  The
# PKG name is gtar so the catalog never shows two packages called tar.
#
# ---------------------------------------------------------------------------
# WHAT MADE IT BUILD -- AND BUILD RIGHT (all measured 2026-09-26)
#
# 1. D3, THE FIRST PACKAGE TO NEED IT.  tar -c maps uid->name (getpwuid) and
#    tar -x as root maps name->uid (getpwnam) -- and the FIRST getpwnam() of a
#    process crashes in the stock shared libc (PORTING.md 3.1).  The executable
#    therefore DEFINES all four lookups itself: recipes/common/amix-pwgr.c,
#    linked as a plain object.  Step 5 asserts nm shows them T, never U.
#
# 2. THREE CONFIGURE ANSWERS THAT WERE WRONG, all seeded with the reason:
#      ac_cv_func_lstat=yes      lstat is a STATIC FUNCTION in sys/stat.h:223
#                                (a wrapper around _lxstat), so a link-only
#                                probe cannot see it.  Unseeded, tar does
#                                `#define lstat stat` and archives what every
#                                symlink POINTS AT -- silently.
#      ac_cv_have_decl_valloc=no stdlib.h declares valloc; libc.so.1 does not
#                                export it (nm).  "no" makes tar use malloc.
#      jm_cv_func_gettimeofday_clobber=no
#                                the cross default "yes" wraps gettimeofday to
#                                protect localtime's static buffer.  Ours comes
#                                from libacompat, built on _abi_gettimeofday ->
#                                _abi_hrtcntl, which never touches it.
#    Deliberately NOT seeded (the cross default is correct either way):
#    chown/mktime/utime-null "no" -> gnulib's portable replacements, which are
#    right whatever SVR4.0 does.  ftruncate really is absent from libc.so.1;
#    gnulib's replacement uses F_FREESP, which SVR4 has.
#
# 3. SEVEN SOURCE PATCHES (patches/):
#      01  declare fdopen/fileno/strdup/kill/tzset -- in libc.so.1, hidden
#          behind the __STDC__ gate; -U__STDC__ breaks gcc's stdarg.h and
#          -D_POSIX_SOURCE hides lstat/mknod, which tar needs (PORTING 2.4.1).
#      02  human.c: long double -> double.  This libgcc has no __fixunsxfdi
#          (XFmode -> unsigned long long), so the link fails.
#      03  exclude.c: include gnulib's strcase.h (no SVR4 header declares
#          strcasecmp).
#      04  gettime.c: declare gettimeofday (absent from libc.so.1 AND from
#          every header; the symbol comes from libacompat).
#      05-07  D4, the 68LC060 lane.  gcc 2.7.2.3 at -m68020 open-codes every
#          variable uintmax_t product as MULU.L <reg|mem>,Dh:Dl -- the one
#          multiply form the 060 does not implement and the kernel's vector-61
#          handler does not emulate, so it is a SIGKILL.  Four such sites:
#          human.c (x2, --totals), xstrtol.c's bkm_scale in the uintmax
#          instance (size suffixes), strtol.c's QUAD instance (strtoull: every
#          numeric option).  Each is routed through libgcc's __muldi3, which is
#          built from 32-bit multiplies only.  D4's documented escape hatch --
#          build the TU -m68000 -- does NOT work on this toolchain: libgcc.a
#          carries no __mulsi3/__divsi3/__udivsi3/__umodsi3, so a -m68000
#          human.o fails to link (a gcc-cross-amix item).
#
# The program stays DYNAMIC against libc.so.1: a static link would embed stock
# SVR4 libc.a objects in a binary this repo publishes (see amix-pwgr.c).

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

PKG=gtar
VERSION=$TAR_VERSION
# The PACKAGE version is the source version plus a package revision.  -2 is
# the 68060 re-mint (2026-10-05; no package may rely on kernel emulation of
# 68060-unimplemented instructions): the same source rebuilt through the
# wrapper's 64-bit multiply expansion (gcc-cross-amix 2ab2b22) -- new
# bytes, so a new catalog version; apkg_vercmp orders 1.14-2 above 1.14.
# Package revision by toolchain: the period build is -2 (the 68060 re-mint);
# a TOOLCHAIN=gcc14 build is new bytes and so a new revision, -3 (the userland
# switch, owner decision D-3 sec 9 and 2026-10-27); pkginfo is retagged in the
# work copy (amix_pkginfo_retag).
#
# TOOLCHAIN=gcc14 needs no libacompat.  Its one symbol here, gettimeofday,
# has an owner on that toolchain: GCC 14 links -lc the SVR4 way, through
# usr/ccs/lib/libc.so (libc.so.1 plus static members), and its static
# gettimeofday.o (weak; the stock one-argument _hrtcntl(1, 1, 0, &buf) read,
# the same contract as libacompat's _abi_gettimeofday wrapper, and it never
# touches localtime's buffer, so the clobber seed below still holds).
# Step 5 asserts which archive defined it.  Everything else is the same
# recipe: the D3 object, the seeds, the seven patches (05-07 route products
# through __muldi3, which GCC 14's libgcc has; -m68020-60 would not emit the
# 64-bit form anyway).
case "$AMIX_TOOLCHAIN" in
gcc14) PKGREV=3 ;;
*)     PKGREV=2 ;;
esac
PKGVERSION=$VERSION-$PKGREV

BUILD="$AMIX_BUILD_ROOT/tar"
SRC="$BUILD/src"
WORKDIR="$BUILD/work"
TREE="$WORKDIR/tar-$VERSION"
DEST="$BUILD/dest"
PKGOUT="$AMIX_BUILD_ROOT/pkg"

ACOMPAT_LIB="$REPO/build/libamixcompat/dest/usr/local/lib"

echo "=== GNU tar $VERSION ==="
amix_env_banner
echo

if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	TAR_LIBS="$BUILD/amix-pwgr.o -Wl,-y,gettimeofday"
else
	[ -f "$ACOMPAT_LIB/libacompat.a" ] || {
		echo "[FAIL] libacompat.a not found at $ACOMPAT_LIB (build libamixcompat first)" >&2
		exit 1
	}
	TAR_LIBS="$BUILD/amix-pwgr.o -L$ACOMPAT_LIB -lacompat -lc"
fi

mkdir -p "$SRC" "$WORKDIR" "$PKGOUT"

# ---------------------------------------------------------------------------
# 1. Fetch, verified BEFORE extraction.
# ---------------------------------------------------------------------------
echo "--- source ---"
amix_fetch "$TAR_URL" "$TAR_SHA256" "$SRC/tar-$VERSION.tar.gz"
rm -rf "$TREE"
tar xzf "$SRC/tar-$VERSION.tar.gz" -C "$WORKDIR"
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
# TOOLCHAIN=gcc14 only: what GCC 14 rejects in AMIX's own headers (sys/mkdev.h).
# Applied after the shared patches; the period build never sees them.
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	for p in "$HERE"/patches-gcc14/*.patch; do
		echo "  applying gcc14 $(basename "$p")"
		( cd "$TREE" && patch -p0 --batch --fuzz=0 < "$p" ) || {
			echo "[FAIL] patch $(basename "$p") did not apply cleanly" >&2; exit 1; }
	done
fi
amix_gate_noasm "$TREE" || {
	echo "[FAIL] unexpected .s/.S assembly in the tar tree." >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 3. Cross-configure, with the three seeds justified in the header above.
# ---------------------------------------------------------------------------
echo "--- cross-configure ---"
cd "$TREE"
# TOOLCHAIN=gcc14 pins two more answers to the period build's, config.h diffed:
#   ftruncate -> GCC 14's SVR4-style -lc finds the static truncate.o the period
#     link never saw; pinned no, so tar keeps gnulib's F_FREESP replacement,
#     as bench-proven;
#   stdint.h (the sysroot's compat one) -> pinned no, as grep and make do:
#     intmax_t/uintmax_t stay configure's `long long' macros (gnulib asks
#     under three cache names; all three pinned).
# Accepted as GCC 14 finds them: HAVE_STRCASECMP/HAVE_STRNCASECMP (libamixc99
# owns both, so gnulib's strcasecmp.c is not compiled), ssize_t (GCC 14's fixed
# sys/types.h has `typedef int ssize_t', the period's `#define ssize_t int'),
# HAVE_STDBOOL_H/HAVE__BOOL and `restrict' (compiler features).
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	export ac_cv_func_ftruncate=no ac_cv_header_stdint_h=no gl_cv_header_stdint_h=no \
		jm_ac_cv_header_stdint_h=no
fi
ac_cv_func_lstat=yes \
ac_cv_have_decl_valloc=no \
jm_cv_func_gettimeofday_clobber=no \
CC="$CC" \
CPP="$AMIX_CPP" \
CFLAGS="$AMIX_CFLAGS $AMIX_CONFIGURE_LENIENT" \
./configure \
	--host="$AMIX_HOST_TRIPLET" \
	--prefix="$AMIX_PREFIX" \
	--disable-nls \
	--disable-largefile \
	> "$BUILD/configure.log" 2>&1 || {
		echo "[FAIL] configure failed; see $BUILD/configure.log" >&2
		tail -20 "$BUILD/configure.log" >&2
		exit 1
	}

echo "  asserting the cross-configure answers:"
# The seeds must have LANDED -- a cache variable spelled wrong is silently
# ignored, and each of these is a silent wrong binary if it did not.
grep '^#define HAVE_LSTAT 1' config.h >/dev/null || {
	echo "[FAIL] HAVE_LSTAT is not 1 -- tar would '#define lstat stat' and follow" >&2
	echo "       every symlink it archives.  The ac_cv_func_lstat seed did not land." >&2
	exit 1; }
echo "    HAVE_LSTAT 1 (symlinks archived as symlinks)"
grep '^#define HAVE_DECL_VALLOC 0' config.h >/dev/null || {
	echo "[FAIL] HAVE_DECL_VALLOC is not 0 -- valloc is not in libc.so.1." >&2; exit 1; }
echo "    HAVE_DECL_VALLOC 0 (valloc -> malloc)"
if grep '^#define GETTIMEOFDAY_CLOBBERS_LOCALTIME_BUFFER' config.h >/dev/null; then
	echo "[FAIL] the gettimeofday clobber wrapper is still selected." >&2; exit 1
fi
echo "    no rpl_gettimeofday wrapper"
# Amix has no <strings.h>, <stdint.h> or <inttypes.h>; a HAVE_ for any of them
# would mean a probe read the BUILD host's headers (PORTING.md 4.1).
for h in STRINGS_H STDINT_H INTTYPES_H; do
	if grep "^#define HAVE_$h 1" config.h >/dev/null; then
		echo "[FAIL] config.h defines HAVE_$h -- a probe reached the host's headers." >&2
		exit 1
	fi
done
echo "    HAVE_STRINGS_H/STDINT_H/INTTYPES_H absent (target headers were read)"
echo

# ---------------------------------------------------------------------------
# 4. The D3 object, then make.
# ---------------------------------------------------------------------------
# amix-pwgr.o is linked as a plain OBJECT, not from an archive, so its four
# definitions are in the executable unconditionally.  LIBS is set at make time:
# configure tests nothing it provides.  The wrapper appends libc.so.1 itself
# (cc84d5b); the trailing -lc is kept for the older-wrapper rule (recipes/README).
echo "--- D3 passwd/group parsers ---"
$CC $AMIX_CFLAGS -c "$REPO/recipes/common/amix-pwgr.c" -o "$BUILD/amix-pwgr.o" \
	> "$BUILD/pwgr.log" 2>&1 || {
		echo "[FAIL] amix-pwgr.c did not compile" >&2; cat "$BUILD/pwgr.log" >&2; exit 1; }
# Warnings from the 1992 system headers themselves (sys/types.h's nested
# comment, stat.h's unused static wrappers) are noise; any other is a defect.
# (GCC 14 reports the system headers from its include-fixed copies.)
if grep 'warning' "$BUILD/pwgr.log" | grep -v "^$AMIX_SYSROOT/" | grep -v '/include-fixed/' >/dev/null 2>&1; then
	echo "[FAIL] amix-pwgr.c compiled with warnings:" >&2; cat "$BUILD/pwgr.log" >&2; exit 1
fi
echo "  amix-pwgr.o compiled clean"
echo

echo "--- make ---"
# gcc14: configure ran lenient; the build gets the strict CFLAGS back.
set --
[ "$AMIX_TOOLCHAIN" = gcc14 ] && set -- CFLAGS="$AMIX_CFLAGS"
make LIBS="$TAR_LIBS" "$@" > "$BUILD/make.log" 2>&1 || {
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
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	amix_gate_g14_strict "$BUILD/make.log" || exit 1
	amix_gate_g14_compat "$BUILD/make.log" || exit 1
	# the linker's trace of the final tar link: gettimeofday from libc.so's
	# static gettimeofday.o (header comment), not from anywhere else
	grep 'libc\.so(gettimeofday\.o): definition of gettimeofday$' "$BUILD/make.log" >/dev/null || {
		echo "[FAIL] gettimeofday is not defined by usr/ccs/lib/libc.so(gettimeofday.o):" >&2
		grep 'gettimeofday' "$BUILD/make.log" | grep -v '^[^ ]*gcc ' >&2
		exit 1; }
	echo "  OWNER ok  gettimeofday from libc.so(gettimeofday.o), the stock static member"
fi
BIN="$TREE/src/tar"
[ -f "$BIN" ] || { echo "[FAIL] tar binary not built" >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 5. Gates -- object code, not exit status.
# ---------------------------------------------------------------------------
echo "--- gates ---"
amix_gate_elf "$BIN"
amix_gate_d4 "$BIN" || {
	echo "[FAIL] D4 gate: this binary SIGKILLs on a 68LC060." >&2
	exit 1
}
# D3: the four lookups are DEFINED here, so libc's are never reached.
for s in getpwnam getpwuid getgrnam getgrgid; do
	"$NM" "$BIN" | awk -v s="$s" '$NF==s && $(NF-1)=="T" {f=1} END {exit !f}' || {
		echo "[FAIL] D3: $s is not defined (T) in the executable" >&2; exit 1; }
	if "$NM" -u "$BIN" | awk '{print $NF}' | grep -x "$s" >/dev/null; then
		echo "[FAIL] D3: $s is still UNDEFINED -- libc's copy would be called" >&2; exit 1
	fi
done
echo "  D3 ok   getpwnam/getpwuid/getgrnam/getgrgid defined in the executable (T), none undefined"
# Dynamic, libc.so.1 only: no host path, no other DSO (the cc84d5b DT_NEEDED fix).
needed=$("$OBJDUMP" -p "$BIN" | awk '$1=="NEEDED" {print $2}' | tr '\n' ' ')
[ "$needed" = "/usr/lib/libc.so.1 " ] || {
	echo "[FAIL] DT_NEEDED is '$needed', expected only /usr/lib/libc.so.1" >&2; exit 1; }
echo "  DT_NEEDED ok  $needed"
# Every undefined symbol must be something libc.so.1 exports.
"$NM" "$AMIX_SYSROOT/usr/lib/libc.so.1" | awk '{print $NF}' | LC_ALL=C sort -u > "$BUILD/libc.syms"
missing=$("$NM" -u "$BIN" | awk '{print $NF}' | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$BUILD/libc.syms" | tr '\n' ' ')
[ -z "$missing" ] || {
	echo "[FAIL] undefined symbols libc.so.1 does not export: $missing" >&2; exit 1; }
echo "  UNDEF ok  every undefined symbol is exported by libc.so.1"
amix_gate_undef "$BIN"
echo

# ---------------------------------------------------------------------------
# 6. Stage.
# ---------------------------------------------------------------------------
echo "--- stage ---"
rm -rf "$DEST"
mkdir -p "$DEST/opt/amix/bin" "$DEST/opt/amix/doc/tar"
cp "$BIN" "$DEST/opt/amix/bin/tar"
$STRIP "$DEST/opt/amix/bin/tar"
cp "$TREE/COPYING" "$DEST/opt/amix/doc/tar/COPYING"
cp "$TREE/NEWS"    "$DEST/opt/amix/doc/tar/NEWS"
cp "$TREE/README"  "$DEST/opt/amix/doc/tar/README"
chmod 0755 "$DEST/opt/amix/bin/tar"
chmod 0644 "$DEST/opt/amix/doc/tar"/*

echo "--- payload identity (sum -r, the only digest the box can compute) ---"
printf '  %-10s %s  %s bytes\n' tar \
    "$(sum -r "$DEST/opt/amix/bin/tar" | awk '{print $1}')" \
    "$(stat -c%s "$DEST/opt/amix/bin/tar")"
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
echo "=== GNU tar $VERSION built ==="
