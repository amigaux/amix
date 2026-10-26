#!/bin/sh
# mkprobes.sh -- S3-44's probe modules, built with one line's ABI kit
# (tests/bench/README.md, S3-44): t44intr and t44fill, for /tmp/s44
# on the box, loaded under development load.
#
# usage: mkprobes.sh KIT OUTDIR      (KIT: build/kit/<line>, `make kit`)
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
R=$(cd "$(dirname "$0")/../../.." && pwd)
S=$R/tests/bench/s3-44/src
K=$(cd "$1" && pwd) OUT=$2
[ -n "$OUT" ] && [ -f "$K/kit.conf" ] || { echo "usage: mkprobes.sh KIT OUTDIR" >&2; exit 2; }
. "$K/kit.conf"
mkdir -p "$OUT/s44" "$OUT/work"
OUT=$(cd "$OUT" && pwd)
for n in t44intr t44fill; do
	d=$OUT/work/$n
	rm -rf "$d" && mkdir -p "$d"
	cp "$S/$n.c" "$d/"
	cp "$S/$n.Master" "$d/Master"
	printf 'KIT = %s\nMODULE = %s\nOBJS = %s.o\ninclude $(KIT)/mk/module.mk\n' "$K" $n $n > "$d/Makefile"
	(cd "$d" && make > make.log 2>&1) || { echo "mkprobes: $n:" >&2; cat "$d/make.log" >&2; exit 1; }
	cp "$d/build/$LINE/mod.d/$n" "$OUT/s44/"
	echo "mkprobes: $n: $(grep '^modcheck' "$d/make.log" | tail -1)"
done
rm -rf "$OUT/work"
(cd "$OUT" && sha256sum s44/*)
