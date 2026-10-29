#!/bin/sh
# s3-modpkg.sh -- a stand-in module package (docs/contracts/C3-5-module-
# member.md section 1), until amix-packages makes the real ones (S3-22):
# the module object as the package installs it and the apkg record, so
# kbootset build composes it into the next generation (gate 1).  The rows
# copy OUTDIR's tree onto the box's root (tests/bench/README.md, S3-B5).
#
# usage: s3-modpkg.sh MODULE LINE OUTDIR [modreg-line ...]
#   MODULE   the module object built with the ABI kit (build/<line>/mod.d/<name>)
#   LINE     k30 or k46
#   modreg-line  written to etc/conf/modreg.d/<name> ("param intr=6", "disable")
#   KABI     the record's kabi (default <line>.1.0; k46.1.1 for a module
#            built with the stage-4 kit)
# Writes OUTDIR/etc/conf/mod.d/<name>, OUTDIR/var/apkg/kpkg/mod-<name> and,
# with modreg lines, OUTDIR/etc/conf/modreg.d/<name>.
set -e
M=$1 LINE=$2 OUT=$3
[ -n "$OUT" ] || { echo "usage: s3-modpkg.sh MODULE LINE OUTDIR [modreg-line ...]" >&2; exit 2; }
shift 3
N=$(basename "$M")
sha() { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }
mkdir -p "$OUT/etc/conf/mod.d" "$OUT/var/apkg/kpkg"
cp "$M" "$OUT/etc/conf/mod.d/$N"
files="file /etc/conf/mod.d/$N $(size "$M") $(sha "$M")"
if [ $# -gt 0 ]; then
	mkdir -p "$OUT/etc/conf/modreg.d"
	printf '%s\n' "$@" > "$OUT/etc/conf/modreg.d/$N"
	files="$files
file /etc/conf/modreg.d/$N $(size "$OUT/etc/conf/modreg.d/$N") $(sha "$OUT/etc/conf/modreg.d/$N")"
fi
cat > "$OUT/var/apkg/kpkg/mod-$N" <<EOF2
name mod-$N
version 0.0.0
role module
line $LINE
kabi ${KABI:-$LINE.1.0}
pin gcc-2.7.2.3-8949028
sha256 0000000000000000000000000000000000000000000000000000000000000000
source stand-in (tests/bench/s3-modpkg.sh)
installed ${SOURCE_DATE_EPOCH:-1761400000}
verified no
$files
EOF2
echo "s3-modpkg: $OUT: $N for $LINE (copy onto the box's root)"
