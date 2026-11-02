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
#   bin/apkg       apkg 0.3, static, FILE+RAW (amix userland/pkgtools)
#   kpkg/catalog kpkg/pkgs/...   the FILE source: the packages kbootset (userland) and
#                  loader-amix and the kernel (kernel space, the #ext kpkg 1 block), as
#                  amix-packages mints them. They are installed like any package, so the
#                  box carries their records and `apkg upgrade` reaches all three; the
#                  store is laid by the INSTALLED /sbin/kbootset from the INSTALLED
#                  /stand/loader files -- one copy of each, the package's.
#   updbootpart    the shim laid at /usr/sbin/updbootpart (payload/updbootpart-l11)
#   recover.conf   apkg's conf for `apkg -R /mnt recover` from the repair path
#   bcheckrc bcheckrc.stock   /sbin/bcheckrc with `kbootset retry` before each root
#                  fsck reboot (C2-4 v5 §7), and the stock file's `sum -r`
#   inittab        amix-base's /etc/inittab (it carries C3-5 §5's dlm line before its first
#                  sysinit entry): what the target holds once amix-base is in
#   base/          the userland packages added after core: order (the pkginsts every set
#                  takes, in order), o.<set> (the ones only that set takes), each
#                  <pkginst>.pkg, <pkginst>.cf (its pkgmap's `e conffile` paths; s5-safe names)
#                  and seed.sh (payload/l11-seed.sh)
#   2.1_unix.sum   the `sum -r` of core's /stand/2.1_unix, which stays when the name
#                  /stand/unix goes (C2-4 v9 §12)
#
# PROFILE KEYS:
#   INSTALL_LAYOUT=1.1   this file; 1.0 (the default) never sources it
#   KERNEL_KPKG          the kernel package's catalog name (kernel-k30-m, ...). A module
#                        kernel (its row's kabi= is not static; its sidecar has arena=)
#                        brings modtools into the same transaction
#   KERNEL_MODPKGS       the module packages, catalog names <name>-<line> (z3660eth-k46;
#                        C3-5 v4 §1.1), installed in the same transaction; a module
#                        kernel only
#   TARGET_FASTMEM_MB    fast memory of the box that will BOOT this disk (not of the
#                        machine running the install: a bench rig and a disk moved
#                        between boxes differ), for gate 6 and bootset's mem=. The
#                        miniroot cannot measure it (its kernel has no kinfo), so a
#                        profile states it; on a kinfo kernel kinfo wins at run time
#   TARGET_DATA_MB       the data slice in MB; 0 = none; empty = the spec's default
#   KBOOTSET_BOOTDEV KBOOTSET_ROOTDEV   match keys; derived from TARGET_HBA when empty
#   KBOOTSET_ROOTREC     the manifest's root record; derived from the root key when empty

L11=$INST/l11
L11_APKG=$L11/bin/apkg
# the kernel-space catalog: the medium's, or on the netinstall medium the one net_source
# read over HTTP (and kernel space over HTTP with the image's HTTP apkg)
L11_KCAT=$L11/kpkg/catalog
if [ "$SRC_KIND" = net ]; then
	L11_APKG=$INST/bin/apkg
	L11_KCAT=/tmp/netk/catalog
fi
L11_BASE_KPKGS="kbootset loader-amix"	# installed with the kernel, every 1.1 disk
L11_DLM='dlm::sysinit:/sbin/modadmin -B </dev/console >/dev/console 2>&1'	# C3-5 §5
L11_STORE_MB=64
L11_STORE_BYTES=67108864

# l11_keys -- validate the 1.1 keys and derive the box facts. Called once, right
# after the profile is loaded.
l11_keys()
{
	for _f in "$L11_APKG" "${L11_KCAT:-$L11/kpkg/catalog}" "$L11/updbootpart" \
		"$L11/bcheckrc" "$L11/bcheckrc.stock" "$L11/inittab" "$L11/2.1_unix.sum"
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
	# the kernel and the modules: rows of the medium's catalog, of this line
	[ "`l11_kpkg_key "$KERNEL_KPKG" role`" = kernel ] || die "KERNEL_KPKG=$KERNEL_KPKG is not a kernel package of the medium's catalog"
	[ "`l11_kpkg_key "$KERNEL_KPKG" line`" = "k$L11_LINE" ] || die "KERNEL_KPKG=$KERNEL_KPKG is not a k$L11_LINE kernel (INSTALL_CPU=$INSTALL_CPU)"
	L11_KMOD=n L11_MODS= L11_XPKGS= L11_SDCARDS=2
	[ "`l11_kpkg_key "$KERNEL_KPKG" kabi`" = static ] || L11_KMOD=y L11_XPKGS=modtools
	if [ -n "$KERNEL_MODPKGS" ] && [ "$L11_KMOD" = n ]; then
		die "KERNEL_MODPKGS='$KERNEL_MODPKGS' needs a module kernel; $KERNEL_KPKG is static"
	fi
	for _m in $KERNEL_MODPKGS
	do
		[ "`l11_kpkg_key "$_m" role`" = module ] || die "KERNEL_MODPKGS: $_m is not a module package of the medium's catalog"
		[ "`l11_kpkg_key "$_m" line`" = "k$L11_LINE" ] || die "KERNEL_MODPKGS: $_m is not a k$L11_LINE module"
		_o=`expr "$_m" : "\\(.*\\)-k$L11_LINE\$"`
		[ -n "$_o" ] || die "KERNEL_MODPKGS: $_m is not named <module>-k$L11_LINE (C3-5 section 1.1)"
		L11_MODS="$L11_MODS $_o"
	done
	# the controller from the disk the user picked: the medium's kbootset reads the running
	# kernel's sd card table (`kbootset cards DISK`, C2-1); a key it names wins over the
	# profile's TARGET_HBA, which stays the fallback for a medium or kernel that cannot say
	# L11_CTL says where the key came from; l11_bootstore logs it (the install log is not open yet here)
	L11_CTL="the profile's KBOOTSET_BOOTDEV"
	if [ -z "$KBOOTSET_BOOTDEV" ] && [ -x "$L11/bin/kbootset" ]; then
		# one line either way: the key on standard output, or why not on standard error
		_k=`"$L11/bin/kbootset" cards "/dev/dsk/c${TARGET_SCSI_ID}d0s${TARGET_ROOT_SLICE}" 2>&1`
		set -- $_k
		# the interview took the IDE port's card from the same table: the disk's key must be
		# the IDE's (kbootset -34 and earlier read c10-c17 as card 1 and named its controller)
		if [ -n "$IDE_CARD" ] && [ "$1" != mobo:gayle ]; then
			die "kbootset cards names '$1' for the IDE master c${TARGET_SCSI_ID}d0 (IDE card $IDE_CARD): this medium's kbootset misreads the card (kbootset -35 reads c10-c17)"
		fi
		case "$1" in
			mobo:?*|zorro:?*:?*)
				KBOOTSET_BOOTDEV="$1"
				L11_CTL="kbootset cards: the target disk's own card; profile TARGET_HBA=$TARGET_HBA" ;;
			*)	L11_CTL="the profile's TARGET_HBA=$TARGET_HBA; kbootset cards: ${_k:-no answer}" ;;
		esac
		msg "controller   : ${KBOOTSET_BOOTDEV:-from TARGET_HBA} ($L11_CTL)"
	elif [ -z "$KBOOTSET_BOOTDEV" ]; then
		L11_CTL="the profile's TARGET_HBA=$TARGET_HBA; the medium has no kbootset for cards"
	fi
	if [ -z "$KBOOTSET_BOOTDEV" ]; then
		case "$TARGET_HBA" in
			a3000)		KBOOTSET_BOOTDEV=mobo:a3000-wd ;;
			z3660scsi)	KBOOTSET_BOOTDEV=zorro:144b:01 ;;
			a4091)		KBOOTSET_BOOTDEV=zorro:0202:54 ;;
			a4092)		KBOOTSET_BOOTDEV=zorro:c0de:01 ;;
			gayle)		KBOOTSET_BOOTDEV=mobo:gayle ;;
			# the onboard 53C710 Kickstart boots through its ROM's NCR scsi.device;
			# a4kt710's match key (C4-2 sec 8, C4-1 sec 5.2: motherboard id 3)
			a4000t|a4kt710)	KBOOTSET_BOOTDEV=mobo:a4000t-710 ;;
			*)		die "INSTALL_LAYOUT=1.1: no controller key known for TARGET_HBA='$TARGET_HBA'; set KBOOTSET_BOOTDEV" ;;
		esac
	fi
	[ -n "$KBOOTSET_ROOTDEV" ] || KBOOTSET_ROOTDEV="$KBOOTSET_BOOTDEV"
	# the root record (amix-dlm 10 §5.1): a Zorro board by its id, manufacturer<<16 |
	# product<<8; a motherboard controller by the `mobo` flag with id and base 0
	if [ -z "$KBOOTSET_ROOTREC" ]; then
		# the record's unit is the SCSI unit, card*8 + unit's low three bits (C4-1 §2.2: the
		# controller is named by identity, never by its card number)
		_u=`expr "$TARGET_SCSI_ID" : '.*\(.\)$'`
		case "$_u" in
			[0-7])	;;
			8) _u=0 ;; 9) _u=1 ;; a|A) _u=2 ;; b|B) _u=3 ;; c|C) _u=4 ;; d|D) _u=5 ;; e|E) _u=6 ;; f|F) _u=7 ;;
			*)	die "TARGET_SCSI_ID='$TARGET_SCSI_ID' is not a controller number" ;;
		esac
		case "$KBOOTSET_ROOTDEV" in
			zorro:*:*)
				_m=`expr "$KBOOTSET_ROOTDEV" : 'zorro:\([0-9a-fA-F]*\):'`
				_p=`expr "$KBOOTSET_ROOTDEV" : 'zorro:[0-9a-fA-F]*:\([0-9a-fA-F]*\)$'`
				KBOOTSET_ROOTREC="sd id=${_m}${_p}00 base=00000000 unit=$_u slice=$TARGET_ROOT_SLICE" ;;
			mobo:*)	KBOOTSET_ROOTREC="sd id=00000000 base=00000000 unit=$_u slice=$TARGET_ROOT_SLICE mobo" ;;
			*)	die "KBOOTSET_ROOTDEV='$KBOOTSET_ROOTDEV' is not a zorro: or mobo: match key" ;;
		esac
	fi
	msg "layout 1.1   : store ${L11_STORE_MB} MiB (s$TARGET_BOOT_SLICE), kernel package $KERNEL_KPKG, line k$L11_LINE"
	[ "$L11_KMOD" = y ] && msg "modules      : a module kernel: modtools $KERNEL_MODPKGS"
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
	# the ufs ceiling, 4194303 blocks (2047 MiB): mkfs of 2048 MiB fails at the driver's raw-I/O
	# clamp, 3072 MiB at a 32-bit seek (measured 2026-10-31; spec 40 §2.1's 1024 was the
	# 1.0 figure), and a stock kernel's own cap
	if [ "$DATA_MB" -gt 2047 ]; then DATA_MB=2047; fi
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
	run /bin/mkfs_ufs -o `ufs_mkfs_opts "$DATALEN"` "/dev/dsk/c${ID}d0s4" "$DATALEN"
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
	# bootset=manual while the packages go in: apkg's trigger then only prints the
	# commands, so neither the loader nor the kernel package commits anything, and the
	# store gets exactly one generation, the pristine one, composed below. Its store-id=
	# is filled in once the store exists.
	L11_STORE_ID=
	l11_bootset manual
	KCONF="$TARGET/tmp/kpkg.conf"
	{
		echo "# apkg 0.3, the medium's kernel-space source -- written by install.sh (1.1)"
		if [ "$SOURCE_KIND" = net ]; then echo "repo=$NET_KREPO"; else echo "repo=file://$L11/kpkg"; fi
		echo "cachedir=$TARGET/tmp/kpkgcache"
		echo "admin=$INST/admin/pkgadd"
		echo "pkgadd=$INST/bin/pkgadd"
		echo "kbootset=$TARGET/sbin/kbootset"
	} > "$KCONF" || die "cannot write $KCONF"
	run "$L11_APKG" -c "$KCONF" update
	# one transaction: kbootset, the loader, the kernel; for a module kernel modtools and
	# the module packages too
	l11_apkg -c "$KCONF" -R "$TARGET" install $L11_BASE_KPKGS $L11_XPKGS "$KERNEL_KPKG" $KERNEL_MODPKGS
	l11_kpkg_record loader-amix loader
	l11_kpkg_record "$KERNEL_KPKG" kernel
	for _m in $KERNEL_MODPKGS
	do
		l11_kpkg_record "$_m" module
	done
	[ -f "$TARGET/var/sadm/pkg/kbootset/pkginfo" ] || die "apkg installed kbootset but the package database has no kbootset"
	_ka=`( while read _l; do case "$_l" in arena=*) echo y ;; esac; done ) < "$TARGET/stand/k$L11_LINE/kabi"`
	[ "${_ka:-n}" = "$L11_KMOD" ] || die "the catalog and /stand/k$L11_LINE/kabi disagree on whether $KERNEL_KPKG is a module kernel (arena= ${_ka:-absent})"
	# the kernel's sd cards (C4-1; the sidecar's sdcards=4, absent = 2): a four-card
	# kernel reads minor bit 7 as the card's high bit, so firstboot swaps core's d1 nodes
	# for the c10-c1f nodes
	_sc=`( while read _l; do case "$_l" in sdcards=*) expr "$_l" : 'sdcards=\(.*\)' ;; esac; done ) < "$TARGET/stand/k$L11_LINE/kabi"`
	L11_SDCARDS=${_sc:-2}
	case "$L11_SDCARDS" in 2|4) ;; *) die "/stand/k$L11_LINE/kabi says sdcards=$L11_SDCARDS, not 2 or 4" ;; esac
	if [ "$L11_KMOD" = y ]; then
		[ -f "$TARGET/var/sadm/pkg/modtools/pkginfo" ] && [ -x "$TARGET/sbin/modadmin" ] \
			|| die "apkg installed modtools but there is no /sbin/modadmin or no modtools in the package database"
		l11_inittab
	fi
	msg "packages     : `echo $L11_BASE_KPKGS $L11_XPKGS $KERNEL_KPKG $KERNEL_MODPKGS` installed by apkg (records under /var/apkg/kpkg)"
	msg "sd cards     : $L11_SDCARDS (the kernel's sidecar, C4-1)"
	msg "controller   : $KBOOTSET_BOOTDEV ($L11_CTL)"

	# the store, by the INSTALLED kbootset from the INSTALLED loader files: it lays the
	# store over whatever the slice held -- a 1.0 chain, an earlier store, a 1.0 root's
	# tail -- and with --force zeroes the first 64 KiB itself (C2-4 v6 §8); its set id
	# is what `status` prints, for bootset's store-id=
	KBX="$TARGET/sbin/kbootset"
	[ -x "$KBX" ] || die "the kbootset package laid no executable $KBX"
	_lv=`( while read _l; do case "$_l" in version=*) expr "$_l" : 'version=\(.*\)' ;; esac; done ) < "$TARGET/stand/loader/ldrinfo"`
	is_num "$_lv" || die "the loader package's /stand/loader/ldrinfo names no version"
	KB="$KBX -R $TARGET --dev $BOOT_RAW --journal $TARGET/var/kbootset/journal"
	run "$KBX" --dev "$BOOT_RAW" create "$L11_STORE_BYTES" "$TARGET/stand/loader/boot2" \
		--boot1 "$TARGET/stand/loader/boot1" --version "$_lv" --force
	"$KBX" --dev "$BOOT_RAW" status > /tmp/.l11st 2>&1
	L11_STORE_ID=`( while read _a _b _r; do [ "$_a" = store-id: ] && echo "$_b"; done ) < /tmp/.l11st`
	rm -f /tmp/.l11st
	[ -n "$L11_STORE_ID" ] || die "kbootset status names no store-id for the new store on $BOOT_RAW"
	l11_bootset manual
	msg "boot store   : laid by the installed kbootset with the loader package's boot1/boot2 (version $_lv), store-id $L11_STORE_ID"

	# MODREG_LOCAL (a profile key, emulation rigs only): administrator lines for modules, as
	# "module:line|module:line", laid in /etc/conf/modreg.local.d/<module> before the build so the
	# generation carries them (e.g. "z3660rtg:param fixed=1" where an emulator's RTG board has no
	# AutoConfig entry; never on a real Z3660, whose board has one)
	if [ -n "$MODREG_LOCAL" ]; then
		run mkdir -p "$TARGET/etc/conf/modreg.local.d"
		_ml="$MODREG_LOCAL"
		while [ -n "$_ml" ]
		do
			_e=`expr "$_ml" : '\([^|]*\)'`
			_ml=`expr "$_ml" : '[^|]*|\(.*\)'`
			_mm=`expr "$_e" : '\([^:]*\):'` _mv=`expr "$_e" : '[^:]*:\(.*\)'`
			[ -n "$_mm" ] && [ -n "$_mv" ] || die "MODREG_LOCAL entry '$_e' is not module:line"
			echo "$_mv" >> "$TARGET/etc/conf/modreg.local.d/$_mm" || die "cannot write modreg.local.d/$_mm"
			msg "modreg.local: $_mm: $_mv"
		done
	fi
	l11_kb build --line "$L11_LINE" --bootdev "$KBOOTSET_BOOTDEV" --rootdev "$KBOOTSET_ROOTDEV" \
		--rootfs "$TARGET_ROOT_FSTYPE" --mem "$L11_MEM" --root "$KBOOTSET_ROOTREC"
	l11_kb commit
	run sync
	# the post-write proof: every member's SHA-256 and CRC-32 against its manifest,
	# the generation against apkg's record; kbootset never writes in `check`
	l11_kb check
	runq $KB status
	# the generation's module copies, where the module core loads them from (C2-4 §11:
	# build -R writes them onto this root; check above hashed them)
	for _o in $L11_MODS
	do
		[ -f "$TARGET/stand/gen/1/mod/$_o" ] || die "the pristine generation has no /stand/gen/1/mod/$_o -- NOT arming"
	done
	[ -n "$L11_MODS" ] && msg "modules      :$L11_MODS in generation 1 (/stand/gen/1/mod)"
	l11_namelist

	# /dev/kinfo (amix-dlm C2-3 v3 §1, C2-4 v4 §2): kernel-space packages are pure
	# files, so the node is the installer's: c 53 0, 0444. The miniroot has no chown or
	# chgrp; the node is root's already, and first boot gives it group sys.
	[ -d "$TARGET/dev" ] || run mkdir -p "$TARGET/dev"
	rm -f "${TARGET:?}/dev/kinfo"
	run /bin/mknod "$TARGET/dev/kinfo" c 53 0
	run chmod 0444 "$TARGET/dev/kinfo"
	# updbootpart would frame a 1.0 chain over the store: on this disk it is the shim
	# that refuses and names kbootset (spec 40 §2.2, P-28 D54)
	[ -d "$TARGET/usr/sbin" ] || run mkdir -p "$TARGET/usr/sbin"
	run cp "$L11/updbootpart" "$TARGET/usr/sbin/updbootpart"
	run chmod 0755 "$TARGET/usr/sbin/updbootpart"
	l11_bcheckrc "$TARGET/sbin/bcheckrc"
	l11_markgood
	l11_bootset auto
	rm -rf "${TARGET:?}/tmp/kpkgcache" "${KCONF:?}"
	msg "boot store   : pristine generation committed on $BOOT_RAW and checked; /etc/default/bootset, /dev/kinfo and the updbootpart shim laid"
}

# l11_base -- after core and the base set, the base packages in base/order (amix-base, then
# dhcp-client and syslog; amix userland/base/docs/package-split.md).
# Under the target's own chroot: its /bin/sh, grep, sum, cmp and APKGENG's engine
# (/usr/apkg/bin/pkgadd and removef). The miniroot carries none of the conffile class's tools,
# and stock 2.1 has no removef. For each package: seed the baselines of its conffiles that
# still match their contents record (seed.sh), then pkgadd it. Then `removef core` the paths
# amix-base took over and `removef -f core`. A fresh install leaves no PENDING.
l11_base()
{
	_bd="$TARGET/tmp/l11base" _cr="$TARGET/usr/sbin/chroot"
	[ -x "$_cr" ] || die "base packages: the target has no /usr/sbin/chroot"
	[ -x "$TARGET/usr/apkg/bin/pkgadd" ] && [ -x "$TARGET/usr/apkg/bin/removef" ] \
		|| die "base packages: the target has no APKGENG engine (/usr/apkg/bin/pkgadd, removef) -- APKGENG must be in the set"
	[ -f "$L11/base/order" ] || die "INSTALL_LAYOUT=1.1 but the medium has no $L11/base/order -- re-master with tools/build-install-iso.sh"
	run mkdir -p "$_bd"
	# the installer's TMPDIR is /mnt/tmp, which does not exist inside the chroot: the engine
	# could not make its unpack directory ("Bad file number" on a test install)
	_tmpd="$TMPDIR"; TMPDIR=/tmp; export TMPDIR
	# the engine reads the mount table for its space check; core ships /etc/mnttab empty, so
	# it gets the root line the miniroot's has (install.sh section 4), emptied again below
	echo "/dev/root / $TARGET_ROOT_FSTYPE rw 0" > "$TARGET/etc/mnttab" || die "cannot write $TARGET/etc/mnttab"
	run cp "$L11/base/seed.sh" "$_bd/seed.sh"
	run cp "$INST/admin/pkgadd" "$_bd/admin"
	_n=0
	# every set's packages, then the chosen set's own (base/o.<set>, staged only for a set the
	# medium offers)
	_ord=`cat "$L11/base/order"`
	[ -f "$L11/base/o.$INSTALL_SET" ] && _ord="$_ord `cat "$L11/base/o.$INSTALL_SET"`"
	for _p in $_ord
	do
		_f="$_p.pkg"
		[ -f "$L11/base/$_f" ] || die "base packages: no $_p datastream ($_f) in $L11/base"
		run cp "$L11/base/$_f" "$_bd/$_f"
		if [ -s "$L11/base/$_p.cf" ]; then
			"$_cr" "$TARGET" /bin/sh /tmp/l11base/seed.sh "$_p" `cat "$L11/base/$_p.cf"` > "$_bd/seed.out" 2>&1 \
				|| { cat "$_bd/seed.out"; die "base packages: seeding $_p's conffile baselines failed"; }
			logline "+ seed $_p:"
			cat "$_bd/seed.out" >> "$LOGFILE"
		fi
		stage "Installing $_p"
		runq "$_cr" "$TARGET" /usr/apkg/bin/pkgadd -n -a /tmp/l11base/admin -d "/tmp/l11base/$_f" "$_p" \
			|| die "base packages: pkgadd $_p failed (rc=$?) -- refusing to arm"
		[ -d "$TARGET/var/sadm/pkg/$_p" ] || die "base packages: pkgadd $_p returned 0 but $_p is not installed"
		# one datastream at a time on the target (x11r63's is 34 MB)
		run rm -f "${_bd:?}/$_f"
		_n=`expr $_n + 1`
	done
	[ "$_n" -gt 0 ] || die "base packages: $L11/base/order names none"
	# the ownership transfer: amix-base's conffiles leave core
	if [ -s "$L11/base/amxbase.cf" ]; then
		runq "$_cr" "$TARGET" /usr/apkg/bin/removef core `cat "$L11/base/amxbase.cf"` \
			|| die "base packages: removef core failed (rc=$?)"
		runq "$_cr" "$TARGET" /usr/apkg/bin/removef -f core || die "base packages: removef -f core failed (rc=$?)"
	fi
	TMPDIR="$_tmpd"; export TMPDIR
	run cp /dev/null "$TARGET/etc/mnttab"
	[ -s "$TARGET/var/sadm/conffiles/PENDING" ] \
		&& die "base packages: a fresh install left conffiles PENDING: `cat "$TARGET/var/sadm/conffiles/PENDING"`"
	run rm -rf "${_bd:?}"
	msg "base pkgs    : $_n added under the target's chroot (`echo $_ord`); core gave up amix-base's conffiles"
}

# l11_bits MASK -- _bits: the prefix length of a dotted netmask (empty: none); dies on
# another. Called directly, never in backticks, so the die stops the install.
l11_bits()
{
	case "$1" in
		"")			_bits="" ;;
		255.0.0.0)		_bits=8 ;;
		255.255.0.0)		_bits=16 ;;
		255.255.240.0)		_bits=20 ;;
		255.255.248.0)		_bits=21 ;;
		255.255.252.0)		_bits=22 ;;
		255.255.254.0)		_bits=23 ;;
		255.255.255.0)		_bits=24 ;;
		255.255.255.128)	_bits=25 ;;
		255.255.255.192)	_bits=26 ;;
		255.255.255.224)	_bits=27 ;;
		255.255.255.240)	_bits=28 ;;
		255.255.255.248)	_bits=29 ;;
		255.255.255.252)	_bits=30 ;;
		*)	die "netmask '$1' is not one of the prefix lengths 8, 16, 20-30" ;;
	esac
}

# l11_admin -- the three admin files no package owns, from the profile, each
# checked by its own reader under the target's chroot (amix-base's ifup -n, xstart -n).
#   /etc/inet/interfaces (interfaces(4)): FB_IP set (bench, metal, matrix) gives a
#     static line for FB_ETHER_IF, a zen0 line beside it from FB_ZEN_IP, a MAC line per
#     FB_ZEN_CARDS row (the address-by-card table, docs/address-by-card.md), and dns/domain;
#     FB_IP empty (public) gives `* dhcp`, with the profile's name, else `hostname dhcp`.
#   /etc/rc.conf (rc.conf(4)): syslogd=yes|no from FB_SYSLOG; swap_add= from SWAP_ADD_MB, the
#     sizes amix-base's boot swap step tries (bootswap(1M)); every other service keeps its own
#     default.
#   /etc/display (display(4)): card auto (the first card whose device answers, the chipset
#     display last), monsw from MONSW, start manual (no xdm is packaged yet).
l11_admin()
{
	_cr="$TARGET/usr/sbin/chroot" _if="$TARGET/etc/inet/interfaces"
	l11_bits "$FB_ZEN_NETMASK"; _zbits=$_bits
	l11_bits "$FB_NETMASK"; _b=$_bits
	{
		echo "# /etc/inet/interfaces -- written by install.sh from profile $PROFILE_NAME; see interfaces(4)"
		if [ -n "$FB_IP" ]; then
			echo "$FB_ETHER_IF static $FB_IP${_b:+/$_b}${FB_GATEWAY:+ gw $FB_GATEWAY}${FB_NODENAME:+ name $FB_NODENAME}"
			if [ -n "$FB_ZEN_IP" ] && [ "$FB_ETHER_IF" != zen0 ]; then
				_zb=$_zbits
				echo "zen0 static $FB_ZEN_IP${_zb:+/$_zb}${FB_ZEN_GATEWAY:+ gw $FB_ZEN_GATEWAY}"
			fi
			for _w in $FB_ZEN_CARDS
			do
				_mac=`expr "$_w" : '\([^=]*\)='` _ad=`expr "$_w" : '[^=]*=\([^=]*\)'` _nm=`expr "$_w" : '[^=]*=[^=]*=\(.*\)'`
				case "$_mac" in default|"") continue ;; esac
				echo "$_mac static $_ad${_b:+/$_b}${FB_GATEWAY:+ gw $FB_GATEWAY}${_nm:+ name $_nm}"
			done
		elif [ -n "$FB_NODENAME" ]; then
			echo "* dhcp name $FB_NODENAME"
		else
			echo "* dhcp"
			echo "hostname dhcp"
		fi
		[ -z "$FB_DNS1$FB_DNS2" ] || echo "dns `echo $FB_DNS1 $FB_DNS2`"
		[ -z "$FB_DOMAIN" ] || echo "domain $FB_DOMAIN"
	} > "$_if" || die "cannot write $_if"
	run chmod 0644 "$_if"
	{
		echo "# /etc/rc.conf -- written by install.sh from profile $PROFILE_NAME; see rc.conf(4)"
		case "$FB_SYSLOG" in n) echo "syslogd=no" ;; *) echo "syslogd=yes" ;; esac
		[ -z "$SWAP_ADD_MB" ] || echo "swap_add=$SWAP_ADD_MB"
	} > "$TARGET/etc/rc.conf" || die "cannot write $TARGET/etc/rc.conf"
	run chmod 0644 "$TARGET/etc/rc.conf"
	{
		echo "# /etc/display -- written by install.sh from profile $PROFILE_NAME; see display(4)"
		echo "card auto"
		case "$MONSW" in ""|none) ;; *) echo "monsw $MONSW" ;; esac
		echo "start manual"
	} > "$TARGET/etc/display" || die "cannot write $TARGET/etc/display"
	run chmod 0644 "$TARGET/etc/display"
	_tmpd="$TMPDIR"; TMPDIR=/tmp; export TMPDIR   # the chroot has no /mnt/tmp (l11_base)
	"$_cr" "$TARGET" /usr/sbin/ifup -n > /tmp/.l11if 2>&1 \
		|| { cat /tmp/.l11if; die "/etc/inet/interfaces does not pass ifup -n"; }
	# xstart -n also checks the card's X server, so only a set with X can pass it; without X
	# the file is checked by xstart when X is added (the minimal set has no X)
	if [ -d "$TARGET/usr/X/bin" ]; then
		"$_cr" "$TARGET" /usr/amix/bin/xstart -n > /tmp/.l11dp 2>&1 \
			|| { cat /tmp/.l11dp; die "/etc/display does not pass xstart -n"; }
		_xs="xstart -n passes"
	else
		_xs="no X in this set: xstart checks it when X is added"
	fi
	TMPDIR="$_tmpd"; export TMPDIR
	rm -f /tmp/.l11if /tmp/.l11dp
	# no backquoted `if` inside the double quotes: the 1991 sh cannot parse it
	if [ -n "$FB_IP" ]; then _ifd="$FB_ETHER_IF static $FB_IP"; else _ifd="* dhcp"; fi
	msg "admin files  : /etc/inet/interfaces ($_ifd), /etc/rc.conf, /etc/display; ifup -n passes; $_xs"
}

# l11_bcheckrc FILE -- FILE becomes the medium's bcheckrc, with `kbootset retry`
# before each of the root fsck block's three `/sbin/uadmin 1 1` (C2-4 v5 §7: a repair
# reboot gives a trial its attempt back instead of spending it), only while FILE is
# still the stock 2.1 file; written with cat, so its links (/usr/sbin/bcheckrc) and
# mode stay. Anything else is left alone, and said.
l11_bcheckrc()
{
	_bf="$1"
	set x `"$INST/bin/sum" -r "$_bf"`; shift
	_bh=$1
	_bs=`( read _s _r; echo "$_s" ) < "$L11/bcheckrc.stock"`
	set x `"$INST/bin/sum" -r "$L11/bcheckrc"`; shift
	_bp=$1
	if [ "$_bh" = "$_bp" ]; then
		msg "bcheckrc     : $_bf already carries kbootset retry (sum -r $_bp)"
		return 0
	fi
	if [ "$_bh" != "$_bs" ]; then
		warn "$_bf is not the stock 2.1 bcheckrc (sum -r $_bh, stock $_bs) -- kbootset retry NOT added; add it by hand (C2-4 section 7)"
		return 0
	fi
	cat "$L11/bcheckrc" > "$_bf" || die "cannot write $_bf"
	set x `"$INST/bin/sum" -r "$_bf"`; shift
	[ "$1" = "$_bp" ] || die "the patched bcheckrc did not read back ($_bf)"
	msg "bcheckrc     : kbootset retry before the three root-fsck reboots in $_bf (sum -r $_bp)"
}

# l11_markgood -- /etc/rc2.d/S99zkbootset, the LAST run-level-2 script (it sorts after
# S99zen): a box that came all the way up marks the booted generation good (spec 40
# §3.3, D-3 §6, P-28 D54), with C2-4 §9's line. kbootset takes the booted generation from the loader record
# through kinfo; a box that panics or hangs in rc never gets here, and the loader's
# try-once rule boots the previous good generation instead. kbootset's package ships it (-26
# on: init.d/kbmarkgood with its rc2.d link); this checks it.
l11_markgood()
{
	[ -f "$TARGET/etc/init.d/kbmarkgood" ] && [ -f "$TARGET/etc/rc2.d/S99zkbootset" ] \
		|| die "the kbootset package laid no /etc/init.d/kbmarkgood and rc2.d/S99zkbootset -- kbootset -26 or later ships them"
	msg "mark-good    : kbootset's /etc/rc2.d/S99zkbootset runs kbootset mark-good at the end of run level 2"
}

# l11_kpkg_record NAME ROLE -- the kernel-space record of NAME: /var/apkg/kpkg/<pkginst>
# (C2-2 v4 §2), whose `name` line is NAME and `role` line ROLE; a module's names its
# object /etc/conf/mod.d/<module> and the package's modreg.d file (C3-5 §1), which are
# on the target. Refuses to go on without it.
l11_kpkg_record()
{
	_pi=`l11_kpkg_inst "$1"`
	[ -n "$_pi" ] || die "the medium's catalog has no #kpkg row for $1"
	_rec="$TARGET/var/apkg/kpkg/$_pi"
	[ -f "$_rec" ] || die "apkg installed $1 but wrote no record /var/apkg/kpkg/$_pi -- kbootset gate 1 would refuse"
	_rn=`( read _k _v _r; [ "$_k" = name ] && echo "$_v" ) < "$_rec"`
	[ "$_rn" = "$1" ] || die "/var/apkg/kpkg/$_pi names '$_rn', not $1"
	_rr=`( while read _k _v _r; do [ "$_k" = role ] && echo "$_v"; done ) < "$_rec"`
	[ "$_rr" = "$2" ] || die "/var/apkg/kpkg/$_pi says role '$_rr', not $2"
	[ "$2" = module ] || return 0
	_o=`expr "$1" : '\(.*\)-k[34][06]$'`
	_rf=`( while read _k _v _r; do [ "$_k" = file ] && echo "$_v"; done ) < "$_rec"`
	for _f in /etc/conf/mod.d/$_o /etc/conf/modreg.d/$_o
	do
		case " "`echo $_rf`" " in
			*" $_f "*)	: ;;
			*)	die "/var/apkg/kpkg/$_pi has no file line for $_f" ;;
		esac
		[ -f "$TARGET$_f" ] || die "the module package $1 laid no $_f"
	done
	return 0
}

# l11_kpkg_key NAME KEY -- KEY's value in the #kpkg row of NAME in the medium's
# catalog (role, line, kabi, ...); nothing when there is no such row or key
l11_kpkg_key()
{
	( while read _h _n _v _rest
	do
		[ "$_h" = "#kpkg" ] && [ "$_n" = "$1" ] || continue
		for _t in $_rest
		do
			case "$_t" in "$2"=*) expr "$_t" : "$2=\\(.*\\)" ;; esac
		done
	done ) < "${L11_KCAT:-$L11/kpkg/catalog}"
}

# l11_inittab -- once amix-base is in (it ships /etc/inittab as a conffile; modtools
# -9 has no scripts and never edits it): /etc/inittab holds exactly one line with the id
# dlm, it is the first sysinit entry, with C3-5 §5's text, and the file is amix-base's
# default (the medium's inittab, taken from amix-base's datastream). The miniroot has no grep or awk: read, expr and sum only, and a
# redirect-fed loop is a subshell, so what it finds goes to files.
l11_inittab()
{
	_it="$TARGET/etc/inittab"
	_why="/etc/inittab is not amix-base's default (C3-5 section 5: one dlm line, the first sysinit entry)"
	[ -f "$_it" ] || die "$_why: there is no $_it"
	rm -f /tmp/.l11it /tmp/.l11dl
	while read _l
	do
		case "$_l" in
			dlm:*)	echo dlm >> /tmp/.l11it
				echo "$_l" >> /tmp/.l11dl ;;
			\#*)	: ;;
			*)	expr "$_l" : '[^:]*:[^:]*:sysinit:' > /dev/null && echo other >> /tmp/.l11it ;;
		esac
	done < "$_it"
	[ -s /tmp/.l11it ] || die "$_why: it has no sysinit entry and no dlm line"
	set x `cat /tmp/.l11it`; shift
	_first=$1 _nd=0
	for _w
	do
		[ "$_w" = dlm ] && _nd=`expr $_nd + 1`
	done
	[ "$_nd" = 1 ] || die "$_why: $_nd line(s) with the id dlm, not exactly one"
	[ "$_first" = dlm ] || die "$_why: the dlm line is not the first sysinit entry"
	_dl=`cat /tmp/.l11dl`
	[ "$_dl" = "$L11_DLM" ] || die "$_why: the dlm line reads '$_dl'"
	set x `"$INST/bin/sum" -r "$_it"`; shift
	_ih=$1
	set x `"$INST/bin/sum" -r "$L11/inittab"`; shift
	[ "$_ih" = "$1" ] || die "$_why: it is not amix-base's inittab (sum -r $_ih, expected $1)"
	rm -f /tmp/.l11it /tmp/.l11dl
	msg "inittab      : amix-base's default: the dlm line (modadmin -B) once, the first sysinit entry (sum -r $_ih)"
}

# l11_namelist -- /stand/unix is the namelist the stock nlist users read (netstat,
# ifconfig, crash). Core left it a hard link to /stand/2.1_unix, the 1992 kernel, never
# the booted one on a 1.1 disk: the name goes (2.1_unix stays, checked), and so does any
# /unix. /etc/rc2.d/S01kbnamelist -- after S01MOUNTFSYS, before every other rc2 script --
# writes the booted generation's namelist on every boot (C2-4 v9 §12, spec 40 §4.2): the
# installer cannot, it does not know where the first boot binds the kernel. kbootset's
# package ships it (-26 on: init.d/kbnamelist with its rc2.d link); this checks it.
l11_namelist()
{
	rm -f "${TARGET:?}/stand/unix" "${TARGET:?}/unix"
	[ -f "$TARGET/stand/unix" ] && die "cannot remove $TARGET/stand/unix"
	[ -f "$TARGET/stand/2.1_unix" ] || die "core's /stand/2.1_unix is not on the target"
	_us=`( read _s _r; echo "$_s" ) < "$L11/2.1_unix.sum"`
	set x `"$INST/bin/sum" -r "$TARGET/stand/2.1_unix"`; shift
	[ "$1" = "$_us" ] || die "/stand/2.1_unix is not core's 2.1 kernel (sum -r $1, core $_us)"
	[ -f "$TARGET/etc/init.d/kbnamelist" ] && [ -f "$TARGET/etc/rc2.d/S01kbnamelist" ] \
		|| die "the kbootset package laid no /etc/init.d/kbnamelist and rc2.d/S01kbnamelist -- kbootset -26 or later ships them"
	msg "namelist     : /stand/unix and /unix removed (/stand/2.1_unix kept, sum -r $_us); kbootset's S01kbnamelist writes it at every boot"
}

# l11_kpkg_inst NAME -- the pkginst of catalog entry NAME on the medium: its pkginst=
# key, else NAME (C2-2 v4 §1-2); nothing when the catalog has no such row
l11_kpkg_inst()
{
	( while read _h _n _v _rest
	do
		[ "$_h" = "#kpkg" ] && [ "$_n" = "$1" ] || continue
		_pi="$1"
		for _t in $_rest
		do
			case "$_t" in pkginst=*) _pi=`expr "$_t" : 'pkginst=\(.*\)'` ;; esac
		done
		echo "$_pi"
	done ) < "${L11_KCAT:-$L11/kpkg/catalog}"
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
