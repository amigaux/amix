#!/bin/sh
#
# pkgbuild.sh -- INTERIM driver for a P-31 sec 10.9 package directory.
#
#     sh recipes/common/pkgbuild.sh recipes/<name>
#
# Two build styles (package.sh STYLE): `configure' (./configure --host, then
# make) and `make' (a plain Makefile: make with CC/AR/RANLIB/CFLAGS given on
# the command line, no configure step).
#
# INTERIM.  This stands in for amix's build/pkg framework (styles/*.sh
# + env/ + roll + pkgmeta) until the packages move into amix
# userland/packages/; it is replaced there, not carried over.  It is kept
# small and generic so the real framework can grow out of what it proves.
# It reuses this repo's amix-env.sh, fetch.sh, gates.sh and pkgroll.sh and
# adds nothing a recipe has to know about.
#
# The package directory (P-31 sec 10.9):
#   package.sh      KEY=value metadata, assignments only, the ONLY place each
#                   fact is written (below)
#   build.sh        optional hooks only, sourced after the environment:
#                     configure_args     echo extra ./configure arguments
#                     pre_configure      export configure seeds (ac_cv_...)
#                     post_configure     assert config.h answers (cwd: tree)
#                                        (the three run in STYLE=configure only)
#                     make_args          echo extra make arguments/targets
#                     post_build         assert the build (cwd: tree)
#                     stage              copy the payload into $DEST (cwd:
#                                        tree); binaries unstripped, the
#                                        driver gates and strips them
#   prototype       hand-written SVR4 payload; `i pkginfo' is generated here
#   patches/*.patch applied in name order, -p$PATCH_STRIP (default 1), each
#                   with its reason in its header
#   tests/smoke.sh  on-box acceptance (tools/pkg-smoke/ runs it)
#   README.md       porting decisions
#
# package.sh keys (required unless a default is shown):
#   NAME PKG VERSION PKGREV SUMMARY DESC CATEGORY SET LICENSE URL SHA256
#   STYLE=configure  TOOLCHAIN=gcc14  PREFIX=/opt/amix  DEPENDS=""
#   BUILD_DEPENDS=""  SRCDIR=$NAME-$VERSION  PATCH_STRIP=1
#
# Recipe variables a build.sh may set (defaults empty):
#   EXTRA_CFLAGS     added to the strict CFLAGS of configure AND make
#   ASM_REVIEWED     why imported .s/.S files are acceptable (else a failure)
#   ZERO_OK          payload paths allowed to be empty files (else a failure:
#                    a cross build's config/missing leaves a regenerated man
#                    page or info file empty, exit 0)
#
# Outputs: $AMIX_BUILD_ROOT/<NAME>/{src,work,dest,pkgwork,*.log,BUILD.txt}
# and $AMIX_BUILD_ROOT/pkg/<PKG>-<VERSION>-<PKGREV>.pkg (build/gcc14/... for
# TOOLCHAIN=gcc14).  pkginfo is generated from package.sh into pkgwork/ and
# never committed.

set -e

[ $# -eq 1 ] && [ -f "$1/package.sh" ] || {
	echo "usage: sh recipes/common/pkgbuild.sh recipes/<name>" >&2
	exit 2
}
HERE=$(cd "$1" && pwd)
REPO=$(cd "$(dirname "$0")/../.." && pwd)

# --- package.sh ---------------------------------------------------------------
STYLE=configure TOOLCHAIN=gcc14 PREFIX=/opt/amix DEPENDS= BUILD_DEPENDS= SRCDIR= PATCH_STRIP=1
. "$HERE/package.sh"
for k in NAME PKG VERSION PKGREV SUMMARY DESC CATEGORY SET LICENSE URL SHA256; do
	eval "v=\${$k-}"
	[ -n "$v" ] || { echo "[FAIL] package.sh: $k is not set" >&2; exit 1; }
done
case "$STYLE" in configure|make) ;;
*) echo "[FAIL] STYLE=$STYLE -- known: configure, make" >&2; exit 1 ;;
esac
[ "$NAME" = "$(basename "$HERE")" ] || { echo "[FAIL] NAME=$NAME is not the directory name" >&2; exit 1; }
[ "${#PKG}" -le 9 ] || { echo "[FAIL] PKG=$PKG is over 9 characters" >&2; exit 1; }
echo "$CATEGORY" | grep -Ex '[A-Za-z0-9][A-Za-z0-9+.-]*' >/dev/null || {
	echo "[FAIL] CATEGORY='$CATEGORY' is not one token" >&2; exit 1; }
for s in $SET; do
	case $s in minimal|standard|full|developer|x11|extra) ;;
	*) echo "[FAIL] SET: unknown set '$s'" >&2; exit 1 ;;
	esac
done
case "$DESC" in *'
'*) echo "[FAIL] DESC must be one line" >&2; exit 1 ;; esac
SRCDIR=${SRCDIR:-$NAME-$VERSION}
PKGVERSION=$VERSION-$PKGREV

# --- environment and hooks ------------------------------------------------------
export AMIX_PREFIX="$PREFIX"
export TOOLCHAIN
AMIX_RECIPE_TOOLCHAINS=$TOOLCHAIN
. "$REPO/recipes/common/amix-env.sh"
. "$REPO/recipes/common/fetch.sh"
. "$REPO/recipes/common/pkgroll.sh"
. "$REPO/recipes/common/gates.sh"
EXTRA_CFLAGS= ASM_REVIEWED= ZERO_OK=
configure_args() { :; }
make_args() { :; }
pre_configure() { :; }
post_configure() { :; }
post_build() { :; }
stage() { echo "[FAIL] build.sh defines no stage hook" >&2; exit 1; }
[ -f "$HERE/build.sh" ] && . "$HERE/build.sh"

BUILD="$AMIX_BUILD_ROOT/$NAME"
SRC="$BUILD/src"
WORKDIR="$BUILD/work"
TREE="$WORKDIR/$SRCDIR"
DEST="$BUILD/dest"
PKGOUT="$AMIX_BUILD_ROOT/pkg"
export HERE BUILD TREE DEST

echo "=== $NAME $PKGVERSION ($PKG, $CATEGORY, set $SET, style $STYLE) ==="
amix_env_banner
echo
mkdir -p "$SRC" "$WORKDIR" "$PKGOUT"

# --- 1. fetch, verified before extraction ----------------------------------------
echo "--- source ---"
TARBALL="$SRC/${URL##*/}"
amix_fetch "$URL" "$SHA256" "$TARBALL"
rm -rf "$TREE"
case "$TARBALL" in
*.tar.gz|*.tgz) tar xzf "$TARBALL" -C "$WORKDIR" ;;
*.tar.bz2)      tar xjf "$TARBALL" -C "$WORKDIR" ;;
*.tar.xz)       tar xJf "$TARBALL" -C "$WORKDIR" ;;
*) echo "[FAIL] unknown archive type: $TARBALL" >&2; exit 1 ;;
esac
[ -d "$TREE" ] || { echo "[FAIL] $TREE not produced by the tarball" >&2; exit 1; }
echo

# --- 2. patches ----------------------------------------------------------------------
echo "--- patches ---"
for p in "$HERE"/patches/*.patch; do
	[ -f "$p" ] || continue
	echo "  applying $(basename "$p")"
	( cd "$TREE" && patch -p"$PATCH_STRIP" --batch --fuzz=0 < "$p" ) || {
		echo "[FAIL] patch $(basename "$p") did not apply cleanly" >&2; exit 1; }
done
if ! amix_gate_noasm "$TREE"; then
	[ -n "$ASM_REVIEWED" ] || { echo "[FAIL] assembly in the tree and no ASM_REVIEWED" >&2; exit 1; }
	echo "  ASM reviewed: $ASM_REVIEWED"
fi
echo

cd "$TREE"
# --- 3. cross-configure (lenient: probes decided by the linker, gcc14-env.sh) ---------
if [ "$STYLE" = configure ]; then
echo "--- cross-configure ---"
pre_configure
CC="$CC" CPP="$AMIX_CPP" \
CFLAGS="$AMIX_CFLAGS $EXTRA_CFLAGS $AMIX_CONFIGURE_LENIENT" \
./configure --host="$AMIX_HOST_TRIPLET" --prefix="$AMIX_PREFIX" --disable-nls \
	$(configure_args) > "$BUILD/configure.log" 2>&1 || {
	echo "[FAIL] configure failed; see $BUILD/configure.log" >&2
	tail -20 "$BUILD/configure.log" >&2
	exit 1
}
post_configure
echo
fi

# --- 4. build (strict) -------------------------------------------------------------------
echo "--- make ---"
if [ "$STYLE" = make ]; then
	set -- CC="$CC" AR="$AR" RANLIB="$RANLIB"
else
	set --
fi
make "$@" CFLAGS="$AMIX_CFLAGS $EXTRA_CFLAGS" $(make_args) > "$BUILD/make.log" 2>&1 || {
	echo "[FAIL] make failed; see $BUILD/make.log" >&2
	tail -25 "$BUILD/make.log" >&2
	exit 1
}
if grep -E 'implicit declaration|pointer from integer|integer from pointer' "$BUILD/make.log" >/dev/null; then
	echo "[FAIL] implicit declarations or pointer/integer conversions in the build:" >&2
	grep -E 'implicit declaration|pointer from integer|integer from pointer' "$BUILD/make.log" | sort -u >&2
	exit 1
fi
echo "  no implicit declarations, no pointer/integer conversions"
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	amix_gate_g14_strict "$BUILD/make.log"
	amix_gate_g14_compat "$BUILD/make.log"
fi
post_build
echo

# --- 5. stage, then the prototype and the binaries ----------------------------------------
echo "--- stage ---"
rm -rf "$DEST"; mkdir -p "$DEST"
stage
# the prototype is the payload: every f/d/s line staged, nothing staged unlisted
awk '$1 ~ /^[fdvesl]$/ && NF >= 3 { p = $3; sub(/=.*$/, "", p); print p }' "$HERE/prototype" | LC_ALL=C sort > "$BUILD/proto.list"
( cd "$DEST" && find . -mindepth 1 | sed 's|^\.||' ) | LC_ALL=C sort > "$BUILD/dest.list"
if ! LC_ALL=C comm -3 "$BUILD/proto.list" "$BUILD/dest.list" | grep . >/dev/null; then
	echo "  PROTO ok  $(grep -c . "$BUILD/proto.list") paths, prototype == staged tree"
else
	echo "[FAIL] prototype and staged tree differ (left: prototype only, right: staged only):" >&2
	LC_ALL=C comm -3 "$BUILD/proto.list" "$BUILD/dest.list" >&2
	exit 1
fi
for z in $( cd "$DEST" && find . -type f -size 0 | sed 's|^\.||' ); do
	case " $ZERO_OK " in *" $z "*) echo "  EMPTY ok  $z (ZERO_OK)" ;;
	*) echo "[FAIL] empty file in the payload: $z (regenerated by config/missing?)" >&2; exit 1 ;;
	esac
done
"$NM" "$AMIX_SYSROOT/usr/lib/libc.so.1" | awk '{print $NF}' | LC_ALL=C sort -u > "$BUILD/libc.syms"
BINS=$(amix_gate_elfs "$DEST")
for b in $BINS; do
	# executables and shared objects only (ELF e_type 2/3): an archive keeps
	# its symbols and its members' undefined references
	case "$(od -An -tx1 -j16 -N2 "$b" | tr -d ' ')" in
	0002|0003) ;;
	*) echo "  ARCHIVE/OBJ $(basename "$b"): no undef gate, not stripped"; continue ;;
	esac
	amix_gate_elf "$b"
	missing=$("$NM" -u "$b" | awk '{print $NF}' | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$BUILD/libc.syms" | tr '\n' ' ')
	[ -z "$missing" ] || { echo "[FAIL] $(basename "$b"): undefined symbols libc.so.1 does not export: $missing" >&2; exit 1; }
	echo "  UNDEF ok  $(basename "$b"): every undefined symbol is exported by libc.so.1"
	$STRIP "$b"
done
echo

# --- 6. pkginfo from package.sh, roll ----------------------------------------------------
echo "--- package ---"
WORK="$BUILD/pkgwork"
rm -rf "$WORK"; mkdir -p "$WORK"
cat > "$WORK/pkginfo" <<EOF
PKG=$PKG
NAME=$SUMMARY
ARCH=Amiga
VERSION=$PKGVERSION
CATEGORY=$CATEGORY
CLASSES=none
VENDOR=amix-packages
PSTAMP=amix-packages-$PKG-$PKGVERSION-$AMIX_TOOLCHAIN
DESC=$DESC
EOF
cp "$HERE/prototype" "$WORK/prototype"
amix_pkgroll "$WORK" "$DEST" "$PKG" "$PKGVERSION" "$PKGOUT/$PKG-$PKGVERSION.pkg"

{
	echo "$NAME $PKGVERSION ($PKG) toolchain $AMIX_TOOLCHAIN"
	echo "pkg $PKGOUT/$PKG-$PKGVERSION.pkg md5 $(md5sum "$PKGOUT/$PKG-$PKGVERSION.pkg" | cut -d' ' -f1) size $(stat -c%s "$PKGOUT/$PKG-$PKGVERSION.pkg")"
	for b in $BINS; do
		echo "sum-r $(sum -r "$b" | awk '{print $1}') $(stat -c%s "$b") ${b#$DEST}"
	done
} > "$BUILD/BUILD.txt"
sed 's/^/  /' "$BUILD/BUILD.txt"
echo
echo "=== $NAME $PKGVERSION built ==="
