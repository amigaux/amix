#!/bin/sh
# test-swap.sh -- host tests of the swap boot step against a scratch vfstab,
# a fake swap (its areas in a file) and a fake rdb.
#
#   sh userland/base/rc/test-swap.sh [shell]     (default sh)
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
SH=${1:-sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-swap.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { # same <name> <want> <got>
	[ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"
}
expect() { # expect <name> <want-substring> <got>
	case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac
}
refuse() { # refuse <name> <unwanted-substring> <got>
	case "$3" in *"$2"*) bad "$1: did not want [$2] in [$3]" ;; *) ok ;; esac
}

mkdir -p "$T/bin"
# swap -l | -a <path> <lo> <n> | -d <path> <lo>; the areas are $T/areas,
# "<path> <lo> <n>" a line; an overlap on the same path is refused. As the
# stock swap, -l counts 2 KiB pages: with $T/k46 (4 KiB pages) half of each
cat > "$T/bin/swap" <<EOF
#!/bin/sh
A=$T/areas
touch \$A
case "\$1" in
-l)
	h=1; [ -f $T/k46 ] && h=2
	echo "path                 dev  swaplo blocks   free"
	awk -v h=\$h '{ printf "%-20s 18,38 %6d %6d %6d\\n", \$1, \$2, \$3 / h, \$3 / h }' \$A
	;;
-a)
	echo "-a \$2 \$3 \$4" >> $T/calls
	# a kernel with the guard: an area over \$T/max blocks is refused (ENOMEM)
	if [ -f $T/max ] && [ "\$4" -gt "\`cat $T/max\`" ]; then
		echo "SC_ADD failed"; echo "swap: Not enough space" >&2; exit 2; fi
	awk -v p="\$2" -v lo="\$3" -v n="\$4" '\$1 == p && lo < \$2 + \$3 && \$2 < lo + n { bad = 1 } END { exit bad }' \$A || {
		echo "/usr/sbin/swap: File exists" >&2; exit 2; }
	echo "\$2 \$3 \$4" >> \$A
	;;
-d)
	echo "-d \$2 \$3" >> $T/calls
	awk -v p="\$2" -v lo="\$3" '!(\$1 == p && \$2 == lo)' \$A > \$A.n && mv "\${A:?}.n" "\${A:?}"
	;;
esac
EOF
# rdb <raw s0>: the partitions of disk c6d0 (s1 root, s2 swap, s3 home), and
# of c7d0, whose s2 is 8 GiB
cat > "$T/bin/rdb" <<'EOF'
#!/bin/sh
case "$1" in
/dev/rdsk/c6d0s0) printf 'root 2 204800\nswap 204802 102400\nhome 307202 40000\n' ;;
/dev/rdsk/c7d0s0) printf 'root 2 204800\nswap 204802 16777216\n' ;;
*) exit 1 ;;
esac
EOF
# adb -k <namelist> <kmem>: "<sym>/D" lines in, "<sym>:  <value>" out, the
# values from $T/adb.<sym>
cat > "$T/bin/adb" <<EOF
#!/bin/sh
[ "\$1" = -k ] || exit 1
while read q
do
	s=\`echo \$q | sed 's:/[DX]\$::'\`
	[ -f $T/adb.\$s ] && echo "\$s:        \`cat $T/adb.\$s\`"
done
EOF
: > "$T/unix"
# sed as the box's: a last line without a newline is dropped, whole (in a
# pipe; a file operand goes to the real sed as it is)
REALSED=$(command -v sed)
cat > "$T/bin/sed" <<EOF
#!/bin/sh
for a; do l=\$a; done
[ -f "\$l" ] && exec $REALSED "\$@"
cat > $T/sed.in
[ -n "\`tail -c 1 $T/sed.in\`" ] && { $REALSED '\$d' $T/sed.in > $T/sed.cut; mv "${T:?}/sed.cut" "${T:?}/sed.in"; }
exec $REALSED "\$@" $T/sed.in
EOF
# uname -a: the kernel's build id names its CPU; $T/uname, else a 68030's
cat > "$T/bin/uname" <<EOF
#!/bin/sh
[ -f $T/uname ] && exec cat $T/uname
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) 68030-261101-67 m68k"
EOF
chmod +x "$T/bin/"*

vfstab() { cat > "$T/vfstab"; }
areas() { cat > "$T/areas"; }
run() { # run start|stop: the step, its output; the calls in calls
	: > "$T/calls"
	: > "$T/rc.log"
	env RC_SUBR="$here/rc.subr" RC_LOG="$T/rc.log" RC_CONF="$T/rc.conf" RC_RUN="$T" \
	    SWAP="$T/bin/swap" RDB="$T/bin/rdb" SWAP_ADB="${ADB:-$T/bin/adb}" SWAP_UNIX="$T/unix" SWAP_KMEM=/dev/null \
	    SWAP_VFSTAB="$T/vfstab" SWAP_FILES="$T/SWAPFILE $T/SRCSWAP" PATH="$T/bin:$PATH" \
	    $SH "$here/swap" "$@" 2>&1
}

STOCK='#device         device          mount   FS      fsck    mount   mount
#to mount       to fsck         point   type    pass    at boot options
/dev/dsk/c6d0s1	/dev/rdsk/c6d0s1	/	ufs	1	yes	-
/dev/dsk/c6d0s2	-	-	swap	-	no	-'

# the slice's end: the cases below, before the size list
echo "swap_add=all" > "$T/rc.conf"

# the bench kernel: the whole slice already its area -- nothing to add
echo "$STOCK" | vfstab
echo "/dev/dsk/c6d0s2 0 102400" | areas
o=$(run start)
same "whole slice in use: nothing added" "" "$(cat "$T/calls")"
same "whole slice in use: nothing said" "" "$o"

# the 030 kernel: its 20476-block boot area -- the tail from 20480
echo "/dev/dsk/c6d0s2 0 20476" | areas
o=$(run start)
same "boot area: the tail added" "-a /dev/dsk/c6d0s2 20480 81920" "$(cat "$T/calls")"
expect "boot area: said" "Added swap slice tail /dev/dsk/c6d0s2, 81920 blocks at 20480 (swap_add all)." "$o"
expect "boot area: logged" "swap: added /dev/dsk/c6d0s2 20480 81920 (slice tail, swap_add all)" "$(cat "$T/rc.log")"
# run again: two areas now -- left alone
o=$(run start)
same "again: nothing more" "" "$(cat "$T/calls")"

# a 68060 kernel: swap -l lists half of each area (2 KiB pages counted,
# 4 KiB used), so its whole-slice area reads 51200 -- nothing to add
touch "$T/k46"
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) 68060-261031-94 m68k" > "$T/uname"
echo "/dev/dsk/c6d0s2 0 102400" | areas
o=$(run start)
same "68060, whole slice in use: nothing added" "" "$(cat "$T/calls")"
same "68060, whole slice in use: nothing said" "" "$o"
# its 40960-block area (listed 20480): the tail from 40960
echo "/dev/dsk/c6d0s2 0 40960" | areas
run start > /dev/null
same "68060 boot area: the tail past its real length" "-a /dev/dsk/c6d0s2 40960 61440" "$(cat "$T/calls")"
# a 68040 kernel the same
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) 68040-261031-94 m68k" > "$T/uname"
echo "/dev/dsk/c6d0s2 0 40960" | areas
run start > /dev/null
same "68040 boot area: the tail past its real length" "-a /dev/dsk/c6d0s2 40960 61440" "$(cat "$T/calls")"
# the stock kernel names no CPU: 2 KiB pages, as listed
rm -f "${T:?}/k46"
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) m68k" > "$T/uname"
echo "/dev/dsk/c6d0s2 0 20476" | areas
run start > /dev/null
same "stock kernel: the tail as listed" "-a /dev/dsk/c6d0s2 20480 81920" "$(cat "$T/calls")"
rm -f "${T:?}/uname"

# no area listed: the whole slice
: | areas
o=$(run start)
same "no area: the whole slice" "-a /dev/dsk/c6d0s2 0 102400" "$(cat "$T/calls")"

# a boot area that leaves under 2048 blocks: nothing
echo "/dev/dsk/c6d0s2 0 100400" | areas
run start > /dev/null
same "small tail: nothing" "" "$(cat "$T/calls")"
# 2048 exactly: added
echo "/dev/dsk/c6d0s2 0 100352" | areas
run start > /dev/null
same "2048 left: added" "-a /dev/dsk/c6d0s2 100352 2048" "$(cat "$T/calls")"

# an area not from block 0: left alone
echo "/dev/dsk/c6d0s2 4096 20000" | areas
run start > /dev/null
same "not from 0: left" "" "$(cat "$T/calls")"

# the slice is the RDB's line: s3 is "home", 40000 blocks
printf '%s\n/dev/dsk/c6d0s3\t-\t-\tswap\t-\tno\t-\n' "$STOCK" | vfstab
: | areas
run start > /dev/null
same "two slices: each its own length" "-a /dev/dsk/c6d0s2 0 102400
-a /dev/dsk/c6d0s3 0 40000" "$(cat "$T/calls")"

# a disk the RDB tool cannot read: left, and said
printf '/dev/dsk/c5d0s2\t-\t-\tswap\t-\tno\t-\n' | vfstab
run start > /dev/null
same "no RDB: nothing" "" "$(cat "$T/calls")"
expect "no RDB: logged" "swap: /dev/dsk/c5d0s2: no length in the RDB of c5d0; left" "$(cat "$T/rc.log")"

# swap files: the stock two when present, and a vfstab file line; the
# slices first, so that the partition has the kernel's memory first
dd if=/dev/zero of="$T/SWAPFILE" bs=512 count=64 2> /dev/null
dd if=/dev/zero of="$T/more" bs=512 count=32 2> /dev/null
printf '%s/SWAPFILE\t-\t-\tswap\t-\tno\t-\n%s/more\t-\t-\tswap\t-\tno\t-\n%s\n' "$T" "$T" "$STOCK" | vfstab
: | areas
o=$(run start)
same "files: each once, after the slice" "-a /dev/dsk/c6d0s2 0 102400
-a $T/more 0 32
-a $T/SWAPFILE 0 64" "$(cat "$T/calls")"
expect "files: said" "Added swap file $T/more, 32 blocks at 0." "$o"
# a vfstab line naming nothing
printf '/nowhere/swapfile\t-\t-\tswap\t-\tno\t-\n' | vfstab
rm -f "${T:?}/SWAPFILE"
run start > /dev/null
expect "missing: logged" "swap: /nowhere/swapfile: no such file or slice; left" "$(cat "$T/rc.log")"

# commented and other lines are not swap
printf '#/dev/dsk/c6d0s2\t-\t-\tswap\t-\tno\t-\n/dev/dsk/c6d0s1\t/dev/rdsk/c6d0s1\t/\tufs\t1\tyes\t-\n' | vfstab
run start > /dev/null
same "comments and ufs: nothing" "" "$(cat "$T/calls")"

# the size list (rc.conf swap_add): the 50 MiB slice c6d0s2, the 030
# kernel's 20476-block area from 0
printf '%s\n' "$STOCK" | vfstab
: > "$T/rc.conf"
# no swap_add, a 68030 kernel with the guard (its marker read with adb): all
echo 53574721 > "$T/adb.swg_magic"
echo "/dev/dsk/c6d0s2 0 20476" | areas
o=$(run start)
same "no swap_add, guard: the slice's end" "-a /dev/dsk/c6d0s2 20480 81920" "$(cat "$T/calls")"
expect "no swap_add, guard: the size logged" "swap: added /dev/dsk/c6d0s2 20480 81920 (slice tail, swap_add all)" "$(cat "$T/rc.log")"
refuse "no swap_add, guard: no line" "no guard" "$o"
# no guard (no marker, or not its value: another kernel's namelist): 30
echo 12345678 > "$T/adb.swg_magic"
echo "/dev/dsk/c6d0s2 0 20476" | areas
o=$(run start)
same "no swap_add, no guard: 30 MiB in all" "-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
expect "no swap_add, no guard: said" "swap: the kernel has no guard against a swap area too large for its memory: 30 MiB a slice in all" "$o"
expect "no swap_add, no guard: logged" "swap: the kernel has no guard against a swap area too large for its memory" "$(cat "$T/rc.log")"
rm -f "${T:?}/adb.swg_magic"
echo "/dev/dsk/c6d0s2 0 20476" | areas
run start > /dev/null
same "no swap_add, no marker: 30" "-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
echo "/dev/dsk/c6d0s2 0 20476" | areas
ADB="$T/noadb" run start > /dev/null
same "no swap_add, no adb: 30" "-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
# a 68060 kernel the same: the guard, all; without (cuts before
# 68060-261101-56), 30 in all, which its 30 MiB boot area already is
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) 68060-261106-64 m68k" > "$T/uname"
touch "$T/k46"
echo 53574721 > "$T/adb.swg_magic"
echo "/dev/dsk/c6d0s2 0 40960" | areas
o=$(run start)
same "no swap_add, 68060 guard: all" "-a /dev/dsk/c6d0s2 40960 61440" "$(cat "$T/calls")"
refuse "no swap_add, 68060 guard: no line" "no guard" "$o"
rm -f "${T:?}/adb.swg_magic"
echo "/dev/dsk/c6d0s2 0 40960" | areas
o=$(run start)
same "no swap_add, 68060 no guard: 30" "-a /dev/dsk/c6d0s2 40960 20480" "$(cat "$T/calls")"
expect "no swap_add, 68060 no guard: said" "swap: the kernel has no guard" "$o"
rm -f "${T:?}/uname" "${T:?}/k46"
echo "swap_add=30" > "$T/rc.conf"
echo "/dev/dsk/c6d0s2 0 20476" | areas
run start > /dev/null
same "30: 61440 blocks in all" "-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
# no area listed: 30 MiB from block 0
: | areas
run start > /dev/null
same "30, no area: from 0" "-a /dev/dsk/c6d0s2 0 61440" "$(cat "$T/calls")"
# a size past the slice's end is the end
echo "swap_add=200" > "$T/rc.conf"
echo "/dev/dsk/c6d0s2 0 20476" | areas
run start > /dev/null
same "200 MiB: the slice's end" "-a /dev/dsk/c6d0s2 20480 81920" "$(cat "$T/calls")"
# a size inside the kernel's area adds nothing, and the next is tried
echo "swap_add=10 30" > "$T/rc.conf"
echo "/dev/dsk/c6d0s2 0 20476" | areas
run start > /dev/null
same "10 inside the area: 30 next" "-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
# the guard: all refused, 48 refused, 30 taken; each said in rc.log
echo "swap_add=all 48 30" > "$T/rc.conf"
echo 50000 > "$T/max"
echo "/dev/dsk/c6d0s2 0 20476" | areas
o=$(run start)
same "all 48 30: stepped down" "-a /dev/dsk/c6d0s2 20480 81920
-a /dev/dsk/c6d0s2 20480 77824
-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
expect "all 48 30: the refusal logged" "swap: swap -a /dev/dsk/c6d0s2 20480 81920 failed: SC_ADD failed swap: Not enough space" "$(cat "$T/rc.log")"
expect "all 48 30: the size used logged" "swap: added /dev/dsk/c6d0s2 20480 40960 (slice tail, swap_add 30)" "$(cat "$T/rc.log")"
expect "all 48 30: the refusal said" "failed: SC_ADD failed swap: Not enough space" "$o"
expect "all 48 30: less than asked said" "swap: /dev/dsk/c6d0s2: 20 of 40 MiB added; the kernel refused more for want of memory" "$o"
expect "all 48 30: less than asked logged" "swap: /dev/dsk/c6d0s2: 20 of 40 MiB added; the kernel refused more for want of memory" "$(cat "$T/rc.log")"
refuse "68030: no figure" "at most" "$o"
# the refusal's text on standard output alone still steps down
cp "$T/bin/swap" "$T/swap.real"
printf '#!/bin/sh\ncase "$1" in -a) if [ "$4" -gt 50000 ]; then echo "-a $2 $3 $4" >> %s/calls; echo "swap: Not enough space"; exit 2; fi ;; esac\nexec %s/swap.real "$@"\n' "$T" "$T" > "$T/bin/swap"
rm -f "${T:?}/max"
echo "/dev/dsk/c6d0s2 0 20476" | areas
run start > /dev/null
same "stdout text: stepped down" "-a /dev/dsk/c6d0s2 20480 81920
-a /dev/dsk/c6d0s2 20480 77824
-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
cp "$T/swap.real" "$T/bin/swap"

# all fits: one try
rm -f "${T:?}/max"
echo "/dev/dsk/c6d0s2 0 20476" | areas
run start > /dev/null
same "all fits: one try" "-a /dev/dsk/c6d0s2 20480 81920" "$(cat "$T/calls")"
# every size refused: each tried once, then halves of the last down to 8 MiB
echo 1000 > "$T/max"
echo "swap_add=all 48 30 30 all" > "$T/rc.conf"
echo "/dev/dsk/c6d0s2 0 20476" | areas
o=$(run start)
same "all refused: each size once, then halves" "-a /dev/dsk/c6d0s2 20480 81920
-a /dev/dsk/c6d0s2 20480 77824
-a /dev/dsk/c6d0s2 20480 40960
-a /dev/dsk/c6d0s2 20480 20480" "$(cat "$T/calls")"
same "all refused: nothing added" "/dev/dsk/c6d0s2 0 20476" "$(cat "$T/areas")"
expect "all refused: said" "swap: /dev/dsk/c6d0s2: 0 of 40 MiB added; the kernel refused more for want of memory" "$o"
expect "all refused: logged" "swap: /dev/dsk/c6d0s2: 0 of 40 MiB added" "$(cat "$T/rc.log")"
# no list below the refused size: halves, whole MiB
echo 50000 > "$T/max"
echo "swap_add=all" > "$T/rc.conf"
echo "/dev/dsk/c6d0s2 0 20476" | areas
o=$(run start)
same "halved: the half taken" "-a /dev/dsk/c6d0s2 20480 81920
-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
expect "halved: said how" "Added swap slice tail /dev/dsk/c6d0s2, 40960 blocks at 20480 (stepped down)." "$o"
expect "halved: less said" "swap: /dev/dsk/c6d0s2: 20 of 40 MiB added" "$o"
# a size not below the last refused is not tried
echo "swap_add=48 all 30" > "$T/rc.conf"
echo "/dev/dsk/c6d0s2 0 20476" | areas
run start > /dev/null
same "larger after a refusal: skipped" "-a /dev/dsk/c6d0s2 20480 77824
-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
# the tries are bounded: 8 at most (an 8 GiB slice, nothing taken)
printf '/dev/dsk/c7d0s2\t-\t-\tswap\t-\tno\t-\n' | vfstab
echo "swap_add=all" > "$T/rc.conf"
echo "/dev/dsk/c7d0s2 0 20476" | areas
echo 1 > "$T/max"
o=$(run start)
same "bounded: 8 tries, halving" "-a /dev/dsk/c7d0s2 20480 16756736
-a /dev/dsk/c7d0s2 20480 8378368
-a /dev/dsk/c7d0s2 20480 4188160
-a /dev/dsk/c7d0s2 20480 2093056
-a /dev/dsk/c7d0s2 20480 1046528
-a /dev/dsk/c7d0s2 20480 522240
-a /dev/dsk/c7d0s2 20480 260096
-a /dev/dsk/c7d0s2 20480 129024" "$(cat "$T/calls")"
expect "bounded: said" "swap: /dev/dsk/c7d0s2: 0 of 8182 MiB added" "$o"
# a 68030 kernel whose guard has the eighth rule (its symbol swg_keep, from
# cut -72): its limit read with adb (maxmem/32 MiB, maxmem in 2 KiB pages)
# is the next try, and the line says it
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) 68030-261106-72 m68k" > "$T/uname"
echo 15021 > "$T/adb.maxmem"; echo 16384 > "$T/adb.physmem"; echo 0 > "$T/adb.swg_keep"
echo 53574721 > "$T/adb.swg_magic"
echo 1000000 > "$T/max"
echo "/dev/dsk/c7d0s2 0 20476" | areas
o=$(run start)
same "68030 -72 limit: tried next" "-a /dev/dsk/c7d0s2 20480 16756736
-a /dev/dsk/c7d0s2 20480 960512" "$(cat "$T/calls")"
expect "68030 -72 limit: added as" "Added swap slice tail /dev/dsk/c7d0s2, 960512 blocks at 20480 (the kernel's limit)." "$o"
expect "68030 -72 limit: said" "swap: /dev/dsk/c7d0s2: 469 of 8182 MiB added; the kernel refused more for want of memory (it takes at most 469 MiB per area with 29 MiB of pageable memory)" "$o"
expect "68030 -72 limit: logged" "(it takes at most 469 MiB per area with 29 MiB of pageable memory)" "$(cat "$T/rc.log")"
# 16 MiB (maxmem 7104): 222 MiB
echo 7104 > "$T/adb.maxmem"; echo 8192 > "$T/adb.physmem"
echo "/dev/dsk/c7d0s2 0 20476" | areas
o=$(run start)
same "68030 -72 at 16 MiB: 222" "-a /dev/dsk/c7d0s2 20480 16756736
-a /dev/dsk/c7d0s2 20480 454656" "$(cat "$T/calls")"
expect "68030 -72 at 16 MiB: said" "(it takes at most 222 MiB per area with 13 MiB of pageable memory)" "$o"
# the build number does not tell: a trial build without the symbol
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) 68030-261105-98 m68k" > "$T/uname"
rm -f "${T:?}/adb.swg_keep"
echo "/dev/dsk/c7d0s2 0 20476" | areas
o=$(run start)
refuse "68030 without swg_keep: no figure" "at most" "$o"
# cut -71: the guard without the eighth rule: no figure, halves
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) 68030-261103-71 m68k" > "$T/uname"
echo "/dev/dsk/c7d0s2 0 20476" | areas
o=$(run start)
same "68030 -71: halves" "-a /dev/dsk/c7d0s2 20480 16756736
-a /dev/dsk/c7d0s2 20480 8378368
-a /dev/dsk/c7d0s2 20480 4188160
-a /dev/dsk/c7d0s2 20480 2093056
-a /dev/dsk/c7d0s2 20480 1046528
-a /dev/dsk/c7d0s2 20480 522240" "$(cat "$T/calls")"
refuse "68030 -71: no figure" "at most" "$o"
# -72 with a namelist adb cannot read (maxmem over physmem): no figure
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) 68030-261106-72 m68k" > "$T/uname"
echo 0 > "$T/adb.swg_keep"
echo 99999 > "$T/adb.maxmem"
echo "/dev/dsk/c7d0s2 0 20476" | areas
o=$(run start)
refuse "68030 -72 nonsense: no figure" "at most" "$o"
expect "68030 -72 nonsense: still said" "swap: /dev/dsk/c7d0s2: 255 of 8182 MiB added" "$o"
# swg_keep with no marker: no figure
rm -f "${T:?}/adb.swg_magic"
echo 15021 > "$T/adb.maxmem"
echo "/dev/dsk/c7d0s2 0 20476" | areas
o=$(run start)
refuse "68030 swg_keep, no marker: no figure" "at most" "$o"
rm -f "${T:?}/uname" "${T:?}/adb.swg_keep"
# a 68060 kernel: its limit read with adb (maxmem/8 MiB) is the next try,
# and the line says it, with the pageable memory (maxmem 4 KiB pages)
touch "$T/k46"
echo "UNIX_System_V box 4.0 2.1c 0800430 Amiga (Unlimited) 68060-261031-94 m68k" > "$T/uname"
echo 3562 > "$T/adb.maxmem"; echo 4096 > "$T/adb.physmem"
echo 1000000 > "$T/max"
echo "/dev/dsk/c7d0s2 0 40960" | areas
o=$(run start)
same "68060 limit: tried next" "-a /dev/dsk/c7d0s2 40960 16736256
-a /dev/dsk/c7d0s2 40960 911360" "$(cat "$T/calls")"
expect "68060 limit: added as" "Added swap slice tail /dev/dsk/c7d0s2, 911360 blocks at 40960 (the kernel's limit)." "$o"
expect "68060 limit: said" "swap: /dev/dsk/c7d0s2: 445 of 8172 MiB added; the kernel refused more for want of memory (it takes at most 445 MiB per area with 13 MiB of pageable memory)" "$o"
expect "68060 limit: logged" "swap: /dev/dsk/c7d0s2: 445 of 8172 MiB added; the kernel refused more for want of memory (it takes at most 445 MiB per area with 13 MiB of pageable memory)" "$(cat "$T/rc.log")"
# the limit refused too (another limit bit first): halves of it
echo 500000 > "$T/max"
echo "/dev/dsk/c7d0s2 0 40960" | areas
run start > /dev/null
same "68060 limit refused: its half" "-a /dev/dsk/c7d0s2 40960 16736256
-a /dev/dsk/c7d0s2 40960 911360
-a /dev/dsk/c7d0s2 40960 454656" "$(cat "$T/calls")"
# adb gives nonsense (maxmem over physmem: no symbol table): no figure
echo 999999 > "$T/adb.maxmem"
echo 9000000 > "$T/max"
echo "/dev/dsk/c7d0s2 0 40960" | areas
o=$(run start)
expect "nonsense maxmem: still said" "swap: /dev/dsk/c7d0s2: 4086 of 8172 MiB added; the kernel refused more for want of memory" "$o"
refuse "nonsense maxmem: no figure" "at most" "$o"
# no adb: no figure, the line still said
echo 3562 > "$T/adb.maxmem"
echo "/dev/dsk/c7d0s2 0 40960" | areas
o=$(ADB="$T/noadb" run start)
expect "no adb: still said" "swap: /dev/dsk/c7d0s2: 4086 of 8172 MiB added" "$o"
refuse "no adb: no figure" "at most" "$o"
# what fits whole: no line
rm -f "${T:?}/max"
echo "/dev/dsk/c7d0s2 0 40960" | areas
o=$(run start)
refuse "fits: no line" "MiB added" "$o"
rm -f "${T:?}/k46" "${T:?}/uname" "${T:?}/adb.maxmem" "${T:?}/adb.physmem"
# a file refused: halves of it
dd if=/dev/zero of="$T/SWAPFILE" bs=512 count=1 seek=65535 2> /dev/null
: > "$T/vfstab"
: | areas
echo 40000 > "$T/max"
o=$(run start)
same "file refused: halves" "-a $T/SWAPFILE 0 65536
-a $T/SWAPFILE 0 32768" "$(cat "$T/calls")"
expect "file refused: said" "swap: $T/SWAPFILE: 16 of 32 MiB added" "$o"
rm -f "${T:?}/max" "${T:?}/SWAPFILE"
printf '%s\n' "$STOCK" | vfstab
# a 48 that ends where all does (a 40 MiB slice) is not tried again
printf '/dev/dsk/c6d0s3\t-\t-\tswap\t-\tno\t-\n' | vfstab
echo 1000 > "$T/max"
echo "swap_add=all 48 10" > "$T/rc.conf"
: | areas
run start > /dev/null
same "48 = all: not again" "-a /dev/dsk/c6d0s3 0 40000
-a /dev/dsk/c6d0s3 0 20480" "$(cat "$T/calls")"
rm -f "${T:?}/max"
# another failure ends it: no step down
printf '%s\n' "$STOCK" | vfstab
echo "swap_add=all 30" > "$T/rc.conf"
printf '/dev/dsk/c6d0s2 0 20476\n/dev/dsk/c6d0s2 30000 100\n' | areas
run start > /dev/null
same "two areas: left" "" "$(cat "$T/calls")"
echo "/dev/dsk/c6d0s2 0 20476" | areas
cp "$T/bin/swap" "$T/swap.real"
printf '#!/bin/sh\ncase "$1" in -a) echo "-a $2 $3 $4" >> %s/calls; echo "/usr/sbin/swap: Invalid argument" >&2; exit 1 ;; esac\nexec %s/swap.real "$@"\n' "$T" "$T" > "$T/bin/swap"
run start > /dev/null
same "EINVAL: no step down" "-a /dev/dsk/c6d0s2 20480 81920" "$(cat "$T/calls")"
cp "$T/swap.real" "$T/bin/swap"
# a bad entry is said and skipped
echo "swap_add=lots 30" > "$T/rc.conf"
echo "/dev/dsk/c6d0s2 0 20476" | areas
run start > /dev/null
same "bad entry: skipped" "-a /dev/dsk/c6d0s2 20480 40960" "$(cat "$T/calls")"
expect "bad entry: logged" "swap: swap_add: lots is neither all nor a size in MiB; skipped" "$(cat "$T/rc.log")"
ls "$T"/swap.[0-9]* > /dev/null 2>&1 && bad "an error file was left" || ok

# stop: the files go, then every area after the first
printf '/dev/dsk/c6d0s2 0 20476\n/dev/dsk/c6d0s2 20480 81920\n%s/more 0 32\n' "$T" | areas
run stop > /dev/null
same "stop: the file, then the tail" "-d $T/more 0
-d /dev/dsk/c6d0s2 20480" "$(cat "$T/calls")"
same "stop: the boot area stays" "/dev/dsk/c6d0s2 0 20476" "$(cat "$T/areas")"

same "usage" "1" "$(env RC_SUBR="$here/rc.subr" $SH "$here/swap" 2>/dev/null; echo $?)"

echo "test-swap: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
