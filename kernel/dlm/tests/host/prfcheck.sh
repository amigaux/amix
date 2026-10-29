#!/bin/sh
# prfcheck.sh -- the module core as shipped (core/upstream + core/series)
# and core/plat: kernel-side printf formats only %d, %x, %s (tools/prfcheck.py).
# The host and user-space sources (tools/, test/, libmod/, modadmin.c) are
# not checked: they print through a libc.
set -e
B=${B:-build}
S=$B/prfcheck
rm -rf "$S" && mkdir -p "$S"
cp -R core/upstream/. "$S/"
grep -v '^#' core/series | while read p; do
	[ -n "$p" ] && patch -p1 -s -d "$S" < "core/patches/$p"
done
python3 tools/prfcheck.py "$S"/dlm_*.c "$S"/dlmconf.c core/plat/*.c core/plat/*/*.c
echo "prfcheck: kernel-side printf formats ok"
