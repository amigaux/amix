#!/bin/sh
#
# smoke.sh -- OFFLINE, host-side smoke for the amix-benchmark package.
#
#     sh recipes/amix-benchmark/tests/smoke.sh
#
# This is what can be proven WITHOUT an Amix box: the datastream is structurally
# valid, its binaries are the pinned m68k SVR4 artifacts with a clean libc-only
# DT_NEEDED, and the runbench driver's argument handling / matrix are intact
# (the driver is portable SVR4 Bourne sh, so --help and --list run on the host
# without executing any m68k code).  The actual on-box RUN is a separate proof
# -- see README.md "Re-running the on-box test".

set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
. "$HERE/../pin.sh" 2>/dev/null || { AMIXBENCH_VERSION=1.3; }

PKG=amixbench
VERSION="${AMIXBENCH_VERSION:-1.3}"
DS="$REPO/build/pkg/$PKG-$VERSION.pkg"

PM="$REPO/../amix-packagemanager"
HB="${AMIX_PKGMGR:-$PM}/heirloom/build-host/bin"
PKGCHK="$HB/pkgchk"; PKGTRANS="$HB/pkgtrans"; PKGINFO="$HB/pkginfo"

fail() { echo "[FAIL] $*" >&2; exit 1; }

[ -f "$DS" ] || fail "datastream not built: $DS (run build.sh first)"
echo "=== amix-benchmark smoke: $DS ==="

# 1. newc magic at 512
magic=$(dd if="$DS" bs=1 skip=512 count=6 2>/dev/null)
[ "$magic" = "070701" ] || fail "member magic '$magic' != 070701"
echo "  [ok] newc (070701) member magic"

# 2. pkginfo + pkgchk on the stream
"$PKGINFO" -d "$DS" >/dev/null 2>&1 || fail "pkginfo -d rejected the stream"
"$PKGCHK"  -d "$DS" "$PKG" >/dev/null 2>&1 || fail "pkgchk -d failed"
echo "  [ok] pkginfo -d / pkgchk -d accept the stream"

# 3. unpack and check the payload
UX=$(mktemp -d)
trap 'rm -rf "$UX"' EXIT
"$PKGTRANS" "$DS" "$UX" "$PKG" >/dev/null 2>&1
ROOT="$UX/$PKG/root"; KIT="$ROOT/opt/amix/lib/amix-bench"

[ -f "$ROOT/opt/amix/bin/amix-bench" ] || fail "entry command not packaged"
for b in dhry iobench fpbench membench vmbench runbench.sh BUILD-INFO PROVENANCE; do
	[ -f "$KIT/$b" ] || fail "kit file missing from package: $b"
done
if [ -e "$KIT/whet" ]; then
	fail "whet is packaged -- it statically links stock SVR4 libm.a and must not ship (see pin.sh)"
fi
echo "  [ok] entry command + kit (5 binaries incl. iobench, driver, BUILD-INFO, PROVENANCE); whet absent"

# 4. each binary is m68k SVR4 ELF, libc-only DT_NEEDED, pinned sha256
echo "$AMIXBENCH_PINS" | while read name want; do
	[ -n "$name" ] || continue
	# README-FIELD.txt is staged as the doc README.txt (<= 14-byte s5 name);
	# everything else is verbatim in the kit dir.
	case "$name" in
		README-FIELD.txt) path="$ROOT/opt/amix/doc/amix-benchmark/README.txt" ;;
		*)                path="$KIT/$name" ;;
	esac
	got=$(sha256sum "$path" | cut -d' ' -f1)
	[ "$got" = "$want" ] || { echo "[FAIL] $name sha256 $got != pinned $want" >&2; exit 1; }
done
for b in dhry iobench fpbench membench vmbench; do
	d=$(LC_ALL=C file -b "$KIT/$b")
	case "$d" in
		*"ELF 32-bit MSB"*"Motorola m68k"*) : ;;
		*) fail "$b is not m68k SVR4 ELF: $d" ;;
	esac
	if command -v readelf >/dev/null 2>&1; then
		needed=$(readelf -d "$KIT/$b" 2>/dev/null | grep NEEDED | grep -v 'libc\.so\.1' || true)
		[ -z "$needed" ] || fail "$b has a NEEDED other than libc.so.1: $needed"
		rp=$(readelf -d "$KIT/$b" 2>/dev/null | grep -iE 'RPATH|RUNPATH' || true)
		[ -z "$rp" ] || fail "$b carries an RPATH/RUNPATH: $rp"
	fi
done
echo "  [ok] all five binaries: m68k SVR4 ELF, DT_NEEDED=libc.so.1 only, sha256 == pins"

# 5. the driver's arg handling / matrix (host sh; no m68k executed)
sh "$KIT/runbench.sh" --help >/dev/null 2>&1 || fail "--help did not exit 0"
rows=$(sh "$KIT/runbench.sh" --list | grep -c .)
[ "$rows" = 24 ] || fail "--list produced $rows rows, expected 24"
sh "$KIT/runbench.sh" --list | grep -q '^cpu.dhry '   || fail "--list missing cpu.dhry"
sh "$KIT/runbench.sh" --list | grep -q '^disk.seq.read.512 ' || fail "--list missing the iobench disk rows"
sh "$KIT/runbench.sh" --list | grep -q '^fpu.whet '   || fail "--list missing fpu.whet"
if sh "$KIT/runbench.sh" --bogus >/dev/null 2>&1; then fail "a bogus arg should exit non-zero"; fi
echo "  [ok] driver: --help exit 0, 24-row matrix incl. iobench + fpu, bad arg rejected"

# 6. ★ THE 1.2 DRIVER FIX GATE.
#
# The metal run (real 68LC060 A4000D @ 80 MHz, 2026-09-16) found the default
# suite stopping after cpu.dhry + fpu.dhry.  Cause: `matrix_rows | while read
# row` feeds the row list on the shell's STDIN, and the benchmark children
# INHERIT that pipe -- run_fpdhry's fpbench pilot ladder, which iterates far
# more on soft FP than on the emulated reference, drained the remaining rows and
# the loop ended early.  The 1.2 driver redirects the benchmark calls' stdin
# from /dev/null.
#
# Assert the SHIPPED driver actually carries the fix instead of trusting the
# kit's version string -- the family rule is to verify the artifact.  This is
# NOT vacuous: 1.1 contained no stdin redirect at all (every /dev/null in it is
# a stderr/stdout redirect), so this check fails on 1.1 and passes only once the
# fix is really in the file.
grep -qE '<[[:space:]]*/dev/null' "$KIT/runbench.sh" || \
	fail "shipped runbench.sh has NO stdin redirect from /dev/null -- the 1.2 pipe-drain fix is missing from this kit"
echo "  [ok] driver carries the 1.2 stdin-redirect fix (pipe-drain defect)"

# 7. ★ THE LICENCE GATE: NO STOCK SVR4 libm MAY BE STATICALLY LINKED IN.
#
# The fieldkit's `whet` statically links /usr/ccs/lib/libm.a -- Commodore/AT&T
# SVR4 object code -- so it is not packaged (pin.sh has the measurement and the
# argument).  This repository ships only our own builds, and pkg.amigaux.org is
# a PUBLIC mirror, so that exposure must not come back silently in a later kit
# bump or a rebuilt binary.
#
# Checking the file list is not enough: the question is not "is whet here" but
# "does ANY shipped binary carry libm.a's code".  So look at the object code --
# a T-defined (locally defined, not imported) libm signature symbol.  Imported
# ones are fine and expected: they resolve from the box's own libc at runtime,
# which is the normal, permitted dynamic link.
LIBM_SYMS='^(sin|cos|tan|atan|atan2|exp|log|log10|sqrt|matherr)$'
NMBIN=""
for c in "${NM:-}" m68k-cbm-sysv4-nm nm; do
	if [ -n "$c" ] && command -v "$c" >/dev/null 2>&1; then
		NMBIN="$c"
		break
	fi
done
# A gate that cannot run must FAIL, never silently pass -- an absent nm would
# otherwise report the healthy answer for every package forever.
[ -n "$NMBIN" ] || fail "no nm available: cannot verify the libm licence gate (refusing to pass it unchecked)"
if ! "$NMBIN" "$KIT/dhry" >/dev/null 2>&1; then
	fail "$NMBIN cannot read m68k SVR4 objects: cannot verify the libm licence gate"
fi
for b in dhry iobench fpbench membench vmbench; do
	hits=$("$NMBIN" "$KIT/$b" 2>/dev/null | grep -E '^[0-9a-fA-F]+ [Tt] ' | awk '{print $3}' \
	       | grep -E "$LIBM_SYMS" | tr '\n' ' ')
	[ -z "$hits" ] || fail "$b statically defines stock SVR4 libm symbols ($hits) -- must not be published"
done
echo "  [ok] licence gate: no packaged binary statically defines libm.a symbols"

echo "=== smoke PASS (offline) -- on-box RUN is the deferred proof, see README.md ==="
