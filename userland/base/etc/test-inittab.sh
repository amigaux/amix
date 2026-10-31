#!/bin/sh
# test-inittab.sh -- amix-base's /etc/inittab is the stock file with exactly
# one line added: C3-5 section 5's dlm entry, as the first sysinit entry.
#
#   sh userland/base/etc/test-inittab.sh
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
C35="$top/kernel/dlm/docs/contracts/C3-5-module-member.md"
T=$(mktemp -d "${TMPDIR:-/tmp}/test-inittab.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }

sh "$here/mkinittab.sh" "$SYS" "$top/system/MANIFEST.sha256" "$T/inittab" && ok || bad "mkinittab.sh failed"
# the line is C3-5 section 5's, the one backquoted dlm::sysinit entry there
want=$(sed -n 's/^.*`\(dlm::sysinit:[^`]*\)`.*$/\1/p' "$C35" | sort -u)
[ -n "$want" ] && [ "$(echo "$want" | grep -c .)" -eq 1 ] && ok || bad "C3-5 does not give one dlm::sysinit line: [$want]"
[ "$(sed -n 2p "$T/inittab")" = "$want" ] && ok || bad "line 2 is not C3-5's: [$(sed -n 2p "$T/inittab")]"
# the first sysinit entry, after the initdefault line
[ "$(awk -F: '$3 == "sysinit" { print NR; exit }' "$T/inittab")" = 2 ] && ok || bad "the dlm line is not the first sysinit entry"
case $(sed -n 1p "$T/inittab") in *:initdefault:*) ok ;; *) bad "line 1 is not initdefault" ;; esac
# dropping it gives back the stock bytes
sed 2d "$T/inittab" | cmp -s - "$SYS/etc/inittab" && ok || bad "without line 2 the file is not the stock one"
[ $(($(wc -l < "$T/inittab") - $(wc -l < "$SYS/etc/inittab"))) -eq 1 ] && ok || bad "more than one line added"
# a stock file other than the manifest's is refused
mkdir -p "$T/sys/etc"; cp "$SYS/etc/inittab" "$T/sys/etc/inittab"
echo "# changed" >> "$T/sys/etc/inittab"
sh "$here/mkinittab.sh" "$T/sys" "$top/system/MANIFEST.sha256" "$T/i2" 2>/dev/null && bad "a changed stock file was taken" || ok

echo "test-inittab: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
