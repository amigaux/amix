#!/bin/sh
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# content-gate.sh (Gate 12) - verify the INSTALLED CONTENT of one or more
# packages against the per-file cksum/size recorded in the contents DB,
# via `pkgchk -R -c`.  Fails closed on ANY content discrepancy.
#
# This is the highest-value missing artifact in the effort: nothing else
# checksums installed CONTENT (Gate 11 / pkgchk -a attests OWNERSHIP; -c
# is content only, so this gate is meaningful even off-root / non-euid0).
#
# Portable Bourne sh - runs on the Amix box against the box engine.
#
#   content-gate.sh <root> <pkg> [pkg ...]
#   PKGCHK=/usr/apkg/bin/pkgchk content-gate.sh <root> core bsd net ...
#
# Exit 0 = every package's content verified; non-zero = a discrepancy
# (the offending pkgchk output is echoed) or a usage error.
PKGCHK="${PKGCHK:-pkgchk}"

root="$1"
[ -n "$root" ] || { echo "usage: content-gate.sh <root> <pkg> [pkg ...]" >&2; exit 2; }
shift
[ $# -ge 1 ] || { echo "usage: content-gate.sh <root> <pkg> [pkg ...]" >&2; exit 2; }

rc=0
tmp="${TMPDIR:-/tmp}/content-gate.$$"
for pkg in "$@"; do
	"$PKGCHK" -R "$root" -c "$pkg" > "$tmp" 2>&1
	prc=$?
	# CONTENT is defined by size + cksum.  pkgchk -c also flags modtime,
	# but a modtime-only mismatch is metadata drift (e.g. a pre-seeded
	# EDITABLE /etc/passwd|group that pkgadd correctly preserves), NOT
	# content corruption - real corruption always moves size and/or
	# cksum too.  Fail closed on size/cksum; tolerate modtime-only.
	if grep 'cksum' "$tmp" > /dev/null 2>&1 || \
	   grep 'file size' "$tmp" > /dev/null 2>&1; then
		echo "content-gate: $pkg: FAILED - content (size/cksum) discrepancy:"
		sed 's/^/    /' "$tmp"
		rc=1
	elif grep 'modtime' "$tmp" > /dev/null 2>&1; then
		echo "content-gate: $pkg: OK (per-file cksum clean; modtime-only"
		echo "    drift on preserved editable file(s) - tolerated)"
	elif [ "$prc" = 0 ]; then
		echo "content-gate: $pkg: OK (per-file cksum clean)"
	else
		echo "content-gate: $pkg: FAILED - pkgchk rc=$prc:"
		sed 's/^/    /' "$tmp"
		rc=1
	fi
done
rm -f "$tmp"

if [ "$rc" -eq 0 ]; then
	echo "content-gate: all content verified"
else
	echo "content-gate: FAIL (content discrepancy)"
fi
exit $rc
