#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# move-1.0-tree.sh -- move the 1.0 package tree from the repository's
# docroot into its own release tree, once.
#
#   move-1.0-tree.sh [--apply | --remove-root] <docroot>
#
# The repository has one tree per release: <docroot>/<release>/catalog,
# catalog.md5 and pkgs/ (docs/design.md section 5).  Until now 1.0 was
# published at the docroot itself (<docroot>/catalog, catalog.md5, pkgs/).
# This script puts it at <docroot>/1.0/.  It runs where the docroot is a
# local directory, i.e. on the repository host, for example:
#
#   ssh <host> 'bash -s -- <docroot>'           < move-1.0-tree.sh   # plan
#   ssh <host> 'bash -s -- --apply <docroot>'   < move-1.0-tree.sh   # copy
#   ssh <host> 'bash -s -- --remove-root <docroot>' < move-1.0-tree.sh
#
# Three steps, each run on its own:
#
#   (no option)    the plan, a dry run: checks the root tree and prints
#                  what --apply would copy (rsync -n) and what
#                  --remove-root would remove.  Writes nothing.
#   --apply        copies (never moves) catalog, catalog.md5 and pkgs/ into
#                  <docroot>/1.0/, then verifies the copy: catalog.md5
#                  matches, and every package the catalog names is in
#                  1.0/pkgs/ with the catalog's md5.  The root tree stays,
#                  so a client still fetching from the root keeps working.
#                  Run it again and it changes nothing.
#   --remove-root  verifies <docroot>/1.0/ again and only then removes the
#                  root's catalog, catalog.md5 and pkgs/.  Run it after the
#                  site deploy is live and http://<host>/1.0/catalog serves
#                  the copy.
#
# Deployed 1.0 boxes (apkg 0.2.x) have repo=http://pkg.amigaux.org, the
# root.  After --remove-root they find nothing there unless the web server
# answers the old paths with a redirect into the 1.0 tree:
#
#   /catalog      -> 301 /1.0/catalog
#   /catalog.md5  -> 301 /1.0/catalog.md5
#   /pkgs/<path>  -> 301 /1.0/pkgs/<path>
#
# apkg follows one 301/302 hop by default (apkg.conf redirects=1).  That
# redirect belongs to the site deploy and should be live before
# --remove-root.  Anything else in the docroot (other release trees, an
# index page) is never touched.
set -euo pipefail

usage() {
    echo "usage: $0 [--apply | --remove-root] <docroot>" >&2
    exit 1
}

MODE=plan
DOCROOT=""
for arg in "$@"; do
    case "$arg" in
        --apply)       MODE=apply ;;
        --remove-root) MODE=remove ;;
        -h|--help)     usage ;;
        -*)            echo "move-1.0: unknown option: $arg" >&2; usage ;;
        *)             [[ -n "$DOCROOT" ]] && usage; DOCROOT="$arg" ;;
    esac
done
[[ -n "$DOCROOT" ]] || usage
[[ -d "${DOCROOT:?}" ]] || { echo "move-1.0: $DOCROOT: not a directory" >&2; exit 1; }
D="$(cd "${DOCROOT:?}" && pwd)"
T="${D:?}/1.0"

# verify <tree>: catalog.md5 matches, and every catalogued package is in
# <tree>/pkgs/ with the catalog's md5.  Prints a summary; nonzero on any miss.
verify() {
    local tree="$1" n=0 bad=0 file md5 got
    if ! (cd "${tree:?}" && md5sum -c catalog.md5 >/dev/null 2>&1); then
        echo "move-1.0: $tree/catalog does not match its catalog.md5" >&2
        return 1
    fi
    while IFS='|' read -r _name _ver _inst file md5 _rest; do
        n=$((n + 1))
        if [[ ! -f "$tree/pkgs/$file" ]]; then
            echo "move-1.0: missing $tree/pkgs/$file" >&2; bad=$((bad + 1)); continue
        fi
        got="$(md5sum < "$tree/pkgs/$file" | cut -d' ' -f1)"
        if [[ "$got" != "$md5" ]]; then
            echo "move-1.0: $tree/pkgs/$file md5 $got, catalog says $md5" >&2
            bad=$((bad + 1))
        fi
    done < <(grep -v '^#' "$tree/catalog")
    echo "move-1.0: $tree: catalog.md5 OK, $n package(s) checked, $bad bad"
    if [[ $n -eq 0 ]]; then
        echo "move-1.0: $tree/catalog names no package: NOTHING INSPECTED" >&2
        return 1
    fi
    [[ $bad -eq 0 ]]
}

case $MODE in
plan|apply)
    for f in catalog catalog.md5; do
        [[ -f "$D/$f" ]] || { echo "move-1.0: no $D/$f: nothing to move" >&2; exit 1; }
    done
    [[ -d "$D/pkgs" ]] || { echo "move-1.0: no $D/pkgs/: nothing to move" >&2; exit 1; }
    echo "== the root tree (source)"
    verify "$D"
    if [[ -f "$T/catalog" ]] && ! cmp -s "$D/catalog" "$T/catalog"; then
        echo "move-1.0: $T/catalog exists and differs from the root's; refusing" >&2
        exit 1
    fi
    ;;
remove)
    [[ -f "$T/catalog" ]] || { echo "move-1.0: no $T/catalog: run --apply first" >&2; exit 1; }
    ;;
esac

case $MODE in
plan)
    echo "== --apply would copy into $T/ (dry run)"
    echo "   catalog, catalog.md5"
    rsync -an --itemize-changes "${D:?}/pkgs/" "${T:?}/pkgs/"
    echo "== --remove-root would then remove"
    echo "   $D/catalog"
    echo "   $D/catalog.md5"
    echo "   $D/pkgs/ ($(find "$D/pkgs" -type f | wc -l) file(s))"
    echo "move-1.0: plan only; nothing was written"
    ;;
apply)
    mkdir -p "${T:?}/pkgs"
    rsync -a "${D:?}/pkgs/" "${T:?}/pkgs/"
    cp -p "${D:?}/catalog" "${D:?}/catalog.md5" "${T:?}/"
    echo "== the 1.0 tree (copy)"
    verify "$T" || { echo "move-1.0: the copy does not verify; the root tree is untouched" >&2; exit 1; }
    echo "move-1.0: copied; the root tree is untouched.  Next: the site deploy (with"
    echo "          the redirects above), check http://<host>/1.0/catalog, then"
    echo "          --remove-root."
    ;;
remove)
    echo "== the 1.0 tree (before removing the root's)"
    verify "$T" || { echo "move-1.0: $T does not verify; removing nothing" >&2; exit 1; }
    rm -f -- "${D:?}/catalog" "${D:?}/catalog.md5"
    rm -rf -- "${D:?}/pkgs"
    echo "move-1.0: removed $D/catalog, $D/catalog.md5 and $D/pkgs/"
    ;;
esac
