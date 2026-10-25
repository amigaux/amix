#!/bin/sh
# ld-rows.sh -- vehicles and expected outcomes for the loader's write rows
# (M-LD4, docs/plan/stage-1.md S1-22) and menu rows (M-LD5, S1-21).
#
# Each vehicle is a copy of a proven loader vehicle (a disk image whose
# UNI\0 boot slice already holds a store, rows N19-N26) with that store
# rewritten in place by mkstore: same slice, same kernel, different
# generations and control state.  For the write rows, axsim then plays the
# loader's own selection and write rules over a copy for the row's number
# of boots; its output is the expected serial sequence, and lsstore of that
# copy is the expected state of the slot image after the lifecycle cell.
# The menu rows' input schedules and expected lines are in tests/bench/README.md.
#
# usage: ld-rows.sh SRC.hdf OFFSET SIZE KERNEL LINE OUTDIR
#   SRC.hdf  a proven vehicle (read only)
#   OFFSET   the boot slice's byte offset, SIZE its size (from the
#            vehicle's .build.txt: mkstore -p / -s)
#   KERNEL   the 1.0 static kernel the vehicle boots (its .kernel file)
#   LINE     k30 or k46
# Writes OUTDIR/<row>.hdf, <row>.spec*, <row>.expected for rows W1-W3 and M.
# Run from the repository root after `make tools build/axsim boot1 boot2`.
set -e
SRC=$1 OFF=$2 SIZE=$3 KERNEL=$4 LINE=$5 OUT=$6
B=${B:-build}
mkdir -p "$OUT"

spec() {	# spec FILE ID STATE
	cat > "$1" <<SPEC
generation $2
state $3
line $LINE
rootfs ufs
kernel unix $KERNEL z=deflate
SPEC
}

# row NAME BOOTS MKSTORE-OPTIONS SPEC...
row() {
	name=$1 boots=$2 opts=$3
	shift 3
	cp "$SRC" "$OUT/$name.hdf"
	$B/mkstore -o "$OUT/$name.hdf" -p "$OFF" -s "$SIZE" -1 $B/boot1.img -2 $B/boot2.bin \
		$opts "$@" > /dev/null
	$B/lsstore "$OUT/$name.hdf" "$OFF" > "$OUT/$name.before"
	{
		echo "# $name: the vehicle as built"
		sed 's/^/#   /' "$OUT/$name.before"
		if [ "$boots" -gt 0 ]; then
			cp "$OUT/$name.hdf" "$OUT/$name.sim"
			echo "# expected serial lines over $boots boots (axsim)"
			$B/axsim "$OUT/$name.sim" "$OFF" "$boots"
			echo "# expected store after the cell (lsstore of the slot image)"
			$B/lsstore "$OUT/$name.sim" "$OFF" | sed 's/^/#   /'
			rm -f "$OUT/$name.sim"
		fi
	} > "$OUT/$name.expected"
	echo "$name: $OUT/$name.hdf ($boots boots)"
}

# W1 try-once: generation 2 on trial, 1 good and default.  Boot 1 records
# the attempt and boots 2; boot 2 finds 2 not marked good (a 1.0 kernel
# never marks it), marks it bad (L8) and boots 1.
spec "$OUT/W1.spec1" 1 good
spec "$OUT/W1.spec2" 2 trial
row W1 2 "-d 1" "$OUT/W1.spec1" "$OUT/W1.spec2"

# W2 one-shot: two good generations, default 2, a request for 1.  Boot 1
# clears the request and boots 1; boot 2 boots the default 2.
spec "$OUT/W2.spec1" 1 good
spec "$OUT/W2.spec2" 2 good
row W2 2 "-d 2 -n 1" "$OUT/W2.spec1" "$OUT/W2.spec2"

# W3 loader trial: the primary boot2 on trial, the same boot2 as the
# previous loader.  Boot 1: boot1 records the start in the tally block and
# runs the primary; boot 2: the start is recorded and nothing marked the
# loader good, so boot1 runs the secondary and boot2 prints B4.
spec "$OUT/W3.spec1" 1 good
row W3 2 "-b $B/boot2.bin -T" "$OUT/W3.spec1"

# M (menu rows, one vehicle): two good generations, default 2, a 60 s menu
# window so the schedule's first event lands in it whatever the boot time.
spec "$OUT/M.spec1" 1 good
spec "$OUT/M.spec2" 2 good
row M 0 "-d 2 -m 600" "$OUT/M.spec1" "$OUT/M.spec2"
