#!/bin/sh
# mkprofile.sh -- amix-base's /etc/profile: the stock one with our lines added.
#
#   sh userland/base/etc/mkprofile.sh <amix-system checkout> <manifest> <out>
#
# The stock bytes are Commodore's and live only in amix-system (etc/profile,
# 2.1p2a); this repository holds just the lines we add, etc/profile.add. The
# stock file is checked against its sha256 in system/MANIFEST.sha256 first.
#
# MIT licence, see LICENSE at the top of the repository.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
stock="$1/etc/profile"
want=$(awk '$2 == "etc/profile" { print $1 }' "$2")
got=$(sha256sum < "$stock" | cut -c1-64)
[ -n "$want" ] && [ "$got" = "$want" ] || {
	echo "mkprofile.sh: $stock is $got, the manifest says ${want:-<none>}" >&2
	exit 1
}
cat "$stock" "$here/profile.add" > "$3"
