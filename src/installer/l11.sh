# l11.sh -- the 1.1 disk layout and its boot store, sourced by install.sh when the
# profile says INSTALL_LAYOUT=1.1. Runs ON THE MINIROOT under the same 1991 sh and
# the same tool allowlist as install.sh (installer-selftest audits both); it uses
# install.sh's helpers (msg warn die run runq is_num) and its variables.
#
# THE LAYOUT (amix-dlm docs/spec/40-generations-and-composer.md §2.1):
#   s1 UNI\1 root   s2 resv swap   s3 UNI\0 the boot store, 64 MiB, the ONLY UNI\0
#   s4 UNI\1 data, mounted at /home -- laid when TARGET_DATA_MB asks for it, or by
#      default on a disk of 512 MB and more (a quarter of the disk)
# The store holds generations, never a 1.0 boot chain: the kernel reaches the
# target as an apkg kernel-space package (/stand/k30|k46/{unix,kabi}, the record in
# /var/apkg/kpkg) and `kbootset` composes and commits the pristine generation from
# it (C2-2, C2-3, C2-4). Nothing here frames a kernel or writes a loader by hand.
#
# THE MEDIUM (/install/l11, tools/build-install-iso.sh):
#   bin/kbootset   the box kbootset (GCC 14, static; amix-dlm `make box`)
#   bin/apkg       apkg 0.3, static, FILE+RAW (amix-packagemanager)
#   loader/boot1 loader/boot2 loader/store-id   the amix-dlm loader; store-id = the
#                  header set id `kbootset create` gives a 64 MiB store of this boot2
#   kpkg/catalog kpkg/pkgs/kernel/*.pkg   the FILE source (#ext kpkg 1 block)
#   updbootpart    the shim laid at /usr/sbin/updbootpart (payload/updbootpart-l11)
#
# PROFILE KEYS:
#   INSTALL_LAYOUT=1.1   this file; 1.0 (the default) never sources it
#   KERNEL_KPKG          the kernel package's catalog name (kernel-k030u, ...)
#   TARGET_FASTMEM_MB    fast memory of the box, for gate 6 and bootset's mem= (until
#                        kinfo is on the installed system)
#   TARGET_DATA_MB       the data slice in MB; 0 = none; empty = the spec's default
#   KBOOTSET_BOOTDEV KBOOTSET_ROOTDEV   match keys; derived from TARGET_HBA when empty
#   KBOOTSET_ROOTREC     the manifest's root record; derived from the root key when empty

L11=$INST/l11
L11_KB=$L11/bin/kbootset
L11_APKG=$L11/bin/apkg
L11_STORE_MB=64
L11_STORE_BYTES=67108864

# l11_keys -- validate the 1.1 keys and derive the box facts. Called once, right
# after the profile is loaded.
l11_keys()
{
	for _f in "$L11_KB" "$L11_APKG" "$L11/loader/boot1" "$L11/loader/boot2" \
		"$L11/loader/store-id" "$L11/kpkg/catalog" "$L11/updbootpart"
	do
		[ -f "$_f" ] || die "INSTALL_LAYOUT=1.1 but the medium has no $_f -- re-master with tools/build-install-iso.sh"
	done
	[ "${INSTALL_TARGET_PREBUILT:-0}" = 1 ] && die "INSTALL_LAYOUT=1.1 is laid on the box: INSTALL_TARGET_PREBUILT=1 (mkroot.sh's 1.0 layout) cannot be used"
	[ -z "$TARGET_BOOT_MB" ] || die "INSTALL_LAYOUT=1.1: the boot store is ${L11_STORE_MB} MiB by the spec; drop TARGET_BOOT_MB"
	[ -n "$KERNEL_KPKG" ] || die "INSTALL_LAYOUT=1.1 needs KERNEL_KPKG (the kernel package to install)"
	is_num "$TARGET_FASTMEM_MB" || die "INSTALL_LAYOUT=1.1 needs TARGET_FASTMEM_MB (the box's fast memory in MB)"
	L11_MEM=`expr "$TARGET_FASTMEM_MB" \* 1048576`
	case "$INSTALL_CPU" in
		030)		L11_LINE=30 ;;
		*)		L11_LINE=46 ;;
	esac
	if [ -z "$KBOOTSET_BOOTDEV" ]; then
		case "$TARGET_HBA" in
			a3000)		KBOOTSET_BOOTDEV=mobo:a3000-wd ;;
			z3660scsi)	KBOOTSET_BOOTDEV=zorro:144b:01 ;;
			a4091)		KBOOTSET_BOOTDEV=zorro:0202:54 ;;
			a4092)		KBOOTSET_BOOTDEV=zorro:c0de:01 ;;
			gayle)		KBOOTSET_BOOTDEV=mobo:gayle ;;
			*)		die "INSTALL_LAYOUT=1.1: no controller key known for TARGET_HBA='$TARGET_HBA'; set KBOOTSET_BOOTDEV" ;;
		esac
	fi
	[ -n "$KBOOTSET_ROOTDEV" ] || KBOOTSET_ROOTDEV="$KBOOTSET_BOOTDEV"
	# the root record (amix-dlm 10 §5.1): a Zorro board by its id, manufacturer<<16 |
	# product<<8; a motherboard controller by the `mobo` flag with id and base 0
	if [ -z "$KBOOTSET_ROOTREC" ]; then
		case "$KBOOTSET_ROOTDEV" in
			zorro:*:*)
				_m=`expr "$KBOOTSET_ROOTDEV" : 'zorro:\([0-9a-fA-F]*\):'`
				_p=`expr "$KBOOTSET_ROOTDEV" : 'zorro:[0-9a-fA-F]*:\([0-9a-fA-F]*\)$'`
				KBOOTSET_ROOTREC="sd id=${_m}${_p}00 base=00000000 unit=$TARGET_SCSI_ID slice=$TARGET_ROOT_SLICE" ;;
			mobo:*)	KBOOTSET_ROOTREC="sd id=00000000 base=00000000 unit=$TARGET_SCSI_ID slice=$TARGET_ROOT_SLICE mobo" ;;
			*)	die "KBOOTSET_ROOTDEV='$KBOOTSET_ROOTDEV' is not a zorro: or mobo: match key" ;;
		esac
	fi
	L11_STORE_ID=`( read _s _r; echo "$_s" ) < "$L11/loader/store-id"`
	[ -n "$L11_STORE_ID" ] || die "the medium's loader/store-id is empty"
	msg "layout 1.1   : store ${L11_STORE_MB} MiB (s$TARGET_BOOT_SLICE), kernel package $KERNEL_KPKG, line k$L11_LINE"
	msg "box facts    : bootdev $KBOOTSET_BOOTDEV rootdev $KBOOTSET_ROOTDEV mem ${TARGET_FASTMEM_MB} MB"
	msg "root record  : $KBOOTSET_ROOTREC"
}

# l11_plan_data DISK_MB -- DATALEN (512-byte blocks, cylinder-aligned) for s4.
# Called by plan_partitions before the root is sized: the data slice comes out of
# what the root would otherwise get.
l11_plan_data()
{
	if [ -n "$TARGET_DATA_MB" ]; then
		is_num "$TARGET_DATA_MB" || die "TARGET_DATA_MB='$TARGET_DATA_MB' is not a number"
		DATA_MB="$TARGET_DATA_MB"
	elif [ "$1" -ge 512 ]; then
		DATA_MB=`expr "$1" / 4`
	else
		DATA_MB=0
	fi
	# the 1.0 filesystem limit (spec 40 §2.1, OQ-40.7), and a stock kernel's own cap
	if [ "$DATA_MB" -gt 1024 ]; then DATA_MB=1024; fi
	if [ "$KERNEL_SDDEVSIZE" != fixed ]; then
		_cap=`expr "$SDDEV_CAP_BLOCKS" / "$BLOCKS_PER_MB"`
		if [ "$DATA_MB" -gt "$_cap" ]; then DATA_MB="$_cap"; fi
	fi
	DATALEN=`expr "$DATA_MB" \* "$BLOCKS_PER_MB"`
}

# l11_uni0_count DISK -- how many partitions of DISK carry DosType UNI\0 (echoed).
# Read from the RDB itself: every PART block in the first 128 blocks (stock /etc/rdb
# keeps its blocks there; the first slice starts at OFFSET_BLOCKS=128), its DosType
# at byte 192 (de_DosType, DosEnvVec[16]). The sh drops the NUL of UNI\0, so UNI\0
# reads "UNI" and UNI\1 does not. Counting a stale, unlinked PART block too errs on
# the refusing side.
l11_uni0_count()
{
	_n=0
	_b=0
	while [ "$_b" -lt 128 ]
	do
		dd if="$1" of=/tmp/.l11b bs=512 iseek="$_b" count=1 2>/dev/null
		_mg=`dd if=/tmp/.l11b bs=4 count=1 2>/dev/null`
		if [ "$_mg" = PART ]; then
			_dt=`dd if=/tmp/.l11b bs=4 iseek=48 count=1 2>/dev/null`
			[ "$_dt" = UNI ] && _n=`expr $_n + 1`
		fi
		_b=`expr $_b + 1`
	done
	rm -f /tmp/.l11b
	echo "$_n"
}

# l11_mkfs_data -- the data slice's filesystem (install.sh added and stamped s4)
l11_mkfs_data()
{
	if [ "$DATALEN" -le 0 ]; then
		msg "data slice   : none laid (TARGET_DATA_MB=${TARGET_DATA_MB:-default} on a ${DISK_MB}MB disk)"
		return 0
	fi
	if [ "$TARGET_ROOT_FSTYPE" = ufs ]; then
		run /bin/mkfs_ufs -o free=2,opt=s "/dev/dsk/c${ID}d0s4" "$DATALEN"
	else
		run /bin/mkfs_s5 "/dev/rdsk/c${ID}d0s4" "$DATALEN"
		run /usr/lib/fs/s5/labelit "/dev/rdsk/c${ID}d0s4" home DATA
	fi
	msg "data slice   : s4 ${DATA_MB}MB $TARGET_ROOT_FSTYPE, /home"
}

# l11_check_layout -- after authoring: exactly one UNI\0 on the disk (gate 9's rule)
l11_check_layout()
{
	_u=`l11_uni0_count "$DISK_RAW"`
	[ "$_u" = 1 ] || die "the authored disk carries $_u UNI\\0 partitions, not exactly one -- kbootset would refuse it (gate 9)"
	msg "layout check : exactly one UNI\\0 partition (s$TARGET_BOOT_SLICE, the boot store)"
}

# l11_bootset MODE -- write $TARGET/etc/default/bootset (C2-4 §6), bootset=MODE
l11_bootset()
{
	[ -d "$TARGET/etc/default" ] || run mkdir -p "$TARGET/etc/default"
	{
		echo "# /etc/default/bootset -- read by kbootset and apkg (40 §2.2, §5; C2-4 §6)"
		echo "# written by install.sh; kbootset rewrites only store= and store-id="
		echo "bootset=$1"
		echo "store=$BOOT_RAW"
		echo "store-id=$L11_STORE_ID"
		echo "line=$L11_LINE"
		echo "bootdev=$KBOOTSET_BOOTDEV"
		echo "rootdev=$KBOOTSET_ROOTDEV"
		echo "rootfs=$TARGET_ROOT_FSTYPE"
		echo "mem=$L11_MEM"
	} > "$TARGET/etc/default/bootset" || die "cannot write $TARGET/etc/default/bootset"
}

# l11_bootstore -- the kernel package in, then the store laid, the pristine
# generation built and committed, and the whole store checked. Replaces 1.0's
# sections 6-8c (boot2.boot, the chain dd, the sum -r verify, /stand/unix, RTO1).
l11_bootstore()
{
	stage ""
	stage "Installing the kernel and writing the boot store."
	run mkdir -p "$TARGET/var/kbootset"
	# bootset=manual while the kernel package goes in: apkg's trigger then only
	# prints the commands, and the store is composed below with the facts named
	l11_bootset manual
	KCONF="$TARGET/tmp/kpkg.conf"
	{
		echo "# apkg 0.3, the medium's kernel-space source -- written by install.sh (1.1)"
		echo "repo=file://$L11/kpkg"
		echo "cachedir=$TARGET/tmp/kpkgcache"
		echo "admin=$INST/admin/pkgadd"
		echo "pkgadd=$INST/bin/pkgadd"
		echo "kbootset=$L11_KB"
	} > "$KCONF" || die "cannot write $KCONF"
	run "$L11_APKG" -c "$KCONF" update
	l11_apkg -c "$KCONF" -R "$TARGET" install "$KERNEL_KPKG"
	[ -f "$TARGET/var/apkg/kpkg/$KERNEL_KPKG" ] || die "apkg installed $KERNEL_KPKG but wrote no record /var/apkg/kpkg/$KERNEL_KPKG -- kbootset gate 1 would refuse"
	msg "kernel package $KERNEL_KPKG installed; record /var/apkg/kpkg/$KERNEL_KPKG"

	KB="$L11_KB -R $TARGET --dev $BOOT_RAW --journal $TARGET/var/kbootset/journal"
	# whatever was in the slice (a 1.0 chain, an old store, a 1.0 root's tail) is gone
	# from the store's own area before kbootset lays it
	run dd if=/dev/zero of="$BOOT_RAW" bs=512 count=128
	run "$L11_KB" --dev "$BOOT_RAW" create "$L11_STORE_BYTES" "$L11/loader/boot2" --boot1 "$L11/loader/boot1"
	l11_kb build --line "$L11_LINE" --bootdev "$KBOOTSET_BOOTDEV" --rootdev "$KBOOTSET_ROOTDEV" \
		--rootfs "$TARGET_ROOT_FSTYPE" --mem "$L11_MEM" --root "$KBOOTSET_ROOTREC"
	l11_kb commit
	run sync
	# the post-write proof: every member's SHA-256 and CRC-32 against its manifest,
	# the generation against apkg's record; kbootset never writes in `check`
	l11_kb check
	runq $KB status

	# /dev/kinfo (amix-dlm C2-3 v3 §1, C2-4 v4 §2): kernel-space packages are pure
	# files, so the node is the installer's: c 53 0, 0444. The miniroot has no chown or
	# chgrp; the node is root's already, and first boot gives it group sys.
	[ -d "$TARGET/dev" ] || run mkdir -p "$TARGET/dev"
	rm -f "$TARGET/dev/kinfo"
	run /bin/mknod "$TARGET/dev/kinfo" c 53 0
	run chmod 0444 "$TARGET/dev/kinfo"
	# the installed box gets the same kbootset (a driver-written file until the
	# kbootset package exists, C2-3 §4) and the final bootset file
	run cp "$L11_KB" "$TARGET/sbin/kbootset"
	run chmod 0755 "$TARGET/sbin/kbootset"
	# updbootpart would frame a 1.0 chain over the store: on this disk it is the shim
	# that refuses and names kbootset (spec 40 §2.2, P-28 D54)
	[ -d "$TARGET/usr/sbin" ] || run mkdir -p "$TARGET/usr/sbin"
	run cp "$L11/updbootpart" "$TARGET/usr/sbin/updbootpart"
	run chmod 0755 "$TARGET/usr/sbin/updbootpart"
	l11_bootset auto
	rm -rf "$TARGET/tmp/kpkgcache" "$KCONF"
	msg "boot store   : pristine generation committed on $BOOT_RAW and checked; /sbin/kbootset, /etc/default/bootset, /dev/kinfo and the updbootpart shim laid"
}

# l11_kb ARGS -- one kbootset call on the target's store; any status but 0 stops
# the install before anything is armed (C2-4 §1: 1 I/O, 2 usage, 3 rule, 4 gate)
l11_kb()
{
	runq $KB "$@"
	_rc=$?
	case "$_rc" in
		0)	return 0 ;;
		4)	die "kbootset $1 refused at a gate (status 4) -- the disk has no bootable generation; NOT arming" ;;
		3)	die "kbootset $1 refused by a rule (status 3) -- the disk has no bootable generation; NOT arming" ;;
		*)	die "kbootset $1 failed (status $_rc) -- the disk has no bootable generation; NOT arming" ;;
	esac
}

# l11_apkg ARGS -- apkg 0.3 for the kernel-space install; a failure stops the install
l11_apkg()
{
	runq "$L11_APKG" "$@"
	_rc=$?
	[ "$_rc" = 0 ] || die "apkg $* failed (rc=$_rc) -- refusing to arm a half-installed disk"
	return 0
}

