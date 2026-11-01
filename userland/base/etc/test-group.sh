#!/bin/sh
# test-group.sh -- amix-base's /etc/group is the stock file with one line
# added: audio::20: after daemon.
#
#   sh userland/base/etc/test-group.sh
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
T=$(mktemp -d "${TMPDIR:-/tmp}/test-group.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }

sh "$here/mkgroup.sh" "$SYS" "$top/system/MANIFEST.sha256" "$T/group" && ok || bad "mkgroup.sh failed"
[ "$(grep -c '^audio::20:$' "$T/group")" -eq 1 ] && ok || bad "no single audio::20: line"
# right after daemon, so the file stays in gid order
[ "$(grep -A1 '^daemon::12:' "$T/group" | sed -n 2p)" = "audio::20:" ] && ok || bad "audio is not after daemon"
# every stock line is there, in order, and only the one line is added
[ "$(diff "$SYS/etc/group" "$T/group" | grep -c '^[<>]')" -eq 1 ] && ok || bad "more than the one line differs"
[ "$(diff "$SYS/etc/group" "$T/group" | grep '^>')" = "> audio::20:" ] && ok || bad "the added line is not audio::20:"
# names and gids stay unique
[ -z "$(cut -d: -f1 "$T/group" | sort | uniq -d)" ] && ok || bad "a group name is repeated"
[ -z "$(cut -d: -f3 "$T/group" | sort | uniq -d)" ] && ok || bad "a gid is repeated"
# four fields on every line, as the stock tools read them
awk -F: 'NF != 4 { exit 1 }' "$T/group" && ok || bad "a line has other than four fields"
# a stock file other than the manifest's is refused
mkdir -p "$T/sys/etc"; cp "$SYS/etc/group" "$T/sys/etc/group"
echo "x::99:" >> "$T/sys/etc/group"
sh "$here/mkgroup.sh" "$T/sys" "$top/system/MANIFEST.sha256" "$T/g2" 2>/dev/null && bad "a changed stock file was taken" || ok

echo "test-group: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
