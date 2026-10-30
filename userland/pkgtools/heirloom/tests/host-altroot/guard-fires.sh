#!/bin/bash
#
# guard-fires.sh - prove the fail-closed -R ownership guard ABORTS the
# package when an owner/group name cannot be resolved through the TARGET
# root's name service (libpkg/verify.c averify() -> set_ownerfail_hook,
# registered by pkginstall/main.c).  Companion to run.sh, which proves
# the RESOLVABLE path stays clean; this proves the UNRESOLVABLE path is
# fatal instead of silently installing a mis-owned object.
#
# Uses the PLAIN build-host/bin (no LD_PRELOAD): the name resolution
# chain is clgrnam(<root>/etc/group) -> getgrnam(host /etc/group), so a
# name absent from both the seeded root AND the host is genuinely
# unresolvable and must trip the guard.
#
#   cd heirloom && ./build-host.sh && ./tests/host-altroot/guard-fires.sh
#
# Exit 0 = guard behaved correctly (fatal on unresolvable, clean on
# resolvable).  Exit 1 = harness could not run.  Exit 2 = guard FAILED
# to fail closed (the regression this test guards against).
set -u

D="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$D/../.." && pwd)"
BIN="$TOP/build-host/bin"
OUT="${OUTDIR:-/tmp/guard-fires}"

[ -x "$BIN/pkgadd" ] || { echo "SKIP: $BIN/pkgadd not built - run ./build-host.sh"; exit 1; }

# A group/user name that must not exist in any real name service.
BADGRP="zznosuchg"
GOODGRP="other"

rm -rf "$OUT"; mkdir -p "$OUT/src/root/gtest" "$OUT/src/spool" "$OUT/src/out"
echo "guard probe" > "$OUT/src/root/gtest/f"

cat > "$OUT/src/pkginfo" <<'EOF'
PKG=GUARDP
NAME=Fail-closed -R ownership guard probe
ARCH=m68k
VERSION=1.0
CATEGORY=application
EOF

# The seeded target root only knows root/other - never $BADGRP.
mk_seed() {
	rm -rf "$1"; mkdir -p "$1/etc"
	printf 'root:x:0:1:0000:/:/sbin/sh\nother:x:1:1:/:\n' > "$1/etc/passwd"
	printf 'root::0:root\nother::1:\n' > "$1/etc/group"
}

cat > "$OUT/admin" <<'EOF'
mail=
instance=overwrite
partial=nocheck
runlevel=nocheck
idepend=nocheck
rdepend=nocheck
space=nocheck
setuid=nocheck
conflict=nocheck
action=nocheck
basedir=default
EOF

build_pkg() {	# $1 = group for the f file
	rm -rf "$OUT/src/spool"/* "$OUT/src/out"/* 2>/dev/null
	cat > "$OUT/src/prototype" <<EOF
i pkginfo=$OUT/src/pkginfo
d none /gtest 0755 root other
f none /gtest/f 0644 root $1
EOF
	"$BIN/pkgmk" -o -r "$OUT/src/root" -f "$OUT/src/prototype" \
		-d "$OUT/src/spool" GUARDP >"$OUT/pkgmk.log" 2>&1 || {
		echo "FAIL: pkgmk"; tail "$OUT/pkgmk.log"; exit 1; }
	"$BIN/pkgtrans" -s "$OUT/src/spool" "$OUT/src/out/g.pkg" GUARDP \
		>"$OUT/pkgtrans.log" 2>&1 || {
		echo "FAIL: pkgtrans"; tail "$OUT/pkgtrans.log"; exit 1; }
}

rc_bad=0
# ---- NEGATIVE: unresolvable group must ABORT (fatal, non-zero) --------
build_pkg "$BADGRP"
mk_seed "$OUT/rbad"
"$BIN/pkgadd" -R "$OUT/rbad" -n -a "$OUT/admin" \
	-d "$OUT/src/out/g.pkg" GUARDP >"$OUT/bad.log" 2>&1
neg_rc=$?
if [ "$neg_rc" -ne 0 ] && grep -q "fail-closed" "$OUT/bad.log"; then
	echo "NEGATIVE (group <$BADGRP> absent): pkgadd rc=$neg_rc + fail-closed msg  -> OK (aborted)"
else
	echo "NEGATIVE: pkgadd rc=$neg_rc but did NOT fail closed -- guard REGRESSED"
	echo "  ---- bad.log tail ----"; tail -8 "$OUT/bad.log"
	rc_bad=2
fi

# ---- POSITIVE control: resolvable group must NOT abort ----------------
build_pkg "$GOODGRP"
mk_seed "$OUT/rok"
"$BIN/pkgadd" -R "$OUT/rok" -n -a "$OUT/admin" \
	-d "$OUT/src/out/g.pkg" GUARDP >"$OUT/ok.log" 2>&1
pos_rc=$?
if [ "$pos_rc" -eq 0 ] || [ "$pos_rc" -eq 2 ]; then
	if grep -q "fail-closed" "$OUT/ok.log"; then
		echo "POSITIVE: fail-closed msg present on a RESOLVABLE name -- guard too aggressive"
		rc_bad=2
	else
		echo "POSITIVE (group <$GOODGRP> present):  pkgadd rc=$pos_rc, no abort  -> OK (installed)"
	fi
else
	echo "POSITIVE: resolvable install rc=$pos_rc (unexpected)"
	echo "  ---- ok.log tail ----"; tail -8 "$OUT/ok.log"
	rc_bad=2
fi

if [ "$rc_bad" = 2 ]; then
	echo "RESULT: guard did NOT behave correctly - see logs in $OUT"
	exit 2
fi
echo "RESULT: fail-closed -R ownership guard OK (fatal on unresolvable, clean on resolvable)."
exit 0
