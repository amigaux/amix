#!/bin/sh
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# source-acceptance.sh - Wave 3: install the base set THROUGH the apkg
# SOURCE layer (-c <conf> selects http:// / a mounted /cdrom / raw:<dev>)
# into a FRESH, seeded alternate root, run the Wave-2 gate battery, and
# emit the installed DB for the host canonical-tree digest.  "Three
# sources, one digest": run this once per source with three fresh roots;
# altroot_attest.py on each emit must print the same digest.
#
# Box-side Bourne sh (Amix 2.1, pre-POSIX /bin/sh: backticks not $(...),
# `VAR=val; export VAR`).  euid 0 (ownership attest is only meaningful as
# root).  The engine (pkgadd/pkgrm/pkgchk/contents-fsck) is the box's
# Wave-2 engine and is NOT moved by -R - it runs from the box and installs
# INTO $ROOT.
#
# Env:
#   APKG    apkg client            (default /usr/apkg/bin/apkg)
#   CONF    apkg config (repo=...) (required; selects the source)
#   ROOT    fresh -R target root   (required; keep the path SHORT, <110c)
#   SCRATCH scratch dir + TMPDIR   (required; needs headroom)
#   ADMIN   admin(4) file          (required; informational - the config's
#                                   admin is what apkg actually passes)
#   ENGINE  engine bin dir         (default /usr/apkg/bin)
#   GATEDIR gate-script dir        (default: dirname of this script)
#   EMIT    emit dir               (default $SCRATCH/emit)
#   PKGS    install list           (default core bsd net text sysadm)
#
# Exit 0 = base set installed via the source layer + every gate passed,
# DB emitted; non-zero = first failure (logged).  The digest itself is
# computed on the HOST from the emitted files by altroot_attest.py.

APKG="${APKG:-/usr/apkg/bin/apkg}"
CONF="${CONF:?set CONF}"
ROOT="${ROOT:?set ROOT}"
SCRATCH="${SCRATCH:?set SCRATCH}"
ADMIN="${ADMIN:?set ADMIN}"
ENGINE="${ENGINE:-/usr/apkg/bin}"
GATEDIR="${GATEDIR:-`dirname $0`}"
EMIT="${EMIT:-$SCRATCH/emit}"
PKGS="${PKGS:-core bsd net text sysadm}"

PKGCHK="$ENGINE/pkgchk"
FSCK="$ENGINE/contents-fsck"
PKGINFO="$ENGINE/pkginfo"
export PKGCHK                 # content-gate.sh honours it
TMPDIR="$SCRATCH"            # pkgadd temp image lands here (headroom!)
export TMPDIR

echo "=== source-acceptance: conf=$CONF root=$ROOT pkgs=[$PKGS] ==="
echo "euid check:"; id
fail() { echo "ACCEPTANCE-FAIL: $1"; exit 1; }

# --- seed a FRESH target root (Wave-2 seed discipline) ---------------
echo "--- seed fresh root $ROOT ---"
rm -rf "$ROOT"
mkdir -p "$ROOT/etc" "$ROOT/var/sadm/pkg" "$ROOT/var/sadm/install" "$ROOT/tmp"
cp /etc/passwd "$ROOT/etc/passwd" || fail "seed passwd"
cp /etc/group  "$ROOT/etc/group"  || fail "seed group"
chmod 1777 "$ROOT/tmp"
mkdir -p "$SCRATCH" "$EMIT"
echo "seeded: `ls $ROOT/etc` + var/sadm dirs + tmp(1777)"

# --- Gate 13 core-first (core establishes the name service) ----------
echo "--- Gate 13 core-first-gate ---"
for pkg in $PKGS; do
	sh "$GATEDIR/core-first-gate.sh" "$ROOT" "$pkg" || fail "core-first-gate $pkg"
done

# --- apkg update + install THROUGH THE SOURCE LAYER ------------------
echo "--- apkg update ($CONF)  start: `date` ---"
"$APKG" -c "$CONF" update || fail "apkg update"
echo "--- apkg install $PKGS -R $ROOT  start: `date` ---"
"$APKG" -c "$CONF" -R "$ROOT" install $PKGS
rc=$?
echo "--- apkg install rc=$rc  end: `date` ---"
[ "$rc" = 0 ] || fail "apkg install rc=$rc"

# --- Gate 12 content gate (pkgchk -R -c: per-file size + cksum) ------
echo "--- Gate 12 content-gate ---"
sh "$GATEDIR/content-gate.sh" "$ROOT" $PKGS || fail "content-gate"

# --- Gate 11 ownership attest (pkgchk -R -a, meaningful at euid 0) ---
echo "--- Gate 11 ownership attest (pkgchk -R -a) ---"
for pkg in $PKGS; do
	"$PKGCHK" -R "$ROOT" -a "$pkg" || fail "ownership attest $pkg"
done

# --- contents-fsck: must report ZERO repairs ------------------------
echo "--- contents-fsck (0 findings expected) ---"
CDB="$ROOT/var/sadm/install/contents"
"$FSCK" "$CDB" > "$SCRATCH/fsck.out" 2>&1
frc=$?
cat "$SCRATCH/fsck.out"
[ "$frc" = 0 ] || fail "contents-fsck reported findings (rc=$frc)"

# --- pkginfo -R must list every package -----------------------------
echo "--- pkginfo -R ---"
"$PKGINFO" -R "$ROOT" || fail "pkginfo -R"

# --- emit DB + name service for the host canonical-tree digest ------
cp "$CDB" "$EMIT/contents" || fail "emit contents"
cp "$ROOT/etc/passwd" "$EMIT/passwd"
cp "$ROOT/etc/group"  "$EMIT/group"
echo "emitted: $EMIT/{contents,passwd,group}"
ls -l "$EMIT"

echo "ACCEPTANCE-OK: base set installed via the source layer + all gates passed"
exit 0
