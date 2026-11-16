#!/bin/sh
# test-shutdown.sh -- amix-base's /usr/sbin/shutdown is the stock script with
# its last line, and only that, made the initwait request.
#
#   sh userland/base/rc/test-shutdown.sh
#
# Needs the amix-system checkout: AMIX_SYSTEM, else the one beside the main
# working tree (as build/pkg/layout.sh finds it); AMIX_MANIFEST, else
# system/MANIFEST.sha256.
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../.." && pwd)
main=$(cd "$(git -C "$top" rev-parse --git-common-dir)/.." && pwd)
SYS=${AMIX_SYSTEM:-$(dirname "$main")/amix-system}
MAN=${AMIX_MANIFEST:-$top/system/MANIFEST.sha256}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-shutdown.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $*"; }

sh "$here/mkshutdown.sh" "$SYS" "$MAN" "$T/shutdown" && ok || bad "mkshutdown.sh failed"
[ "$(tail -n 1 "$T/shutdown")" = '/usr/sbin/initwait ${initstate}' ] && ok || bad "the last line is not the initwait request"
# every other line is the stock one: dropping the last gives the stock file less its last
sed '$d' "$SYS/usr/sbin/shutdown" > "$T/stock-head"
sed '$d' "$T/shutdown" | cmp -s - "$T/stock-head" && ok || bad "a line other than the last differs from the stock file"
[ "$(wc -l < "$T/shutdown")" -eq "$(wc -l < "$SYS/usr/sbin/shutdown")" ] && ok || bad "the line count differs"
grep -q '/sbin/init ' "$T/shutdown" && bad "a direct /sbin/init request is left" || ok
sh -n "$T/shutdown" && ok || bad "the result does not parse"

# a stock file other than the manifest's is refused
mkdir -p "$T/sys/usr/sbin"; cp "$SYS/usr/sbin/shutdown" "$T/sys/usr/sbin/shutdown"
echo "# changed" >> "$T/sys/usr/sbin/shutdown"
sh "$here/mkshutdown.sh" "$T/sys" "$MAN" "$T/s2" 2>/dev/null && bad "a changed stock file was taken" || ok
# a file of the manifest's sha256 that does not end with the request is refused
printf '#!/sbin/sh\n/sbin/init ${initstate}\necho\n' > "$T/sys/usr/sbin/shutdown"
echo "$(sha256sum < "$T/sys/usr/sbin/shutdown" | cut -c1-64)  usr/sbin/shutdown" > "$T/man"
sh "$here/mkshutdown.sh" "$T/sys" "$T/man" "$T/s3" 2>/dev/null && bad "a file not ending with the request was taken" || ok
printf '#!/sbin/sh\n/sbin/init ${initstate}\n' > "$T/sys/usr/sbin/shutdown"
echo "$(sha256sum < "$T/sys/usr/sbin/shutdown" | cut -c1-64)  usr/sbin/shutdown" > "$T/man"
sh "$here/mkshutdown.sh" "$T/sys" "$T/man" "$T/s4" && ok || bad "a file ending with the one request was refused"
[ "$(cat "$T/s4")" = "$(printf '#!/sbin/sh\n/usr/sbin/initwait ${initstate}')" ] && ok || bad "the minimal file: [$(cat "$T/s4")]"

echo "test-shutdown: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
