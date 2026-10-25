#!/bin/sh
# kbootset-smoke-host.sh -- the host half of the kbootset smoke run: the
# same steps as kbootset-smoke.sh with the host build, on the files the
# box used, then the comparison.
#
# usage: kbootset-smoke-host.sh BOXDIR
#   BOXDIR  the box's run directory, copied back: boot1.img, boot2.bin,
#           unix, kb.img and smoke.log as the box left them
# Run from the repository root after `make tools`.
set -e
BOX=$1
H=${B:-build}/smoke-host
rm -rf "$H" && mkdir -p "$H"
cp "$BOX/boot1.img" "$BOX/boot2.bin" "$BOX/unix" "$H/"
cp tests/bench/kbootset-smoke.sh "$H/"
(cd "$H" && KB="$OLDPWD/${B:-build}/kbootset" sh kbootset-smoke.sh)
if cmp "$BOX/kb.img" "$H/kb.img"; then
	echo "kbootset-smoke: the box and the host wrote identical stores"
else
	echo "kbootset-smoke: the stores DIFFER" >&2
	exit 1
fi
# the logs, without the commands' paths
sed 's#^> [^ ]*kbootset#> kbootset#' "$BOX/smoke.log" > "$H/box.log"
sed 's#^> [^ ]*kbootset#> kbootset#' "$H/smoke.log" > "$H/host.log"
if diff "$H/box.log" "$H/host.log"; then
	echo "kbootset-smoke: identical output"
else
	echo "kbootset-smoke: output differs (above)" >&2
	exit 1
fi
${B:-build}/lsstore "$BOX/kb.img" 65536 | tail -1
