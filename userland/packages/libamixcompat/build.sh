#!/bin/sh
#
# build.sh -- cross-build libacompat and roll it into an SVR4 .pkg datastream.
#
#     sh recipes/libamixcompat/build.sh
#
# Outputs, all under the gitignored build/ tree:
#
#     build/libamixcompat/obj/           object files
#     build/libamixcompat/dest/          the staged install tree pkgmk reads
#     build/libamixcompat/host/          the host differential test
#     build/pkg/acompat-<VERSION>.pkg    the datastream
#
# TOOLCHAIN=gcc14 (owner decision 2026-10-27, the userland switch): the same
# outputs under build/gcc14/ (libamixcompat/, pkg/acompat-0.1-4.pkg).
#
# ORDER OF OPERATIONS, AND WHY.  The host differential test runs FIRST and its
# failure is fatal.  It compares this exact source against glibc's snprintf over
# five thousand (format, value, buffer-size) combinations, and it costs a
# second.  Running it after the cross build would mean discovering an algorithm
# bug at the far end of a bench cycle, which on this project is a ten-minute
# inetd lockout away from being an hour.
#
# THE BUILD IS NOT DONE WHEN THE COMPILER EXITS 0.  On this toolchain a clean
# exit proves nothing: fcmp operand order, SGS '#'-as-comment and constant-
# folded FP all produce exit 0 and a wrong binary.  So the script ends in gates
# that read object code -- see recipes/common/gates.sh.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

AMIX_RECIPE_TOOLCHAINS="period gcc14"

. "$REPO/recipes/common/amix-env.sh"
. "$REPO/recipes/common/pkgroll.sh"
. "$REPO/recipes/common/gates.sh"

VERSION=0.1
PKG=acompat
# The PACKAGE version is the source version plus a package revision.  -2 is
# the 68060 re-mint (2026-10-05; no package may rely on kernel emulation of
# 68060-unimplemented instructions): the same source rebuilt through the
# wrapper's 64-bit multiply expansion (gcc-cross-amix 2ab2b22) -- new
# bytes, so a new catalog version; apkg_vercmp orders 0.1-2 above 0.1.
# Package revision by toolchain: the period build is -2 (the 68060 re-mint); a
# TOOLCHAIN=gcc14 build is new bytes and so a new revision (the userland
# switch, owner decision D-3 sec 9 and 2026-10-27): -3 was gcc14-cross-amix
# e316f1b (never published: pointers came back in %d0 only), -4 is cf461e3
# (pointers in %a0 and %d0, structs via %a0, as AMIX's compilers and libc).
# pkginfo is retagged in the work copy (amix_pkginfo_retag).
case "$AMIX_TOOLCHAIN" in
gcc14) PKGREV=4 ;;
*)     PKGREV=2 ;;
esac
PKGVERSION=$VERSION-$PKGREV

# THE gcc14 BUILD IS THE SAME LIBRARY, NOT A SUBSET.  libacompat ships to the
# box for on-box builds, which have no libamixc99, so the gcc14 archive keeps
# all seven members -- snprintf/strcasecmp/usleep included -- with the same
# declarations (include/amixcompat.h, unchanged).  Two gcc14-only details:
#   - GCC 14's fixed <unistd.h> declares usleep(unsigned long); amixcompat.h
#     declares usleep(unsigned int) (the same 32-bit argument on this ABI, but
#     two types to a C compiler).  -D_AMIX_HAVE_USLEEP suppresses the fixed
#     header's declaration in this build only, so the shipped header and the
#     definition stay as they are.
#   - the version string says which build it is (acompat-test prints it), so a
#     smoke cannot mistake the period archive for this one.
# The ONE-OWNER rule for gcc14 PORTS is untouched: no ported recipe links
# libacompat (amix_gate_g14_compat).  Its own acceptance test is the exception
# by design -- it exists to run libacompat's members -- and step 3 proves from
# the linker's trace that every compat symbol came from libacompat.a.
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	ACOMPAT_VERSTR="$PKGVERSION-gcc14"
	ACOMPAT_G14FLAGS="-D_AMIX_HAVE_USLEEP"
else
	ACOMPAT_VERSTR="$VERSION"
	ACOMPAT_G14FLAGS=
fi

BUILD="$AMIX_BUILD_ROOT/libamixcompat"
OBJ="$BUILD/obj"
DEST="$BUILD/dest"
HOSTB="$BUILD/host"
PKGOUT="$AMIX_BUILD_ROOT/pkg"

echo "=== libacompat $VERSION ==="
amix_env_banner
echo

rm -rf "$OBJ" "$DEST" "$HOSTB"
mkdir -p "$OBJ" "$HOSTB" "$PKGOUT"
mkdir -p "$DEST/usr/local/lib" "$DEST/usr/local/include" \
         "$DEST/usr/local/bin" "$DEST/usr/local/doc/acompat"

# ---------------------------------------------------------------------------
# 1. Host differential test -- the algorithm, checked against a known-good
#    reference before a single m68k instruction is emitted.
# ---------------------------------------------------------------------------
echo "--- host differential test (vs the host libc's snprintf) ---"
HOSTCC="${HOSTCC:-cc}"
$HOSTCC -O1 -Wall -o "$HOSTB/host-diff" \
	"$HERE/tests/host-diff.c" "$HERE/src/snprintf.c" \
	-I"$HERE/include" -DAMIX_NO_LIBC_NAMES -D_AMIX_HAVE_SSIZE_T
"$HOSTB/host-diff" || {
	echo "[FAIL] host differential test failed -- the algorithm is wrong;" >&2
	echo "       do not spend a bench cycle on this build." >&2
	exit 1
}
echo

# ---------------------------------------------------------------------------
# 2. Cross-compile.
#
# ON -U__STDC__.  PORTING.md sec 2.4 records that 131 sysroot headers gate on
# __STDC__ and that the ANSI view is the SMALLER one, so the standing advice is
# to try -U__STDC__ before believing a header says a facility is absent.  This
# library was built BOTH WAYS and the objects compared: for this source the two
# are byte-identical, because nothing here touches a __STDC__-gated declaration
# (`struct timeval` is gated on _POSIX_SOURCE, not on __STDC__).  So the flag is
# NOT applied -- adding a flag that changes nothing would leave the next reader
# unable to tell which of the two rules it was obeying.  The rule libacompat
# does obey is the other half of sec 2.4: never -ansi, never -D_POSIX_SOURCE,
# because on this vintage those REMOVE API.
#
# AMIX_COMPAT_VERSION is injected rather than edited into version.c so the
# recipe's version and the binary's cannot disagree.
# ---------------------------------------------------------------------------
echo "--- cross-compile (m68k-cbm-sysv4) ---"
CFLAGS="$AMIX_CFLAGS $ACOMPAT_G14FLAGS -I$HERE/include -DAMIX_COMPAT_VERSION=\"$ACOMPAT_VERSTR\""

SOURCES="snprintf.c strcase.c env.c mkstemp.c usleep.c timeofday.c version.c"
for s in $SOURCES; do
	o="$OBJ/$(basename "$s" .c).o"
	echo "  CC   $s"
	# -Wall output is captured, not discarded: on gcc 2.7 an "implicit
	# declaration" warning means the compiler invented an int-returning
	# prototype and the program will get the wrong value at run time.  Any
	# such warning is a defect, so the build refuses on one.
	$CC $CFLAGS -c "$HERE/src/$s" -o "$o" 2>"$OBJ/$(basename "$s" .c).warn"
	if [ -s "$OBJ/$(basename "$s" .c).warn" ]; then
		cat "$OBJ/$(basename "$s" .c).warn"
		if grep -q 'implicit declaration' "$OBJ/$(basename "$s" .c).warn"; then
			echo "[FAIL] implicit declaration in $s -- gcc 2.7 will hand the" >&2
			echo "       caller an int where the real return type is not one." >&2
			exit 1
		fi
	fi
done

echo "  AR   libacompat.a"
rm -f "$DEST/usr/local/lib/libacompat.a"
$AR rc "$DEST/usr/local/lib/libacompat.a" "$OBJ"/*.o
$RANLIB "$DEST/usr/local/lib/libacompat.a"
echo

# ---------------------------------------------------------------------------
# 3. The on-box acceptance test, linked against the archive being packaged.
# ---------------------------------------------------------------------------
#
# TWO WRAPPER RULES, BOTH MEASURED HERE AND BOTH SILENT WHEN BROKEN.  The
# wrapper hand-rolls its own ld command line, and that has consequences no
# ordinary gcc has:
#
#   1. AN ARCHIVE NAMED ON THE COMMAND LINE LANDS *BEFORE* THE OBJECTS.  The
#      wrapper collects `foo.a` into its objects[] list while parsing, then
#      APPENDS the objects it compiles from .c sources to the same list.  So
#      `gcc prog.c libfoo.a` links as `libfoo.a prog.o`, single-pass ld sees
#      the archive while nothing is undefined yet, extracts no members, and the
#      link fails with "undefined reference" to every symbol the archive
#      contains.  Use -L/-l, which the wrapper places after the objects.
#
#   2. ANY EXPLICIT -l SUPPRESSES THE IMPLICIT libc.  The wrapper defaults to
#      `libs=(c)` only when NO -l was given at all, so `-lacompat` alone drops
#      libc from the link entirely -- and the first casualties are crt1.o's own
#      atexit/exit/_environ/__fpstart, which makes the error look like a broken
#      toolchain rather than a missing flag.  ALWAYS end the library list with
#      -lc.  Any recipe whose configure fills in LIBS= must append it there too.
#
echo "--- link the on-box acceptance test ---"
# gcc14: -Wl,-y asks the linker where each compat symbol was defined; every
# one must come from libacompat.a (the archive under test), not libamixc99.
set --
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	for s in snprintf vsnprintf strcasecmp strncasecmp usleep setenv unsetenv mkstemp gettimeofday; do
		set -- "$@" "-Wl,-y,$s"
	done
fi
$CC $AMIX_CFLAGS $ACOMPAT_G14FLAGS -I"$HERE/include" \
	-o "$DEST/usr/local/bin/acompat-test" \
	"$HERE/tests/compat-test.c" \
	-L"$DEST/usr/local/lib" -lacompat -lc "$@" > "$BUILD/link.log" 2>&1 || {
		echo "[FAIL] acompat-test did not link" >&2; cat "$BUILD/link.log" >&2; exit 1; }
[ "$AMIX_TOOLCHAIN" = gcc14 ] || cat "$BUILD/link.log"
if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	echo "  linker trace (definitions):"
	grep 'definition of' "$BUILD/link.log" | sed 's|.*/||; s/^/    /'
	for s in snprintf vsnprintf strcasecmp strncasecmp usleep setenv unsetenv mkstemp gettimeofday; do
		grep -E "libacompat\.a\([a-z]+\.o\): definition of $s\$" "$BUILD/link.log" >/dev/null || {
			echo "[FAIL] $s in acompat-test is not defined by libacompat.a -- the test" >&2
			echo "       would exercise another archive's copy (libamixc99 or libc)." >&2
			exit 1; }
	done
	echo "  OWNER ok  all nine compat symbols come from libacompat.a"
	# acompat-test prints with libc printf, never an ll conversion: every %ll
	# in its strings goes to snprintf (the member under test).  Reviewed
	# 2026-10-27 (tests/compat-test.c: printf takes %s/%d/%ld only).
	AMIX_LL_PRINTF_REVIEWED="acompat-test: every ll conversion goes to libacompat snprintf; printf takes %s/%d/%ld only"
	export AMIX_LL_PRINTF_REVIEWED
fi
# NOT stripped yet.  amix_gate_undef reads the symbol table to list what the
# binary still needs from the box's libc, and stripping first makes that gate
# print nothing at all -- a gate that silently reports success because it can no
# longer see anything is worse than no gate.  The strip happens after the gates.
echo

# ---------------------------------------------------------------------------
# 4. Stage headers and documentation.
# ---------------------------------------------------------------------------
cp "$HERE/include/amixcompat.h" "$DEST/usr/local/include/amixcompat.h"
cp "$HERE/include/stdint.h"     "$DEST/usr/local/include/stdint.h"
cp "$HERE/include/strings.h"    "$DEST/usr/local/include/strings.h"
cp "$HERE/LICENSE"              "$DEST/usr/local/doc/acompat/LICENSE"
cp "$HERE/README.md"            "$DEST/usr/local/doc/acompat/README"
chmod 0644 "$DEST/usr/local/include"/*.h "$DEST/usr/local/doc/acompat"/*
chmod 0644 "$DEST/usr/local/lib/libacompat.a"
chmod 0755 "$DEST/usr/local/bin/acompat-test"

# ---------------------------------------------------------------------------
# 5. Gates -- read the object code, not the exit status.
# ---------------------------------------------------------------------------
echo "--- gates ---"
amix_gate_noasm "$HERE/src"
amix_gate_elf "$DEST/usr/local/bin/acompat-test"
# D4: the 68LC060 lane.  Run on the ARCHIVE as well as the executable, because
# the archive is what every other package in this repo will link.
amix_gate_d4 "$DEST/usr/local/lib/libacompat.a" "$DEST/usr/local/bin/acompat-test" || {
	echo "[FAIL] D4 gate: this artifact SIGKILLs on a 68LC060." >&2
	echo "       Escape hatches, in order: the kernel-side ISP vector-61" >&2
	echo "       extension (X1); building the offending TU -m68000; a 32-bit" >&2
	echo "       algorithm.  Do not wave it through." >&2
	exit 1
}
amix_gate_undef "$DEST/usr/local/bin/acompat-test"
echo "  symbols defined by the archive:"
$NM "$DEST/usr/local/lib/libacompat.a" 2>/dev/null |
	awk '$2 == "T" || $2 == "D" { print "          " $3 }' | sort
echo

# Strip only now that every gate has read what it needed.  Size is not a
# nicety on this target: the box has ~44 MB free on its root.
$STRIP "$DEST/usr/local/bin/acompat-test" 2>/dev/null || true

# The identity a bench transcript can check against.  `sum -r` is the one
# checksum Amix actually has -- the box ships no md5 and no cksum -- so this is
# what an on-box verification of "the installed file is the file I built" has to
# compare, and printing it here is what makes that comparison possible later.
echo "--- payload identity (sum -r, the only digest the box can compute) ---"
for f in "$DEST/usr/local/lib/libacompat.a" "$DEST/usr/local/bin/acompat-test"; do
	printf '  %-16s %s  %s bytes\n' "$(basename "$f")" \
	    "$(sum -r "$f" | awk '{print $1}')" "$(stat -c%s "$f")"
done
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
echo "=== libacompat $VERSION built ==="
