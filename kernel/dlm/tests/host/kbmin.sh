#!/bin/sh
# kbmin.sh -- core/kbootset-min: one line, a kbootset package version, no
# newer than the kbootset recipe in pkg/kbootset (a floor names a version
# that is published).  abi/registry/kbootset (C2-2 version 7): one line per
# row of abi/registry/majors, in its order, each a version in that form no
# newer than the recipe, or `-`.
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

# the kbootset each major needs
r=abi/registry/kbootset
want=$(sed 's/#.*//' abi/registry/majors | awk 'NF == 3 { print $1, $2 }')
got=$(sed 's/#.*//' "$r" | awk 'NF { print $1, $2 }')
[ -n "$want" ] && [ "$want" = "$got" ] && ok "$r: the rows of majors, in its order" ||
	bad "$r: rows differ from abi/registry/majors"
n=0
for v in $(sed 's/#.*//' "$r" | awk 'NF { if (NF != 3) print "bad-field-count"; else print $3 }'); do
	n=$((n + 1))
	[ "$v" = - ] && continue
	echo "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]{6}-[0-9]+$' || { bad "$r: form '$v'"; continue; }
	lo=$(printf '%s\n%s\n' "$v" "$kb" | sort -V | head -1)
	[ "$lo" = "$v" ] || bad "$r: $v is newer than the kbootset recipe $kb"
done
[ $fail -eq 0 ] && ok "$r: $n versions, each published or -"
exit $fail
