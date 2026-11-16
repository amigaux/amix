#!/bin/sh
# mkshutdown.sh -- amix-base's /usr/sbin/shutdown: the stock script with its
# last line, the request to init, made a request that is seen through.
#
#   sh userland/base/rc/mkshutdown.sh <amix-system checkout> <manifest> <out>
#
# The stock bytes are Commodore's and live only in amix-system
# (usr/sbin/shutdown, core 2.1); the stock file is checked against its
# sha256 in system/MANIFEST.sha256 first. Its last line,
#
#	/sbin/init ${initstate}
#
# becomes /usr/sbin/initwait ${initstate} (initwait(1M)): the same request,
# then a look that init acted on it, and the request once more if it has
# not. Every line before it, and so every option, is the stock script's.
#
# MIT licence, see LICENSE at the top of the repository.
set -eu
OLD='/sbin/init ${initstate}'
NEW='/usr/sbin/initwait ${initstate}'
stock="$1/usr/sbin/shutdown"
want=$(awk '$2 == "usr/sbin/shutdown" { print $1 }' "$2")
got=$(sha256sum < "$stock" | cut -c1-64)
[ -n "$want" ] && [ "$got" = "$want" ] || {
	echo "mkshutdown.sh: $stock is $got, the manifest says ${want:-<none>}" >&2
	exit 1
}
[ "$(tail -n 1 "$stock")" = "$OLD" ] && [ "$(grep -c '/sbin/init' "$stock")" -eq 1 ] || {
	echo "mkshutdown.sh: $stock does not end with its one '$OLD' line" >&2
	exit 1
}
{ sed '$d' "$stock"; echo "$NEW"; } > "$3"
