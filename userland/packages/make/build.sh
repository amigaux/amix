#!/bin/sh
#
# build.sh -- fetch, cross-configure, cross-build and package GNU make 3.81.
#
#     sh recipes/make/build.sh
#
# Outputs under the gitignored build/ tree:
#
#     build/make/src/make-3.81.tar.gz   the pinned tarball (cached)
#     build/make/work/make-3.81/        the extracted, patched, built tree
#     build/make/dest/                  the staged install tree
#     build/pkg/make-3.81.pkg           the datastream
#
# make coexists with stock: the AT&T/SVR4 make is /usr/ccs/bin/make, owned by
# `core`, and this package does NOT touch it.  Ours installs to
# /opt/amix/bin/make and wins for interactive users by PATH.
#
# ---------------------------------------------------------------------------
# WHAT MADE IT BUILD -- AND BUILD RIGHT (all measured 2026-09-26)
#
# 1. -D_POSIX_SOURCE, deliberately.  make's job control needs sigset_t,
#    sigprocmask, sigemptyset and kill, all behind the __STDC__ header gate in
#    the default ANSI view (job.c does not even parse).  Of the gate's three keys
#    (PORTING.md 2.4.1) -U__STDC__ breaks gcc's own <stdarg.h> and
#    -D_XOPEN_SOURCE breaks <signal.h>; -D_POSIX_SOURCE opens every door make
#    walks through.  What it closes -- lstat (so no -L/--check-symlink-times),
#    struct timeval (make falls back to time(), unaffected), strdup's
#    declaration -- is either unused or restored by patches/01.  The cross-
#    configure answers were diffed with and without the key: identical.
#
# 2. patches/01 (config.h.in): declare strdup (hidden) and getrlimit/setrlimit
#    (declared by no SVR4 header outside _KERNEL); define SA_RESTART (a kernel
#    ABI value, 0x4, that sys/signal.h hides under _POSIX_SOURCE); and
#    `#define environ _environ` -- libc.so.1 exports only _environ (PORTING 3.1).
#
# 3. TWO CONFIGURE ANSWERS THAT WERE WRONG, seeded with the reason:
#      ac_cv_have_decl__sys_siglist=no  <signal.h> declares _sys_siglist but
#                                       libc.so.1 does not export it (nm); make
#                                       then builds its own signal-name table.
#      make_cv_sa_restart=yes           the probe compiles in the POSIX view,
#                                       where the macro is hidden; the kernel
#                                       honours the flag.  It also turns on the
#                                       jobserver (-j across recursive makes).
#
# 4. The load-average code (make -l) is compiled with NO kernel-reading method:
#    getloadavg.c finds no OS branch for SVR4.0/m68k, so make -l reports it
#    cannot enforce the limit instead of reading /dev/kmem through nlist() --
#    which on Amix returns an ALIGNMENT for the COMMON avenrun symbol and would
#    throttle on garbage (PORTING.md 3.3).  The build asserts no nlist/kmem use.
#
# make links nothing from libacompat (measured: the undefined-symbol gate
# below is satisfied by libc.so.1 alone), so it carries no build dependency.

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

PKG=make
VERSION=$MAKE_VERSION
# The PACKAGE version is the source version plus a package revision.  -2 is
# the 68060 re-mint (2026-10-05; no package may rely on kernel emulation of
# 68060-unimplemented instructions): the same source rebuilt through the
# wrapper's 64-bit multiply expansion (gcc-cross-amix 2ab2b22) -- new
# bytes, so a new catalog version; apkg_vercmp orders 3.81-2 above 3.81.
# Package revision by toolchain: the period build is -2 (the 68060 re-mint);
# a TOOLCHAIN=gcc14 build is new bytes and so a new revision, -3 (phase 2 of
# the userland switch, owner decision D-3 sec 9); pkginfo is retagged in the
# work copy (amix_pkginfo_retag).
case "$AMIX_TOOLCHAIN" in
gcc14) PKGREV=3 ;;
*)     PKGREV=2 ;;
esac
PKGVERSION=$VERSION-$PKGREV

BUILD="$AMIX_BUILD_ROOT/make"
SRC="$BUILD/src"
WORKDIR="$BUILD/work"
TREE="$WORKDIR/make-$VERSION"
DEST="$BUILD/dest"
PKGOUT="$AMIX_BUILD_ROOT/pkg"

echo "=== GNU make $VERSION ==="
amix_env_banner
echo

mkdir -p "$SRC" "$WORKDIR" "$PKGOUT"

# ---------------------------------------------------------------------------
# 1. Fetch, verified BEFORE extraction.
# ---------------------------------------------------------------------------
echo "--- source ---"
amix_fetch "$MAKE_URL" "$MAKE_SHA256" "$SRC/make-$VERSION.tar.gz"
rm -rf "$TREE"
tar xzf "$SRC/make-$VERSION.tar.gz" -C "$WORKDIR"
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
	echo "[FAIL] unexpected .s/.S assembly in the make tree." >&2; exit 1; }
echo

# ---------------------------------------------------------------------------
# 3. Cross-configure.
# ---------------------------------------------------------------------------
echo "--- cross-configure ---"
cd "$TREE"
# TOOLCHAIN=gcc14 pins four configure answers to the period build's.  GCC 14
# links the SVR4 way -- usr/ccs/lib/libc.so is an archive of libc.so.1 plus
# static members -- so probes now find what the period link never saw:
#   elf_begin in -lelf -> AC_FUNC_GETLOADAVG defines SVR4 and takes the
#     nlist()/kmem load average (the NLIST-COMMON trap, PORTING.md 3.3) with
#     a setgid-kmem install: pinned no, as the LOADAVG gate below requires;
#   vfork (static vfork.o) -> pinned no: make keeps fork, as bench-proven;
#   stdint.h (the compat one) -> make.h then uses uintmax_t without
#     including it and does not compile: pinned no, uintmax_t stays the
#     period's `unsigned long long'.
#   lstat (static lstat.o) -> MAKE_SYMLINKS, whose code needs lstat,
#     readlink and S_IFLNK, which the -D_POSIX_SOURCE view below hides:
#     pinned no, as the period build (no symlink-mtime support).
# realpath/seteuid/setegid (static members) and strsignal (libamixc99, its
# one owner) are left as GCC 14's configure finds them.
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	export ac_cv_lib_elf_elf_begin=no ac_cv_func_vfork=no ac_cv_header_stdint_h=no \
		ac_cv_func_lstat=no
fi
ac_cv_have_decl__sys_siglist=no \
make_cv_sa_restart=yes \
CC="$CC" \
CPP="$AMIX_CPP" \
CFLAGS="$AMIX_CFLAGS -D_POSIX_SOURCE $AMIX_CONFIGURE_LENIENT" \
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
grep '^#define HAVE_DECL__SYS_SIGLIST 0' config.h >/dev/null || {
	echo "[FAIL] HAVE_DECL__SYS_SIGLIST is not 0 -- _sys_siglist is not in libc.so.1." >&2; exit 1; }
echo "    HAVE_DECL__SYS_SIGLIST 0 (make's own signal-name table)"
grep '^#define HAVE_SA_RESTART 1' config.h >/dev/null || {
	echo "[FAIL] HAVE_SA_RESTART is not 1 -- the make_cv_sa_restart seed did not land." >&2; exit 1; }
echo "    HAVE_SA_RESTART 1"
grep '^#define MAKE_JOBSERVER 1' config.h >/dev/null || {
	echo "[FAIL] the jobserver is not enabled." >&2; exit 1; }
echo "    MAKE_JOBSERVER 1"
grep '^#define environ _environ' config.h >/dev/null || {
	echo "[FAIL] patches/01's environ alias is not in config.h" >&2; exit 1; }
echo "    environ -> _environ"
for h in STRINGS_H STDINT_H INTTYPES_H; do
	if grep "^#define HAVE_$h 1" config.h >/dev/null; then
		echo "[FAIL] config.h defines HAVE_$h -- a probe reached the host's headers." >&2
		exit 1
	fi
done
echo "    HAVE_STRINGS_H/STDINT_H/INTTYPES_H absent (target headers were read)"
echo

# ---------------------------------------------------------------------------
# 4. Build.
# ---------------------------------------------------------------------------
echo "--- make ---"
# gcc14: configure ran lenient; the build gets the strict CFLAGS back.
set --
[ "$AMIX_TOOLCHAIN" = gcc14 ] && set -- CFLAGS="$AMIX_CFLAGS -D_POSIX_SOURCE"
make "$@" > "$BUILD/make.log" 2>&1 || {
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
fi
BIN="$TREE/make"
[ -f "$BIN" ] || { echo "[FAIL] make binary not built" >&2; exit 1; }
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
needed=$("$OBJDUMP" -p "$BIN" | awk '$1=="NEEDED" {print $2}' | tr '\n' ' ')
[ "$needed" = "/usr/lib/libc.so.1 " ] || {
	echo "[FAIL] DT_NEEDED is '$needed', expected only /usr/lib/libc.so.1" >&2; exit 1; }
echo "  DT_NEEDED ok  $needed"
"$NM" "$AMIX_SYSROOT/usr/lib/libc.so.1" | awk '{print $NF}' | LC_ALL=C sort -u > "$BUILD/libc.syms"
missing=$("$NM" -u "$BIN" | awk '{print $NF}' | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$BUILD/libc.syms" | tr '\n' ' ')
[ -z "$missing" ] || {
	echo "[FAIL] undefined symbols libc.so.1 does not export: $missing" >&2; exit 1; }
echo "  UNDEF ok  every undefined symbol is exported by libc.so.1"
# The load average must not come from nlist()/kmem (PORTING.md 3.3).
if "$NM" -u "$BIN" | awk '{print $NF}' | grep -E '^(nlist|kvm_open|kstat_open)$' >/dev/null; then
	echo "[FAIL] make reads kernel symbols via nlist -- the COMMON-avenrun trap" >&2; exit 1
fi
if strings "$BIN" | grep -x '/dev/kmem' >/dev/null; then
	echo "[FAIL] make opens /dev/kmem for the load average" >&2; exit 1
fi
echo "  LOADAVG ok  no nlist(), no /dev/kmem (make -l degrades to a warning)"
# SHIM-FNMATCH: the box has no fnmatch/glob; make's bundled glob/ must be the
# copy in the binary, not a half-present system symbol.
for s in glob fnmatch; do
	"$NM" "$BIN" | awk -v s="$s" '$NF==s && $(NF-1)=="T" {f=1} END {exit !f}' || {
		echo "[FAIL] $s is not defined in the binary -- the bundled glob/ was not linked" >&2; exit 1; }
done
echo "  GLOB ok  bundled glob()/fnmatch() linked in (T)"
amix_gate_undef "$BIN"
echo

# ---------------------------------------------------------------------------
# 6. Stage.
# ---------------------------------------------------------------------------
echo "--- stage ---"
rm -rf "$DEST"
mkdir -p "$DEST/opt/amix/bin" "$DEST/opt/amix/man/man1" "$DEST/opt/amix/doc/make"
cp "$BIN" "$DEST/opt/amix/bin/make"
$STRIP "$DEST/opt/amix/bin/make"
cp "$TREE/make.1"            "$DEST/opt/amix/man/man1/make.1"
cp "$TREE/COPYING"           "$DEST/opt/amix/doc/make/COPYING"
cp "$TREE/glob/COPYING.LIB"  "$DEST/opt/amix/doc/make/COPYING.LIB"
cp "$TREE/NEWS"              "$DEST/opt/amix/doc/make/NEWS"
cp "$TREE/README"            "$DEST/opt/amix/doc/make/README"
chmod 0755 "$DEST/opt/amix/bin/make"
chmod 0644 "$DEST/opt/amix/man/man1/make.1" "$DEST/opt/amix/doc/make"/*

echo "--- payload identity (sum -r, the only digest the box can compute) ---"
printf '  %-10s %s  %s bytes\n' make \
    "$(sum -r "$DEST/opt/amix/bin/make" | awk '{print $1}')" \
    "$(stat -c%s "$DEST/opt/amix/bin/make")"
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
echo "=== GNU make $VERSION built ==="
