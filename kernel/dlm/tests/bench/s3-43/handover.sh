#!/bin/sh
# handover.sh -- one line's S3-43 inputs for the Bench, in one directory
# (tests/bench/README.md, S3-43): the module set (mkset.sh), the loader
# rows (boot2.sh), and a list of what is there with SHA-256s.
#
# usage: handover.sh LINE KERNEL SIDECAR ETREL "ROOTREC" SLICEBYTES OUTDIR
#   LINE        k30 or k46 (the kit is build/kit/LINE)
#   KERNEL      the kernel as shipped, SIDECAR its sidecar
#   ETREL       the kernel as ET_REL (k46: KERNEL itself; k30: the .etrel)
#   ROOTREC     the vehicle's root record, SLICEBYTES its boot slice
# Writes OUTDIR/tree/, OUTDIR/s43/, OUTDIR/verdicts.txt, OUTDIR/l14.spec,
# OUTDIR/l5.img, OUTDIR/boot2/ (boot2.sh's inputs) and OUTDIR/SHA256SUMS.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
R=$(cd "$(dirname "$0")/../../.." && pwd)
LINE=$1 KERNEL=$2 SIDECAR=$3 ETREL=$4 ROOTREC=$5 SLICE=$6 OUT=$7
[ -n "$OUT" ] || { echo "usage: handover.sh LINE KERNEL SIDECAR ETREL ROOTREC SLICEBYTES OUTDIR" >&2; exit 2; }
rm -rf "$OUT" && mkdir -p "$OUT"
KERNEL=$ETREL sh "$R/tests/bench/s3-43/mkset.sh" "$R/build/kit/$LINE" "$OUT"
rm -rf "$OUT/work"
sh "$R/tests/bench/s3-43/boot2.sh" "$KERNEL" "$SIDECAR" "$OUT/boot2" "$ROOTREC" "$SLICE"
mv "$OUT/boot2/l14.spec" "$OUT/boot2/l5.img" "$OUT/"
(cd "$OUT" && find tree s43 verdicts.txt l14.spec l5.img -type f | sort | xargs sha256sum) > "$OUT/SHA256SUMS"
echo "handover: $OUT ($LINE): $(wc -l < "$OUT/SHA256SUMS") files, l5.img $SLICE bytes"
