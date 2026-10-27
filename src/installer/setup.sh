#!/bin/sh
# setup.sh -- the Installer-NG INTERVIEW (wave W2 of the installer-UX rework).
# Runs ON THE MINIROOT, single-user, after the install source has been mounted at
# /cdrom. It asks the operator the handful of questions the original Amiga UNIX
# installer asked, composes the answers into /tmp/answers.profile on top of a
# MEDIA-RESIDENT BASE PROFILE, and hands that straight to the proven driver:
#
#     exec sh /cdrom/install/bin/install.sh /tmp/answers.profile < /dev/null
#
# It is a VENEER. Nothing here partitions, mkfs's, pkgadd's or writes a boot
# chain -- install.sh still does all of that, unattended, exactly as it does for
# a canned profile. The only thing this file produces is a profile.
#
# ===========================================================================
# THE UX SPEC IS THE STOCK INSTALLER, NOT AN INVENTION
# ===========================================================================
# The original interactive install script IS `/etc/profile` on the stock root
# floppy (floppies/orig/amix_21_root.adf, 19,351 B, md5 97f800ec7bcd627bfed2
# 322fdc19f86b; extract it host-side with tools/lib/s5.py). Every prompt, every
# default, every validation message and every error path below is that file's,
# VERBATIM, unless a line is marked NG. The package-set menu's wording comes
# from the other stock artifact, `/bin/amixpkg` (12,216 B, md5 d63408968f8702
# 7313dc9115a6756d55) -- recovered by strings; see docs/installer.md "The stock
# amixpkg screens".
#
# The stock idioms this file reuses, and why each matters:
#   * readask()   -- `echo "...\c"` + `read ask`, with EOF falling through to an
#                    interactive shell. The SVR4 builtin echo interprets \c
#                    (no newline) and \n; there is no /bin/echo on the miniroot
#                    and no `echo -n`, so this is the only way to prompt.
#   * defaults in brackets: `... ? [12] `; an empty answer takes the default.
#   * y/n as CASE GLOBS: [yY]|[yY][eE][sS] -- never a string compare.
#   * numbered menus, `(1)  ...` / `Choose: [1] `.
#   * "WARNING:  " with TWO spaces after the colon.
#   * the restart idiom: "Press RETURN to restart the installation script. ".
#     On the miniroot the stock script `exit 99`s and init respawns it; HERE the
#     script is on the medium and nothing respawns it, so restart() RE-EXECS
#     ITSELF instead. Same operator experience, different mechanism (plan §1).
#   * Ctrl-C anywhere -> `trap` -> "Running interactive shell..." -> sh -i.
#
# ===========================================================================
# PRE-POSIX SVR4 /bin/sh -- HARD PORTABILITY RULES (the miniroot sh is 1991)
# ===========================================================================
# Identical to src/installer/install.sh's; tools/installer-selftest.py audits
# THIS file with the same greps and the same miniroot.proto-derived tool
# allowlist (audits A, B, G, H, I, T all cover setup.sh from W2 on).
#   * NO $(...)   -- use `backticks`      * NO $(( ))  -- arithmetic is `expr`
#   * NO [[ ]]    -- test with [ ]        * NO `local`, NO arrays, NO wc
#   * NO `export VAR=val` -- write VAR=val; export VAR
#   * NO basename/sed/touch/date/grep/od/cmp/tr -- the miniroot carries NONE.
#   * ★ NEVER `: > file` INSIDE A LOOP. On this shell a redirection applied to
#     the NULL COMMAND fires only on the FIRST pass through a loop body; from
#     the second on it returns 0 and creates nothing (bench-proven 2026-08-11,
#     matrix run 20260811-103107-cd). Straight-line `: >` is fine. Inside a
#     loop, create with `cp /dev/null` or append with `echo ... >>`.
#     ★ W3b widened this: a FUNCTION called from a loop body is a loop body.
#     Every question here sits inside the `Do you wish to change any of these?`
#     re-ask loop, so W2's straight-line `: >` truncations in scan_disks /
#     choose_disk / set_size_mb / build_set_table were only straight-line on
#     the FIRST pass -- a second pass would have appended to a scratch file it
#     believed it had emptied, and the operator would have been shown the disk
#     table and the package menu TWICE OVER. All of them now use `cp /dev/null`.
#   * A `while read ... done < FILE` loop runs in a SUBSHELL: a variable
#     assigned inside is LOST at `done`. Record to an append-only temp FILE and
#     decide in the parent. And `set -- \`cat FILE\`` on an EMPTY file is a
#     NO-OP on $@ (it does NOT clear it), so every such count is [ -s ]-guarded.
#
# ===========================================================================
# WHAT IT ASKS (plan §2; the decisions locked in plan §8)
# ===========================================================================
#   1. Destination disk   -- stock "Scanning SCSI bus for hard disks..." + the
#                            per-id table + "What is the SCSI id of the disk you
#                            want to install?" (SKIPPED when exactly one disk is
#                            eligible -- stock behaviour), then the stock
#                            no-default "Are you sure you want to erase this
#                            disk? " when the chosen disk already has an RDB.
#   2. Partition sizes    -- the stock root/swap questions, stock arithmetic,
#                            stock floors (MINROOT 16 / MINSWAP 5) and stock
#                            validation messages, landing in W1's driver keys
#                            TARGET_ROOT_MB / TARGET_SWAP_MB.
#   3. Root fs type       -- the stock s5/ufs menu, restored verbatim except for
#                            its default: stock offered `[s5]`, we offer `[ufs]`.
#                            See "THE ROOT FILESYSTEM QUESTION" below for why the
#                            question came back and why the default moved. Lands
#                            in the driver key TARGET_ROOT_FSTYPE. ASKED ONLY
#                            WHEN THE TARGET WILL ACTUALLY BE AUTHORED.
#   4. Package set        -- amixpkg's THREE-TIER menu (W3b), data-driven from
#                            the medium's /install/sets table and its per-set
#                            /install/order.<set> files, sized from the catalog's
#                            #isize block. Tier 3 is the amixpkg CUSTOM TABLE.
#   5. Verbose install?   -- INSTALL_VERBOSE.
#   6. Confirmation       -- the stock summary + "Do you wish to change any of
#                            these? [n] " loop, then compose + exec.
#
# NOT asked here, deliberately (plan §8):
#   * keymap        -- pre-mount, so it is the miniroot /etc/profile's question
#                      (src/miniroot/profile, W4). Its answer arrives here as
#                      $KMAP / /tmp/kmap and lands in FB_KMAP; see "THE KEYMAP".
#   * AmigaDOS reservation, RDB reuse, the 4th partition, per-partition fs --
#     the phase-2 RDB-states cluster (plan §8.8), backlog.
#   * identity/network/users -- first boot (W5); the miniroot cannot hash a
#     password and has no network userland.
#
# ===========================================================================
# ★ THE ROOT FILESYSTEM QUESTION -- restored, with its default moved
# ===========================================================================
# This question used to be listed above as "SUPPRESSED while the chain is
# s5-only". That premise was wrong in one respect and is now obsolete in the
# other, and both halves were measured rather than argued (the whole file of
# evidence is docs/ufs-target-scoping.md, and the kernel half is
# ../amix-kerntools/docs/ufs-root-kernel-capability.md):
#
#   * "the chain is s5-only" was never true of the MEDIUM. /bin/mkfs_ufs and
#     /bin/fsck_ufs have been on this miniroot since W5.2 -- byte-identical to
#     the stock root floppy's, every undefined symbol resolving against the
#     miniroot's own libc -- because the build starts from a byte copy of the
#     stock image and the proto preserves them. Nothing had to be added to the
#     floppy, which matters: it has 46 free blocks.
#   * nor of the KERNEL. `ufs` sits at vfssw[2] in all ten kernels examined,
#     including this medium's own fd0unix install kernel, and `rootfstype` is
#     compiled EMPTY ("Empty means try them all"), so vfs_mountroot probes s5
#     first and ufs second and takes the first that mounts. A ufs root costs
#     zero kernel bytes and zero configuration.
#   * nor of the INSTALLED SYSTEM. core-2.1.pkg ships the complete ufs back end
#     (mkfs, fsck, mount, labelit + 17 more) -- a LARGER suite than the s5 one.
#
# ★ THE ONE DELIBERATE DIVERGENCE FROM STOCK IS THE DEFAULT. Stock's prompt read
# `[s5]` and ufs had to be typed; ours reads `[ufs]` and s5 has to be typed. The
# menu text, the branch structure and the option constant are stock's, verbatim.
# The reason for moving it is stock's own documentation, which recommends ufs
# over s5 -- advice whoever built the Amix install this project INHERITED
# evidently took: both goldens carry a UFS1 big-endian root whose superblock
# reads back fs_minfree=2 / fs_optim=SPACE, the exact fingerprint of the
# `-o free=2,opt=s` this script hands the driver. s5's 14-character names and
# 65,535-inode ceiling are the concrete cost of the other answer; s5 stays
# selectable because it is what every attested digest was measured on and what
# the miniroot itself is.
# (This is the same class of divergence as W4's "Suomi / Svenska" relabel: stock
# shape, one deliberate word changed, recorded as such.)
#
# ★ AND IT IS ASKED ONLY WHEN IT CAN BE HONOURED. With INSTALL_TARGET_PREBUILT=1
# the target's filesystem was already minted host-side by tools/mkroot.sh, which
# writes s5 and only s5 -- there is no host-side ufs writer and deliberately none
# planned. Asking there would be exactly the locked question the stock idiom
# forbids, so the question is skipped and s5 is composed. That is not a
# reduced-function mode in the field: a person installing from this disc onto
# their own blank disk is in AUTHOR mode, which is where the question belongs and
# where mkfs_ufs actually runs.
#
# ===========================================================================
# ★ WHY THE DISK SCAN DOES NOT CALL /etc/ddsize
# ===========================================================================
# The stock scan called `/etc/ddsize /dev/rdsk/c${i}d0s0` once per id. W1 tried
# exactly one such call in the driver and it WEDGED THE INSTALL on the bench
# A3000 onboard-SCSI (a3091) path: the console printed `a3091: 0x1 0 0x0` and
# nothing ever advanced (matrix run 20260811-094255-cd, install gate FAIL after
# the 300 s go-marker budget). There is NO timeout tool on the miniroot, so a
# hang here cannot be bounded -- and a scan runs the call once PER ID, which
# multiplies the exposure by six. So:
#
#   * the SCAN never calls ddsize. It opens and reads ONE 512-byte block from
#     each id's /dev/dsk/cNd0s0 with `dd`. That is not a new invention: stock's
#     own `/etc/atdevs` (2,404 B, extracted from the same root floppy) is a
#     tiny ELF whose only format string is `/dev/dsk/c%dd0s0` and whose only
#     libc calls are open/read/close/printf -- i.e. it IS this probe, in C, on
#     the BLOCK node. We do it in sh so the failure mode is inspectable;
#     atdevs itself is avoided because it has already been observed returning
#     nonzero on metal (firstboot's /dev regen, docs/installer.md).
#   * ddsize is reachable ONLY after the disk is chosen, ONLY for that one id,
#     and ONLY when the base profile says the rig tolerates it (DDSIZE_SAFE=y --
#     metal-class rigs, where stock's own installer ran it). On a rig that says
#     n, an unknown size is ASKED for instead. An unbounded hang is never
#     preferable to a question.
#
# ===========================================================================
# HOW THE SIZE OF A DISK IS DECIDED (first hit wins)
# ===========================================================================
#   1. the base profile's TARGET_DISK_MB, if the chosen id IS the profile's
#      TARGET_SCSI_ID -- the medium's own declaration about its own rig. This
#      is the same precedence the W1 driver applies, and it is what keeps a
#      pinned rig (bench, metal) byte-deterministic.
#   2. the RDB's own extent, when the disk already carries an RDB: the largest
#      (start + length) over its partitions, read with `/etc/rdb -h 5` (last
#      partition number) and `/etc/rdb -p N` ("name start length" -- the exact
#      output shape the stock script parses with `set --`). This UNDERSTATES a
#      disk whose RDB does not span it, which is the FAIL-SAFE direction: the
#      plan then lays partitions inside a region we have proof exists. Never
#      the other way round.
#   3. `/etc/ddsize`, iff DDSIZE_SAFE=y (see above).
#   4. the operator, asked outright.
# Whatever wins is written to the answers profile as TARGET_DISK_MB, so the
# driver's own probe is short-circuited and install.sh NEVER calls ddsize.
#
# ===========================================================================
# THE ANSWERS PROFILE
# ===========================================================================
# /tmp/answers.profile = the whole base profile, byte for byte, with the
# answers APPENDED. The profile is sourced by sh, so a later assignment wins --
# that is the entire merge mechanism, and it means every key the medium
# declares (kernel sums, CD_SPEC, boot-slice paths, FB_*) survives untouched.
# The medium is read-only, which is why the driver learned to take a profile BY
# PATH in W1.
#
# stdin: the interview OWNS the console; install.sh must NOT. The exec below
# redirects install.sh's stdin from /dev/null, preserving METAL-FIX.3 (an
# inherited stdin is what hung M-RUN1 on the 1991 pkgadd's prompt). Anything
# still queued in the tty when the interview ends is therefore discarded rather
# than fed to the transplant.

PROG=setup.sh
CDROOT=/cdrom
INST=/cdrom/install
ANSWERS=/tmp/answers.profile
# W4: where the miniroot's own /etc/profile leaves the keymap the operator chose
# (src/miniroot/profile). See "THE KEYMAP" below.
KMAP_FILE=/tmp/kmap

# scratch (miniroot RAM disk; a few hundred bytes each). Created straight-line,
# never inside a loop -- see the null-command-redirection rule above.
BLK0=/tmp/setup.blk0
SCAN_F=/tmp/setup.scan
SET_F=/tmp/setup.sets
TOK_F=/tmp/setup.tok
CATN_F=/tmp/setup.catn
ISZ_F=/tmp/setup.isz
# W3b, the custom screen: the per-package table, its own copy of the #isize
# block, one marker FILE per selected package (the 1991 sh has no arrays and
# every list loop here is a subshell, so a file is the only state that survives),
# and the composed custom order. The order goes in /tmp because the MEDIUM IS
# READ-ONLY -- the same reason W1 taught the driver to take a profile by path.
PKG_F=/tmp/setup.pkgs
ISZP_F=/tmp/setup.iszp
SELP=/tmp/setup.p.
CUSTOM_ORDER=/tmp/setup.order
# The composed answers, on their own: appended to $ANSWERS and echoed as the
# beacon. Small on purpose -- see the compose step at the end of this file.
ANSWERS_BLOCK=/tmp/setup.ans

# --- stock install-script constants (identical to install.sh's; DO NOT rederive)
MINROOT=16
MINSWAP=5
BREAKPT=120
LGSWAP=30
SMSWAP=18
MINBOOT=2                # the boot-slice floor; install.sh carries the same constant
BOOTSIZE=10               # r6e (owner 2026-10-10): 10 MiB so every kernel cut fits; stock was 2
OFFSET_BLOCKS=128
BLOCKS_PER_MB=2048
# E-BIG (KT-32, 2026-10-02): the STOCK kernel cannot write an on-box filesystem
# past block 1234567 -- sdpart.c sddevsize() answers 1234567 for an unknown
# partition length and dd.c clamps raw I/O to it, so mkfs dies "wtfs: No such
# device or address" on any root above ~603 MB (600 MB proven, 640 fails).
# KERNEL_SDDEVSIZE names the medium's TARGET kernel: `stock` (the default) caps
# the root at SDDEV_CAP_BLOCKS / 2048 = 602 whole MB; `fixed` (a kernel family
# carrying the sddevsize fix) lifts the cap. Keyed on the kernel, never a date.
SDDEV_CAP_BLOCKS=1234567
SECS=64                 # blocks per cylinder (heads=1, sectors=64)

# The SCSI ids this miniroot can address at all. /dev/dsk/c4d0* is deliberately
# ABSENT from miniroot.proto -- stock reserved id 4 for the tape drive ("SCSI
# device 4 must be used for the tape drive"), so that refusal is STRUCTURAL
# here, not a special case in the code. installer-selftest audit U derives the
# expected list from miniroot.proto and fails if this default drifts from it.
#
# ★ CARD-1 MEDIA SCAN CARD 1 ONLY. On the real Z3660 (amix_mode NO) the SCSI is
# card 1 (c8d0..cfd0) and card 0 is the phantom A3091: the FIRST I/O to ANY
# c0..c7 node bus-errors in its driver (a supervisor-mode kernel panic,
# pc=0x800D578) -- the same rule as the root path and the atdevs probe. The
# interview's disk scan opens /dev/dsk/c<i>d0s0 for every i, so on a card-1
# medium it MUST list card-1 ids ONLY, or the "Scanning SCSI bus" step double-
# panics (metal-confirmed 2026-09-15). We derive that from the SAME baked file
# the miniroot's source auto-probe reads -- /etc/install-src-candidates -- so a
# card-1 medium cannot regress: each candidate names its card via the controller
# letter c<X>d0 (X = card<<3 | unit), and any X in 8..f means card 1. A card-0
# medium (the 030 line, or no candidates file) keeps the historical card-0 scan.
if [ -z "$SCAN_IDS" ] && [ -f /etc/install-src-candidates ]; then
	_c1=
	for _cand in `cat /etc/install-src-candidates`
	do
		_x=`expr "$_cand" : '.*/c\([0-9a-fA-F]*\)d0'`
		case "$_x" in [89aAbBcCdDeEfF]) _c1=1 ;; esac
	done
	# card-1 ids only (units 0..7 of card 1); nodes absent for a given id fail at
	# open() and are skipped -- no c0..c7 node is ever opened.
	[ -n "$_c1" ] && SCAN_IDS="8 9 a b c d e f"
fi
[ -n "$SCAN_IDS" ] || SCAN_IDS="0 1 2 3 5 6"

# ---------------------------------------------------------------------------
# stock helpers, verbatim
# ---------------------------------------------------------------------------
trap '	echo "Running interactive shell..."
	exec /bin/sh -i' 2

readask()
{
	echo "$*\c"
	read ask ||
	{
		echo "\nRunning interactive shell..."
		exec /bin/sh -i
	}
}

warn() { echo "$PROG: WARNING: $*" >&2; }
die()  { echo "$PROG: STOP: $*" >&2; exit 1; }

# is_num WORD -- strict non-negative integer test (no external tool). Every
# value read off a device or a tool's stdout goes through this, so an empty or
# garbled reading can never be used as a number (fail closed).
# hexval N -- the value of a controller number (c<N>d0: N = card*8 + unit in lowercase hex,
# one digit for cards 0-1, 10-1f for cards 2-3, contract C4-1 §2.2), or "".
hexval()
{
	case "$1" in
		[0-9])	echo "$1" ;;
		a|A) echo 10 ;; b|B) echo 11 ;; c|C) echo 12 ;;
		d|D) echo 13 ;; e|E) echo 14 ;; f|F) echo 15 ;;
		1[0-9])	expr 16 + `expr "$1" : '1\(.\)'` ;;
		1a|1A) echo 26 ;; 1b|1B) echo 27 ;; 1c|1C) echo 28 ;;
		1d|1D) echo 29 ;; 1e|1E) echo 30 ;; 1f|1F) echo 31 ;;
		*)	echo "" ;;
	esac
}
# hexname V -- the name of the controller number V (0-31): c%x, lowercase (C4-1 §2.2).
hexname()
{
	case "$1" in
		[0-9])	echo "$1" ;;
		10) echo a ;; 11) echo b ;; 12) echo c ;; 13) echo d ;; 14) echo e ;; 15) echo f ;;
		1[6-9]|2[0-5])	echo 1`expr $1 - 16` ;;
		26) echo 1a ;; 27) echo 1b ;; 28) echo 1c ;; 29) echo 1d ;; 30) echo 1e ;; 31) echo 1f ;;
		*)	echo "" ;;
	esac
}

# cd_unit_id -- the controller number of the cdfs source (CD_SPEC <card>,<unit>), or "".
cd_unit_id()
{
	[ -n "$CD_SPEC" ] || return 0
	_cc=`expr "$CD_SPEC" : '\([0-9]*\),'`
	_cu=`expr "$CD_SPEC" : '[0-9]*,\([0-9]*\)'`
	[ -n "$_cc" ] && [ -n "$_cu" ] || return 0
	hexname `expr $_cc \* 8 + $_cu`
}

# MINIROOT_CD_CANDIDATES -- the miniroot's own CD probe walk (src/miniroot/profile
# CD_CANDIDATES; installer-selftest pins the two equal). The miniroot mounts the
# first of these that answers and does not tell us which: cdfs records the mount
# as "/cdrom on /cdrom", and the root floppy's profile exports no spec. So the
# profile's CD_SPEC is only where the medium EXPECTS the CD. On an A4000/030 whose
# only host is the A4091 the CD answers 0,3 while the public classic profile says
# 1,3, and the scan would dd the CD (route B).
MINIROOT_CD_CANDIDATES="1,3 0,3 0,2 1,2"

# spec_id SPEC -- cdfs <card>,<unit> -> the controller digit c<card*8+unit>, or "".
spec_id()
{
	_cc=`expr "$1" : '\([0-9]*\),'`
	_cu=`expr "$1" : '[0-9]*,\([0-9]*\)'`
	[ -n "$_cc" ] && [ -n "$_cu" ] || return 0
	_cx=`expr $_cc \* 8 + $_cu`
	case "$_cx" in
		10) echo a ;; 11) echo b ;; 12) echo c ;;
		13) echo d ;; 14) echo e ;; 15) echo f ;;
		*)	echo "$_cx" ;;
	esac
}

# scan_safe_ids ID... -- the ids, minus the CD source's unit, the host ids 7 / f,
# and every id the miniroot's CD probe could have mounted that this medium cannot
# install to (an installable id stays: no shipped profile installs onto a CD unit).
scan_safe_ids()
{
	_cdx=`cd_unit_id`
	_cand=
	for _s in $MINIROOT_CD_CANDIDATES
	do
		_cand="$_cand `spec_id $_s`"
	done
	_out=
	for _i in "$@"
	do
		case "$_i" in 7|f|F|17|1f|1F) continue ;; esac
		[ -n "$_cdx" ] && [ "$_i" = "$_cdx" ] && continue
		case " $_cand " in
			*" $_i "*)
				case " $INSTALLABLE_IDS " in
					*" $_i "*)	;;
					*)		continue ;;
				esac
				;;
		esac
		_out="$_out $_i"
	done
	echo $_out
}

# ensure_disk_nodes ID -- create /dev/[r]dsk/c<ID>d0s0..s5 when absent. The K1 miniroot
# carries card-1 nodes only for c8 and ce; a card-1 target needs its own. The sd majors
# are miniroot.proto's (block 18, raw 40; installer-selftest audit CD2 pins them) and
# minor = slice*16 + X, the rule the stock /dev follows (c9d0s1 = 18,25); for cards 2-3
# (c10-c1f) the card's high bit is minor bit 7 (C4-1 §2.1).
SD_BMAJ=18
SD_CMAJ=40
ensure_disk_nodes()
{
	_ID="$1"
	_v=`hexval "$_ID"`
	[ -n "$_v" ] || return 1
	for _s in 0 1 2 3 4 5
	do
		_mn=`expr $_s \* 16 + $_v % 16 + $_v / 16 \* 128`
		[ -b /dev/dsk/c${_ID}d0s$_s ] || /bin/mknod /dev/dsk/c${_ID}d0s$_s b $SD_BMAJ $_mn || return 1
		[ -c /dev/rdsk/c${_ID}d0s$_s ] || /bin/mknod /dev/rdsk/c${_ID}d0s$_s c $SD_CMAJ $_mn || return 1
	done
	return 0
}

is_num() {
	case "$1" in
		'')       return 1 ;;
		*[!0-9]*) return 1 ;;
		*)        return 0 ;;
	esac
}

# ---------------------------------------------------------------------------
# 0. THE BASE PROFILE
# ---------------------------------------------------------------------------
# Resolution, in order -- the same shape install.sh uses, so a runbook line
# reads the same either way:
#   * an argument containing '/'  -> a PATH, verbatim
#   * an argument naming a file   -> a PATH
#   * an argument                 -> $INST/profiles/<name>.profile
#   * no argument                 -> the medium's own declaration in
#                                    $INST/profiles/BASE (written by
#                                    tools/build-install-iso.sh from the family
#                                    the boot slice was built for), so the W4
#                                    miniroot handoff can be a bare
#                                    `exec sh /cdrom/install/bin/setup.sh`.
#                                    Before BASE: BASE.<line> for the running
#                                    kernel's line (k30, k46), from /dev/kinfo
#                                    (C2-1: magic KIF1, the line a big-endian
#                                    long at offset 16, 30 or 46; byte 19 is
#                                    '.' only for 46), so a disc that boots
#                                    both lines names one profile per line.
SETUP_SELF="$0"
case "$SETUP_SELF" in
	*setup.sh) : ;;
	*)         SETUP_SELF="$INST/bin/setup.sh" ;;
esac
SETUP_ARG="$1"

kinfo_line() {
	[ -r /dev/kinfo ] || return 0
	[ "`dd if=/dev/kinfo bs=4 count=1 2>/dev/null`" = KIF1 ] || return 0
	if [ "`dd if=/dev/kinfo bs=20 count=1 2>/dev/null | dd bs=1 skip=19 count=1 2>/dev/null`" = . ]; then
		echo k46
	else
		echo k30
	fi
}
PROFILE_ARG="$SETUP_ARG"
if [ -z "$PROFILE_ARG" ]; then
	KLINE=`kinfo_line`
	if [ -n "$KLINE" ] && [ -f "$INST/profiles/BASE.$KLINE" ]; then
		PROFILE_ARG=`cat "$INST/profiles/BASE.$KLINE"`
	fi
fi
if [ -z "$PROFILE_ARG" ] && [ -f "$INST/profiles/BASE" ]; then
	PROFILE_ARG=`cat "$INST/profiles/BASE"`
	# W4: a RAW payload slice is s5, and s5 truncates every name at 14
	# characters -- `metal-a4000-z3660-raw.profile` is not the name that is
	# actually on the slice. build-raw-source.sh writes the profile under an
	# s5-safe short name for exactly that reason, so when BASE's own name does
	# not resolve, fall back to that short name before giving up. On a CD
	# (Rock Ridge, long names) this branch never fires.
	if [ ! -f "$INST/profiles/$PROFILE_ARG.profile" ] && [ -f "$INST/profiles/raw.profile" ]; then
		PROFILE_ARG=raw
	fi
fi
[ -n "$PROFILE_ARG" ] || PROFILE_ARG=bench-a3000-a4091
case "$PROFILE_ARG" in
	*/*)	PROFILE_FILE="$PROFILE_ARG" ;;
	*)	if [ -f "$PROFILE_ARG" ]; then
			PROFILE_FILE="$PROFILE_ARG"
		else
			PROFILE_FILE="$INST/profiles/$PROFILE_ARG.profile"
		fi ;;
esac
[ -f "$PROFILE_FILE" ] || die "no base profile '$PROFILE_ARG' at $PROFILE_FILE
	(available: `set -- $INST/profiles/*.profile; echo $*`  -- or pass a PATH)"
. "$PROFILE_FILE"

# --- W2 base-profile keys ----------------------------------------------------
#   DDSIZE_SAFE    n   may this rig's /etc/ddsize be called at all? (see above)
#   ANSWERS_ECHO   n   write the composed profile to ANSWERS_ECHO_PATH before
#                      the transplant, so a BLIND console (the install matrix)
#                      can prove the typed answers parsed correctly BEFORE the
#                      five-minute install runs rather than after it.
#   INSTALLABLE_IDS    the ids this medium carries a matching-ROOTDEV TARGET
#                      kernel for. Defaults to the base profile's own
#                      TARGET_SCSI_ID -- today a medium is mastered for exactly
#                      one root device, and offering any other id would install
#                      a kernel that cannot find its root. When P6.3
#                      (root-by-identity) lands, this constraint dies and the
#                      key opens up (plan §8.2).
#   TARGET_BOOT_MB     the boot slice size. The interview does not ASK for this
#                      one -- stock STATES it ("Your boot partition is $BOOTSIZE
#                      megabytes.") -- so the only thing the interview owes it is
#                      to state the TRUTH. BOOTSIZE is set at the top of this
#                      file, before the profile is sourced, so without this the
#                      screen (and plan_root_default's arithmetic behind it)
#                      would still say 2 while the driver made 4. Same floor and
#                      same message as install.sh's copy, deliberately: one key,
#                      two readers, one behaviour.
if [ -n "$TARGET_BOOT_MB" ]; then
	is_num "$TARGET_BOOT_MB" || die "TARGET_BOOT_MB='$TARGET_BOOT_MB' is not a number"
	[ "$TARGET_BOOT_MB" -ge "$MINBOOT" ] || die "TARGET_BOOT_MB=$TARGET_BOOT_MB is below the minimum boot partition of ${MINBOOT}MB"
	BOOTSIZE="$TARGET_BOOT_MB"
fi
# 1.1 (INSTALL_LAYOUT=1.1): the boot slice is the 64 MiB boot store (l11.sh L11_STORE_MB,
# fixed by the spec; l11_keys refuses TARGET_BOOT_MB), and a data slice may come off the
# disk before the root is sized (l11_data_mb, l11.sh's l11_plan_data). The interview plans
# with install.sh's numbers, or its root default is one install.sh refuses.
L11_STORE_MB=64
[ "${INSTALL_LAYOUT:-1.0}" = 1.1 ] && BOOTSIZE="$L11_STORE_MB"
[ -n "$DDSIZE_SAFE" ] || DDSIZE_SAFE=n
[ -n "$ANSWERS_ECHO_PATH" ] || ANSWERS_ECHO_PATH=/matrix.ans
[ -n "$INSTALLABLE_IDS" ] || INSTALLABLE_IDS="$TARGET_SCSI_ID"
[ -n "$INSTALLABLE_IDS" ] || die "base profile $PROFILE_FILE declares neither INSTALLABLE_IDS nor TARGET_SCSI_ID -- no id could ever be installable"

# --- CD-2: the scan a profile names, and the units no scan may open ----------
#   TARGET_SCAN_IDS   when set, the disk scan opens EXACTLY these ids and nothing
#                     else (CD-2: "9" = card 1 unit 1, the Zulu target behind the
#                     A4092). The owner's other disks on that bus (the AmigaOS disk,
#                     an MD-1 root) are then never opened at all, let alone offered.
# Whatever the list, two kinds of id are dropped from it WITHOUT being opened:
#   * the install CD's own unit (cdfs <card>,<unit> -> c<card*8+unit>): a 512-byte
#     dd-layer read of a 2048-byte CD unit behind an A4091/A4092 overruns the
#     SCRIPTS and wedges that bus (A4091-UA, 2026-10-05) -- only cdfs may talk to it;
#   * the host adapters' own ids, unit 7 of each card: 7, f, 17, 1f.
if [ -n "$TARGET_SCAN_IDS" ]; then
	SCAN_IDS="$TARGET_SCAN_IDS"
fi
# D-2 (r6): every id this medium can install to is SCANNED and has its NODES. The
# K1 miniroot carries nodes for c0-c3, c5, c6, c8 and ce only, so an installable
# id outside that set (c4 for the picker's unit 4; c9..cd on card 1) is made here.
# Ids the medium cannot install to keep the old behaviour: no node, open fails,
# skipped -- so a legacy medium's scan is unchanged. A node that cannot be made is
# a warning here (that id just fails at open, as before); install.sh, which writes
# the chosen target, still refuses to go on without its nodes.
for _id in $INSTALLABLE_IDS
do
	case " $SCAN_IDS " in
		*" $_id "*)	;;
		*)		SCAN_IDS="$SCAN_IDS $_id" ;;
	esac
done
SCAN_IDS=`scan_safe_ids $SCAN_IDS`
for _id in $INSTALLABLE_IDS $TARGET_SCAN_IDS
do
	case " $SCAN_IDS " in
		*" $_id "*)	ensure_disk_nodes "$_id" 2>/dev/null || warn "could not create the device nodes for SCSI id $_id -- it will not be scanned" ;;
	esac
done

# The answers beacon also arms itself when the install matrix's own markers are
# already on the root filesystem: the harness writes /matrix.up at the miniroot
# handshake and /matrix.go on the driver line, both BEFORE this script runs. A
# harness that forgot the profile key still gets its beacon, and a real install
# (no markers, key n) writes nothing.
# ---------------------------------------------------------------------------
# THE KEYMAP (W4) -- an answer given BEFORE this script existed
# ---------------------------------------------------------------------------
# The miniroot's /etc/profile asks the keyboard question first, before anything
# is mounted, because you have to be able to type before you can be asked
# anything else. It hands the answer on through two channels, and either alone
# is enough: an exported $KMAP (this script is exec'd by it) and the file
# /tmp/kmap. The FILE wins -- it is the channel that survives a Ctrl-C into an
# interactive shell and back, and its EXISTENCE is itself an answer: an EMPTY
# /tmp/kmap means `usa`, which means bake NOTHING. That is stock's own `unset
# KMAP` semantics and the driver's FB_KMAP semantics, unchanged.
#
# With NEITHER channel present the base profile's own FB_KMAP stands: that is an
# unattended profile run, or a pre-W4 miniroot whose stock id_kmap lost $KMAP at
# the Ctrl-C exec. Never guess a keyboard.
if [ -f "$KMAP_FILE" ]; then
	FB_KMAP=`cat "$KMAP_FILE"`
elif [ -n "$KMAP" ]; then
	FB_KMAP="$KMAP"
fi

case "$ANSWERS_ECHO" in
	[yY]|[yY][eE][sS]|1)	ECHO_ANSWERS=1 ;;
	*)			ECHO_ANSWERS= ;;
esac
if [ -z "$ECHO_ANSWERS" ]; then
	if [ -f /matrix.up ] || [ -f /matrix.go ]; then
		ECHO_ANSWERS=1
	fi
fi

# ---------------------------------------------------------------------------
# restart -- the stock dead-end idiom.
# ---------------------------------------------------------------------------
# Stock printed this and `exit 99`d, and init respawned /etc/profile. This
# script lives on the MEDIUM and nothing respawns it, so it re-execs itself:
# same words, same effect, and a re-run over a half-set-up disk goes back
# through the existing-RDB erase confirmation like any other run.
restart()
{
	readask "\nPress RETURN to restart the installation script. "
	exec sh "$SETUP_SELF" $SETUP_ARG
}

# ---------------------------------------------------------------------------
# 1. DESTINATION DISK
# ---------------------------------------------------------------------------
# Writes one row per PRESENT id to $SCAN_F as
#     <id> <state> <size-or-"?">
# where <state> is one of  ok | source | nokernel .  The loop is fed by a `for`
# over a word list (NOT a redirect), so it is not a subshell -- but it still
# only APPENDS to the file, and every decision is made afterwards, because that
# is the idiom this codebase can prove.
scan_disks()
{
	echo "\nScanning SCSI bus for hard disks..."
	cp /dev/null "$SCAN_F"
	nfound=0
	for i in $SCAN_IDS
	do
		dev="/dev/dsk/c${i}d0s0"
		# ONE bounded read of block 0. rc answers "is there a disk at
		# this id"; the block's first four bytes answer "does it start
		# with an RDB". Absent targets fail at open() -- that is what
		# stock's atdevs relied on too.
		dd if="$dev" of="$BLK0" bs=512 count=1 2>/dev/null
		if [ "$?" != 0 ] || [ ! -s "$BLK0" ]; then
			continue
		fi
		nfound=`expr "$nfound" + 1`

		state=ok
		# The mounted install source is NEVER offered for erasure. On a
		# RAW-source medium the source IS a disk on this bus (the metal
		# self-booting source .hdf sits at id 0), and without this the
		# interview would happily propose erasing the disk it is reading
		# itself from. Mirrors stock's id-4 tape refusal.
		if [ -n "$SRC_SCSI_ID" ] && [ "$i" = "$SRC_SCSI_ID" ]; then
			state=source
		else
			# eligibility: a matching-ROOTDEV TARGET kernel must be
			# on this medium for this id.
			elig=
			for k in $INSTALLABLE_IDS
			do
				if [ "$i" = "$k" ]; then elig=1; fi
			done
			[ -n "$elig" ] || state=nokernel
		fi

		echo "$i $state `disk_size_hint "$i"`" >> "$SCAN_F"
	done
	[ "$nfound" -gt 0 ] || return 1
	return 0
}

# disk_size_hint ID -- echo a megabyte figure for the table, or "?" when we do
# not honestly know one yet. NEVER calls ddsize (see the header): this runs
# once per scanned id, which is exactly where an unbounded call would hurt most.
disk_size_hint()
{
	hid="$1"
	# (1) the medium's own declaration about its own rig.
	if [ -n "$TARGET_DISK_MB" ] && [ "$hid" = "$TARGET_SCSI_ID" ]; then
		echo "$TARGET_DISK_MB"
		return 0
	fi
	# (2) the RDB's extent, when there is an RDB.
	if rdb_present "$hid"; then
		hmb=`rdb_extent_mb "$hid"`
		if is_num "$hmb" && [ "$hmb" -gt 0 ]; then
			echo "$hmb"
			return 0
		fi
	fi
	echo "?"
	return 0
}

# rdb_present ID -- does this disk carry a Rigid Disk Block?
# Two independent readings, and the disk is treated as HAVING an RDB if EITHER
# says so, because the consequence of a false "no" is skipping the erase
# confirmation on a disk that holds somebody's data:
#   * the four bytes at block 0 are "RDSK" (already in $BLK0 from the scan's
#     own read -- re-read here so the helper is usable on its own), and
#   * `/etc/rdb <dev>` exits 0, which is the stock script's own test and the
#     only one that finds an RDB parked in blocks 1..15 (stock's own OLD_BOOT
#     path moved it to block 8 with `rdb -r 8`).
rdb_present()
{
	pdev="/dev/dsk/c${1}d0s0"
	pmagic=`dd if="$pdev" bs=4 count=1 2>/dev/null`
	case "$pmagic" in
		RDSK*)	return 0 ;;
	esac
	if /etc/rdb "$pdev" > /dev/null 2>&1; then
		return 0
	fi
	return 1
}

# rdb_extent_mb ID -- the largest (start + length) over the RDB's partitions,
# in megabytes; nothing when it cannot be read. `/etc/rdb -h 5` returns the
# LAST partition number (stock calls it right after `-a` to learn the number it
# just created) and `/etc/rdb -p N` prints "name start length" -- the exact
# three-token shape stock parses with `set --`.
rdb_extent_mb()
{
	edev="/dev/dsk/c${1}d0s0"
	enp=`/etc/rdb -h 5 "$edev" 2>/dev/null`
	is_num "$enp" || return 0
	[ "$enp" -gt 0 ] || return 0
	emax=0
	for p in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16
	do
		[ "$p" -le "$enp" ] || break
		# Via a FILE, not straight into `set --`: an empty command
		# substitution leaves `set --` a NO-OP on this shell, so a
		# partition rdb declines to print would silently re-use the
		# PREVIOUS partition's numbers (audit I's trap, in its nastiest
		# form -- it would still produce a plausible size).
		/etc/rdb -p "$p" "$edev" > "$SCAN_F.p" 2>/dev/null
		if [ -s "$SCAN_F.p" ]; then
			set -- `cat "$SCAN_F.p"`
		else
			continue
		fi
		# name start length; anything else is skipped rather than guessed at
		if [ "$#" -ge 3 ]; then
			estart="$2"
			elen="$3"
			if is_num "$estart" && is_num "$elen"; then
				eend=`expr "$estart" + "$elen"`
				if [ "$eend" -gt "$emax" ]; then emax="$eend"; fi
			fi
		fi
	done
	rm -f "$SCAN_F.p"
	[ "$emax" -gt 0 ] || return 0
	expr "$emax" / "$BLOCKS_PER_MB"
}

# choose_disk -- print the table, pick an id. Sets SCSI + DISK_MB, or restarts.
choose_disk()
{
	if scan_disks; then
		:
	else
		# stock, verbatim
		echo "\nNo hard disks are attached to this system."
		# ...and then the line stock never had to write, because in 1991
		# nobody tried to install UNIX on an IDE machine. Today the most
		# likely reader of the sentence above is somebody with a stock
		# A4000 or A1200 whose hard disk is working perfectly well and is
		# simply invisible to this kernel. Saying "no disks" and stopping
		# leaves them to conclude their disk is broken. Plan section 6:
		# surface the coverage hole IN THE PRODUCT.
		echo ""
		echo "If this machine's hard disk is an IDE drive -- the internal"
		echo "drive of an A4000, A1200 or A600 -- then it cannot be used."
		echo "There is no Amiga UNIX IDE driver, and there never was one."
		echo "UNIX needs a SCSI host adapter (the A3000 or A4000T onboard"
		echo "controller, an A2091, an A590 or an A4091) with a SCSI disk"
		echo "attached to it."
		restart
	fi

	echo "\nHard disks attached to this system:\n"
	# The eligible ids, collected in the PARENT: the loop below is fed by a
	# redirect and therefore runs in a subshell, so it may only append.
	cp /dev/null "$TOK_F"
	while read sid sstate ssize
	do
		case "$sid" in ""|\#*) continue ;; esac
		if [ "$ssize" = "?" ]; then
			stext="size unknown"
		else
			stext="$ssize megabytes"
		fi
		case "$sstate" in
			ok)		echo "SCSI id $sid		$stext"
					echo "$sid" >> "$TOK_F" ;;
			source)		echo "SCSI id $sid		$stext	source -- not installable" ;;
			nokernel)	echo "SCSI id $sid		$stext	no kernel on this medium for id $sid" ;;
		esac
	done < "$SCAN_F"

	# `[ -s ]` FIRST: `set --` with an empty list is a NO-OP on $@ on this
	# shell, so counting an empty file would return a stale $# (audit I).
	if [ -s "$TOK_F" ]; then
		set -- `cat "$TOK_F"`
	else
		echo "\nNone of the disks on this system can be installed to from this medium."
		echo "This medium carries a UNIX kernel for SCSI id $INSTALLABLE_IDS only."
		restart
	fi

	if [ "$#" -gt 1 ]; then
		ELIGIBLE="$*"
		SCSI=
		while [ "$SCSI" = "" ]
		do
			readask "\nWhat is the SCSI id of the disk you want to install? "
			for i in $ELIGIBLE
			do
				if [ "$ask" = "$i" ]; then
					SCSI="$i"
				fi
			done
			if [ "$SCSI" = "" ]; then
				echo "\nChoose one of the following:\n$ELIGIBLE"
			fi
		done
	else
		# stock: with exactly one candidate the question is not asked.
		SCSI="$1"
	fi

	# the size that was tabled for the chosen id (see the SCAN_F shape).
	DISK_MB=
	while read sid sstate ssize
	do
		case "$sid" in ""|\#*) continue ;; esac
		if [ "$sid" = "$SCSI" ]; then echo "$ssize" > "$BLK0.mb"; fi
	done < "$SCAN_F"
	if [ -f "$BLK0.mb" ]; then
		DISK_MB=`cat "$BLK0.mb"`
		rm -f "$BLK0.mb"
	fi
	case "$DISK_MB" in
		"?")	DISK_MB= ;;
	esac

	# Only NOW, on ONE id, may the stock probe be considered.
	if [ -z "$DISK_MB" ]; then
		case "$DDSIZE_SAFE" in
			[yY]|[yY][eE][sS]|1)
				echo "\nSizing the disk (/etc/ddsize /dev/rdsk/c${SCSI}d0s0) ..."
				pblk=`/etc/ddsize "/dev/rdsk/c${SCSI}d0s0" 2>/dev/null | ( read n rest; echo "$n" )`
				if is_num "$pblk" && [ "$pblk" -gt 0 ]; then
					DISK_MB=`expr "$pblk" / "$BLOCKS_PER_MB"`
				else
					warn "/etc/ddsize returned no usable size for id $SCSI"
				fi
				;;
		esac
	fi
	if [ -z "$DISK_MB" ]; then
		# NG question -- stock never needed it (it always probed). The
		# answer is bounded by the same "is it a number" discipline as
		# everything else, and by the boot+root+swap floors downstream.
		while [ "$DISK_MB" = "" ]
		do
			readask "\nHow many megabytes is this disk? [100] "
			case "$ask" in
				"")	DISK_MB=100 ;;
				[0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9])
					DISK_MB="$ask" ;;
			esac
		done
	fi

	echo "\nYour disk is $DISK_MB megabytes."

	# stock state 5: an existing RDB is destroyed, and the operator says so
	# out loud. NO DEFAULT -- an empty answer re-asks (stock has no "" arm).
	# S4-58: on a 1.1 medium a disk that holds Amix is offered the upgrade first.
	ANS_UPGRADE= ANS_DROP_HOME=
	if rdb_present "$SCSI" && upgrade_offer; then
		return 0
	fi
	if rdb_present "$SCSI"; then
		echo "\nWARNING:  The following existing data on disk will be destroyed.\n"
		/etc/rdb -V "/dev/dsk/c${SCSI}d0s0" 2>/dev/null
		while :
		do
			readask "\nAre you sure you want to erase this disk? "
			case $ask in
				[yY]|[yY][eE][sS] )	break ;;
				[nN]|[nN][oO] )		restart ;;
			esac
		done
	fi
}

# upgrade_offer -- S4-58 (amix-dlm spec 40 §7): the chosen disk holds an Amix system
# and this medium lays the 1.1 disk. Says what an upgrade keeps and what it does not,
# with the size of /home read off the installed root (mounted read-only, measured by
# its own du), and asks: upgrade, erase and install afresh, or stop. Returns 0 for the
# upgrade (ANS_UPGRADE=yes; ANS_DROP_HOME=yes when /home cannot be carried over),
# 1 for an ordinary install (the erase question follows).
upgrade_offer()
{
	[ "${INSTALL_LAYOUT:-1.0}" = 1.1 ] || return 1
	udev="/dev/dsk/c${SCSI}d0s0"
	/etc/rdb -p 1 "$udev" > /tmp/.upo 2>/dev/null
	set x `cat /tmp/.upo`; shift
	[ "$1" = UNIX_Root ] || { rm -f /tmp/.upo; return 1; }
	/etc/rdb -p 2 "$udev" > /tmp/.upo 2>/dev/null
	set x `cat /tmp/.upo`; shift
	[ "$1" = UNIX_Swap ] || { rm -f /tmp/.upo; return 1; }
	uswlen="$3"
	ukind=1.0 udata=
	um=`dd if="/dev/rdsk/c${SCSI}d0s3" bs=512 iseek=2 count=1 2>/dev/null | dd bs=4 count=1 2>/dev/null`
	if [ "$um" = AXS1 ]; then
		ukind=1.1
		/etc/rdb -p 4 "$udev" > /tmp/.upo 2>/dev/null
		set x `cat /tmp/.upo`; shift
		[ "$1" = UNIX_Data ] && udata=y
	fi
	rm -f /tmp/.upo
	uhome=
	if [ -z "$udata" ]; then
		for ufs in ufs s5
		do
			if /etc/mount "/dev/dsk/c${SCSI}d0s1" /mnt 1 $ufs > /dev/null 2>&1; then
				if [ -d /mnt/home ] && [ -x /mnt/usr/sbin/chroot ]; then
					set x `/mnt/usr/sbin/chroot /mnt /usr/bin/du -s /home 2>/dev/null`; shift
					uhome="$1"
				fi
				/etc/umount /mnt
				break
			fi
		done
	fi
	echo "\nThis disk holds an Amiga UNIX $ukind installation."
	echo "An upgrade installs this disc's system again and keeps the configuration:"
	echo "the node name, users and passwords, the network, the time zone and the"
	echo "first-boot answers."
	echo "Not kept: every package beyond this disc's set, and every other file on the root."
	if [ -n "$udata" ]; then
		echo "/home is on its own partition and stays as it is."
	elif is_num "$uhome"; then
		umb=`expr "$uhome" / 2048`
		ucap=`expr "$uswlen" - 2048`
		if [ "$uhome" -gt "$ucap" ]; then
			echo "/home holds $umb megabytes, more than an upgrade can carry over: it is LOST."
			ANS_DROP_HOME=yes
		elif [ "$umb" = 0 ]; then
			echo "/home holds less than a megabyte and is carried over."
		else
			echo "/home holds $umb megabytes and is carried over."
		fi
	fi
	while :
	do
		echo ""
		echo "  1)   Upgrade this installation"
		echo "  2)   Erase the disk and install afresh"
		echo "  3)   Stop"
		readask "\nWhich? [1] "
		case $ask in
			""|1)	ANS_UPGRADE=yes; return 0 ;;
			2)	ANS_DROP_HOME=; return 1 ;;
			3)	restart ;;
		esac
	done
}

# upgrade_sizes -- an upgrade asks no sizes: a 1.1 disk keeps its layout and a 1.0 disk
# is re-laid to the driver's defaults (the old swap slice, which holds the saved
# configuration, is checked against them there). The values here are for the space
# check and the summary only; the answers carry no sizes.
upgrade_sizes()
{
	if plan_root_default "$DISK_MB"; then
		:
	else
		echo "\nA ${DISK_MB} megabyte disk is too small to install UNIX on."
		restart
	fi
	ANS_ROOT="$DEF_ROOT"
	plan_swap_default "$ANS_ROOT"
	ANS_SWAP="$DEF_SWAP"
	ANS_FSYS="${TARGET_ROOT_FSTYPE:-ufs}"
}

# ---------------------------------------------------------------------------
# 1b. THE OLD_BOOT MACHINE CLASS (W6, plan section 6)
# ---------------------------------------------------------------------------
# ★ THE ONE COVERAGE HOLE THAT CURRENTLY FAILS UNDIAGNOSED. Stock 2.1 supported
# a class of machine this installer does not: Kickstart 1.3 boxes and A2090
# controllers, which cannot be booted by the modern boot chain at all and which
# stock handled with the "old Johann ROM magic cookie" method -- an RDB moved to
# block 8 and a patched boot block. Nothing in this tree does that, and nothing
# in this tree NOTICES: the install would run to completion, write a perfectly
# good root filesystem and a boot slice those ROMs cannot read, and the machine
# would simply never boot. Unlike the IDE hole (which at least announces itself
# as "no disks"), this one has no symptom until the disc comes out.
#
# The detection is not new work and not a guess -- it is stock's own, verbatim,
# using the two probes the miniroot still carries for exactly this purpose:
#
#     ROMSIZE=`/etc/romsize`         # < 524288 => a 256 KB ROM => Kickstart 1.3
#     set `/etc/dioc 1 < $rDISK`     # $1 == "A2090" => the old controller
#     OLD_BOOT = (small ROM) OR (A2090)
#
# FAILS OPEN, deliberately and in every direction. A probe that is missing,
# unreadable, silent, or that answers with anything other than a plain number /
# a controller name leaves OLD_BOOT unset and the install proceeds. The cost of
# a false positive here is refusing every machine this installer CAN do; the
# cost of a false negative is the situation we are already in. (Bench-measured
# on the canonical rig, 2026-08-12: see docs/installer.md.)
check_old_boot()
{
	OB_ROM=
	OB_CTL=
	OB=
	if [ -x /etc/romsize ]; then
		OB_ROM=`/etc/romsize 2>/dev/null`
	fi
	if [ -x /etc/dioc ]; then
		# Via a FILE, then `[ -s ]`, then `set --`: an empty command
		# substitution leaves `set --` a NO-OP on this shell -- it does
		# NOT clear $@ -- so an unguarded `set -- \`cat FILE\`` on an
		# empty file reads back whatever $@ already held (audit I; the
		# same trap rdb_extent_mb documents). Here that is a function
		# called with no arguments, so the guard is belt-and-braces
		# rather than load-bearing; it is written this way because the
		# next reader should not have to work that out.
		/etc/dioc 1 < "/dev/rdsk/c${SCSI}d0s0" > "$SCAN_F.c" 2>/dev/null
		if [ -s "$SCAN_F.c" ]; then
			set -- `cat "$SCAN_F.c"`
			if [ "$#" -ge 1 ]; then OB_CTL="$1"; fi
		fi
		rm -f "$SCAN_F.c"
	fi

	case "$OB_ROM" in
		"")		: ;;	# no probe, no answer -- fail open
		*[!0-9]*)	: ;;	# not a plain number -- fail open
		*)		if [ "$OB_ROM" -lt 524288 ]; then OB=rom; fi ;;
	esac
	if [ "$OB_CTL" = A2090 ]; then OB=controller; fi
	[ -n "$OB" ] || return 0

	echo "\nThis machine is not supported by this installation disc."
	echo ""
	case "$OB" in
		rom)
			echo "Its Kickstart ROM is $OB_ROM bytes.  A ROM this small is"
			echo "Kickstart 1.3, and UNIX can only be started on such a"
			echo "machine by the old 2620/2630 ROM boot method."
			;;
		controller)
			echo "Its disk controller is an $OB_CTL.  UNIX can only be"
			echo "started from that controller by the old 2620/2630 ROM"
			echo "boot method."
			;;
	esac
	echo ""
	echo "This disc writes the modern boot chain only.  Install from the"
	echo "original Amiga UNIX 2.1 distribution instead:  its own install"
	echo "script performs the old boot patching, and it supports this"
	echo "machine."
	restart
}

# ---------------------------------------------------------------------------
# 2. PARTITION SIZES
# ---------------------------------------------------------------------------
# l11_data_mb DISK_MB -- DATA_MB, the 1.1 data slice (s4): l11.sh's l11_plan_data,
# the same rule on the same keys (TARGET_DATA_MB, else a quarter of a disk of 512 MB
# or more), capped at 1024 MB and at the stock kernel's on-box ceiling.
l11_data_mb()
{
	if [ -n "$TARGET_DATA_MB" ]; then
		is_num "$TARGET_DATA_MB" || die "TARGET_DATA_MB='$TARGET_DATA_MB' is not a number"
		DATA_MB="$TARGET_DATA_MB"
	elif [ "$1" -ge 512 ]; then
		DATA_MB=`expr "$1" / 4`
	else
		DATA_MB=0
	fi
	if [ "$DATA_MB" -gt 1024 ]; then DATA_MB=1024; fi
	if [ "$KERNEL_SDDEVSIZE" != fixed ]; then
		_cap=`expr "$SDDEV_CAP_BLOCKS" / "$BLOCKS_PER_MB"`
		if [ "$DATA_MB" -gt "$_cap" ]; then DATA_MB="$_cap"; fi
	fi
}

# plan_root_default DISK_MB -- sets PRE_REMAIN (blocks left after offset
# rounding and the boot partition), DEFSWAP, ROOTMAX and DEF_ROOT. This is
# install.sh's plan_partitions, step for step, on the same constants; audit V
# EXECUTES both and requires the same numbers for a range of disk sizes, so the
# default this screen SHOWS is by construction the layout the driver BUILDS.
plan_root_default()
{
	pdisk="$1"
	DISKLEN=`expr "$pdisk" \* "$BLOCKS_PER_MB"`
	off="$OFFSET_BLOCKS"
	PRE_REMAIN=`expr "$DISKLEN" - "$off"`
	ROUND=`expr "$off" % "$SECS"`
	if [ "$ROUND" -gt 0 ]; then
		add=`expr "$SECS" - "$ROUND"`
		off=`expr "$off" + "$add"`
		PRE_REMAIN=`expr "$PRE_REMAIN" - "$add"`
	fi
	rmod=`expr "$PRE_REMAIN" % "$SECS"`
	PRE_REMAIN=`expr "$PRE_REMAIN" - "$rmod"`
	BOOTLEN=`expr "$BOOTSIZE" \* "$BLOCKS_PER_MB"`
	if [ "$BOOTLEN" -ge "$PRE_REMAIN" ]; then
		return 1
	fi
	PRE_REMAIN=`expr "$PRE_REMAIN" - "$BOOTLEN"`
	DATA_MB=0
	if [ "${INSTALL_LAYOUT:-1.0}" = 1.1 ]; then
		l11_data_mb "$pdisk"
		datalen=`expr "$DATA_MB" \* "$BLOCKS_PER_MB"`
		[ "$datalen" -lt "$PRE_REMAIN" ] || return 1
		PRE_REMAIN=`expr "$PRE_REMAIN" - "$datalen"`
	fi
	if [ "$pdisk" -gt "$BREAKPT" ]; then DEFSWAP="$LGSWAP"; else DEFSWAP="$SMSWAP"; fi
	# r6 (owner 2026-10-06): the 040/060 kernels link a 61440-sector (30 MB) swapfile; a shorter
	# slice 2 leaves the tail of that swap failing with EIO -- so 30 MB is the default AND the floor.
	if [ "${INSTALL_CPU:-030}" = 040 ] || [ "${INSTALL_CPU:-030}" = 060 ]; then
		DEFSWAP=30; MINSWAP=30
		SWAPWHY="The 68040/68060 kernel's swap area is 30 megabytes."
	fi
	# stepped out into temp variables rather than nested backticks -- the same
	# call install.sh's plan_partitions makes, written the same way.
	minswblk=`expr "$MINSWAP" \* "$BLOCKS_PER_MB"`
	rootmaxblk=`expr "$PRE_REMAIN" - "$minswblk"`
	ROOTMAX=`expr "$rootmaxblk" / "$BLOCKS_PER_MB"`
	swblk=`expr "$DEFSWAP" \* "$BLOCKS_PER_MB"`
	rootblk=`expr "$PRE_REMAIN" - "$swblk"`
	DEF_ROOT=`expr "$rootblk" / "$BLOCKS_PER_MB"`
	# E-BIG: the same stock-kernel root ceiling the driver enforces.
	ROOTCAP=
	[ "$KERNEL_SDDEVSIZE" = fixed ] || ROOTCAP=`expr "$SDDEV_CAP_BLOCKS" / "$BLOCKS_PER_MB"`
	if [ -n "$ROOTCAP" ] && [ "$ROOTMAX" -gt "$ROOTCAP" ]; then ROOTMAX="$ROOTCAP"; fi
	if [ -n "$ROOTCAP" ] && [ "$DEF_ROOT" -gt "$ROOTCAP" ]; then DEF_ROOT="$ROOTCAP"; fi
	# ★ NG, and it is a REAL fix, not a flourish. On a disk under ~23 MB the
	# stock arithmetic yields a NEGATIVE ROOTMAX, and stock's own loop would
	# then reject every possible answer -- "You must leave at least 5 megabytes
	# free for swap space." forever, with no way out but Ctrl-C. Refuse the
	# disk instead: if no answer can satisfy both stock floors at once, there
	# is no question to ask.
	[ "$ROOTMAX" -ge "$MINROOT" ] || return 1
	# Between ~23 and ~36 MB the DEFAULT (which reserves the full default swap)
	# lands under MINROOT while a legal answer still exists. Stock would offer
	# that illegal default and accept it on a bare RETURN; our driver then dies
	# at its own MINROOT gate. Clamp the OFFER to the floor -- the operator can
	# still type anything up to ROOTMAX.
	if [ "$DEF_ROOT" -lt "$MINROOT" ]; then DEF_ROOT="$MINROOT"; fi
	return 0
}

# plan_swap_default ROOT_MB -- sets MAXSWAP and DEF_SWAP from PRE_REMAIN, after
# the root answer is known. Stock computes its swap default in exactly this
# order, and so does the driver (its TARGET_SWAP_MB bound is MAXSWAP).
plan_swap_default()
{
	sroot="$1"
	srootlen=`expr "$sroot" \* "$BLOCKS_PER_MB"`
	smod=`expr "$srootlen" % "$SECS"`
	srootlen=`expr "$srootlen" - "$smod"`
	sremain=`expr "$PRE_REMAIN" - "$srootlen"`
	MAXSWAP=`expr "$sremain" / "$BLOCKS_PER_MB"`
	DEF_SWAP="$MAXSWAP"
	if [ "$DEF_SWAP" -gt "$DEFSWAP" ]; then DEF_SWAP="$DEFSWAP"; fi
}

ask_sizes()
{
	if plan_root_default "$DISK_MB"; then
		:
	else
		echo "\nA ${DISK_MB} megabyte disk is too small to install UNIX on."
		restart
	fi

	echo "\nYour boot partition is $BOOTSIZE megabytes."
	[ "$DATA_MB" -gt 0 ] && echo "Your data partition is $DATA_MB megabytes."

	ANS_ROOT=
	while [ "$ANS_ROOT" = "" ]
	do
		readask "\nHow many megabytes for the root file system? [$DEF_ROOT] "
		case "$ask" in
			"")
				ANS_ROOT="$DEF_ROOT"
				;;
			[0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9])
				if [ "$ask" -lt "$MINROOT" ]
				then
					echo "\nYour root partition must be at least $MINROOT megabytes."
				fi
				if [ "$ask" -gt "$ROOTMAX" ]
				then
	if [ -n "$ROOTCAP" ] && [ "$ask" -gt "$ROOTCAP" ]; then
		echo "\nThis kernel limits an on-box root to $ROOTCAP megabytes."
	else
	echo "\nYou must leave at least $MINSWAP megabytes free for swap space."
	fi
				else
					if [ "$ask" -ge "$MINROOT" ]; then ANS_ROOT="$ask"; fi
				fi
		esac
	done

	plan_swap_default "$ANS_ROOT"

	ANS_SWAP=
	while [ "$ANS_SWAP" = "" ]
	do
		readask "\nHow many megabytes for the swap partition? [$DEF_SWAP] "
		case "$ask" in
			"" )
				ANS_SWAP="$DEF_SWAP"
				;;
			[0-9]|[0-9][0-9]|[0-9][0-9][0-9]|[0-9][0-9][0-9][0-9])
				ANS_SWAP="$ask"
				if [ "$ask" -lt "$MINSWAP" ]
				then
					echo "\nYou must have at least $MINSWAP megabytes of swap space."
					[ -n "${SWAPWHY:-}" ] && echo "$SWAPWHY"
					ANS_SWAP=
				fi
				if [ "$ask" -gt "$MAXSWAP" ]
				then
					echo "\nYou only have $MAXSWAP remaining megabytes available."
					ANS_SWAP=
				fi
		esac
	done
}

# ---------------------------------------------------------------------------
# 3. ROOT FILESYSTEM TYPE -- the stock menu, default moved to ufs
# ---------------------------------------------------------------------------
# ★ STOCK, QUOTED RATHER THAN IMITATED. Extracted from /etc/profile on the stock
# root floppy (floppies/orig/amix_21_root.adf, ino 166, 19,351 B, md5
# 97f800ec7bcd627bfed2322fdc19f86b) with tools/lib/s5.py, verbatim -- every echo,
# every blank line, the prompt, and the case arms:
#
#     UFS_OPT="-o free=2,opt=s"	#options for mkfs_ufs
#     ...
#     if [ "$OLD_BOOT" = "0" ]
#     then
#         unset ANS
#         while [ "$ANS" = "" ]
#         do
#             unset ROOT_OPT
#             echo "\nChoose a file system type for the root partition:"
#             echo ""
#             echo "    s5:  Traditional UNIX file system"
#             echo "   ufs:  Berkeley file system"
#             echo ""
#             readask "What file system type is the root partition? [s5] "
#             case $ask in
#             "")     ANS="s5" ;;
#             "s5")   ANS="s5" ;;
#             "ufs")  ANS="ufs" ; ROOT_OPT="$UFS_OPT" ;;
#             "*")    echo "Available file system types are s5 and ufs."
#             esac
#         done
#         ROOT_FSYS="$ANS"
#     else
#         ROOT_FSYS="s5"		# Johann ROM can only boot s5 filesystem
#     fi
#
# Two things about that block are worth keeping straight, because the story
# "stock forced s5" is half true and the half that is true is not this:
#
#   * the WHOLE block sits inside `if [ "$OLD_BOOT" = "0" ]`, and the else arm is
#     `ROOT_FSYS="s5"   # Johann ROM can only boot s5 filesystem`. THAT is the
#     force -- and it applies to a machine class we refuse outright, by name,
#     before any of this runs (check_old_boot above). So the branch that forces
#     s5 is one we never take.
#   * the option constant is carried by the ANSWER, not by the filesystem: only
#     the ufs arm sets ROOT_OPT. Our driver holds the same constant on its own
#     side (install.sh, the mkfs_ufs arm), so this script hands over a TYPE and
#     nothing else -- one fact in one place.
#
# We keep stock's shape, its blank lines and its strings, and change ONE WORD:
# the default is `[ufs]`.
#
# One repair comes with it. Stock QUOTED its `*` glob, and in a `case` a quoted
# `"*"` matches a LITERAL asterisk -- so that arm never fired. A typo therefore
# fell through the whole case with ANS unset, the `while [ "$ANS" = "" ]` loop
# went round again, and the message nobody wrote to be unreachable was never
# printed in 1991. Ours is unquoted, so the typo is caught and the string finally
# does what it says. (Its text is stock's, to the byte.)
ask_fstype()
{
	# ★ NEVER SHOW A LOCKED QUESTION (the stock idiom, and this file's own rule).
	# The 040/060 install line is UFS-ONLY: s5 is structurally broken under the
	# 4 KiB pages that line runs (docs/miniroot.md "The UFS miniroot"; the 040/060
	# campaign plan §1). So on that line there is nothing to decide -- the ufs
	# miniroot is what booted, and the driver would refuse an s5 target here
	# anyway. Lock it, exactly as the prebuilt case below does. INSTALL_CPU comes
	# from the base profile this script already sourced (absent => the 030 line).
	if [ "${INSTALL_CPU:-030}" = 040 ] || [ "${INSTALL_CPU:-030}" = 060 ]; then
		ANS_FSYS=ufs
		return 0
	fi
	# A prebuilt target already HAS its filesystem -- mkroot.sh minted it
	# host-side, in s5 -- so there is nothing to decide and the driver would
	# refuse any other answer anyway.
	if [ "${INSTALL_TARGET_PREBUILT:-0}" = 1 ]; then
		ANS_FSYS=s5
		return 0
	fi
	ANS_FSYS=
	while [ "$ANS_FSYS" = "" ]
	do
		echo "\nChoose a file system type for the root partition:"
		echo ""
		echo "    s5:  Traditional UNIX file system"
		echo "   ufs:  Berkeley file system"
		echo ""
		readask "What file system type is the root partition? [ufs] "
		case "$ask" in
			"")	ANS_FSYS=ufs ;;
			s5)	ANS_FSYS=s5 ;;
			ufs)	ANS_FSYS=ufs ;;
			*)	echo "Available file system types are s5 and ufs." ;;
		esac
	done
}

# ---------------------------------------------------------------------------
# 4. PACKAGE SET -- amixpkg's three-tier menu (W3b)
# ---------------------------------------------------------------------------
# The menu is amixpkg's OWN and it is THREE ROWS; it always was, W2 simply had
# only one set to put in it. The format strings, recovered from /bin/amixpkg's
# .rodata (docs/installer.md "The stock amixpkg screens"):
#
#     (1)  Standard Amiga UNIX installation    %6.1f MB
#     (2)  Everything on the tape              %6.1f MB
#     (3)  Custom selection
#     Choose: [1]
#
# "tape" -> "disc" is the ONE changed word (plan §2.7). Both labels sit in a
# 36-column field ("Standard Amiga UNIX installation" is 32 + 4 spaces,
# "Everything on the tape" is 22 + 14), so the %6.1f lands at columns 42..47 in
# both rows; padr() reproduces that without a printf, which the miniroot has not.
#
# ROWS 1 AND 2 ARE MEDIA FACTS, read from /install/sets, which
# tools/build-install-iso.sh authors from the packagemanager's sets.conf:
#
#     <num> <setname> <orderfile> <attested> <label...>
#
# Row 1 is the `standard` set when the medium carries all of it -- that is what
# "Standard Amiga UNIX installation" MEANT on the tape -- and the medium's own
# mastered set otherwise (on a base-8 disc there is no larger truth to offer).
# Row 2 is everything on the disc. Row 3, Custom, is a property of the interview
# rather than of the disc, so it is appended here. A medium mastered before W3b
# has no /install/sets and the two tiers are synthesized from its single
# /install/order: the menu keeps three rows and the same numbering either way,
# which is what the blind-console install matrix types into.
#
# ATTESTATION (plan §5.7, locked). Each row declares whether a REFERENCE
# INSTALLED-TREE DIGEST exists for that set. A row that says n -- and every
# Custom selection, always -- is marked "unattested selection" on the
# confirmation screen and lands in the answers profile as INSTALL_ATTESTED=n,
# which the driver copies into the install log in as many words. The digest gate
# is not softened for those runs; it is WAIVED, visibly. The install matrix only
# ever drives attested sets.
#
# SIZES come from the catalog's opt-in `#isize` extension block (gen-catalog.py
# --isize), BUDGETED at ~1.10x. The block is a payload BYTE SUM; an s5 filesystem
# charges 1 KB blocks plus indirect blocks plus directories, measured at ~1.08x
# against the original tape's own 512-byte-block accounting. The figure the menu
# shows is therefore the FOOTPRINT, directly comparable to the root partition the
# operator has just sized -- which is exactly what the free-space check compares.
# A medium with no #isize block prints NO figure, never 0.0.

# padr TEXT WIDTH -- TEXT padded on the RIGHT to WIDTH columns: printf's %-Ns,
# without printf. Two `expr` forks plus one per eight columns of deficit, so the
# widest frozen field (%-40s) costs at most seven. That matters: the custom table
# re-renders every package on every keystroke, and this is a 68030.
padr()
{
	ptx="$1"
	# ★ THE "X" IS LOAD-BEARING. The rule row pads the literal `----`, and an
	# `expr` handed an argument that starts with a dash reads it as an OPTION --
	# `expr -- : '.*'` is a syntax error on a modern expr, and nothing here would
	# survive the column shift. Measuring "X$ptx" makes the first character
	# always a letter; the +1 it costs is cancelled in the same subtraction, so
	# this is still TWO forks, not three.
	pl=`expr "X$ptx" : '.*'`
	pd=`expr "$2" + 1 - "$pl"`
	while [ "$pd" -ge 8 ]
	do
		ptx="$ptx        "
		pd=`expr "$pd" - 8`
	done
	case "$pd" in
		1)	ptx="$ptx " ;;
		2)	ptx="$ptx  " ;;
		3)	ptx="$ptx   " ;;
		4)	ptx="$ptx    " ;;
		5)	ptx="$ptx     " ;;
		6)	ptx="$ptx      " ;;
		7)	ptx="$ptx       " ;;
	esac
	echo "$ptx"
}

# pad6 TEXT -- right-align TEXT in six columns, so a MB figure lands where
# amixpkg's %6.1f put it. `expr STR : '.*'` is the miniroot's only string length
# (no wc, no printf).
pad6()
{
	pl=`expr "$1" : '.*'`
	case "$pl" in
		1)	echo "     $1" ;;
		2)	echo "    $1" ;;
		3)	echo "   $1" ;;
		4)	echo "  $1" ;;
		5)	echo " $1" ;;
		*)	echo "$1" ;;
	esac
}

# bytes_mb1 BYTES -- "N.N" megabytes. Whole megabytes FIRST and only then the
# remainder scaled, so nothing here overflows a 32-bit `expr`.
bytes_mb1()
{
	bmb=`expr "$1" / 1048576`
	brem=`expr "$1" % 1048576`
	brx=`expr "$brem" \* 10`
	bt=`expr "$brx" / 1048576`
	echo "$bmb.$bt"
}

# budget BYTES -- the ~1.10x s5 footprint of a payload byte sum. Written as
# b + b/10 and NOT as b*11/10 deliberately: the full set is ~290 MB, b*11 is
# 3.2e9, and a signed 32-bit `expr` would hand back a NEGATIVE budget that every
# free-space comparison downstream would happily accept.
budget()
{
	# TWO single-operator `expr`s, not one `a + a / 10`: every other arithmetic
	# line in this file and in install.sh is a single operator, so operator
	# PRECEDENCE in the 1991 expr is an assumption nothing here has ever tested.
	# Two calls cost one fork and assume nothing.
	bten=`expr "$1" / 10`
	expr "$1" + "$bten"
}

# order_size_bytes ORDERFILE -- the payload byte sum of that order file's
# packages, or NOTHING when the medium cannot answer honestly. Deliberately
# ALL-OR-NOTHING: a partial sum printed as a figure is worse than no figure,
# because the operator cannot tell the two apart, and a missing #isize line means
# UNKNOWN, never zero. Package names differ between the order file (pkginst, e.g.
# APKGENG) and the catalog (lowercase name, e.g. apkgeng), so the catalog's own
# entry lines map one to the other before the sum.
order_size_bytes()
{
	sfile="$1"
	[ -f "$CDROOT/catalog" ] || return 0
	[ -f "$sfile" ] || return 0

	# (a) wanted pkginst tokens, from the order file -> a space-delimited
	#     string built in the PARENT (the loop is redirect-fed = a subshell).
	cp /dev/null "$TOK_F"
	while read pkg
	do
		case "$pkg" in ""|\#*) continue ;; esac
		echo "$pkg" >> "$TOK_F"
	done < "$sfile"
	[ -s "$TOK_F" ] || return 0
	set -- `cat "$TOK_F"`
	WANT=" $* "
	nwant="$#"

	# (b) map to catalog names: an entry line is
	#     name|version|pkginst|filename|md5|size|deps|category|description
	cp /dev/null "$CATN_F"
	while read cline
	do
		case "$cline" in ""|\#*) continue ;; esac
		cn=`expr "$cline" : '\([^|]*\)|'`
		ci=`expr "$cline" : '[^|]*|[^|]*|\([^|]*\)|'`
		[ -n "$cn" ] || continue
		case "$WANT" in
			*" $ci "*)	echo "$cn" >> "$CATN_F" ;;
			*" $cn "*)	echo "$cn" >> "$CATN_F" ;;
		esac
	done < "$CDROOT/catalog"
	[ -s "$CATN_F" ] || return 0
	set -- `cat "$CATN_F"`
	CATWANT=" $* "
	ncat="$#"

	# every wanted package must have been found, or we do not know the size
	[ "$ncat" = "$nwant" ] || return 0

	# (c) the #isize lines for exactly those catalog names
	cp /dev/null "$ISZ_F"
	while read itag iname ibytes irest
	do
		case "$itag" in
			"#isize")	: ;;
			*)		continue ;;
		esac
		is_num "$ibytes" || continue
		case "$CATWANT" in
			*" $iname "*)	echo "$ibytes" >> "$ISZ_F" ;;
		esac
	done < "$CDROOT/catalog"
	[ -s "$ISZ_F" ] || return 0
	set -- `cat "$ISZ_F"`
	[ "$#" = "$ncat" ] || return 0

	tot=0
	for b in "$@"
	do
		tot=`expr "$tot" + "$b"`
	done
	echo "$tot"
	return 0
}

# set_size_mb ORDERFILE -- the menu's MB column: the BUDGETED footprint of that
# set as "N.N", or nothing at all when the medium cannot answer.
set_size_mb()
{
	sbytes=`order_size_bytes "$1"`
	is_num "$sbytes" || return 0
	sbud=`budget "$sbytes"`
	bytes_mb1 "$sbud"
	return 0
}

# build_set_table -- $SET_F gets the menu, one row per line:
#     <num> <setname> <orderfile|-> <attested> <label...>
# and $R1*/$R2* get rows 1 and 2 in the PARENT (a brace group with one
# redirection is not a subshell, so two `read`s off it survive).
build_set_table()
{
	[ -f "$INST/order" ] || die "no install order file on this medium ($INST/order) -- the disc is not an install disc"
	cp /dev/null "$SET_F"
	if [ -f "$INST/sets" ]; then
		while read snum srest
		do
			case "$snum" in ""|\#*) continue ;; esac
			[ -n "$srest" ] || continue
			echo "$snum $srest" >> "$SET_F"
		done < "$INST/sets"
	fi
	if [ -s "$SET_F" ]; then
		:
	else
		# pre-W3b medium: one order file, and no claim about which named set
		# it is. It is the medium's default, which is what has always been
		# attested, so the tiers say so and both point at the same file.
		echo "1 default order y Standard Amiga UNIX installation" >> "$SET_F"
		echo "2 default order y Everything on the disc" >> "$SET_F"
	fi
	echo "3 custom - n Custom selection" >> "$SET_F"

	# Row 1's ORDER FILE and row 2's SET NAME, back in the PARENT.
	#
	# ★ NOT `{ read A; read B; } < "$SET_F"`. That was W3b's first try and the
	# bench refused it outright: this shell FORKS for a compound command with an
	# input redirection -- the same reason every `while read ... done < FILE`
	# loop in this tree is treated as a subshell -- so both reads happened in a
	# child and the parent saw nothing (`STOP: internal: /cdrom/install/sets has
	# no usable first row`, run w3b2-cdi). Values come back through the
	# FILESYSTEM here, which is the only channel this shell cannot lose.
	rm -f "$SET_F.r1o" "$SET_F.r2s"
	while read snum sname sord satt slbl
	do
		case "$snum" in
			1)	echo "$sord" > "$SET_F.r1o" ;;
			2)	echo "$sname" > "$SET_F.r2s" ;;
		esac
	done < "$SET_F"
	R1ORD=
	R2SET=
	if [ -s "$SET_F.r1o" ]; then R1ORD=`cat "$SET_F.r1o"`; fi
	if [ -s "$SET_F.r2s" ]; then R2SET=`cat "$SET_F.r2s"`; fi
	rm -f "$SET_F.r1o" "$SET_F.r2s"
	[ -n "$R1ORD" ] || die "internal: $INST/sets has no usable first row"
	[ -n "$R2SET" ] || R2SET=set
	return 0
}

show_set_menu()
{
	echo ""
	while read snum sname sord satt slbl
	do
		case "$snum" in ""|\#*) continue ;; esac
		if [ "$sord" = "-" ]; then
			echo "($snum)  $slbl"
			continue
		fi
		ssize=`set_size_mb "$INST/$sord"`
		if [ -n "$ssize" ]; then
			echo "($snum)  `padr "$slbl" 36``pad6 "$ssize"` MB"
		else
			echo "($snum)  $slbl"
		fi
	done < "$SET_F"
}

pick_set()
{
	SET_NUM=
	while [ "$SET_NUM" = "" ]
	do
		readask "Choose: [1] "
		case "$ask" in
			"")	ask=1 ;;
		esac
		# One FILE per field, `cat` back in the parent -- never a redirected
		# `read`, which this shell may run in a fork (see build_set_table).
		rm -f "$SET_F.n" "$SET_F.s" "$SET_F.o" "$SET_F.a" "$SET_F.l"
		while read snum sname sord satt slbl
		do
			case "$snum" in ""|\#*) continue ;; esac
			if [ "$ask" = "$snum" ]; then
				echo "$snum"  > "$SET_F.n"
				echo "$sname" > "$SET_F.s"
				echo "$sord"  > "$SET_F.o"
				echo "$satt"  > "$SET_F.a"
				echo "$slbl"  > "$SET_F.l"
			fi
		done < "$SET_F"
		if [ -s "$SET_F.n" ]; then
			SET_NUM=`cat "$SET_F.n"`
			SET_NAME=`cat "$SET_F.s"`
			SET_ORDBASE=`cat "$SET_F.o"`
			SET_ATT=`cat "$SET_F.a"`
			SET_LABEL=`cat "$SET_F.l"`
		fi
		rm -f "$SET_F.n" "$SET_F.s" "$SET_F.o" "$SET_F.a" "$SET_F.l"
	done
}

# check_space ORDERFILE -- the menu-time free-space check, with stock's own
# overcommit override kept verbatim (amixpkg's WARNING + "Go ahead with the
# installation anyway? [n] "). An UNKNOWN size is no gate at all: refusing an
# install because the medium declined to say how big a set is would be treating
# "unknown" as "too big", which is the same class of mistake as treating it as 0.
#
# ★ THE UFS SUPERUSER RESERVE IS SUBTRACTED HERE, because stock subtracted it
# here -- in the same position, before package selection:
#     if [ $ROOT_FSYS = "ufs" ] ; then
#         MARGIN=`expr $ROOTLEN '/' 50`
#         AVAILABLE=`expr $ROOTLEN '-' $MARGIN`
#     else
#         AVAILABLE=$ROOTLEN
#     fi
# `-o free=2` keeps 2% of a ufs filesystem for the superuser, so 2% of the root
# is not available to a package set and a check that ignored it would be
# optimistic by exactly that much -- enough for a set that just fits on s5 to
# overrun on ufs. Stock got this right in 1991; the arithmetic is `expr` and
# integer division, as everywhere in this file.
check_space()
{
	avail="$ANS_ROOT"
	if [ "$ANS_FSYS" = ufs ]; then
		margin=`expr "$ANS_ROOT" / 50`
		avail=`expr "$ANS_ROOT" - "$margin"`
	fi
	kbytes=`order_size_bytes "$1"`
	is_num "$kbytes" || return 0
	kbud=`budget "$kbytes"`
	kmb=`expr "$kbud" / 1048576`
	[ "$kmb" -gt "$avail" ] || return 0
	while :
	do
		echo "\nWARNING:  Your allocated space for installation is $avail MB,"
		echo "but you have selected to install $kmb MB."
		readask "\nGo ahead with the installation anyway? [n] "
		case $ask in
			[yY]|[yY][eE][sS] )	return 0 ;;
			[nN]|[nN][oO]|"" )	return 1 ;;
		esac
	done
}

ask_set()
{
	build_set_table
	SET_ORDER=
	while [ "$SET_ORDER" = "" ]
	do
		show_set_menu
		pick_set
		if [ "$SET_ORDBASE" = "-" ]; then
			if custom_select; then
				SET_NAME=custom
				SET_ATT=n
				SET_LABEL="Custom selection ($CUSTOM_N packages)"
				SET_ORDER="$CUSTOM_ORDER"
			fi
		else
			SET_ORDER="$INST/$SET_ORDBASE"
		fi
		if [ "$SET_ORDER" != "" ]; then
			if check_space "$SET_ORDER"; then
				:
			else
				SET_ORDER=
			fi
		fi
	done
}

# ---------------------------------------------------------------------------
# 3b. THE CUSTOM TABLE (amixpkg's own; column layout FROZEN 2026-08-11)
# ---------------------------------------------------------------------------
#     %-8s %-10s %-40s %6.1f      Inst / Name / Description / Size, Size LAST
#     header + rule use %-8s %-10s %-40s %8s with "Size  " / "----  ",
#     the pre-total rule is "====  ", and the total is %53s Total: %6.1f MB.
# Surrounding text, verbatim from the binary:
#     "\nTape contents:  %s\n"   ("Disc" here -- the same one changed word)
#     "\nEnter package name to install or ignore; enter GO when ready.\n"
#     "Unknown package:  %s\n"
# Keywords: all / standard / none / GO / go / restart.
#
# THE UNIVERSE is /install/order -- everything on this disc, in that file's own
# order. build-iso.sh refuses to master a disc carrying a package the set does
# not name, so "the mastered set" and "everything on the disc" are the same
# thing by construction. The order is topological, and a SUBSET of a topological
# order is still topological, so the custom screen only ever FILTERS it: no
# dependency solver ever runs on the miniroot.
#
# SELECTION STATE is one marker FILE per package ($SELP<catalog-name>). The 1991
# sh has no arrays, and every list-shaped loop here is redirect-fed and therefore
# a subshell, so a file is the only "associative array" whose writes survive.
#
# `core` IS MANDATORY -- amixpkg greyed it, we refuse to deselect it with a line
# saying why. It is the base OS; Gate 13 in the driver would refuse the resulting
# order anyway, and refusing at the menu is a diagnosis instead of a failure.

# build_pkg_table -- $PKG_F, one row per package ON THIS DISC, in universe order:
#     <catalog-name> <order-token> <bytes|?> <mb-text|?> <deps|-> <description...>
# Built ONCE per entry into the custom screen; every redraw is then a single pass
# over this file with no forks per package beyond the padding.
build_pkg_table()
{
	if [ -f "$CDROOT/catalog" ]; then
		:
	else
		echo "\nThis medium carries no package catalog, so packages cannot be listed."
		return 1
	fi

	# (a) the universe
	cp /dev/null "$TOK_F"
	while read pkg
	do
		case "$pkg" in ""|\#*) continue ;; esac
		echo "$pkg" >> "$TOK_F"
	done < "$INST/order"
	[ -s "$TOK_F" ] || return 1
	set -- `cat "$TOK_F"`
	PWANT=" $* "

	# (b) ONE pass over the catalog for the rows of exactly those packages
	cp /dev/null "$CATN_F"
	cp /dev/null "$CATN_F.n"
	while read cline
	do
		case "$cline" in ""|\#*) continue ;; esac
		cn=`expr "$cline" : '\([^|]*\)|'`
		ci=`expr "$cline" : '[^|]*|[^|]*|\([^|]*\)|'`
		[ -n "$cn" ] || continue
		ctok=
		case "$PWANT" in
			*" $ci "*)	ctok="$ci" ;;
		esac
		if [ -z "$ctok" ]; then
			case "$PWANT" in
				*" $cn "*)	ctok="$cn" ;;
			esac
		fi
		[ -n "$ctok" ] || continue
		cdp=`expr "$cline" : '[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|\([^|]*\)|'`
		cds=`expr "$cline" : '.*|\(.*\)'`
		[ -n "$cdp" ] || cdp=none
		[ -n "$cds" ] || cds="-"
		echo "$cn $ctok $cdp $cds" >> "$CATN_F"
		echo "$cn" >> "$CATN_F.n"
	done < "$CDROOT/catalog"
	[ -s "$CATN_F" ] || return 1
	set -- `cat "$CATN_F.n"`
	CWANT=" $* "
	rm -f "$CATN_F.n"

	# (c) the #isize block as one "name bytes name bytes" string. A package
	#     with no line simply is not in it, and shows "?" -- absence is UNKNOWN.
	cp /dev/null "$ISZP_F"
	while read itag iname ibytes irest
	do
		case "$itag" in
			"#isize")	: ;;
			*)		continue ;;
		esac
		is_num "$ibytes" || continue
		echo "$iname $ibytes" >> "$ISZP_F"
	done < "$CDROOT/catalog"
	ISZS=" "
	if [ -s "$ISZP_F" ]; then
		set -- `cat "$ISZP_F"`
		ISZS=" $* "
	fi

	# (d) merge, IN UNIVERSE ORDER, so core heads the table exactly as it heads
	#     the install. Dependencies are filtered to what is ON THIS MEDIUM: a
	#     dep the disc does not carry is not a constraint the menu can honour.
	cp /dev/null "$PKG_F"
	[ -s "$TOK_F" ] || return 1
	set -- `cat "$TOK_F"`
	for t in "$@"
	do
		# One FILE per field, `cat` back here in the parent (never a redirected
		# `read` -- see build_set_table for what this shell does with those).
		rm -f "$PKG_F.c" "$PKG_F.t" "$PKG_F.d" "$PKG_F.x"
		while read qcn qtok qdep qdesc
		do
			if [ "$qtok" = "$t" ]; then
				echo "$qcn"  > "$PKG_F.c"
				echo "$qtok" > "$PKG_F.t"
				echo "$qdep" > "$PKG_F.d"
				echo "$qdesc" > "$PKG_F.x"
			fi
		done < "$CATN_F"
		[ -s "$PKG_F.c" ] || continue
		rcn=`cat "$PKG_F.c"`
		rtok=`cat "$PKG_F.t"`
		rdep=`cat "$PKG_F.d"`
		rdesc=`cat "$PKG_F.x"`
		rm -f "$PKG_F.c" "$PKG_F.t" "$PKG_F.d" "$PKG_F.x"
		rsz=`expr "$ISZS" : ".* $rcn \([0-9][0-9]*\) "`
		if is_num "$rsz"; then
			rbg=`budget "$rsz"`
			rmb=`bytes_mb1 "$rbg"`
		else
			rsz="?"
			rmb="?"
		fi
		rdf=
		rdl="$rdep"
		case "$rdl" in
			-|none)	rdl= ;;
		esac
		while [ -n "$rdl" ]
		do
			rd1=`expr "$rdl" : '\([^,]*\)'`
			rdl=`expr "$rdl" : '[^,]*,\(.*\)'`
			[ -n "$rd1" ] || continue
			case "$CWANT" in
				*" $rd1 "*)
					if [ -n "$rdf" ]; then
						rdf="$rdf,$rd1"
					else
						rdf="$rd1"
					fi ;;
			esac
		done
		[ -n "$rdf" ] || rdf="-"
		echo "$rcn $rtok $rsz $rmb $rdf $rdesc" >> "$PKG_F"
	done
	[ -s "$PKG_F" ] || return 1
	return 0
}

custom_screen()
{
	echo "\nDisc contents:  $R2SET"
	echo "`padr Inst 8` `padr Name 10` `padr Description 40`   Size  "
	echo "`padr ---- 8` `padr ---- 10` `padr ----------- 40`   ----  "
	rm -f "$PKG_F.sel"
	while read pcn ptok psz pmb pdep pdesc
	do
		if [ -f "$SELP$pcn" ]; then
			pin=yes
			echo "$psz" >> "$PKG_F.sel"
		else
			pin=no
		fi
		echo "`padr "$pin" 8` `padr "$ptok" 10` `padr "$pdesc" 40` `pad6 "$pmb"`"
	done < "$PKG_F"

	# The total is summed in the PARENT: the loop above is redirect-fed, so a
	# counter mutated inside it would be gone at `done`. An UNKNOWN size
	# anywhere in the selection suppresses the total entirely rather than
	# understating it.
	CUSTOM_BYTES=
	if [ -s "$PKG_F.sel" ]; then
		set -- `cat "$PKG_F.sel"`
		ctot=0
		cunk=
		for b in "$@"
		do
			case "$b" in
				"?")	cunk=1 ;;
				*)	ctot=`expr "$ctot" + "$b"` ;;
			esac
		done
		[ -n "$cunk" ] || CUSTOM_BYTES="$ctot"
		rm -f "$PKG_F.sel"
	fi
	if [ -n "$CUSTOM_BYTES" ]; then
		cbud=`budget "$CUSTOM_BYTES"`
		ctxt=`bytes_mb1 "$cbud"`
		echo "`padr "" 61`  ====  "
		echo "`padr "" 53` Total: `pad6 "$ctxt"` MB"
	fi
}

custom_all()
{
	while read pcn prest
	do
		[ -f "$SELP$pcn" ] || echo 1 > "$SELP$pcn"
	done < "$PKG_F"
}

custom_none()
{
	rm -f "$SELP"*
	echo 1 > "$SELP"core
}

# custom_preset ORDERFILE -- select exactly that order file's packages (plus the
# mandatory core). This is what the `standard` keyword does, and it is also the
# screen's starting state: stock opened on `standard`, not on an empty list.
custom_preset()
{
	rm -f "$SELP"*
	if [ -f "$1" ]; then
		:
	else
		echo 1 > "$SELP"core
		return 0
	fi
	cp /dev/null "$TOK_F.pre"
	while read pkg
	do
		case "$pkg" in ""|\#*) continue ;; esac
		echo "$pkg" >> "$TOK_F.pre"
	done < "$1"
	SWANT=" "
	if [ -s "$TOK_F.pre" ]; then
		set -- `cat "$TOK_F.pre"`
		SWANT=" $* "
	fi
	rm -f "$TOK_F.pre"
	while read pcn ptok prest
	do
		case "$SWANT" in
			*" $ptok "*)	echo 1 > "$SELP$pcn" ;;
			*" $pcn "*)	echo 1 > "$SELP$pcn" ;;
		esac
	done < "$PKG_F"
	echo 1 > "$SELP"core
}

custom_toggle()
{
	tnm="$1"
	rm -f "$PKG_F.hit"
	while read pcn ptok prest
	do
		if [ "$tnm" = "$pcn" ] || [ "$tnm" = "$ptok" ]; then
			echo "$pcn" > "$PKG_F.hit"
		fi
	done < "$PKG_F"
	if [ -s "$PKG_F.hit" ]; then
		tcn=`cat "$PKG_F.hit"`
		rm -f "$PKG_F.hit"
	else
		echo "\nUnknown package:  $tnm"
		return 0
	fi
	if [ "$tcn" = core ]; then
		echo "\ncore is required and cannot be deselected."
		return 0
	fi
	if [ -f "$SELP$tcn" ]; then
		rm -f "$SELP$tcn"
		close_deselect
	else
		echo 1 > "$SELP$tcn"
		close_select
	fi
	return 0
}

# close_select   -- after an explicit SELECT: every dependency of a selected
#                   package must itself be selected.
# close_deselect -- after an explicit DESELECT: every dependent of an unselected
#                   package must go too.
# They are separate ON PURPOSE. Run together they would fight -- one rule wants A
# in because A is selected, the other wants A out because a dep of A is not -- and
# the screen would oscillate. Each user action applies exactly ONE direction, so
# the selection is consistent after every keystroke and can never loop.
# Six passes is a fixed point for this graph: the longest chain the catalog can
# express is oldev -> {olcore,xdev} -> xcore, three deep.
close_select()
{
	cpass=1
	while [ "$cpass" -le 6 ]
	do
		while read pcn ptok psz pmb pdep pdesc
		do
			[ -f "$SELP$pcn" ] || continue
			case "$pdep" in
				-|none)	continue ;;
			esac
			csdl="$pdep"
			while [ -n "$csdl" ]
			do
				csd1=`expr "$csdl" : '\([^,]*\)'`
				csdl=`expr "$csdl" : '[^,]*,\(.*\)'`
				[ -n "$csd1" ] || continue
				[ -f "$SELP$csd1" ] || echo 1 > "$SELP$csd1"
			done
		done < "$PKG_F"
		cpass=`expr "$cpass" + 1`
	done
}

close_deselect()
{
	cpass=1
	while [ "$cpass" -le 6 ]
	do
		while read pcn ptok psz pmb pdep pdesc
		do
			[ -f "$SELP$pcn" ] || continue
			case "$pdep" in
				-|none)	continue ;;
			esac
			cxdl="$pdep"
			while [ -n "$cxdl" ]
			do
				cxd1=`expr "$cxdl" : '\([^,]*\)'`
				cxdl=`expr "$cxdl" : '[^,]*,\(.*\)'`
				[ -n "$cxd1" ] || continue
				if [ -f "$SELP$cxd1" ]; then
					:
				else
					rm -f "$SELP$pcn"
				fi
			done
		done < "$PKG_F"
		cpass=`expr "$cpass" + 1`
	done
}

# custom_write_order -- the selection, as an order file the driver can run. It is
# written to /tmp because the MEDIUM IS READ-ONLY; install.sh takes INSTALL_ORDER
# as a path for exactly this reason.
custom_write_order()
{
	{
		echo "# amix-installng CUSTOM selection, composed on the box by $PROG."
		echo "# A SUBSET of $INST/order, in that file's own order: a subset of a"
		echo "# topological order is still topological, so nothing on the miniroot"
		echo "# ever resolves a dependency."
	} > "$CUSTOM_ORDER" || die "cannot write $CUSTOM_ORDER"
	cp /dev/null "$PKG_F.n"
	while read pcn ptok psz pmb pdep pdesc
	do
		[ -f "$SELP$pcn" ] || continue
		echo "$ptok" >> "$CUSTOM_ORDER"
		echo "$ptok" >> "$PKG_F.n"
	done < "$PKG_F"
	[ -s "$PKG_F.n" ] || return 1
	set -- `cat "$PKG_F.n"`
	CUSTOM_N="$#"
	rm -f "$PKG_F.n"
	[ "$1" = core ] || die "internal: the custom order starts with '$1', not core -- Gate 13 in the driver would refuse it"
	return 0
}

custom_select()
{
	build_pkg_table || return 1
	custom_preset "$INST/$R1ORD"
	while :
	do
		custom_screen
		readask "\nEnter package name to install or ignore; enter GO when ready.\n"
		case "$ask" in
			GO|go)		break ;;
			restart)	restart ;;
			all)		custom_all ;;
			standard)	custom_preset "$INST/$R1ORD" ;;
			none)		custom_none ;;
			"")		: ;;
			*)		custom_toggle "$ask" ;;
		esac
	done
	if custom_write_order; then
		return 0
	fi
	echo "\nNothing is selected."
	return 1
}

# ---------------------------------------------------------------------------
# 4. VERBOSE
# ---------------------------------------------------------------------------
ask_verbose()
{
	ANS_VERBOSE=
	while [ "$ANS_VERBOSE" = "" ]
	do
		readask "\nVerbose install? [n] "
		case $ask in
			[yY]|[yY][eE][sS] )	ANS_VERBOSE=y ;;
			[nN]|[nN][oO]|"" )	ANS_VERBOSE=n ;;
		esac
	done
}

# ---------------------------------------------------------------------------
# 5. CONFIRMATION -- the stock summary shape (system.setup's, tab-aligned)
# ---------------------------------------------------------------------------
confirm()
{
	echo ""
	if [ "$ANS_UPGRADE" = yes ]; then
		if [ "$ANS_DROP_HOME" = yes ]; then
			echo "Upgrade install:	the configuration is kept; /home is NOT"
		else
			echo "Upgrade install:	the configuration and /home are kept"
		fi
	fi
	echo "Install to:		SCSI id $SCSI  (/dev/dsk/c${SCSI}d0s${TARGET_ROOT_SLICE})"
	echo "Disk size:		$DISK_MB megabytes"
	echo "Root file system:	$ANS_ROOT megabytes"
	echo "Swap partition:		$ANS_SWAP megabytes"
	echo "Boot partition:		$BOOTSIZE megabytes"
	[ "${DATA_MB:-0}" -gt 0 ] && echo "Data partition:		$DATA_MB megabytes"
	# Shown on every run, including the prebuilt one where it was not asked --
	# what filesystem the root will be is a fact about the install whether the
	# operator chose it or the medium did, and a blind console has no other place
	# to see it. (The install matrix's beacon check reads the composed key, not
	# this line; this is for the human.)
	echo "Root file system type:	$ANS_FSYS"
	echo "Software:		$SET_LABEL"
	# Plan §5.7: a selection with no reference installed-tree digest is SAID to
	# be one, here and in the log. The gate is not softened for it -- it is
	# waived, and a waiver nobody was told about is the failure mode.
	if [ "$SET_ATT" = n ]; then
		echo "Package set:		$SET_NAME -- unattested selection"
	else
		echo "Package set:		$SET_NAME"
	fi
	echo "Verbose install:	$ANS_VERBOSE"
	# W4: not a question here -- the keyboard was chosen on the miniroot before
	# this script ran. It is SHOWN because it is one of the things this run will
	# change on the target (the default.kmap hard link), and because on a blind
	# console it is the only place the answer becomes visible again.
	if [ -n "$FB_KMAP" ]; then
		echo "Keyboard:		$FB_KMAP"
	else
		echo "Keyboard:		American (built in)"
	fi
	# W5: not a question either. Every interactive install arms the first-boot
	# dialog, and saying so here is the only warning the operator gets that the
	# machine will ask for a nodename, a network and a root password when it
	# boots off its own disk for the first time.
	if [ "$ANS_UPGRADE" = yes ]; then
		echo "Configure at first boot:	no (the old configuration is kept)"
	else
		echo "Configure at first boot:	yes (nodename, network, passwords, users)"
	fi

	CHANGE=
	while [ "$CHANGE" = "" ]
	do
		readask "\nDo you wish to change any of these? [n] "
		case $ask in
			[nN]* | "" )	CHANGE=no ;;
			[yY]* )		CHANGE=yes ;;
		esac
	done
	[ "$CHANGE" = no ]
}

# ---------------------------------------------------------------------------
# THE INTERVIEW
# ---------------------------------------------------------------------------
echo "Amiga UNIX install script"

DONE=
while [ "$DONE" = "" ]
do
	choose_disk
	# Right where stock ran it: after the disk is chosen (the controller
	# probe needs a raw node) and before a single size is asked for.
	check_old_boot
	if [ "$ANS_UPGRADE" = yes ]; then
		upgrade_sizes
	else
		ask_sizes
		# Stock's position too, and it is load-bearing in both directions: AFTER the
		# sizes (the reserve is a percentage of a root that has to exist first) and
		# BEFORE the package menu (check_space subtracts that reserve).
		ask_fstype
	fi
	ask_set
	ask_verbose
	if confirm; then
		DONE=y
	fi
done

# ---------------------------------------------------------------------------
# COMPOSE THE ANSWERS PROFILE
# ---------------------------------------------------------------------------
# The chosen id must still be one the medium has a kernel for. It cannot fail
# from the menu (the menu only offers those), but composing a profile that
# points the transplant at a disk whose kernel cannot find its own root is the
# one mistake that would survive every downstream gate and only show up as a
# dead box, so it is checked here as well as offered there.
elig=
for k in $INSTALLABLE_IDS
do
	if [ "$SCSI" = "$k" ]; then elig=1; fi
done
[ -n "$elig" ] || die "chosen SCSI id $SCSI has no matching kernel on this medium (INSTALLABLE_IDS='$INSTALLABLE_IDS')"

# ★ THE BASE PROFILE, WITHOUT ITS COMMENTS (bench-measured, 2026-08-12).
# This used to be `cat "$PROFILE_FILE" > "$ANSWERS"` -- a byte copy -- and a
# profile is 90% COMMENTS: 13,556 bytes of which about 1,000 are assignments.
# That is 26 of the floppy's 46 free blocks spent on prose, on the same
# filesystem the static pkgadd needs for /usr/apkg/sadm/install/scripts. W4 got
# away with it by TWO blocks; W5's profiles grew by twenty lines of comment and
# the run died exactly where W4's first one did: `Floppy fd0: no space` ->
# `pkgadd: ERROR: unable to make packaging directory` -> `STOP: base-OS install
# FAILED for package(s): core`.
#
# Copying only the ASSIGNMENTS keeps the merge mechanism EXACTLY: the profile is
# sourced by sh, comments contribute nothing when sourced, and every key the
# medium declares still survives into the answers profile untouched. It buys
# back ~24 blocks -- an order of magnitude more headroom than the margin the
# last three waves have been living on.
#
# `while read ... done < FILE > OUT` is a subshell here (as always on this
# shell); that is harmless because nothing inside is read afterwards -- the loop
# only writes to its redirected stdout. There is no grep/sed on the miniroot, so
# the filter is a `case` glob. NB `read` eats backslashes: profile values are
# bare tokens or double-quoted prose, and none may contain one.
while read pline
do
	case "$pline" in
		''|\#*)	;;
		*)	echo "$pline" ;;
	esac
done < "$PROFILE_FILE" > "$ANSWERS" || die "cannot write $ANSWERS"
[ -s "$ANSWERS" ] || die "composed an EMPTY $ANSWERS from $PROFILE_FILE"
# The answers go into their own small file FIRST, and are appended from there.
# ★ THE BEACON IS THAT FILE, NOT THE WHOLE PROFILE. The root filesystem here is
# an 880-block FLOPPY with ~46 blocks free, and the interview already spends 12
# of them on $ANSWERS (the base profile is mostly comments, and it is copied
# whole because the medium is read-only). Echoing the composed profile as well
# spent another 12 -- and the static pkgadd needs room on this same filesystem
# for /usr/apkg/sadm/install/scripts. W4's first interactive run died exactly
# there: `Floppy fd0: no space`, then `pkgadd: ERROR: unable to make packaging
# directory`. W3b survived the same shape with SIX blocks to spare, which is
# luck, not headroom. The beacon proves the ANSWERS parsed, so the answers are
# all it needs to carry.
{
	echo ""
	echo "# W2-ANSWERS-BEGIN"
	echo "# Composed by $PROG on the box, from $PROFILE_FILE plus the operator's"
	echo "# answers. A profile is sourced by sh, so these APPENDED assignments"
	echo "# win over the base profile's -- that is the whole merge mechanism."
	echo "# install set: $SET_LABEL"
	echo "TARGET_SCSI_ID=$SCSI"
	echo "TARGET_DISK_MB=$DISK_MB"
	if [ "$ANS_UPGRADE" = yes ]; then
		# S4-58: the upgrade keeps or re-lays the layout itself; no sizes
		echo "INSTALL_UPGRADE=yes"
		echo "UPGRADE_DROP_HOME=${ANS_DROP_HOME:-no}"
		echo "TARGET_ROOT_MB="
		echo "TARGET_SWAP_MB="
	else
		echo "TARGET_ROOT_MB=$ANS_ROOT"
		echo "TARGET_SWAP_MB=$ANS_SWAP"
	fi
	# The root filesystem type. Written UNCONDITIONALLY, exactly like FB_KMAP
	# above and for the same reason: the value must OVERRIDE whatever the base
	# profile declares, so it can never be omitted just because the question was
	# not asked. On a prebuilt target that value is s5 -- the only thing
	# mkroot.sh can have minted -- and saying so explicitly is what keeps a
	# profile from quietly promising the driver a filesystem that is not there.
	echo "TARGET_ROOT_FSTYPE=$ANS_FSYS"
	echo "INSTALL_VERBOSE=$ANS_VERBOSE"
	echo "INSTALL_SET=$SET_NAME"
	echo "INSTALL_ORDER=$SET_ORDER"
	echo "INSTALL_ATTESTED=$SET_ATT"
	# W4: the keymap chosen on the miniroot, before this script ran. Written
	# UNCONDITIONALLY -- an EMPTY value is the answer `usa` (bake nothing), and
	# it must override a base profile that names a map, so it can never be
	# omitted just because it is empty.
	echo "FB_KMAP=$FB_KMAP"
	# W5: an INTERACTIVE install arms the first-boot configuration dialog. This
	# is not a question -- it is what "interactive" MEANS here: someone is at
	# this console, so someone will be at the console at the next boot, and the
	# identity questions (nodename, network, passwords, users) belong there,
	# where the full installed userland exists. The miniroot cannot hash a
	# password or bring up an interface; the stock installer split the same way.
	# A profile-driven unattended run never reaches this file, so its target is
	# byte-identical to a pre-W5 one.
	echo "FIRSTBOOT_DIALOG=y"
	echo "# W2-ANSWERS-END"
} > "$ANSWERS_BLOCK" || die "cannot write $ANSWERS_BLOCK"
cat "$ANSWERS_BLOCK" >> "$ANSWERS" || die "cannot append the answers to $ANSWERS"

# --- the answers beacon (blind-console discipline) ---------------------------
# The install matrix drives this interview with NO way to read the screen back.
# Writing the answers where the HOST can read them -- the root floppy is the
# miniroot's own filesystem, and the harness greps the .adf between the two
# fence markers -- means a mistyped or mis-parsed answer is caught in seconds,
# BEFORE the five-minute transplant runs, instead of being diagnosed from a
# digest mismatch after it.
if [ -n "$ECHO_ANSWERS" ]; then
	cat "$ANSWERS_BLOCK" > "$ANSWERS_ECHO_PATH"
	sync
	sync
	echo "$PROG: answers echoed to $ANSWERS_ECHO_PATH"
fi

# --- give the floppy back its scratch ---------------------------------------
# Everything below this line runs on the TARGET, but pkgadd still needs room on
# THIS filesystem for its packaging directory, and the interview's own scratch
# is a dozen blocks of an 880-block floppy. $ANSWERS is kept (the driver sources
# it), and so is $CUSTOM_ORDER when a Custom selection chose it -- $SET_ORDER may
# BE that file.
rm -f "$BLK0" "$SCAN_F" "$SCAN_F.p" "$SET_F" "$TOK_F" "$TOK_F.pre" "$CATN_F" \
      "$CATN_F.n" "$ISZ_F" "$PKG_F" "$PKG_F.sel" "$PKG_F.n" "$ISZP_F" \
      "$ANSWERS_BLOCK" "$KMAP_FILE" "$SELP"*
sync

echo ""
echo "$PROG: starting the installation ($SET_LABEL)."
echo ""

# stdin from /dev/null: the transplant must never inherit the console (FIX.3).
# D15: NOT exec'd. When the driver returns, THIS script ends the install: on
# success the final screen, RETURN, sync and halt (`uadmin 2 0`) -- never a
# respawned installer offering to erase the disk it just wrote; on failure a
# shell on the console for inspection, the target left as the driver left it.
sh "$INST/bin/install.sh" "$ANSWERS" < /dev/null
rc=$?
# The install matrix (its /matrix.go marker, the same seam as the answers beacon)
# needs the driver's status back and halts the box itself.
if [ -f /matrix.go ]; then
	exit $rc
fi
if [ "$rc" = 0 ]; then
	echo ""
	echo "The installation is complete.  The system will now halt."
	echo "Then select the installed disk (or remove the installation media) and"
	echo "switch the machine off.  Wait at least 60 seconds before switching it"
	echo "on again: the first boot of the installed system asks its questions."
	readask "\nPress RETURN to halt the system. "
	sync
	sync
	/etc/uadmin 2 0
fi
echo ""
echo "WARNING:  the installation FAILED (status $rc).  The system is NOT halted."
echo "The log is on the screen above; an interactive shell follows."
exec /bin/sh
