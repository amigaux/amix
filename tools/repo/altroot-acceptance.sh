#!/bin/sh
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# altroot-acceptance.sh - drive the base-set `pkgadd -R` acceptance run on
# the Amix box (Bourne sh, euid 0).  For each package, in dependency order
# (core first):
#     Gate 13  core-first-gate.sh   (refuse non-core into a bare root)
#     install  pkgadd -R ... -n -a  (the real alternate-root install)
#     Gate 12  content-gate.sh      (pkgchk -R -c: per-file cksum)
#     Gate 11  pkgchk -R -a         (ownership attest, meaningful at euid 0)
# Then, once:
#     contents-fsck  (must report ZERO repairs)
#     pkginfo -R     (must list every installed package)
#     emit           (contents DB + etc/passwd + etc/group for the host
#                     canonical tree digest = altroot_attest.py)
#
# Parameters via env:
#   ENGINE  engine bin dir            (default /usr/apkg/bin)
#   SADM    sadm-helper bin dir       (informational; compiled-in)
#   ROOT    target -R root            (required; keep the path SHORT, <110c)
#   PKGDIR  dir of <pkg>-2.1.pkg      (required)
#   ADMIN   admin(4) file             (required)
#   SCRATCH scratch dir w/ headroom   (required; exported as TMPDIR)
#   GATEDIR dir with the gate scripts (default: dirname of this script)
#   EMIT    dir to write emitted DB   (default: $SCRATCH/emit)
#   PKGS    install order             (default: core bsd net text sysadm)
#
# Exit 0 = every gate + step passed; non-zero = first failure (logged).

ENGINE="${ENGINE:-/usr/apkg/bin}"
ROOT="${ROOT:?set ROOT}"
PKGDIR="${PKGDIR:?set PKGDIR}"
ADMIN="${ADMIN:?set ADMIN}"
SCRATCH="${SCRATCH:?set SCRATCH}"
GATEDIR="${GATEDIR:-`dirname $0`}"
EMIT="${EMIT:-$SCRATCH/emit}"
PKGS="${PKGS:-core bsd net text sysadm}"

PKGADD="$ENGINE/pkgadd"
PKGCHK="$ENGINE/pkgchk"
PKGINFO="$ENGINE/pkginfo"
FSCK="$ENGINE/contents-fsck"
export PKGCHK               # content-gate.sh honours it
TMPDIR="$SCRATCH"           # pkgadd temp image lands here (headroom!)
export TMPDIR               # SVR4 /bin/sh: `export VAR=val` is not valid

echo "=== altroot-acceptance: engine=$ENGINE root=$ROOT pkgs=[$PKGS] ==="
echo "euid check:"; id
fail() { echo "ACCEPTANCE-FAIL: $1"; exit 1; }

for pkg in $PKGS; do
	echo
	echo "########## $pkg ##########"
	pf="$PKGDIR/$pkg-2.1.pkg"
	[ -f "$pf" ] || fail "$pkg: missing package file $pf"

	echo "--- Gate 13 core-first-gate ($pkg) ---"
	sh "$GATEDIR/core-first-gate.sh" "$ROOT" "$pkg" || fail "$pkg: core-first-gate"

	echo "--- pkgadd -R ($pkg)  start: `date` ---"
	"$PKGADD" -R "$ROOT" -n -a "$ADMIN" -d "$pf" "$pkg"
	rc=$?
	echo "--- pkgadd -R ($pkg) rc=$rc  end: `date` ---"
	[ "$rc" = 0 ] || fail "$pkg: pkgadd rc=$rc"

	echo "--- Gate 12 content-gate ($pkg) ---"
	sh "$GATEDIR/content-gate.sh" "$ROOT" "$pkg" || fail "$pkg: content-gate"

	echo "--- Gate 11 ownership attest (pkgchk -R -a, euid 0) ($pkg) ---"
	"$PKGCHK" -R "$ROOT" -a "$pkg" || fail "$pkg: ownership attest (pkgchk -a)"
	echo "$pkg: ALL GATES PASSED"
done

echo
echo "########## contents-fsck (report mode: exit 0 clean / 1 findings) ##########"
CDB="$ROOT/var/sadm/install/contents"
"$FSCK" "$CDB" > "$SCRATCH/fsck.out" 2>&1
frc=$?
cat "$SCRATCH/fsck.out"
echo "contents-fsck rc=$frc"
[ "$frc" = 0 ] || fail "contents-fsck reported findings (rc=$frc: not clean, would need repair)"

echo
echo "########## pkginfo -R (must list all) ##########"
"$PKGINFO" -R "$ROOT" || fail "pkginfo -R"

echo
echo "########## emit contents DB + name service for host digest ##########"
mkdir -p "$EMIT"
cp "$CDB" "$EMIT/contents"
cp "$ROOT/etc/passwd" "$EMIT/passwd"
cp "$ROOT/etc/group" "$EMIT/group"
echo "emitted: $EMIT/{contents,passwd,group}"
ls -l "$EMIT"

echo
echo "ACCEPTANCE-OK: base set installed + all gates passed"
exit 0
