#!/usr/bin/env bash
# publish.sh -- push a staged apkg repo (catalog + packages) to the repo host.
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Usage: publish.sh [--dry-run|-n] <stagingdir>
#
#   <stagingdir> must contain: catalog, catalog.md5 (from gen-catalog.py)
#                and the *.pkg / *.pkg.Z files the catalog references.
#
# Layout pushed (docs/design.md section 5, categorized subdirectories):
#   $PUBLISH_DEST/catalog, catalog.md5     served as <repo>/catalog
#   $PUBLISH_DEST/pkgs/**/*.pkg[.Z]        served as <repo>/pkgs/<filename>
#                                          (<filename> may contain '/':
#                                          stock/, base/, test/, ...)
#
# Environment:
#   PUBLISH_DEST   rsync destination, REQUIRED, e.g. <user>@<host>:<docroot>
#                  (rsync over ssh as the invoking user; the docroot should be
#                  owned by that user, so no root is involved)
#   PUBLISH_URL    HTTP base for verify   (default http://pkg.amigaux.org)
#
# There is deliberately no default destination: publishing mutates a public
# host, so the caller names it every time.  The repository moved to the
# canonical public host pkg.amigaux.org on 2026-09-15; see NOTES.md.
#
# --dry-run maps to rsync -n: nothing is written, and the post-publish HTTP
# verification (curl of $PUBLISH_URL/catalog + md5 compare) is skipped.

set -euo pipefail

DEST="${PUBLISH_DEST:?set PUBLISH_DEST=<user>@<host>:<docroot>}"
URL="${PUBLISH_URL:-http://pkg.amigaux.org}"

usage() {
    echo "usage: $0 [--dry-run|-n] <stagingdir>" >&2
    exit 1
}

DRY=0
STAGING=""
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY=1 ;;
        -h|--help)    usage ;;
        -*)           echo "publish: unknown option: $arg" >&2; usage ;;
        *)            [[ -n "$STAGING" ]] && usage; STAGING="$arg" ;;
    esac
done
[[ -n "$STAGING" ]] || usage

[[ -d "$STAGING" ]] || { echo "publish: $STAGING: not a directory" >&2; exit 1; }
[[ -f "$STAGING/catalog" ]] || {
    echo "publish: $STAGING/catalog missing -- run gen-catalog.py first" >&2
    exit 1
}
[[ -f "$STAGING/catalog.md5" ]] || {
    echo "publish: $STAGING/catalog.md5 missing -- run gen-catalog.py first" >&2
    exit 1
}

# Refuse to publish a catalog that does not match its own checksum file
# (stale gen-catalog output or a hand-edited catalog).
if ! (cd "$STAGING" && md5sum -c catalog.md5 >/dev/null 2>&1); then
    echo "publish: catalog.md5 does not match catalog in $STAGING" >&2
    exit 1
fi

# ---- licensing gate (W6-K section 3): refuse OUR private kernel packages ----
# A package whose pkginfo carries the kernel-package markers (KSUM_R/BOOT2_SHA)
# is one of the minted KERNBENCH/KERNZ3660 packages -- PRIVATE-only (their
# /stand/unix + /stand/boot2.boot payload is proprietary-derived).  This DEST
# is redistributable -- and since 2026-09-15 it is PUBLICLY reachable, not
# LAN-only -- so it must never carry one.  This is the load-bearing
# gate: publish rsyncs every *.pkg in staging (not just cataloged ones), so a
# hand-added or stale-catalog kernel package would otherwise reach the host.
# The gate keys on the pkginfo markers, NOT on pathnames, so STOCK packages
# (core) that ship /stand members as original content publish normally.
# Delegated to gen-catalog.py --scan-private so "what is a private kernel
# package" is defined in exactly one place.  Fail closed (no --force): if the
# scan cannot even run, refuse.
SELFDIR="$(cd "$(dirname "$0")" && pwd)"
GEN="$SELFDIR/gen-catalog.py"
SCAN_RC=0
python3 "$GEN" --scan-private "$STAGING" || SCAN_RC=$?
if [[ $SCAN_RC -eq 3 ]]; then
    echo "publish: REFUSING to publish $STAGING -- it carries proprietary" >&2
    echo "         kernel/boot2 payload (PRIVATE-only; W6-K section 3). Such" >&2
    echo "         packages may NEVER reach a redistributable/off-LAN repo." >&2
    echo "         There is no --force: build them into a private staging" >&2
    echo "         area (build-packages.sh --kernbench/--kernz3660), not here." >&2
    exit 4
elif [[ $SCAN_RC -ne 0 ]]; then
    echo "publish: REFUSING -- private-content scan could not run (rc=$SCAN_RC)." >&2
    echo "         Failing closed rather than publishing unverified content." >&2
    exit 4
fi

# ---- licensing gate 2: what is INSIDE a payload --------------------------
# The scan above answers "is this one of OUR private kernel packages".  It
# does NOT answer "what does this package's payload carry", and on 2026-09-16
# that gap let amixbench-1.2 -- whose `whet` statically embedded the stock
# SVR4 libm.a -- through every automated check; a human reading the recipe
# caught it.  Two different properties, so two separate gates rather than
# one overloaded one.
#
# REFUSE (rc 2) is a Kickstart ROM image in the payload -- not covered by the
# Amix permission -- and is fatal here, for the same reason the kernel gate
# is: this DEST is public and the mistake is not retractable once fetched.
# Embedded stock Amix object code (libm) is NOT refused since 2026-10-30
# (owner: ports link the stock libm.a; the permission covers all of Amix,
# ruling 2026-10-29): the gate prints an "embeds" line per binary so the
# publish log shows it.  UNKNOWN (a stripped binary, whose symbol table the
# test cannot read) is NOT fatal -- most of the add-on set is stripped -- but
# it prints, because "not inspected" must never read as "clean".
echo "publish: payload licence gate"
PLG="$SELFDIR/payload-licence-gate.py"
if [[ -f "$PLG" ]]; then
    PLG_RC=0
    python3 "$PLG" "$STAGING" || PLG_RC=$?
    if [[ $PLG_RC -eq 2 ]]; then
        echo "publish: REFUSING to publish $STAGING -- a payload carries" >&2
        echo "         content the public repo may not ship (a Kickstart ROM;" >&2
        echo "         see above). Fix the mint; there is no --force." >&2
        exit 5
    elif [[ $PLG_RC -ne 0 ]]; then
        echo "publish: REFUSING -- payload licence gate could not run (rc=$PLG_RC)." >&2
        exit 5
    fi
else
    echo "publish: WARNING: $PLG missing -- payload NOT screened" >&2
fi

RSYNC_OPTS=(-av)
if [[ $DRY -eq 1 ]]; then
    RSYNC_OPTS+=(-n)
    echo "publish: DRY RUN -- no files will be written"
fi

# Local destination dirs must exist before rsync (skip for remote host:path
# destinations and for dry runs).
if [[ $DRY -eq 0 && "$DEST" != *:* ]]; then
    mkdir -p "$DEST/pkgs"
fi

# Packages first, catalog second: a client never sees a catalog that
# references packages which are not uploaded yet.  --delete-excluded prunes
# packages that were removed from staging (and any stray non-pkg files).
# Filters: '*/' lets rsync descend into the categorized subdirectories
# (stock/, base/, test/, ...) with the directory structure preserved;
# --prune-empty-dirs keeps package-less directories off the server.
echo "publish: syncing packages -> $DEST/pkgs/"
rsync "${RSYNC_OPTS[@]}" --delete --delete-excluded --prune-empty-dirs \
    --include='*/' --include='*.pkg' --include='*.pkg.Z' --exclude='*' \
    "$STAGING/" "$DEST/pkgs/"

echo "publish: syncing catalog -> $DEST/"
rsync "${RSYNC_OPTS[@]}" "$STAGING/catalog" "$STAGING/catalog.md5" "$DEST/"

if [[ $DRY -eq 1 ]]; then
    echo "publish: dry run complete -- skipping HTTP verify of $URL/catalog"
    exit 0
fi

# ------------------------------------------------------------- verify ---
# Fetch the published catalog back over plain HTTP (the same path the apkg
# client uses) and compare checksums against the staged copy.
echo "publish: verifying $URL/catalog"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
if ! curl -fsS --max-time 30 "$URL/catalog" -o "$TMP"; then
    echo "publish: ERROR: could not fetch $URL/catalog" >&2
    exit 2
fi
LOCAL_MD5="$(md5sum < "$STAGING/catalog" | cut -d' ' -f1)"
REMOTE_MD5="$(md5sum < "$TMP" | cut -d' ' -f1)"
if [[ "$LOCAL_MD5" != "$REMOTE_MD5" ]]; then
    echo "publish: ERROR: served catalog md5 $REMOTE_MD5 != local $LOCAL_MD5" >&2
    exit 3
fi
echo "publish: OK -- served catalog matches staging (md5 $LOCAL_MD5)"
