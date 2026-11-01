#!/bin/sh
# kbmin.sh -- core/kbootset-min: one line, a kbootset package version, no
# newer than the kbootset recipe in pkg/kbootset (a floor names a version
# that is published).
set -u
cd "$(dirname "$0")/../.." || exit 1
f=core/kbootset-min
fail=0
ok() { echo "PASS kbmin: $1"; }
bad() { echo "FAIL kbmin: $1"; fail=1; }
[ "$(wc -l < "$f")" -eq 1 ] && ok "one line" || bad "$f is not one line"
v=$(cat "$f")
echo "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]{6}-[0-9]+$' && ok "form $v" || bad "form: '$v'"
kb=$(sed -n 's/^KB_VERSION=//p' pkg/kbootset/pin.sh)
[ -n "$kb" ] || bad "no KB_VERSION in pkg/kbootset/pin.sh"
lo=$(printf '%s\n%s\n' "$v" "$kb" | sort -V | head -1)
[ "$lo" = "$v" ] && ok "$v <= recipe $kb" || bad "$v is newer than the kbootset recipe $kb"
exit $fail
