#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# build-amix-static.sh - STATIC-LINK variant of the Amix cross build.
#
# Emits the CD-resident installer engine tools as FULLY STATIC m68k SVR4
# ELF executables (ET_EXEC, ZERO PT_INTERP, ZERO DT_NEEDED):
#
#   build-amix-static/bin/          apkg  pkgadd  pkgtrans  pkginfo  pkgchk
#                                   contents-fsck
#   build-amix-static/sadm-helpers/ pkginstall
#
# apkg here is the FILE+RAW-only variant (built -DAPKG_NO_HTTP with http.c
# excluded); see the apkg section below and AMIX-PORT.md option 1.
#
# contents-fsck is our own C89 contents(4) DB checker (src/contents-fsck),
# added here so the installer driver can run a contents-DB integrity CHECK
# as an install step on the freshly-installed target (Installer-NG W6.4a).
# It is libc-only (single source, static buffers, no malloc, no sockets),
# so it links fully static exactly like apkg's FILE+RAW path - crt +
# values-Xt + one object + libc.a, no heirloom libs, no libnsl/libsocket.
# The installer invocation is CHECK-ONLY (report mode, no -r): exit 0 =
# clean, non-zero = findings/error -> the driver must fail closed.  See the
# contents-fsck section below and AMIX-PORT.md "Static-link variant".
#
# WHY STATIC (Installer-NG W5.0 / E4 probe, 2026-07-22).  The stock
# install miniroot (amix-installng amix_21_root.adf) is a hostile host
# for our dynamically-linked engine:
#   * it carries NO libnsl.so anywhere;
#   * its libc.so.1 is a DIFFERENT build from the golden 2.1c one, and on
#     Amix libc.so.1 IS the PT_INTERP (the runtime linker is embedded in
#     libc), so LD_LIBRARY_PATH provably cannot redirect it.
# Static linking kills all three: it bundles everything, removes the
# libc-build skew, and drops PT_INTERP entirely.  These tools are what the
# install CD carries (per the miniroot decomposition: pkgadd execs
# pkginstall; pkgtrans reads the .pkg datastream; pkginfo/pkgchk are the
# installer's gates).
#
# THE DEFAULT SHARED BUILD (build-amix.sh) IS UNCHANGED and stays the
# deploy set for the installed /usr/apkg.  This is an ADDITIONAL variant,
# NOT a replacement; it does not touch build-amix/ or any shared output.
#
# Mechanism.  The compile step is identical to the shared build - only the
# LINK differs (static libc.a instead of the shared libc).  So this script
# runs build-amix.sh to produce the compiled objects, the heirloom
# archives (libinst/libpkg/libgendb/libadm .a) and libamix.a, then
# RE-LINKS the CD tool subset with m68k-cbm-sysv4-ld directly (the same
# ld-direct pattern src/apkg uses), swapping the shared libc for the
# static /usr/ccs/lib/libc.a and adding values-Xt.o.  values-Xt.o defines
# _lib_version (the C library-mode global the compiler driver normally
# injects): the shared libc.so.1 EXPORTS it so the shared build never
# names it, but static libc.a members only REFERENCE it, so it must be
# linked in.  -Xt is the traditional SVR4.0 default library mode.
#
# apkg IS emitted here (option 1, resolved 2026-07-22).  Its SVR4 socket()
# path (libsocket.a) transitively pulls in libnsl's netconfig(3N) trio
# (setnetconfig/getnetconfig/endnetconfig), and NO static libnsl.a exists
# in the Amix 2.1 distribution (the install tape ships libnsl.so only).
# So the STATIC apkg drops the HTTP backend: it is compiled -DAPKG_NO_HTTP
# with http.c excluded, which removes the socket -> netconfig dependency
# entirely and lets apkg link fully static against libc.a alone, exactly
# like the heirloom tools.  An http:// repo given to this build FAILS
# CLOSED at source classification (source.c); FILE (file:///path) and RAW
# (raw:<device>) - the only media a CD install uses - are byte-for-byte
# the shared build's.  The DYNAMIC apkg (src/apkg `make amix`) is
# UNAFFECTED and keeps full HTTP.  Rationale + the deferred option 2
# (static netconfig(3N) reader, if a static+HTTP apkg is ever wanted):
# AMIX-PORT.md "Static-link variant".
#
# NOTE: like build-amix.sh, this regenerates every <dir>/Makefile and runs
# "make clean" (inside build-amix.sh), so it cannot run concurrently with
# an in-flight build-host.sh / build-amix.sh.  Set SKIP_DYNAMIC=1 to reuse
# an EXISTING build-amix.sh tree (fast iteration; assumes objects current).
#
set -eu

TOP="$(cd "$(dirname "$0")" && pwd)"
# Default: a gcc-cross-amix checkout beside this repo (set AMIX_CROSS_ENV
# to point elsewhere).
CROSS_ENV="${AMIX_CROSS_ENV:-$TOP/../../gcc-cross-amix/build/env.sh}"

if ! command -v m68k-cbm-sysv4-gcc >/dev/null 2>&1; then
	if [ -r "$CROSS_ENV" ]; then
		# shellcheck disable=SC1090
		. "$CROSS_ENV"
	fi
fi
command -v m68k-cbm-sysv4-ld >/dev/null 2>&1 || {
	echo "build-amix-static.sh: m68k-cbm-sysv4-ld not in PATH (set AMIX_CROSS_ENV)" >&2
	exit 1
}

LD=m68k-cbm-sysv4-ld
STRIP=m68k-cbm-sysv4-strip
OBJDUMP=m68k-cbm-sysv4-objdump
# ELF parsing is target-agnostic; the cross toolchain ships no readelf, so
# use the host readelf (it reads the m68k SVR4 ELF perfectly) for the
# ET_EXEC / PT_INTERP / dynamic-section evidence.
READELF="${READELF:-readelf}"
command -v "$READELF" >/dev/null 2>&1 || {
	echo "build-amix-static.sh: host '$READELF' not found (needed for ELF checks)" >&2
	exit 1
}

REAL_SYSROOT="${AMIX_SYSROOT:-$HOME/opt/amix-cross/m68k-cbm-sysv4/sysroot}"
CRT="$REAL_SYSROOT/usr/ccs/lib"
LIBC_A="$CRT/libc.a"
VALUES="$CRT/values-Xt.o"
for f in "$CRT/crt1.o" "$CRT/crti.o" "$CRT/crtn.o" "$VALUES" "$LIBC_A"; do
	[ -r "$f" ] || { echo "build-amix-static.sh: missing $f" >&2; exit 1; }
done

# ------------------------------------------------------------------
# 1. Produce the compiled objects + archives via the shared build.
#    (build-amix.sh leaves every <dir>/*.o, the four heirloom .a, and
#    build-amix/lib/libamix.a in place; it also rebuilds the DEFAULT
#    shared set into build-amix/ - identically to a standalone run.)
# ------------------------------------------------------------------
if [ "${SKIP_DYNAMIC:-0}" = 1 ]; then
	echo "== SKIP_DYNAMIC=1: reusing existing build-amix.sh tree =="
else
	echo "== running build-amix.sh to compile objects + archives =="
	"$TOP/build-amix.sh" >/dev/null
fi

LIBAMIX="$TOP/build-amix/lib/libamix.a"
[ -r "$LIBAMIX" ] || {
	echo "build-amix-static.sh: $LIBAMIX not found - run build-amix.sh first (or unset SKIP_DYNAMIC)" >&2
	exit 1
}

# The four heirloom archives (PKGLIBS, identical for every tool:
# -linst -lpkg -lgendb -ladm) resolved to full paths, in link order.
HEIRLIBS="$TOP/libinst/libinst.a $TOP/libpkg/libpkg.a \
	$TOP/libgendb/libgendb.a $TOP/libadm/libadm.a"

# ------------------------------------------------------------------
# 2. Fresh output area
# ------------------------------------------------------------------
# STATIC_OUT names the output dir (default build-amix-static/, rebuilt in
# place).  A mint that a consumer pins builds into a versioned sibling
# instead, e.g. STATIC_OUT=$TOP/build-amix-static-1.12.2, so the set an
# earlier pin names is never overwritten (amix-installng's build-install-
# iso.sh takes STATIC=<dir>; NOTES.md 2026-10-05, APKGENG 1.12.2).
OUTDIR="${STATIC_OUT:-$TOP/build-amix-static}"
case "$OUTDIR" in /*) ;; *) OUTDIR="$PWD/$OUTDIR" ;; esac
BIN="$OUTDIR/bin"
SADM="$OUTDIR/sadm-helpers"
APKG_OBJ="$OUTDIR/obj-apkg"
CFSCK_OBJ="$OUTDIR/obj-cfsck"
rm -rf "$OUTDIR"
mkdir -p "$BIN" "$SADM" "$APKG_OBJ" "$CFSCK_OBJ"

# fail flag is accumulated across the whole run (the apkg section below
# and the verification section both feed it); declared once here.
fail=0

# the repo root (this script lives in heirloom/) and the apkg / contents-fsck
# source dirs
REPO="$(dirname "$TOP")"
APKG_SRCDIR="$REPO/src/apkg"
CFSCK_SRCDIR="$REPO/src/contents-fsck"

# ------------------------------------------------------------------
# 3. Parse OBJ from a tool's Makefile.mk (handles \-continuations) and
#    resolve each token relative to the tool directory.  Parsing the
#    Makefile is faithful to the shared build; globbing *.o is NOT (some
#    tool dirs carry a stray build-artifact version.o that OBJ never
#    references - linking it would multiply-define version()).
# ------------------------------------------------------------------
obj_list() {	# $1 = absolute tool dir
	local dir="$1" toks
	toks=$(awk '
		/^OBJ[[:space:]]*=/ { grab=1; sub(/^OBJ[[:space:]]*=[[:space:]]*/, "") }
		grab {
			line=$0
			cont = (line ~ /\\[[:space:]]*$/)
			gsub(/\\[[:space:]]*$/, "", line)
			print line
			if (!cont) exit
		}' "$dir/Makefile.mk")
	local t
	for t in $toks; do
		printf '%s/%s\n' "$dir" "$t"
	done
}

# ------------------------------------------------------------------
# 4. Static link the CD tool subset.
#    Layout: <tool> <subdir-under-pkgcmds> <dest: bin|sadm>
# ------------------------------------------------------------------
TOOLS="pkgadd:bin pkgtrans:bin pkginfo:bin pkgchk:bin pkginstall:sadm"

echo "== static-linking CD engine tools =="
for spec in $TOOLS; do
	tool="${spec%%:*}"; dest="${spec##*:}"
	sdir="$TOP/pkgcmds/$tool"
	[ -d "$sdir" ] || { echo "  $tool: no dir $sdir" >&2; exit 1; }
	case "$dest" in
	bin)  out="$BIN/$tool" ;;
	sadm) out="$SADM/$tool" ;;
	esac
	objs=$(obj_list "$sdir")
	echo "--- $tool"
	# shellcheck disable=SC2086
	"$LD" -o "$out" \
		"$CRT/crt1.o" "$CRT/crti.o" "$VALUES" \
		$objs \
		$HEIRLIBS \
		"$LIBAMIX" \
		"$LIBC_A" \
		"$CRT/crtn.o"
done

# ------------------------------------------------------------------
# 4b. Static-link apkg (FILE + RAW only; HTTP backend compiled out).
#     The dynamic apkg needs libsocket.a -> libnsl netconfig(3N), which
#     has no static archive on Amix 2.1; -DAPKG_NO_HTTP + dropping http.c
#     removes the socket path entirely, so apkg links fully static like
#     the heirloom tools (crt + values-Xt + objs + libc.a, no libnsl/
#     libsocket).  Source set = the apkg Makefile's SRCS minus http.c and
#     dns.c, so it never drifts from the shared build's file list.
#     (dns.c is the stub resolver: sockets and gethostbyname, i.e. the
#     same netconfig closure.  It also #ifdefs itself out entirely under
#     -DAPKG_NO_HTTP, so the exclusion here is belt to that braces -- it
#     is listed by name so the build LOG says the resolver is absent.)
# ------------------------------------------------------------------
APKG_CC=m68k-cbm-sysv4-gcc
APKG_CFLAGS="-O -DHIGHFIRST -DAPKG_NO_HTTP"
command -v "$APKG_CC" >/dev/null 2>&1 || {
	echo "build-amix-static.sh: $APKG_CC not in PATH (needed for apkg)" >&2
	exit 1
}
[ -d "$APKG_SRCDIR" ] || { echo "build-amix-static.sh: no $APKG_SRCDIR" >&2; exit 1; }
APKG_SRCS=$(awk '/^SRCS[[:space:]]*=/{sub(/^SRCS[[:space:]]*=[[:space:]]*/,"");print}' \
	"$APKG_SRCDIR/Makefile")
[ -n "$APKG_SRCS" ] || { echo "build-amix-static.sh: could not read SRCS from apkg Makefile" >&2; exit 1; }

echo "== compiling apkg objects (FILE+RAW only, -DAPKG_NO_HTTP; http.c + dns.c excluded) =="
apkg_objs=""
for s in $APKG_SRCS; do
	case "$s" in
	http.c) echo "  (excluding $s - HTTP backend not in the static build)"; continue ;;
	dns.c)  echo "  (excluding $s - stub resolver not in the static build)"; continue ;;
	esac
	o="$APKG_OBJ/${s%.c}.o"
	# shellcheck disable=SC2086
	"$APKG_CC" $APKG_CFLAGS -c "$APKG_SRCDIR/$s" -o "$o"
	apkg_objs="$apkg_objs $o"
done

echo "== static-linking apkg =="
# shellcheck disable=SC2086
"$LD" -o "$BIN/apkg" \
	"$CRT/crt1.o" "$CRT/crti.o" "$VALUES" \
	$apkg_objs \
	"$LIBC_A" \
	"$CRT/crtn.o"

# nm proof (UNSTRIPPED, before the strip below).  A fully static exe has
# ZERO undefined symbols; in particular NONE of the libnsl netconfig(3N)
# trio or gethostbyname that the HTTP/socket path would have dragged in.
echo "== apkg nm proof: no undefined symbols, no netconfig/libnsl/socket refs =="
NM="${NM:-m68k-cbm-sysv4-nm}"
command -v "$NM" >/dev/null 2>&1 || NM=nm
undef=$("$NM" -u "$BIN/apkg" 2>/dev/null || true)
if [ -n "$undef" ]; then
	echo "  BAD: apkg has undefined symbols:"; echo "$undef" | sed 's/^/    /'
	fail=1
else
	echo "  OK: apkg has ZERO undefined symbols (fully static)"
fi
netref=$("$NM" "$BIN/apkg" 2>/dev/null | \
	grep -Ew 'setnetconfig|getnetconfig|endnetconfig|gethostbyname|socket|connect|http_get' || true)
if [ -n "$netref" ]; then
	echo "  BAD: apkg references socket/netconfig/http symbols:"; echo "$netref" | sed 's/^/    /'
	fail=1
else
	echo "  OK: no setnetconfig/getnetconfig/endnetconfig/gethostbyname/socket/connect/http_get"
fi

# ------------------------------------------------------------------
# 4c. Static-link contents-fsck (our C89 contents(4) checker/repairer).
#     Single libc-only source (static buffers, no malloc, no sockets), so
#     it links fully static exactly like apkg's FILE+RAW path: crt +
#     values-Xt + the one object + libc.a, NO heirloom libs, NO libnsl/
#     libsocket.  Compiled with the SAME wrapper (m68k-cbm-sysv4-gcc) the
#     engine set uses, so it inherits the .swbeg + tdivs asm fixes.  The
#     installer runs it CHECK-ONLY (report mode, no -r): exit 0 = clean,
#     non-zero = findings/error (the driver fails closed).  -r/-s repair
#     is a post-migration tool, NOT an install step.
# ------------------------------------------------------------------
CFSCK_CC=m68k-cbm-sysv4-gcc
CFSCK_CFLAGS="-O"
command -v "$CFSCK_CC" >/dev/null 2>&1 || {
	echo "build-amix-static.sh: $CFSCK_CC not in PATH (needed for contents-fsck)" >&2
	exit 1
}
[ -r "$CFSCK_SRCDIR/contents-fsck.c" ] || {
	echo "build-amix-static.sh: no $CFSCK_SRCDIR/contents-fsck.c" >&2
	exit 1
}

echo "== compiling + static-linking contents-fsck (libc-only) =="
# shellcheck disable=SC2086
"$CFSCK_CC" $CFSCK_CFLAGS -c "$CFSCK_SRCDIR/contents-fsck.c" \
	-o "$CFSCK_OBJ/contents-fsck.o"
"$LD" -o "$BIN/contents-fsck" \
	"$CRT/crt1.o" "$CRT/crti.o" "$VALUES" \
	"$CFSCK_OBJ/contents-fsck.o" \
	"$LIBC_A" \
	"$CRT/crtn.o"

# nm proof (UNSTRIPPED, before the strip below): a fully static exe has
# ZERO undefined symbols.
echo "== contents-fsck nm proof: no undefined symbols (fully static) =="
cundef=$("$NM" -u "$BIN/contents-fsck" 2>/dev/null || true)
if [ -n "$cundef" ]; then
	echo "  BAD: contents-fsck has undefined symbols:"; echo "$cundef" | sed 's/^/    /'
	fail=1
else
	echo "  OK: contents-fsck has ZERO undefined symbols (fully static)"
fi

# strip (deploy-ready, matching build-amix.sh)
# shellcheck disable=SC2086
"$STRIP" "$BIN"/apkg "$BIN"/pkgadd "$BIN"/pkgtrans "$BIN"/pkginfo "$BIN"/pkgchk \
	"$BIN"/contents-fsck "$SADM"/pkginstall 2>/dev/null || echo "(strip failed; binaries left unstripped)"

# ------------------------------------------------------------------
# 5. Verification: ET_EXEC, m68k MSB, ZERO PT_INTERP, ZERO DT_NEEDED,
#    no dynamic section.
# ------------------------------------------------------------------
echo "== verification (static ELF: EXEC / no INTERP / no NEEDED) =="
for f in "$BIN"/apkg "$BIN"/pkgadd "$BIN"/pkgtrans "$BIN"/pkginfo "$BIN"/pkgchk \
	 "$BIN"/contents-fsck "$SADM"/pkginstall; do
	b=$(basename "$f")

	t=$(file -b "$f")
	case "$t" in
	*"ELF 32-bit MSB"*[mM]68k*statically*) ;;
	*) printf '%-12s BAD file: %s\n' "$b" "$t"; fail=1 ;;
	esac

	etype=$("$READELF" -h "$f" 2>/dev/null | awk -F: '/^[[:space:]]*Type:/{print $2}')
	case "$etype" in
	*EXEC*) ;;
	*) printf '%-12s BAD ELF type:%s\n' "$b" "$etype"; fail=1 ;;
	esac

	interp=$("$READELF" -l "$f" 2>/dev/null | grep -c INTERP || true)
	[ "$interp" = 0 ] || { printf '%-12s BAD: %s PT_INTERP\n' "$b" "$interp"; fail=1; }

	# DT_NEEDED via BOTH host readelf and the cross objdump the shared
	# build uses; either printing a dynamic entry is a failure.
	needed=$("$READELF" -d "$f" 2>/dev/null | grep -c NEEDED || true)
	[ "$needed" = 0 ] || { printf '%-12s BAD: %s DT_NEEDED\n' "$b" "$needed"; fail=1; }
	odneed=$("$OBJDUMP" -p "$f" 2>/dev/null | awk '/NEEDED/{n++} END{print n+0}')
	[ "$odneed" = 0 ] || { printf '%-12s BAD: objdump %s NEEDED\n' "$b" "$odneed"; fail=1; }

	if [ "$fail" = 0 ] || true; then
		printf '%-12s OK  %s\n' "$b" "$t"
	fi
done

# ------------------------------------------------------------------
# 6. Cross-build health: divsll-only.  Scope = OUR compiled objects
#    (the .o that feed the link) + libamix's di_ops.  A whole-binary
#    scan would false-positive on the vendor libc.a members that a
#    static link legitimately pulls in (pre-assembled by the original
#    SGS toolchain, they carry real 64-bit divsl/divul).  The only
#    acceptable helper form in OUR code is the 32-bit-dividend
#    divsll/divull (the tdivs-fix criterion; see AMIX-PORT.md item 0).
# ------------------------------------------------------------------
echo "== cross-build health: divsll-only (our compiled code) =="
bad=$(
	{
		find "$TOP" -name '*.o' -not -path "$TOP/build-amix/*" \
			-not -path "$TOP/build-amix-static*" -print0 |
			xargs -0 "$OBJDUMP" -d 2>/dev/null
		"$OBJDUMP" -d "$LIBAMIX" 2>/dev/null
	} | grep -oE '\bdiv[su]l\b' | sort | uniq -c
)
good=$(
	{
		find "$TOP" -name '*.o' -not -path "$TOP/build-amix/*" \
			-not -path "$TOP/build-amix-static*" -print0 |
			xargs -0 "$OBJDUMP" -d 2>/dev/null
		"$OBJDUMP" -d "$LIBAMIX" 2>/dev/null
	} | grep -oE '\bdiv[su]ll\b' | sort | uniq -c
)
echo "  acceptable (divsll/divull):"; echo "$good" | sed 's/^/    /'
if [ -n "$bad" ]; then
	echo "  MIS-ASSEMBLED 64-bit divsl/divul (tdivs defect!):"
	echo "$bad" | sed 's/^/    /'
	fail=1
else
	echo "  no bare divsl/divul in our code (clean)"
fi

# same check for the NEW apkg objects (they live under the output dir,
# build-amix-static*/, so the find above deliberately skipped them; scan
# them explicitly).
echo "== cross-build health: divsll-only (apkg compiled objects) =="
abad=$("$OBJDUMP" -d "$APKG_OBJ"/*.o 2>/dev/null | grep -oE '\bdiv[su]l\b' | sort | uniq -c)
agood=$("$OBJDUMP" -d "$APKG_OBJ"/*.o 2>/dev/null | grep -oE '\bdiv[su]ll\b' | sort | uniq -c)
echo "  acceptable (divsll/divull):"
[ -n "$agood" ] && echo "$agood" | sed 's/^/    /' || echo "    (none present)"
if [ -n "$abad" ]; then
	echo "  MIS-ASSEMBLED 64-bit divsl/divul in apkg (tdivs defect!):"
	echo "$abad" | sed 's/^/    /'
	fail=1
else
	echo "  no bare divsl/divul in apkg objects (clean)"
fi

# same check for the NEW contents-fsck object (also under build-amix-static/,
# skipped by the section-6 find; scan it explicitly).
echo "== cross-build health: divsll-only (contents-fsck object) =="
cbad=$("$OBJDUMP" -d "$CFSCK_OBJ"/*.o 2>/dev/null | grep -oE '\bdiv[su]l\b' | sort | uniq -c)
cgood=$("$OBJDUMP" -d "$CFSCK_OBJ"/*.o 2>/dev/null | grep -oE '\bdiv[su]ll\b' | sort | uniq -c)
echo "  acceptable (divsll/divull):"
[ -n "$cgood" ] && echo "$cgood" | sed 's/^/    /' || echo "    (none present - contents-fsck does no division)"
if [ -n "$cbad" ]; then
	echo "  MIS-ASSEMBLED 64-bit divsl/divul in contents-fsck (tdivs defect!):"
	echo "$cbad" | sed 's/^/    /'
	fail=1
else
	echo "  no bare divsl/divul in contents-fsck object (clean)"
fi

# ------------------------------------------------------------------
# 6b. 68060 health: no 64-bit MULx.L/DIVx.L, MOVEP, CMP2/CHK2/CAS2 in
#     the emitted binaries (vector 61 SIGKILLs the process on the 060;
#     NOTES.md 2026-10-05).  Decided from the encoding, whole binary,
#     libc.a members included.
# ------------------------------------------------------------------
echo "== 68060 health: scan060 (emitted static binaries) =="
python3 "$TOP/../tools/repo/scan060.py" "$BIN" "$SADM" || fail=1

# ------------------------------------------------------------------
# 7. Sizes
# ------------------------------------------------------------------
echo "== emitted static binaries =="
ls -l "$BIN" "$SADM"
echo "== sizes (bytes) =="
for f in "$BIN"/apkg "$BIN"/pkgadd "$BIN"/pkgtrans "$BIN"/pkginfo "$BIN"/pkgchk \
	 "$BIN"/contents-fsck "$SADM"/pkginstall; do
	printf '  %-13s %s\n' "$(basename "$f")" "$(wc -c < "$f")"
done

[ "$fail" = 0 ] && echo "== STATIC BUILD OK ==" || echo "== STATIC BUILD FAILED =="
exit $fail
