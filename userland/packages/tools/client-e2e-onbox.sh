#!/bin/sh
#
# client-e2e-onbox.sh -- the on-box CLIENT round trip for one catalog package:
# apkg install -> the package's own smoke -> pkgchk -> apkg remove -> gone.
#
#     sh client-e2e-onbox.sh <catalog-name> <pkginst> <probe-path> <smoke-dir> <cmd> [args...]
#
#   catalog-name  what a user types (`apkg install amix-benchmark`)
#   pkginst       the SVR4 PKG it lands as (`amixbench`) -- pkgchk takes this
#   probe-path    one file the package installs; must appear, then vanish
#   smoke-dir     directory holding the package's smoke fixtures ("-" = none)
#   cmd args      the smoke command, run inside smoke-dir; exit 0 = pass
#
# Runs ON THE BOX, as root, against whatever repo= /etc/apkg.conf names.  This
# is a SEPARATE proof from the recipe's bench smoke (stock pkgadd of a local
# .pkg): it exercises the catalog lookup, the HTTP fetch, the md5 check, and
# apkg's own pkgadd/pkgrm wrappers.  Written for the 1992 pre-POSIX Bourne
# shell (PORTING.md 3.6): backticks, `expr`, no `grep -q`, no printf(1).
# Prints one verdict line, `E2E <name> PASS|FAIL <reason>`, last.

name=$1; pkginst=$2; probe=$3; sdir=$4
if [ $# -lt 5 ]; then
	echo "usage: $0 <catalog-name> <pkginst> <probe-path> <smoke-dir> <cmd> [args...]"
	exit 2
fi
shift 4

APKG=/usr/apkg/bin/apkg
fail() { echo "E2E $name FAIL $*"; exit 1; }

echo "=== client E2E: $name (pkginst $pkginst) ==="
$APKG version
if [ -f "$probe" ]; then
	fail "$probe already present before install -- not a fresh install"
fi

echo "-- apkg install $name"
$APKG install "$name"
rc=$?
echo "     rc=$rc"
[ $rc -eq 0 ] || fail "apkg install rc=$rc"
[ -f "$probe" ] || fail "$probe not present after apkg install"
echo "ok   $probe installed"

echo "-- smoke: $*"
if [ "$sdir" != "-" ]; then
	cd "$sdir" || fail "cannot cd $sdir"
fi
"$@"
rc=$?
cd /
[ $rc -eq 0 ] || fail "smoke rc=$rc"
echo "ok   smoke passed"

echo "-- pkgchk $pkginst"
pkgchk "$pkginst"
rc=$?
[ $rc -eq 0 ] || fail "pkgchk rc=$rc"
echo "ok   pkgchk 0"

echo "-- apkg remove $name"
$APKG remove "$name"
rc=$?
echo "     rc=$rc"
[ $rc -eq 0 ] || fail "apkg remove rc=$rc"
[ -f "$probe" ] && fail "$probe still present after apkg remove"
if [ -d "/var/sadm/pkg/$pkginst" ]; then
	fail "/var/sadm/pkg/$pkginst still present after remove"
fi
echo "ok   $probe and /var/sadm/pkg/$pkginst gone"

echo "E2E $name PASS"
exit 0
