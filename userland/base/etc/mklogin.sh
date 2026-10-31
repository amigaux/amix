#!/bin/sh
# mklogin.sh -- amix-base's /etc/default/login: the stock one with the file
# size limit of a login set to the largest file ufs takes.
#
#   sh userland/base/etc/mklogin.sh <amix-system checkout> <manifest> <out>
#
# The stock bytes are Commodore's and live only in amix-system
# (etc/default/login); the stock file is checked against its sha256 in
# system/MANIFEST.sha256 first. Its commented "#ULIMIT=4096" becomes
# ULIMIT=4194303 (512-byte blocks: 2 GiB less 512 bytes, the ufs per-file
# ceiling); without it a login's limit is the kernel's 524288 blocks
# (256 MiB), and a bigger file fails with EFBIG. Nothing else changes.
#
# MIT licence, see LICENSE at the top of the repository.
set -eu
ULIMIT=4194303
stock="$1/etc/default/login"
want=$(awk '$2 == "etc/default/login" { print $1 }' "$2")
got=$(sha256sum < "$stock" | cut -c1-64)
[ -n "$want" ] && [ "$got" = "$want" ] || {
	echo "mklogin.sh: $stock is $got, the manifest says ${want:-<none>}" >&2
	exit 1
}
[ "$(grep -c '^#ULIMIT=4096$' "$stock")" -eq 1 ] || {
	echo "mklogin.sh: $stock has no single #ULIMIT=4096 line" >&2
	exit 1
}
sed "s/^#ULIMIT=4096\$/ULIMIT=$ULIMIT/" "$stock" > "$3"
