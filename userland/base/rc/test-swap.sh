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
trap 'rm -rf "$T"' EXIT
pass=0 fail=0

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }
same() { # same <name> <want> <got>
	[ "$2" = "$3" ] && ok || bad "$1: want [$2] got [$3]"
}
expect() { # expect <name> <want-substring> <got>
	case "$3" in *"$2"*) ok ;; *) bad "$1: want [$2] got [$3]" ;; esac
}

mkdir -p "$T/bin"
# swap -l | -a <path> <lo> <n> | -d <path> <lo>; the areas are $T/areas,
# "<path> <lo> <n>" a line; an overlap on the same path is refused
cat > "$T/bin/swap" <<EOF
#!/bin/sh
A=$T/areas
touch \$A
case "\$1" in
-l)
	echo "path                 dev  swaplo blocks   free"
	awk '{ printf "%-20s 18,38 %6d %6d %6d\\n", \$1, \$2, \$3, \$3 }' \$A
	;;
-a)
	echo "-a \$2 \$3 \$4" >> $T/calls
	awk -v p="\$2" -v lo="\$3" -v n="\$4" '\$1 == p && lo < \$2 + \$3 && \$2 < lo + n { bad = 1 } END { exit bad }' \$A || {
		echo "/usr/sbin/swap: File exists" >&2; exit 2; }
	echo "\$2 \$3 \$4" >> \$A
	;;
-d)
	echo "-d \$2 \$3" >> $T/calls
	awk -v p="\$2" -v lo="\$3" '!(\$1 == p && \$2 == lo)' \$A > \$A.n && mv \$A.n \$A
	;;
esac
EOF
# rdb <raw s0>: the partitions of disk c6d0 (s1 root, s2 swap, s3 home)
cat > "$T/bin/rdb" <<'EOF'
#!/bin/sh
case "$1" in
/dev/rdsk/c6d0s0) printf 'root 2 204800\nswap 204802 102400\nhome 307202 40000\n' ;;
*) exit 1 ;;
esac
EOF
chmod +x "$T/bin/"*

vfstab() { cat > "$T/vfstab"; }
areas() { cat > "$T/areas"; }
run() { # run start|stop: the step, its output; the calls in calls
	: > "$T/calls"
	: > "$T/rc.log"
	env RC_SUBR="$here/rc.subr" RC_LOG="$T/rc.log" SWAP="$T/bin/swap" RDB="$T/bin/rdb" \
	    SWAP_VFSTAB="$T/vfstab" SWAP_FILES="$T/SWAPFILE $T/SRCSWAP" PATH="$T/bin:$PATH" \
	    $SH "$here/swap" "$@" 2>&1
}

STOCK='#device         device          mount   FS      fsck    mount   mount
#to mount       to fsck         point   type    pass    at boot options
/dev/dsk/c6d0s1	/dev/rdsk/c6d0s1	/	ufs	1	yes	-
/dev/dsk/c6d0s2	-	-	swap	-	no	-'

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
expect "boot area: said" "Added swap slice tail /dev/dsk/c6d0s2, 81920 blocks at 20480." "$o"
expect "boot area: logged" "swap: added /dev/dsk/c6d0s2 20480 81920 (slice tail)" "$(cat "$T/rc.log")"
# run again: two areas now -- left alone
o=$(run start)
same "again: nothing more" "" "$(cat "$T/calls")"

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

# swap files: the stock two when present, and a vfstab file line
dd if=/dev/zero of="$T/SWAPFILE" bs=512 count=64 2> /dev/null
dd if=/dev/zero of="$T/more" bs=512 count=32 2> /dev/null
printf '%s/more\t-\t-\tswap\t-\tno\t-\n%s/SWAPFILE\t-\t-\tswap\t-\tno\t-\n' "$T" "$T" | vfstab
o=$(run start)
same "files: each once" "-a $T/SWAPFILE 0 64
-a $T/more 0 32" "$(cat "$T/calls")"
expect "files: said" "Added swap file $T/more, 32 blocks at 0." "$o"
# a vfstab line naming nothing
printf '/nowhere/swapfile\t-\t-\tswap\t-\tno\t-\n' | vfstab
rm -f "$T/SWAPFILE"
run start > /dev/null
expect "missing: logged" "swap: /nowhere/swapfile: no such file or slice; left" "$(cat "$T/rc.log")"

# commented and other lines are not swap
printf '#/dev/dsk/c6d0s2\t-\t-\tswap\t-\tno\t-\n/dev/dsk/c6d0s1\t/dev/rdsk/c6d0s1\t/\tufs\t1\tyes\t-\n' | vfstab
run start > /dev/null
same "comments and ufs: nothing" "" "$(cat "$T/calls")"

# stop: the files go, then every area after the first
printf '/dev/dsk/c6d0s2 0 20476\n/dev/dsk/c6d0s2 20480 81920\n%s/more 0 32\n' "$T" | areas
run stop > /dev/null
same "stop: the file, then the tail" "-d $T/more 0
-d /dev/dsk/c6d0s2 20480" "$(cat "$T/calls")"
same "stop: the boot area stays" "/dev/dsk/c6d0s2 0 20476" "$(cat "$T/areas")"

same "usage" "1" "$(env RC_SUBR="$here/rc.subr" $SH "$here/swap" 2>/dev/null; echo $?)"

echo "test-swap: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
