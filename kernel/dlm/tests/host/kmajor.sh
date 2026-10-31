#!/bin/sh
# kmajor.sh -- `kbootset major NAME` (C2-4 §15): the majors the compiled-in
# registry gives a module, one `c N` or `b N` line each, compared with
# abi/registry/majors read here independently.  Covered: every name in the
# registry; `major -l`, every row as `NAME c|b N` in the registry's order
# (version 18); a name it does not know (status 1, the message); usage
# (status 2); no kinfo and no store anywhere (a static kernel, a medium
# boot), with -R and with --image before the command: the same lines.
# Run from the repository root after `make tools`.
set -e
B=${B:-build}
T=$B/kmajor
rm -rf $T && mkdir -p $T/dev $T/root
export KBOOTSET_DEVROOT=$T/dev KBOOTSET_KINFO=$T/no-kinfo

# every owner in the registry: its lines in the registry's order
sed 's/#.*//' abi/registry/majors | awk 'NF == 3 { print $3 }' | sort -u > $T/names
[ -s $T/names ]
n=0
for m in $(cat $T/names); do
	sed 's/#.*//' abi/registry/majors | awk -v m=$m 'NF == 3 && $3 == m { print $1, $2 }' > $T/want
	$B/kbootset major $m > $T/got
	cmp -s $T/want $T/got || { echo "kmajor: $m: got '$(cat $T/got)', want '$(cat $T/want)'" >&2; exit 1; }
	# the options before the command change nothing: no store is opened
	$B/kbootset -R $T/root major $m | cmp -s $T/want -
	$B/kbootset --image $T/none.img --offset 65536 major $m | cmp -s $T/want -
	n=$((n + 1))
done
# the ones other stations hard-code today (C3-6, C3-5 §2)
[ "$($B/kbootset major z3660eth)" = "c 51" ]
[ "$($B/kbootset major ramdisk)" = "b 20" ]
[ "$($B/kbootset major kinfo)" = "c 53" ]
# -l: the whole registry, its rows in its order, as `NAME c|b N`
sed 's/#.*//' abi/registry/majors | awk 'NF == 3 { print $3, $1, $2 }' > $T/wantl
$B/kbootset major -l > $T/gotl
cmp -s $T/wantl $T/gotl || { echo "kmajor: -l: got '$(cat $T/gotl)', want '$(cat $T/wantl)'" >&2; exit 1; }
$B/kbootset -R $T/root major -l | cmp -s $T/wantl -
grep -qx "z3660eth c 51" $T/gotl && grep -qx "ramdisk b 20" $T/gotl
# a name the registry does not know: status 1, nothing on stdout
set +e
$B/kbootset major nosuch > $T/out 2> $T/err; r1=$?
$B/kbootset major > /dev/null 2>&1; r2=$?
$B/kbootset major z3660eth extra > /dev/null 2>&1; r3=$?
$B/kbootset major -l extra > /dev/null 2>&1; r4=$?
set -e
[ $r1 -eq 1 ] && [ ! -s $T/out ] && grep -qx "kbootset: no major is registered to nosuch" $T/err
[ $r2 -eq 2 ] && [ $r3 -eq 2 ] && [ $r4 -eq 2 ]
echo "kmajor: $n registered modules, -l, an unknown name, usage, no kinfo and no store ok"
