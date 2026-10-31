#!/bin/sh
# firstboot.sh -- runs ONCE on the freshly-installed target's first boot, to
# bake in the machine identity the interactive stock first-boot dialog would
# otherwise ask for. Installed by src/installer/install.sh into
# /var/adm/firstboot/ and driven off the PENDING marker there.
#
# PRE-POSIX SVR4 /bin/sh SYNTAX rules (same as install.sh): no $(...), no
# `export VAR=val`, no $(( )), no [[ ]], no `local` -- installer-selftest.py
# audit A greps this file for them too.
#
# TOOL AVAILABILITY DIFFERS FROM install.sh. This script runs on the FULLY
# INSTALLED target (core + base already transplanted), NOT on the thin install
# miniroot -- so the complete SVR4 userland is present. It deliberately uses
# `sed` and `uname`, which the miniroot lacks but every installed Amix carries
# (this is the proven network-ready from-scratch-base recipe, hdf/README). The
# selftest's miniroot-tool allowlist audit therefore carries a documented,
# per-script exception for exactly those target-side tools (see FIRSTBOOT_EXTRA
# in installer-selftest.py); install.sh gets NO such exception.
#
# WHAT IT DOES (from the network-ready from-scratch-base recipe, hdf/README):
#   nodename, timezone (the profile's FB_TZ zone; US/Eastern = index 47), root
#   password, /etc/vfstab for the real controller/slice, and /dev regeneration
#   via /usr/amiga/lib/atdevs.
#
# TWO HARD RULES (both learned the hard way -- see hdf/README):
#   * NEVER touch /etc/inet/network-config. The shipped file brings aen0 up via
#     `ifconfig aen0 `uname -n`` resolving through /etc/inet/hosts; editing it
#     is what broke networking on the 2026-07-13 base. We bake ONLY the hosts
#     entry (so `uname -n` resolves to the box's IP) + pw + CONSOLE.
#   * NEVER set the clock forward. Amix's RTC/`lastchg` aging trap makes a
#     future date poison account aging. We leave the clock alone.
#
# Some target file locations (nodename store, the Amix timezone index file) are
# SVR4-conventional here and confirmed on-box in W5.4; each is flagged.

FBDIR=/var/adm/firstboot
CONF="$FBDIR/firstboot.conf"
MARK="$FBDIR/PENDING"
DIALOG_DONE="$FBDIR/DIALOG-DONE"
# The state dir is ROOT'S ALONE (P-15, 2026-10-03). Installs before that fix laid it
# 0777 with 0666 files -- any local user could then re-create PENDING and have this
# script, run as root by S16firstboot, source a planted firstboot.conf. Tighten it on
# every run, so a disk minted before the fix is closed at its own first boot.
chmod 700 "$FBDIR" 2>/dev/null
chmod 600 "$CONF" "$MARK" "$DIALOG_DONE" "$FBDIR/root.shadow" 2>/dev/null

# ---------------------------------------------------------------------------
# ENTRY POINTS
# ---------------------------------------------------------------------------
# `firstboot.sh --dialog`  -- the first-boot CONFIGURATION DIALOG, run from the
#      stock sysinit slot by the three-line /usr/amiga/bin/system.setup stub the
#      driver writes when a profile says FIRSTBOOT_DIALOG=y. It COLLECTS answers
#      into firstboot.conf (and performs the live stock actions), then disarms
#      the stub. It applies nothing mechanical -- that is the other half's job,
#      below, in both tiers.
# `firstboot.sh`           -- the APPLY half, run from /etc/rc2.d/S16firstboot.

# ===========================================================================
# THE FIRST-BOOT CONFIGURATION DIALOG  (entry point: `firstboot.sh --dialog`)
# ===========================================================================
# The Amiga UNIX first-boot configuration dialog (installer-NG W5). It is reached
# through the STOCK system.setup slot: /etc/sysinit runs
# `sh /usr/amiga/bin/system.setup` iff that file is executable, on /dev/syscon
# (inittab: `S2::sysinit:/etc/sysinit </dev/syscon >/dev/syscon 2>&1`), BEFORE run
# level 2, and the file it finds there is a three-line stub that execs THIS file
# with `--dialog`. So the dialog owns the console before any rc2 script runs, and
# its answers are already on disk when /etc/rc2.d/S16firstboot fires later in the
# same boot. `chmod -x` on THE STUB is the once-only disarm, exactly as stock's
# own dialog ended.
#
# ===========================================================================
# TWO-STAGE: THIS COLLECTS, S16firstboot APPLIES (plan v3 section 3)
# ===========================================================================
# This script does TWO kinds of thing and nothing else:
#
#   1. the LIVE stock actions that cannot be deferred -- `uname -S`, the stock
#      /usr/amiga/etc/TZ zone menu, `passwd`/`passwdall`, `amixmkuser`, the A2024
#      relink, `amixcolorx`, `amixnews`;
#   2. it writes every answer it COLLECTED into /var/adm/firstboot/firstboot.conf.
#
# Everything MECHANICAL -- /etc/nodename, /etc/TIMEZONE, /etc/vfstab, the
# /etc/inet/hosts entries, /dev regeneration, the rc2 laydowns, the resolver --
# is applied by ONE path -- the OTHER half of this same file, driven from
# /etc/rc2.d/S16firstboot. That is true in BOTH tiers: an unattended install ships
# firstboot.conf pre-filled and never arms this dialog, an interactive install
# arms it and the conf gets the operator's answers first. One application path,
# one set of variables, no drift.
#
# ===========================================================================
# THE RESILIENCE CONTRACT (plan v3 section 3 -- the security guarantees hang on it)
# ===========================================================================
#   * `chmod -x` fires ONLY at the clean exit of the summary loop (stock's own
#     convention -- its very last act). An interruption, a power cycle or an EOF
#     therefore leaves the stub executable and the WHOLE dialog runs again at the
#     next boot. There is no half-disarmed state.
#   * Ctrl-C is TRAPPED and re-asks the question. It never exits, so it can never
#     exit un-armed. EOF on the console DOES exit -- armed -- because a console
#     that cannot be read would otherwise spin forever and hang the boot.
#   * The FORCED ROOT PASSWORD is that contract: the dialog re-arms until the
#     password step has actually completed (`passwd` returned 0). A run that could
#     not set it says so, loudly, and leaves itself armed.
#   * Every write is idempotent or duplicate-guarded: the conf writer strips its
#     own previous block before appending a new one, so a re-run can never
#     accumulate keys, and /etc/inet/* is not touched here at all (that is S16's).
#   * If this dialog never completes, S16 still applies the MECHANICAL keys from
#     the profile-written conf, so the box boots healthy, and PENDING stays -- the
#     next boot's dialog answers are applied by the next boot's S16.
#
# ===========================================================================
# PRE-POSIX SVR4 /bin/sh (the installed box's sh is the same 1991 shell)
# ===========================================================================
#   * NO $(...)  -- use `backticks`      * NO $(( ))  -- arithmetic is `expr`
#   * NO [[ ]]   -- test with [ ]        * NO `local`, NO arrays, NO `set -- ` on
#     an empty list (it is a NO-OP on $@ there, not a clear -- always guard it)
#   * NO `export VAR=val` -- write VAR=val; export VAR
#   * ★ NEVER `: > file` inside a loop (the null-command redirection fires only on
#     the first pass through a loop body on this shell) -- use `cp /dev/null`.
# It runs on the FULLY INSTALLED target, so unlike the miniroot driver it may use
# sed/ed/ksh/passwd/useradd/date/grep -- installer-selftest audit Z scans it under
# the TARGET allowlist, never the miniroot one.
#
# ===========================================================================
# WORDING
# ===========================================================================
# Stock order, stock words. The sources are the recovered stock scripts:
# /usr/amiga/bin/system.setup, /usr/amiga/lib/{amixnode,amixhosts,amixdate},
# /usr/amiga/bin/passwdall, /usr/amiga/lib/amixmkuser. Where a question is OURS
# (network, syslog, root-telnet) it uses the same idiom: `echo "...? [default] \c"`
# + `read`, y/n as case globs, defaults in brackets. Deviations from stock, all
# deliberate and all recorded in docs/installer.md:
#   * NO date/time question. The clock is never set forward on this platform (the
#     RTC-1978 / future-`lastchg` aging trap) (the "kernel caps at 1999" belief is refuted: date(1) sets 2026, IN-rtc 2026-09-29); the
#     stock zone menu survives, its date half does not. `amixadm` still offers it.
#   * NO "small network hosts file with two addresses" question: our network step
#     supersedes it, and writing stock's two-address file would destroy the repo
#     host entry the installer bakes. Asking for something we would not do is
#     exactly what the stock idiom forbids.
#   * The domain is NOT written to /etc/domain (stock's amixnode did). A set
#     domain makes this resolver append it to EVERY lookup, even fully-qualified
#     ones; the domain lands only in the /etc/inet/hosts FQDN alias.


# ★ WHY THE DIALOG LIVES IN THIS FILE, of all files (bench, 2026-08-12).
# It was the driver's, emitted from a quoted here-doc -- the `emit_updbootpart`
# pattern. That cost an install. The 1991 SVR4 sh MATERIALIZES EVERY HERE-DOC
# BODY INTO A FILE UNDER /tmp WHEN IT PARSES THE SCRIPT (proven on the box: a
# here-doc inside a function that is never called still puts `/tmp/sh<pid>`
# there), and on the miniroot /tmp IS the 880-block install floppy, which has 46
# free 1 KB blocks. The updbootpart here-doc already in the driver was measured
# on the box at 15,427 B = 16 of those 46 blocks; ~29 KB of dialog on top takes
# the total to about 45 of 46, leaving roughly one block for everything else --
# and the static `pkgadd` needs several for its packaging directory. So the
# shell ran the floppy out of space before the driver printed its first line,
# and `pkgadd` could not create that directory, on the INTERACTIVE and the
# UNATTENDED path alike.
# (This comment first read "11 KB ... is 78 blocks". Both figures were wrong and
# W5.5 corrected them: the 11 KB came from a scanner that mis-delimited the body,
# and 78 divided by 512-byte blocks when the floppy's free blocks are 1 KB. The
# arithmetic is in docs/installer.md; the here-doc law is now ZERO, because W5.5
# moved updbootpart itself onto the medium.)
#
# This file is already staged on the medium and already copied onto the target
# by the driver's arm step, so carrying the dialog here costs no new medium
# file, no builder change and no here-doc anywhere. What the driver writes into
# the stock `/usr/amiga/bin/system.setup` slot is now a THREE-LINE STUB that
# execs this file with `--dialog` (payload/firstboot/system.setup is that stub,
# and installer-selftest drift-locks it against the driver's emitter). The
# pkgchk content-divergence wart shrinks with it: a three-line wrapper instead
# of a whole replaced body. It is the alternative plan v3 section 3 kept on
# file, chosen for a reason the plan could not have known.

dialog_setup()
{
	PATH=/sbin:/usr/bin:/usr/amiga/bin:/usr/sbin
	export PATH

	PROG=system.setup
	# The stub in the stock sysinit slot -- what `chmod -x` disarms at the clean
	# exit. FBDIR/CONF/DIALOG_DONE are this file's own, defined at the top.
	SELF=/usr/amiga/bin/system.setup
	# ★ THE TEMP NAME IS NOT COSMETIC. The target root MAY BE s5 -- it still is on
	# every attested rig, and s5 stays selectable for good -- and s5 TRUNCATES
	# EVERY NAME AT 14 CHARACTERS. A ufs root does not, but this script ships on
	# media that installs either, so the 14-character discipline is unconditional
	# here: a rule that holds only on the filesystem you happened to choose is not
	# a rule. `firstboot.conf` is exactly 14, so the obvious
	# `firstboot.conf.new` IS `firstboot.conf` -- and the consequence is not a failed
	# rename, it is the total loss of the file: `sed ... "$CONF" > "$NEWCONF"`
	# truncates its own input before sed reads a byte, and then `mv` finds source and
	# destination identical and takes the file with it. MEASURED on the bench,
	# 2026-08-12, on the first end-to-end run of this dialog: firstboot.conf ceased to
	# exist, taking FB_ROOTDEV/FB_SCSI_ID -- i.e. the next boot's /etc/vfstab -- with
	# it. Every temp name this dialog and firstboot.sh use must therefore still differ
	# from its target inside the first 14 characters; installer-selftest audit Z pins
	# that for both scripts.
	NEWCONF=$FBDIR/fbconf.new

	# The stock terminal setup, verbatim from the stock system.setup.
	stty erase '^H' kill '^U' intr '^C' eof '^D' quit '^\' 2>/dev/null
	stty iexten echoke echoe echoctl echoprt -istrip tab0 2>/dev/null

	# Ctrl-C -> note it and let the interrupted `read` fall into the re-ask path
	# below. NEVER exit: an exit here would leave the dialog armed but half-run with
	# the operator believing it had been dismissed.
	INTR=
	trap 'INTR=y' 2

	# ---------------------------------------------------------------------------
	# defaults: whatever the installer already knows about this box
	# ---------------------------------------------------------------------------
	# The driver wrote firstboot.conf from the install profile, so every question can
	# offer the profile's own value as its bracketed default -- and a run that answers
	# RETURN to everything lands exactly where the unattended tier would.
	if [ -f "$CONF" ]; then
		. "$CONF"
	fi

	# ---------------------------------------------------------------------------
	# stock helpers
	# ---------------------------------------------------------------------------
	# readask TEXT -- print TEXT (\c = no newline, \n = newline; the SVR4 builtin
	# echo interprets both) and read one line into $ask. Ctrl-C re-asks. EOF exits,
	# ARMED, so an unreadable console costs one boot message instead of a hang.
}

readask()
{
	while :
	do
		echo "$*\c"
		if read ask; then
			return 0
		fi
		if [ -n "$INTR" ]; then
			INTR=
			echo ""
			echo "Interrupted.  This configuration is not finished, so it will"
			echo "run again at the next boot.  Asking again:"
			continue
		fi
		echo ""
		echo "End of input.  The configuration dialog is NOT complete; it will"
		echo "run again at the next boot."
		exit 0
	done
}

# is_num WORD -- strict non-negative integer (no external tool).
is_num()
{
	case "$1" in
		'')       return 1 ;;
		*[!0-9]*) return 1 ;;
		*)        return 0 ;;
	esac
}

# valid_ip WORD -- four dot-separated decimal fields. A bad address here is not
# cosmetic: it is the difference between a box that answers on the LAN and one
# that has to be reconfigured from the console.
valid_ip()
{
	case "$1" in
		*[!0-9.]*)	return 1 ;;
	esac
	vi=`expr "$1" : '\([0-9][0-9]*\)\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$'`
	[ -n "$vi" ] || return 1
	return 0
}

# classful_mask IP -- the classful default netmask, which is what SVR4 assumes
# when `ifconfig` is given no netmask at all.
classful_mask()
{
	cm=`expr "$1" : '\([0-9][0-9]*\)\.'`
	is_num "$cm" || { echo 255.255.255.0; return 0; }
	if [ "$cm" -lt 128 ]; then
		echo 255.0.0.0
	else
		if [ "$cm" -lt 192 ]; then
			echo 255.255.0.0
		else
			echo 255.255.255.0
		fi
	fi
}

# ---------------------------------------------------------------------------
# write_conf -- the collected answers, into firstboot.conf, for S16 to apply
# ---------------------------------------------------------------------------
# A profile is sourced by sh, so an APPENDED assignment wins -- the same merge
# mechanism the interview uses for its answers profile. The previous dialog block
# (and every key we own) is stripped first, so a re-run REPLACES rather than
# accumulates. Written to a temp file and moved into place, and only after the
# closing marker has been proven present: a half-written firstboot.conf would
# take the boot-critical mechanical keys down with it.
write_conf()
{
	if [ ! -d "$FBDIR" ]; then
		mkdir -p "$FBDIR" || return 1
	fi
	if [ -f "$CONF" ]; then
		sed	-e '/^FB_NODENAME=/d' \
			-e '/^FB_DOMAIN=/d' \
			-e '/^FB_TZ=/d' \
			-e '/^FB_TZ_KEEP=/d' \
			-e '/^FB_IP=/d' \
			-e '/^FB_NETMASK=/d' \
			-e '/^FB_ETHER_IF=/d' \
			-e '/^FB_GATEWAY=/d' \
			-e '/^FB_DNS1=/d' \
			-e '/^FB_DNS2=/d' \
			-e '/^FB_NET_CONFIGURED=/d' \
			-e '/^FB_NET_MODE=/d' \
			-e '/^FB_REPO_HOST=/d' \
			-e '/^FB_REPO_IP=/d' \
			-e '/^FB_REPO_URL=/d' \
			-e '/^FB_ROOT_TELNET=/d' \
			-e '/^FB_SYSLOG=/d' \
			-e '/^# W5-DIALOG-/d' \
			"$CONF" > "$NEWCONF" || return 1
	else
		cp /dev/null "$NEWCONF" || return 1
	fi
	{
		echo "# W5-DIALOG-BEGIN -- answered at the console by $PROG"
		echo "FB_NODENAME=$FB_NODENAME"
		echo "FB_DOMAIN=$FB_DOMAIN"
		echo "FB_TZ=$FB_TZ"
		echo "FB_TZ_KEEP=$FB_TZ_KEEP"
		echo "FB_IP=$FB_IP"
		echo "FB_NETMASK=$FB_NETMASK"
		echo "FB_ETHER_IF=$FB_ETHER_IF"
		echo "FB_GATEWAY=$FB_GATEWAY"
		echo "FB_DNS1=$FB_DNS1"
		echo "FB_DNS2=$FB_DNS2"
		echo "FB_NET_CONFIGURED=$FB_NET_CONFIGURED"
		echo "FB_NET_MODE=$FB_NET_MODE"
		echo "FB_REPO_HOST=$FB_REPO_HOST"
		echo "FB_REPO_IP=$FB_REPO_IP"
		echo "FB_REPO_URL=$FB_REPO_URL"
		echo "FB_ROOT_TELNET=$FB_ROOT_TELNET"
		echo "FB_SYSLOG=$FB_SYSLOG"
		echo "# W5-DIALOG-END"
	} >> "$NEWCONF" || return 1
	grep '^# W5-DIALOG-END$' "$NEWCONF" > /dev/null || return 1
	mv "$NEWCONF" "$CONF" || return 1
	chmod 600 "$CONF" 2>/dev/null
	chmod 644 "$CONF" 2>/dev/null
	return 0
}

# ---------------------------------------------------------------------------
# the questions
# ---------------------------------------------------------------------------
ask_nodename()
{
	NDEF="$FB_NODENAME"
	if [ "$FB_L11" = y ]; then
		# an empty answer is allowed: the name DHCP offers (`hostname dhcp`), else
		# amix- and the last four hex digits of the first interface's MAC (section 1)
		if [ -n "$NDEF" ]; then
			readask "\nWhat is the nodename of this machine? [$NDEF] "
		else
			readask "\nWhat is the nodename of this machine? (RETURN: the name DHCP gives, else amix-xxxx) "
		fi
		if [ "$ask" != "" ]; then
			FB_NODENAME="$ask"
		else
			FB_NODENAME="$NDEF"
		fi
		[ -n "$FB_NODENAME" ] && uname -S "$FB_NODENAME" 2>/dev/null
		return 0
	fi
	[ -n "$NDEF" ] || NDEF=`uname -n`
	readask "\nWhat is the nodename of this machine? [$NDEF] "
	if [ "$ask" != "" ]; then
		FB_NODENAME="$ask"
	else
		FB_NODENAME="$NDEF"
	fi
	# stock amixnode's live half: the running kernel learns the name now.
	# /etc/nodename (the persistent half) is S16's -- one writer per file.
	uname -S "$FB_NODENAME" 2>/dev/null
}

ask_domain()
{
	if [ -z "$FB_DOMAIN" ] && [ -f /etc/domain ]; then
		# stock offered `cat /etc/domain`; ours is dot-less (see below)
		FB_DOMAIN=`sed -e 's/^\.*//' /etc/domain`
	fi
	readask "\nWhat is this machine's network domain? [$FB_DOMAIN] "
	if [ "$ask" != "" ]; then
		# Stock amixnode PREPENDED a dot (`sed -e 's/^\.*/./'`) because its
		# value went into /etc/domain. Ours goes into the hosts FQDN alias
		# `<node>.<domain>`, so a leading dot would produce `node..dom`.
		FB_DOMAIN=`echo "$ask" | sed -e 's/^\.*//'`
	fi
}

ask_timezone()
{
	# The stock zone menu, invoked exactly as stock's amixdate did: 56 entries in
	# three columns with an "Other (nonstandard)" escape. It writes /etc/TIMEZONE
	# itself (with the load-bearing leading colon) and creates the
	# /usr/lib/locale/TZ/localtime alias. Seeding TZ from the profile first makes
	# the menu's own default the zone this medium was built for, so RETURN keeps
	# it -- and a colon is emitted HERE, by code, never taken from data.
	if [ -n "$FB_TZ" ]; then
		TZ=":$FB_TZ"
		export TZ
	fi
	if [ -x /usr/amiga/etc/TZ ] && [ -x /usr/bin/ksh ]; then
		ksh /usr/amiga/etc/TZ
		if [ -f /etc/TIMEZONE ]; then
			. /etc/TIMEZONE
			ZSET=`sed -n 's/^TZ=//p' /etc/TIMEZONE`
			case "$ZSET" in
				:?*)
					FB_TZ=`expr "$ZSET" : ':\(.*\)'`
					FB_TZ_KEEP=y
					;;
				?*)
					# The "Other (nonstandard)" escape produced a POSIX rule
					# string (GMT0, PST8PDT). /etc/TIMEZONE is already correct;
					# FB_TZ is cleared so nothing can ever re-emit it as
					# `TZ=:GMT0`, which would bus-error every ctime(3) consumer.
					FB_TZ=
					FB_TZ_KEEP=y
					echo "\nTimezone $ZSET is a POSIX rule string, not a zone file."
					echo "/etc/TIMEZONE has it; it is not recorded as a zone name."
					;;
			esac
			# IN-rtc: the battery clock is kept in the machine's LOCAL time (the
			# AmigaOS convention), so the zone chosen here is also the zone setclk
			# must read it in. Follow it in /etc/clkzone when the install laid one
			# down (RTC=setclk); a POSIX rule string works there as well as :zone.
			if [ -f /etc/clkzone ] && [ -n "$ZSET" ]; then
				echo "$ZSET" > /etc/clkzone
				echo "\nThe battery clock will be read as $ZSET time (/etc/clkzone)."
				# IN-rtc-2: sysinit ran setclk BEFORE this dialog, in the image's
				# default zone; read the battery clock again in the chosen one so
				# this first boot already runs on the right time.
				if [ -x /usr/amiga/bin/setclk ]; then
					/usr/amiga/bin/setclk > /dev/null
				fi
			fi
		fi
	else
		echo "\nThe timezone menu (/usr/amiga/etc/TZ) is not installed on this"
		echo "system; the timezone stays $FB_TZ."
	fi
	# The stock dialog asked for the date and the time here. We do not, and the
	# reason is worth one screen (plan v3 section 3.3).
	echo ""
	echo "The date and time are NOT asked for.  This machine keeps its clock in"
	echo "the battery-backed real-time clock, and Amiga UNIX must never be given"
	echo "a date in the future: password aging stores the day an account was last"
	echo "changed, and a clock that has been forward locks every account out when"
	echo "it is put back.  At every boot the clock is set from the battery clock"
	echo "(if its reading is plausible); set the battery clock from AmigaOS."
}

find_ifs()
{
	# Interface detection with what an installed box carries TODAY.
	#   aen0 -- the stock A2065 probe, `aen -S`. This IS the stock convention:
	#           /etc/inet/network-config gates its own bring-up on it.
	#   zen0 -- the Z3660 native ethernet (z3660eth, cdevsw major 51). No `zen -S`
	#           tool ships on the media yet (a queued z3660net packet), so the
	#           probe is a pure-sh OPEN test: a redirection opens the device, and
	#           the shell reports a failed open as a nonzero status. The node
	#           itself only appears at S99zen (rc2), i.e. AFTER this dialog, so
	#           mknod it first if it is absent.
	#           ★ MEASURED (bench, 2026-08-12): on a kernel WITHOUT z3660eth the
	#           shell prints `/dev/zen0: cannot open` and returns 1 -- and that is
	#           ALL it reports. No errno reaches the script (ENXIO, EBUSY and
	#           EACCES are indistinguishable here), so this probe answers exactly
	#           one question: can this kernel open the device, yes or no. On the
	#           same box `( : < /dev/aen0 )` returns 0.
	NET_IFS=
	if /usr/amiga/bin/aen -S > /dev/null 2>&1; then
		NET_IFS="aen0"
	fi
	ZMADE=
	if [ -c /dev/zen0 ]; then
		:
	else
		mknod /dev/zen0 c 51 0 2>/dev/null && ZMADE=y
	fi
	if ( : < /dev/zen0 ) 2>/dev/null; then
		NET_IFS="$NET_IFS zen0"
	else
		# The probe made the node; the kernel says there is no driver behind it.
		# Take it away again rather than leave a dead device node on every
		# machine that answered this question with an A2065 in it. (On a real
		# Z3660 the node stays, and S99zen re-creates it at every boot anyway.)
		if [ -n "$ZMADE" ]; then
			rm -f /dev/zen0
		fi
	fi

	NIF=0
	if [ -n "$NET_IFS" ]; then
		set -- $NET_IFS
		NIF=$#
	fi
}

ask_network()
{
	# Cleared FIRST so a second pass through the summary loop that declines
	# networking really does decline it (the answer is the whole gate S16 reads).
	FB_NET_CONFIGURED= FB_NET_NOIF=
	# 1.1: look for an interface first. With none there is nothing to ask: the network is
	# recorded as DHCP on any interface (`* dhcp`), so a card fitted later comes up at its
	# first boot through ifup, and no repository address is asked (DNS from the lease).
	if [ "$FB_L11" = y ]; then
		find_ifs
		if [ "$NIF" = 0 ]; then
			echo "\nNo supported Ethernet interface was found on this machine, so the"
			echo "network questions are skipped.  Amiga UNIX supports the A2065 (aen0) and,"
			echo "on a Z3660, the native Ethernet (zen0).  A card fitted later asks a"
			echo "DHCP server for its address at the next boot."
			FB_NET_MODE=dhcp FB_IP= FB_NETMASK= FB_GATEWAY= FB_DNS1= FB_DNS2= FB_NET_NOIF=y
			FB_NET_CONFIGURED=y
			return 0
		fi
	fi
	readask "\nDo you want to configure networking? [y] "
	case $ask in
		[nN]* )
			echo "\nNetworking is left as the installation set it."
			return 0
			;;
	esac

	# 1.1: every interface a driver finds asks a DHCP server (`* dhcp`),
	# or one interface gets a static address. Default: static when the installation set
	# an address, else DHCP.
	FB_NET_MODE=static
	if [ "$FB_L11" = y ]; then
		DHDEF=y
		[ -n "$FB_IP" ] && DHDEF=n
		readask "\nUse DHCP to configure the network? [$DHDEF] "
		[ "$ask" != "" ] || ask=$DHDEF
		case $ask in
			[yY]* )
				FB_NET_MODE=dhcp FB_IP= FB_NETMASK= FB_GATEWAY= FB_DNS1= FB_DNS2=
				ask_repo
				FB_NET_CONFIGURED=y
				return 0
				;;
		esac
	fi

	[ "$FB_L11" = y ] || find_ifs
	# a function's `set --` stays its own: the list is set here for the choice below
	[ -z "$NET_IFS" ] || set -- $NET_IFS
	if [ "$NIF" = 0 ]; then
		echo "\nNo supported Ethernet interface was found on this machine."
		echo "Amiga UNIX supports the A2065 (aen0) and, on a Z3660, the native"
		echo "Ethernet (zen0).  Networking is left as the installation set it."
		return 0
	fi
	if [ "$NIF" = 1 ]; then
		FB_ETHER_IF="$1"
		echo "\nEthernet interface $FB_ETHER_IF found."
	else
		IFSEL=
		while [ "$IFSEL" = "" ]
		do
			echo ""
			echo "  1)   aen0	A2065 Ethernet"
			echo "  2)   zen0	Z3660 native Ethernet"
			readask "\nWhich interface do you want to use? [1] "
			case $ask in
				1|"" )	IFSEL=aen0 ;;
				2 )	IFSEL=zen0 ;;
			esac
		done
		FB_ETHER_IF="$IFSEL"
	fi

	IPOK=
	while [ "$IPOK" = "" ]
	do
		readask "\nWhat is this machine's network address? [$FB_IP] "
		if [ "$ask" = "" ]; then
			ask="$FB_IP"
		fi
		if valid_ip "$ask"; then
			FB_IP="$ask"
			IPOK=y
		else
			echo "\n$ask is not a network address (n.n.n.n), please try again."
		fi
	done

	NMDEF="$FB_NETMASK"
	[ -n "$NMDEF" ] || NMDEF=`classful_mask "$FB_IP"`
	NMOK=
	while [ "$NMOK" = "" ]
	do
		readask "\nWhat is the netmask? [$NMDEF] "
		if [ "$ask" = "" ]; then
			ask="$NMDEF"
		fi
		if valid_ip "$ask"; then
			FB_NETMASK="$ask"
			NMOK=y
		else
			echo "\n$ask is not a netmask (n.n.n.n), please try again."
		fi
	done

	GWDEF="$FB_GATEWAY"
	[ -n "$GWDEF" ] || GWDEF=none
	GWOK=
	while [ "$GWOK" = "" ]
	do
		readask "\nWhat is the default gateway? [$GWDEF] "
		if [ "$ask" = "" ]; then
			ask="$GWDEF"
		fi
		case "$ask" in
			none|NONE )
				FB_GATEWAY=
				GWOK=y
				;;
			* )
				if valid_ip "$ask"; then
					FB_GATEWAY="$ask"
					GWOK=y
				else
					echo "\n$ask is not a network address (n.n.n.n), please try again."
				fi
				;;
		esac
	done

	# DNS. The five-part enablement (resolv.conf, the libsockdns relink, the DNS
	# transport table, an empty /etc/domain and LITERAL-IP boot ifconfigs) is
	# applied by S16, atomically, and only where all five parts are reachable.
	# On aen0 the fifth part is the /etc/inet/network-config ifconfig -- the ONE
	# file this project never edits -- so DNS is not offered there yet.
	if [ "$FB_ETHER_IF" = zen0 ] || [ "$FB_L11" = y ]; then
		DNSOK=
		while [ "$DNSOK" = "" ]
		do
			readask "\nEnable DNS? [n] "
			case $ask in
				[yY]* )		DNSOK=y ;;
				[nN]*|"" )	DNSOK=n; FB_DNS1=; FB_DNS2= ;;
			esac
		done
		if [ "$DNSOK" = y ]; then
			D1OK=
			while [ "$D1OK" = "" ]
			do
				readask "\nWhat is the address of the name server? [$FB_DNS1] "
				if [ "$ask" = "" ]; then
					ask="$FB_DNS1"
				fi
				if valid_ip "$ask"; then
					FB_DNS1="$ask"
					D1OK=y
				else
					echo "\n$ask is not a network address (n.n.n.n), please try again."
				fi
			done
			readask "\nWhat is the address of a second name server? [none] "
			case "$ask" in
				""|none|NONE )	FB_DNS2= ;;
				* )
					if valid_ip "$ask"; then
						FB_DNS2="$ask"
					else
						echo "\n$ask is not a network address; no second name server."
						FB_DNS2=
					fi
					;;
			esac
		fi
	else
		if [ -n "$FB_DNS1" ]; then
			FB_DNS1=
			FB_DNS2=
		fi
		echo "\nDNS is not offered on $FB_ETHER_IF yet: enabling it requires the"
		echo "boot-time ifconfig to use a literal address, and on this interface"
		echo "that line lives in /etc/inet/network-config, which this system never"
		echo "edits.  Name resolution stays /etc/inet/hosts."
	fi

	ask_repo
	FB_NET_CONFIGURED=y
	return 0
}

ask_repo()
{
	# The package repository. Its name has to resolve without DNS, so the address
	# is asked for too and S16 bakes the pair into /etc/inet/hosts.
	readask "\nWhat is the package repository host? [$FB_REPO_HOST] "
	if [ "$ask" != "" ]; then
		RNEW="$ask"
		if [ -n "$FB_REPO_HOST" ] && [ -n "$FB_REPO_URL" ]; then
			# keep the URL pointing at the host that was just named
			FB_REPO_URL=`echo "$FB_REPO_URL" | sed -e "s|//$FB_REPO_HOST/|//$RNEW/|"`
		fi
		FB_REPO_HOST="$RNEW"
	fi
	if [ -n "$FB_REPO_HOST" ]; then
		RIOK=
		while [ "$RIOK" = "" ]
		do
			readask "\nWhat is the repository's network address? [$FB_REPO_IP] "
			# ★ W6: RETURN WITH NO DEFAULT IS AN ANSWER, and it has to be,
			# because the distro-neutral public flavor ships a repository
			# HOST with no address -- we know where the packages live, we
			# cannot know what address that name has on the buyer's LAN.
			# Before W6 this loop re-asked forever on an empty default (an
			# empty answer became an empty $ask, valid_ip refused it, and
			# nothing could ever satisfy it), so a public disc would have
			# hung its own first boot. Two ways out, both stated out loud:
			# with DNS the name resolves and no hosts line is wanted; with
			# neither, S16 skips the bake and says so -- and `apkg update`
			# will not resolve the repository until somebody adds it by
			# hand. Half a resolver is worse than none, so we never pretend
			# an address we were not given.
			if [ "$ask" = "" ] && [ -z "$FB_REPO_IP" ]; then
				if [ -n "$FB_DNS1" ]; then
					echo "\nNo address: $FB_REPO_HOST will be resolved by DNS."
				elif [ "$FB_NET_MODE" = dhcp ]; then
					# ifup gives the resolver the name servers of the lease (DHCP_DNS)
					echo "\nNo address: $FB_REPO_HOST will be resolved by the name"
					echo "servers the DHCP server gives. If it gives none, add the"
					echo "name to /etc/inet/hosts by hand."
				else
					echo "\nNo address recorded for $FB_REPO_HOST."
					echo "Package downloads will not resolve it until it is"
					echo "added to /etc/inet/hosts by hand."
				fi
				RIOK=y
				continue
			fi
			if [ "$ask" = "" ]; then
				ask="$FB_REPO_IP"
			fi
			if valid_ip "$ask"; then
				FB_REPO_IP="$ask"
				RIOK=y
			else
				echo "\n$ask is not a network address (n.n.n.n), please try again."
			fi
		done
	fi
}

ask_passwords()
{
	# Stock's own two lines, verbatim, and stock's own tool behind them:
	# /usr/amiga/bin/passwdall runs `passwd root` and then propagates the
	# resulting hash to the ~20 SECURELIST system accounts with one `ed` pass,
	# replacing ONLY the hash field -- so the aging fields those lines carry are
	# untouched (empty stays empty; the RTC trap discipline).
	echo "\nWould you like to assign a password to all of the"
	readask "system accounts? [y] "
	case $ask in
		[nN]* )
			SYSPASS="n"
			# The root password is NOT optional here, and this is the one place
			# this dialog deviates from stock out loud: stock let the operator
			# decline and keep the shipped hash on every account. We keep asking
			# until root has a password of its own.
			echo "\nThe root password must still be set."
			set_root_password
			;;
		* )
			SYSPASS="y"
			PWTRY=0
			while [ "$PW_DONE" = "" ] && [ "$PWTRY" -lt 3 ]
			do
				PWTRY=`expr "$PWTRY" + 1`
				if /usr/amiga/bin/passwdall; then
					PW_DONE=y
				else
					echo "\nThe password was not changed.  Try again."
				fi
			done
			;;
	esac

	if [ "$PW_DONE" = "" ]; then
		echo ""
		echo "WARNING:  the root password was NOT set.  This configuration"
		echo "WARNING:  dialog will run again at the next boot until it is."
	fi

	# The guest account, stock's wording and stock's default (it mirrors the
	# system-accounts answer). Asked only when the account exists -- stock asked
	# unconditionally, which on a set without `guest` is a question about nothing.
	if grep '^guest:' /etc/passwd > /dev/null 2>&1; then
		readask "\nWould you like to assign a password to the guest account? [$SYSPASS] "
		case $ask in
			[nN]* )
				;;
			[yY]* )
				passwd guest
				;;
			* )
				if [ "$SYSPASS" = "y" ]; then
					passwd guest
				fi
				;;
		esac
	fi

	# Root over the network. `CONSOLE=` in /etc/default/login gates ROOT logins
	# only -- ordinary users can always telnet in -- and telnet is the only remote
	# login this system has. Default ENABLED, and never silently changed.
	RTOK=
	while [ "$RTOK" = "" ]
	do
		readask "\nDo you want to allow root to log in over the network? [y] "
		case $ask in
			[yY]*|"" )	FB_ROOT_TELNET=y; RTOK=y ;;
			[nN]* )		FB_ROOT_TELNET=n; RTOK=y ;;
		esac
	done
}

set_root_password()
{
	PWTRY=0
	while [ "$PW_DONE" = "" ] && [ "$PWTRY" -lt 3 ]
	do
		PWTRY=`expr "$PWTRY" + 1`
		if passwd root; then
			PW_DONE=y
		else
			echo "\nThe password was not changed.  Try again."
		fi
	done
}

# clear_lastchg -- empty the lastchg (password-age) field on EVERY /etc/shadow line,
# after the dialog's password steps. `passwd root`, `passwd guest` and amixmkuser each
# stamp lastchg with the clock of the moment; if that clock is the battery clock's
# 2026 and a later boot comes up at the root fs time or 1977 (dead battery, or an RTC
# the setclk gate refused), SVR4 login sees a FUTURE lastchg and calls the password
# EXPIRED at every login (grimoire quirk 20). Empty lastchg = no aging, the shape
# every installer-written shadow line already has. Hashes and the other fields are
# untouched; firstboot's own write-temp-then-mv pattern, mode 400.
clear_lastchg()
{
	[ -f /etc/shadow ] || return 0
	# umask 077 in a subshell: the temp holds every hash, and boot's umask is 0.
	if (umask 077; sed 's|^\([^:]*:[^:]*:\)[^:]*:|\1:|' /etc/shadow > /etc/shadow.lc$$) \
		&& [ -s /etc/shadow.lc$$ ]; then
		mv /etc/shadow.lc$$ /etc/shadow
		chmod 400 /etc/shadow
		echo "firstboot: cleared lastchg on every /etc/shadow line (no password aging; the RTC trap)"
	else
		rm -f /etc/shadow.lc$$
		echo "firstboot: WARNING: could not clear lastchg in /etc/shadow -- a clock set back may expire passwords" >&2
	fi
}

home_on_data()
{
	# 1.1 with a data slice: /home is that slice from the first boot's steps on (section
	# 4), but the dialog runs before them. Mount it here, so the home amixmkuser makes
	# (/home/<login>) lands on it and not under its mount point on the root.
	HOME_MNT=
	[ -n "$FB_DATA_SLICE" ] || return 0
	set -- `/etc/devnm / 2>/dev/null`
	_hd=`expr "$1" : '\(/dev/dsk/c[0-9a-f]*d[01]\)s[0-7]$'`
	[ -d /home ] || mkdir /home
	if [ -n "$_hd" ] && mount -F "$FB_ROOT_FSTYPE" "${_hd}s$FB_DATA_SLICE" /home 2>/dev/null; then
		HOME_MNT=y
	else
		echo "\nThe /home slice could not be mounted; the new home is made on the root"
		echo "and is hidden once /home is mounted. Move it there after the first boot."
	fi
}

ask_users()
{
	# Stock's loop, verbatim (one account, then on), with /home on the data slice (1.1).
	USER_ADDED=
	while [ "$USER_ADDED" = "" ]
	do
		readask "\nWould you like to create a user account? [n] "
		case $ask in
			[yY]* )
				home_on_data
				/usr/amiga/lib/amixmkuser && USER_ADDED="done"
				[ -z "$HOME_MNT" ] || umount /home 2>/dev/null
				;;
			[nN]* | "" )
				USER_ADDED="done"
				;;
		esac
	done
}

ask_monitor()
{
	# Stock, verbatim: /usr/amiga/bin/A2024 IS the flag -- it is a hard link to
	# /usr/bin/true or /usr/bin/false, and /etc/sysinit runs it as a test.
	if /usr/amiga/bin/A2024
	then
		DEFMON="y"
	else
		DEFMON="n"
	fi
	readask "\nAre you using an A2024 or Moniterm high resolution monitor? [$DEFMON] "
	if [ "$ask" = "" ]
	then
		ask=$DEFMON
	fi
	case $ask in
		[yY]* )
			rm -f /usr/amiga/bin/A2024
			ln /usr/bin/true /usr/amiga/bin/A2024
			;;
		* )
			rm -f /usr/amiga/bin/A2024
			ln /usr/bin/false /usr/amiga/bin/A2024
			;;
	esac
}

ask_x11()
{
	# Stock, verbatim -- and asked unconditionally, as stock did: amixcolorx
	# itself handles a system with no Xcore (it prints the package-command help
	# table and waits for RETURN).
	readask "\nDo you wish to configure X Windows for a color graphics card? [n] "
	case $ask in
		[yY]* )
			/usr/amiga/lib/amixcolorx
			;;
	esac
}

ask_netnews()
{
	# Stock, verbatim, including the inews presence gate.
	if [ -f /usr/public/lib/news/inews ]
	then
		readask "\nDo you wish to configure Netnews for either local or networked operation? [n] "
		case $ask in
			[yY]* )
				/usr/amiga/lib/amixnews
				;;
		esac
	fi
}

ask_syslog()
{
	# Ours. The syslog UNIT is laid down by the installer unconditionally (it is
	# driver-written and invisible to the package database); this question only
	# decides whether it starts at boot, which is the vendor `exit` line in
	# /etc/init.d/syslogd. S16 does the edit -- IN PLACE, because that file is one
	# inode with three names (S70syslogd, K50syslogd).
	SLOK=
	while [ "$SLOK" = "" ]
	do
		readask "\nDo you want the system logging daemon enabled? [y] "
		case $ask in
			[yY]*|"" )	FB_SYSLOG=y; SLOK=y ;;
			[nN]* )		FB_SYSLOG=n; SLOK=y ;;
		esac
	done
}

summary()
{
	echo ""
	if [ "$FB_L11" = y ] && [ -z "$FB_NODENAME" ]; then
		echo "Nodename:		from DHCP, else amix-xxxx"
	else
		echo "Nodename:		`uname -n`"
	fi
	# NOT `cat /etc/domain`, which stock used: this system deliberately leaves
	# that file alone (a set domain is appended to every resolver lookup), so the
	# domain lives in the /etc/inet/hosts FQDN alias S16 writes from this value.
	echo "Domain:			$FB_DOMAIN"
	echo "Date:			`date`"
	if [ -n "$FB_TZ" ]; then
		echo "Timezone:		$FB_TZ"
	else
		echo "Timezone:		`sed -n 's/^TZ=//p' /etc/TIMEZONE 2>/dev/null`"
	fi
	if [ "$FB_NET_CONFIGURED" = y ] && [ "$FB_NET_MODE" = dhcp ]; then
		if [ "$FB_NET_NOIF" = y ]; then
			echo "Network:		no interface found; DHCP on a card fitted later"
		else
			echo "Network:		DHCP on every interface"
		fi
	elif [ "$FB_NET_CONFIGURED" = y ]; then
		echo "Network:		$FB_ETHER_IF $FB_IP netmask $FB_NETMASK"
		if [ -n "$FB_GATEWAY" ]; then
			echo "Gateway:		$FB_GATEWAY"
		else
			echo "Gateway:		none"
		fi
		if [ -n "$FB_DNS1" ]; then
			echo "Name server:		$FB_DNS1 $FB_DNS2"
		else
			echo "Name server:		none (/etc/inet/hosts)"
		fi
	else
		echo "Network:		as installed ($FB_ETHER_IF $FB_IP)"
	fi
	if [ -n "$FB_REPO_HOST" ]; then
		echo "Package repository:	$FB_REPO_HOST ($FB_REPO_IP)"
	fi
	if [ "$PW_DONE" = y ]; then
		echo "Root password:		set"
	else
		echo "Root password:		NOT SET"
	fi
	if [ "$FB_ROOT_TELNET" = n ]; then
		echo "Root over network:	no"
	else
		echo "Root over network:	yes"
	fi
	if [ "$FB_SYSLOG" = n ]; then
		echo "System logging:		disabled"
	else
		echo "System logging:		enabled"
	fi
	# stock's own two monitor lines
	if /usr/amiga/bin/A2024
	then
		echo "Monitor:		Moniterm or A2024"
	else
		echo "Monitor:		not a Moniterm or A2024"
	fi
	# stock's NetNews line, gate and all
	if [ -f /usr/public/lib/news/inews ]
	then
		inewssum="`sum < /usr/public/bin/inews`"
		cnewssum="`sum < /usr/public/lib/newsbin/inject/inews`"
		if [ "$inewssum" = "$cnewssum" ]
		then
		echo "NetNews:		cnews"
		else
		echo "NetNews:		nntp"
		fi
	fi
}

run_dialog()
{
	dialog_setup
	# ---------------------------------------------------------------------------
	# THE DIALOG
	# ---------------------------------------------------------------------------
	# Stock's outer loop: everything is asked, the summary is shown, and answering
	# `y` to "change any of these" asks the lot again. REPEAT gates the password and
	# user-creation blocks on a second pass, exactly as stock did.
	echo ""
	echo "Amiga UNIX system configuration"

	[ -n "$FB_ROOT_TELNET" ] || FB_ROOT_TELNET=y
	[ -n "$FB_SYSLOG" ] || FB_SYSLOG=y
	PW_DONE=
	REPEAT=
	FB_NET_CONFIGURED=

	while :
	do
		ask_nodename
		ask_domain
		ask_timezone
		ask_network
		if [ "$REPEAT" = "" ]
		then
			ask_passwords
			ask_users
			clear_lastchg
		fi
		ask_monitor
		ask_x11
		ask_netnews
		ask_syslog
		summary

		CHANGE=
		while [ "$CHANGE" = "" ]
		do
			readask "\nDo you wish to change any of these? [n] "
			case $ask in
				[nN]* | "" )
					CHANGE=no
					;;
				[yY]* )
					CHANGE=yes
					REPEAT="y"
					;;
			esac
		done
		[ "$CHANGE" = no ] || continue

		# ---- the clean exit, and the ONLY place anything is disarmed ----------
		# Order matters: the answers are on disk BEFORE the exec bit comes off, so a
		# crash between the two costs a re-run, never the answers. The DIALOG-DONE
		# marker is what tells firstboot.sh that the identity in the conf is the
		# operator's, so PENDING may be cleared.
		if write_conf; then
			echo ""
			echo "Configuration recorded in $CONF."
		else
			echo ""
			echo "WARNING:  could not write $CONF -- this dialog will run again at"
			echo "WARNING:  the next boot."
			rm -f "$NEWCONF"
			exit 0
		fi
		if [ "$PW_DONE" = "" ]; then
			echo "The root password is still not set; this dialog stays armed."
			exit 0
		fi
		cp /dev/null "$DIALOG_DONE" 2>/dev/null
		chmod 600 "$DIALOG_DONE" 2>/dev/null
		chmod -x "$SELF"
		exit 0
	done
}

case "$1" in
	--dialog)
		run_dialog
		exit 0
		;;
esac


[ -f "$MARK" ] || { echo "firstboot: no PENDING marker, nothing to do"; exit 0; }
[ -f "$CONF" ] || { echo "firstboot: STOP: missing $CONF" >&2; exit 1; }

# load FB_NODENAME / FB_DOMAIN / FB_TZNUM / FB_TZ / FB_TZ_KEEP / FB_IP /
# FB_NETMASK / FB_ETHER_IF / FB_GATEWAY / FB_DNS1 / FB_DNS2 / FB_KMAP /
# FB_REPO_HOST / FB_REPO_IP / FB_REPO_URL / FB_ROOTDEV / FB_SCSI_ID /
# FB_ROOT_SLICE / FB_SWAP_SLICE / FB_ROOT_FSTYPE / FB_DIALOG / FB_ROOT_TELNET /
# FB_SYSLOG / FB_NET_CONFIGURED / FB_ZEN_CARDS / FB_STANDUNIX_REG / FB_STANDUNIX_RM /
# FB_INITTAB_SYS / FB_SDCARDS / FB_L11 / FB_NET_MODE
. "$CONF"

# FB_TZ is the timezone ZONE NAME (W1). It was a literal `US/Eastern` in this
# script until then, so an install whose profile said otherwise silently got
# US/Eastern anyway. Default to that same literal when the conf predates the key,
# so an old firstboot.conf keeps its old behaviour exactly.
[ -n "$FB_TZ" ] || FB_TZ=US/Eastern
# W5 DEFAULTS. Each is the behaviour this script had BEFORE W5, so a firstboot.conf
# written by an older driver -- or by a profile that names none of these -- produces
# a byte-identical result:
#   FB_ROOT_TELNET    y  -- comment CONSOLE= (root may telnet in), as always
#   FB_SYSLOG         y  -- leave the laid-down syslog unit enabled: NO edit at all
#   FB_NET_CONFIGURED    -- empty: the network EXTRAS (default route, zen0 laydown
#                           refresh, DNS) are the DIALOG's, and an unattended
#                           install must not grow a step it never had
#   FB_TZ_KEEP           -- empty: this script writes /etc/TIMEZONE, as always
[ -n "$FB_ROOT_TELNET" ] || FB_ROOT_TELNET=y
[ -n "$FB_SYSLOG" ] || FB_SYSLOG=y
# The filesystem the installer laid on the root slice, for /etc/vfstab column 4
# (section 4 below). Default s5 -- the type this script wrote as a LITERAL until
# the UFS lane existed -- so a firstboot.conf written by an older driver, or one
# that predates the key entirely, produces the byte-identical vfstab it always
# did. An unknown value is refused rather than written: vfstab column 4 is what
# every boot's fsck and root remount dispatch on, and a typo there is a fault
# that only shows up at the NEXT boot, on a console nobody is watching.
[ -n "$FB_ROOT_FSTYPE" ] || FB_ROOT_FSTYPE=s5
case "$FB_ROOT_FSTYPE" in
	s5|ufs)	;;
	*)	echo "firstboot: STOP: FB_ROOT_FSTYPE='$FB_ROOT_FSTYPE' is not s5 or ufs" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# THE TWO TIERS (W5) -- and why PENDING sometimes stays
# ---------------------------------------------------------------------------
# FB_DIALOG=y means the install ARMED the first-boot configuration dialog in the
# stock sysinit slot. sysinit runs before rc2, so on a normal boot the dialog has
# already replaced its own block in firstboot.conf by the time this script reads
# it, and $DIALOG_DONE exists. If it does NOT exist the dialog was interrupted
# (Ctrl-C, a power cycle, an unreadable console): we then apply the MECHANICAL
# keys anyway -- the box must boot healthy, with a vfstab, its devices and its
# hosts entries -- but we LEAVE PENDING in place, because the dialog is still
# armed and the identity it collects at the next boot needs this script to run
# once more to apply it.
DIALOG_PENDING=
if [ "$FB_DIALOG" = y ] && [ ! -f "$DIALOG_DONE" ]; then
	DIALOG_PENDING=y
	echo "firstboot: the first-boot dialog has not completed -- applying the mechanical"
	echo "firstboot: steps only; PENDING stays so the next boot's answers are applied too"
fi

echo "firstboot: applying identity nodename=$FB_NODENAME domain=$FB_DOMAIN tz=$FB_TZ (index $FB_TZNUM)"

ID="$FB_SCSI_ID"
# The root as the running kernel names it. A four-card kernel (C4-1) orders the controllers
# by class, so the installer's id can name another card than the kernel's (the A3000 WD
# beside an A4091: c6d0 under the install kernel, ced0 under the target's). /etc/devnm maps
# the mounted root's device number to its /dev/dsk node by stat alone, opening no device;
# vfstab, the swap name and the atdevs gate then follow the kernel.
set -- `/etc/devnm / 2>/dev/null`
_kid=`expr "$1" : '/dev/dsk/c\([0-9a-f]*\)d0s[0-7]$'`
# before 4d a card-2/3 root still has core's d1 node for its minor: c<X>d1 is c1<X> there
[ -z "$_kid" ] && [ "$FB_SDCARDS" = 4 ] && _kid=`expr "$1" : '/dev/dsk/c\([0-9a-f]\)d1s[0-7]$'` && _kid=1$_kid
if [ -n "$_kid" ] && [ "$_kid" != "$ID" ]; then
	echo "firstboot: the kernel roots on /dev/dsk/c${_kid}d0 (the installer named c${ID}d0) -- the names follow the kernel"
	ID=$_kid FB_SCSI_ID=$_kid
fi
ROOT_BLK="/dev/dsk/c${ID}d0s${FB_ROOT_SLICE}"
ROOT_RAW="/dev/rdsk/c${ID}d0s${FB_ROOT_SLICE}"
SWAP_BLK="/dev/dsk/c${ID}d0s${FB_SWAP_SLICE}"

# --- 1. nodename ------------------------------------------------------------
# SVR4 persists the nodename in /etc/nodename (read at boot) AND the running
# kernel value is set with `uname -S`. Do both so `uname -n` resolves now and
# after a reboot. (W5.4 confirms Amix reads /etc/nodename at boot.)
# 1.1: no name given -> amix- and the last four hex digits of the first interface's
# MAC (amix-base's dlpi-mac; zen0 first, the Z3660's own), which ifup replaces with the name a
# DHCP server offers when /etc/inet/interfaces says `hostname dhcp`
if [ "$FB_L11" = y ] && [ -z "$FB_NODENAME" ]; then
	FB_NAME_EFF=
	for d in /dev/zen0 /dev/aen0
	do
		[ -c "$d" ] || continue
		m=`/usr/sbin/dlpi-mac -t 2 "$d" 2>/dev/null`
		case "$m" in
			??:??:??:??:??:??)
				FB_NAME_EFF=amix-`echo "$m" | sed -e 's/://g' -e 's/^........//'`
				break ;;
		esac
	done
	[ -n "$FB_NAME_EFF" ] || FB_NAME_EFF=amix-0000
	echo "firstboot: no name given -- $FB_NAME_EFF until a DHCP server offers one"
else
	FB_NAME_EFF="$FB_NODENAME"
fi
echo "$FB_NAME_EFF" > /etc/nodename
uname -S "$FB_NAME_EFF" 2>/dev/null || true

# --- 2. timezone (zone name from FB_TZ; US/Eastern = index 47) ---------------
# SVR4 sources TZ from /etc/TIMEZONE at init. Amix's first-boot dialog takes the
# numeric index 47 (US/Eastern); store both the standard TZ string and the index
# breadcrumb. (W5.4 confirms the exact Amix timezone store + 47 mapping.)
#
# THE LEADING COLON IS LOAD-BEARING (W6.3, proven on-box). SVR4 ctime(3)/tzset(3)
# only reads a tzfile when TZ is `:<pathname>` -- the colon says "this is a path".
# `TZ=:US/Eastern` maps to the tzfile /usr/lib/locale/TZ/US/Eastern (present, and
# byte-identical to the golden's). WITHOUT the colon SVR4 tries to parse
# `US/Eastern` as a POSIX rule string, walks off into garbage, and every consumer
# (date, who -r, ls -l, cron, sac) takes a BUS ERROR at 474D5400 on cold boot --
# and the crashed `who -r` cascades into the rc2 `test: unknown operator S` errors.
# installer-selftest.py audit F enforces the colon form.
#
# W1 parametrizes the ZONE (FB_TZ) but NOT the colon: the colon is emitted by
# THIS line, never taken from data, so no profile/answers file can ever produce
# the bus-erroring colon-less form -- not by typo, not by a stripped quote. The
# driver strips a leading colon off FB_TZ before writing firstboot.conf for the
# same reason (`TZ=::US/Eastern` would be just as broken).
#
# W5: FB_TZ_KEEP=y says the first-boot DIALOG already ran the genuine stock zone
# menu (/usr/amiga/etc/TZ), which writes /etc/TIMEZONE itself -- with the colon,
# and with the /usr/lib/locale/TZ/localtime alias that only that tool creates. Do
# not rewrite it. This is also what protects the menu's "Other (nonstandard)"
# escape: a POSIX rule string like GMT0 is a VALID TZ that must NOT be prefixed
# with a colon, and the only way this script can never emit `TZ=:GMT0` is to not
# write the file at all. FB_TZ is empty in exactly that case.
if [ "$FB_TZ_KEEP" = y ] && [ -f /etc/TIMEZONE ]; then
	echo "firstboot: /etc/TIMEZONE was set by the first-boot dialog's stock zone menu -- keeping it"
else
	{
		echo "# set by firstboot.sh (zone $FB_TZ, Amix tz index $FB_TZNUM)"
		echo "TZ=:$FB_TZ"
		echo "export TZ"
	} > /etc/TIMEZONE
fi
echo "$FB_TZNUM" > /etc/tz.index 2>/dev/null || true
chmod 644 /etc/tz.index 2>/dev/null

# --- 3. root password + console -------------------------------------------
# Root pw hash comes from the payload root.shadow (bench pw `pass`, the
# well-documented bench credential; crypt("pass","aB")=ROOT_HASH_PLACEHOLDER). Replace
# the root line of /etc/shadow, keep every other line. mode 400.
#
# W5: when the first-boot DIALOG is in play it runs the stock `passwd root` /
# `passwdall` flow on the console BEFORE this script, and the whole point of that
# question is that the shipped credential does not survive it. Re-stamping the
# payload hash here would undo it silently, so the shadow write is skipped once
# the dialog has completed. If the dialog did NOT complete, the payload hash IS
# the right answer: the box would otherwise come up with core's shipped root hash.
if [ "$FB_DIALOG" = y ] && [ -z "$DIALOG_PENDING" ]; then
	echo "firstboot: root password was set by the first-boot dialog -- not touching /etc/shadow"
elif [ -f "$FBDIR/root.shadow" ]; then
	newhash=`sed -n 's/^root:\([^:]*\):.*/\1/p' "$FBDIR/root.shadow"`
	if [ -n "$newhash" ] && [ -f /etc/shadow ]; then
		# rewrite the root: line with the new hash, empty aging fields (no expiry)
		(umask 077; sed "s|^root:[^:]*:.*|root:$newhash:::::::|" /etc/shadow > /etc/shadow.fb$$) \
			&& mv /etc/shadow.fb$$ /etc/shadow
		chmod 400 /etc/shadow
	fi
fi
# Root over the network (FB_ROOT_TELNET, W5; default y = what this always did).
# `CONSOLE=` in /etc/default/login gates ROOT logins only -- ordinary users can
# telnet in either way -- and telnet is the only remote login this system has, so
# the default is PERMIT and turning it off is an explicit answer, never a silent
# hardening. Both directions are idempotent: the sed either comments the live line
# or uncomments the commented one, and running it twice changes nothing.
if [ -f /etc/default/login ]; then
	if [ "$FB_ROOT_TELNET" = n ]; then
		sed 's/^#CONSOLE=/CONSOLE=/' /etc/default/login > /etc/default/login.fb$$ \
			&& mv /etc/default/login.fb$$ /etc/default/login
		echo "firstboot: root logins RESTRICTED to the console (CONSOLE= in /etc/default/login)"
	else
		sed 's/^CONSOLE=/#CONSOLE=/' /etc/default/login > /etc/default/login.fb$$ \
			&& mv /etc/default/login.fb$$ /etc/default/login
	fi
	chmod 444 /etc/default/login
fi

# --- 4. /etc/vfstab for the real controller/slice --------------------------
# SVR4 vfstab columns: special fsckdev mountp fstype fsckpass automnt mntopts.
# rootdev is baked into the kernel ($FB_ROOTDEV); vfstab names the mount + swap.
#
# ★ COLUMN 4 IS THE ONLY THING THE ROOT FILESYSTEM TYPE CHANGES ON THIS BOX --
# and it is parameterised here because it was parameterised in 1991. The stock
# installer's own here-doc (stock /etc/profile, extracted verbatim) reads:
#     /dev/dsk/c${SCSI}d0s${ROOTPART}	/dev/rdsk/c${SCSI}d0s${ROOTPART}	/	${ROOT_FSYS}	1	no	-
# i.e. block node, char node, mount point, THE CHOSEN TYPE. The literal `s5` this
# line carried until the UFS lane was OUR hardcode, not stock's.
# $FB_ROOT_FSTYPE comes from the installer (install.sh writes it into
# firstboot.conf from TARGET_ROOT_FSTYPE); everything downstream is already
# type-generic and needs no edit:
#   * /usr/sbin/bcheckrc asks the KERNEL first (`set \`/sbin/df -n /\``), falls
#     back to this column, and builds `fstyp="-F $3"` for /sbin/fsck -- which
#     execs /usr/lib/fs/<type>/fsck. core ships the ufs back end in full.
#   * the SWAP row has no filesystem at all: `swap` is a type, not a mount, and
#     the slice is handed to the kernel's swap layer raw.
# The fsckdev column is the CHAR node while column 1 is the BLOCK node -- already
# right here, and it matters MORE on ufs than it did on s5, because on ufs this
# is the fsck that actually runs at every boot.
#
# ★ COLUMN 6 (mount at boot) IS `no` FOR ROOT, AND THAT IS NOT A TYPO. The kernel
# mounts the root filesystem itself, from the rootdev baked into the kernel --
# long before /etc/rc2.d ever runs mountall. A `yes` here orders mountall to mount
# a filesystem that is ALREADY mounted, and SVR4 answers with EBUSY. MEASURED on
# metal 2026-08-15, on every single boot (console screencaps):
#     mount: Device busy
#     mount: /dev/dsk/c6d0s1 on /: Device busy
#     mount: giving up on: /
# Harmless in effect -- the box boots, because the mount that matters already
# happened -- but it is three lines of alarming console noise on every boot of
# every box this installer ever makes, and it was OURS: the stock here-doc quoted
# above ends `1  no  -`, and the `yes` was introduced here. The SWAP row was
# always `no` (a swap slice is handed to the kernel's swap layer, never mounted),
# so root was the only defective column. Anything that WANTS root in vfstab still
# gets it -- bcheckrc's fsck fallback and updbootpart's boot-slice derivation both
# read columns 1-4 and neither looks at column 6.
{
	echo "#device         device          mount   FS      fsck    mount   mount"
	echo "#to mount       to fsck         point   type    pass    at boot options"
	echo "$ROOT_BLK	$ROOT_RAW	/	$FB_ROOT_FSTYPE	1	no	-"
	echo "$SWAP_BLK	-	-	swap	-	no	-"
	# a 1.1 disk's data slice (FB_DATA_SLICE, absent on 1.0) holds /home
	if [ -n "$FB_DATA_SLICE" ]; then
		echo "/dev/dsk/c${ID}d0s${FB_DATA_SLICE}	/dev/rdsk/c${ID}d0s${FB_DATA_SLICE}	/home	$FB_ROOT_FSTYPE	2	yes	-"
	fi
} > /etc/vfstab
# a 1.1 disk: the installer made /dev/kinfo (c 53 0, 0444) on a miniroot with no chgrp
if [ -c /dev/kinfo ]; then
	chown root /dev/kinfo; chgrp sys /dev/kinfo; chmod 444 /dev/kinfo
fi
if [ -n "$FB_DATA_SLICE" ]; then
	[ -d /home ] || mkdir /home
	mount /home 2>/dev/null && echo "firstboot: mounted the data slice s$FB_DATA_SLICE at /home"
fi
echo "firstboot: wrote /etc/vfstab (root $ROOT_BLK $FB_ROOT_FSTYPE, rootdev $FB_ROOTDEV)"

# --- 4b. /stand/unix in the core package (040/060 line; Q-4.15 trap ii) ---------
# The installer laid the kernel the boot slice frames at /stand/unix (over the core
# package's 1992 030 kernel). Re-register it so the contents DB records what is really
# there and pkgchk stays clean. Idempotent: installf on an existing path updates it.
# APKG's engine, NOT the stock /usr/sbin/installf: the 1992 binary takes a user BUS ERROR
# in `installf -f` on the 68060 (K1 r5 cell A2, 2026-10-03), dumps core into the cwd and
# leaves the entry half-registered ("? ? ? +core"). Run from /tmp so a failure can never
# leave a core file in /.
if [ "$FB_STANDUNIX_REG" = y ]; then
	if [ -x /usr/apkg/bin/installf ] &&
	   ( cd /tmp && /usr/apkg/bin/installf core /stand/unix f 0644 root root >/dev/null 2>&1 &&
	     /usr/apkg/bin/installf -f core >/dev/null 2>&1 ); then
		echo "firstboot: /stand/unix re-registered in the core package (APKG installf)"
	else
		echo "firstboot: WARNING: could not re-register /stand/unix (no APKG installf?) -- pkgchk will report it modified"
	fi
fi

# --- 4c. a 1.1 disk: /stand/unix and /etc/inittab in the core package --------------
# The installer removed the name /stand/unix, core's 1992 kernel (S01kbnamelist writes
# the booted generation's namelist there; amix-dlm C2-4 section 12). Core's contents
# record it as the file and /stand/2.1_unix as a link to it: /stand/2.1_unix becomes the
# file, /stand/unix goes, so pkgchk core stays quiet on both. APKG's heirloom tools as in
# 4b, from /tmp (the stock installf and removef take a bus error on the 68060).
if [ "$FB_STANDUNIX_RM" = y ]; then
	( cd /tmp && /usr/apkg/bin/installf core /stand/2.1_unix f 0644 root root >/dev/null 2>&1 &&
	  /usr/apkg/bin/installf -f core >/dev/null 2>&1 &&
	  /usr/apkg/bin/removef core /stand/unix >/dev/null 2>&1 &&
	  /usr/apkg/bin/removef -f core >/dev/null 2>&1 )
	if grep '^/stand/unix[ =]' /var/sadm/install/contents >/dev/null 2>&1; then
		echo "firstboot: WARNING: /stand/unix is still in core's contents -- pkgchk core will report it missing"
	elif ( cd /tmp && /usr/apkg/bin/pkgchk -p /stand/2.1_unix core 2>&1 ) | grep . >/dev/null; then
		echo "firstboot: WARNING: pkgchk core is not quiet on /stand/2.1_unix"
	else
		echo "firstboot: /stand/unix out of the core package, /stand/2.1_unix its own file (APKG removef/installf); pkgchk quiet"
	fi
fi
# modtools' postinstall rewrote /etc/inittab by rename on the install miniroot, which has
# no chgrp: core's owner, group and mode back (root sys 0664)
if [ "$FB_INITTAB_SYS" = y ]; then
	chown root /etc/inittab; chgrp sys /etc/inittab; chmod 664 /etc/inittab
	set -- `ls -l /etc/inittab`
	if [ "$1" = "-rw-rw-r--" ] && [ "$3" = root ] && [ "$4" = sys ]; then
		echo "firstboot: /etc/inittab root sys 0664, as core lays it"
	else
		echo "firstboot: WARNING: /etc/inittab is $1 $3 $4, not -rw-rw-r-- root sys"
	fi
fi

# --- 4d. a four-card kernel (C4-1): the card-2/3 disk nodes replace core's d1 nodes ----
# Minor bit 7 is the card's high bit on a four-card kernel, so core's 256 c<N>d1s<S>
# nodes (minor 128 + ...) would open card-2/3 disks under names that say otherwise.
# `kbootset nodes` (C2-4 v12 §14, S5-44 R2) owns the set: it reads the installed kernel's
# sidecar (sdcards=4 in /stand/k30/kabi or /stand/k46/kabi) itself, makes c0-c1f d0 s0-s7
# at their C4-1 minors, removes the d1 nodes and registers the change to core with APKG's
# removef/installf; on a two-card kernel it says core's nodes stand. Success is exit 0
# with "the four-card set is complete" or "registered to core".
if [ -x /sbin/kbootset ]; then
	_nl=`/sbin/kbootset nodes 2>&1`; _nrc=$?
	echo "firstboot: $_nl"
	[ $_nrc -eq 0 ] || echo "firstboot: WARNING: kbootset nodes failed ($_nrc)"
fi

# --- 5. /etc/inet/hosts (the ONLY networking edit; NEVER network-config) ----
# Add "<ip> <nodename> <nodename>.<domain>" so `uname -n` resolves to the box's
# own IP (which is what the SHIPPED network-config's `ifconfig aen0 `uname -n``
# needs). Do not create/edit /etc/inet/network-config.
#
# W5 makes this RE-RUNNABLE. The dialog can be interrupted and completed on a
# later boot, and it can be answered with a different nodename than the profile
# baked, so this section now guards BOTH ways round: it drops any alias of the new
# nodename (the stray one stock's own dialog leaves on the 127.1 loopback line
# included) AND any earlier line for the same address. Without the second guard a
# nodename change would leave two entries claiming one IP.
# 1.1: amix-base's ifup writes this host's row from /etc/inet/interfaces' `name`
if [ "$FB_L11" != y ] && [ -n "$FB_IP" ] && [ -f /etc/inet/hosts ]; then
	# Drop any stale alias of our nodename (the one stock's own dialog leaves on
	# the 127.1 loopback line included), then any line already claiming our
	# address, then append exactly one.
	#
	# ★ TWO -e EXPRESSIONS, NOT ONE ALTERNATION. This guard used to read
	# `s/[ TAB]$FB_NODENAME\([ TAB]\|$\)/\1/g` -- and `\|` is a GNU extension that
	# SVR4 sed does not have. MEASURED on the box 2026-08-12: the alternation form
	# matches NOTHING (all three fixture lines survive), so both duplicate guards
	# in this file have been inert since W6.4c; the repo-host line was appended a
	# second time on the first re-run and nobody noticed, because the resolver
	# takes the first match. The two-expression form is the same rule, portably:
	# one for "token at end of line", one for "token followed by whitespace".
	sed -e "s/[ 	]$FB_NODENAME\$//" \
	    -e "s/[ 	]$FB_NODENAME\\([ 	]\\)/\\1/g" \
		/etc/inet/hosts > /etc/inet/hosts.fb$$
	sed "/^$FB_IP[ 	]/d" /etc/inet/hosts.fb$$ > /etc/inet/hosts.fb2$$ \
		&& mv /etc/inet/hosts.fb2$$ /etc/inet/hosts.fb$$
	echo "$FB_IP	$FB_NODENAME $FB_NODENAME.$FB_DOMAIN" >> /etc/inet/hosts.fb$$
	mv /etc/inet/hosts.fb$$ /etc/inet/hosts
	chmod 444 /etc/inet/hosts
	echo "firstboot: added $FB_IP $FB_NODENAME to /etc/inet/hosts (network-config UNTOUCHED)"
fi

# --- 5b. package-repo host -> /etc/inet/hosts (zero-touch `apkg update`) -----
# A fresh install has NO way to resolve the apkg repo's hostname: the bench LAN has
# no DNS, and section 5 baked only THIS box's own nodename. So `apkg update` against
# a hostname-based repo URL cannot resolve the host and fails until someone
# hand-edits /etc/inet/hosts (exactly the manual step W6.4b's acceptance still
# needed). Bake the repo's "<ip> <host>" line here so the package manager works
# ZERO-TOUCH out of the box (W6.4c). Same /etc/inet/hosts, same rule: NEVER touch
# network-config. Profile-driven: FB_REPO_HOST/FB_REPO_IP come from firstboot.conf.
#   * Both empty/absent  -> a profile without a repo is legal; skip, but LOG it.
#   * Duplicate-guarded  -> strip any prior line naming FB_REPO_HOST (as a
#     whitespace-delimited token) before appending exactly one, so a re-run (or a
#     repo host already present) can never accumulate duplicate lines.
if [ -n "$FB_REPO_HOST" ] && [ -n "$FB_REPO_IP" ]; then
	if [ -f /etc/inet/hosts ]; then
		# two -e expressions, never `\|` -- SVR4 sed has no alternation (see the
		# nodename guard above; measured 2026-08-12, this line's alternation form
		# matched nothing and the repo host was appended twice on a re-run).
		sed -e "/[ 	]$FB_REPO_HOST[ 	]/d" \
		    -e "/[ 	]$FB_REPO_HOST\$/d" \
			/etc/inet/hosts > /etc/inet/hosts.rp$$
		echo "$FB_REPO_IP	$FB_REPO_HOST" >> /etc/inet/hosts.rp$$
		mv /etc/inet/hosts.rp$$ /etc/inet/hosts
		chmod 444 /etc/inet/hosts
		echo "firstboot: added repo host $FB_REPO_IP $FB_REPO_HOST to /etc/inet/hosts (network-config UNTOUCHED)"
	else
		echo "firstboot: WARNING: /etc/inet/hosts absent -- cannot bake repo host $FB_REPO_HOST" >&2
	fi
else
	echo "firstboot: no repo host in profile (FB_REPO_HOST/FB_REPO_IP empty) -- skipping repo hosts entry"
fi

# --- 5c. the package-repo URL -> /etc/apkg.conf (W5) -------------------------
# install.sh writes /etc/apkg.conf on the miniroot from the profile's FB_REPO_URL.
# The first-boot dialog can NAME A DIFFERENT REPOSITORY HOST, and it rewrites the
# URL's host when it does -- so if the conf's URL and the file's `repo=` line have
# parted company, the file follows the answer. Guarded three ways: no key, no
# file, or no difference => no write at all, which is every unattended install.
if [ -n "$FB_REPO_URL" ] && [ -f /etc/apkg.conf ]; then
	cur=`sed -n 's/^repo=//p' /etc/apkg.conf`
	if [ "$cur" != "$FB_REPO_URL" ]; then
		sed "s|^repo=.*|repo=$FB_REPO_URL|" /etc/apkg.conf > /etc/apkg.conf.fb$$ \
			&& mv /etc/apkg.conf.fb$$ /etc/apkg.conf
		chmod 644 /etc/apkg.conf
		echo "firstboot: /etc/apkg.conf repo= now $FB_REPO_URL (was $cur)"
	fi
fi

# --- 5d. the address-by-card table -> /etc/inet/zen.conf (P-3) --------------
# One image, several Z3660 cards: /etc/rc2.d/S99zen reads zen0's MAC at every
# boot and takes that card's address + nodename from /etc/inet/zen.conf
# (docs/address-by-card.md). The profile carries the table as FB_ZEN_CARDS
# ("MAC=ADDR=NAME ..." words); S99zen's own `mkconf` verb renders it, so the file
# format has exactly one writer. Written ONCE: an existing zen.conf is the
# operator's and is never touched. S99zen runs later in this same rc2 pass, so the
# very first boot already comes up at the card's address.
if [ "$FB_ETHER_IF" = zen0 ] && [ -n "$FB_ZEN_CARDS" ] && [ -f /etc/rc2.d/S99zen ]; then
	if [ -f /etc/inet/zen.conf ]; then
		echo "firstboot: /etc/inet/zen.conf already present -- left as it is"
	elif /sbin/sh /etc/rc2.d/S99zen mkconf $FB_ZEN_CARDS > /etc/inet/zen.cf$$; then
		mv /etc/inet/zen.cf$$ /etc/inet/zen.conf
		chmod 644 /etc/inet/zen.conf
		echo "firstboot: wrote /etc/inet/zen.conf (address by card: $FB_ZEN_CARDS)"
	else
		rm -f /etc/inet/zen.cf$$
		echo "firstboot: WARNING: could not render /etc/inet/zen.conf -- zen0 keeps the laydown address" >&2
	fi
fi

# --- 6. regenerate /dev for the real hardware -------------------------------
# /usr/amiga/lib/atdevs is a PROBE, not a generator: it opens /dev/dsk/c0d0s0,
# c1..c7 in turn and prints which controllers answer -- it mknods NOTHING (the
# stock core /dev already ships the full static node grid). "regenerating /dev"
# is a misnomer; on a machine whose /dev is already the stock grid the probe
# only DETECTS controllers and changes no node.
#
# ★ SKIP THE PROBE WHEN ROOT IS NOT ON CARD 0. FB_SCSI_ID is the destination
# controller number (card*8 + unit, hex); card 0 is ids 0..7, card 1 is 8..f (ced0 = e =
# card 1 unit 6), cards 2-3 are 10..1f (C4-1 §2.2).
# A card-1 root means this is the real Z3660 under amix_mode NO, where card 0 is
# the PHANTOM A3091 -- and atdevs's very first open, /dev/dsk/c0d0s0, bus-errors
# in the driver's initialize() -> a supervisor-mode KERNEL PANIC (pc=0x800D578,
# vector 2), METAL-CONFIRMED 2026-09-14 on the installed 060 first boot (double
# panic). The stock /dev already carries the card-1 nodes (ced0/c8d0), so there
# is nothing to detect and everything to lose: skip it. A card-0 root (ids 0..7:
# the 030/040 bench line, e.g. c6d0) keeps the historical probe -- there card 0
# IS the real HBA and answering is correct. Derived from FB_SCSI_ID, never a
# separate key, so a card-1 install can never forget to skip and panic.
case "$FB_SCSI_ID" in
	[0-7])
		if [ -x /usr/amiga/lib/atdevs ]; then
			# atdevs's EXIT STATUS IS MEANINGLESS: its main() probes c0..c6d0s0 (4
			# skipped), prints each unit whose 512-byte read succeeds ("%d\n") and
			# falls off its end with NO return -- the status is whatever the last
			# library call left in d0, i.e. printf's byte count when unit 6 answers,
			# which is every healthy c6d0 root (disassembled 2026-09-29; the K1-T
			# metal boot printed a "returned nonzero" WARNING with /dev intact).
			# So report WHAT it found and never judge the status.
			_atd=`/usr/amiga/lib/atdevs 2>&1`
			echo "firstboot: /dev probe (atdevs): card-0 disk units answering:" $_atd
		else
			echo "firstboot: WARNING: /usr/amiga/lib/atdevs not present -- /dev not regenerated" >&2
		fi
		;;
	*)
		echo "firstboot: /dev regeneration SKIPPED -- root is not on card 0 (FB_SCSI_ID=$FB_SCSI_ID); atdevs probes card 0 only, and on the real LC060 card 0 is the phantom A3091 (bus error)"
		;;
esac

# --- 7. system logging on/off (FB_SYSLOG, W5) -------------------------------
# The installer lays the complete 2.1c syslog unit down ENABLED (the vendor ships
# /etc/init.d/syslogd dead, with a bare `exit` on line 8; the media staging
# comments it). FB_SYSLOG=n puts that `exit` back. FB_SYSLOG=y writes NOTHING --
# the unit is already enabled, so the default path does not touch the file at all
# and every pre-W5 install is byte-identical.
#
# ★ IN PLACE, NEVER `mv`. /etc/init.d/syslogd is ONE INODE with THREE names
# (/etc/rc2.d/S70syslogd and /etc/rc0.d/K50syslogd are hard links -- the stock
# topology). A `mv` would replace the inode behind the name we edited and leave
# the two rc links pointing at the OLD content, so the change would appear to work
# and then not survive a reboot. `cp` writes THROUGH the existing inode.
# 1.1: the syslog package's unit reads syslogd= from /etc/rc.conf (the installer
# wrote it from the profile); the dialog's answer replaces that one line
if [ "$FB_L11" = y ]; then
	sv=yes; [ "$FB_SYSLOG" = n ] && sv=no
	{ grep -v '^syslogd=' /etc/rc.conf 2>/dev/null; echo "syslogd=$sv"; } > /etc/rc.conf.fb$$ \
		&& cp /etc/rc.conf.fb$$ /etc/rc.conf && chmod 644 /etc/rc.conf
	rm -f /etc/rc.conf.fb$$
	echo "firstboot: /etc/rc.conf syslogd=$sv"
elif [ "$FB_SYSLOG" = n ] && [ -f /etc/init.d/syslogd ]; then
	if grep '^#exit$' /etc/init.d/syslogd > /dev/null 2>&1; then
		chmod 644 /etc/init.d/syslogd
		sed 's/^#exit$/exit/' /etc/init.d/syslogd > /tmp/syslogd.fb$$ \
			&& cp /tmp/syslogd.fb$$ /etc/init.d/syslogd
		rm -f /tmp/syslogd.fb$$
		chmod 544 /etc/init.d/syslogd
		if grep '^exit$' /etc/rc2.d/S70syslogd > /dev/null 2>&1; then
			echo "firstboot: system logging DISABLED (vendor exit restored, in place -- all 3 links)"
		else
			echo "firstboot: WARNING: could not disable syslogd (the rc2 link does not show the edit)" >&2
		fi
	fi
fi

# --- 8. network EXTRAS -- only what the first-boot DIALOG configured (W5) ----
# Everything below is gated on FB_NET_CONFIGURED=y, which ONLY the dialog sets.
# An unattended install therefore behaves exactly as it did before W5: its
# /etc/inet/hosts entry (section 5) and, for zen0 flavors, the installer's own
# S99zen laydown are the whole of its networking.
# 1.1: the dialog's answers become /etc/inet/interfaces; amix-base's ifup (S69inet,
# after this script) brings the interfaces up from it, writes this host's hosts row and the
# DNS parts. 8a-8c below are 1.0's.
fb_bits()
{
	case "$1" in
		255.0.0.0) echo 8 ;; 255.255.0.0) echo 16 ;; 255.255.240.0) echo 20 ;;
		255.255.248.0) echo 21 ;; 255.255.252.0) echo 22 ;; 255.255.254.0) echo 23 ;;
		255.255.255.0) echo 24 ;; 255.255.255.128) echo 25 ;; 255.255.255.192) echo 26 ;;
		255.255.255.224) echo 27 ;; 255.255.255.240) echo 28 ;; 255.255.255.248) echo 29 ;;
		255.255.255.252) echo 30 ;; *) echo "" ;;
	esac
}
if [ "$FB_L11" = y ] && [ "$FB_NET_CONFIGURED" = y ]; then
	b=`fb_bits "$FB_NETMASK"`
	{
		echo "# /etc/inet/interfaces -- written by firstboot.sh from the first-boot dialog; see interfaces(4)"
		if [ "$FB_NET_MODE" = dhcp ]; then
			if [ -n "$FB_NODENAME" ]; then
				echo "* dhcp name $FB_NODENAME"
			else
				echo "* dhcp"
				echo "hostname dhcp"
			fi
		else
			echo "$FB_ETHER_IF static $FB_IP${b:+/$b}${FB_GATEWAY:+ gw $FB_GATEWAY} name $FB_NAME_EFF"
		fi
		[ -z "$FB_DNS1$FB_DNS2" ] || echo "dns `echo $FB_DNS1 $FB_DNS2`"
		[ -z "$FB_DOMAIN" ] || echo "domain $FB_DOMAIN"
	} > /etc/inet/interfaces.fb$$ && mv /etc/inet/interfaces.fb$$ /etc/inet/interfaces && chmod 644 /etc/inet/interfaces
	if /usr/sbin/ifup -n > /tmp/ifup.fb$$ 2>&1; then
		echo "firstboot: /etc/inet/interfaces from the dialog (`grep -v '^#' /etc/inet/interfaces | head -1`)"
	else
		echo "firstboot: WARNING: /etc/inet/interfaces from the dialog does not pass ifup -n:" >&2
		cat /tmp/ifup.fb$$ >&2
	fi
	rm -f /tmp/ifup.fb$$
elif [ "$FB_L11" != y ] && [ "$FB_NET_CONFIGURED" = y ]; then

	# 8a. zen0: the laydown was written at INSTALL time from the profile's
	# address. If the operator named a different one, re-point the two
	# parameterized lines -- the file's BODY still has exactly one definition
	# (install.sh's emit_zen_hook, drift-locked against payload/S99zen), so this
	# is a parameter patch, never a second copy of the bring-up.
	if [ "$FB_ETHER_IF" = zen0 ] && [ -f /etc/rc2.d/S99zen ]; then
		# The route line is only re-pointed when there IS a gateway: an empty
		# FB_GATEWAY would otherwise write `route add default  1`, which is a
		# broken command in a boot script -- worse than the address the install
		# baked. No gateway answered means the laydown's own route stands.
		# P-3: the laydown carries its address as parameter LINES at the top
		# (FALLBACK= NETMASK= GATEWAY= DOMAIN=); a card row in /etc/inet/zen.conf
		# still wins over FALLBACK at boot -- the dialog's address is the one
		# for a card the table does not list.
		if [ -n "$FB_GATEWAY" ]; then
			sed -e "s|^FALLBACK=.*|FALLBACK=$FB_IP|" \
			    -e "s|^NETMASK=.*|NETMASK=$FB_NETMASK|" \
			    -e "s|^GATEWAY=.*|GATEWAY=$FB_GATEWAY|" \
			    -e "s|^DOMAIN=.*|DOMAIN=$FB_DOMAIN|" \
				/etc/rc2.d/S99zen > /etc/rc2.d/S99zen.fb$$
		else
			sed -e "s|^FALLBACK=.*|FALLBACK=$FB_IP|" \
			    -e "s|^NETMASK=.*|NETMASK=$FB_NETMASK|" \
			    -e "s|^DOMAIN=.*|DOMAIN=$FB_DOMAIN|" \
				/etc/rc2.d/S99zen > /etc/rc2.d/S99zen.fb$$
		fi
		if grep "^FALLBACK=$FB_IP\$" /etc/rc2.d/S99zen.fb$$ > /dev/null 2>&1 && \
		   grep "^NETMASK=$FB_NETMASK\$" /etc/rc2.d/S99zen.fb$$ > /dev/null 2>&1; then
			mv /etc/rc2.d/S99zen.fb$$ /etc/rc2.d/S99zen
			chmod 744 /etc/rc2.d/S99zen
			echo "firstboot: /etc/rc2.d/S99zen re-pointed at zen0 $FB_IP netmask $FB_NETMASK gw $FB_GATEWAY"
		else
			rm -f /etc/rc2.d/S99zen.fb$$
			echo "firstboot: WARNING: could not re-point /etc/rc2.d/S99zen -- leaving the laydown alone" >&2
		fi
	fi

	# 8b. aen0: the default route. The stock a2065 bring-up is
	# /etc/inet/network-config (NEVER edited) and it installs no route at all;
	# /etc/inet/rc.inet is the stock file that exists for exactly this -- it ends
	# with "# Add lines here to set up routes to gateways" and a commented
	# `#/usr/sbin/route add default your_nearest_gateway hops_to_gateway`.
	#
	# ED HALF-PATCH DISCIPLINE: pre-probe, ONE ed run, post-verify.
	#   pre-probe   exactly one `^exit ` line (the file's `exit $exitcode`) and NO
	#               live route-add already there -- never guess at a file we did
	#               not write
	#   one edit    insert the route line immediately above it
	#   post-verify the line is present EXACTLY once and `exit $exitcode` survived;
	#               otherwise the original is restored and nothing is claimed
	# The metric argument (`1`) is mandatory on this SVR4. rc.inet is mode 0444 and
	# a `net` package member, so this is the same recorded content-divergence class
	# as the /etc/shadow and /etc/TIMEZONE edits.
	if [ "$FB_ETHER_IF" != zen0 ] && [ -n "$FB_GATEWAY" ] && [ -f /etc/inet/rc.inet ]; then
		nex=`grep -c '^exit ' /etc/inet/rc.inet`
		nrt=`grep -c '^[ 	]*/usr/sbin/route add default' /etc/inet/rc.inet`
		if [ "$nex" = 1 ] && [ "$nrt" = 0 ]; then
			cp /etc/inet/rc.inet /tmp/rc.inet.fb$$
			chmod 644 /etc/inet/rc.inet
			{
				echo "/^exit /i"
				echo "/usr/sbin/route add default $FB_GATEWAY 1"
				echo "."
				echo "w"
				echo "q"
			} | ed - /etc/inet/rc.inet > /dev/null 2>&1
			got=`grep -c "^/usr/sbin/route add default $FB_GATEWAY 1\$" /etc/inet/rc.inet`
			kept=`grep -c '^exit ' /etc/inet/rc.inet`
			if [ "$got" = 1 ] && [ "$kept" = 1 ]; then
				echo "firstboot: default route $FB_GATEWAY written into /etc/inet/rc.inet (network-config UNTOUCHED)"
			else
				cp /tmp/rc.inet.fb$$ /etc/inet/rc.inet
				echo "firstboot: WARNING: the rc.inet route edit did not verify -- original restored" >&2
			fi
			chmod 444 /etc/inet/rc.inet
			rm -f /tmp/rc.inet.fb$$
		else
			echo "firstboot: /etc/inet/rc.inet already carries a default route (or does not have the expected shape) -- not editing it"
		fi
	fi

	# 8c. DNS -- ALL FIVE PARTS OR NONE (plan v3 section 3.4).
	#   1 /etc/resolv.conf              nameservers only, never `domain`/`search`
	#   2 libsocket.so -> libsockdns.so the gethostbyname() path (`ln -f`, atomic)
	#   3 /etc/netconfig <- .DNS        the TLI/netdir path (adds resolv.so)
	#   4 /etc/domain EMPTY             a set domain is appended to EVERY lookup by
	#                                   this resolver, even fully-qualified ones
	#   5 LITERAL-IP boot ifconfigs     with DNS on, a boot-time ifconfig that
	#                                   takes a NAME burns the full resolver
	#                                   retransmit (~90 s each) because it runs
	#                                   before the default route exists
	#
	# Part 5 is why this is zen0-only for now: our S99zen already uses a literal
	# address, but on aen0 the bring-up line lives in /etc/inet/network-config --
	# the one file this project never edits -- so DNS there would be half-applied,
	# and half-applied is exactly the 3-minutes-per-boot failure. The loopback half
	# of part 5 (S69inet's `ifconfig lo0 localhost`) is edited IN PLACE: that file
	# is a hard link to /etc/init.d/inetinit.
	if [ -n "$FB_DNS1" ]; then
		if [ "$FB_ETHER_IF" != zen0 ]; then
			echo "firstboot: DNS requested but the interface is $FB_ETHER_IF -- NOT applied."
			echo "firstboot:   enabling it needs a literal-IP boot ifconfig, and on this"
			echo "firstboot:   interface that line is in /etc/inet/network-config, which is"
			echo "firstboot:   never edited. Resolution stays /etc/inet/hosts."
		elif [ -f /usr/lib/libsockdns.so ] && [ -f /etc/netconfig.DNS ] && [ -f /etc/rc2.d/S69inet ]; then
			{
				echo "nameserver $FB_DNS1"
				if [ -n "$FB_DNS2" ]; then
					echo "nameserver $FB_DNS2"
				fi
			} > /etc/resolv.conf
			chmod 644 /etc/resolv.conf
			ln -f /usr/lib/libsockdns.so /usr/lib/libsocket.so
			cp /etc/netconfig.DNS /etc/netconfig
			cp /dev/null /etc/domain
			domainname "" 2>/dev/null || true
			if grep 'ifconfig lo0 localhost' /etc/rc2.d/S69inet > /dev/null 2>&1; then
				chmod 644 /etc/rc2.d/S69inet
				sed 's/ifconfig lo0 localhost up/ifconfig lo0 127.0.0.1 up/' \
					/etc/rc2.d/S69inet > /tmp/S69inet.fb$$ \
					&& cp /tmp/S69inet.fb$$ /etc/rc2.d/S69inet
				rm -f /tmp/S69inet.fb$$
				chmod 444 /etc/rc2.d/S69inet
			fi
			echo "firstboot: DNS enabled (resolv.conf, libsockdns, netconfig.DNS, empty /etc/domain, literal-IP lo0)"
		else
			echo "firstboot: WARNING: DNS requested but this system lacks libsockdns.so / netconfig.DNS -- NOT applied" >&2
		fi
	fi
fi

# --- 8b (1.1): the X11 and apkg PATH as /etc/profile.d drop-ins ------------
# /etc/profile is amix-base's conffile now; an edit would make the next update leave a .new.
# amix-base's /etc/profile reads /etc/profile.d/*.sh, so the two PATH additions go
# there, written by no package, until APKG and the X stack ship their own drop-ins. The
# desktop session is amix-base's xstart and its xsession: no /.xinitrc, no startx here.
if [ "$FB_L11" = y ]; then
	[ -d /etc/profile.d ] || mkdir /etc/profile.d
	if [ ! -f /etc/profile.d/x11.sh ]; then
		{
			echo "# /etc/profile.d/x11.sh -- written by firstboot.sh: the X server and clients"
			echo "# (/usr/bin/X11) and olwm's libXol.so (/usr/lib), for login shells only"
			echo 'case "$0" in'
			echo '"-rsh" | "-rksh" )	;;'
			echo '* )'
			echo '	PATH=$PATH:/usr/bin/X11'
			echo '	LD_LIBRARY_PATH=/usr/lib'
			echo '	export PATH LD_LIBRARY_PATH'
			echo '	;;'
			echo 'esac'
		} > /etc/profile.d/x11.sh
		chmod 644 /etc/profile.d/x11.sh
	fi
	if [ ! -f /etc/profile.d/opt-amix.sh ]; then
		{
			echo "# /etc/profile.d/opt-amix.sh -- written by firstboot.sh: apkg's /opt/amix/bin"
			echo "# LAST on PATH (stock tools keep precedence), for login shells only"
			echo 'case "$0" in'
			echo '"-rsh" | "-rksh" )	;;'
			echo '* )'
			echo '	PATH=$PATH:/opt/amix/bin'
			echo '	export PATH'
			echo '	;;'
			echo 'esac'
		} > /etc/profile.d/opt-amix.sh
		chmod 644 /etc/profile.d/opt-amix.sh
	fi
	echo "firstboot: /etc/profile.d/x11.sh and opt-amix.sh (X11 and apkg PATH; /etc/profile untouched)"
else
# --- 8b. X11 easy-start: /usr/bin/X11 on PATH, libXol on the linker path, and a
#         one-command `startx` (W6) -------------------------------------------
# The X packages (xcore/xbasic/olcore) install under /usr/X, with /usr/bin/X11 ->
# /usr/X/bin, and are NOT on the stock login PATH; olwm's shared library libXol.so
# lives in /usr/lib, which the X binaries' own linker path does not search. So a
# freshly `apkg install`ed X cannot be started by name -- the server is not found,
# and olwm cannot find libXol.so (both metal-observed 2026-09-15). We make the
# installed system X-READY here, BEFORE X is present: pure config, harmless until
# the X set lands the binaries, correct the moment it does. Stock /etc/profile
# (@(#)sadmin:etc/profile 2.3) sets PATH inside its `case "$0"` block and exports
# it with no /usr/bin/X11 and no LD_LIBRARY_PATH; stock /etc/default/login sets no
# PATH at all -- so /etc/profile is the one place to fix, for root and every user.
# We APPEND one guarded block (the grep guard makes a re-run -- a dialog that spans
# boots -- a no-op, which is what keeps this idempotent like everything above).
if [ -f /etc/profile ]
then
	# `if grep; then already; else append; fi` -- NOT `if ! grep`: the target
	# /bin/sh is the 1991 SVR4 Bourne shell, which has no `!` pipeline negation
	# (every guard in this file uses this shape; `[ ! -f ]` is test's operator, ok).
	if grep 'Installer-NG X11' /etc/profile > /dev/null 2>&1
	then
		echo "firstboot: /etc/profile already carries the X11 easy-start block (skipped)"
	else
		{
			echo ""
			echo "# Installer-NG X11 easy-start: the X server + clients are in /usr/bin/X11"
			echo "# (-> /usr/X/bin); olwm's libXol.so is in /usr/lib. Put both on the"
			echo "# paths -- but only for login/-su shells, skipping -rsh/-rksh exactly"
			echo "# as the stock case above does, so a restricted shell stays restricted."
			echo 'case "$0" in'
			echo '"-rsh" | "-rksh" )	;;'
			echo '* )'
			echo '	PATH=$PATH:/usr/bin/X11'
			echo '	LD_LIBRARY_PATH=/usr/lib'
			echo '	export PATH LD_LIBRARY_PATH'
			echo '	;;'
			echo 'esac'
		} >> /etc/profile
		echo "firstboot: /etc/profile += /usr/bin/X11 on PATH + /usr/lib on LD_LIBRARY_PATH (X easy-start)"
	fi
fi
# --- 8b(ii). apkg PATH: /opt/amix/bin appended LAST on PATH (owner rule: last,
#           never first -- stock tools keep precedence; overriding a stock command
#           is a later deliberate choice). apkg installs packages under /opt/amix/bin
#           (e.g. `less`), which the stock login PATH does not carry. Same one file
#           and same rules as the X11 append -- /etc/profile ONLY: root's login shell
#           is /bin/sh (empty passwd shell field) reading /etc/profile, /etc/default/
#           login carries NO PATH/SUPATH, and no per-user rc exists; a console bash is
#           a manual non-login child that INHERITS this PATH (all metal-verified by the
#           Z3660 station on the demo disk, 2026-09-16). Independent grep guard.
if [ -f /etc/profile ]
then
	if grep '/opt/amix/bin' /etc/profile > /dev/null 2>&1
	then
		echo "firstboot: /etc/profile already carries the /opt/amix/bin PATH block (skipped)"
	else
		{
			echo ""
			echo "# Installer-NG apkg PATH: /opt/amix/bin LAST (stock tools keep precedence)."
			echo 'case "$0" in'
			echo '"-rsh" | "-rksh" )	;;'
			echo '* )'
			echo '	PATH=$PATH:/opt/amix/bin'
			echo '	export PATH'
			echo '	;;'
			echo 'esac'
		} >> /etc/profile
		echo "firstboot: /etc/profile += /opt/amix/bin LAST on PATH (apkg tools: less, etc.)"
	fi
fi
# A default X session -- the OPEN LOOK desktop (olwm + the olwsm Workspace-menu
# daemon + a small client set) -- for root (~/ is /) and, via /etc/skel, every user
# made later. Written every run (idempotent: the same bytes overwrite). The clients
# resolve through the PATH added just above. Owner-approved layout, 2026-09-16.
#
# olwsm is the SEPARATE OPEN LOOK Workspace-menu daemon: olwm alone draws window
# frames but gives NO root menu (the "no window manager" look the owner hit). Start
# BOTH. `sleep 2` lets olwm own the screen before the clients map, else they come up
# undecorated. The final `exec xterm` is the session-controlling client -- when it
# exits the X session ends, which is why it is exec'd rather than backgrounded.
{
	echo "#!/bin/sh"
	echo "# Installer-NG default X session: the OPEN LOOK desktop (owner-approved)."
	echo "olwm &"
	echo "olwsm &"
	echo "sleep 2"
	echo "xclock -geometry 120x120-2+2 &"
	echo "xload -geometry 200x80-2+134 &"
	echo "olfm &"
	echo "xterm -geometry 80x20-2-2 -title Terminal-2 &"
	echo "exec xterm -geometry 80x24+2+2 -title Terminal"
} > /.xinitrc
# 755, NOT 644: a standard xinit EXECs ~/.xinitrc as the client and only falls back
# to running it through `sh` when it is X_OK -- a non-executable .xinitrc means xinit
# launches NO client, tears the server straight back down, and `startx` appears to
# start then instantly dies (adversarial-review finding, 2026-09-15).
chmod 755 /.xinitrc
if [ -d /etc/skel ]
then
	cp /.xinitrc /etc/skel/.xinitrc
	chmod 755 /etc/skel/.xinitrc
fi
# `startx`: run ~/.xinitrc's clients against the X2410 server named by ABSOLUTE
# path -- this rig's X package ships no `X' name link, so xinit cannot find the
# server by name. One command from a text login to the OpenLook desktop.
if [ -d /usr/local/bin ]
then
	{
		echo "#!/bin/sh"
		echo "# Installer-NG easy X start: ~/.xinitrc's clients on the X2410 server,"
		echo "# named by absolute path (this rig has no /usr/bin/X11/X name link)."
		echo 'exec xinit -- /usr/bin/X11/X2410 "$@"'
	} > /usr/local/bin/startx
	chmod 755 /usr/local/bin/startx
	echo "firstboot: X easy-start ready -- /.xinitrc + /etc/skel + /usr/local/bin/startx (after: apkg install xcore xbasic olcore, run 'startx')"
fi
fi	# FB_L11: 8b and 8b(ii) are 1.0's

# --- done: disarm so this runs exactly once --------------------------------
# ...unless the first-boot dialog is armed and has not completed yet: then the
# NEXT boot's dialog answers still need applying, so PENDING stays and this script
# runs again. Everything above is idempotent, which is what makes that safe.
if [ -n "$DIALOG_PENDING" ]; then
	echo "firstboot: mechanical steps applied; PENDING KEPT -- the configuration dialog"
	echo "firstboot: has not completed, so it will run again and be applied next boot."
	exit 0
fi
rm -f "$MARK"
# The seeded root hash has done its job (applied above, or superseded by the dialog's
# own password): do not leave a copy of a root credential lying in /var/adm.
rm -f "$FBDIR/root.shadow"
echo "firstboot: identity baked; NOT rebooting, NOT touching the clock. Done."
exit 0
