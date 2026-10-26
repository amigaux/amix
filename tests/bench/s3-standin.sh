#!/bin/sh
# s3-standin.sh -- a stand-in package for a stage-3 module kernel, until the
# real kernel packages carry one (docs/plan/stage-3.md S3-22): the kernel
# and the sidecar its build wrote (C2-3 version 5, C3-3 §3), as the package
# would install them, and the install record apkg would write (C2-2), so
# kbootset's gates 1 and 2 accept them.  The boot rows of S3-20 and S3-21
# copy OUTDIR's tree onto the box's root (tests/bench/README.md, stage 3).
#
# usage: s3-standin.sh KERNEL SIDECAR OUTDIR [ROOTREC]
#   KERNEL    the module kernel as shipped (ET_REL on k46, brel on k30)
#   SIDECAR   its sidecar from the kernel build: kabi=, line=, pin=,
#             loader-min=2, ident=, arena=, root=, rootfs= (and bss= for a
#             brel); size= and sha256= are written here from KERNEL
#   ROOTREC   the vehicle's manifest root record ("sd id=144b0100
#             base=00000000 unit=6 slice=1"); with it, the two specs of the
#             loader-1 rows are written too (`kbootset commit --spec`, which
#             runs no gates):
#               l9.spec       the generation as kbootset build composes it
#                             (loader-min 2, arena, ident): a version-1
#                             loader refuses it with L9
#               noarena.spec  the same kernel as a version-1 generation (no
#                             arena, no ident): the core finds no arena
# Writes OUTDIR/stand/<line>/{unix,kabi}, OUTDIR/var/apkg/kpkg/kernel-s3standin
# and, with ROOTREC, OUTDIR/l9.spec and OUTDIR/noarena.spec.
set -e
KERNEL=$1 SIDECAR=$2 OUT=$3 ROOTREC=$4
[ -n "$OUT" ] || { echo "usage: s3-standin.sh KERNEL SIDECAR OUTDIR [ROOTREC]" >&2; exit 2; }
sha() { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }
key() { sed -n "s/^$1=//p" "$SIDECAR" | head -1; }
LINE=$(key line) KABI=$(key kabi) PIN=$(key pin)
for k in line kabi pin ident arena root rootfs; do
	[ -n "$(key $k)" ] || { echo "s3-standin: the sidecar has no $k=" >&2; exit 1; }
done
mkdir -p "$OUT/stand/$LINE" "$OUT/var/apkg/kpkg"
cp "$KERNEL" "$OUT/stand/$LINE/unix"
{
	grep -v '^size=\|^sha256=' "$SIDECAR"
	echo "size=$(size "$OUT/stand/$LINE/unix")"
	echo "sha256=$(sha "$OUT/stand/$LINE/unix")"
} > "$OUT/stand/$LINE/kabi"
cat > "$OUT/var/apkg/kpkg/kernel-s3standin" <<EOF
name kernel-s3standin
version 0.0.0
role kernel
line $LINE
kabi $KABI
pin $PIN
sha256 0000000000000000000000000000000000000000000000000000000000000000
source stand-in (tests/bench/s3-standin.sh)
installed ${SOURCE_DATE_EPOCH:-1761400000}
verified no
file /stand/$LINE/unix $(size "$OUT/stand/$LINE/unix") $(sha "$OUT/stand/$LINE/unix")
file /stand/$LINE/kabi $(size "$OUT/stand/$LINE/kabi") $(sha "$OUT/stand/$LINE/kabi")
EOF
if [ -n "$ROOTREC" ]; then
	BSS=$(key bss)
	KLINE="kernel unix /stand/$LINE/unix${BSS:+ bss=$BSS}"
	FS=$(key rootfs | cut -d, -f1)
	printf 'line %s\nkabi %s\nloader-min 2\nrootfs %s\nroot %s\narena %s\nident %s\n%s\n' \
		"$LINE" "$KABI" "$FS" "$ROOTREC" "$(key arena)" "$(key ident)" "$KLINE" > "$OUT/l9.spec"
	printf 'line %s\nkabi %s\nloader-min 1\nrootfs %s\nroot %s\n%s\n' \
		"$LINE" "$KABI" "$FS" "$ROOTREC" "$KLINE" > "$OUT/noarena.spec"
fi
echo "s3-standin: $OUT (copy onto the box's root)"
