#!/bin/sh
# kbootset-smoke.sh -- the box build of kbootset on an Amix box, against a
# store in an image file (docs/plan/stage-2.md S2-07).  Bourne shell, for
# the box's /bin/sh.  Run in a directory holding kbootset (build/box/),
# boot1.img, boot2.bin and unix (any kernel-sized file).
#
# usage: sh kbootset-smoke.sh            writes kb.img and smoke.log here
#
# Every step prints its exit status.  tests/bench/kbootset-smoke-host.sh
# runs the same steps with the host build on the same files: the two
# kb.img must be byte-identical (SOURCE_DATE_EPOCH fixes the times), and
# the two logs equal except for the hold step's kill.
SOURCE_DATE_EPOCH=1761400000
export SOURCE_DATE_EPOCH
KB=${KB:-./kbootset}
J=kb.journal
rm -f kb.img $J smoke.log
run() {
	echo "> $*" >> smoke.log
	"$@" >> smoke.log 2>&1
	echo "rc=$?" >> smoke.log
}
echo "line k46" > g.spec
echo "rootfs ufs" >> g.spec
echo "kernel unix unix" >> g.spec
dd if=/dev/zero of=kb.img bs=1024 count=8256 2>/dev/null
run $KB --image kb.img --offset 65536 create 8388608 boot2.bin --boot1 boot1.img
run $KB --image kb.img --offset 65536 --journal $J commit --spec g.spec
run $KB --image kb.img --offset 65536 --journal $J commit --spec g.spec
run $KB --image kb.img --offset 65536 mark-good --booted 2
run $KB --image kb.img --offset 65536 commit --spec g.spec
run $KB --image kb.img --offset 65536 rollback
run $KB --image kb.img --offset 65536 mark-bad 1
run $KB --image kb.img --offset 65536 next previous
# a commit held before step 4 and killed: generation 4 must not appear
echo "> KBOOTSET_HOLD=4 commit (killed)" >> smoke.log
KBOOTSET_HOLD=4 $KB --image kb.img --offset 65536 --journal $J commit --spec g.spec >> smoke.log 2>&1 &
pid=$!
sleep 5
kill -9 $pid
wait $pid 2>/dev/null
run $KB --image kb.img --offset 65536 --journal $J status
echo "done" >> smoke.log
