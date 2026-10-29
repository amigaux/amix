#!/bin/sh
# stagecore.sh -- the module core as shipped: core/upstream with
# core/series applied, into DIR (made afresh).  For the builds that use the
# core's own sources outside `make core` (modadmin for the box).
#
# usage: sh tools/stagecore.sh DIR
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
D=$1
[ -n "$D" ] || { echo "usage: stagecore.sh DIR" >&2; exit 2; }
rm -rf "${D:?}" && mkdir -p "$D"
cp -R "$R/core/upstream/." "$D/"
grep -v '^#' "$R/core/series" | while read p; do
	[ -n "$p" ] && patch -p1 -s -d "$D" < "$R/core/patches/$p"
done
