#!/bin/sh
# test-login.sh -- amix-base's /etc/default/login is the stock file with one
# line changed: ULIMIT=4194303 for the stock "#ULIMIT=4096".
#
#   sh userland/base/etc/test-login.sh
#
# Needs the amix-system checkout: AMIX_SYSTEM, else the one beside the main
# working tree (as build/pkg/layout.sh finds it).
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../.." && pwd)
main=$(cd "$(git -C "$top" rev-parse --git-common-dir)/.." && pwd)
SYS=${AMIX_SYSTEM:-$(dirname "$main")/amix-system}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-login.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }

sh "$here/mklogin.sh" "$SYS" "$top/system/MANIFEST.sha256" "$T/login" && ok || bad "mklogin.sh failed"
[ "$(grep -c '^ULIMIT=4194303$' "$T/login")" -eq 1 ] && ok || bad "no single ULIMIT=4194303 line"
grep '^#ULIMIT' "$T/login" > /dev/null && bad "the commented ULIMIT is still there" || ok
# every other line is the stock one, in place
[ "$(diff "$SYS/etc/default/login" "$T/login" | grep -c '^[<>]')" -eq 2 ] && ok || bad "more than the one line differs"
[ "$(wc -l < "$T/login")" -eq "$(wc -l < "$SYS/etc/default/login")" ] && ok || bad "the line count changed"
grep '^#CONSOLE=/dev/console$' "$T/login" > /dev/null && ok || bad "CONSOLE is no longer the stock commented line"
# a stock file other than the manifest's is refused
mkdir -p "$T/sys/etc/default"; cp "$SYS/etc/default/login" "$T/sys/etc/default/login"
echo "# changed" >> "$T/sys/etc/default/login"
sh "$here/mklogin.sh" "$T/sys" "$top/system/MANIFEST.sha256" "$T/l2" 2>/dev/null && bad "a changed stock file was taken" || ok

echo "test-login: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
