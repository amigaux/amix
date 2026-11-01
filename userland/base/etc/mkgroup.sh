#!/bin/sh
# mkgroup.sh -- amix-base's /etc/group: the stock one with the groups the
# add-on packages name added.
#
#   sh userland/base/etc/mkgroup.sh <amix-system checkout> <manifest> <out>
#
# The stock bytes are Commodore's and live only in amix-system (etc/group);
# the stock file is checked against its sha256 in system/MANIFEST.sha256
# first. Added, in gid order after daemon (12):
#
#   audio::20:   the sound device's group (its node is 0660 root audio)
#
# A package that lays a node or file owned by a group needs the group in
# the target's /etc/group when it is installed; pkgadd refuses a name it
# cannot resolve. Nothing else changes.
#
# MIT licence, see LICENSE at the top of the repository.
set -eu
stock="$1/etc/group"
want=$(awk '$2 == "etc/group" { print $1 }' "$2")
got=$(sha256sum < "$stock" | cut -c1-64)
[ -n "$want" ] && [ "$got" = "$want" ] || {
	echo "mkgroup.sh: $stock is $got, the manifest says ${want:-<none>}" >&2
	exit 1
}
# the gid and the name must both be free in the stock file
if awk -F: '$1 == "audio" || $3 == 20 { f = 1 } END { exit !f }' "$stock"; then
	echo "mkgroup.sh: $stock already has the name audio or gid 20" >&2
	exit 1
fi
[ "$(grep -c '^daemon::12:' "$stock")" -eq 1 ] || {
	echo "mkgroup.sh: $stock has no single daemon::12: line" >&2
	exit 1
}
sed '/^daemon::12:/a\
audio::20:' "$stock" > "$3"
