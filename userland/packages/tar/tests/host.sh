#!/bin/bash
#
# host.sh -- the HOST side of tar's on-box acceptance (tools/pkg-smoke's host
# side runs it; bash, on the bench host, never on the box).
#
#     host.sh pre    nothing to prepare (the fixture is made by prepare.sh)
#     host.sh post   read the archive the box's tar wrote (smoke.sh leaves
#                    tests/out.tar; guest.sh brings it home inside out.tar) with
#                    the host's own tar: it lists, extracts, keeps the symlink
#                    as a symlink and records an owner name
#
# Env: HOSTWORK (scratch for this cell), RIG_CELL (the cell, holding out.tar).
# Prints RES lines.

set -u
case "$1" in
pre)
	;;
post)
	W=$HOSTWORK
	rm -rf "$W"; mkdir -p "$W/x"
	if ! tar -xf "${RIG_CELL:?}/out.tar" -C "$W" tar/tests/out.tar 2>/dev/null; then
		echo "RES host tar FAIL no tar/tests/out.tar came back from the box"
		exit 1
	fi
	A=$W/tar/tests/out.tar
	fails=0
	if tar -tvf "$A" > "$W/list" 2>&1; then
		echo "RES host tar ok   host tar lists the box's archive ($(wc -l < "$W/list") entries)"
	else
		echo "RES host tar FAIL host tar cannot list the box's archive"; fails=1
	fi
	if grep -q '^l.* x/fx/link -> target.txt' "$W/list"; then
		echo "RES host tar ok   the symlink is a symlink in the archive"
	else
		echo "RES host tar FAIL no x/fx/link symlink in the listing"; fails=1
	fi
	if grep -q ' bin/' "$W/list"; then
		echo "RES host tar ok   an owner name (bin) is recorded"
	else
		echo "RES host tar FAIL no owner name recorded"; fails=1
	fi
	if tar -xf "$A" -C "$W/x" --no-same-owner 2>"$W/x.err" && [ -L "$W/x/x/fx/link" ]; then
		echo "RES host tar ok   host tar extracts it, symlink included"
	else
		echo "RES host tar FAIL host tar extraction: $(head -1 "$W/x.err")"; fails=1
	fi
	[ $fails -eq 0 ] && echo "RES host tar PASS" || echo "RES host tar FAIL"
	;;
esac
