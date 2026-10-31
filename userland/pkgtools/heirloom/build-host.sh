#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# build-host.sh - build heirloom-pkgtools on the Linux HOST and smoke-
# test the result.  The host pkgmk/pkgtrans/pkgproto/pkginfo are used
# by the repo's package-building pipeline (tools/repo/); the same
# patched tree builds both ways (host fixes are conditional).
#
# CRITICAL: stock Amix pkgadd accepts ONLY newc (070701) cpio members
# inside datastreams (bench-verified; odc fails with rc=5).  GNU
# cpio's "-oc" emits odc, so the tools' compiled-in BINDIR points at
# build-host/bindir, where hostshims/cpio translates every SVR4 cpio
# invocation to "GNU cpio -H newc".  The smoke test below verifies the
# member magic at offset 512 of a freshly built datastream.
#
# Output: build-host/bin/  (pkginfo pkgparam pkgtrans pkgadd pkgrm
#         installf pkgchk pkgmk pkgproto pkginstall pkgremove)
#
# NOTE: regenerates every <dir>/Makefile and cleans first - do not
# interleave with build-amix.sh (final binaries in build-*/ coexist).
#
# SANITIZE=1 builds the host tools with AddressSanitizer +
# UndefinedBehaviorSanitizer (and -g, no optimisation-driven inlining of
# the frames we care about).  Used to chase memory-corruption bugs that
# glibc happens to survive silently - notably the `pkgadd -R` alternate
# root group/passwd path (libpkg/ncgrpw.c clgrnam/dup_gr_ent), which is
# reachable ONLY when -R is given AND <root>/etc/group exists.
# See tests/host-altroot/README.md.
set -eu

TOP="$(cd "$(dirname "$0")" && pwd)"

if [ "${SANITIZE:-0}" = "1" ]; then
	SANFLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer -g"
	echo "== SANITIZE=1: building with $SANFLAGS =="
	# These are short-lived 1990s tools that free nothing before exit;
	# LSan would fail every smoke test on by-design leaks.  We are
	# hunting corruption (overflow / use-after-free), not leaks.
	ASAN_OPTIONS="detect_leaks=0:abort_on_error=0"
	UBSAN_OPTIONS="print_stacktrace=1"
	export ASAN_OPTIONS UBSAN_OPTIONS
else
	SANFLAGS=""
fi

# NOGUARD=1 compiles out the defensive gnam/onam guard in
# libpkg/verify.c averify(), so an unterminated ainfo->group/owner
# faults the way stock upstream would instead of being repaired.
# DIAGNOSIS ONLY - never ship a binary built this way.
if [ "${NOGUARD:-0}" = "1" ]; then
	SANFLAGS="$SANFLAGS -DAMIX_NO_ATTR_GUARD"
	echo "== NOGUARD=1: averify() attribute guard COMPILED OUT =="
fi

# ------------------------------------------------------------------
# 1. Work area + external-command shim dir (compiled-in BINDIR)
# ------------------------------------------------------------------
rm -rf "$TOP/build-host"
mkdir -p "$TOP/build-host/bin" "$TOP/build-host/bindir" \
	 "$TOP/build-host/var/sadm" "$TOP/build-host/etc"

install -m 755 "$TOP/hostshims/cpio" "$TOP/build-host/bindir/cpio"
for t in rm rmdir ls dd cp mv ln sh mail awk nawk sed grep; do
	p="$(command -v "$t" 2>/dev/null || true)"
	[ -n "$p" ] && ln -sf "$p" "$TOP/build-host/bindir/$t"
done

# ------------------------------------------------------------------
# 2. Generate per-directory Makefiles and build (two passes: the
#    pkgcmds clean targets also remove ../../version/version.o)
# ------------------------------------------------------------------
SUBDIRS="version libadm libgendb libpkg libinst
	pkgcmds/pkginfo pkgcmds/pkgparam pkgcmds/pkgtrans
	pkgcmds/pkgadd pkgcmds/pkgrm pkgcmds/installf
	pkgcmds/pkginstall pkgcmds/pkgremove
	pkgcmds/pkgchk pkgcmds/pkgmk pkgcmds/pkgproto"

echo "== generating per-directory Makefiles (mk.config.host) =="
for d in $SUBDIRS; do
	{
		echo "TOPDIR=$TOP"
		echo "SANFLAGS=$SANFLAGS"
		cat "$TOP/mk.config.host"
		cat "$TOP/$d/Makefile.mk"
	} > "$TOP/$d/Makefile"
done

echo "== cleaning =="
for d in $SUBDIRS; do
	make -C "$TOP/$d" clean >/dev/null
done

echo "== building =="
for d in $SUBDIRS; do
	echo "--- $d"
	make -C "$TOP/$d" all >/dev/null
done

echo "== collecting binaries =="
BIN="$TOP/build-host/bin"
cp "$TOP/pkgcmds/pkginfo/pkginfo"       "$BIN/"
cp "$TOP/pkgcmds/pkgparam/pkgparam"     "$BIN/"
cp "$TOP/pkgcmds/pkgtrans/pkgtrans"     "$BIN/"
cp "$TOP/pkgcmds/pkgadd/pkgadd"         "$BIN/"
cp "$TOP/pkgcmds/pkgrm/pkgrm"           "$BIN/"
cp "$TOP/pkgcmds/installf/installf"     "$BIN/"
cp "$TOP/pkgcmds/pkgchk/pkgchk"         "$BIN/"
cp "$TOP/pkgcmds/pkgmk/pkgmk"           "$BIN/"
cp "$TOP/pkgcmds/pkgproto/pkgproto"     "$BIN/"
cp "$TOP/pkgcmds/pkginstall/pkginstall" "$BIN/"
cp "$TOP/pkgcmds/pkgremove/pkgremove"   "$BIN/"
ln -sf pkgadd   "$BIN/pkgask"
ln -sf installf "$BIN/removef"

# pkgadd/pkgrm exec the helpers from the compiled-in SADMDIR
mkdir -p "$TOP/build-host/sadm/install/bin"
cp "$TOP/pkgcmds/pkginstall/pkginstall" "$TOP/build-host/sadm/install/bin/"
cp "$TOP/pkgcmds/pkgremove/pkgremove"   "$TOP/build-host/sadm/install/bin/"

# ------------------------------------------------------------------
# 3. Smoke test: pkgmk -> pkgtrans -> verify newc magic -> pkginfo -d
#    -> datastream->dir round trip
# ------------------------------------------------------------------
echo "== smoke test =="
SMOKE="$TOP/build-host/smoke"
rm -rf "$SMOKE"
mkdir -p "$SMOKE/root/usr/lib/jutoy" "$SMOKE/spool" "$SMOKE/out"

echo "hello from jutoy" > "$SMOKE/root/usr/lib/jutoy/data.txt"
cat > "$SMOKE/pkginfo" <<'EOF'
PKG=JUTOY
NAME=Jussi's toy package (host smoke test)
ARCH=m68k
VERSION=1.0
CATEGORY=application
EOF
cat > "$SMOKE/prototype" <<EOF
i pkginfo=$SMOKE/pkginfo
d none /usr/lib/jutoy 0755 root sys
f none /usr/lib/jutoy/data.txt 0644 root sys
EOF

"$BIN/pkgmk" -o -r "$SMOKE/root" -f "$SMOKE/prototype" \
	-d "$SMOKE/spool" JUTOY >/dev/null
[ -d "$SMOKE/spool/JUTOY" ] || { echo "SMOKE FAIL: pkgmk"; exit 1; }
echo "pkgmk:            OK (directory package built)"

"$BIN/pkgtrans" -s "$SMOKE/spool" "$SMOKE/out/jutoy.pkg" JUTOY >/dev/null
[ -f "$SMOKE/out/jutoy.pkg" ] || { echo "SMOKE FAIL: pkgtrans"; exit 1; }

hdr="$(head -c 20 "$SMOKE/out/jutoy.pkg")"
case "$hdr" in
"# PaCkAgE DaTaStReAm"*) echo "datastream header: OK" ;;
*) echo "SMOKE FAIL: bad datastream header: $hdr"; exit 1 ;;
esac

magic="$(dd if="$SMOKE/out/jutoy.pkg" bs=1 skip=512 count=6 2>/dev/null)"
if [ "$magic" = "070701" ]; then
	echo "member magic:      OK (070701 newc at offset 512 - Amix-compatible)"
else
	echo "SMOKE FAIL: member magic at offset 512 is '$magic', want 070701"
	exit 1
fi

"$BIN/pkginfo" -d "$SMOKE/out/jutoy.pkg" | grep -q JUTOY || {
	echo "SMOKE FAIL: pkginfo -d on datastream"; exit 1; }
echo "pkginfo -d:        OK"

mkdir -p "$SMOKE/spool2"
"$BIN/pkgtrans" "$SMOKE/out/jutoy.pkg" "$SMOKE/spool2" JUTOY >/dev/null
diff -r "$SMOKE/spool/JUTOY" "$SMOKE/spool2/JUTOY" >/dev/null || {
	echo "SMOKE FAIL: datastream->dir round trip differs"; exit 1; }
echo "round trip:        OK (dir -> stream -> dir identical)"

# ------------------------------------------------------------------
# 4. Smoke test the two Amix-critical patches against a fake
#    /var/sadm (compiled-in VSADMDIR points into build-host/):
#    - tolerant srchcfile: contents contains the real corrupt factory
#      record (space in pathname) - stock parsers abort on it;
#    - VERSION relaxation: a factory-style pkginfo without VERSION
#      must list as "(none)" instead of erroring.
# ------------------------------------------------------------------
echo "== patched-behavior smoke test =="
V="$TOP/build-host/var/sadm"
mkdir -p "$V/install" "$V/pkg/NOVER"
cp "$TOP/../research/heirloom/contents-harness/contents.amix" 	"$V/install/contents"
cat > "$V/pkg/NOVER/pkginfo" <<'EOF'
PKG=NOVER
NAME=Factory-style package without VERSION
ARCH=Amiga
CATEGORY=system
EOF

"$BIN/pkginfo" | grep -q NOVER || {
	echo "SMOKE FAIL: VERSION-less package missing from listing"; exit 1; }
out="$("$BIN/pkginfo" -l NOVER)" || {
	echo "SMOKE FAIL: pkginfo -l aborted (corrupt contents or VERSION)"
	exit 1; }
echo "$out" | grep -q "VERSION:  (none)" || {
	echo "SMOKE FAIL: missing 'VERSION: (none)' relaxation"; exit 1; }
echo "tolerant parser:   OK (corrupt factory record in contents tolerated)"
echo "VERSION relaxed:   OK (listed as \"(none)\")"

# ------------------------------------------------------------------
# 5. compat pw/gr parser regression against stock-format /etc/passwd
#    and /etc/group fixtures of ours (the libc-passwd sidestep)
# ------------------------------------------------------------------
echo "== pw/gr parser regression (Amix-format fixtures) =="
"$TOP/compat/tests/test-pwgr.sh" || { echo "SMOKE FAIL: pw/gr parser"; exit 1; }

# ------------------------------------------------------------------
# 6. removef stdin form (`removef PKG -`) removes exactly the listed
#    paths (AMIX PORT fix 2026-10-26: upstream kept fgets' newline)
# ------------------------------------------------------------------
echo "== removef stdin-form regression =="
"$TOP/tests/removef-stdin/run.sh" || { echo "SMOKE FAIL: removef stdin"; exit 1; }

echo "== host build + smoke test PASSED =="
ls -l "$BIN"
