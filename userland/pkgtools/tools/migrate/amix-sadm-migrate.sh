#!/bin/sh
# amix-sadm-migrate.sh -- one-time /var/sadm migration for the apkg stack.
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Runs as root on Amix 2.1c under the stock pre-POSIX /bin/sh.  Written to
# the 1992 Bourne dialect on purpose: backticks, test, expr, case; nothing
# newer.  Idempotent -- a second run changes nothing and says so.
#
# Steps, per docs/design.md section 4:
#   1. once-only backup of /var/sadm/install/contents -> contents.pre-migrate
#   2. append VERSION=2.1 to every /var/sadm/pkg/*/pkginfo lacking VERSION=
#   3. mkdir missing /var/sadm/pkg/*/install dirs
#   4. chmod 644 /var/sadm/install/contents (factory ships it world-writable)
#   5. print a summary of every action
#
# Usage: amix-sadm-migrate.sh [-n]
#   -n   dry run: print what would be done, change nothing
#
# SADM_ROOT may be set in the environment as a path prefix (test trees,
# future -R support); default is empty, i.e. the real /var/sadm.

PATH=/bin:/usr/bin:$PATH
export PATH

dry=0
case "$1" in
'')
	;;
-n)
	dry=1
	;;
*)
	echo "usage: $0 [-n]"
	exit 1
	;;
esac

sadm=${SADM_ROOT}/var/sadm
contents=$sadm/install/contents

if test ! -d "$sadm"
then
	echo "amix-sadm-migrate: ERROR: $sadm is not a directory"
	exit 1
fi

if test $dry -eq 1
then
	echo "amix-sadm-migrate: DRY RUN - no changes will be made"
fi

nback=0
nver=0
ndir=0
nmode=0

# --- 1. once-only backup of the contents DB ------------------------------
if test -f "$contents"
then
	if test -f "$contents.pre-migrate"
	then
		echo "backup: contents.pre-migrate already exists - skipped"
	else
		if test $dry -eq 1
		then
			echo "backup: would copy contents to contents.pre-migrate"
		else
			cp "$contents" "$contents.pre-migrate"
			if test $? -ne 0
			then
				echo "amix-sadm-migrate: ERROR: backup of contents failed - aborting before any change"
				exit 1
			fi
			echo "backup: copied contents to contents.pre-migrate"
		fi
		nback=1
	fi
else
	echo "backup: WARNING: $contents does not exist - skipped"
fi

# --- 2 + 3. per-package pkginfo VERSION and install dirs -----------------
for d in $sadm/pkg/*
do
	test -d "$d" || continue
	p=$d/pkginfo
	if test -f "$p"
	then
		if grep '^VERSION=' "$p" > /dev/null 2>&1
		then
			:
		else
			if test $dry -eq 1
			then
				echo "pkginfo: would append VERSION=2.1 to $p"
			else
				echo "VERSION=2.1" >> "$p"
				echo "pkginfo: appended VERSION=2.1 to $p"
			fi
			nver=`expr $nver + 1`
		fi
	else
		echo "pkginfo: WARNING: $d has no pkginfo - skipped"
	fi
	if test -d "$d/install"
	then
		:
	else
		if test $dry -eq 1
		then
			echo "install: would create $d/install"
		else
			mkdir "$d/install"
			echo "install: created $d/install"
		fi
		ndir=`expr $ndir + 1`
	fi
done

# --- 4. contents must not stay world-writable ----------------------------
if test -f "$contents"
then
	mode=`ls -ld "$contents" | awk '{print $1}'`
	case "$mode" in
	-rw-r--r--*)
		echo "contents: mode already 644 - skipped"
		;;
	*)
		if test $dry -eq 1
		then
			echo "contents: would chmod 644 (now $mode)"
		else
			chmod 644 "$contents"
			echo "contents: chmod 644 (was $mode)"
		fi
		nmode=1
		;;
	esac
fi

# --- 5. summary -----------------------------------------------------------
total=`expr $nback + $nver + $ndir + $nmode`
echo ""
echo "summary:"
echo "  contents backup:          $nback"
echo "  VERSION=2.1 appended:     $nver"
echo "  install dirs created:     $ndir"
echo "  contents chmod 644:       $nmode"
if test $dry -eq 1
then
	echo "dry run: $total change(s) would be made"
else
	if test $total -eq 0
	then
		echo "nothing to do: $sadm is already migrated"
	else
		echo "done: $total change(s) made"
	fi
fi
exit 0
