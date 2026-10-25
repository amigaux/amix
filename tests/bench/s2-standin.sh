#!/bin/sh
# s2-standin.sh -- a stand-in kernel package for the stage-2 rows, until the
# real kernel packages (docs/plan/stage-2.md S2-12) and apkg's catalog
# (S2-23) exist: the kernel and its kabi sidecar as the package would
# install them (docs/contracts/C2-3-packages.md), and the install record
# apkg would write (C2-2), so kbootset's gates 1 and 2 accept them.  The
# rows copy OUTDIR's tree onto the box's root.
#
# usage: s2-standin.sh KERNEL LINE ROOTKEYS ROOTFS BUILD OUTDIR
#   KERNEL    the static kernel (brel or ET_REL)
#   LINE      k30 or k46
#   ROOTKEYS  its built-in root controllers as match keys, comma-separated
#             (zorro:144b:01, mobo:a3000-wd, ...)
#   ROOTFS    its built-in root filesystems (ufs, s5), comma-separated
#   BUILD     its build id (uname -m)
# Writes OUTDIR/stand/<line>/{unix,kabi} and OUTDIR/var/apkg/kpkg/kernel-standin.
set -e
KERNEL=$1 LINE=$2 KEYS=$3 FS=$4 BUILD=$5 OUT=$6
sha() { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }
mkdir -p "$OUT/stand/$LINE" "$OUT/var/apkg/kpkg"
cp "$KERNEL" "$OUT/stand/$LINE/unix"
cat > "$OUT/stand/$LINE/kabi" <<EOF
kabi=static
family=standin
line=$LINE
pin=gcc-2.7.2.3-8949028
build=$BUILD
size=$(size "$OUT/stand/$LINE/unix")
sha256=$(sha "$OUT/stand/$LINE/unix")
loader-min=1
root=$KEYS
rootfs=$FS
EOF
cat > "$OUT/var/apkg/kpkg/kernel-standin" <<EOF
name kernel-standin
version 0.0.0
role kernel
line $LINE
kabi static
pin gcc-2.7.2.3-8949028
sha256 0000000000000000000000000000000000000000000000000000000000000000
source stand-in (tests/bench/s2-standin.sh)
installed ${SOURCE_DATE_EPOCH:-1761400000}
verified no
file /stand/$LINE/unix $(size "$OUT/stand/$LINE/unix") $(sha "$OUT/stand/$LINE/unix")
file /stand/$LINE/kabi $(size "$OUT/stand/$LINE/kabi") $(sha "$OUT/stand/$LINE/kabi")
EOF
echo "s2-standin: $OUT (copy onto the box's root)"
