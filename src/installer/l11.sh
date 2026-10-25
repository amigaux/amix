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
#   recover.conf   apkg's conf for `apkg -R /mnt recover` from the repair path
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
	case "${INSTALL_UPGRADE:-no}" in
		yes|no)	: ;;
		*)	die "profile INSTALL_UPGRADE='$INSTALL_UPGRADE' is not yes or no" ;;
	esac
	[ "${INSTALL_UPGRADE:-no}" = yes ] && [ "${FIRSTBOOT_DIALOG:-n}" = y ] \
		&& warn "INSTALL_UPGRADE=yes with FIRSTBOOT_DIALOG=y: the dialog's answers are replaced by the saved configuration at the first boot"
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

# l11_keep_layout -- an upgrade of a 1.1 disk: its RDB stays as it is. The root is
# re-made over slice 1's own extent, the store is checked to be the 64 MiB s3, and a
# data slice s4 is kept with its filesystem untouched.
l11_keep_layout()
{
	l11_rdbpart 1; ROOT_OFF=$_po ROOTLEN=$_pl
	l11_rdbpart 2; SWAP_OFF=$_po SWAPLEN=$_pl
	l11_rdbpart 3
	[ "$_pn" = UNIX_Boot ] && [ "$_pl" = `expr "$L11_STORE_MB" \* "$BLOCKS_PER_MB"` ] \
		|| die "upgrade: slice 3 of c${ID}d0 is '$_pn', $_pl blocks -- not the ${L11_STORE_MB} MiB store of a 1.1 disk"
	BOOT_OFF=$_po BOOTLEN=$_pl
	DATALEN=0 DATA_KEEP=
	l11_rdbpart 4
	if [ "$_pn" = UNIX_Data ]; then DATA_OFF=$_po DATALEN=$_pl DATA_KEEP=y; fi
	is_num "$ROOTLEN" || die "upgrade: slice 1 of c${ID}d0 has no readable length"
	l11_check_layout
	msg "upgrade: the 1.1 layout is kept: root s1 ($ROOTLEN blocks) re-made, swap s2, store s3 re-written"
	[ -n "$DATA_KEEP" ] && msg "upgrade: the data slice s4 ($DATALEN blocks) is kept as it is"
	return 0
}

# l11_mkfs_data -- the data slice's filesystem (install.sh added and stamped s4)
l11_mkfs_data()
{
	if [ -n "$DATA_KEEP" ]; then
		msg "data slice   : s4 kept (upgrade install), its filesystem untouched"
		return 0
	fi
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

# l11_txn_pending -- apkg 0.3's transaction journal on the target (C2-2; apkg's
# /var/apkg/txn): while it exists the next install is blocked and the package set may
# be half-installed, so the disk is never armed over it
l11_txn_pending()
{
	[ -f "$TARGET/var/apkg/txn" ] || return 1
	warn "apkg: a transaction is pending on the target ($TARGET/var/apkg/txn):"
	cat "$TARGET/var/apkg/txn"
	return 0
}

# l11_apkg ARGS -- apkg 0.3 for the kernel-space install. Its exit status decides:
#   0  done (and no journal may be left behind)
#   6  kbootset failed after the packages went in; the journal is KEPT for recover
#   7  kbootset refused (a rule or a gate); the committed generation is unchanged
#   *  anything else: the transaction failed (5 = pre-flight refused, nothing staged)
# Every non-zero status stops the install unarmed and says how to finish the
# transaction: the repair path, then `apkg -R /mnt recover` from this medium.
L11_RECOVER="boot this medium, choose repair, mount the install CD at /cdrom and run: /cdrom/install/l11/bin/apkg -c /cdrom/install/l11/recover.conf -R /mnt recover"
l11_apkg()
{
	l11_txn_pending && die "apkg: a pending transaction blocks the kernel-space install -- NOT arming. To finish it: $L11_RECOVER"
	runq "$L11_APKG" "$@"
	_rc=$?
	case "$_rc" in
		0)	l11_txn_pending && die "apkg $* returned 0 but left its journal -- NOT arming. To finish it: $L11_RECOVER"
			return 0 ;;
		6)	die "apkg $* exit 6: kbootset failed after the packages went in; the journal is kept -- NOT arming. To finish it: $L11_RECOVER" ;;
		7)	die "apkg $* exit 7: kbootset refused it; the committed generation is unchanged -- NOT arming" ;;
		*)	l11_txn_pending
			die "apkg $* failed (rc=$_rc) -- refusing to arm a half-installed disk. If a journal is listed above, to finish it: $L11_RECOVER" ;;
	esac
}

# ===========================================================================
# THE UPGRADE INSTALL (INSTALL_UPGRADE=yes; amix-dlm spec 40 §7, D-3 §5)
# ===========================================================================
# The target already holds Amix. What survives (docs/upgrade-install.md):
#   * the configuration set L11_KEEP below, captured from the old root, restored into
#     /var/adm/upgrade/cfg and checked file by file before the first boot, then put in
#     place once by /etc/rc2.d/S17upgrade at the first boot, after first-boot's own
#     identity steps (so the old box's identity wins);
#   * /home: on a 1.0 disk (no data slice) captured with the configuration and
#     restored into the new /home; on a 1.1 disk the data slice s4 is not touched.
#   * nothing else: the installed packages are the medium's set again, and any other
#     file on the old root is gone.
# The capture is one cpio archive (relative names) written to the OLD swap slice
# before anything is re-laid -- swap is scratch during an install -- with a header
# `AMIXUPG1 <blocks> <sum -r> <home y|n>` in that slice's last block. It is read back
# through the whole-disk node at the old slice's absolute block, so a new RDB does not
# lose it; the new root, swap and data slices must not overlap it (checked before the
# first write), and on a 1.0 disk only the new boot store does, which is written after
# the restore. On a 1.1 disk the layout is kept and s2 is both the stash and the swap:
# no swap is added until the restore is done.
L11_KEEP="etc/nodename etc/domain etc/TIMEZONE etc/TZ etc/tz.index etc/clkzone
etc/passwd etc/shadow etc/group etc/default/login
etc/inet/hosts etc/inet/rc.inet etc/inet/zen.conf etc/resolv.conf etc/netconfig
etc/rc2.d/S99zen etc/apkg.conf"

# l11_rdbpart N -- _pn _po _pl: name, start, length of partition N (empty if none)
l11_rdbpart()
{
	_pn= _po= _pl=
	/etc/rdb -p "$1" "$DISK_RAW" > /tmp/.l11p 2>/dev/null
	if [ -s /tmp/.l11p ]; then
		set x `cat /tmp/.l11p`; shift
		_pn=$1 _po=$2 _pl=$3
	fi
	rm -f /tmp/.l11p
}

# l11_upgrade_capture -- before the first write: what is installed, what survives,
# and the archive written to the old swap slice
l11_upgrade_capture()
{
	stage ""
	stage "Upgrade install: saving the configuration of the installed system."
	_np=`/etc/rdb -h 5 "$DISK_RAW" 2>/dev/null`
	is_num "$_np" || die "INSTALL_UPGRADE=yes but c${ID}d0 carries no readable RDB -- nothing to upgrade"
	l11_rdbpart 1; [ "$_pn" = UNIX_Root ] || die "INSTALL_UPGRADE=yes but slice 1 of c${ID}d0 is '$_pn', not UNIX_Root -- not an Amix disk this installer laid"
	l11_rdbpart 2; [ "$_pn" = UNIX_Swap ] || die "INSTALL_UPGRADE=yes but slice 2 of c${ID}d0 is '$_pn', not UNIX_Swap"
	OLD_SWAP_OFF=$_po OLD_SWAP_LEN=$_pl
	_m=`dd if="/dev/rdsk/c${ID}d0s3" bs=512 iseek=2 count=1 2>/dev/null | dd bs=4 count=1 2>/dev/null`
	OLD_DATA=n
	case "$_m" in
		AXS1)	UPGRADE_KIND=1.1
			l11_rdbpart 4
			[ "$_pn" = UNIX_Data ] && OLD_DATA=y ;;
		*)	UPGRADE_KIND=1.0 ;;
	esac
	msg "upgrade      : an installed $UPGRADE_KIND disk (data slice: $OLD_DATA); swap slice @blk$OLD_SWAP_OFF, $OLD_SWAP_LEN blocks"

	# a 1.0 disk is re-laid: the stash must lie outside the new root, swap and data
	if [ "$UPGRADE_KIND" = 1.0 ]; then
		_se=`expr "$OLD_SWAP_OFF" + "$OLD_SWAP_LEN"`
		[ "$_se" -le "$ROOT_OFF" ] || [ "$OLD_SWAP_OFF" -ge "$BOOT_OFF" ] \
			|| die "upgrade: the old swap slice (blk $OLD_SWAP_OFF-$_se) overlaps the new root or swap (blk $ROOT_OFF-$BOOT_OFF) -- the saved configuration would be overwritten"
		if [ "$DATALEN" -gt 0 ]; then
			_de=`expr "$DATA_OFF" + "$DATALEN"`
			[ "$_se" -le "$DATA_OFF" ] || [ "$OLD_SWAP_OFF" -ge "$_de" ] \
				|| die "upgrade: the old swap slice overlaps the new data slice -- the saved configuration would be overwritten"
		fi
	else
		SWAP_HOLD=y
	fi

	OLD_FS=
	for _fs in ufs s5
	do
		if /etc/mount "/dev/dsk/c${ID}d0s1" /mnt 1 $_fs > /dev/null 2>&1; then OLD_FS=$_fs; break; fi
	done
	[ -n "$OLD_FS" ] || die "upgrade: the installed root c${ID}d0s1 does not mount read-only (ufs or s5) -- check it in repair mode first"
	for _t in /usr/sbin/chroot /usr/bin/find /usr/bin/cpio /usr/bin/du /usr/bin/sum /bin/sh
	do
		[ -x "/mnt$_t" ] || { /etc/umount /mnt; die "upgrade: the installed root has no $_t to save itself with"; }
	done
	cp /dev/null /tmp/upg.list
	for _f in $L11_KEEP
	do
		[ -f "/mnt/$_f" ] && echo "$_f" >> /tmp/upg.list
	done
	UPG_HOME=n
	if [ "$OLD_DATA" = n ] && [ -d /mnt/home ]; then
		set x `/mnt/usr/sbin/chroot /mnt /usr/bin/du -s /home 2>/dev/null`; shift
		_hb="$1"
		is_num "$_hb" || _hb=0
		_hmb=`expr "$_hb" / 2048`
		_cap=`expr "$OLD_SWAP_LEN" - 2048`
		if [ "${UPGRADE_DROP_HOME:-no}" = yes ]; then
			warn "upgrade: /home (${_hmb} MB, on the root) is NOT kept: UPGRADE_DROP_HOME=yes"
		elif [ "$_hb" -gt "$_cap" ]; then
			/etc/umount /mnt
			die "upgrade: /home is ${_hmb} MB ($_hb blocks) and the swap slice holds $_cap -- it cannot be saved there. Move it off the disk, or set UPGRADE_DROP_HOME=yes to reinstall without it."
		else
			UPG_HOME=y
			msg "upgrade: /home (${_hmb} MB, $_hb blocks) is saved with the configuration"
		fi
	fi
	msg "upgrade: NOT kept: every installed package beyond the medium's set, and every other file on the old root"
	# the archive, by the installed system's own find and cpio
	/mnt/usr/sbin/chroot /mnt /bin/sh -c "cd / && { cat; if [ $UPG_HOME = y ]; then /usr/bin/find home -print; fi; } | /usr/bin/cpio -oc" \
		< /tmp/upg.list > "/dev/dsk/c${ID}d0s2" 2> /tmp/upg.err
	_rc=$?
	UPG_NBLK=`( while read _a _b _r; do [ "$_b" = blocks ] && echo "$_a"; done ) < /tmp/upg.err`
	is_num "$UPG_NBLK" || _rc=99
	if [ "$_rc" != 0 ]; then
		cat /tmp/upg.err
		/etc/umount /mnt
		die "upgrade: writing the configuration archive failed (rc=$_rc) -- nothing has been changed on the disk but its swap slice"
	fi
	# the configuration files' own sums, for the check after the restore
	cp /dev/null /tmp/upg.sums
	while read _f
	do
		set x `/mnt/usr/sbin/chroot /mnt /usr/bin/sum -r "/$_f"`; shift
		echo "$1 $2 $_f" >> /tmp/upg.sums
	done < /tmp/upg.list
	/etc/umount /mnt
	run sync
	UPG_SUM=`dd if="/dev/rdsk/c${ID}d0s2" bs=512 count="$UPG_NBLK" 2>/dev/null | "$INST/bin/sum" -r | ( read _s _r; echo "$_s" )`
	is_num "$UPG_SUM" || die "upgrade: the configuration archive does not read back from the swap slice"
	echo "AMIXUPG1 $UPG_NBLK $UPG_SUM $UPG_HOME" > /tmp/upg.hdr
	_hl=`expr "$OLD_SWAP_LEN" - 1`
	dd if=/tmp/upg.hdr of="/dev/dsk/c${ID}d0s2" bs=512 oseek="$_hl" count=1 conv=sync 2>/dev/null
	run sync	# both writes are on the disk before its RDB changes
	set x `cat /tmp/upg.list`; shift
	msg "upgrade: saved $# configuration file(s) + home=$UPG_HOME: $UPG_NBLK blocks, sum -r $UPG_SUM, at disk blk $OLD_SWAP_OFF (header in its last block $_hl)"
	msg "upgrade: kept: $*"
}

# l11_upgrade_restore -- after the base OS is in, before the store is written:
# /home into place, the configuration into /var/adm/upgrade/cfg, every file checked
l11_upgrade_restore()
{
	stage ""
	stage "Upgrade install: restoring the saved configuration."
	_got=`dd if="$DISK_RAW" bs=512 iseek="$OLD_SWAP_OFF" count="$UPG_NBLK" 2>/dev/null | "$INST/bin/sum" -r | ( read _s _r; echo "$_s" )`
	[ "$_got" = "$UPG_SUM" ] || die "upgrade: the saved archive reads back as sum -r '$_got', not $UPG_SUM -- NOT restoring and NOT arming (the archive is at disk blk $OLD_SWAP_OFF, $UPG_NBLK blocks)"
	if [ "$UPG_HOME" = y ]; then
		_hm=
		if [ "$DATALEN" -gt 0 ]; then
			[ -d "$TARGET/home" ] || run mkdir "$TARGET/home"
			run /etc/mount "/dev/dsk/c${ID}d0s4" "$TARGET/home" 0 "$TARGET_ROOT_FSTYPE"
			_hm=y
		fi
		( cd "$TARGET" && dd if="$DISK_RAW" bs=512 iseek="$OLD_SWAP_OFF" count="$UPG_NBLK" 2>/dev/null \
			| /bin/cpio -icdmu 'home' 'home/*' ) > /tmp/upg.err 2>&1 || { cat /tmp/upg.err; die "upgrade: restoring /home failed"; }
		[ -n "$_hm" ] && run /etc/umount "$TARGET/home"
		if [ -n "$_hm" ]; then msg "upgrade: /home restored into the data slice s4"; else msg "upgrade: /home restored onto the root"; fi
	fi
	run mkdir -p "$TARGET/var/adm/upgrade/cfg"
	( cd "$TARGET/var/adm/upgrade/cfg" && dd if="$DISK_RAW" bs=512 iseek="$OLD_SWAP_OFF" count="$UPG_NBLK" 2>/dev/null \
		| /bin/cpio -icdmu 'etc/*' ) > /tmp/upg.err 2>&1 || { cat /tmp/upg.err; die "upgrade: restoring the configuration failed"; }
	cp /dev/null /tmp/upg.bad
	while read _s _n _f
	do
		set x `"$INST/bin/sum" -r "$TARGET/var/adm/upgrade/cfg/$_f"`; shift
		[ "$1" = "$_s" ] || echo "$_f" >> /tmp/upg.bad
	done < /tmp/upg.sums
	[ -s /tmp/upg.bad ] && die "upgrade: restored file(s) differ from the saved ones: `cat /tmp/upg.bad` -- NOT arming"
	run cp /tmp/upg.sums "$TARGET/var/adm/upgrade/SUMS"
	run cp /tmp/upg.hdr "$TARGET/var/adm/upgrade/HEADER"
	: > "$TARGET/var/adm/upgrade/PENDING"
	{
		echo '#!/bin/sh'
		echo '# S17upgrade -- written by install.sh (an upgrade install). Puts the saved'
		echo '# configuration in place once, after S16firstboot, so the old identity wins.'
		echo 'U=/var/adm/upgrade'
		echo 'case $1 in start) ;; *) exit 0 ;; esac'
		echo '[ -f $U/PENDING ] || exit 0'
		echo 'cd $U/cfg || exit 0'
		echo '# a redirect-fed loop is a subshell on this sh: the misses go to a file'
		echo 'rm -f $U/BAD'
		echo 'while read s n f; do'
		echo '	set x `sum -r $f`; shift'
		echo '	[ "$1" = "$s" ] || echo "$f" >> $U/BAD'
		echo 'done < $U/SUMS'
		echo 'if [ -s $U/BAD ]; then echo "upgrade: saved file(s) changed since the install, NOT applied:" `cat $U/BAD`; exit 0; fi'
		echo 'find . -print | cpio -pdmu / 2>/dev/null'
		echo '[ -s /etc/nodename ] && uname -S `cat /etc/nodename`'
		echo 'rm -f $U/PENDING'
		echo 'echo "upgrade: the previous configuration is in place (`wc -l < $U/SUMS` files; $U)"'
	} > "$TARGET/etc/rc2.d/S17upgrade" || die "cannot write $TARGET/etc/rc2.d/S17upgrade"
	run chmod 0744 "$TARGET/etc/rc2.d/S17upgrade"
	set x `cat /tmp/upg.sums`; shift
	_nf=`expr $# / 3`
	msg "upgrade: $_nf configuration file(s) restored to /var/adm/upgrade/cfg and checked; S17upgrade applies them at the first boot"
	rm -f /tmp/upg.list /tmp/upg.sums /tmp/upg.err /tmp/upg.bad
}
