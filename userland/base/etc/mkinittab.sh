#!/bin/sh
# mkinittab.sh -- amix-base's /etc/inittab: the stock one with the dlm line
# as its first sysinit entry.
#
#   sh userland/base/etc/mkinittab.sh <amix-system checkout> <manifest> <out>
#
# The stock bytes are Commodore's and live only in amix-system (etc/inittab);
# the stock file is checked against its sha256 in system/MANIFEST.sha256
# first. The line goes right after line 1, the initdefault entry, so that
# modadmin -B runs before autopush, sioc and bcheckrc (C3-5 section 5,
# kernel/dlm/docs/contracts/C3-5-module-member.md, the authority for its text).
#
# MIT licence, see LICENSE at the top of the repository.
set -eu
DLM='dlm::sysinit:/sbin/modadmin -B </dev/console >/dev/console 2>&1'
stock="$1/etc/inittab"
want=$(awk '$2 == "etc/inittab" { print $1 }' "$2")
got=$(sha256sum < "$stock" | cut -c1-64)
[ -n "$want" ] && [ "$got" = "$want" ] || {
	echo "mkinittab.sh: $stock is $got, the manifest says ${want:-<none>}" >&2
	exit 1
}
case $(sed -n 1p "$stock") in
*:initdefault:*) ;;
*) echo "mkinittab.sh: line 1 of $stock is not the initdefault entry" >&2; exit 1 ;;
esac
{ sed -n 1p "$stock"; echo "$DLM"; sed 1d "$stock"; } > "$3"
