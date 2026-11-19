#!/bin/sh
# build.sh: build the shared host tools that write Amix-format files.
#
# MIT licence, see LICENSE at the top of the repository.
#
#     sh build/hosttools/build.sh [--check]
#
# Builds, from our pinned sources, the tools a recipe runs on the build host
# whose output Amix reads, so that every recipe uses one Amix-correct set
# instead of the build host's own:
#
#   imake        X11R6.3's, built with -DAMIX: it hands its cpp -traditional
#                -DAMIX -DSVR4 -Dm68k and none of the build host's defines
#                (the wrapper runs it with IMAKECPP=libexec/imakecpp, the host
#                cpp with -undef)
#   makedepend   X11R6.3's, with no built-in defines of the build host; the
#                wrapper passes the target compiler's defines (CC, else
#                AMIX_GCC14_CC, as build/pkg sets them) and its include
#                directories, never the host's /usr/include
#   bdftopcf     X11R6.3's, PCF in the Amix server's layout (MSB first, glyphs
#   mkfontdir    padded to 32 bits), deterministic (patches/x11r6.3)
#   amix-xcpp    a traditional cpp with the predefines of the stock Amix
#                /usr/ccs/lib/cpp (m68k, unix) and none of the host's: what
#                xrdb runs on the box, for resource files preprocessed at
#                build time
#   gencat       ours (gencat/), writes the catalogue formats of Amix's libc,
#                byte for byte as the stock gencat does
#
# The X11R6.3 source is x11r6.3.distfile's tarball (the one the x11r6.3 recipe
# builds), fetched and checked by toolchain/fetch-distfile; patches/x11r6.3 is
# applied to it in name order. The host C compiler is HOSTCC (default cc).
#
# Output: AMIX_HOSTTOOLS (default out/hosttools in this checkout):
#   bin/       what goes first on a recipe's PATH (build/pkg/pkgbuild.sh)
#   libexec/   the programs the wrappers run
#   TOOLS      one line per program of bin/ and libexec/: name, sha256
#   STAMP      the inputs' digest; a build with the same inputs is skipped
# --check: exit 0 if the set is built and current, 1 if not, building nothing.
# Prints the bin/ directory last.
set -eu
umask 022

here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../.." && pwd)
out=${AMIX_HOSTTOOLS:-$top/out/hosttools}
hcc=${HOSTCC:-cc}
check=0
[ "${1:-}" = --check ] && check=1

# the inputs: every file of this directory (git's list in a checkout, else
# all of them), the distfile's sha256 and the host compiler's identity
inputs() {
	( cd "$here" &&
	  { git ls-files -co --exclude-standard . 2>/dev/null || find . -type f; } |
	  LC_ALL=C sort | while read -r f; do [ -f "$f" ] && sha256sum "$f"; done )
	"$hcc" --version 2>/dev/null | head -1
}
stamp=$(inputs | sha256sum | cut -c1-64)
if [ -f "$out/STAMP" ] && [ "$(cat "$out/STAMP")" = "$stamp" ] && [ -x "$out/bin/imake" ]; then
	[ $check = 1 ] || echo "  current  $out ($stamp)" >&2
	echo "$out/bin"
	exit 0
fi
if [ $check = 1 ]; then
	echo "[FAIL] the shared host tools in $out are not built from these inputs;" >&2
	echo "       sh build/hosttools/build.sh" >&2
	exit 1
fi

work=$out/work
rm -rf "${out:?}/bin" "${out:?}/libexec" "${out:?}/TOOLS" "${out:?}/STAMP" "${work:?}"
mkdir -p "$work" "$out/bin" "$out/libexec"

# --- the X11R6.3 source ------------------------------------------------------
tgz=$(sh "$top/toolchain/fetch-distfile" "$here/x11r6.3.distfile")
tar -xzf "$tgz" -C "$work"
xc=$work/xc
chmod -R u+w "$xc"
for p in "$here"/patches/x11r6.3/*.patch; do
	patch -s -d "$xc" -p1 --fuzz=0 < "$p" || { echo "[FAIL] $p does not apply" >&2; exit 1; }
done
# the X headers as <X11/...>
mkdir -p "$work/hinc"
ln -s "$xc/include" "$work/hinc/X11"

log=$work/build.log
: > "$log"
cc_() { echo "$hcc $*" >> "$log"; "$hcc" "$@" >> "$log" 2>&1 || { echo "[FAIL] host compile, see $log" >&2; tail -20 "$log" >&2; exit 1; }; }
# R6.3 is K&R-era C: gnu89, common symbols, its warnings off
base="-std=gnu89 -fcommon -w -O2"

# --- imake ---------------------------------------------------------------------
# -Ulinux: imake's host branches (the build host's uname and libc in the
# Makefiles) stay out; -DAMIX: the cpp_argv of patches 01
cc_ $base -DAMIX -DSVR4 -Dm68k -Ulinux -I"$xc/include" -I"$work/hinc" \
	-o "$out/libexec/imake" "$xc/config/imake/imake.c"

# --- makedepend -----------------------------------------------------------------
md=$xc/config/makedepend
# XPG5, not glibc's default view: its own getline() is not POSIX 2008's
cc_ $base -std=c89 -D_XOPEN_SOURCE=500 -DAMIX -DSVR4 -Dm68k -DINCLUDEDIR='"/nonexistent"' -DOBJSUFFIX='".o"' \
	-I"$md" -I"$xc/config/imake" -I"$xc/include" -I"$work/hinc" \
	-o "$out/libexec/makedepend" \
	"$md/include.c" "$md/main.c" "$md/parse.c" "$md/pr.c" "$md/cppsetup.c" "$md/ifparser.c"

# --- the font library subset, bdftopcf and mkfontdir ------------------------------
# -DLONG64: R6.3's font code assumes 32-bit longs otherwise; -DAMIX -Dm68k
# -Ulinux: servermd.h's Amix block (patches 02), not the host's
fl=$xc/lib/font
fcflags="$base -D_GNU_SOURCE -DLONG64 -DAMIX -Dm68k -Ulinux \
	-I$xc/include/fonts -I$fl/include -I$xc/programs/Xserver/include -I$work/hinc -I$xc/include"
mkdir -p "$work/font"
for s in \
	bitmap/bdfread bitmap/bdfutils bitmap/bitmap bitmap/bitmaputil bitmap/bitscale \
	bitmap/bitmapfunc bitmap/pcfread bitmap/pcfwrite bitmap/snfread bitmap/fontink \
	fontfile/dirfile fontfile/fontdir fontfile/fontfile fontfile/fileio fontfile/fontscale \
	fontfile/defaults fontfile/bitsource fontfile/register fontfile/renderers fontfile/bufio \
	fontfile/decompress fontfile/filewr fontfile/printerfont fontfile/ffcheck \
	util/utilbitmap util/fontnames util/fontutil util/fontxlfd util/format \
	util/fontaccel util/atom util/miscutil util/private util/patcache; do
	# shellcheck disable=SC2086 (the flags, one word each)
	cc_ $fcflags -c "$fl/$s.c" -o "$work/font/$(echo "$s" | tr / _).o"
done
rm -f "$work/libfont.a"
ar cq "$work/libfont.a" "$work"/font/*.o
# shellcheck disable=SC2086
cc_ $fcflags -o "$out/bin/bdftopcf" "$xc/programs/bdftopcf/bdftopcf.c" "$work/libfont.a"
# shellcheck disable=SC2086
cc_ $fcflags -o "$out/bin/mkfontdir" "$xc/programs/mkfontdir/mkfontdir.c" "$work/libfont.a" -lm

# --- gencat --------------------------------------------------------------------------
cc_ -O2 -Wall -Wextra -o "$out/bin/gencat" "$here/gencat/gencat.c"

# --- the wrappers ----------------------------------------------------------------------
for w in imake imakecpp makedepend amix-xcpp; do
	case $w in
	imakecpp) d=$out/libexec ;;
	*) d=$out/bin ;;
	esac
	cp "$here/wrap/$w" "$d/$w"
	chmod 755 "$d/$w"
done

( cd "$out" && find bin libexec -type f | LC_ALL=C sort | xargs sha256sum ) > "$out/TOOLS"
rm -rf "${work:?}"
echo "$stamp" > "$out/STAMP"
echo "  built    $out ($stamp)" >&2
echo "$out/bin"
