#!/bin/sh
# install.sh -- the Installer-NG driver. Runs ON THE MINIROOT, single-user,
# after the install kernel has come up. It builds the target root, transplants
# the base OS from the install CD with the static pkgadd, writes the boot chain,
# and arms first-boot. It is the replacement for the stock Amix install script.
#
# ===========================================================================
# PRE-POSIX SVR4 /bin/sh -- HARD PORTABILITY RULES (the miniroot sh is 1991)
# ===========================================================================
#   * NO $(...)      -- use `backticks`
#   * NO `export VAR=val`  -- write `VAR=val; export VAR`
#   * NO $(( ))      -- arithmetic is `expr`
#   * NO [[ ]]       -- test with [ ]
#   * NO `local`, NO arrays, NO `wc` (miniroot has none) -- count with
#     `set -- pattern; echo $#`
#   * The miniroot has NO od/cmp/sum/grep-q either; checksumming on the box is
#     the CD-resident SVR4 `sum` at $INSTALL/bin/sum (see docs/installer.md).
#   * NO basename/sed/touch/date -- the miniroot carries NONE of them (W5.4c
#     proved it on the box). basename -> `expr "$x" : '.*/\(.*\)'`; sed field
#     extractions -> `expr`/`case`/`read`; touch -> `: > file`; date -> omit
#     (there is no wall clock we may trust; never write a time field the box
#     cannot produce). NO ${x##*/}-style parameter expansion either (not 1991).
# tools/installer-selftest.py audits this file two ways: a grep for the pre-POSIX
# SYNTAX pitfalls above, AND a miniroot-tool ALLOWLIST audit -- every command's
# first word must be a /bin/sh builtin, a binary the miniroot.proto actually
# carries, or a /cdrom/... path; a reference to a tool the miniroot lacks fails.
#
# ===========================================================================
# WHAT RUNS THIS, AND WHERE THE PIECES ARE
# ===========================================================================
# The install CD is mounted at /cdrom (cdfs). This driver lives on it at
# /cdrom/install/bin/install.sh and is launched from the miniroot shell:
#
#     /usr/lib/fs/cdfs/mount <card>,<unit> /cdrom     # e.g. 1,3 (retry-once)
#     sh /cdrom/install/bin/install.sh [profile-name | /path/to/answers.profile]
#
# The argument is a profile NAME resolved under /cdrom/install/profiles/ (the
# original form) OR A PATH to a profile file anywhere -- the latter is what lets
# the W2 interview compose /tmp/answers.profile and hand it straight to this
# driver, since the medium is read-only.
#
# EVERY INSTALL WRITES A LOG. From the moment the target root is mounted, every
# message and every child command's output is appended to
# <target>/var/adm/install.log (i.e. /var/adm/install.log on the installed
# system). The console shows stage messages only unless the profile sets
# INSTALL_VERBOSE=y. See "THE INSTALL LOG" below.
#
#   /cdrom/install/bin/{pkgadd,pkgtrans,pkginfo,pkgchk,pkginstall,sum}  static engine + sum
#   /cdrom/install/admin           permissive pkgadd admin(4) policy
#   /cdrom/install/order           the install order (core first; gen-install-order.py)
#   /cdrom/install/order.<set>     per-named-set orders (W3b; selected by INSTALL_ORDER)
#   /cdrom/install/sets            the interview's set table (W3b; read by setup.sh)
#   /cdrom/install/profiles/*.profile   target specs
#   /cdrom/install/boot/<p>/{bootslice.img,boot2.boot,bootslice.manifest}
#   /cdrom/install/firstboot/*     first-boot payload (armed into the target)
#   /cdrom/pkgs/stock/*.pkg        the base-OS packages
#
# ===========================================================================
# THE HOST/ON-BOX SPLIT (mkroot.sh is host python; this is its on-box twin)
# ===========================================================================
# tools/mkroot.sh authors a target disk HOST-side: partition arithmetic ->
# rdbtool RDB -> s5 mkfs (tools/lib/s5.py) -> read-back gate -> layout.json.
# This driver does the ON-BOX equivalent with the miniroot's own tools:
#   arithmetic in `expr` (the SAME stock constants) -> /etc/rdb RDB authoring ->
#   /bin/mkfs_{s5,ufs} -> (s5 only) /usr/lib/fs/s5/labelit -> mount(2) via
#   /etc/mount.
# Two supported target-build modes:
#   author   (default) -- this driver partitions + mkfs the blank target on-box.
#            THE ONLY MODE THAT CAN LAY DOWN A UFS ROOT, because `mkfs_ufs` runs
#            on the box; there is no host-side UFS writer and deliberately none
#            planned (docs/ufs-target-scoping.md §3.3 costs one at 600-900 lines
#            against a 20 KB C program we already ship).
#   prebuilt (INSTALL_TARGET_PREBUILT=1) -- the target was fully built host-side
#            by tools/mkroot.sh (RDB + s5 root, read-back-gated); the driver
#            skips authoring/mkfs and only fscks + mounts. This is the LOW-RISK
#            path recommended for the W5.4 canonical run (mkroot.sh is proven and
#            has its own read-back gate; it also runs identically for metal).
#            mkroot.sh mints s5 and only s5, so this mode REFUSES a ufs target
#            rather than mounting an s5 filesystem under the wrong type.
# The whole author sequence -- the `/etc/rdb` create/geometry primitive included
# -- is transcribed from the stock installer (grimoire anatomy-root-adf; the
# script itself is /etc/profile on the stock root floppy) and, since 2026-07-31,
# RUN END-TO-END ON THE BENCH by tools/install-matrix.sh cell `cd-author`.
#
# NOT boot-tested here. W5.4 runs it end-to-end on the bench profile.

PROG=install.sh
CDROOT=/cdrom
INST=/cdrom/install
TARGET=/mnt

# --- stock install-script constants (mkroot.sh header; DO NOT rederive) -------
OFFSET_BLOCKS=128
MINROOT=16
MINSWAP=5
BREAKPT=120
LGSWAP=30
SMSWAP=18
MINBOOT=2
BOOTSIZE=10               # r6e (owner 2026-10-10): 10 MiB so every kernel cut fits; stock was 2
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

# ---------------------------------------------------------------------------
# THE INSTALL LOG + THE QUIET/VERBOSE SPLIT (W1)
# ---------------------------------------------------------------------------
# Every install persists a COMPLETE transcript to <target>/var/adm/install.log.
# Until the target root is mounted there is nowhere to write it, so the pre-mount
# window (banner, profile echo, RDB authoring, mkfs -- the author-mode failure
# hotspot) is CONSOLE-ONLY by nature; the log opens with a marker line saying so.
#
# There is NO tee(1) on the miniroot (and no /bin/echo either), so "show it and
# log it" is the temp-file + cat-twice idiom: a child's output is captured to
# $RUNOUT, appended to the log, and -- in verbose mode -- cat'd to the console as
# well. `cat` IS on the proto; tee is not. What the two modes look like:
#
#   quiet (default, INSTALL_VERBOSE=n)  console: stage messages only
#                                       log:    stage messages + every `+ cmd`
#                                               echo + all child output
#   verbose (INSTALL_VERBOSE=y)         console: everything the log gets
#                                       log:    unchanged (always complete)
#
# A FAILING child's output is cat'd to the console in BOTH modes -- a quiet run
# must never hide the reason it stopped.
LOGFILE=                                 # set once the target root is mounted
RUNOUT=                                  # child-output scratch (under $TARGET/tmp)
VERBOSE=                                 # non-empty => also mirror to the console

# ---------------------------------------------------------------------------
# tiny helpers
# ---------------------------------------------------------------------------
# logline TEXT -- append TEXT to the install log, if one is open yet. Always
# returns 0 so it can never change a caller's exit status.
logline() {
	if [ -n "$LOGFILE" ]; then
		echo "$*" >> "$LOGFILE"
	fi
	return 0
}

msg()  { echo "$PROG: $*"; logline "$PROG: $*"; }
warn() { echo "$PROG: WARNING: $*" >&2; logline "$PROG: WARNING: $*"; }
die()  { echo "$PROG: STOP: $*" >&2; logline "$PROG: STOP: $*"; exit 1; }

# stage TEXT -- a STAGE message, printed unprefixed. Where the stock installer
# (/etc/profile on the stock root floppy) has an equivalent stage, TEXT is its
# string VERBATIM ("Making filesystems.  This will take a few minutes.",
# "Installing <pkg>", ...), so a normal install reads like the original. NG-only
# stages keep the msg() idiom instead (prefixed with the program name) -- the
# distinction is deliberate: unprefixed == the original's own words.
stage() { echo "$*"; logline "$*"; }

# runq CMD... -- run CMD with its output routed the INSTALL_VERBOSE way, and
# RETURN ITS EXIT STATUS (no die). Used where the caller must branch on the rc.
# Before the log opens this is a bare invocation (console-only, pre-mount window).
runq() {
	if [ -z "$LOGFILE" ]; then
		echo "+ $*"
		"$@"
		return $?
	fi
	if [ -n "$VERBOSE" ]; then
		echo "+ $*"
	fi
	echo "+ $*" >> "$LOGFILE"
	"$@" > "$RUNOUT" 2>&1
	rc=$?
	cat "$RUNOUT" >> "$LOGFILE"
	if [ -n "$VERBOSE" ]; then
		cat "$RUNOUT"
	else
		if [ "$rc" != 0 ]; then
			cat "$RUNOUT"
		fi
	fi
	return $rc
}

# run a command, echoing it; die on failure with context.
run() {
	runq "$@" || die "command failed (rc=$?): $*"
	return 0
}

# strict non-negative-integer test (pre-POSIX; no grep, no expr anchor). The
# boot-chain verify uses it to FAIL CLOSED: an empty or garbled checksum is NOT
# a number, so it can never compare equal. (W5.4c: `sed` was absent, both sides
# of the comparison went empty, and empty==empty printed a vacuous OK per region.)
is_num() {
	case "$1" in
		'')       return 1 ;;
		*[!0-9]*) return 1 ;;
		*)        return 0 ;;
	esac
}

# count_tokens FILE -- echo the number of whitespace-separated tokens in FILE.
# The subshell-safe loops (W5.4e) count by tallying an append-only temp file after
# the loop. The obvious `set -- \`cat FILE\`; echo $#` is a TRAP on the miniroot sh:
# `set --` with an EMPTY argument list is a NO-OP on $@ there (it does NOT clear the
# positional parameters -- confirmed on-box: `set -- a b c; set -- \`cat /dev/null\``
# leaves $#=3), so counting an EMPTY file returns whatever $# was last set to (a
# stale count from the previous count_tokens call). W5.4e-run-1 hit exactly this:
# all 3 boot regions verified OK (vok=3) but the empty vfails file then "counted" 3
# and the verify false-failed. The `[ -s ]` presence guard returns 0 for an empty
# file WITHOUT running the no-op `set --`, so $@ is only ever reset from a non-empty
# list. cat is on the miniroot (miniroot.proto); no wc needed.
# --- byte writing on the miniroot (D-2, measured 2026-10-05) ------------------------
# The miniroot has dd, cat, expr and the sh `echo` (which emits any byte from '\0ooo'),
# but no od/cmp/printf and a dd WITHOUT conv=notrunc. So a few bytes are written by
# REBUILDING their 512-byte block -- head | the bytes | tail -- and writing the whole
# block back to the raw slice; and they are checked one by one, because the `sum -r`
# of a 1-byte file IS that byte's value (no sum over a span can see every change).
# oct_file FILE OOO... -- FILE := the bytes, given as 3-digit octal without a backslash
# (the 1991 sh `read` strips backslashes, so the tables carry none).
oct_file()
{
	_of=$1; shift
	_s=
	for _o in "$@"
	do
		_s="$_s\\0$_o"
	done
	echo "$_s\c" > "$_of"
}
# put_bytes RAWDEV BLOCK OFFSET NBYTES FILE -- write FILE's NBYTES bytes at OFFSET of BLOCK
put_bytes()
{
	_pb="$TARGET/tmp/.pb.$$"
	_po="$TARGET/tmp/.po.$$"
	_end=`expr $3 + $4`
	[ "$_end" -le 512 ] || return 1
	dd if="$1" of="$_pb" bs=512 skip="$2" count=1 2>/dev/null || return 1
	: > "$_po"
	if [ "$3" -gt 0 ]; then
		dd if="$_pb" bs="$3" count=1 2>/dev/null >> "$_po"
	fi
	cat "$5" >> "$_po"
	if [ "$_end" -lt 512 ]; then
		dd if="$_pb" bs="$_end" skip=1 2>/dev/null >> "$_po"
	fi
	dd if="$_po" of="$1" bs=512 seek="$2" count=1 2>/dev/null || return 1
	rm -f "$_pb" "$_po"
	return 0
}
# byte_is FILE OFFSET OOO -- is the byte at OFFSET of FILE the octal OOO?
byte_is()
{
	dd if="$1" of="$TARGET/tmp/.b1.$$" bs=1 skip="$2" count=1 2>/dev/null
	_got=`"$INST/bin/sum" -r "$TARGET/tmp/.b1.$$" | ( read s rest; echo "$s" )`
	rm -f "$TARGET/tmp/.b1.$$"
	_d1=`expr "$3" : '\(.\)'`
	_d2=`expr "$3" : '.\(.\)'`
	_d3=`expr "$3" : '..\(.\)'`
	_want=`expr $_d1 \* 64 + $_d2 \* 8 + $_d3`
	is_num "$_got" && [ "$_got" -eq "$_want" ]
}

count_tokens() {
	if [ -s "$1" ]; then
		set -- `cat "$1"`
		echo $#
	else
		echo 0
	fi
}

# emit_firstboot_hook FILE -- write the target's rc2 first-boot hook to FILE.
# This is the W5.4f wiring: the payload was armed by earlier waves but nothing
# in the STOCK target init invoked it, so cold boot #1 fell into the stock
# sysinit dialog (/etc/sysinit runs /usr/amiga/bin/system.setup iff it is -x,
# which prompts "What is the nodename of this machine? [localhost]"). The arm
# step below disarms that dialog (chmod -x system.setup -- the stock's OWN
# once-only mechanism) and drops THIS hook into /etc/rc2.d. /etc/inittab runs
# `s2:23:wait:/etc/rc2` to completion BEFORE it spawns the `con` getty (the
# rc2.d/S* scripts, run via `/sbin/sh S* start`, complete first), so the hook
# runs, bakes identity, and removes PENDING before the console login appears.
# It is a NEW file, NOT a package member -- the driver WRITES it here (it is not
# copied from the CD and not staged by build-install-iso.sh), so it is invisible
# to pkgadd's contents DB (and thus to altroot-attest / pkgchk). The hook body
# is a here-independent set of `echo` lines (single-quoted so $FB stays literal),
# byte-identical to the tracked reference payload/firstboot/S16firstboot -- which
# installer-selftest audit J extracts THIS function and re-runs to prove.
emit_firstboot_hook() {
	{
		echo '#!/bin/sh'
		echo '# S16firstboot -- run the once-only first-boot identity payload iff armed.'
		echo '# Written onto the target by src/installer/install.sh (NOT a package member).'
		echo '# The stock sysinit first-boot dialog is disarmed at install time; this runs'
		echo '# firstboot.sh from run level 2 (which /etc/inittab completes before spawning'
		echo '# the console getty), then firstboot.sh removes PENDING so this stays inert.'
		echo 'FB=/var/adm/firstboot'
		echo 'if [ -f "$FB/PENDING" ]; then'
		echo '	/sbin/sh "$FB/firstboot.sh"'
		echo 'fi'
		echo 'exit 0'
	} > "$1"
}

# emit_zen_hook FILE -- write the target's rc2 Z3660-native-ethernet (zen0) bring-up
# to FILE (METAL-FIX.4). Like S16firstboot above, this is DRIVER-WRITTEN and additive
# -- NOT a package member, so it never reaches the pkgadd contents DB (invisible to
# pkgchk / altroot-attest). It is laid down ONLY for zen0 (metal z3660eth) profiles
# (guarded on FB_ETHER_IF=zen0 in the arm step); the stock a2065/aen0 userland a base
# install ships is inert on metal (no A2065 board). The body is BYTE-IDENTICAL to the
# tracked master payload/S99zen with the profile's FB_IP/FB_NETMASK/FB_GATEWAY/
# FB_DOMAIN substituted for its @FB_*@ placeholders; installer-selftest audit P
# drift-locks the two. Emitted with single-quoted `echo` lines (so $vars, backticks
# and the awk/sed programs stay literal; the master carries no backslash, so no echo
# escape can fire), EXCEPT the four parameter lines, which are DOUBLE-quoted so the
# FB_* values expand -- the selective-expansion idiom install.sh already uses to
# write firstboot.conf. Regenerate this function from the master rather than editing
# it by hand (one echo per master line; ' becomes '"'"'). The bring-up itself is the
# proven z3660net one: self-heal /dev/zen0 (mknod c 51 0), a bare `slink` FIRST then
# `slink addaen` in a retry loop, `ifconfig zen0 <LITERAL-IP> up -trailers` (SVR4.0
# -- NEVER `plumb`, NEVER `uname -n` in the ifconfig), all BACKGROUNDED so it can
# never hang the boot. P-3 (2026-09-26) adds the address-by-card step in front of it:
# with /etc/inet/zen.conf present, zen0's MAC (/usr/amiga/bin/zenmac) picks the
# address + nodename + hosts own row; without it the profile's FB_IP is used exactly
# as before (docs/address-by-card.md). `echo` + redirection only (miniroot-clean).
emit_zen_hook() {
	{
		echo '#!/bin/sh'
		echo '# S99zen -- bring up the Z3660 native ethernet (zen0) at boot, at the address'
		echo '# this CARD owns: zen0'"'"'s MAC (read by /usr/amiga/bin/zenmac) is looked up in'
		echo '# /etc/inet/zen.conf, so one image serves every machine listed there'
		echo '# (docs/address-by-card.md). A matched row also sets the nodename and rewrites'
		echo '# this box'"'"'s own row in /etc/inet/hosts. No zen.conf = the laydown address'
		echo '# below, exactly as before the table existed.'
		echo '# Laid onto the target root by src/installer/install.sh for zen0 (metal) profiles'
		echo '# only: a driver-written ADDITIVE file, NOT a package member (like S16firstboot'
		echo '# and updbootpart). The FALLBACK/NETMASK/GATEWAY/DOMAIN values are the profile'"'"'s'
		echo '# FB_IP/FB_NETMASK/FB_GATEWAY/FB_DOMAIN, parameterized at laydown (the tracked'
		echo '# master carries placeholders the installer-selftest drift-lock resolves).'
		echo '# z3660eth cdevsw major = 51, so /dev/zen0 is c 51 0 (self-healed by mknod below).'
		echo '# Media mastered from this tree REQUIRE kernels that register z3660eth at 51.'
		echo '#'
		echo '# The bring-up proper is BACKGROUNDED so a datapath fault can never hang the boot'
		echo '# (the box still reaches login). Learned on real HW (z3660net 2026-06-21):'
		echo '#  * run a bare slink FIRST to link the base inet STREAMS, THEN slink addaen in a'
		echo '#    retry loop (addaen can race ahead of the base plumbing on a fast clean boot).'
		echo '#  * ifconfig takes a LITERAL IP, never `uname -n` -- on SVR4.0 the name path'
		echo '#    triggers a boot-stalling DNS lookup when the resolver cannot be reached.'
		echo '# Verbs besides start (tools/zen-conf-selftest.sh drives them on the host):'
		echo '#   lookup MAC [CONF]      print "ADDR NAME HOW" for MAC (HOW = card|default|none)'
		echo '#   hosts FILE IP NAME OLD [DOMAIN]   print FILE with this box'"'"'s own row rewritten'
		echo '#   mkconf MAC=ADDR=NAME ...          print a zen.conf holding those rows'
		echo "FALLBACK=$FB_IP"
		echo "NETMASK=$FB_NETMASK"
		echo "GATEWAY=$FB_GATEWAY"
		echo "DOMAIN=$FB_DOMAIN"
		echo 'CONF=/etc/inet/zen.conf'
		echo 'HOSTS=/etc/inet/hosts'
		echo 'ZENMAC=/usr/amiga/bin/zenmac'
		echo ''
		echo '# zen_row KEY FILE -- the first row whose first field is KEY (case-insensitive),'
		echo '# printed as "ADDR NAME" (NAME "-" when absent); status 1 when there is none.'
		echo 'zen_row()'
		echo '{'
		echo '	r=`sed -e '"'"'s/#.*//'"'"' "$2" | grep -i "^[ 	]*$1[ 	]" | sed -n 1p`'
		echo '	[ -n "$r" ] || return 1'
		echo '	set -- $r'
		echo '	expr "$2" : '"'"'[0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*[.][0-9][0-9]*$'"'"' > /dev/null || return 1'
		echo '	echo "$2 ${3:--}"'
		echo '}'
		echo ''
		echo '# zen_pick MAC FILE -- set ADDR NAME HOW: the MAC'"'"'s own row (HOW=card), else the'
		echo '# "default" row (HOW=default), else FALLBACK (HOW=none).'
		echo 'zen_pick()'
		echo '{'
		echo '	r='
		echo '	HOW=none'
		echo '	if [ -f "$2" ]; then'
		echo '		if [ -n "$1" ]; then'
		echo '			r=`zen_row "$1" "$2"`'
		echo '		fi'
		echo '		if [ -n "$r" ]; then'
		echo '			HOW=card'
		echo '		else'
		echo '			r=`zen_row default "$2"`'
		echo '			if [ -n "$r" ]; then'
		echo '				HOW=default'
		echo '			fi'
		echo '		fi'
		echo '	fi'
		echo '	if [ -n "$r" ]; then'
		echo '		set -- $r'
		echo '		ADDR=$1'
		echo '		NAME=$2'
		echo '	else'
		echo '		ADDR=$FALLBACK'
		echo '		NAME=-'
		echo '	fi'
		echo '}'
		echo ''
		echo '# zen_hosts FILE IP NAME OLD DOMAIN -- print FILE without any row for IP and'
		echo '# without the aliases NAME/OLD (bare or dotted), then "IP NAME NAME.DOMAIN".'
		echo 'zen_hosts()'
		echo '{'
		echo '	awk '"'"''
		echo '	/^[ 	]*#/ || NF == 0 { print; next }'
		echo '	$1 == ip { next }'
		echo '	{'
		echo '		keep = ""'
		echo '		drop = 0'
		echo '		for (i = 2; i <= NF; i++) {'
		echo '			f = $i'
		echo '			if (substr(f, 1, 1) == "#") {'
		echo '				for (; i <= NF; i++)'
		echo '					keep = keep " " $i'
		echo '				break'
		echo '			}'
		echo '			if (f == nm || f == old || index(f, nm ".") == 1 || (old != "" && index(f, old ".") == 1)) {'
		echo '				drop++'
		echo '				continue'
		echo '			}'
		echo '			keep = keep " " f'
		echo '		}'
		echo '		if (drop == 0)'
		echo '			print'
		echo '		else if (keep != "" && substr(keep, 2, 1) != "#")'
		echo '			print $1 "	" substr(keep, 2)'
		echo '	}'
		echo '	END {'
		echo '		row = ip "	" nm'
		echo '		if (dom != "")'
		echo '			row = row " " nm "." dom'
		echo '		print row'
		echo '	}'"'"' ip="$2" nm="$3" old="$4" dom="$5" "$1"'
		echo '}'
		echo ''
		echo '# zen_mkconf MAC=ADDR=NAME ... -- a zen.conf holding those rows.'
		echo 'zen_mkconf()'
		echo '{'
		echo '	echo '"'"'# /etc/inet/zen.conf -- the zen0 address of each Z3660 card, read by'"'"''
		echo '	echo '"'"'# /etc/rc2.d/S99zen at every boot (docs/address-by-card.md).'"'"''
		echo '	echo '"'"'#   <MAC as the driver sees it>  <address>  <short-name>'"'"''
		echo '	echo '"'"'# Key on the EFFECTIVE MAC (/usr/amiga/bin/zenmac prints it): the Z3660'"'"''
		echo '	echo '"'"'# firmware mis-parses hex letters in z3660cfg.txt, so a configured'"'"''
		echo '	echo '"'"'# 00:80:1A:.. appears as 00:80:51:.. on the wire and to the driver.'"'"''
		echo '	echo '"'"'# The short-name becomes the nodename; "-" keeps the installed one.'"'"''
		echo '	echo '"'"'# A "default" row is used for a card not listed (with a console warning).'"'"''
		echo '	for w'
		echo '	do'
		echo '		echo "$w" | sed -e '"'"'s/=/  /g'"'"''
		echo '	done'
		echo '}'
		echo ''
		echo 'VERB=$1'
		echo 'case "$VERB" in'
		echo 'lookup)'
		echo '	zen_pick "$2" "${3:-$CONF}"'
		echo '	echo "$ADDR $NAME $HOW"'
		echo '	exit 0'
		echo '	;;'
		echo 'hosts)'
		echo '	zen_hosts "$2" "$3" "$4" "$5" "$6"'
		echo '	exit $?'
		echo '	;;'
		echo 'mkconf)'
		echo '	shift'
		echo '	zen_mkconf "$@"'
		echo '	exit 0'
		echo '	;;'
		echo 'start|"")'
		echo '	;;'
		echo '*)'
		echo '	echo "usage: S99zen [start | lookup MAC [CONF] | hosts FILE IP NAME OLD [DOMAIN] | mkconf MAC=ADDR=NAME ...]" >&2'
		echo '	exit 1'
		echo '	;;'
		echo 'esac'
		echo ''
		echo '[ -c /dev/zen0 ] || mknod /dev/zen0 c 51 0'
		echo ''
		echo 'ADDR=$FALLBACK'
		echo 'if [ -f $CONF ]; then'
		echo '	MAC=`$ZENMAC 2>/dev/null`'
		echo '	expr "$MAC" : '"'"'[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]$'"'"' > /dev/null || MAC='
		echo '	zen_pick "$MAC" $CONF'
		echo '	if [ $HOW = card ]; then'
		echo '		echo "S99zen: zen0 card $MAC -> $ADDR ($NAME)"'
		echo '	else'
		echo '		echo "S99zen: WARNING: zen0 card MAC ${MAC:-unreadable} is not in $CONF -- using $ADDR"'
		echo '	fi'
		echo '	OLD=`uname -n`'
		echo '	NEW=$OLD'
		echo '	if [ "$NAME" != - ] && expr "$NAME" : '"'"'[A-Za-z0-9][-A-Za-z0-9]*$'"'"' > /dev/null; then'
		echo '		NEW=$NAME'
		echo '	fi'
		echo '	if [ "$NEW" != "$OLD" ]; then'
		echo '		uname -S "$NEW" && echo "$NEW" > /etc/nodename && echo "S99zen: nodename $OLD -> $NEW"'
		echo '	fi'
		echo '	if [ -f $HOSTS ]; then'
		echo '		zen_hosts $HOSTS "$ADDR" "$NEW" "$OLD" "$DOMAIN" > $HOSTS.zn$$'
		echo '		if cmp -s $HOSTS $HOSTS.zn$$; then'
		echo '			rm -f $HOSTS.zn$$'
		echo '		else'
		echo '			mv $HOSTS.zn$$ $HOSTS && chmod 444 $HOSTS && echo "S99zen: $HOSTS own row -> $ADDR $NEW"'
		echo '		fi'
		echo '	fi'
		echo 'fi'
		# P-15 I2: an ADDRESS-LESS laydown (FIRSTBOOT_DIALOG=y + empty FB_IP, the
		# public flavor) leaves zen0 DOWN until the dialog (or zen.conf) gives it one,
		# and routes only with a gateway. Emitted only then, so a LAN-flavor S99zen
		# stays byte-identical to the master.
		if [ -z "$FB_IP" ]; then
			echo 'if [ -z "$ADDR" ]; then'
			echo '	echo "S99zen: zen0 has no address -- left down (the first-boot dialog sets one, or FALLBACK= in /etc/rc2.d/S99zen)"'
			echo '	exit 0'
			echo 'fi'
		fi
		echo '('
		echo '  sleep 5'
		echo '  /usr/sbin/slink'
		echo '  i=0'
		echo '  while [ $i -lt 20 ]; do'
		echo '    /usr/sbin/slink addaen /dev/zen0 zen0 && break'
		echo '    sleep 3'
		echo '    i=`expr $i + 1`'
		echo '  done'
		echo '  /usr/sbin/ifconfig zen0 $ADDR netmask $NETMASK up -trailers'
		# no gateway (an address-less laydown, or a zen0 beside another interface
		# that carries the default route): the route line is guarded
		if [ -n "$FB_IP" ] && [ -n "$FB_GATEWAY" ]; then
			echo '  /usr/sbin/route add default $GATEWAY 1'
		else
			echo '  [ -n "$GATEWAY" ] && /usr/sbin/route add default $GATEWAY 1'
		fi
		echo '  /usr/sbin/ifconfig zen0'
		echo ') > /tmp/zen-bringup.log 2>&1 &'
	} > "$1"
}


# emit_system_setup FILE -- write the first-boot dialog's ENTRY POINT to FILE.
# This is W5's one new file on the target, and it goes into the STOCK
# `system.setup` slot: /etc/sysinit runs `sh /usr/amiga/bin/system.setup` iff that
# file is executable, on /dev/syscon, BEFORE run level 2. Written ONLY when the
# profile says FIRSTBOOT_DIALOG=y (interactive installs -- setup.sh writes the
# key); an unattended install still gets the plain `chmod -x` disarm, so its
# installed tree is byte-unchanged.
#
# ★ IT IS A THREE-LINE STUB, AND THE REASON IS THE FLOPPY (bench, 2026-08-12).
# The dialog itself is ~29 KB and used to live HERE, in a quoted here-doc, the
# same pattern updbootpart used. That cost an install: the 1991 SVR4 sh
# MATERIALIZES EVERY HERE-DOC BODY INTO A FILE UNDER /tmp WHEN IT PARSES THE
# SCRIPT -- proven on the box, a here-doc inside a function that is never called
# still leaves `/tmp/sh<pid>` there -- and on the miniroot /tmp IS the 880-block
# install floppy with 46 free 1 KB blocks. updbootpart's body alone was already
# taking 16 of them (15,427 B, measured as /tmp/sh250 on a real run); 29 KB of
# dialog on top ran the floppy out of space before this driver printed its first
# line, and `pkgadd` could not create its packaging directory. It failed the
# INTERACTIVE and the UNATTENDED path alike. So the dialog travels in
# payload/firstboot/firstboot.sh -- already staged on the medium, already copied
# onto the target by the arm step below -- and this stub execs it with
# `--dialog`. W5.5 then moved updbootpart onto the medium too, so this driver now
# carries NO here-doc at all and the selftest's budget for one is zero.
#
# The wart is recorded, not hidden: writing this stub over a core package member
# diverges the realized file from the contents-DB record, so `pkgchk` will report
# /usr/amiga/bin/system.setup as modified -- the same accepted class as the
# /etc/shadow and /etc/TIMEZONE edits first-boot performs (plan v3 section 8.3),
# and now three lines of it rather than a whole replaced body.
#
# `echo` lines, single-quoted so nothing expands, exactly like emit_firstboot_hook
# -- and byte-identical to the tracked master payload/firstboot/system.setup,
# which installer-selftest audit Z re-runs this function to prove.
emit_system_setup() {
	{
		echo '#!/bin/sh'
		echo '# system.setup -- ENTRY POINT for the first-boot configuration dialog (W5).'
		echo '# Written into the stock slot by src/installer/install.sh when the profile says'
		echo '# FIRSTBOOT_DIALOG=y; /etc/sysinit runs it iff it is executable, and the dialog'
		echo '# takes the exec bit off THIS file at the clean end of its summary loop.'
		echo 'exec /sbin/sh /var/adm/firstboot/firstboot.sh --dialog'
	} > "$1"
}

# ---------------------------------------------------------------------------
# 0. select + load the profile
# ---------------------------------------------------------------------------
# The argument is EITHER a profile NAME (resolved on the medium, the original
# form) OR A PATH to a profile file. The path form is what lets a future
# interview (W2 setup.sh) compose its answers into /tmp/answers.profile and hand
# that straight to this driver -- the medium is read-only, so an answers profile
# can never live under $INST/profiles. Resolution, in order:
#   * contains a '/'          -> taken as a path, verbatim (absolute or relative)
#   * names an existing file  -> taken as a path (e.g. `answers.profile` in cwd)
#   * otherwise               -> $INST/profiles/<name>.profile   (the name form)
# The name form is unchanged, so every runbook/matrix invocation keeps working.
PROFILE_ARG="$1"
[ -n "$PROFILE_ARG" ] || PROFILE_ARG=bench-a3000-a4091
case "$PROFILE_ARG" in
	*/*)	PROFILE_FILE="$PROFILE_ARG" ;;
	*)	if [ -f "$PROFILE_ARG" ]; then
			PROFILE_FILE="$PROFILE_ARG"
		else
			PROFILE_FILE="$INST/profiles/$PROFILE_ARG.profile"
		fi ;;
esac
[ -f "$PROFILE_FILE" ] || die "no profile '$PROFILE_ARG' at $PROFILE_FILE
	(available: `set -- $INST/profiles/*.profile; echo $*`  -- or pass a PATH)"

# The profile is strict KEY=value; sourcing it defines the FB_*/CD_SPEC/etc vars.
. "$PROFILE_FILE"

# --- W1 INPUT KEYS: defaults for everything the driver used to hardcode -------
# Each of these was a literal in this file (or in payload/firstboot) until W1.
# The DEFAULT is the value that literal carried, so a profile that omits the key
# behaves EXACTLY as the pre-W1 driver did -- the de-hardcode is a pure seam.
#
#   INSTALL_VERBOSE  n            quiet install (stage messages only on console)
#   FB_KMAP          <empty>      no keymap baked ("usa" means the same: the
#                                 American map is compiled in, stock links nothing)
#   FB_TZ            US/Eastern   TIMEZONE zone NAME; firstboot emits the
#                                 load-bearing leading colon itself (TZ=:<zone>)
#   FB_GATEWAY       <none>       default route for the zen0 laydown; required
#                                 only for FB_ETHER_IF=zen0 profiles (gated below)
#   FB_ZEN_IP        <none>       S3-31: zen0's own address when the z3660eth module
#   FB_ZEN_NETMASK   FB_NETMASK   is installed on a profile whose interface is not
#   FB_ZEN_GATEWAY   <none>       zen0 (S99zen beside it); empty FB_ZEN_IP = zen0 left
#                                 down; never FB_IP (two interfaces, one address)
#   FB_ZEN_CARDS     <empty>      P-3 address-by-card table, "MAC=ADDR=NAME ..."
#                                 (a "default=ADDR" word = the unknown-card row);
#                                 firstboot renders it into /etc/inet/zen.conf on a
#                                 zen0 flavor. Empty = no table (FB_IP, as before)
#   FB_DNS1/FB_DNS2  <empty>      recorded into firstboot.conf; APPLIED by
#                                 firstboot.sh from W5 on, and only on a
#                                 literal-IP (zen0) flavor -- see payload/firstboot
#   FB_REPO_URL      the live repo the /etc/apkg.conf line used to hardcode
#   TARGET_ROOT_MB   <empty>      stock-default root sizing (plan_partitions)
#   TARGET_VFSTAB_SCSI_ID <empty> the controller id written into the TARGET's
#                                 /etc/vfstab. Empty = TARGET_SCSI_ID (unchanged).
#                                 Set it only when the image is AUTHORED on one rig
#                                 and RUN on another (bench c6d0 -> metal ced0).
#   TARGET_BOOT_MB   <empty>      stock 2 MB boot slice (plan_partitions). The
#                                 040/060 target kernel goes in UNCOMPRESSED, so
#                                 2 MB is 92.7% full before anything grows.
#   TARGET_SWAP_MB   <empty>      stock-default swap sizing (plan_partitions)
#   MONSW            <empty>      P-8 monitor switch: the value written to
#                                 /etc/monsw (a bit sum of 1 2 16 32; the owner's
#                                 Z3660 boxes use 34). Set = lay down the five
#                                 /dev/monsw bits (S20monsw, monswctl, sys/monsw.h,
#                                 the c 52 0 node, /etc/monsw); empty or "none" =
#                                 none of them, exactly as before (gated below)
#   RUN_UNIT         6            the target chain: 6 = the profile's single chain;
#                                 install = one pre-framed chain per unit (Q-4.15);
#                                 hint = the family chain to any id (D-2, RTH1);
#                                 stamp = the family chain + the unit's patch rows
#                                 (D-2 fallback B). See the resolver below.
#   ROOT_RECORD_DISK <empty>      D-2: a card-0 id whose slice 3 gets the chain plus an
#                                 RTO1 root record naming the target -- for a root the
#                                 boot ROM cannot boot (behind the A4092). Needs
#                                 RUN_UNIT=hint and ROOT_RECORD_CARD<c>="<base> <id>
#                                 <flags>" for the target's card (used at media build)
#   ROOT_RECORD_BOOTPRI <empty>   with ROOT_RECORD_DISK: after the record is verified, set
#                                 that disk's UNIX_Boot to this boot priority (a separate
#                                 boot-only disk ships at -128, NOT bootable, so it cannot
#                                 win a boot before it carries a chain and a record)
#   X11KIT           <empty>      K1: the RTG desktop kit. "rtg" = lay down Xzz9000,
#                                 startx-rtg, zz9k_monsw (/opt/amix/bin, 755),
#                                 /.xinitrc-rtg (644), /dev/zz9000 c 49 0 and
#                                 /usr/X/bin on /etc/profile's PATH -- the Z3660
#                                 station's MG5 kit; empty or "none" = nothing
#   RTC              setclk       IN-rtc: the battery clock at boot. "setclk" = lay
#                                 our Y2K-fixed, plausibility-gated setclk over the
#                                 stock /usr/amiga/bin/setclk (which /etc/sysinit
#                                 already runs at every boot) and write /etc/clkzone;
#                                 "none" = leave the stock tool and clock alone (a box
#                                 with no clock battery)
#   FB_CLKZONE       <FB_TZ>      the zone the battery clock KEEPS, written to
#                                 /etc/clkzone for setclk. AmigaOS keeps the RTC in
#                                 LOCAL time, so the default is the install's own zone
#                                 (as ":<FB_TZ>", the tzfile form); a value set here is
#                                 written verbatim (e.g. ":GMT" for a UTC-kept clock)
#   TZFILES          tzdata       IN-rtc-2: the zone files. "tzdata" = lay the medium's
#                                 $INST/tz set (every 1991 zone, regenerated from
#                                 current tzdata by tools/build-tzfile.py) over
#                                 /usr/lib/locale/TZ; "stock" = keep the 1991 files
#                                 (EU summer time ends in September, US on pre-2007)
#
# --- W3b INPUT KEYS: WHICH package set this install lays down ------------------
#   INSTALL_ORDER    <empty>      which order file to install from. Empty = the
#                                 medium's own $INST/order, i.e. EXACTLY today's
#                                 behaviour, so every existing profile, runbook
#                                 line and matrix cell is untouched. A bare name
#                                 (`order.standard`) resolves on the medium; a
#                                 value containing '/' is a PATH, which is how
#                                 the interview hands over a CUSTOM selection it
#                                 filtered into /tmp (the medium is read-only).
#   INSTALL_SET      <empty>      the NAME of the set being installed, for the
#                                 log and the summary. Empty = ask the ORDER FILE
#                                 (gen-install-order.py writes a `# set: <name>`
#                                 header), and only "default" if it does not say.
#   INSTALL_ATTESTED y            does this set have a reference installed-tree
#                                 digest? `n` means the digest gate is WAIVED for
#                                 this run and the log says so in as many words
#                                 (plan §5.7). It changes NOTHING the driver
#                                 does -- the driver never gated on a digest; it
#                                 is the matrix that does, and this key is how a
#                                 run tells the record which posture it had.
[ -n "$INSTALL_VERBOSE" ] || INSTALL_VERBOSE=n
# P-8: refuse a bad monitor-switch value BEFORE anything is written -- the same
# bits monswctl itself accepts (1 CTS, 2 SEL, 16 CTS-low=RTG, 32 SEL-low=RTG).
case "$MONSW" in
	""|none|0|1|2|3|16|17|18|19|32|33|34|35|48|49|50|51)	;;
	*)	die "profile MONSW='$MONSW' is not a bit sum of 1 2 16 32 (or 'none')" ;;
esac
case "$X11KIT" in
	""|none|rtg)	;;
	*)	die "profile X11KIT='$X11KIT' is not 'rtg' (or 'none')" ;;
esac
case "$INSTALL_VERBOSE" in
	[yY]|[yY][eE][sS]|1)	VERBOSE=1 ;;
	[nN]|[nN][oO]|0|"")	VERBOSE= ;;
	*)			die "profile INSTALL_VERBOSE='$INSTALL_VERBOSE' is not y or n" ;;
esac
[ -n "$FB_TZ" ] || FB_TZ=US/Eastern
# The tzfile form is `TZ=:<pathname>` and the COLON IS EMITTED BY CODE, never
# carried in data (W6.3: a colon-less TZ BUS-ERRORs every ctime(3) consumer at
# cold boot). A profile that writes the colon anyway must not produce `TZ=::...`,
# so strip a leading colon here and let the emitter own it.
case "$FB_TZ" in
	:*)	FB_TZ=`expr "$FB_TZ" : ':\(.*\)'` ;;
esac
[ -n "$FB_REPO_URL" ] || FB_REPO_URL=http://pkg.amigaux.org
[ -n "$RTC" ] || RTC=setclk
case "$RTC" in
	setclk|none)	;;
	*)	die "profile RTC='$RTC' is not 'setclk' (default) or 'none'" ;;
esac
[ -n "$FB_CLKZONE" ] || FB_CLKZONE=":$FB_TZ"
[ -n "$TZFILES" ] || TZFILES=tzdata
case "$TZFILES" in
	tzdata|stock)	;;
	*)	die "profile TZFILES='$TZFILES' is not 'tzdata' (default) or 'stock'" ;;
esac
# --- W5 INPUT KEY: does this install ARM the first-boot dialog? ----------------
#   FIRSTBOOT_DIALOG n            NO dialog: the stock sysinit dialog is disarmed
#                                 (`chmod -x`, its own lever) and the box configures
#                                 itself from firstboot.conf alone. This is exactly
#                                 today's behaviour, so every canned profile and
#                                 every unattended matrix cell is byte-unchanged.
#                                 =y arms OUR dialog in that same slot (see the
#                                 arm step below); the interview writes the key,
#                                 because "interactive install" is precisely when
#                                 there is an operator to answer it.
[ -n "$KERNEL_SDDEVSIZE" ] || KERNEL_SDDEVSIZE=stock
case "$KERNEL_SDDEVSIZE" in
	stock|fixed)	;;
	*)		die "profile KERNEL_SDDEVSIZE='$KERNEL_SDDEVSIZE' is not stock or fixed" ;;
esac
[ -n "$FIRSTBOOT_DIALOG" ] || FIRSTBOOT_DIALOG=n
case "$FIRSTBOOT_DIALOG" in
	[yY]|[yY][eE][sS]|1)	FIRSTBOOT_DIALOG=y ;;
	[nN]|[nN][oO]|0)	FIRSTBOOT_DIALOG=n ;;
	*)			die "profile FIRSTBOOT_DIALOG='$FIRSTBOOT_DIALOG' is not y or n" ;;
esac
# Both default to the behaviour the driver has always had, so a profile that omits
# them installs a byte-identical tree: root may telnet in (the shipped
# /etc/default/login already has `#CONSOLE=`), and the laid-down syslog unit stays
# enabled. The first-boot dialog asks for both and overwrites them in the conf.
[ -n "$FB_ROOT_TELNET" ] || FB_ROOT_TELNET=y
case "$FB_ROOT_TELNET" in
	[yY]|[yY][eE][sS]|1)	FB_ROOT_TELNET=y ;;
	[nN]|[nN][oO]|0)	FB_ROOT_TELNET=n ;;
	*)			die "profile FB_ROOT_TELNET='$FB_ROOT_TELNET' is not y or n" ;;
esac
[ -n "$FB_SYSLOG" ] || FB_SYSLOG=y
case "$FB_SYSLOG" in
	[yY]|[yY][eE][sS]|1)	FB_SYSLOG=y ;;
	[nN]|[nN][oO]|0)	FB_SYSLOG=n ;;
	*)			die "profile FB_SYSLOG='$FB_SYSLOG' is not y or n" ;;
esac
[ -n "$INSTALL_ATTESTED" ] || INSTALL_ATTESTED=y
case "$INSTALL_ATTESTED" in
	[yY]|[yY][eE][sS]|1)	INSTALL_ATTESTED=y ;;
	[nN]|[nN][oO]|0)	INSTALL_ATTESTED=n ;;
	*)			die "profile INSTALL_ATTESTED='$INSTALL_ATTESTED' is not y or n" ;;
esac

# --- UFS INPUT KEY: which filesystem the TARGET ROOT gets ---------------------
#   TARGET_ROOT_FSTYPE  s5   the filesystem laid on the target root slice.
#                            `ufs` is the Berkeley filesystem the 1991
#                            documentation itself recommends, and it is what the
#                            INTERVIEW now defaults to (setup.sh, `[ufs]`); `s5`
#                            is the traditional one and stays fully selectable.
#
# ★ THE DEFAULT HERE IS s5 AND THAT IS NOT THE PRODUCT DEFAULT. It is the
# compatibility floor, the same seam law every other key in this file follows: a
# profile (or a medium) written before this key existed must install the
# byte-identical tree it always did. The PRODUCT default -- what a person at the
# console gets by pressing RETURN -- is `ufs`, and it arrives here as an ANSWER,
# appended to the profile by setup.sh. An unattended profile says what it means.
#
# What the fs type does and does NOT reach:
#   * mkfs / labelit / the pre-mount check / the mount type  -- section 2 below.
#   * the target's /etc/vfstab column 4                      -- FB_ROOT_FSTYPE,
#     emitted into firstboot.conf in section 9 and consumed by firstboot.sh.
#   * NOT the running miniroot's own /etc/mnttab seed line (section 4) -- that
#     line describes the RUNNING MINIROOT ($MINIROOT_FSTYPE, derived from
#     INSTALL_CPU: s5 on the 030 line, ufs on 040/060), whatever the target is.
#     See the trap note there.
#   * NOT swap and NOT the boot slice: both are RAW. `swap -a` hands a block
#     device to the kernel's swap layer and the ROM/boot1 read the boot slice as
#     raw sectors -- no filesystem is involved in either, on either fs type.
#   * NOT the installed-tree DIGEST. Attestation is computed from the contents
#     DB + passwd + group (altroot_attest), none of which has a filesystem field,
#     so a ufs install of a given set must reproduce that set's EXISTING digest
#     exactly. A difference would be a bug, not a new baseline.
# Evidence for all of the above: docs/ufs-target-scoping.md (media/tooling) and
# ../amix-kerntools/docs/ufs-root-kernel-capability.md (the kernel half: `ufs`
# sits at vfssw[2] in every kernel we build, rootfstype is compiled EMPTY so
# vfs_mountroot probes s5 then ufs, and a ufs root costs zero kernel bytes).
[ -n "$TARGET_ROOT_FSTYPE" ] || TARGET_ROOT_FSTYPE=s5
case "$TARGET_ROOT_FSTYPE" in
	s5|ufs)	: ;;
	*)	die "profile TARGET_ROOT_FSTYPE='$TARGET_ROOT_FSTYPE' is not s5 or ufs" ;;
esac

# --- TARGET_RDB_BLOCK: where the author path puts the RDSK block (2026-09-26) ---
#   TARGET_RDB_BLOCK  0   the block `/etc/rdb -c -L` writes the RDSK to on a
#                         target that carries no RDB. 0 (the DEFAULT) or 2 (the
#                         stock script's `-L 2`), nothing else.
# ★ WHY 0, NOT STOCK'S 2. Stock Z3660 firmware's piscsi_parse_rdb reads the image
# in 64 KB strides and tests only the first 4 bytes of each read, so it can find
# an RDB at byte 0 and never at block 2: an RDSK-at-2 root is "No RDB found" on
# stock firmware (only the fork's blocks-1..15 scan finds it). Blocks 0-1 carry
# NOTHING on an Amix disk -- the boot chain lives in the UNI\0 slice, found via the
# RDB -- and every rdb-reading consumer (Kickstart, sdpart.c, /etc/rdb itself,
# tools/lib/rdb.py) scans blocks 0..15, so RDSK at 0 boots everywhere RDSK at 2
# does. /etc/rdb -c honours -L ONLY on a disk with no RDSK in 0..15 (it rewrites
# an existing RDB where it finds it), which is why the author path clears blocks
# 0..15 first and reads the result back. =2 exists for a legacy medium only.
[ -n "$TARGET_RDB_BLOCK" ] || TARGET_RDB_BLOCK=0
case "$TARGET_RDB_BLOCK" in
	0|2)	: ;;
	*)	die "profile TARGET_RDB_BLOCK='$TARGET_RDB_BLOCK' is not 0 (default) or 2 (legacy stock)" ;;
esac

# --- INSTALL_CPU: which CPU line THIS medium serves; picks the MINIROOT's fs ---
#   INSTALL_CPU  030  the CPU family of THIS boot/install medium: 030 (our proven
#                     s5-miniroot line, 2 KiB pages) or 040/060 (the 040/060 line,
#                     4 KiB pages). It is NOT a target choice -- it is a property of
#                     the medium the machine booted, and it decides the RUNNING
#                     MINIROOT's own filesystem (MINIROOT_FSTYPE just below), which
#                     the /etc/mnttab seed line (section 4) must name.
#
# ★ THE DEFAULT IS 030 -- the compatibility floor, the same seam law every other
# key here follows. A profile or medium written before this key existed serves the
# 030 s5-miniroot line, so MINIROOT_FSTYPE resolves to `s5` and the /etc/mnttab
# seed line is BYTE-IDENTICAL to what it always was. The 040/060 line is UFS-only:
# s5 is structurally broken under 4 KiB pages (docs/miniroot.md "The UFS miniroot";
# the 040/060 campaign plan §1), so the miniroot fs is a STRICT function of the CPU
# line. Deriving MINIROOT_FSTYPE from INSTALL_CPU here keeps ONE source of truth --
# a separate MINIROOT_FSTYPE key could silently contradict the medium that booted.
[ -n "$INSTALL_CPU" ] || INSTALL_CPU=030
case "$INSTALL_CPU" in
	030)		MINIROOT_FSTYPE=s5 ;;
	040|060)	MINIROOT_FSTYPE=ufs ;;
	*)		die "profile INSTALL_CPU='$INSTALL_CPU' is not 030, 040 or 060" ;;
esac

# --- INSTALL_LAYOUT: the 1.0 disk or the 1.1 disk (amix-dlm spec 40 §2.1) ------
#   INSTALL_LAYOUT  1.0  root, swap and a boot slice holding the framed 1.0 chain.
#                        1.1: root, swap, the 64 MiB boot store (generations, the
#                        new loader) and an optional data slice; the kernel comes
#                        in as a kernel-space package and kbootset writes the store.
# The default is 1.0, so every profile and medium written before the key installs
# the byte-identical disk it always did. The 1.1 half lives on the medium in
# $INST/l11/l11.sh and is only ever sourced here.
[ -n "$INSTALL_LAYOUT" ] || INSTALL_LAYOUT=1.0
case "$INSTALL_LAYOUT" in
	1.0)	: ;;
	1.1)	[ -f "$INST/l11/l11.sh" ] || die "INSTALL_LAYOUT=1.1 but the medium has no $INST/l11/l11.sh"
		. "$INST/l11/l11.sh"
		l11_keys ;;
	*)	die "profile INSTALL_LAYOUT='$INSTALL_LAYOUT' is not 1.0 or 1.1" ;;
esac

# --- SOURCE dimension (W6-RAW.1): where the base packages come from -----------
# SOURCE_KIND=cdfs (default, backward-compatible) sources the install CD via the
# cdfs helper and the per-file pkgadd -R loop. SOURCE_KIND=raw sources a raw
# distribution slice via the CD-resident static apkg (SRC_RAW). Each kind requires
# a different set of profile keys; validate the right ones. Absent => cdfs, so
# every pre-W6-RAW.1 profile keeps working unchanged.
[ -n "$SOURCE_KIND" ] || SOURCE_KIND=cdfs
case "$SOURCE_KIND" in
	cdfs)
		: "${CD_SPEC:?profile missing CD_SPEC (SOURCE_KIND=cdfs)}"
		;;
	raw)
		: "${SRC_SCSI_ID:?profile missing SRC_SCSI_ID (SOURCE_KIND=raw)}"
		: "${SRC_PAYLOAD_SLICE:?profile missing SRC_PAYLOAD_SLICE (SOURCE_KIND=raw)}"
		: "${SRC_RAW_SLICE:?profile missing SRC_RAW_SLICE (SOURCE_KIND=raw)}"
		;;
	*)
		die "profile SOURCE_KIND='$SOURCE_KIND' is not 'cdfs' or 'raw'"
		;;
esac
: "${TARGET_SCSI_ID:?profile missing TARGET_SCSI_ID}"
: "${TARGET_ROOT_SLICE:?profile missing TARGET_ROOT_SLICE}"
: "${TARGET_SWAP_SLICE:?profile missing TARGET_SWAP_SLICE}"
: "${TARGET_BOOT_SLICE:?profile missing TARGET_BOOT_SLICE}"
if [ "$INSTALL_LAYOUT" = 1.0 ]; then	# a 1.1 disk carries no framed chain
	: "${BOOTSLICE_IMG:?profile missing BOOTSLICE_IMG}"
	: "${BOOT2_BOOT:?profile missing BOOT2_BOOT}"
	: "${BOOTSLICE_MANIFEST:?profile missing BOOTSLICE_MANIFEST}"
fi

# The cXd0 block/raw namespace binds to the PRIMARY (system) SCSI controller, not
# to whichever physical HBA the profile's TARGET_HBA names. W5.4b proved this on
# the bench two-HBA rig: the target on the A3000's onboard SCSI at id 6 answered at
# c6d0 (dd read + fsck_s5 both clean), while the SAME disk on the A4091 did not
# ("Can't open" / I/O error, 0+0 records) -- there the A4091 carries only the CD
# (cdfs 1,3, by card index). So the driver builds device nodes purely from
# TARGET_SCSI_ID; TARGET_HBA stays informational (which HBA the disk hangs off).
ID="$TARGET_SCSI_ID"
# --- CD-2: a target behind the A4092 (card 1) ------------------------------------
# The id is a controller number c<N>d0, N = card*8 + unit in hex (9 = card 1 unit 1; cards
# 2-3 are 10-1f, C4-1 §2.2). Two kinds of id
# are never a target: the host adapters' own (unit 7: 7, f, 17, 1f), and the install CD's unit (cdfs
# <card>,<unit>) -- only cdfs may talk to a CD behind an A4091/A4092; a dd-layer read
# of it wedges that bus (A4091-UA, 2026-10-05). The K1 miniroot carries card-1 nodes
# only for c8 and ce, so a card-1 target's nodes are made here (the same helper and
# majors as setup.sh's; installer-selftest audit CD2 keeps the two copies equal).
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
cd_unit_id()
{
	[ -n "$CD_SPEC" ] || return 0
	_cc=`expr "$CD_SPEC" : '\([0-9]*\),'`
	_cu=`expr "$CD_SPEC" : '[0-9]*,\([0-9]*\)'`
	[ -n "$_cc" ] && [ -n "$_cu" ] || return 0
	hexname `expr $_cc \* 8 + $_cu`
}
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
[ -n "`hexval "$ID"`" ] || die "TARGET_SCSI_ID='$ID' is not a controller number (0-f, 10-1f)"
case "$ID" in
	7|f|F|17|1f|1F)	die "TARGET_SCSI_ID=$ID is a host adapter's own id -- never a target" ;;
esac
if [ "$SOURCE_KIND" = cdfs ] && [ "$ID" = "`cd_unit_id`" ]; then
	die "TARGET_SCSI_ID=$ID is the install CD's own unit (cdfs $CD_SPEC) -- never a target"
fi
if [ ! -b "/dev/dsk/c${ID}d0s0" ]; then
	ensure_disk_nodes "$ID" || die "cannot create the device nodes for SCSI id $ID"
	msg "made /dev/[r]dsk/c${ID}d0s0..s5 (sd majors $SD_BMAJ/$SD_CMAJ) -- this miniroot did not carry them"
fi
ROOT_BLK="/dev/dsk/c${ID}d0s${TARGET_ROOT_SLICE}"
ROOT_RAW="/dev/rdsk/c${ID}d0s${TARGET_ROOT_SLICE}"
BOOT_RAW="/dev/rdsk/c${ID}d0s${TARGET_BOOT_SLICE}"
DISK_RAW="/dev/rdsk/c${ID}d0s0"          # whole-disk node for /etc/rdb

# --- Q-4.15 PICK-AT-INSTALL: the target kernel follows the chosen unit ---------
# RUN_UNIT=install (the public K1 media): the medium carries one pre-framed chain per
# installable unit, boot/<p>/u<N>/{bootslice.img,bootslice.manifest|.man,boot2.boot,unix},
# and boot/<p>/units ("<id> <rootdev> <kernel sum -r>" per row). The row of the chosen
# id replaces the profile's single chain, ROOTDEV and KERNEL_BREL_SUMR, and the vfstab /
# first-boot unit becomes the chosen id -- Amix then roots the disk it was installed to.
# RUN_UNIT=6 (or unset): the profile's single chain, exactly as before. Host-built and
# gated chains only: nothing is patched on the box (the kernel IBLK checksum covers it).
#
# D-2 (r6), ONE KERNEL PER FAMILY on the medium -- two more modes; `install` stays
# selectable until r6 is accepted:
# RUN_UNIT=hint (design A): the family's single chain goes to the chosen id UNCHANGED. Its
#   loader (good_040_rth / good_rth) passes the RTH1 root hint and the kernel roots the
#   disk it was booted from (or the one an RTO1 root record names, see ROOT_RECORD_DISK).
#   ROOTDEV/KERNEL_BREL_SUMR stay the family's (its built-in root is unit 6, card 0); the
#   vfstab / first-boot unit becomes the chosen id.
# RUN_UNIT=stamp (fallback B, owner rule: kept warm): the family chain + the chosen unit's
#   patch rows (boot/<p>/stamp/u<N>.patch, from tools/rth1-media.py) -- the rootdev byte,
#   the swap-name digit, the IBLK checksum -- applied to the WRITTEN slice and verified byte
#   by byte and against the unit's own manifest; /stand/unix is then read out of the patched
#   slice. The result is byte-identical to the per-unit chain (measured 2026-10-05).
STAND_UNIX=
STAMP_PATCH=
STAND_UNIX_FROM_SLICE=
case "${RUN_UNIT:-6}" in
	hint)
		TARGET_VFSTAB_SCSI_ID="$ID"
		msg "one kernel per family (RTH1 root hint): the family chain goes to SCSI id $ID unchanged"
		;;
	stamp)
		UDIR=`expr "$BOOTSLICE_IMG" : '\(.*\)/'`
		STAB="$INST/$UDIR/stamp/units"
		[ -f "$STAB" ] || die "RUN_UNIT=stamp but this medium has no stamp table at $STAB"
		rm -f /tmp/.unitrow
		while read u_id u_rootdev u_sumr u_klen; do
			[ "$u_id" = "$ID" ] && echo "ROOTDEV=$u_rootdev KERNEL_BREL_SUMR=$u_sumr STAND_UNIX_FROM_SLICE=$u_klen" > /tmp/.unitrow
		done < "$STAB"
		[ -s /tmp/.unitrow ] || die "this medium carries no stamp for SCSI id $ID (its units: $STAB)"
		. /tmp/.unitrow
		rm -f /tmp/.unitrow
		STAMP_PATCH="$INST/$UDIR/stamp/u$ID.patch"
		[ -f "$STAMP_PATCH" ] || die "RUN_UNIT=stamp: no patch for SCSI id $ID at $STAMP_PATCH"
		BOOTSLICE_MANIFEST="$UDIR/stamp/u$ID.manifest"
		TARGET_VFSTAB_SCSI_ID="$ID"
		msg "one kernel per family, stamped at install: SCSI id $ID (rootdev $ROOTDEV, kernel sum -r $KERNEL_BREL_SUMR)"
		;;
	install)
		UDIR=`expr "$BOOTSLICE_IMG" : '\(.*\)/'`
		UTAB="$INST/$UDIR/units"
		[ -f "$UTAB" ] || die "RUN_UNIT=install but this medium has no unit table at $UTAB"
		rm -f /tmp/.unitrow
		while read u_id u_rootdev u_sumr; do
			[ "$u_id" = "$ID" ] && echo "ROOTDEV=$u_rootdev KERNEL_BREL_SUMR=$u_sumr" > /tmp/.unitrow
		done < "$UTAB"
		[ -s /tmp/.unitrow ] || die "this medium carries no kernel for SCSI id $ID (its units: $UTAB)"
		. /tmp/.unitrow
		rm -f /tmp/.unitrow
		BOOTSLICE_IMG="$UDIR/u$ID/bootslice.img"
		BOOTSLICE_MANIFEST="$UDIR/u$ID/bootslice.manifest"
		[ -f "$INST/$BOOTSLICE_MANIFEST" ] || BOOTSLICE_MANIFEST="$UDIR/u$ID/bootslice.man"
		BOOT2_BOOT="$UDIR/u$ID/boot2.boot"
		STAND_UNIX="$UDIR/u$ID/unix"
		TARGET_VFSTAB_SCSI_ID="$ID"
		msg "pick-at-install: SCSI id $ID -> $UDIR/u$ID (rootdev $ROOTDEV, kernel sum -r $KERNEL_BREL_SUMR)"
		;;
	6)	: ;;
	*)	die "profile RUN_UNIT='$RUN_UNIT' is not 6, install, hint or stamp" ;;
esac
# The 040/060 line: /stand/unix must be the kernel the boot slice frames (the port's trap
# ii -- a user's `make bootpart` / updbootpart reframes /stand/unix, and the stock core
# package's 1992 030 kernel there would frame an unbootable chain). RUN_UNIT=6 media ship
# it beside the single chain as boot/<p>/unix.
if [ "$INSTALL_LAYOUT" = 1.0 ] && [ -z "$STAND_UNIX" ] && [ -z "$STAND_UNIX_FROM_SLICE" ]; then
	case "${INSTALL_CPU:-030}" in
		040|060)	STAND_UNIX="`expr "$BOOTSLICE_IMG" : '\(.*\)/'`/unix" ;;
	esac
fi

# --- RAW source devices (SOURCE_KIND=raw): the second disk at SRC_SCSI_ID ------
# The payload s5 slice is mounted AT /cdrom (the operator mounts it before
# launching the driver; see below), so $INST/... paths are byte-unchanged. The
# raw distribution slice is the apkg SRC_RAW device (a raw character node --
# apkg dd's the catalog + package datastreams straight out of it by byte offset).
if [ "$SOURCE_KIND" = raw ]; then
	SRC_ID="$SRC_SCSI_ID"
	SRC_PAYLOAD_BLK="/dev/dsk/c${SRC_ID}d0s${SRC_PAYLOAD_SLICE}"
	SRC_RAW_DEV="/dev/rdsk/c${SRC_ID}d0s${SRC_RAW_SLICE}"
fi

msg "profile      : $PROFILE_NAME"
msg "  $PROFILE_DESC"
if [ "$SOURCE_KIND" = raw ]; then
	msg "install src  : RAW  payload $SRC_PAYLOAD_BLK -> $CDROOT (s5)  packages $SRC_RAW_DEV (apkg SRC_RAW)"
else
	msg "install src  : cdfs $CD_SPEC -> $CDROOT"
fi
msg "target disk  : c${ID}d0  root=s${TARGET_ROOT_SLICE} swap=s${TARGET_SWAP_SLICE} boot=s${TARGET_BOOT_SLICE}"
if [ "$INSTALL_LAYOUT" = 1.0 ]; then
	msg "target kernel: relocunix sum -r $KERNEL_RELOCUNIX_SUMR / brel $KERNEL_BREL_SUMR (rootdev $ROOTDEV)"
fi

# ===========================================================================
# 1. DISCOVER + PLAN -- the partition arithmetic (mkroot.sh, transcribed to sh)
# ===========================================================================
# Every step mirrors tools/mkroot.sh's python (which is itself the stock install
# script, verbatim). Sizes are 512-byte blocks; 2048 blocks == 1 MB; slices are
# rounded DOWN to a whole cylinder (SECS blocks). tools/installer-selftest.py
# cross-checks this arithmetic against mkroot.sh for several disk sizes.
plan_partitions() {
	disk_mb="$1"
	DISKLEN=`expr "$disk_mb" \* "$BLOCKS_PER_MB"`
	off="$OFFSET_BLOCKS"
	REMAIN=`expr "$DISKLEN" - "$off"`

	# round OFFSET up to a cylinder, then REMAIN down to a cylinder
	ROUND=`expr "$off" % "$SECS"`
	if [ "$ROUND" -gt 0 ]; then
		add=`expr "$SECS" - "$ROUND"`
		off=`expr "$off" + "$add"`
		REMAIN=`expr "$REMAIN" - "$add"`
	fi
	rmod=`expr "$REMAIN" % "$SECS"`
	REMAIN=`expr "$REMAIN" - "$rmod"`

	# boot
	# TARGET_BOOT_MB overrides the stock 2 MB boot slice. Stock never ASKED for
	# this one -- it states it ("Your boot partition is $BOOTSIZE megabytes.") --
	# so unlike TARGET_ROOT_MB there is no stock prompt whose bounds to mirror.
	# The bounds that do apply are structural: at least MINBOOT (the chain plus a
	# kernel has to fit, and mkroot.sh enforces the same floor), and it has to
	# leave a root and a swap behind. A whole number of MB is always
	# cylinder-aligned here (BLOCKS_PER_MB 2048 % SECS 64 == 0), so no rounding
	# is owed. Empty = the stock 2, and every existing profile is byte-unchanged.
	#
	# Why it exists: the 68040/68060 target kernel goes into the boot slice
	# UNCOMPRESSED (ET_REL, no elf2brel framing on that line), and FPE r13 plus
	# the 0x2800 chain is 1,943,513 B -- 92.7% of a 2 MB slice. That fits, but a
	# disk handed to someone who BUILDS kernels has ~150 KB of headroom, and
	# growing a boot slice afterwards is a re-partition, i.e. a re-install.
	# 1.1: the boot slice is the 64 MiB store, fixed by the spec (l11_keys refuses
	# TARGET_BOOT_MB), and a data slice may come off the end (l11_plan_data).
	[ "$INSTALL_LAYOUT" = 1.1 ] && BOOTSIZE="$L11_STORE_MB"
	if [ -n "$TARGET_BOOT_MB" ]; then
		is_num "$TARGET_BOOT_MB" || die "TARGET_BOOT_MB='$TARGET_BOOT_MB' is not a number"
		[ "$TARGET_BOOT_MB" -ge "$MINBOOT" ] || die "TARGET_BOOT_MB=$TARGET_BOOT_MB is below the minimum boot partition of ${MINBOOT}MB"
		BOOTSIZE="$TARGET_BOOT_MB"
	fi
	BOOTLEN=`expr "$BOOTSIZE" \* "$BLOCKS_PER_MB"`
	[ "$BOOTLEN" -lt "$REMAIN" ] || die "disk too small for a ${BOOTSIZE}MB boot partition"
	REMAIN=`expr "$REMAIN" - "$BOOTLEN"`
	DATALEN=0
	if [ "$INSTALL_LAYOUT" = 1.1 ]; then
		l11_plan_data "$disk_mb"
		[ "$DATALEN" -lt "$REMAIN" ] || die "disk too small for a ${DATA_MB}MB data slice"
		REMAIN=`expr "$REMAIN" - "$DATALEN"`
	fi

	# swap default: BREAKPT rule
	if [ "$disk_mb" -gt "$BREAKPT" ]; then DEFSWAP="$LGSWAP"; else DEFSWAP="$SMSWAP"; fi
	# r6 (owner 2026-10-06): the 040/060 kernels link a 61440-sector (30 MB) swapfile; a shorter
	# slice 2 leaves the tail of that swap failing with EIO -- so 30 MB is the default AND the floor.
	if [ "${INSTALL_CPU:-030}" = 040 ] || [ "${INSTALL_CPU:-030}" = 060 ]; then
		DEFSWAP=30; MINSWAP=30; SWAPWHY=" (the 68040/68060 kernels link a 30 MB swap area)"
	fi

	# ROOTMAX = the stock ceiling on the root answer: what is left once the
	# MINSWAP floor is reserved. Stock computes it right here, from the SAME
	# pre-root REMAIN, to bound its "How many megabytes for the root file
	# system?" answer. Unused on the default path; it is the validation bound
	# for a TARGET_ROOT_MB override. (Stock writes it as one parenthesised expr;
	# we step it out -- escaped parens are not worth the trouble here.)
	minswblk=`expr "$MINSWAP" \* "$BLOCKS_PER_MB"`
	rootmaxblk=`expr "$REMAIN" - "$minswblk"`
	ROOTMAX=`expr "$rootmaxblk" / "$BLOCKS_PER_MB"`

	# root = REMAIN minus the default swap (the stock default answer)
	swblk=`expr "$DEFSWAP" \* "$BLOCKS_PER_MB"`
	rootblk=`expr "$REMAIN" - "$swblk"`
	ROOT_MB=`expr "$rootblk" / "$BLOCKS_PER_MB"`
	# E-BIG: the stock kernel's on-box root ceiling (see SDDEV_CAP_BLOCKS).
	ROOTCAP=
	[ "$KERNEL_SDDEVSIZE" = fixed ] || ROOTCAP=`expr "$SDDEV_CAP_BLOCKS" / "$BLOCKS_PER_MB"`
	if [ -n "$ROOTCAP" ] && [ "$ROOTMAX" -gt "$ROOTCAP" ]; then ROOTMAX="$ROOTCAP"; fi
	if [ -n "$ROOTCAP" ] && [ "$ROOT_MB" -gt "$ROOTCAP" ]; then
		msg "root size    : ${ROOT_MB}MB capped to ${ROOTCAP}MB -- this kernel limits an on-box root to ${ROOTCAP} MB"
		ROOT_MB="$ROOTCAP"
	fi
	# TARGET_ROOT_MB overrides the stock DEFAULT answer -- it is the profile's
	# stand-in for what stock asked. Validated against the SAME two stock bounds
	# the interactive prompt enforced (>= MINROOT, <= ROOTMAX); unset leaves the
	# arithmetic byte-identical to the pre-W1 driver.
	if [ -n "$TARGET_ROOT_MB" ]; then
		is_num "$TARGET_ROOT_MB" || die "TARGET_ROOT_MB='$TARGET_ROOT_MB' is not a number"
		[ "$TARGET_ROOT_MB" -ge "$MINROOT" ] || die "TARGET_ROOT_MB=$TARGET_ROOT_MB is below the stock minimum root of ${MINROOT}MB"
		if [ -n "$ROOTCAP" ] && [ "$TARGET_ROOT_MB" -gt "$ROOTCAP" ]; then
			die "TARGET_ROOT_MB=$TARGET_ROOT_MB exceeds ${ROOTCAP}MB -- this kernel limits an on-box root to ${ROOTCAP} MB"
		fi
		[ "$TARGET_ROOT_MB" -le "$ROOTMAX" ] || die "TARGET_ROOT_MB=$TARGET_ROOT_MB exceeds ${ROOTMAX}MB -- stock leaves at least ${MINSWAP}MB free for swap"
		ROOT_MB="$TARGET_ROOT_MB"
	fi
	[ "$ROOT_MB" -ge "$MINROOT" ] || die "disk yields only ${ROOT_MB}MB root; stock minimum ${MINROOT}MB"
	ROOTLEN=`expr "$ROOT_MB" \* "$BLOCKS_PER_MB"`
	rmod=`expr "$ROOTLEN" % "$SECS"`
	ROOTLEN=`expr "$ROOTLEN" - "$rmod"`
	REMAIN=`expr "$REMAIN" - "$ROOTLEN"`

	# swap = what is left, capped at DEFSWAP, cylinder-aligned
	MAXSWAP=`expr "$REMAIN" / "$BLOCKS_PER_MB"`
	SWAP_MB="$MAXSWAP"
	if [ "$SWAP_MB" -gt "$DEFSWAP" ]; then SWAP_MB="$DEFSWAP"; fi
	# TARGET_SWAP_MB overrides the stock default swap answer, bounded by the same
	# stock pair (>= MINSWAP, <= what actually remains). Unset => unchanged.
	if [ -n "$TARGET_SWAP_MB" ]; then
		is_num "$TARGET_SWAP_MB" || die "TARGET_SWAP_MB='$TARGET_SWAP_MB' is not a number"
		[ "$TARGET_SWAP_MB" -ge "$MINSWAP" ] || die "TARGET_SWAP_MB=$TARGET_SWAP_MB is below the stock minimum swap of ${MINSWAP}MB${SWAPWHY:-}"
		[ "$TARGET_SWAP_MB" -le "$MAXSWAP" ] || die "TARGET_SWAP_MB=$TARGET_SWAP_MB exceeds the ${MAXSWAP}MB remaining after root"
		SWAP_MB="$TARGET_SWAP_MB"
	fi
	SWAPLEN=`expr "$SWAP_MB" \* "$BLOCKS_PER_MB"`
	if [ "$SWAPLEN" -gt "$REMAIN" ]; then SWAPLEN="$REMAIN"; fi
	rmod=`expr "$SWAPLEN" % "$SECS"`
	SWAPLEN=`expr "$SWAPLEN" - "$rmod"`
	[ "$SWAPLEN" -gt 0 ] || die "no room for the STRUCTURAL swap slice (it is what puts boot at slice 3)"

	# lay out IN ORDER: root, swap, boot -- this ordering IS the slice map
	ROOT_OFF="$off"
	SWAP_OFF=`expr "$ROOT_OFF" + "$ROOTLEN"`
	BOOT_OFF=`expr "$SWAP_OFF" + "$SWAPLEN"`
	DATA_OFF=`expr "$BOOT_OFF" + "$BOOTLEN"`
}

# --- geometry: TARGET_DISK_MB, else the REAL disk, probed (W1) ----------------
# The stock installer sized the plan from the disk it was pointed at:
#     DISKLEN=`/etc/ddsize $rDISK`   ;   DISKMB=`expr $DISKLEN / 2048`
# and /etc/ddsize IS on our miniroot (miniroot.proto) -- it was simply unused, so
# a profile HINT drove the plan and a 500 MB disk got whatever layout the hint
# described (the bench hint is 100 MB). W1 restores that input for the case the
# hint cannot cover -- a disk nobody wrote a profile for:
#   * TARGET_DISK_MB set   -> it WINS and THE PROBE IS NOT RUN AT ALL. Every
#                             tracked profile, runbook and mkroot-prebuilt target
#                             pins it, so today's flows do not touch ddsize.
#   * TARGET_DISK_MB unset -> the probe drives the plan (the stock behaviour;
#                             this is the path the W2 interview will use).
#   * probe unusable        -> 100 MB, the historical fallback.
#
# ★ WHY THE PIN SHORT-CIRCUITS THE PROBE (bench finding, 2026-08-11, W1).
# An earlier cut of this code probed UNCONDITIONALLY, just to log the real size
# and warn when it disagreed with the pin. That WEDGED THE INSTALL on the bench
# rig: install-matrix cell `cd` printed the profile banner, then the kernel
# printed `a3091: 0x1 0 0x0` and the driver never advanced past this line
# (matrix run 20260811-094255-cd, install gate FAIL after the 300 s go-marker
# budget). So `/etc/ddsize` against /dev/rdsk/c6d0s0 is NOT SAFE on the A3000
# onboard-SCSI (a3091) path under Amiberry -- the stock installer ran it on
# stock kernels and stock rigs, which is not what we boot. There is no timeout
# tool on the miniroot, so a hang here cannot be bounded: the only safe posture
# is to not call it when we do not have to. The message below prints BEFORE the
# call, so if the probe ever does wedge, the console says exactly where.
# ★ W2 CONSUMES THIS: the interview's destination screen is specced to build a
# per-id size table from real ddsize probes. That must be re-verified on the
# bench first -- see docs/installer.md "W1: driver plumbing".
#
# ddsize prints the disk length in 512-BYTE BLOCKS (the same unit plan_partitions
# computes DISKLEN in, and the same unit `/etc/rdb -c -d` wants). The `read`
# strips any padding; is_num FAILS CLOSED on an unreadable device (empty output
# is not a number), so a missing/dead disk can never be read as "0 MB".
DISK_MB="$TARGET_DISK_MB"
if [ -n "$DISK_MB" ]; then
	msg "disk size    : ${DISK_MB}MB from the profile (TARGET_DISK_MB pinned -- /etc/ddsize not probed)"
else
	msg "disk size    : no TARGET_DISK_MB pinned -- probing /etc/ddsize $DISK_RAW ..."
	PROBE_BLOCKS=`/etc/ddsize "$DISK_RAW" 2>/dev/null | ( read n rest; echo "$n" )`
	if is_num "$PROBE_BLOCKS" && [ "$PROBE_BLOCKS" -gt 0 ]; then
		DISK_MB=`expr "$PROBE_BLOCKS" / "$BLOCKS_PER_MB"`
		msg "disk probe   : $PROBE_BLOCKS blocks = ${DISK_MB}MB"
	else
		warn "disk probe: /etc/ddsize $DISK_RAW returned no usable size -- falling back to the 100MB default"
	fi
fi
[ -n "$DISK_MB" ] || DISK_MB=100
plan_partitions "$DISK_MB"
msg "plan (${DISK_MB}MB, cyl=${SECS} blocks): root ${ROOT_MB}MB @blk${ROOT_OFF}  swap ${SWAP_MB}MB @blk${SWAP_OFF}  boot ${BOOTSIZE}MB @blk${BOOT_OFF}"
[ "$DATALEN" -gt 0 ] && msg "plan (1.1)   : data ${DATA_MB}MB @blk${DATA_OFF} (s4, /home)"

# --- 1b. MACHINE CLASS: detect-and-print the OLD_BOOT hole (W6, plan sec. 6) --
# The interview refuses this class outright (setup.sh check_old_boot). The
# DRIVER only says so, for two reasons: an unattended run has already been
# pointed at a profile by somebody who knows the rig, and this is the last point
# before the first write -- refusing here would turn a diagnosis into a new way
# for a working install to stop. So it diagnoses, loudly, and continues.
#
# What it diagnoses: Kickstart 1.3 (a ROM smaller than 512 KB) or an A2090
# controller. Stock 2.1 supported both and booted them with the "old Johann ROM
# magic cookie" method -- RDB at block 8 plus a patched boot block. This tree
# writes the modern chain only, so on such a machine every gate below will pass
# and the disk still will not boot. Stock's own probes, stock's own test; and it
# FAILS OPEN on anything it does not recognise (see setup.sh for the full note).
OLDB_ROM=
OLDB_CTL=
OLDB=
if [ -x /etc/romsize ]; then
	OLDB_ROM=`/etc/romsize 2>/dev/null`
fi
if [ -x /etc/dioc ]; then
	# The FIRST TOKEN of dioc's line, taken with the driver's own `read` idiom
	# (the same one the ddsize probe uses) and NOT with `set --`: this is the
	# script's top level, where `set --` would overwrite the driver's own
	# positional parameters. `read` also handles the two failure shapes measured
	# on the bench for free -- an absent disk prints nothing (empty token) and a
	# bad command prints a diagnostic whose first token is not a controller name.
	/etc/dioc 1 < "$DISK_RAW" > /tmp/dioc.$$ 2>/dev/null
	OLDB_CTL=`( read w rest; echo "$w" ) < /tmp/dioc.$$ 2>/dev/null`
	rm -f /tmp/dioc.$$
fi
case "$OLDB_ROM" in
	"")		: ;;
	*[!0-9]*)	: ;;
	*)		if [ "$OLDB_ROM" -lt 524288 ]; then OLDB=rom; fi ;;
esac
if [ "$OLDB_CTL" = A2090 ]; then OLDB=controller; fi
msg "machine class: ROM=${OLDB_ROM:-unknown} controller=${OLDB_CTL:-unknown}"
if [ -n "$OLDB" ]; then
	warn "this machine is the OLD_BOOT class (${OLDB}: Kickstart 1.3 or an A2090)."
	warn "It needs the old 2620/2630 ROM boot method, which this installer does"
	warn "not write.  The install below will SUCCEED and the disk will NOT BOOT."
	warn "Use the original Amiga UNIX 2.1 distribution media for this machine."
fi

# ===========================================================================
# 2. BUILD THE TARGET ROOT (author on-box, or reuse a mkroot-prebuilt disk)
# ===========================================================================
build_target_author() {
	# The stock installer's exact RDB sequence (grimoire anatomy-root-adf):
	#   /etc/rdb -a $DISK <name> <offset_blocks> <len_blocks>   (root, swap, boot IN ORDER)
	#   /etc/rdb -p $BOOTPART -M -B -C 2 -P 2 -F 0x554e4900 $DISK   # UNI\0 bootable
	#   /etc/rdb -p $ROOTPART -m            -F 0x554e4901 $DISK      # UNI\1 root
	#   /etc/rdb -p $SWAPPART -m            -F 0x72657376 $DISK      # resv swap
	# The list ORDER root->swap->boot is the slice map (sdpart.c: slice N = Nth
	# PART block). Swap at slice 2 is STRUCTURAL -- it is what places boot at
	# slice 3. (Until W5.5 nothing ever opened it either; section 2c now hands it
	# to the kernel as real swap for the duration of the install, which is what
	# the stock installer did. See mkroot.sh's header.)
	#
	# NOTE (W5.4b): the end-to-end install was validated via the RECOMMENDED
	# INSTALL_TARGET_PREBUILT=1 path (a mkroot-prebuilt target), which skips this
	# whole block -- so author mode's create/geometry primitive below was the one
	# on-box unknown never exercised.
	#
	# ★ ANSWERED 2026-07-30 and FIXED 2026-07-31 (tools/install-matrix.sh cell
	# `cd-author`). The cell's first run STOPped on the create line with
	#     rdb: -c requires -d disksize
	# and re-reading the miniroot's OWN rdb settled the rest. Three lines below
	# were wrong as shipped; all three are corrected here and the corrections are
	# the STOCK INSTALLER's, verbatim -- /etc/rdb on the NG miniroot is
	# byte-identical (md5 6cacf95f738abea7cfddc6bb9ebf28e7) to the one on the
	# stock root floppy, whose /etc/profile IS the stock install script:
	#   1. `-c` needs `-d <disklen>` (and the stock also passes `-L 2`);
	#   2. `-p` takes a PARTITION NUMBER, not a device path -- rdb's own
	#      "rdb: partitions are numbered from 1", and the stock's ROOTPART/
	#      SWAPPART/BOOTPART are the numbers it also uses as the sN slice suffix;
	#   3. mkfs_s5's size operand is in 512-byte blocks, not 1 KB logical blocks.
	# docs/installer.md "What the author cell found" carries the evidence.
	# ★ NON-BLANK TARGET GUARD. Everything below /etc/rdb -c (wipe the RDB) + mkfs
	# DESTROYS whatever is on $DISK_RAW. Refuse to do that to a disk that already
	# carries ANY RDB -- an Amix root, an AmigaOS-partitioned disk, any partition
	# table -- not merely a slice literally named UNIX_Root (a disk full of AmigaOS
	# partitions was otherwise re-authored silently: overnight review 2026-09-16).
	# Fail CLOSED, mirroring setup.sh rdb_present: RDSK is the RDB magic at block 0
	# (a whole-sector raw read cut to 4 bytes -- a bare bs=4 raw read is EIO on the
	# emulated piscsi); /etc/rdb is the fallback for an RDB not at byte 0. A FRESH
	# ZEROED target has neither, so this guard is transparent to every first install
	# (the blank fall-through is logged, so an unattended wipe is never fully silent).
	# It exists because
	# the unattended driver otherwise re-authors + re-mkfs an already-installed target
	# silently (metal-confirmed: a bare Preset-A re-power wiped a completed install).
	# ★ GATED ON INSTALL_UNATTENDED=yes: ONLY the unattended path -- a re-power with no
	# operator present -- is at risk. An INTERACTIVE install has setup.sh choose_disk's
	# own erase confirmation (setup.sh:700-711), and AUTHOR mode (every cd-* author
	# matrix cell + the metal author path) deliberately (re)authors a target that
	# tools/mkroot.sh has ALREADY stamped UNIX_Root -- so without this gate the guard
	# refuses author mode on its own minted disk (MAJOR, overnight review 2026-09-16).
	# TARGET_ERASE_OK=yes overrides it even on the unattended path -- the demo card
	# sets that (its Preset A IS the deliberate "reinstall over this disk" action);
	# every other unattended profile leaves it unset and is protected. Uses only
	# miniroot builtins (rdb/read/[/die).
	# An upgrade install (INSTALL_UPGRADE=yes, 1.1) IS the deliberate reinstall over an
	# installed disk: it saves what survives first (l11_upgrade_capture), so the guard
	# below does not apply to it.
	if [ "${INSTALL_UNATTENDED:-no}" = yes ] && [ "${TARGET_ERASE_OK:-no}" != yes ] && [ "${INSTALL_UPGRADE:-no}" != yes ]; then
		_tgt_rdb=no
		case "`dd if="$DISK_RAW" bs=512 count=1 2>/dev/null | dd bs=4 count=1 2>/dev/null`" in
			RDSK*)	_tgt_rdb=yes ;;
		esac
		if [ "$_tgt_rdb" = no ] && /etc/rdb "$DISK_RAW" > /dev/null 2>&1; then
			_tgt_rdb=yes
		fi
		if [ "$_tgt_rdb" = yes ]; then
			# name slice 1 for the operator when /etc/rdb can print it (best effort)
			/etc/rdb -p 1 "$DISK_RAW" > /tmp/tgtchk.$$ 2>/dev/null
			_existing_root=`( read _pn _prest; echo "$_pn" ) < /tmp/tgtchk.$$ 2>/dev/null`
			rm -f /tmp/tgtchk.$$
			die "target c${ID}d0 already carries an RDB (a partition table${_existing_root:+, slice 1 = $_existing_root}) -- REFUSING to erase and reinstall over it. Insert a BLANK (zeroed) target, or set TARGET_ERASE_OK=yes to reinstall over an existing disk."
		fi
		# Proceeded on the unattended path: the target read as blank (no RDSK magic,
		# no parseable RDB). Log it so an unattended wipe is never fully silent.
		msg "non-blank guard: target c${ID}d0 read as BLANK (no RDB) -- authoring."
	fi
	warn "author mode: writing the RDB slice map with /etc/rdb on $DISK_RAW."
	warn "  If author mode fails on this miniroot, prefer"
	warn "  INSTALL_TARGET_PREBUILT=1 with a tools/mkroot.sh target (see docs)."
	# Create a blank RDB. Stock line, verbatim (its $DISKLEN comes from
	# `/etc/ddsize $rDISK` and is the disk length in 512-BYTE BLOCKS -- the same
	# unit, and for the profile's disk the same number, that plan_partitions
	# computes DISKLEN in):
	#     /etc/rdb -c -s 64 -L 2 -d $DISKLEN $DISK
	# -s = sectors per track (blocks per cylinder, our $SECS=64).
	# -L = the RDSK block. OURS IS $TARGET_RDB_BLOCK (default 0, see its key note):
	# stock firmware finds an RDB only at byte 0. `rdb -c` rewrites an EXISTING RDB
	# at the block it finds it in (its 0..15 scan overrides -L), so clear blocks
	# 0..15 first -- past the erase guard, on a disk about to be re-authored, and
	# below the first partition (OFFSET=128 blocks) -- or a reinstall over an old
	# RDSK-at-2 disk would silently keep block 2.
	# 1.1: a disk that already carries two UNI\0 partitions is refused, whatever the
	# erase gate said -- which of them booted is not ours to guess (spec 40 §5, gate 9)
	# -- and the whole RDB area below the first slice is cleared, so no PART block of
	# the old layout survives to be counted by the one-store check after authoring.
	RDB_CLEAR=16
	if [ "$INSTALL_LAYOUT" = 1.1 ]; then
		_u0=`l11_uni0_count "$DISK_RAW"`
		[ "$_u0" -le 1 ] || die "target c${ID}d0 already carries $_u0 UNI\\0 (boot) partitions -- REFUSING it: a 1.1 disk has exactly one boot store. Clear the disk first."
		RDB_CLEAR="$OFFSET_BLOCKS"
		[ "${INSTALL_UPGRADE:-no}" = yes ] && l11_upgrade_capture
	fi
	# an upgrade of a 1.1 disk keeps its layout: s1 is re-made, s4 kept, s3 re-written
	if [ "${UPGRADE_KIND:-}" = 1.1 ]; then
		l11_keep_layout
	else
	run dd if=/dev/zero of="$DISK_RAW" bs=512 count="$RDB_CLEAR"
	run /etc/rdb -c -s "$SECS" -L "$TARGET_RDB_BLOCK" -d "$DISKLEN" "$DISK_RAW"
	# add the three slices IN ORDER (root, swap, boot)
	run /etc/rdb -a "$DISK_RAW" UNIX_Root "$ROOT_OFF" "$ROOTLEN"
	run /etc/rdb -a "$DISK_RAW" UNIX_Swap "$SWAP_OFF" "$SWAPLEN"
	run /etc/rdb -a "$DISK_RAW" UNIX_Boot "$BOOT_OFF" "$BOOTLEN"
	# Stamp the SVR4/Amix type tags + boot flags. `-p` selects the partition BY
	# NUMBER (1-based, in PART-block order) -- and because the adds above are in
	# slice order, partition N is slice N, which is exactly the identity the
	# stock script relies on when it uses $ROOTPART both as `-p` argument and as
	# the sN suffix of $UPART. So the profile's slice numbers ARE the -p numbers.
	run /etc/rdb -p "$TARGET_BOOT_SLICE" -M -B -C 2 -P 2 -F 0x554e4900 "$DISK_RAW"
	run /etc/rdb -p "$TARGET_ROOT_SLICE" -m -F 0x554e4901 "$DISK_RAW"
	run /etc/rdb -p "$TARGET_SWAP_SLICE" -m -F 0x72657376 "$DISK_RAW"
	if [ "$INSTALL_LAYOUT" = 1.1 ]; then
		if [ "$DATALEN" -gt 0 ]; then
			run /etc/rdb -a "$DISK_RAW" UNIX_Data "$DATA_OFF" "$DATALEN"
			run /etc/rdb -p 4 -m -F 0x554e4901 "$DISK_RAW"
		fi
		l11_check_layout
	fi
	fi	# UPGRADE_KIND 1.1: the layout was kept
	# RDSK READ-BACK, fail closed: with TARGET_RDB_BLOCK=0 the magic must be at
	# byte 0 -- the only place stock Z3660 firmware looks. A disk that only the
	# fork firmware can boot must never leave this path looking finished.
	# A RAW disk device transfers whole sectors: a bare `dd bs=4` on $DISK_RAW is
	# EIO on the emulated Z3660 piscsi (K1-CM bench, 2026-09-29: "read error: I/O
	# error", so this gate died on a disk that DID carry RDSK at 0). Read the whole
	# sector and cut the 4 magic bytes off a pipe -- same answer on metal and bench.
	if [ "$TARGET_RDB_BLOCK" = 0 ]; then
		case "`dd if="$DISK_RAW" bs=512 count=1 2>/dev/null | dd bs=4 count=1 2>/dev/null`" in
			RDSK*)	msg "RDB read-back: RDSK at block 0 on $DISK_RAW (stock-firmware bootable)" ;;
			*)	die "RDB read-back: no RDSK at block 0 of $DISK_RAW after /etc/rdb -c -L 0 -- stock Z3660 firmware would not find this RDB" ;;
		esac
	fi

	# REAL SWAP BEFORE mkfs (1.1, 2026-10-10). Until 2c the only swap is /dev/fakeswap
	# (dummydisk), and mkfs_ufs of a large root pages: on 16 MB (the published A4000/030
	# config) a 478 or 967 MB root panicked "swapinub: segu_fault() failed to swap in the u
	# area". The slice exists now that the RDB is written, so hand it over here. No temp
	# files (nothing is mounted yet): stock's own `set \`swap -l\`` form; the `x` keeps an
	# empty output from turning `set` into a variable dump. 2c then finds the fake gone and
	# only logs the table. Fail-open like 2c.
	early_target_swap() {
		[ "${SWAP_HOLD:-}" = y ] && return 0	# an upgrade keeps its archive in s2 (l11.sh)
		set x `/bin/swap -l 2>/dev/null`; shift
		[ "$6" = /dev/fakeswap ] || return 0
		set x `/etc/rdb -p "$TARGET_SWAP_SLICE" "$DISK_RAW" 2>/dev/null`; shift
		eblks="$3"
		is_num "$eblks" || eblks="$SWAPLEN"
		if runq /bin/swap -a "/dev/dsk/c${ID}d0s${TARGET_SWAP_SLICE}" 0 "$eblks"; then
			msg "swap: added /dev/dsk/c${ID}d0s${TARGET_SWAP_SLICE} 0 $eblks before mkfs"
			EARLY_SWAP_ADDED="/dev/dsk/c${ID}d0s${TARGET_SWAP_SLICE} 0 $eblks"
			if runq /bin/swap -d /dev/fakeswap 0; then EARLY_SWAP_REMOVED=y
			else warn "swap: could not remove /dev/fakeswap before mkfs"; fi
		else
			warn "swap: could not add the swap slice before mkfs; mkfs runs on /dev/fakeswap"
		fi
		return 0
	}
	early_target_swap

	# The filesystem on the root slice. BOTH mkfs back-ends take their size
	# operand in 512-byte blocks -- SVR4 mkfs(1M), and the stock script passes
	# its $ROOTLEN (which is `MB * 2048`, i.e. 512-blocks) straight through to
	# `mkfs_${ROOT_FSYS}`. mkfs converts to logical blocks itself: mkfs_s5 prints
	# "total logical blocks" = ROOTLEN/2 at its 1 KB default, the same count
	# tools/mkroot.sh mints host-side. Passing the 1 KB count here (what this
	# line used to do) would have built a filesystem over only HALF the slice.
	#
	# STOCK STAGE STRING (verbatim, /etc/profile on the stock root floppy): the
	# original printed this immediately before its own mkfs_${ROOT_FSYS} run.
	stage ""
	stage "Making filesystems.  This will take a few minutes."
	# ★ NO `mkfs_${TARGET_ROOT_FSTYPE}` INTERPOLATION, deliberately. Two literal
	# arms cost three lines and keep every command's first word a LITERAL PATH,
	# which is what installer-selftest audit G (the miniroot-tool allowlist,
	# derived from miniroot.proto) can actually resolve. A composed program name
	# is a name no audit can check, on a filesystem with no `sed` to check it
	# with. Both binaries are already on the medium: /bin/mkfs_ufs (19,664 B) and
	# /bin/fsck_ufs (45,548 B) have been stock-miniroot proto members since W5.2,
	# byte-identical to the ones on the stock root floppy, and their only
	# DT_NEEDED is the miniroot's own /usr/lib/libc.so.1.
	if [ "$TARGET_ROOT_FSTYPE" = ufs ]; then
		# STOCK'S UFS RECIPE, verbatim (stock /etc/profile:
		#     UFS_OPT="-o free=2,opt=s"
		#     mkfs_${ROOT_FSYS} $ROOT_OPT $UPART $ROOTLEN
		# with $UPART = /dev/dsk/cXd0sN, i.e. the BLOCK node -- NOT the raw node
		# our s5 arm passes). Three deliberate fidelities to that line:
		#   1. the BLOCK node. mkfs_ufs carries its own "%s is not special
		#      device, can't mkfs" check and we have never run this binary; the
		#      node stock fed it is the one with 34 years of evidence behind it.
		#      It also keeps mkfs and the mount that follows on the SAME node, so
		#      no write goes through the raw path and no read through the cached
		#      one.
		#   2. `-o free=2,opt=s` and nothing else -- NO geometry operands. The
		#      superblock on amix-images' 1991-installed golden reads back
		#      fs_minfree=2 and fs_optim=FS_OPTSPACE, which IS this option pair's
		#      fingerprint, with mkfs_ufs's own default geometry beside it.
		#   3. the same $ROOTLEN in 512-blocks the s5 arm passes, which that same
		#      golden confirms: its fs_size x fs_fsize equals its slice size to
		#      the byte.
		# NO labelit on this path. The miniroot carries only the s5 back-end
		# (/usr/lib/fs/s5/labelit, a core-2.1.pkg proto member); there is no
		# /usr/lib/fs/ufs/labelit on the medium -- and STOCK RAN labelit ON
		# NEITHER FILESYSTEM. The s5 call below is our own addition, so dropping
		# it here removes nothing stock did and costs the floppy nothing (adding
		# the ufs back-end would have eaten 5,400 of its 46 free KB for a step
		# its author considered unnecessary).
		run /bin/mkfs_ufs -o free=2,opt=s "$ROOT_BLK" "$ROOTLEN"
	else
		run /bin/mkfs_s5 "$ROOT_RAW" "$ROOTLEN"
		# label the root fs (miniroot has only the s5 back-end labelit)
		run /usr/lib/fs/s5/labelit "$ROOT_RAW" root ROOT
	fi
	[ "$INSTALL_LAYOUT" = 1.1 ] && l11_mkfs_data
	return 0
}

build_target_prebuilt() {
	# ★ PREBUILT IS AN s5-ONLY MODE, and it fails closed rather than quietly.
	# tools/mkroot.sh mints the root filesystem host-side with tools/lib/s5.py --
	# an s5 minter, the only filesystem writer this project owns host-side. If a
	# profile or an interview answer asked for ufs and we simply carried on, the
	# mount below would either refuse the filesystem or, far worse, succeed
	# against the s5 image mkroot left there and produce a box whose vfstab says
	# ufs about an s5 root. Neither is a diagnosis anybody wants at cold boot.
	[ "$TARGET_ROOT_FSTYPE" = s5 ] || die "TARGET_ROOT_FSTYPE=$TARGET_ROOT_FSTYPE, but INSTALL_TARGET_PREBUILT=1 and tools/mkroot.sh mints an s5 root host-side.
	A $TARGET_ROOT_FSTYPE root can only be AUTHORED on the box, where its mkfs binary is: re-run without INSTALL_TARGET_PREBUILT."
	msg "prebuilt mode: target RDB + s5 root assumed already authored by mkroot.sh."
	[ -b "$ROOT_BLK" ] || warn "root block device $ROOT_BLK not present -- is the target attached at id ${ID}?"
}

if [ "${INSTALL_TARGET_PREBUILT:-0}" = 1 ]; then
	TARGET_BUILD_MODE="prebuilt host-side by mkroot.sh"
	build_target_prebuilt
else
	TARGET_BUILD_MODE="authored on-box"
	build_target_author
fi

# fsck the root s5 (the stock fs is marked dirty after mkfs; a pre-mount fsck is
# required before a rw mount is allowed) then mount at /mnt via direct mount(2).
# STOCK STAGE STRING (verbatim): the original printed this before its own
# pre-mount partition check.
stage ""
stage "Please wait while the partitions are checked..."
# ★ THE PRE-MOUNT fsck IS OURS, AND IT IS s5-ONLY ON PURPOSE.
# Stock ran `fsck_${ROOT_FSYS}` in exactly ONE place -- repairdisk() -- and never
# between its mkfs and its mount, on EITHER filesystem. Our s5 arm keeps the
# check because that is the sequence every attested s5 digest was produced by and
# nothing here is worth re-litigating; the ufs arm follows stock instead, for a
# reason beyond fidelity: mkfs_ufs above writes through the BLOCK node, so a
# `fsck_ufs $ROOT_RAW` here would read the raw path for bytes that are still in
# the buffer cache -- reading a filesystem through a node the writer never used
# is how you manufacture the corruption you were checking for. (Stock's own
# repairdisk passes the BLOCK node to fsck for the same reason.) The
# post-unmount fsck at the end of this script checks the ufs root for real, on a
# synced and unmounted filesystem, where the raw node is the correct one.
if [ "$TARGET_ROOT_FSTYPE" = ufs ]; then
	msg "ufs target: no pre-mount fsck (stock ran none between mkfs and mount, on either fs); the post-unmount fsck at the end checks it"
else
	run /bin/fsck_s5 "$ROOT_RAW"
fi
# /etc/mount is the miniroot's direct-mount(2) tool. Its usage as printed on the box
# is `mount spec dir [nflag [fstyp [data]]]`: nflag=0 => rw, fstyp=s5|ufs. The bare
# 2-arg form omits nflag+fstyp and mount(2) rejects it (EINVAL "Invalid argument");
# W5.4c proved `... /mnt 0 s5` mounts the prebuilt root rw and leaves it fsck-clean.
# The type is passed STRAIGHT THROUGH to mount(2): /etc/mount is a thin wrapper with
# no type table of its own, and the install kernel carries `ufs` at vfssw[2] with
# `ufsinit` linked, so `... 0 ufs` needs no kernel change (kerntools' UFS capability
# paper §4, all ten kernels examined).
run /etc/mount "$ROOT_BLK" "$TARGET" 0 "$TARGET_ROOT_FSTYPE"
# --- target-root mount note (W5.4d; mnttab written at seed, METAL-FIX.2) ------
# The miniroot's /etc/mount is a direct mount(2) and writes NO /etc/mnttab entry.
# pkgadd/apkg read the RUNNING miniroot's /etc/mnttab via get_mntinfo(), keying off
# the SHORTEST mount point being exactly "/". The engine tolerates a missing entry:
# get_mntinfo SYNTHESIZEs the "/" root when the table lacks the line (amix-package-
# manager 0d3a21c), and METAL-FIX.1 (pkgmgr 3b9b7a1) extended that to a wholly
# ABSENT file (ENOENT -> synthesize).
#
# BUT the engine tolerance alone is NOT enough on fresh media. A freshly built
# miniroot ships NO /etc/mnttab at all, and M-RUN froze exactly here:
#     pkgadd: ERROR: unable to open mount table (/etc/mnttab)
# The open() fails before get_mntinfo's synthesize path is reached, so the base-OS
# transplant never starts. This was MASKED for two waves because the REUSED bench
# floppy carried a stale/contaminated /etc/mnttab whose mere presence let open()
# succeed (acceptance runs must use FRESH media -- see docs/installer.md). So the
# seed step (section 4) now WRITES the root line UNCONDITIONALLY, naming the
# RUNNING MINIROOT's own fs ($MINIROOT_FSTYPE: s5 on the 030 line, ufs on 040/060):
#     echo "/dev/root / $MINIROOT_FSTYPE rw 0" > /etc/mnttab
# belt-and-suspenders with the engine tolerance -- and the OVERWRITE (`>`, not `>>`)
# also replaces any stale/contaminated table rather than appending to it. A "/mnt"
# line does NOT satisfy get_mntinfo (that mount point is not "/") and must never be
# used. Metal citation: METAL-FIX.2 (M-RUN2, 2026-07-23).
# -----------------------------------------------------------------------------
msg "target root mounted at $TARGET"

# --- OPEN THE INSTALL LOG (W1) ----------------------------------------------
# From here on every message and every child command's output is persisted to
# <target>/var/adm/install.log, which SURVIVES the install (it is on the target
# root, not the miniroot's RAM disk). It is a NEW, driver-written file -- never a
# package member -- so it is invisible to the contents DB and cannot perturb
# altroot-attest/pkgchk (the same additive class as S16firstboot / updbootpart /
# S99zen; the property holds because attestation is contents-DB-derived, and it
# holds for DB-INVISIBLE paths only -- do not generalize it).
#
# Both directories are made HERE and not in the seed: the log needs var/adm
# before the first append, and $RUNOUT (the child-output scratch runq cats twice)
# needs tmp. The miniroot's 1991 `mkdir -p` is NOT idempotent on an existing LEAF
# (it prints "File exists" and returns 2 -- W5.4f), so each is guarded; the seed
# in section 4 therefore no longer creates $TARGET/tmp itself.
[ -d "$TARGET/var/adm" ] || run mkdir -p "$TARGET/var/adm"
[ -d "$TARGET/tmp" ] || run mkdir -p "$TARGET/tmp"
RUNOUT="$TARGET/tmp/.runout.$$"
LOGFILE="$TARGET/var/adm/install.log"
: > "$LOGFILE" || die "cannot create the install log $LOGFILE"
chmod 644 "$LOGFILE"
logline "=============================================================="
logline "$PROG install log -- profile $PROFILE_NAME ($PROFILE_FILE)"
logline "NOTE: the PRE-MOUNT window (banner, profile echo, disk probe, RDB"
logline "      authoring, mkfs, the pre-mount fsck) is CONSOLE-ONLY -- there was"
logline "      no target filesystem to write to yet. This log opens at the mount"
logline "      of $ROOT_BLK on $TARGET and is complete from here on."
if [ -n "$VERBOSE" ]; then
	VERBOSE_DESC="verbose -- the console mirrors this log"
else
	VERBOSE_DESC="quiet -- the console shows stage messages only"
fi
logline "mode: INSTALL_VERBOSE=$INSTALL_VERBOSE ($VERBOSE_DESC)"
logline "=============================================================="
msg "install log  : $LOGFILE (complete from this point; pre-mount window was console-only)"

# ===========================================================================
# 2c. REAL SWAP -- hand the target's swap slice to the kernel (STOCK PARITY)
# ===========================================================================
# ★ W5.5. THE INSTALL MINIROOT'S ONLY SWAP IS A BIT BUCKET, and that is what
# panicked the 17-package `standard` install at package 12/17:
#
#     PANIC: swapinub: segu_fault() failed to swap in the u area
#
# MEASURED on the bench miniroot (run w55-m1, 2026-08-12), `swap -l` before any
# install work:
#
#     path                 dev  swaplo blocks   free
#     /dev/fakeswap       19,0       0  20476  20188
#
# One swap area, ~10 MB of it, on block major **19** -- and block major 19 is
# `dummydisk` (grimoire docs/reference/major-number-registry.md §3). The install
# kernel's `swapfile` bootobj names "/dev/fakeswap" precisely because a floppy
# miniroot has no disk to swap to; the kernel therefore SWAPS OUT into a device
# that stores nothing. Note the 288 blocks already "in use" above: pages had
# been written to it before the installer even started. Nothing goes wrong until
# the system needs one of those pages BACK -- then segu_fault() cannot produce
# the u area and the kernel panics. That is why the failure looked flaky (W3b
# passed once, W4 panicked once then passed) and then became reproducible as the
# workload grew: whether a swapped-out u area is ever wanted again is a
# scheduling accident, and 17 packages make it near-certain.
#
# THE FIX IS THE ORIGINAL INSTALLER'S OWN, verbatim in shape. The stock install
# script (/etc/profile on floppies/orig/amix_21_root.adf, "Add the user declared
# swap partition as swap space") did exactly this, and for exactly this reason:
#
#     set `swap -l`
#     if [ "$6" = "/dev/fakeswap" ]
#     then
#         swap -a $SPART 0 $SWAPLEN
#         swap -d /dev/fakeswap 0
#     fi
#
# The target's swap slice exists by now (it is authored with the RDB, or already
# present on a prebuilt target) and NOTHING else opens it during an install, so
# it is free real estate -- 18 MB of it on the bench 100 MB layout. We add it,
# then DELETE the fake, so no page can ever be written to the bit bucket again.
#
# DELIBERATE DEVIATION from stock's position in the flow: stock ran this in its
# pre-mount window, we run it immediately after the install log opens, so the
# whole transaction (the `swap -l` before, the add, the `swap -l` after) is IN
# THE LOG rather than console-only. Everything memory-hungry -- the seed, the
# pkgadd loop, contents-fsck -- is still far downstream.
#
# FAIL-OPEN, DELIBERATELY. Swap is a resource, not a contract: every install
# this project has ever completed ran without it, so a driver that STOPPED here
# would turn "no swap" into a total failure for the minimal tier that does not
# need it. A failure is loud (WARNING, console + log, naming the panic it
# invites) and the matrix's swap assertion turns it into a red cell.
#
# MINIROOT-CLEAN: /bin/swap and /etc/rdb are both miniroot.proto members. The
# two parse loops are the house `while read ... done < FILE` idiom, which runs
# in a SUBSHELL on the 1991 sh -- so they only ever APPEND to a token file and
# the parent decides (W5.4e).
SWAP_BLK="/dev/dsk/c${ID}d0s${TARGET_SWAP_SLICE}"
SWAPOUT="$TARGET/tmp/.swapl.$$"
SWAPTOK="$TARGET/tmp/.swaptk.$$"
add_target_swap() {
	if [ "${SWAP_HOLD:-}" = y ]; then
		msg "swap: held -- the upgrade's saved configuration is in $SWAP_BLK until it is restored"
		return 0
	fi
	rm -f "$SWAPOUT" "$SWAPTOK"
	# --- is the fake still the swap? (stock's own `$6 = /dev/fakeswap` guard) ---
	/bin/swap -l > "$SWAPOUT" 2>&1
	logline "+ /bin/swap -l  (before)"
	cat "$SWAPOUT" >> "$LOGFILE"
	while read sdev srest; do
		case "$sdev" in
			/dev/fakeswap) echo y > "$SWAPTOK" ;;
		esac
	done < "$SWAPOUT"
	if [ ! -f "$SWAPTOK" ]; then
		rm -f "$SWAPOUT" "$SWAPTOK"
		# the console-only pre-mount window already did it (early_target_swap): say so here, in the log
		if [ -n "${EARLY_SWAP_ADDED:-}" ]; then
			logline "$PROG: swap: added $EARLY_SWAP_ADDED (real disk swap replaces the dummydisk fake; done before mkfs)"
			[ -n "${EARLY_SWAP_REMOVED:-}" ] && logline "$PROG: swap: removed /dev/fakeswap (bdevsw major 19 = dummydisk; done before mkfs)"
			return 0
		fi
		msg "swap: /dev/fakeswap is not in the swap table -- swap configuration left alone"
		return 0
	fi
	rm -f "$SWAPTOK"
	# --- the REAL slice length, out of the RDB (stock read it the same way) ----
	# `/etc/rdb -p N <disk>` prints one line: `<name> <offset> <length>` in
	# 512-byte blocks (measured: `UNIX_Swap 161920 36864`). The planned $SWAPLEN
	# is the fallback, not the source of truth -- a prebuilt target's RDB is what
	# the kernel will actually be writing into.
	/etc/rdb -p "$TARGET_SWAP_SLICE" "$DISK_RAW" > "$SWAPOUT" 2>/dev/null
	while read pname poff plen prest; do
		[ -n "$plen" ] || continue
		[ -f "$SWAPTOK" ] || echo "$plen" > "$SWAPTOK"
	done < "$SWAPOUT"
	SWAPBLKS=""
	if [ -s "$SWAPTOK" ]; then
		SWAPBLKS=`cat "$SWAPTOK"`
	fi
	rm -f "$SWAPOUT" "$SWAPTOK"
	if is_num "$SWAPBLKS"; then
		:
	else
		warn "swap: /etc/rdb -p $TARGET_SWAP_SLICE $DISK_RAW named no slice length -- falling back to the planned $SWAPLEN blocks"
		SWAPBLKS="$SWAPLEN"
	fi
	# --- add the real slice, then delete the fake -----------------------------
	if runq /bin/swap -a "$SWAP_BLK" 0 "$SWAPBLKS"; then
		msg "swap: added $SWAP_BLK 0 $SWAPBLKS (real disk swap replaces the dummydisk fake)"
		if runq /bin/swap -d /dev/fakeswap 0; then
			msg "swap: removed /dev/fakeswap (bdevsw major 19 = dummydisk -- pages written there are DISCARDED)"
		else
			warn "swap: could not remove /dev/fakeswap -- it stays in the table beside the real slice"
		fi
	else
		warn "swap: could NOT add $SWAP_BLK as swap; the install continues on /dev/fakeswap alone."
		warn "  /dev/fakeswap is bdevsw major 19 (dummydisk): what is swapped out there is thrown"
		warn "  away, so a large package set may die with"
		warn "  'PANIC: swapinub: segu_fault() failed to swap in the u area'."
	fi
	/bin/swap -l > "$SWAPOUT" 2>&1
	logline "+ /bin/swap -l  (after)"
	cat "$SWAPOUT" >> "$LOGFILE"
	rm -f "$SWAPOUT"
	return 0
}
add_target_swap

# ===========================================================================
# 3. MOUNT / VERIFY THE INSTALL SOURCE
# ===========================================================================
# In BOTH source kinds the driver runs FROM /cdrom (it was launched as
# `sh /cdrom/install/bin/install.sh`), so the source is ALREADY mounted there by
# the time this runs -- section 3 is the safety net + the go/no-go gate.
#
#   cdfs -- /cdrom is the install CD (cdfs). Re-mount defensively (errno-5
#           media-change + stale-empty-mount recovery) and gate on the CD's
#           top-level catalog.
#   raw  -- /cdrom is the PAYLOAD s5 slice of the source disk. The operator
#           mounts it BEFORE launching the driver:
#               /etc/mount /dev/dsk/c<SRC>d0s<A> /cdrom 0 s5
#           A running driver cannot re-mount the busy filesystem it is executing
#           from, so there is nothing to (re)mount here -- just gate on the
#           payload being present. The base packages do NOT come from /cdrom in
#           this kind (no /cdrom/pkgs, no /cdrom/catalog); they come from the raw
#           distribution slice via apkg (section 5). What must be on /cdrom is the
#           /install payload tree -- the static engine, apkg, order, boot images.
if [ "$SOURCE_KIND" = cdfs ]; then
	# The driver runs FROM the CD, so /cdrom is normally already mounted. This is
	# a safety net that also documents the errno-5 media-change quirk: the FIRST
	# mount after a media change returns errno 5 (unit attention); mount again ->
	# succeeds.
	if [ ! -f "$CDROOT/catalog" ]; then
		msg "mounting install CD: /usr/lib/fs/cdfs/mount $CD_SPEC $CDROOT"
		/usr/lib/fs/cdfs/mount "$CD_SPEC" "$CDROOT" 2>/dev/null
		if [ ! -f "$CDROOT/catalog" ]; then
			msg "  first mount returned unit-attention (errno 5) -- retrying once"
			/usr/lib/fs/cdfs/mount "$CD_SPEC" "$CDROOT" 2>/dev/null
		fi
	fi
	# Stale-mount guard (W5.5a field observation): the boot-time cdfs /cdrom mount
	# can come up rc=0 but EMPTY -- something IS mounted, so $CDROOT/catalog is
	# unreadable yet there is no errno-5 unit-attention to retry on, and re-mounting
	# OVER a live mount is a no-op. The errno-5 net above cannot recover this.
	# Recover ONCE: unmount the stale mount (best-effort -- it may already be
	# half-gone) and mount a fresh one; the catalog gate below then makes the final
	# go/no-go decision.
	if [ ! -f "$CDROOT/catalog" ]; then
		warn "install CD mounted but $CDROOT/catalog unreadable (stale/empty mount) -- umount + remount once"
		/etc/umount "$CDROOT" 2>/dev/null || umount "$CDROOT" 2>/dev/null || warn "  stale $CDROOT umount returned nonzero (continuing to remount)"
		/usr/lib/fs/cdfs/mount "$CD_SPEC" "$CDROOT" 2>/dev/null
	fi
	[ -f "$CDROOT/catalog" ] || die "install CD not readable at $CDROOT (no catalog after errno-5 retry + stale-mount umount/remount) -- check the CD unit ($CD_SPEC) and media"
else
	# raw: the payload slice must be mounted at /cdrom already (the operator did
	# `/etc/mount $SRC_PAYLOAD_BLK $CDROOT 0 s5`). Fail closed with the exact
	# command if it is not -- the driver cannot mount what it runs from.
	[ -x "$INST/bin/apkg" ] || die "RAW source: no static apkg at $INST/bin/apkg -- is the payload slice mounted at $CDROOT? (mount it first: /etc/mount $SRC_PAYLOAD_BLK $CDROOT 0 s5)"
	msg "RAW source: payload slice present at $CDROOT (apkg $INST/bin/apkg); packages from $SRC_RAW_DEV"
fi
[ -x "$INST/bin/pkgadd" ] || die "no static pkgadd at $INST/bin/pkgadd -- is /install/ populated (payload slice mounted at $CDROOT)?"

# ===========================================================================
# 4. SEED THE TARGET ROOT (the proven pkgadd -R pre-conditions)
# ===========================================================================
# See ../amix-packagemanager tools/repo/{altroot-acceptance,core-first-gate}.sh
# and its notes. The seed makes ownership resolve through the TARGET's name
# service from the very first package (not the installing box's), and gives
# pkgadd a temp area with real headroom (on the freshly-mkfs'd target).
msg "seeding target root..."
# NB $TARGET/tmp is NOT in this list -- it (and $TARGET/var/adm) were created at
# the log-open step right after the mount, because the log and runq's scratch
# file need them before anything else runs. The 1991 mkdir -p would FAIL here on
# the already-existing leaf.
run mkdir -p "$TARGET/etc" "$TARGET/var/sadm/install/admin" "$TARGET/var/sadm/pkg" "$TARGET/stand"
# passwd + group byte-identical to core's -- the miniroot's own copies ARE core's
# (miniroot.proto sources them from core-2.1.pkg), so this seeds them exactly.
run cp /etc/passwd "$TARGET/etc/passwd"
run cp /etc/group  "$TARGET/etc/group"
# the 183-B stock admin(4) default the installed system should carry
run cp "$INST/admin/default" "$TARGET/var/sadm/install/admin/default"
run chmod 1777 "$TARGET/tmp"
# TMPDIR onto the target (pkgadd/main.c defaults to /var/tmp which the miniroot
# lacks). pre-POSIX: assign then export separately.
TMPDIR="$TARGET/tmp"; export TMPDIR
# The RUNNING miniroot ships NO /etc/mnttab (its /etc/mount is a direct mount(2)
# that records none), yet pkgadd/apkg open() /etc/mnttab before installing. On
# FRESH media that open() fails -- `unable to open mount table (/etc/mnttab)` --
# and the base-OS transplant never starts (M-RUN froze exactly here; METAL-FIX.2).
# Write the root mnttab line so pkgadd/apkg always find a table; get_mntinfo keys
# off the SHORTEST mount point being exactly "/". OVERWRITE (`>`, not `>>`) so any
# stale/contaminated table (e.g. a reused-media leftover) is REPLACED, not appended
# to. echo + redirection only -- miniroot-allowlist-clean (see docs/installer.md).
#
# ★ THE FS TYPE IN THIS LINE IS THE RUNNING MINIROOT's OWN, NEVER THE TARGET'S,
# AND MUST NEVER BE PARAMETERISED BY $TARGET_ROOT_FSTYPE. It describes the root
# this script is executing from: the s5 floppy on the 030 line, the UFS raw slice
# on the 040/060 line (s5 is structurally broken under 4 KiB pages). $MINIROOT_FSTYPE
# is derived from INSTALL_CPU at the top of this file (030 => s5, 040/060 => ufs)
# and is `s5` for every pre-INSTALL_CPU profile, so the 030 line is byte-identical.
# The target is mounted at /mnt, and a "/mnt" line does not satisfy get_mntinfo at
# all (that mount point is not "/"). Making this line say `$TARGET_ROOT_FSTYPE`
# would describe the miniroot as a filesystem it is not, to the one consumer that
# reads it (the target's fs and the miniroot's are independent -- a ufs TARGET can
# be authored from an s5 miniroot on the 030 line, and vice versa).
echo "/dev/root / $MINIROOT_FSTYPE rw 0" > /etc/mnttab
msg "wrote /etc/mnttab root line (/dev/root / $MINIROOT_FSTYPE rw 0) for pkgadd/apkg get_mntinfo"
msg "seed done (passwd/group/admin/pkg, /etc/mnttab, /tmp 1777, TMPDIR=$TMPDIR)"

# ===========================================================================
# 5. INSTALL THE BASE OS -- from the on-disc order file, by SOURCE_KIND
# ===========================================================================
# The order file is baked at build time from deps.conf (core first, deps before
# dependents); the driver does NOT resolve deps in the cdfs loop, and hands the
# same set to apkg (which resolves within the closed set) in the raw branch. Both
# branches install the SAME packages into $TARGET, set $npkgs for the summary and
# the "installed ZERO" guard, and FAIL CLOSED -- so the SAME contents DB (and thus
# the SAME canonical digest) results whether the medium is a cdfs CD or a raw slice.
#
# WHICH order file (W3b). Empty INSTALL_ORDER = the medium's own $INST/order, i.e.
# the pre-W3b behaviour byte for byte. A bare name resolves ON the medium; a value
# with a '/' is a path, which is how a CUSTOM selection arrives (setup.sh filters
# the medium's master order into /tmp -- the medium is read-only).
ORDER="$INST/order"
if [ -n "$INSTALL_ORDER" ]; then
	case "$INSTALL_ORDER" in
		*/*)	ORDER="$INSTALL_ORDER" ;;
		*)	ORDER="$INST/$INSTALL_ORDER" ;;
	esac
fi
[ -f "$ORDER" ] || die "no install order file at $ORDER (INSTALL_ORDER='$INSTALL_ORDER')"

# CORE-FIRST STAYS IN THE DRIVER. Gate 13 already refuses any non-core package
# into a bare root, package by package, inside the install loop -- that is the
# gate and W3b does not move it. But INSTALL_ORDER now lets a file the driver did
# not generate name the packages, so the FIRST package is checked up front too: a
# core-less or core-late order is a mis-authored selection, and finding that out
# after the first pkgadd has already refused is a worse diagnosis than finding it
# out here. Subshell-safe: the redirect-fed loop only APPENDS, the parent decides.
ORDERFIRST="$TARGET/tmp/.order1.$$"
rm -f "$ORDERFIRST"
while read pkg; do
	case "$pkg" in ""|\#*) continue;; esac
	[ -f "$ORDERFIRST" ] || echo "$pkg" > "$ORDERFIRST"
done < "$ORDER"
[ -f "$ORDERFIRST" ] || die "install order $ORDER names no packages -- refusing to install a bare disk"
ofirst=`cat "$ORDERFIRST"`
rm -f "$ORDERFIRST"
[ "$ofirst" = core ] || die "install order $ORDER starts with '$ofirst', not 'core' -- core is the base OS and establishes the target's name service (Gate 13); refusing"

# THE 1.1 BASE CARRIES m4 (2026-10-26). The 2.1c syslogd reads /etc/syslog.conf only
# through /usr/ccs/bin/m4, the m4 package's (Cdev ships the same file); without it the
# conf parses empty and syslogd files nothing, kernel lines included. build-install-iso.sh
# puts m4 in every 1.1 medium's order, so an order with neither is a custom selection
# that dropped it.
if [ "$INSTALL_LAYOUT" = 1.1 ]; then
	ORDCDEV="$TARGET/tmp/.ordcdev.$$"
	rm -f "$ORDCDEV"
	while read pkg; do
		case "$pkg" in m4|Cdev) [ -f "$ORDCDEV" ] || echo y > "$ORDCDEV" ;; esac
	done < "$ORDER"
	[ -f "$ORDCDEV" ] || die "install order $ORDER has neither m4 nor Cdev -- a 1.1 install needs /usr/ccs/bin/m4 (syslogd reads /etc/syslog.conf through m4); refusing"
	rm -f "$ORDCDEV"
fi

# WHICH SET, for the log. An explicit INSTALL_SET (the interview always writes
# one) wins; otherwise the ORDER FILE says so itself -- gen-install-order.py
# writes a `# set: <name> (N package(s))` header line, which every consumer
# already skips as a comment. So an unattended profile run over a medium
# mastered for `standard` logs `standard` without the profile knowing anything
# about sets. Subshell-safe: append-only inside, decide in the parent.
if [ -z "$INSTALL_SET" ]; then
	ORDSET="$TARGET/tmp/.ordset.$$"
	rm -f "$ORDSET"
	while read otag okey oval orest; do
		[ "$otag" = "#" ] || continue
		[ "$okey" = "set:" ] || continue
		[ -f "$ORDSET" ] || echo "$oval" > "$ORDSET"
	done < "$ORDER"
	if [ -s "$ORDSET" ]; then
		INSTALL_SET=`cat "$ORDSET"`
	fi
	rm -f "$ORDSET"
fi
[ -n "$INSTALL_SET" ] || INSTALL_SET=default

# ★ THE MEDIUM IS THE AUTHORITY ON ATTESTATION, NOT THE PROFILE. INSTALL_ATTESTED
# arrives from the answers profile, and on an INTERACTIVE install that is already
# the medium's own answer -- setup.sh reads $INST/sets and writes
# INSTALL_ATTESTED=$SET_ATT. An UNATTENDED install has no interview, so the value
# is whatever the canned profile says, and every tracked profile says `y` on the
# reasoning that "the matrix only drives attested sets". THAT REASONING WAS WRONG:
# a profile is a RIG, a set is a MEDIUM, and one rig profile serves several
# media. bench-a3000-a4091-big serves cd-developer and cd-x11 (attested) AND
# cd-full (not attested until it has a green run behind it), so the 2026-08-14
# cd-full run logged `install set: full ... (attested=y)` against a disc whose own
# /install/sets said `2 full order n`. Nothing was misinformed -- the unattended
# path simply never asked the medium.
#
# So ask it, and let it DOWNGRADE only. y->n is fail-safe: a set the disc does not
# vouch for must not be recorded as vouched-for. n->y is refused by construction --
# a profile that deliberately waives the gate keeps its waiver, and a medium can
# never talk a run INTO claiming an attestation. This is log-only either way: the
# key changes nothing the driver does (see the key's own comment above), and
# install.log is driver-written and invisible to the contents DB, so the canonical
# digest cannot move. Subshell-safe: the redirect-fed loop only APPENDS, the
# parent decides. A medium with no sets table (pre-W3b, or a raw slice) is left
# alone -- absence is UNKNOWN, not `n`.
if [ "$INSTALL_ATTESTED" = y ] && [ -f "$INST/sets" ]; then
	SETATT="$TARGET/tmp/.setatt.$$"
	rm -f "$SETATT"
	while read snum sname sord satt srest; do
		case "$snum" in ""|\#*) continue;; esac
		[ "$sname" = "$INSTALL_SET" ] || continue
		[ -f "$SETATT" ] || echo "$satt" > "$SETATT"
	done < "$INST/sets"
	if [ -s "$SETATT" ] && [ "`cat "$SETATT"`" = n ]; then
		INSTALL_ATTESTED=n
		msg "attestation: $INST/sets marks set '$INSTALL_SET' UNATTESTED; the profile said attested=y -- THE MEDIUM WINS"
	fi
	rm -f "$SETATT"
fi
msg "install set: $INSTALL_SET  order: $ORDER  (attested=$INSTALL_ATTESTED)"

# /etc/apkg.conf is written BEFORE the APKG package is added (r6, 2026-10-06). APKG 0.2.3's
# class action script (i.apkgconf, class e) then KEEPS it ("kept as it is"), and pkginstall
# 1.12.3 records the kept file's on-disk size/sum, so a fresh install's PLAIN `pkgchk APKG` is
# clean. Gated on APKG being in the order file: the package is not on the target yet. Section
# 5c re-checks the file after the install. echo + redirection only (allowlist-clean).
APKG_CONF="$TARGET/etc/apkg.conf"
write_apkg_conf() {
	{
		echo "# apkg configuration -- written by install.sh (W6.4b); points at the live repo"
		echo "repo=$FB_REPO_URL"
		echo "cachedir=/var/apkg/cache"
		echo "admin=/var/apkg/admin"
	} > "$APKG_CONF" || die "cannot write $APKG_CONF"
	run chmod 0644 "$APKG_CONF"
	msg "wrote $APKG_CONF (repo=$FB_REPO_URL)"
}
rm -f "$TARGET/tmp/.apkgord.$$"
while read _p _rest; do
	if [ "$_p" = APKG ]; then echo y > "$TARGET/tmp/.apkgord.$$"; fi
done < "$ORDER"
if [ -f "$TARGET/tmp/.apkgord.$$" ]; then
	rm -f "$TARGET/tmp/.apkgord.$$"
	write_apkg_conf
fi
if [ "$INSTALL_ATTESTED" = n ]; then
	# Plan §5.7: named sets WITH a reference digest are gated; an unattested
	# named set and every Custom selection run with the gate explicitly waived.
	# Saying so IN THE LOG is the whole mechanism -- a tree nobody can compare
	# to a reference must not be mistaken later for one that was compared.
	msg "unattested selection -- no reference installed-tree digest exists for this set; the digest gate is WAIVED for this install"
fi

if [ "$SOURCE_KIND" = cdfs ]; then
	# --- cdfs: pkgadd -R down the order file, one /cdrom/pkgs file per line ---
	#     pkgadd -R /mnt -n -a <admin> -d <pkgfile> <pkgname>
	# mirroring the proven altroot-acceptance.sh invocation (Wave-2, 4/4 rc=0,
	# canonical tree digest 86e1ceb144f1328bf441c5df38fc2798). apkg is NOT in this
	# loop -- it is the remote client, not part of the base-OS transplant.
	#
	# $INST/admin/pkgadd = the PERMISSIVE install-time admin passed to `pkgadd -a`
	# (non-interactive, all checks nocheck). Distinct from the 183-B stock default
	# seeded at <target>/var/sadm/install/admin/default, which is what the FINISHED
	# system carries. See docs/installer.md "the two admin files".
	ADMIN="$INST/admin/pkgadd"
	[ -f "$ADMIN" ] || die "no permissive pkgadd admin at $ADMIN"
	PKGADD="$INST/bin/pkgadd"

	# SUBSHELL-SAFE COUNTING (W5.4e). The miniroot's 1991 SVR4 /bin/sh runs a
	# `while read ... done < FILE` loop in a SUBSHELL, so a variable mutated inside
	# (npkgs) reverts to its pre-loop value at `done` -- W5.4d printed "installed 0
	# package(s)" while all 5 packages sat in <target>/var/sadm/pkg. WORSE: an
	# in-loop `die`/exit would kill only the subshell and let the PARENT sail on and
	# arm a half-installed disk. So the loop records to append-only temp FILES (which
	# DO survive the subshell), and EVERY go/no-go decision is made AFTER the loop,
	# in the parent, from those files. installer-selftest.py audit H enforces that no
	# `done < FILE` loop leaves a variable-assign-then-use-after-loop.
	pkgok="$TARGET/tmp/.pkgok.$$"        # one line per package installed rc=0
	pkgfail="$TARGET/tmp/.pkgfail.$$"    # one line per package that failed (any cause)
	: > "$pkgok"
	: > "$pkgfail"
	while read pkg; do
		case "$pkg" in ""|\#*) continue;; esac      # skip blanks + comments
		# resolve the package file (stock/ then base/), first match
		set -- "$CDROOT"/pkgs/stock/"$pkg"-*.pkg
		pf="$1"
		if [ ! -f "$pf" ]; then
			set -- "$CDROOT"/pkgs/base/"$pkg"-*.pkg
			pf="$1"
		fi
		# FAIL CLOSED, but post-loop: record the failure (an in-loop `die` would only
		# exit the subshell, not halt the install) and move on -- the parent hard-fails.
		if [ ! -f "$pf" ]; then
			warn "  FAIL $pkg  package from the order file is not on the disc"
			echo "$pkg" >> "$pkgfail"
			continue
		fi

		# Gate 13 (core-first): any non-core package needs the target name service.
		if [ "$pkg" != core ]; then
			if [ ! -f "$TARGET/etc/passwd" ] || [ ! -f "$TARGET/etc/group" ]; then
				warn "  FAIL $pkg  core-first gate: target lacks etc/passwd+group"
				echo "$pkg" >> "$pkgfail"
				continue
			fi
		fi

		pfbase=`expr "$pf" : '.*/\(.*\)'`      # basename absent on the miniroot
		# STOCK STAGE STRING (verbatim, amixpkg's per-package line): "Installing %s".
		# The disc filename stays in the log, which is where the detail belongs.
		stage "Installing $pkg"
		logline "$PROG: package file $pfbase"
		if runq "$PKGADD" -R "$TARGET" -n -a "$ADMIN" -d "$pf" "$pkg"; then
			echo "$pkg" >> "$pkgok"
		else
			warn "  FAIL $pkg  pkgadd returned nonzero (rc=$?)"
			echo "$pkg" >> "$pkgfail"
		fi
	done < "$ORDER"
	# Decide in the PARENT, from the files (the subshell's counter mutations are
	# gone): count the OK tokens (pre-POSIX-safe -- see count_tokens re the empty
	# `set --` trap), then FAIL CLOSED on any recorded failure or an empty run.
	npkgs=`count_tokens "$pkgok"`
	if [ -s "$pkgfail" ]; then
		die "base-OS install FAILED for package(s): `cat "$pkgfail"` -- refusing to arm a half-installed disk"
	fi
	[ "$npkgs" -gt 0 ] || die "installed ZERO packages ($ORDER empty or unparseable) -- refusing to arm a bare disk"
	rm -f "$pkgok" "$pkgfail"
	msg "installed $npkgs package(s) via pkgadd -R"
else
	# --- raw: the CD-resident static apkg drives the SAME pkgadd (SRC_RAW) ----
	# apkg reads the self-describing raw distribution slice ($SRC_RAW_DEV): the
	# catalog at byte 0, catalog.md5 at 32768, and each package datastream at the
	# catalog's offset column. `apkg update` fetches the catalog; `apkg install`
	# stages+md5-verifies each datastream into the cache and hands it to the SAME
	# CD-resident pkgadd with the SAME permissive admin, into $TARGET via -R.
	#
	# THE TWO ROOTS (../amix-packagemanager src/apkg/conf.c): -R is the INSTALL
	# TARGET (prefixes only the /var/sadm/pkg "is it installed?" DB and passes
	# through to `pkgadd -R`); APKG_ROOT is the CLIENT's own root and MUST STAY
	# UNSET here -- the engine runs FROM the payload slice and installs INTO the
	# target, so pointing the client root at the target would be the bootstrap bug.
	# The conf's cachedir/admin/pkgadd are LITERAL (never APKG_ROOT-prefixed), so
	# they name absolute miniroot/payload/target paths directly.
	[ -n "$SRC_APKG_TIMEOUT" ] || SRC_APKG_TIMEOUT=600
	APKG="$INST/bin/apkg"
	APKGCACHE="$TARGET/tmp/apkgcache/cache"    # disk-backed (target), real headroom
	RAWCONF="$TARGET/tmp/raw.conf"
	# raw.conf: echo + redirection only (allowlist-clean; the target tmp is writable).
	{
		echo "# apkg raw source -- written by install.sh (W6-RAW.1)"
		echo "repo=raw:$SRC_RAW_DEV"
		echo "cachedir=$APKGCACHE"
		echo "admin=$INST/admin/pkgadd"
		echo "pkgadd=$INST/bin/pkgadd"
		# Install-time apkg reads the LOCAL raw slice (repo=raw:), so it must FAIL
		# FAST: a stall here is a dead device, not a slow mirror. The profile's short
		# SRC_APKG_TIMEOUT bounds the worst case (unattended re-power must not hang
		# minutes). (An earlier `retries=0` line was dropped 2026-09-16: APKG 0.2 has
		# no `retries` key and warned `unknown key 'retries', ignored` on every RAW
		# install -- the timeout alone is the fail-fast.) The INSTALLED /etc/apkg.conf
		# below deliberately keeps the package DEFAULTS instead, so the live post-
		# install network fetch (Xcore ~4 min at ~37 KB/s under APKG 0.2's inactivity
		# timeout) is not cut short.
		echo "timeout=$SRC_APKG_TIMEOUT"
	} > "$RAWCONF" || die "cannot write $RAWCONF"
	msg "RAW: wrote $RAWCONF (repo=raw:$SRC_RAW_DEV cachedir=$APKGCACHE)"

	# apkg update: pull the catalog out of the raw slice (byte 0). FAIL CLOSED.
	msg "RAW: apkg update (catalog from $SRC_RAW_DEV)"
	runq "$APKG" -c "$RAWCONF" update || die "RAW source: apkg update FAILED (catalog unreadable from $SRC_RAW_DEV) -- refusing to install"

	# Build the install set from the order file -- SUBSHELL-SAFE (record to a temp
	# FILE inside the redirect-fed loop, then `set --` it in the parent). The raw
	# catalog's names match the order-file tokens exactly (build-raw-source.sh
	# names.conf preserves pkginst case), so the tokens pass straight to apkg.
	rawnames="$TARGET/tmp/.rawnames.$$"
	: > "$rawnames"
	while read pkg; do
		case "$pkg" in ""|\#*) continue;; esac
		echo "$pkg" >> "$rawnames"
	done < "$ORDER"
	# `[ -s ]`-guard the count (empty `set --` is a no-op on the miniroot sh --
	# audit I): the guard also is the "no packages" fail-closed gate.
	[ -s "$rawnames" ] || die "RAW source: order file $ORDER lists no packages -- refusing to install a bare disk"
	set -- `cat "$rawnames"`
	npkgs=$#
	rm -f "$rawnames"

	# apkg install into $TARGET. apkg stages+verifies EVERYTHING before the first
	# pkgadd and stops on the first pkgadd failure (nonzero rc), so a nonzero rc
	# means the install is incomplete -- HARD STOP, never arm a half-installed disk.
	msg "RAW: apkg install ($npkgs packages) -R $TARGET  [$*]"
	runq "$APKG" -c "$RAWCONF" -R "$TARGET" install "$@" || die "RAW source: apkg install FAILED (apkg rc nonzero) -- refusing to arm a half-installed disk"
	msg "installed $npkgs package(s) via apkg SRC_RAW (-R $TARGET)"
fi

# ===========================================================================
# 5b. CONTENTS-DB INTEGRITY CHECK -- fail closed on any finding (W6.4b)
# ===========================================================================
# The pkgadd loop above built <target>/var/sadm/install/contents (the SVR4 package
# contents DB). Run the CD-resident STATIC contents-fsck over it as a CHECK-ONLY
# gate BEFORE arming first-boot. It is statically linked (no libc/libnsl), so it
# runs on the thin miniroot. CHECK-ONLY, never `-r` repair -- a freshly built DB
# that needs repair means the INSTALL itself is wrong, not something to paper over.
# exit 0 = clean; 1 = findings; 2 = error. ANY non-zero is a HARD STOP: the arm
# step must never run on a bad contents DB (fail closed, like the boot-chain verify).
CFSCK="$INST/bin/contents-fsck"
CONTENTS="$TARGET/var/sadm/install/contents"
[ -x "$CFSCK" ] || die "no contents-fsck at $CFSCK -- is /install/ populated? (W6.4b)"
[ -f "$CONTENTS" ] || die "contents DB absent at $CONTENTS after the pkgadd loop -- refusing to arm"
msg "checking contents-DB integrity (CHECK-ONLY): $CFSCK $CONTENTS"
if runq "$CFSCK" "$CONTENTS"; then
	msg "contents-DB integrity check: clean"
else
	die "contents-DB integrity check FAILED (contents-fsck rc=$?) -- the freshly built contents DB has findings; the install is WRONG. NOT arming first-boot."
fi

# ===========================================================================
# 5b. FP-PATCH THE INSTALLED UFS TOOLS (BLIZZARD F2-M1; ufs + fpfix media only)
# ===========================================================================
# On an FPU-less 68060 (the LC060) the target's OWN /usr/lib/fs/ufs/{mkfs,fsck}
# die at a display-only FP expression -- fsck at its summary line, UPSTREAM of
# "FILE SYSTEM STATE SET TO OKAY" -- so a freshly shipped ufs root can never fsck
# itself in place. MINIROOT_FP_PATCH already fixes the MINIROOT's copies at build
# time (which is what lets the INSTALL's own mkfs_ufs/fsck_ufs run); this fixes the
# copies that land ON THE TARGET. build-install-iso.sh stages a host-PATCHED copy
# of each (patch-ufs-fp.py -- the byte-for-byte F2-M1 transform, every length
# preserved) at $INST/fpfix with a `sum -r` checksum file, IFF the medium's profile
# set MINIROOT_FP_PATCH. Here we cp them over the freshly-installed pair and VERIFY
# the checksum -- fail closed, because a MIS-patched fsck is worse than an unpatched
# one. `cp` and `$INST/bin/sum -r` are the only on-box operations. The patch
# preserves length, so altroot-attest's size-only digest does NOT move; the one
# reader that notices is pkgchk (a cksum mismatch on exactly these two paths -- the
# same declared exception miniroot.proto already carries for the miniroot pair).
# Gated on fpfix PRESENCE: a medium that did not stage it is byte-unaffected and
# this block never runs, so every existing s5/030 and un-patched 040 medium is
# unchanged. The installed size is unmoved (20092 / 111580 B), so /etc/fs -> /usr/
# lib/fs (a symlink) resolves the same files -- patching the real paths covers both.
# Only sh builtins + $INST/bin/sum are used on-box here (the thin miniroot has no
# awk/grep/sed): the SUMS file is parsed with `read`, the member name mapped with
# `case`, and `sum -r`'s first field taken via `set --`. $@ is not used after this
# point, so clobbering the positional params is safe.
FPFIX="$INST/fpfix"
if [ "$TARGET_ROOT_FSTYPE" = ufs ] && [ -d "$FPFIX" ]; then
	FPSUM="$INST/bin/sum"
	[ -x "$FPSUM" ] || die "5b: no SVR4 sum at $FPSUM -- cannot verify the FP-patched ufs tools"
	[ -f "$FPFIX/SUMS" ] || die "5b: $FPFIX present but no $FPFIX/SUMS -- refusing to install unverifiable binaries"
	# The loop runs in a SUBSHELL on the miniroot sh (W5.4e): a `die` in it would end
	# only the subshell and the install would sail on to arm the disk. So it RECORDS
	# (fpok/fpfail files, reason per line) and the parent decides after `done` (IN-fp).
	fpok="$TARGET/tmp/.fpok.$$"
	fpfail="$TARGET/tmp/.fpfail.$$"
	: > "$fpok"
	: > "$fpfail"
	while read fp_nm fp_exp; do
		[ -n "$fp_nm" ] || continue
		case "$fp_nm" in
			mkfs) fp_rel=/usr/lib/fs/ufs/mkfs ;;
			fsck) fp_rel=/usr/lib/fs/ufs/fsck ;;
			*)    echo "unknown fpfix member '$fp_nm' in $FPFIX/SUMS" >> "$fpfail"; continue ;;
		esac
		fp_src="$FPFIX/$fp_nm"; fp_dst="$TARGET$fp_rel"
		if [ ! -f "$fp_src" ]; then
			echo "staged FP-patched $fp_nm missing at $fp_src" >> "$fpfail"; continue
		fi
		if [ ! -f "$fp_dst" ]; then
			echo "target has no $fp_rel to replace -- is ufs in this install set? (core lays it)" >> "$fpfail"; continue
		fi
		if [ -z "$fp_exp" ]; then
			echo "no expected sum for $fp_nm in $FPFIX/SUMS" >> "$fpfail"; continue
		fi
		if runq cp "$fp_src" "$fp_dst"; then
			:
		else
			echo "cp $fp_src -> $fp_rel failed" >> "$fpfail"; continue
		fi
		if [ -s "$fp_dst" ]; then
			set -- `"$FPSUM" -r "$fp_dst"`; fp_got=$1
		else
			echo "$fp_rel is empty after cp (a sum of nothing leaves \$@ stale and would false-verify)" >> "$fpfail"; continue
		fi
		if [ "$fp_got" = "$fp_exp" ]; then
			echo "$fp_nm" >> "$fpok"
			msg "5b: FP-patched installed $fp_rel (sum -r $fp_got, verified) [BLIZZARD F2-M1]"
		else
			echo "FP-patched $fp_rel sum -r $fp_got != expected $fp_exp (a mis-patched fsck is worse than none)" >> "$fpfail"
		fi
	done < "$FPFIX/SUMS"
	[ -s "$fpfail" ] && die "5b: REFUSING to arm -- `cat "$fpfail"`"
	[ "`count_tokens "$fpok"`" -gt 0 ] || die "5b: $FPFIX/SUMS names no member -- nothing was patched"
	rm -f "$fpok" "$fpfail"
	msg "5b: installed-tree ufs FP patch applied + verified -- the shipped root can fsck itself on an FPU-less 060"
elif [ "$TARGET_ROOT_FSTYPE" = ufs ]; then
	msg "5b: no $FPFIX on the medium -- installed ufs tools left STOCK (fine on a real FPU; FATAL on an LC060)"
fi

# ===========================================================================
# 5c. WRITE THE PACKAGE-CLIENT CONFIG (/etc/apkg.conf on the target) (W6.4b)
# ===========================================================================
# The APKG package (installed above) delivers the dynamic apkg remote client and
# ships a default /etc/apkg.conf (class `e apkgconf` since APKG 0.2.3; a plain `f` file
# through 0.2.2) already pointing at the live
# repo. The driver re-writes it here, DELIBERATELY overwriting the package copy, so
# that "the installed box's package client points at the live repo" is a DRIVER-
# guaranteed invariant -- provable in the s5 check -- rather than contingent on
# pkgadd's editable-file placement (which our install contract never verifies).
# W1: the repo URL is the profile key FB_REPO_URL. Its default is the PUBLIC
# canonical repo http://pkg.amigaux.org (2026-09-15; the old LAN literal repo
# is RETIRED), so a profile that omits the key
# points at the live public repo.
# /etc/apkg.conf is a class-`e` editable member (APKG 0.2.3), so `pkgchk -n APKG`
# skips its content check (a plain `pkgchk APKG` still names the edited conf, by SVR4
# design -- checks use -n), and the contents-DB digest (a pure function of what pkgadd
# RECORDED, not the live bytes) is UNAFFECTED. Identity-independent, so it is written HERE on
# the miniroot against the mounted target, NOT at first-boot. repo/cachedir/admin
# match the package's shipped conf. echo + redirection only (allowlist-clean).
if [ -x "$TARGET/usr/apkg/bin/apkg" ]; then
	# Written before the package loop (above). An APKG older than 0.2.3 delivers the conf as a
	# plain `f` file and REPLACES it: then the repo line is gone -- write it again (a plain
	# `pkgchk APKG` will then name it; the r6 media carry 0.2.3, where the file is kept).
	rm -f "$TARGET/tmp/.apkgrepo.$$"
	if [ -f "$APKG_CONF" ]; then
		while read _l; do
			if [ "$_l" = "repo=$FB_REPO_URL" ]; then echo y > "$TARGET/tmp/.apkgrepo.$$"; fi
		done < "$APKG_CONF"
	fi
	if [ -f "$TARGET/tmp/.apkgrepo.$$" ]; then
		rm -f "$TARGET/tmp/.apkgrepo.$$"
		msg "$APKG_CONF kept by the APKG package (repo=$FB_REPO_URL)"
	else
		warn "$APKG_CONF lost its repo line in the package install (APKG older than 0.2.3?) -- writing it again"
		write_apkg_conf
	fi
else
	warn "target has no /usr/apkg/bin/apkg -- skipping /etc/apkg.conf (APKG not in this install set?)"
fi

# ===========================================================================
# 6-8c, 1.1: the kernel package and the boot store (l11.sh) REPLACE sections 6 to 8c
# ===========================================================================
if [ "$INSTALL_LAYOUT" = 1.1 ]; then
	if [ "${INSTALL_UPGRADE:-no}" = yes ]; then
		l11_upgrade_restore
		if [ "${SWAP_HOLD:-}" = y ]; then SWAP_HOLD=; add_target_swap; fi
	fi
	l11_bootstore
else
# ===========================================================================
# 6. OVERWRITE /stand/boot2.boot WITH THE FLAGS-BASED LOADER
# ===========================================================================
# core ships the NAME-BASED loader (sha256 5ab360b1...) at /stand/boot2.boot --
# it cannot relocate the project's flags-based ET_REL kernels (D245/RELA Guru).
# Replace it with the flags-based loader (f287ff3a..., shipped on the CD, gated
# at build time). This is what the pipeline does before rebuilding a boot part;
# it matters when the user later runs `make bootpart` on the installed system.
run cp "$INST/$BOOT2_BOOT" "$TARGET/stand/boot2.boot"
run chmod 644 "$TARGET/stand/boot2.boot"
# Name the loader from the medium's own boot-slice manifest (its "# source ...
# boot2 sha256=<12 hex>" line, written by tools/build-bootslice.py) -- the 030 line
# ships f287ff3a, the 040/060 line good_040 fd7dacf6; a fixed string was wrong for
# one of them. Builtin read only: the miniroot has no sed, and no ${var#pat}. The
# 1991 sh runs a redirect-fed loop in a SUBSHELL, so the answer is ECHOED out of
# it and captured -- a variable assigned inside would be lost after the loop.
BOOT2_ID=`( while read _h _k _f1 _f2 _f3 _rest
do
	if [ "$_h" = "#" ] && [ "$_k" = source ] && [ "$_f2" = boot2 ]; then
		echo "$_f3"
	fi
done ) < "$INST/$BOOTSLICE_MANIFEST"`
[ -n "$BOOT2_ID" ] || BOOT2_ID="sha256 unknown"
msg "installed flags-based /stand/boot2.boot ($BOOT2_ID...)"

# ===========================================================================
# 7. WRITE THE TARGET BOOT SLICE (dd a pre-built chain image; no sh assembly)
# ===========================================================================
# The chain boot1|IBLK|boot2|IBLK|kernel was assembled + gated HOST-side
# (tools/build-bootslice.py) and shipped on the CD. The driver just dd's it to
# the start of the target's UNI\0 boot slice (raw node) -- no chain
# reconstruction in sh, no compression, no checksum arithmetic on the box.
BSIMG="$INST/$BOOTSLICE_IMG"
[ -f "$BSIMG" ] || die "boot-slice image missing on the disc: $BSIMG"
# FIT GUARD (060 line): the 68040/68060 target kernel is UNCOMPRESSED, so the
# chain is ~1.94 MB and needs a >=2 MiB boot slice. A chain larger than the slice
# would dd past slice 3 into root/swap and corrupt them -- and the damage would
# only surface as a bad root at the post-install first boot, the wrong end of the
# demo to debug. In AUTHOR mode BOOTLEN is the slice size we wrote to the RDB (512-
# blocks); the manifest chain region is the chain block count. Refuse if it does not
# fit. (Prebuilt/030 media size the slice via mkroot and ship the small brel chain --
# no overflow risk -- so BOOTLEN is only checked when it is set.)
FIT_MAN="$INST/$BOOTSLICE_MANIFEST"
if [ -n "${BOOTLEN:-}" ] && [ -f "$FIT_MAN" ]; then
	rm -f "$TARGET/tmp/.chainblk"
	while read fit_region fit_off fit_nblk fit_sum
	do
		case "$fit_region" in
		chain)	echo "$fit_nblk" > "$TARGET/tmp/.chainblk" ;;
		esac
	done < "$FIT_MAN"
	[ -s "$TARGET/tmp/.chainblk" ] || die "boot-chain manifest names no chain region -- cannot check the chain fits the boot slice; refusing to dd"
	CHAIN_BLK=`cat "$TARGET/tmp/.chainblk"`
	rm -f "$TARGET/tmp/.chainblk"
	is_num "$CHAIN_BLK" || die "boot-chain size unreadable from the manifest -- refusing to dd"
	[ "$CHAIN_BLK" -le "$BOOTLEN" ] || die "boot chain is $CHAIN_BLK blocks but the target boot slice is only $BOOTLEN blocks -- it would overflow into the next partition. Grow TARGET_BOOT_MB (the 060 chain needs >=2 MiB). NOT writing."
	msg "boot chain fits: $CHAIN_BLK blocks <= boot slice $BOOTLEN blocks"
fi
msg "writing boot chain: dd $BSIMG -> $BOOT_RAW"
run dd if="$BSIMG" of="$BOOT_RAW" bs=512
run sync

# --- 7b. RUN_UNIT=stamp: the chosen unit's bytes into the written family chain -------
# Each row "<block> <offset> <ooo>" is written by rebuilding its block (put_bytes) and
# then checked byte by byte off the raw slice; section 8 then verifies every region
# against the UNIT's manifest, which is what makes the stamped chain the unit's chain.
if [ -n "$STAMP_PATCH" ]; then
	msg "stamping SCSI id $ID into the family chain ($STAMP_PATCH)"
	while read s_blk s_off s_oct; do
		case "$s_blk" in ''|\#*) continue ;; esac
		[ -n "$s_oct" ] || continue
		oct_file "$TARGET/tmp/.sb.$$" "$s_oct"
		put_bytes "$BOOT_RAW" "$s_blk" "$s_off" 1 "$TARGET/tmp/.sb.$$" || echo "$s_blk $s_off" >> "$TARGET/tmp/.stampfail.$$"
		dd if="$BOOT_RAW" of="$TARGET/tmp/.sr.$$" bs=512 skip="$s_blk" count=1 2>/dev/null
		byte_is "$TARGET/tmp/.sr.$$" "$s_off" "$s_oct" || echo "$s_blk $s_off" >> "$TARGET/tmp/.stampfail.$$"
		echo "$s_blk" >> "$TARGET/tmp/.stampok.$$"
	done < "$STAMP_PATCH"
	rm -f "$TARGET/tmp/.sb.$$" "$TARGET/tmp/.sr.$$"
	[ -s "$TARGET/tmp/.stampfail.$$" ] && die "stamp FAILED at `cat $TARGET/tmp/.stampfail.$$` -- the boot slice does not hold the unit's chain"
	[ -s "$TARGET/tmp/.stampok.$$" ] || die "the stamp table $STAMP_PATCH held no rows -- refusing an unstamped family chain"
	rm -f "$TARGET/tmp/.stampok.$$"
	run sync
	msg "stamp written and read back byte for byte"
fi

# ===========================================================================
# 8. ON-TARGET BOOT-CHAIN VERIFICATION (dd out, sum -r, compare to manifest)
# ===========================================================================
# The miniroot has no python, no od, no cmp -- but the CD ships the genuine SVR4
# `sum` (from core). For each region in the manifest, dd it out of the WRITTEN
# boot slice and compare its `sum -r` (first field) to the manifest value. The
# box `sum -r` == the manifest's BSD checksum (tools/lib/sumr.py).
SUM="$INST/bin/sum"
MAN="$INST/$BOOTSLICE_MANIFEST"
[ -x "$SUM" ] || die "no SVR4 sum at $SUM (needed for on-target boot-chain verify)"
[ -f "$MAN" ] || die "no boot-slice manifest at $MAN"
msg "verifying the written boot chain against $BOOTSLICE_MANIFEST ..."
# SUBSHELL-SAFE COUNTING (W5.4e) -- identical rationale to the pkgadd loop above.
# This `while read ... done < FILE` also runs in a SUBSHELL, so vok/vfails mutated
# inside are lost at `done`. In W5.4d the loop printed three OK lines, then the
# aggregate guard `[ $vok -gt 0 ]` false-fired on the reset-to-zero vok ("checked
# ZERO regions ... refusing to arm") and the driver died before first-boot. Record
# OK/FAIL to append-only temp FILES inside; count them in the parent after `done`.
vok_f="$TARGET/tmp/.vok.$$"
vfails_f="$TARGET/tmp/.vfails.$$"
: > "$vok_f"
: > "$vfails_f"
tmpr="$TARGET/tmp/.bootregion.$$"
# manifest lines: <region> <block_off> <n_blocks> <sum-r>. Every region is
# block-aligned (the image is zero-padded to a whole block), so each read is a
# clean dd bs=512 -- no bs=1 crawl, no hex conversion.
while read region blk_off nblk want_sum; do
	case "$region" in ""|\#*) continue;; esac
	# FAIL CLOSED on a truncated manifest line: without all three numeric fields
	# there is nothing real to compare (the line-level empty-vs-empty trap).
	if [ -z "$blk_off" ] || [ -z "$nblk" ] || [ -z "$want_sum" ]; then
		warn "  FAIL $region  malformed manifest line (missing block/count/sum field)"
		echo "$region" >> "$vfails_f"
		continue
	fi
	dd if="$BOOT_RAW" bs=512 skip="$blk_off" count="$nblk" of="$tmpr" 2>/dev/null
	got_sum=`"$SUM" -r "$tmpr" | ( read s rest; echo "$s" )`
	# Numeric equality: is_num guards BOTH sides (an empty/garbled got_sum -- dd or
	# sum failed -- is not a number) and `-eq` ignores sum -r's 5-digit zero pad,
	# so no leading-zero strip (no sed) is needed. empty==empty can never pass now.
	if is_num "$got_sum" && is_num "$want_sum" && [ "$got_sum" -eq "$want_sum" ]; then
		msg "  OK   $region  sum -r $got_sum ($nblk blocks)"
		echo "$region" >> "$vok_f"
	else
		warn "  FAIL $region  sum -r '$got_sum' != manifest '$want_sum'"
		echo "$region" >> "$vfails_f"
	fi
done < "$MAN"
rm -f "$tmpr"
# Count in the PARENT (the subshell's increments are gone): tokens per file.
# pre-POSIX-safe -- count_tokens `[ -s ]`-guards the empty `set --` no-op trap that
# would otherwise carry the vok count over into an empty vfails (W5.4e-run-1).
vok=`count_tokens "$vok_f"`
vfails=`count_tokens "$vfails_f"`
rm -f "$vok_f" "$vfails_f"
[ "$vfails" = 0 ] || die "boot-chain verification FAILED ($vfails region(s)) -- the disk will not boot; NOT arming first-boot"
# A manifest that yielded ZERO verified regions is itself a failure -- never read
# "nothing checked" as "all good" (the aggregate form of the empty-vs-empty trap).
[ "$vok" -gt 0 ] || die "boot-chain verification checked ZERO regions ($BOOTSLICE_MANIFEST empty or unparseable) -- refusing to arm a possibly-unbootable disk"
msg "boot chain verified on-target ($vok region(s), $BOOTSLICE_MANIFEST)"

# --- 8b. /stand/unix = THE FRAMED KERNEL (040/060 line; Q-4.15 trap ii) ----------
# The stock core package lays its 1992 030 kernel at /stand/unix. On the 040/060 line
# an on-box reframe (`make bootpart`, updbootpart) would then frame an unbootable chain,
# so /stand/unix becomes the exact kernel the boot slice frames -- for RUN_UNIT=install,
# the chosen unit's. Gated by its sum -r against KERNEL_BREL_SUMR (the framed kernel's).
# First boot re-registers it in the core package (installf), so pkgchk stays clean.
if [ -n "$STAND_UNIX_FROM_SLICE" ]; then
	# RUN_UNIT=stamp: the unit's kernel IS the stamped slice from block 20 (0x2800) on,
	# STAND_UNIX_FROM_SLICE bytes long -- read it out, never patch a file in place.
	_kb=`expr $STAND_UNIX_FROM_SLICE + 511`
	_kb=`expr $_kb / 512`
	run dd if="$BOOT_RAW" of="$TARGET/tmp/.unix.$$" bs=512 skip=20 count="$_kb"
	run dd if="$TARGET/tmp/.unix.$$" of="$TARGET/stand/unix" bs="$STAND_UNIX_FROM_SLICE" count=1
	rm -f "$TARGET/tmp/.unix.$$"
	STAND_UNIX=stamped
fi
if [ -n "$STAND_UNIX" ]; then
	if [ "$STAND_UNIX" != stamped ]; then
		[ -f "$INST/$STAND_UNIX" ] || die "the 040/060 kernel for /stand/unix is missing from the medium: $INST/$STAND_UNIX"
		run cp "$INST/$STAND_UNIX" "$TARGET/stand/unix"
	fi
	run chmod 0644 "$TARGET/stand/unix"
	su_got=`"$SUM" -r "$TARGET/stand/unix" | ( read s rest; echo "$s" )`
	if is_num "$su_got" && is_num "$KERNEL_BREL_SUMR" && [ "$su_got" -eq "$KERNEL_BREL_SUMR" ]; then
		msg "/stand/unix = the framed kernel (sum -r $su_got); first boot re-registers it (installf core)"
	else
		die "/stand/unix sum -r '$su_got' != the framed kernel's $KERNEL_BREL_SUMR -- refusing to arm"
	fi
fi

# --- 8c. the RTO1 root record: boot disk and root disk differ (D-2, RTH1 spec) ---------
# ROOT_RECORD_DISK=<card-0 id> names the disk Kickstart will BOOT (the A4092 ROM 42.39
# offers no Amix partition, so a root behind it is started from a boot disk on the
# Z3660). That disk's slice 3 gets this medium's chain and, at boot-slice offset 0x2700
# (kernel IBLK +0x100, in ib_pad; no checksum covers it), the 0x1c-byte record naming the
# target: unit, controller identity, check (boot/<p>/rto1, tools/rth1-media.py). The loader
# copies it verbatim; the kernel validates it and otherwise uses its built-in root. The
# record's 28 bytes are verified ONE BY ONE: no span sum can tell two units' records apart.
if [ -n "${ROOT_RECORD_DISK:-}" ]; then
	RD="$ROOT_RECORD_DISK"
	[ -n "`hexval "$RD"`" ] || die "ROOT_RECORD_DISK='$RD' is not a controller number"
	# card 0 only: this is the 1.0 hint path, whose kernels are two-card and boot from the
	# card Kickstart boots; cards 2-3 (10-1f, C4-1) cannot hold this boot disk today. A 1.1
	# root on card 2/3 is named by identity in the store's root record instead (stage 5:
	# revisit if a root record ever has to point at a card-2/3 boot disk)
	case "$RD" in
		7|f|F|8|9|a|A|b|B|c|C|d|D|e|E|1?)	die "ROOT_RECORD_DISK=$RD: the boot disk must be a card-0 unit 0-6 (Kickstart boots it)" ;;
	esac
	[ "$RD" != "$ID" ] || die "ROOT_RECORD_DISK=$RD is the target itself -- a same-disk install carries no root record"
	[ "${RUN_UNIT:-6}" = hint ] || die "ROOT_RECORD_DISK needs RUN_UNIT=hint (a root record means nothing to a loader without RTH1)"
	RTAB="$INST/`expr "$BOOTSLICE_IMG" : '\(.*\)/'`/rto1"
	[ -f "$RTAB" ] || die "ROOT_RECORD_DISK is set but this medium has no root-record table at $RTAB"
	rm -f /tmp/.rtorow
	while read r_id r_nblk r_sum r_rest; do
		[ "$r_id" = "$ID" ] && echo "$r_nblk $r_sum $r_rest" > /tmp/.rtorow
	done < "$RTAB"
	[ -s /tmp/.rtorow ] || die "this medium carries no root record for SCSI id $ID ($RTAB)"
	set -- `cat /tmp/.rtorow`
	rm -f /tmp/.rtorow
	R_NBLK=$1; R_SUM=$2; shift 2
	[ "$#" = 28 ] || die "the root record for SCSI id $ID is not 28 bytes ($# in $RTAB)"
	RD_RAW="/dev/rdsk/c${RD}d0s3"
	if [ ! -c "$RD_RAW" ]; then
		ensure_disk_nodes "$RD" || die "cannot create the device nodes for the boot disk (SCSI id $RD)"
	fi
	# the boot disk must already be partitioned, with a slice 3 the chain fits in
	rdlen=`/etc/rdb "/dev/rdsk/c${RD}d0s0" 2>/dev/null | ( read a1 b1 c1; read a2 b2 c2; read a3 b3 c3; echo "$c3" )`
	is_num "$rdlen" || die "boot disk SCSI id $RD has no readable slice 3 (/etc/rdb) -- author it as a boot-only disk first"
	[ "$R_NBLK" -le "$rdlen" ] || die "the chain is $R_NBLK blocks but boot disk $RD's slice 3 is $rdlen -- NOT writing"
	msg "root record: boot disk SCSI id $RD gets the chain + RTO1 naming SCSI id $ID"
	run dd if="$BSIMG" of="$RD_RAW" bs=512
	oct_file "$TARGET/tmp/.rto.$$" "$@"
	put_bytes "$RD_RAW" 19 256 28 "$TARGET/tmp/.rto.$$" || die "could not write the root record to $RD_RAW"
	rm -f "$TARGET/tmp/.rto.$$"
	run sync
	dd if="$RD_RAW" of="$TARGET/tmp/.rb.$$" bs=512 skip=19 count=1 2>/dev/null
	r_off=256
	for r_oct in "$@"
	do
		byte_is "$TARGET/tmp/.rb.$$" "$r_off" "$r_oct" || die "root record byte at boot-slice 0x2700+`expr $r_off - 256` did not read back"
		r_off=`expr $r_off + 1`
	done
	rm -f "$TARGET/tmp/.rb.$$"
	dd if="$RD_RAW" bs=512 count="$R_NBLK" of="$TARGET/tmp/.rc.$$" 2>/dev/null
	r_got=`"$INST/bin/sum" -r "$TARGET/tmp/.rc.$$" | ( read s rest; echo "$s" )`
	rm -f "$TARGET/tmp/.rc.$$"
	is_num "$r_got" && [ "$r_got" -eq "$R_SUM" ] || die "boot disk $RD: the chain with its root record sums $r_got, expected $R_SUM"
	msg "root record verified: 28 bytes one by one, chain sum -r $r_got"
	# A separate boot-only disk ships NOT bootable (pri -128): it must not win a boot
	# before it carries a chain and a record. Arm it now, above the installer's pri.
	if [ -n "${ROOT_RECORD_BOOTPRI:-}" ]; then
		is_num "$ROOT_RECORD_BOOTPRI" || die "ROOT_RECORD_BOOTPRI='$ROOT_RECORD_BOOTPRI' is not a number"
		run /etc/rdb -p 3 -M -B -C 2 -P "$ROOT_RECORD_BOOTPRI" -F 0x554e4900 "/dev/rdsk/c${RD}d0s0"
		msg "boot disk SCSI id $RD: UNIX_Boot armed at boot priority $ROOT_RECORD_BOOTPRI"
	fi
fi

fi	# INSTALL_LAYOUT 1.0: sections 6-8c

# ===========================================================================
# 8z. THE 030 LINE'S SWAP (2026-10-07; the tail 2026-10-08, r6c)
# ===========================================================================
# The 030 kernel (K030-U) swaps on its built-in boot area only: the first NSWAP (20479)
# sectors of the root disk's slice 2, listed by `swap -l` as 20476 blocks of 512 bytes.
# The installer's slice 2 is longer (18 MB = 36864 on a 100 MB disk), and with only 10 MiB
# reservable, pkgadd's class-action fork failed EAGAIN (APKG 0.2.3 upgrade, fresh030d/e/g);
# with the unused tail added as a second area the same upgrade completed (fresh030f).
# (`swap -s` reads 0 on Amix whatever is configured -- never evidence; judge by swap -l.)
# S89rootswap, a driver-written ADDITIVE file like S16firstboot, finds slice 2 of the disk /
# is mounted from (devnm, as bcheckrc does) and adds, at boot:
#   * no area listed            -> the whole slice, 0..LEN (LEN read off THIS disk's RDB);
#   * exactly the boot area     -> the tail, START..LEN, START = the next 16-block boundary
#     (s2, swaplo 0, BOOT blocks)  past BOOT (no page of the boot area can reach it), only
#                                  when at least 2048 blocks (1 MiB) remain;
#   * anything else             -> nothing (a second area, another device, other lengths).
# The 040/060 line never gets the file (INSTALL_CPU=040 there).
K030_BOOTSWAP=20476
K030_SWAPTAIL=20480	# the next 16-block boundary past K030_BOOTSWAP
if [ "${INSTALL_CPU:-030}" = 030 ]; then
	RSLEN="$SWAPBLKS"
	is_num "$RSLEN" || RSLEN="$SWAPLEN"
	RSSTART=$K030_SWAPTAIL
	{
		echo '#!/bin/sh'
		echo '# S89rootswap -- written by install.sh (the 030 line). The 030 kernel swaps on its boot'
		echo '# area only: the first BOOT blocks of the root disk'"'"'s slice 2. Slice 2 is LEN blocks (read'
		echo '# off its RDB at install), so add the unused tail START..LEN as a second area; with no'
		echo '# area listed add the whole slice. Any other swap -l: leave it alone.'
		echo "LEN=$RSLEN"
		echo "BOOT=$K030_BOOTSWAP"
		echo "START=$RSSTART"
		echo 'case $1 in'
		echo 'start)'
		echo '	r=`/etc/devnm / 2>/dev/null | sed -e "s: .*::"`'
		echo '	s=`echo "$r" | sed -e "s:s[0-9a-fA-F]*\$:s2:"`'
		echo '	case "$s" in /dev/dsk/c*s2) ;; *) exit 0 ;; esac'
		echo '	l=`/usr/sbin/swap -l 2>/dev/null | grep "^/dev/"`'
		echo '	if [ -z "$l" ]; then'
		echo '		/usr/sbin/swap -a $s 0 $LEN && echo "Added swap partition $s, $LEN blocks."'
		echo '		exit 0'
		echo '	fi'
		echo '	set -- $l'
		echo '	[ $# = 5 ] || exit 0'
		echo '	[ "$1" = "$s" ] && [ "$3" = 0 ] && [ "$4" = "$BOOT" ] || exit 0'
		echo '	[ $LEN -ge `expr $START + 2048` ] || exit 0'
		echo '	n=`expr $LEN - $START`'
		echo '	/usr/sbin/swap -a $s $START $n && echo "Added swap partition tail $s, $n blocks at $START."'
		echo '	;;'
		echo 'esac'
	} > "$TARGET/etc/rc2.d/S89rootswap" || die "could not write $TARGET/etc/rc2.d/S89rootswap"
	run chmod 0744 "$TARGET/etc/rc2.d/S89rootswap"
	msg "030 swap: /etc/rc2.d/S89rootswap adds slice 2's tail past the kernel's boot area ($RSSTART..$RSLEN) at boot"
fi

# ===========================================================================
# 9. ARM FIRST-BOOT
# ===========================================================================
# Copy the first-boot payload into the target and drop a marker the target's
# first multiuser boot runs once. Identity comes from the profile (FB_*).
msg "arming first-boot..."
run mkdir -p "$TARGET/var/adm/firstboot"
# root's alone: S16firstboot runs firstboot.sh AS ROOT whenever PENDING exists and it
# sources firstboot.conf, so a writable dir or conf is a local root (P-15, 2026-10-03).
run chmod 700 "$TARGET/var/adm/firstboot"
run cp "$INST"/firstboot/firstboot.sh "$TARGET/var/adm/firstboot/firstboot.sh"
run cp "$INST"/firstboot/root.shadow  "$TARGET/var/adm/firstboot/root.shadow"
run chmod 700 "$TARGET/var/adm/firstboot/firstboot.sh"
run chmod 600 "$TARGET/var/adm/firstboot/root.shadow"
# write the profile-derived identity the firstboot script consumes
{
	echo "# generated by install.sh from profile $PROFILE_NAME"
	echo "FB_NODENAME=$FB_NODENAME"
	echo "FB_DOMAIN=$FB_DOMAIN"
	echo "FB_TZNUM=$FB_TZNUM"
	# W1: the TIMEZONE zone NAME, de-hardcoded out of firstboot.sh (which used to
	# write the literal `TZ=:US/Eastern` no matter what the profile said, so every
	# unattended install silently diverged from its own spec). The value here is
	# the BARE zone -- firstboot.sh emits the load-bearing leading colon itself.
	echo "FB_TZ=$FB_TZ"
	echo "FB_IP=$FB_IP"
	echo "FB_NETMASK=$FB_NETMASK"
	echo "FB_ETHER_IF=$FB_ETHER_IF"
	# W1: the LAN default-route gateway the zen0 bring-up installs (was the
	# literal LAN gateway in emit_zen_hook).
	echo "FB_GATEWAY=$FB_GATEWAY"
	# P-3: the address-by-card table (MAC=ADDR=NAME words, quoted -- the conf is
	# sourced). firstboot.sh renders it into /etc/inet/zen.conf on a zen0 flavor,
	# which S99zen reads at every boot (docs/address-by-card.md). Empty = no table.
	echo "FB_ZEN_CARDS=\"$FB_ZEN_CARDS\""
	# W1 recorded these; W5 APPLIES them. The five-part DNS enablement
	# (resolv.conf, the libsockdns relink, netconfig.DNS, an empty /etc/domain and
	# LITERAL-IP boot ifconfigs) is firstboot.sh's, and it fires only on a
	# literal-IP flavor: on aen0 the fifth part is the /etc/inet/network-config
	# ifconfig, the one file this project never edits, so DNS is refused there with
	# a printed line rather than half-applied.
	echo "FB_DNS1=$FB_DNS1"
	echo "FB_DNS2=$FB_DNS2"
	# W5: the keys the first-boot DIALOG owns. The driver writes the profile's
	# values (and the defaults that preserve today's behaviour exactly); when the
	# dialog is armed it REPLACES its own block in this file before S16 reads it.
	#   FB_DIALOG          y when this install armed the dialog (S16 then keeps
	#                      PENDING until the dialog has completed once)
	#   FB_ROOT_TELNET     y = `#CONSOLE=` in /etc/default/login, i.e. root may
	#                      telnet in. Default y: that is what the driver has always
	#                      done, and CONSOLE= gates ROOT only (ordinary users can
	#                      always telnet), so silently disabling it would take the
	#                      only remote root login this system has.
	#   FB_SYSLOG          y = the laid-down syslog unit stays enabled (today's
	#                      behaviour, no edit at all); n = firstboot restores the
	#                      vendor `exit` line, IN PLACE (three hard links).
	#   FB_NET_CONFIGURED  set to y only by the dialog. It gates the network
	#                      EXTRAS (the rc.inet default route, the zen0 laydown
	#                      refresh, DNS), so an unattended install never grows a
	#                      step it did not have before W5.
	#   FB_TZ_KEEP         set to y only by the dialog, whose stock TZ menu has
	#                      already written /etc/TIMEZONE (with the colon, and with
	#                      the localtime alias): firstboot then leaves it alone.
	echo "FB_DIALOG=$FIRSTBOOT_DIALOG"
	echo "FB_ROOT_TELNET=$FB_ROOT_TELNET"
	echo "FB_SYSLOG=$FB_SYSLOG"
	echo "FB_NET_CONFIGURED=$FB_NET_CONFIGURED"
	echo "FB_TZ_KEEP=$FB_TZ_KEEP"
	echo "FB_REPO_URL=$FB_REPO_URL"
	# W1: the keymap baked onto the target at the arm step below (empty or `usa`
	# means "none" -- the American map is compiled in and stock linked nothing).
	echo "FB_KMAP=$FB_KMAP"
	# W6.4c: the apkg repo host->IP, baked into /etc/inet/hosts by firstboot.sh so
	# `apkg update` resolves the repo with no DNS. Empty when a profile carries no
	# repo (firstboot then skips the hosts append, silently-but-logged).
	echo "FB_REPO_HOST=$FB_REPO_HOST"
	echo "FB_REPO_IP=$FB_REPO_IP"
	echo "FB_ROOTDEV=$ROOTDEV"
	# ★ THE CONTROLLER THE *DESTINATION* SEES, which is not always the one we
	# installed through. firstboot builds /etc/vfstab as /dev/dsk/c${FB_SCSI_ID}d0sN,
	# so on an image AUTHORED on one rig and RUN on another these are two different
	# facts: the bench installs through c6d0 (card 0, unit 6) while the Z3660 metal
	# target boots a card-1-stamped kernel whose root is ced0s1 (card e = card 1 |
	# unit 6). Left empty -- as every existing profile leaves it -- FB_SCSI_ID is
	# TARGET_SCSI_ID and nothing changes by a byte.
	# Both names reach the same disk under the card-index identity law, so a
	# mismatch is LATENT rather than fatal at boot; it bites the things that DERIVE
	# a device from vfstab (updbootpart's boot-slice derivation, bcheckrc's fsck
	# fallback), which then act on the wrong controller.
	echo "FB_SCSI_ID=${TARGET_VFSTAB_SCSI_ID:-$ID}"
	# 8b laid the framed kernel at /stand/unix: first boot re-registers it in core.
	[ -n "$STAND_UNIX" ] && echo "FB_STANDUNIX_REG=y"
	# 1.1: l11_namelist removed the name /stand/unix; first boot takes it out of core's
	# contents too. modtools rewrote /etc/inittab by rename, so it lost core's group.
	[ "$INSTALL_LAYOUT" = 1.1 ] && echo "FB_STANDUNIX_RM=y"
	[ "${L11_KMOD:-n}" = y ] && echo "FB_INITTAB_SYS=y"
	# a four-card kernel (C4-1): first boot swaps core's d1 nodes for c10-c1f
	[ "${L11_SDCARDS:-2}" = 4 ] && echo "FB_SDCARDS=4"
	echo "FB_ROOT_SLICE=$TARGET_ROOT_SLICE"
	echo "FB_SWAP_SLICE=$TARGET_SWAP_SLICE"
	# The filesystem this install laid on the root slice -- the ONE field the
	# first boot needs it for is /etc/vfstab column 4 (firstboot.sh section 4).
	# Everything downstream of that column is already type-generic: the stock
	# /usr/sbin/bcheckrc resolves the root type from the KERNEL (`df -n /`),
	# falls back to vfstab, and dispatches through the generic /sbin/fsck front
	# end, which execs /usr/lib/fs/<type>/fsck -- and core ships the whole ufs
	# back end (mkfs/fsck/mount/labelit + 17 more). firstboot.sh defaults this
	# key to s5 when it is absent, so a firstboot.conf written by an older
	# driver keeps its old behaviour exactly.
	echo "FB_ROOT_FSTYPE=$TARGET_ROOT_FSTYPE"
	# 1.1: the data slice firstboot.sh mounts at /home (absent = none, as before)
	if [ "${DATALEN:-0}" -gt 0 ]; then echo "FB_DATA_SLICE=4"; fi
} > "$TARGET/var/adm/firstboot/firstboot.conf"
# The PENDING marker: the rc2 hook (below) runs firstboot.sh once iff this exists,
# and firstboot.sh removes it when done -- that pair is the once-only mechanism.
# `touch` is absent on the miniroot, so create the empty marker with a redirection
# -- which cannot route through run().
echo "+ : > $TARGET/var/adm/firstboot/PENDING"
: > "$TARGET/var/adm/firstboot/PENDING" || die "cannot create the first-boot PENDING marker"
run chmod 600 "$TARGET/var/adm/firstboot/firstboot.conf" "$TARGET/var/adm/firstboot/PENDING"

# --- WIRE first-boot into the target's init (W5.4f) --------------------------
# Two moves, both proven against an s5 read of the installed target's init flow:
#   1. DISARM the stock sysinit dialog. /etc/sysinit (a core member, run from the
#      inittab `S2::sysinit` line at BOOT, before run level 2) does:
#          if [ -x /usr/amiga/bin/system.setup ]; then sh .../system.setup; fi
#      system.setup sources /usr/amiga/lib/amixnode ("What is the nodename ...?")
#      and, when the operator finally answers "no" to "change any of these?", ends
#      with `chmod -x /usr/amiga/bin/system.setup` -- its OWN once-only disarm. We
#      apply exactly that disarm non-interactively here (mode-only; content/cksum
#      untouched), so the dialog never appears. It is the intended end-state of any
#      configured Amix box, and altroot-attest (a pure function of the pkgadd
#      contents DB) is unaffected. This is the single package-file touch in the
#      whole install, and it is a mode bit, not a rewrite of any rc script.
#   2. ADD the rc2 hook (emit_firstboot_hook above), a NEW non-package file that
#      runs firstboot.sh iff PENDING exists. rc2.d/S* scripts complete before the
#      inittab `con` getty spawns, so identity is baked before the console login.
# core always ships /etc/rc2.d (a directory member), so it exists by now. The
# miniroot's 1991 `mkdir -p` is NOT idempotent on an EXISTING leaf -- it prints
# "File exists" and returns rc=2 (W5.4f-run-1 hit exactly this and `run` died
# before wiring). Only mkdir when the dir is actually absent (a no-core profile).
[ -d "$TARGET/etc/rc2.d" ] || run mkdir -p "$TARGET/etc/rc2.d"
echo "+ emit_firstboot_hook $TARGET/etc/rc2.d/S16firstboot"
emit_firstboot_hook "$TARGET/etc/rc2.d/S16firstboot" || die "cannot write the first-boot rc2 hook"
run chmod 0744 "$TARGET/etc/rc2.d/S16firstboot"

# 1.1: no reframe tool and no /stand framing tools -- kbootset owns the boot store.
if [ "$INSTALL_LAYOUT" != 1.1 ]; then
# --- INSTALL updbootpart onto the target (W6-I; MEDIUM-STAGED since W5.5) ----
# The on-box boot-slice reframe tool -- the finisher for "kernel upgrade via a
# package": `updbootpart --backup` -> `pkgadd KERNBENCH` -> `updbootpart` reframes
# the UNI\0 boot slice from the freshly-landed /stand/unix, so the next cold boot
# runs the new kernel. Additive, exactly like S16firstboot above: NOT a package
# member, so it is invisible to the contents DB (pkgchk/altroot-attest unaffected)
# -- being COPIED from the medium rather than written by the driver changes
# nothing about that, because attestation is a function of what pkgadd RECORDED.
#
# ★ W5.5: IT COMES OFF THE MEDIUM NOW, and that is a floppy fix, not a tidy-up.
# Until this wave the body travelled inside THIS FILE as a quoted here-doc, and
# the 1991 SVR4 sh materializes every here-doc body into a real file under /tmp
# the moment it PARSES the script -- for the life of the shell, whether or not
# the function is ever called (W5 finding 1, proven on the box). On the miniroot
# /tmp IS the 880-block install floppy, whose 46 free blocks are also where the
# static pkgadd builds its packaging directory. 15,427 bytes of updbootpart is
# 16 of those 46 blocks, on every install since W6-I -- the real reason this
# floppy has been "six blocks from death" for three waves. build-install-iso.sh
# stages payload/updbootpart at $INST/updbootpart (byte-identity gated there),
# and the copy below costs the floppy nothing.
#
# core ships /usr/sbin, so it exists by now; guard the mkdir all the same (the
# miniroot 1991 mkdir -p is not idempotent on an existing leaf -- W5.4f).
[ -d "$TARGET/usr/sbin" ] || run mkdir -p "$TARGET/usr/sbin"
[ -f "$INST/updbootpart" ] || die "no updbootpart on the medium at $INST/updbootpart -- re-master with tools/build-install-iso.sh (W5.5 staged it there)"
run cp "$INST/updbootpart" "$TARGET/usr/sbin/updbootpart"
run chmod 0755 "$TARGET/usr/sbin/updbootpart"
msg "installed /usr/sbin/updbootpart from $INST/updbootpart (on-box boot-slice reframe tool; additive, not a package member)"

# --- LAY DOWN the /stand framing tools updbootpart needs (P5.4-FT) -----------
# updbootpart's reframe pipeline (its gate 5a) fails closed without
# /stand/boot1.boot and an executable local /stand/makeiblk. On M-RUN4b the
# KERN-package handoff on a fresh metal base-8 install died exactly there
# ("framed image is empty") until the pair was ferried by hand from the bench
# golden -- so their presence is now a DRIVER-GUARANTEED invariant, not
# contingent on what the package transplant happened to deliver. Staged on the
# media fingerprint-gated (build-install-iso.sh): boot1.boot is the 2.1
# original (1,024 B, sum -r 41892 -- untouched by the 2.1c patch, so core's
# copy IS the golden's), makeiblk is the 2.1c PATCHED build every golden runs
# and the metal reframe was proven with (14,924 B, sum -r 58483). The cp
# OVERWRITES any core-delivered 2.1 makeiblk with the golden-proven one --
# deterministic end state, exactly like the flags-based boot2.boot overwrite in
# section 6 (same class of package-member content touch: invisible to the
# contents-DB digest, which records what pkgadd DELIVERED, not the live bytes).
run cp "$INST/stand/boot1.boot" "$TARGET/stand/boot1.boot"
run chmod 0644 "$TARGET/stand/boot1.boot"
run cp "$INST/stand/makeiblk" "$TARGET/stand/makeiblk"
run chmod 0755 "$TARGET/stand/makeiblk"
msg "laid down /stand framing tools: boot1.boot (41892) + makeiblk (2.1c, 58483) -- updbootpart gate 5a satisfied on every fresh install"

fi	# INSTALL_LAYOUT 1.0: updbootpart + /stand framing

# --- LAY DOWN the syslog unit (P5.4 queue: base-8 ships none) ----------------
# A base-8 install carries core's /usr/sbin/syslogd BINARY (2.1, 22,368 B) but
# NO unit around it: no /etc/init.d/syslogd, no rc links, no /etc/syslog.conf,
# no /var/log -- so the box cannot log at all, and the inetd-throttle hunt
# (kerntools docs/inetd-telnet-throttle.md) proved how expensive that silence
# is. Lay down the complete 2.1c unit from the media (fingerprint-gated at
# staging), driver-written like S16firstboot/updbootpart/S99zen -- every file
# here is ADDITIVE (not a package member, invisible to pkgchk/altroot-attest)
# EXCEPT the daemon overwrite, which is the boot2.boot-class content touch:
# the 2.1c "major revisions" syslogd (22,728 B, sum -r 53154) replaces core's
# 2.1 copy so the installed unit is the exact combination the goldens run and
# the throttle doc validated end to end.
#   * /etc/init.d/syslogd is the ENABLED copy -- the vendor ships it dead (a
#     bare `exit` at line 8); the §5 enablement comments that line. The
#     transform happened HOST-SIDE at media staging (the miniroot has no sed);
#     the driver just copies. Fresh installs therefore log from day one.
#   * S70syslogd/K50syslogd are HARD LINKS to /etc/init.d/syslogd (one inode,
#     3 links -- the stock topology). Anyone editing the script later must
#     `cp` in place, never `mv`: mv would break the links and the edit would
#     work once and never again after a reboot (throttle doc §4).
#   * the eight /var/log stubs are created empty (syslogd appends to existing
#     files; the vendor patch ships them as zero-length stubs), and
#     /dev/conslog (c 25 0, mode 222) mirrors the vendor patch's own
#     "device node added to support syslogd". /dev/log is already a core member.
run cp "$INST/syslog/syslog.conf" "$TARGET/etc/syslog.conf"
run chmod 0444 "$TARGET/etc/syslog.conf"
[ -d "$TARGET/etc/init.d" ] || run mkdir -p "$TARGET/etc/init.d"
run cp "$INST/syslog/syslogd.init" "$TARGET/etc/init.d/syslogd"
run chmod 0544 "$TARGET/etc/init.d/syslogd"
[ -d "$TARGET/etc/rc2.d" ] || run mkdir -p "$TARGET/etc/rc2.d"
[ -d "$TARGET/etc/rc0.d" ] || run mkdir -p "$TARGET/etc/rc0.d"
run ln "$TARGET/etc/init.d/syslogd" "$TARGET/etc/rc2.d/S70syslogd"
run ln "$TARGET/etc/init.d/syslogd" "$TARGET/etc/rc0.d/K50syslogd"
run cp "$INST/syslog/syslogd" "$TARGET/usr/sbin/syslogd"
run chmod 0100 "$TARGET/usr/sbin/syslogd"
[ -d "$TARGET/var/log" ] || run mkdir -p "$TARGET/var/log"
run chmod 0755 "$TARGET/var/log"
# ★ NEVER `: > file` IN A LOOP ON THIS SHELL (bench-proven 2026-08-11).
# The miniroot's 1991 SVR4 /bin/sh performs a redirection on the NULL COMMAND
# only on the FIRST pass through a loop body. On iterations 2..N `: > file`
# returns rc=0, prints nothing, and CREATES NOTHING -- a create that LIES.
# Measured on the bench (matrix run 20260811-103107-cd, instrumented driver):
#     DIAG stub alert       rc=0 -> present     <- iteration 1
#     DIAG stub bus-errors  rc=0 -> ABSENT      <- iterations 2..8, every one
#     ... console/critical/kernel/news-urgent/notice/security all ABSENT
#     DIAG retry-cp <same 7 names> rc=0 -> present   (cp, same dir, same names)
# Straight-line `: >` is fine (three consecutive control creates in /tmp and
# /var/adm all succeeded in the same run) -- it is the LOOP that breaks it. So
# this is not the filesystem, not the names, not space, and not the a3091: an
# EXTERNAL command creating the very same paths a moment later works 7/7.
# `cp /dev/null` forks a real command, so the create happens every iteration.
# The `[ -f ]` re-check after it is deliberate: this defect class returns
# SUCCESS while doing nothing, so presence is asserted, never assumed.
for lf in alert bus-errors console critical kernel news-urgent notice security; do
	run cp /dev/null "$TARGET/var/log/$lf"
	[ -f "$TARGET/var/log/$lf" ] || die "created /var/log/$lf but it is not there -- refusing to ship a silently-empty syslog unit"
	run chmod 0644 "$TARGET/var/log/$lf"
done
[ -c "$TARGET/dev/conslog" ] || run mknod "$TARGET/dev/conslog" c 25 0
run chmod 0222 "$TARGET/dev/conslog"
msg "laid down the syslog unit (2.1c conf+daemon, init ENABLED, S70/K50 hard links, 8 /var/log stubs, /dev/conslog) -- fresh installs log from day one"

# --- LAY DOWN the zen0 (Z3660 native ethernet) bring-up (METAL-FIX.4) --------
# The installed metal kernel already contains z3660eth, but a base install ships
# only the STOCK a2065/aen0 inet userland -- inert on metal (no A2065 board), so a
# fresh metal install has NO working ethernet. Metal ethernet is interface zen0
# (cdevsw major 51, /dev/zen0 c 51 0 -- renumbered from 48 on 2026-07-30; media
# mastered from this tree REQUIRE 51-registering kernels, the P5.4 set), brought up
# by z3660net's proven
# `slink addaen /dev/zen0 zen0` + `ifconfig zen0 <LITERAL-IP> up -trailers` (SVR4.0
# -- NOT plumb, NOT uname -n). We lay that bring-up down as /etc/rc2.d/S99zen,
# DRIVER-WRITTEN + additive exactly like S16firstboot / updbootpart (NOT a package
# member; NEVER edits /etc/inet/network-config -- the hard rule). GUARDED on the
# profile's ethernet interface being zen0, so the bench a2065/aen0 path is untouched.
# The IP is the profile's FB_IP (never a hardcoded golden .39); zen0 profiles MUST
# carry one. /dev/zen0 is self-healed by S99zen's own mknod at first boot. NB: the
# zen0 LINK is metal-only-testable (no z3660eth under emulation) -- the laydown is
# bench-provable, and the actual traffic was PROVEN on metal by M-RUN3 (2026-07-24:
# zen0 UP, ping 3/3, bidirectional telnet, surviving 4 cold boots).
if [ "$FB_ETHER_IF" = zen0 ]; then
	# P-15 I2: the public flavor (FIRSTBOOT_DIALOG=y) may leave BOTH FB_IP and
	# FB_GATEWAY empty -- an address-less laydown the dialog's 8a re-point fills in;
	# zen0 stays down until it has an address. Every unattended profile keeps the
	# hard requirement.
	if [ "$FIRSTBOOT_DIALOG" = y ] && [ -z "$FB_IP" ]; then
		[ -z "$FB_GATEWAY" ] || die "profile $PROFILE_NAME sets FB_GATEWAY=$FB_GATEWAY but no FB_IP -- a route without an address"
		msg "zen0: no address in the profile -- the first-boot dialog asks for one (zen0 stays down until then)"
	else
		[ -n "$FB_IP" ] || die "profile $PROFILE_NAME sets FB_ETHER_IF=zen0 but FB_IP is empty -- the zen0 bring-up needs a LITERAL IP (never uname -n on SVR4.0)"
		[ -n "$FB_GATEWAY" ] || die "profile $PROFILE_NAME sets FB_ETHER_IF=zen0 but FB_GATEWAY is empty -- the zen0 bring-up writes a literal default route (W1: it was a hardcoded LAN gateway)"
	fi
	echo "+ emit_zen_hook $TARGET/etc/rc2.d/S99zen (zen0 @ ${FB_IP:-no address})"
	emit_zen_hook "$TARGET/etc/rc2.d/S99zen" || die "cannot write the zen0 bring-up hook /etc/rc2.d/S99zen"
	run chmod 0744 "$TARGET/etc/rc2.d/S99zen"
	msg "laid down /etc/rc2.d/S99zen (zen0 @ $FB_IP netmask $FB_NETMASK gw $FB_GATEWAY; additive, not a package member)"
	# P-3: the MAC reader S99zen's address-by-card step needs (/usr/amiga/bin/zenmac,
	# src/zenmac, cross-built by tools/build-zenmac.sh and staged on the medium by
	# build-install-iso.sh). Absent from an older medium it is only a WARNING: S99zen
	# then treats the MAC as unreadable, takes the table's default row (or FB_IP) and
	# says so on the console at every boot -- the box still comes up on the network.
	if [ -f "$INST/zenmac" ]; then
		run cp "$INST/zenmac" "$TARGET/usr/amiga/bin/zenmac"
		run chmod 0755 "$TARGET/usr/amiga/bin/zenmac"
		msg "installed /usr/amiga/bin/zenmac from $INST/zenmac (zen0 MAC reader for S99zen's address-by-card table; additive)"
	else
		msg "WARNING: no $INST/zenmac on this medium -- S99zen cannot read the card MAC (address-by-card falls back; re-master with tools/build-install-iso.sh)"
	fi
else
	# S3-31: a disk that installs the z3660eth module gets the zen0 bring-up too, on
	# both lines, beside the profile's own interface: at its own FB_ZEN_IP /
	# FB_ZEN_NETMASK (default FB_NETMASK) / FB_ZEN_GATEWAY (optional), or address-less
	# (left down) without FB_ZEN_IP -- never the same address on two interfaces
	case " $KERNEL_MODPKGS " in
	*" z3660eth-k"*)
		[ -z "$FB_ZEN_IP" ] || [ "$FB_ZEN_IP" != "$FB_IP" ] \
			|| die "profile $PROFILE_NAME: FB_ZEN_IP=$FB_ZEN_IP is FB_IP, $FB_ETHER_IF's address -- zen0 needs its own"
		echo "+ emit_zen_hook $TARGET/etc/rc2.d/S99zen (z3660eth module; zen0 @ ${FB_ZEN_IP:-no address})"
		( FB_IP="$FB_ZEN_IP"; FB_NETMASK="${FB_ZEN_NETMASK:-$FB_NETMASK}"; FB_GATEWAY="$FB_ZEN_GATEWAY"
		  emit_zen_hook "$TARGET/etc/rc2.d/S99zen" ) || die "cannot write the zen0 bring-up hook /etc/rc2.d/S99zen"
		run chmod 0744 "$TARGET/etc/rc2.d/S99zen"
		msg "laid down /etc/rc2.d/S99zen for the z3660eth module (zen0 @ ${FB_ZEN_IP:-no address -- left down}; $FB_ETHER_IF stays as it is)"
		;;
	*)	msg "ethernet interface is '$FB_ETHER_IF' (not zen0) -- stock aen0 userland; no zen0 bring-up laid down" ;;
	esac
fi

# --- LAY DOWN the monitor-switch bits (P-8, /dev/monsw) -----------------------
# The Z3660 flavors carry what amix-kerntools' build-image.sh section b3b lays on
# a desktop golden (kerntools docs/monsw.md, "What amix-installng profiles must
# carry"): the rc step /etc/rc2.d/S20monsw (755), the tool /usr/sbin/monswctl
# (755), the interface header /usr/include/sys/monsw.h (644), the node
# /dev/monsw c 52 0, and /etc/monsw = the profile's MONSW value (644). The three
# files ride the medium under $INST/monsw, staged by build-install-iso.sh ONLY
# after it checked monswctl against kerntools' MANIFEST sha and the header
# against its pin -- so the bytes here are the pinned ones. DRIVER-WRITTEN and
# additive like S99zen (not package members, invisible to the attestation). A
# The major is 52 (port driver line b9992ed; 50 is the stock SAD STREAMS row).
# kernel without the monsw driver boots this unchanged: S20monsw prints one
# console line and the boot goes on. MONSW empty or "none" lays down nothing.
if [ -n "$MONSW" ] && [ "$MONSW" != none ]; then
	for mf in S20monsw monswctl monsw.h; do
		[ -f "$INST/monsw/$mf" ] || die "profile $PROFILE_NAME sets MONSW=$MONSW but this medium has no $INST/monsw/$mf (re-master with tools/build-install-iso.sh)"
	done
	[ -d "$TARGET/etc/rc2.d" ] || run mkdir -p "$TARGET/etc/rc2.d"
	run cp "$INST/monsw/S20monsw" "$TARGET/etc/rc2.d/S20monsw"
	run chmod 0755 "$TARGET/etc/rc2.d/S20monsw"
	[ -d "$TARGET/usr/sbin" ] || run mkdir -p "$TARGET/usr/sbin"
	run cp "$INST/monsw/monswctl" "$TARGET/usr/sbin/monswctl"
	run chmod 0755 "$TARGET/usr/sbin/monswctl"
	[ -d "$TARGET/usr/include/sys" ] || run mkdir -p "$TARGET/usr/include/sys"
	run chmod 0755 "$TARGET/usr/include/sys"
	run cp "$INST/monsw/monsw.h" "$TARGET/usr/include/sys/monsw.h"
	run chmod 0644 "$TARGET/usr/include/sys/monsw.h"
	[ -c "$TARGET/dev/monsw" ] || run mknod "$TARGET/dev/monsw" c 52 0
	# 0644 root, as the Z3660 station's MG5 kit: monswctl and the X server run as
	# root, and a world-writable switch node would let any user flip the monitor
	# (mknod alone takes the miniroot's umask and leaves it crw-rw-rw-).
	run chmod 0644 "$TARGET/dev/monsw"
	echo "$MONSW" > "$TARGET/etc/monsw" || die "cannot write $TARGET/etc/monsw"
	[ -f "$TARGET/etc/monsw" ] || die "wrote $TARGET/etc/monsw but it is not there"
	run chmod 0644 "$TARGET/etc/monsw"
	msg "laid down the monitor switch (P-8): /etc/monsw=$MONSW, S20monsw, /usr/sbin/monswctl, sys/monsw.h, /dev/monsw c 52 0 (additive)"
else
	msg "monitor switch: none (MONSW='$MONSW') -- no /dev/monsw bits laid down"
fi

# --- LAY DOWN the RTG X11 kit (K1, X11KIT=rtg) ---------------------------------
# The Z3660 RTG desktop exactly as the Z3660 station installed it on metal (MG5/
# MG9, the maintainer's notes): the Xzz9000 server, the
# startx-rtg launcher, rtg-kbdback (RT-10: gives the console keyboard back after
# a killed server) and the zz9k_monsw fallback switch in /opt/amix/bin (755),
# root's session file /.xinitrc-rtg (644), the ZZ9000 node /dev/zz9000 c 49 0, and
# /usr/X/bin on /etc/profile's PATH (the session file starts olwm/xterm by name).
# /etc/rtg-monswitch is never written: under P-8 /dev/monsw owns the line. The five
# files ride the medium under $INST/x11kit, staged by build-install-iso.sh only
# after each hashed to its pin. Driver-written and additive, like S99zen and the
# monsw bits -- EXCEPT the /etc/profile line, a one-line append to a core member
# (the same edit MG5 made; the attestation is contents-DB-derived and does not see
# it). A fresh install writes it once, so no guard is needed -- and the miniroot
# has no grep to make one with.
if [ "$X11KIT" = rtg ]; then
	for xf in Xzz9000 rtg-kbdback startx-rtg zz9k_monsw xinitrc-rtg; do
		[ -f "$INST/x11kit/$xf" ] || die "profile $PROFILE_NAME sets X11KIT=rtg but this medium has no $INST/x11kit/$xf (re-master with tools/build-install-iso.sh)"
	done
	[ -f "$TARGET/etc/profile" ] || die "X11KIT=rtg: the target has no /etc/profile to put /usr/X/bin on (is core installed?)"
	[ -d "$TARGET/opt/amix/bin" ] || run mkdir -p "$TARGET/opt/amix/bin"
	# the miniroot's umask is 0: a mkdir -p'd dir is 0777, and this one is on PATH.
	run chmod 0755 "$TARGET/opt/amix" "$TARGET/opt/amix/bin"
	run cp "$INST/x11kit/Xzz9000" "$TARGET/opt/amix/bin/Xzz9000"
	run chmod 0755 "$TARGET/opt/amix/bin/Xzz9000"
	run cp "$INST/x11kit/startx-rtg" "$TARGET/opt/amix/bin/startx-rtg"
	run chmod 0755 "$TARGET/opt/amix/bin/startx-rtg"
	run cp "$INST/x11kit/rtg-kbdback" "$TARGET/opt/amix/bin/rtg-kbdback"
	run chmod 0755 "$TARGET/opt/amix/bin/rtg-kbdback"
	run cp "$INST/x11kit/zz9k_monsw" "$TARGET/opt/amix/bin/zz9k_monsw"
	run chmod 0755 "$TARGET/opt/amix/bin/zz9k_monsw"
	run cp "$INST/x11kit/xinitrc-rtg" "$TARGET/.xinitrc-rtg"
	run chmod 0644 "$TARGET/.xinitrc-rtg"
	# Cut 4: every copy proven against the medium (which build-install-iso.sh staged
	# only after each file matched the RTG kit's KIT.sha256). No sha256 on the
	# miniroot: sum -r of the target file must equal the medium's. A plain for loop
	# (not redirect-fed), so die stops the install.
	XSUM="$INST/bin/sum"
	[ -x "$XSUM" ] || die "X11KIT=rtg: no SVR4 sum at $XSUM to verify the kit"
	for xf in Xzz9000 rtg-kbdback startx-rtg zz9k_monsw xinitrc-rtg; do
		case "$xf" in
			xinitrc-rtg) xd="$TARGET/.xinitrc-rtg" ;;
			*)           xd="$TARGET/opt/amix/bin/$xf" ;;
		esac
		[ -s "$xd" ] || die "X11KIT=rtg: $xd is empty after cp"
		xs_want=`"$XSUM" -r "$INST/x11kit/$xf"`; xs_want=`expr "$xs_want" : '\([0-9]*\)'`
		xs_got=`"$XSUM" -r "$xd"`; xs_got=`expr "$xs_got" : '\([0-9]*\)'`
		[ -n "$xs_want" ] && [ "$xs_got" = "$xs_want" ] || die "X11KIT=rtg: $xd sum -r $xs_got != medium $xs_want"
	done
	run rm -f "$TARGET/etc/rtg-monswitch"
	[ -c "$TARGET/dev/zz9000" ] || run mknod "$TARGET/dev/zz9000" c 49 0
	run chmod 0644 "$TARGET/dev/zz9000"
	echo 'PATH=$PATH:/usr/X/bin; export PATH' >> "$TARGET/etc/profile" || die "cannot append /usr/X/bin to $TARGET/etc/profile"
	msg "laid down the RTG X11 kit (sum -r verified): /opt/amix/bin/{Xzz9000,rtg-kbdback,startx-rtg,zz9k_monsw}, /.xinitrc-rtg, /dev/zz9000 c 49 0, /usr/X/bin on /etc/profile PATH (additive; /etc/rtg-monswitch absent)"
else
	msg "RTG X11 kit: none (X11KIT='$X11KIT')"
fi

# --- LAY DOWN the battery-clock setclk (IN-rtc, RTC=setclk) --------------------
# The stock /usr/amiga/bin/setclk -- run at EVERY boot by /etc/sysinit, before rc2
# and anything that stamps times -- reads the year as %02d, so from 2000 on it hands
# date(1) "1YY" and the boot says "date: bad conversion" and keeps 1977/the root's
# time. Ours (tools/build-setclk.sh: the stock source + src/setclk/setclk-y2k.patch)
# passes a 4-digit year, leaves the clock alone for an RTC outside 1992..2037 (a clock
# set back past root's password age makes every login "expired", grimoire quirk 20)
# and prints one console line either way; it never writes the RTC. It is copied ONTO
# the stock file: cp into an existing file keeps its inode, owner and group
# (amiga:amiga, as stock -- the miniroot has no chown), and /sbin/setclk and
# /etc/setclk are symlinks to it already. /etc/clkzone names the zone the RTC keeps.
# RTC=none leaves the stock tool, the clock and /etc/clkzone exactly as installed.
if [ "$RTC" = setclk ]; then
	[ -f "$INST/setclk" ] || die "profile $PROFILE_NAME has RTC=setclk but this medium has no $INST/setclk (re-master with tools/build-install-iso.sh, or set RTC=none)"
	[ -f "$TARGET/usr/amiga/bin/setclk" ] || die "RTC=setclk: the target has no stock /usr/amiga/bin/setclk to replace (is core installed?)"
	run cp "$INST/setclk" "$TARGET/usr/amiga/bin/setclk"
	run chmod 0755 "$TARGET/usr/amiga/bin/setclk"
	echo "$FB_CLKZONE" > "$TARGET/etc/clkzone" || die "cannot write $TARGET/etc/clkzone"
	[ -f "$TARGET/etc/clkzone" ] || die "wrote $TARGET/etc/clkzone but it is not there"
	run chmod 0644 "$TARGET/etc/clkzone"
	msg "laid down the Y2K battery-clock setclk (1992..2037 gate) over /usr/amiga/bin/setclk; /etc/clkzone=$FB_CLKZONE"
else
	msg "battery clock: RTC=none -- stock setclk and clock left alone"
fi

# --- LAY DOWN the regenerated zone files (IN-rtc-2, TZFILES=tzdata) -------------
# The 1991 files under /usr/lib/locale/TZ carry 1991 rules (EET/MET/WET end summer
# time on the last Sunday of September, the US zones keep the pre-2007 rule). The
# medium's $INST/tz holds every one of them regenerated from current tzdata in the
# same 1991 layout, same names (tools/build-tzfile.py; MANIFEST = "sha256 size name").
# Each is REMOVED first, then copied: the stock set hard-links names whose meanings
# have since parted (EST = US/East-Indiana, CET = MET), so every name becomes its own
# file; sum -r of the copy must equal the medium's. The loop runs in a subshell on
# the miniroot sh, so it only RECORDS (ok/fail files) and the parent decides.
if [ "$TZFILES" = tzdata ]; then
	[ -f "$INST/tz/MANIFEST" ] || die "profile $PROFILE_NAME has TZFILES=tzdata but this medium has no $INST/tz/MANIFEST (re-master with tools/build-install-iso.sh, or set TZFILES=stock)"
	[ -d "$TARGET/usr/lib/locale/TZ" ] || die "TZFILES=tzdata: the target has no /usr/lib/locale/TZ (is core installed?)"
	TZSUM="$INST/bin/sum"
	[ -x "$TZSUM" ] || die "TZFILES=tzdata: no SVR4 sum at $TZSUM to verify the zone copies"
	tzok="$TARGET/tmp/.tzok.$$"
	tzfail="$TARGET/tmp/.tzfail.$$"
	: > "$tzok"
	: > "$tzfail"
	while read tz_sha tz_size tz_name; do
		[ -n "$tz_name" ] || continue
		tz_src="$INST/tz/$tz_name"; tz_dst="$TARGET/usr/lib/locale/TZ/$tz_name"
		tz_dir=`expr "$tz_name" : '\(.*\)/'`
		if [ ! -s "$tz_src" ] || { [ -n "$tz_dir" ] && [ ! -d "$TARGET/usr/lib/locale/TZ/$tz_dir" ]; }; then
			echo "$tz_name" >> "$tzfail"; continue
		fi
		rm -f "$tz_dst"
		if cp "$tz_src" "$tz_dst" && [ -s "$tz_dst" ]; then
			set -- `"$TZSUM" -r "$tz_src"`; tz_want=$1
			set -- `"$TZSUM" -r "$tz_dst"`; tz_got=$1
			if [ "$tz_got" = "$tz_want" ]; then
				chmod 0644 "$tz_dst"; echo "$tz_name" >> "$tzok"
			else
				echo "$tz_name" >> "$tzfail"
			fi
		else
			echo "$tz_name" >> "$tzfail"
		fi
	done < "$INST/tz/MANIFEST"
	[ -s "$tzfail" ] && die "zone files FAILED to lay down: `cat "$tzfail"`"
	tzn=`count_tokens "$tzok"`
	[ "$tzn" -gt 0 ] || die "laid down ZERO zone files ($INST/tz/MANIFEST empty or unparseable)"
	rm -f "$tzok" "$tzfail"
	msg "laid down $tzn regenerated zone files (current tzdata, 1991 layout) over /usr/lib/locale/TZ"
else
	msg "zone files: TZFILES=stock -- the 1991 /usr/lib/locale/TZ left alone"
fi

# --- BAKE THE KEYMAP ONTO THE TARGET (stock step, restored in W1) ------------
# The stock installer's LAST act before halting was to persist the keyboard the
# operator picked at the very start:
#     rm -f /mnt/usr/amiga/lib/kmap/default.kmap
#     if [ "$KMAP" != "" ]; then
#         ln /mnt/usr/amiga/lib/kmap/$KMAP /mnt/usr/amiga/lib/kmap/default.kmap
#     fi
# (/etc/id_kmap `unset KMAP` for the American map -- "usa" means link NOTHING,
# the map is compiled in.) /etc/sysinit on the installed system loads
# default.kmap on every boot, so this hard link IS the persistence mechanism.
# Our driver dropped the step entirely: research found NO default.kmap on any
# golden, i.e. every NG-installed box has been running the compiled-in American
# map regardless of what anyone believed. FB_KMAP restores it, with the same
# empty/usa == none semantics. The kmap files are CORE members (core ships
# /usr/amiga/lib/kmap/{cdn,ch1,ch2,d,dk,e,f,gb,i,n,s,usa,usa0,usa1,usa2}), so on
# any install that has a target root at all the named map must exist -- a missing
# one is a profile error and fails closed. HARD link, exactly like stock (not a
# symlink): /etc/sysinit reads the file, and a dangling symlink would be silent.
KMAPDIR="$TARGET/usr/amiga/lib/kmap"
if [ -n "$FB_KMAP" ] && [ "$FB_KMAP" != usa ]; then
	[ -d "$KMAPDIR" ] || die "profile $PROFILE_NAME sets FB_KMAP=$FB_KMAP but the target has no $KMAPDIR (is core installed?)"
	[ -f "$KMAPDIR/$FB_KMAP" ] || die "profile $PROFILE_NAME sets FB_KMAP=$FB_KMAP but $KMAPDIR/$FB_KMAP does not exist -- valid stock maps are cdn ch1 ch2 d dk e f gb i n s usa usa0 usa1 usa2"
	run rm -f "$KMAPDIR/default.kmap"
	run ln "$KMAPDIR/$FB_KMAP" "$KMAPDIR/default.kmap"
	msg "baked keymap $FB_KMAP (hard link $KMAPDIR/default.kmap; /etc/sysinit loads it every boot)"
else
	if [ -d "$KMAPDIR" ]; then
		run rm -f "$KMAPDIR/default.kmap"
	fi
	msg "keymap: none baked (FB_KMAP='$FB_KMAP') -- the compiled-in American map, exactly as stock did for 'usa'"
fi

# --- PRESEED /lost+found (stock step, restored in W1) ------------------------
# Stock created 100 entries in the root filesystem's lost+found and immediately
# removed them:
#     for i in 0 1 2 3 4 5 6 7 8 9; do
#         for j in 0 1 2 3 4 5 6 7 8 9; do  > /mnt/lost+found/$i$j; done
#     done
#     /mnt/usr/bin/rm /mnt/lost+found/*
# Neither an s5 nor a ufs directory ever SHRINKS, so this permanently grows
# lost+found to hold at least 100 slots -- which is what lets fsck reconnect
# orphaned inodes on a full filesystem, when it cannot allocate a new directory
# block. Our driver dropped the step; no NG-installed box has ever had a usable
# lost+found. It is a DIRECTORY, not a package member, so it is invisible to the
# contents DB (altroot-attest / pkgchk unaffected -- the same additive class as
# the log). BOTH mkfs back-ends already create the directory (`lost+found` is a
# literal in mkfs_ufs's own binary, and the 1991-installed ufs golden has one);
# mkdir only covers the odd case where it is absent (the 1991 mkdir is not
# idempotent on an existing leaf -- W5.4f).
LOSTFOUND="$TARGET/lost+found"
if [ -d "$LOSTFOUND" ]; then
	msg "preseeding $LOSTFOUND with 100 directory slots (stock step; fsck needs them)"
else
	run mkdir "$LOSTFOUND"
	run chmod 0777 "$LOSTFOUND"
	msg "created + preseeding $LOSTFOUND with 100 directory slots (stock step; fsck needs them)"
fi
# `cp /dev/null`, NOT `: >` -- same shell defect as the /var/log stubs above:
# a null-command redirection inside a loop fires only on the first iteration, so
# `: >` here created exactly ONE slot and silently skipped 99 (the preseed was a
# no-op; measured lost+found stayed at its mkfs 38 slots). An external command
# creates every time.
for i in 0 1 2 3 4 5 6 7 8 9; do
	for j in 0 1 2 3 4 5 6 7 8 9; do
		cp /dev/null "$LOSTFOUND/$i$j" || die "cannot preseed $LOSTFOUND/$i$j"
	done
done
# ASSERT the preseed really happened -- the defect this replaces returned success
# while doing nothing, so check a slot from the LAST iteration, not the first.
[ -f "$LOSTFOUND/99" ] || die "lost+found preseed created nothing (slot 99 absent) -- fsck would have no room to reconnect orphans"
# Remove exactly what we created (stock used a `*` glob; naming the entries keeps
# anything else that might be in there safe and keeps the echo short).
for i in 0 1 2 3 4 5 6 7 8 9; do
	for j in 0 1 2 3 4 5 6 7 8 9; do
		rm -f "$LOSTFOUND/$i$j" || die "cannot clear the $LOSTFOUND preseed"
	done
done
msg "lost+found preseeded (100 slots created + removed; the directory keeps the space)"

# --- THE sysinit DIALOG SLOT: disarm it, or make it OURS (W5) ----------------
# /etc/sysinit runs `sh /usr/amiga/bin/system.setup` iff that file is EXECUTABLE.
# Two mutually exclusive end states, chosen by the profile:
#
#   FIRSTBOOT_DIALOG=n (default, every canned profile)  -- `chmod -x`, the stock
#     dialog's OWN once-only lever, applied non-interactively. The box configures
#     itself from firstboot.conf and never asks anything. Byte-for-byte what the
#     driver has always done.
#   FIRSTBOOT_DIALOG=y (what setup.sh writes for an INTERACTIVE install) -- our
#     first-boot dialog is written INTO that slot and left executable. It collects
#     identity/network/password answers on the console at the next boot, writes
#     them into firstboot.conf, and disarms itself with the same `chmod -x` at the
#     clean end of its summary loop. S16firstboot still applies every mechanical
#     step in BOTH cases -- the dialog never writes vfstab/hosts/devices itself.
#
# The wart is recorded, not hidden: writing our body over a core member diverges
# the realized file from the contents-DB record, so `pkgchk` will call
# /usr/amiga/bin/system.setup modified. The installed-tree DIGEST does not move --
# altroot-attest is a pure function of what pkgadd RECORDED -- and this is the same
# accepted class as the /etc/shadow and /etc/TIMEZONE edits first-boot performs.
SETUP="$TARGET/usr/amiga/bin/system.setup"
if [ -f "$SETUP" ]; then
	if [ "$FIRSTBOOT_DIALOG" = y ]; then
		echo "+ emit_system_setup $SETUP"
		emit_system_setup "$SETUP" || die "cannot write the first-boot dialog to $SETUP"
		run chmod 0755 "$SETUP"
		msg "ARMED the first-boot configuration dialog in the stock sysinit slot (system.setup, executable)"
		msg "  NOTE: the dialog REPLACES a core package member's body -- digest-neutral, visible to pkgchk (recorded wart)"
	else
		run chmod 0644 "$SETUP"
		msg "disarmed the stock sysinit first-boot dialog (chmod -x system.setup; its own once-only mechanism)"
	fi
else
	if [ "$FIRSTBOOT_DIALOG" = y ]; then
		die "profile $PROFILE_NAME sets FIRSTBOOT_DIALOG=y but the target has no $SETUP -- refusing to invent the sysinit slot"
	fi
	warn "stock /usr/amiga/bin/system.setup absent on the target -- no dialog to disarm (unexpected for a core install)"
fi
msg "first-boot armed + wired (rc2.d/S16firstboot; nodename=$FB_NODENAME tz=$FB_TZNUM dialog=$FIRSTBOOT_DIALOG)"

# ===========================================================================
# 10. FINAL fsck + SUMMARY
# ===========================================================================
run sync

# --- CLOSE THE INSTALL LOG ---------------------------------------------------
# The log FILE lives on the filesystem we are about to unmount, so this is where
# it ends -- symmetric with the pre-mount window the opening marker declares.
# Everything after this point (the unmount, the final fsck, the summary) is
# console-only and is named here so a reader of the log knows what is missing
# rather than wondering. $RUNOUT goes too: it is a scratch file, not an artifact.
logline "--------------------------------------------------------------"
logline "$PROG: base OS installed ($npkgs package(s)); contents DB checked;"
logline "$PROG: boot chain verified on-target; first-boot armed + wired."
logline "$PROG: THE LOG ENDS HERE. The final sync/unmount, the post-unmount"
logline "$PROG:   fsck of $ROOT_RAW and the INSTALL COMPLETE summary all run"
logline "$PROG:   with $TARGET unmounted, so they are console-only."
logline "--------------------------------------------------------------"
INSTALL_LOG_PATH="$LOGFILE"
rm -f "$RUNOUT"
LOGFILE=
RUNOUT=

# The RAW arm's apkg cache and raw.conf live in the target's /tmp; they are done.
rm -rf "$TARGET/tmp/apkgcache" "$TARGET/tmp/raw.conf"
msg "unmounting target and running a final fsck..."
/etc/umount "$TARGET" 2>/dev/null || umount "$TARGET" 2>/dev/null || warn "umount $TARGET returned nonzero"
# Two literal arms, not `fsck_${TARGET_ROOT_FSTYPE}` -- same reason as the mkfs
# above: the allowlist audit resolves first words, and a composed program name is
# one it cannot resolve. On the ufs path this is the ONLY fsck of the run (the
# pre-mount one is s5-only, see section 2), and it is the right place for it: the
# filesystem has been synced and UNMOUNTED, so the raw node is now the correct
# one to read it through.
if [ "$TARGET_ROOT_FSTYPE" = ufs ]; then
	run /bin/fsck_ufs "$ROOT_RAW"
else
	run /bin/fsck_s5 "$ROOT_RAW"
fi

echo
msg "=============================================================="
msg " INSTALL COMPLETE ($PROFILE_NAME)"
if [ "$SOURCE_KIND" = raw ]; then
	msg "   packages installed : $npkgs (see $ORDER) via apkg SRC_RAW ($SRC_RAW_DEV)"
else
	msg "   packages installed : $npkgs (see $ORDER) via pkgadd -R (cdfs $CD_SPEC)"
fi
if [ "$INSTALL_ATTESTED" = n ]; then
	msg "   package set        : $INSTALL_SET -- unattested selection (digest gate waived)"
else
	msg "   package set        : $INSTALL_SET (attested -- a reference digest exists)"
fi
msg "   root filesystem    : $TARGET_ROOT_FSTYPE on $ROOT_BLK ($TARGET_BUILD_MODE)"
msg "   contents DB        : integrity-checked (contents-fsck, clean)"
msg "   apkg client        : /etc/apkg.conf -> $FB_REPO_URL"
if [ "$INSTALL_LAYOUT" = 1.1 ]; then
	msg "   layout             : 1.1 (store s$TARGET_BOOT_SLICE ${L11_STORE_MB} MiB, store-id $L11_STORE_ID)"
	msg "   kernel             : $KERNEL_KPKG (apkg 0.3 kernel space, record /var/apkg/kpkg)"
	[ "$L11_KMOD" = y ] && msg "   modules            : modtools (dlm sysinit line checked)$L11_MODS"
	msg "   boot store         : pristine generation committed + kbootset check clean"
	msg "   /stand/unix        : removed; /etc/rc2.d/S01kbnamelist writes the booted namelist"
else
	msg "   boot chain         : verified on-target ($KERNEL_BREL_SUMR brel)"
	msg "   /stand/boot2.boot  : flags-based ($BOOT2_ID...)"
	msg "   /stand framing     : boot1.boot 41892 + makeiblk 58483 (updbootpart-ready)"
fi
msg "   syslog             : unit laid down ENABLED (2.1c; S70/K50 links, /var/log)"
msg "   keymap             : ${FB_KMAP:-none} (default.kmap hard link; empty/usa = compiled-in American)"
msg "   lost+found         : preseeded with 100 slots (stock step)"
msg "   install log        : $INSTALL_LOG_PATH  (= /var/adm/install.log on the installed system)"
if [ "$FIRSTBOOT_DIALOG" = y ]; then
	msg "   first-boot         : armed + wired (rc2.d/S16firstboot) + the CONFIGURATION DIALOG in the sysinit slot"
else
	msg "   first-boot         : armed + wired (rc2.d/S16firstboot; stock dialog disarmed)"
fi
msg "   next: halt (/etc/uadmin 2 0), remove the install kernel/CD, boot the target disk (c${ID}d0)."
msg "=============================================================="
exit 0
