#!/bin/sh
# test-profile.sh -- amix-base's /etc/profile is the stock file plus exactly
# etc/profile.add, and that addition sources the drop-ins.
#
#   sh userland/base/etc/test-profile.sh [shell]     (default sh)
#
# Needs the amix-system checkout: AMIX_SYSTEM, else the one beside the main
# working tree (as build/pkg/layout.sh finds it).
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../.." && pwd)
SH=${1:-sh}
main=$(cd "$(git -C "$top" rev-parse --git-common-dir)/.." && pwd)
SYS=${AMIX_SYSTEM:-$(dirname "$main")/amix-system}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-profile.XXXXXX")
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }

sh "$here/mkprofile.sh" "$SYS" "$top/system/MANIFEST.sha256" "$T/profile" && ok || bad "mkprofile.sh failed"
n=$(wc -c < "$SYS/etc/profile")
head -c "$n" "$T/profile" | cmp -s - "$SYS/etc/profile" && ok || bad "the stock bytes are not the start, unchanged"
tail -c +$((n + 1)) "$T/profile" | cmp -s - "$here/profile.add" && ok || bad "the rest is not exactly profile.add"
[ "$(grep -c . "$here/profile.add")" -eq 2 ] && ok || bad "profile.add is not one comment and one line"
# a stock file other than the manifest's is refused
cp -R "$SYS/etc" "$T/sys-etc" 2>/dev/null; mkdir -p "$T/sys"; mv "$T/sys-etc" "$T/sys/etc"
echo "# changed" >> "$T/sys/etc/profile"
sh "$here/mkprofile.sh" "$T/sys" "$top/system/MANIFEST.sha256" "$T/p2" 2>/dev/null && bad "a changed stock file was taken" || ok

# the added line sources every readable *.sh in /etc/profile.d, leaves no variable
sed 's|/etc/profile.d|'"$T"'/pd|g' "$here/profile.add" > "$T/add"
mkdir -p "$T/pd"
echo 'A=one' > "$T/pd/a.sh"; echo 'B=two' > "$T/pd/b.sh"; echo 'C=never' > "$T/pd/c.txt"
o=$($SH -c ". '$T/add'; echo \"\$A \$B \${C:-unset} \${_amx_f:-unset}\"")
[ "$o" = "one two unset unset" ] && ok || bad "drop-ins: got [$o]"
rm -f "$T/pd/"*
o=$($SH -c ". '$T/add'; echo ok")
[ "$o" = ok ] && ok || bad "an empty profile.d: got [$o]"
rmdir "$T/pd"
o=$($SH -c ". '$T/add'; echo ok")
[ "$o" = ok ] && ok || bad "no profile.d: got [$o]"

echo "test-profile: $pass passed, $fail failed ($SH)"
[ "$fail" -eq 0 ]
