#!/bin/sh
# hosttest.sh -- libzz9k's host test, without a box: the library as the package builds it
# (src/ copied, patches/ applied, compiled with ZZ9K_HOST_AMIX) against kernel/modules'
# zz9ksvc driver and its stand-in runtimes (tests/kern.c over zz9ksvc/test/td.h and fw.c),
# the library's system calls routed to the driver (tests/sysshim.c), the scenarios in
# tests/t.c.  It runs once with the k30 page size (2 KiB) and once with the k46 one (4 KiB).
# First it checks the upstream files against src/PROVENANCE.
#
#   usage: sh userland/packages/libzz9k/tests/hosttest.sh     (HOSTCC overrides cc)
#
# Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see LICENSE.
set -e
pkg=$(cd "$(dirname "$0")/.." && pwd)
top=$(cd "$pkg/../../.." && pwd)
km=$top/kernel/modules
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
cc=${HOSTCC:-cc}

# the upstream files, byte for byte
(cd "$pkg/src" && sed -n 's/^\([0-9a-f]\{64\}\)  \(.*\)$/\1  \2/p' PROVENANCE | sha256sum -c --quiet -) ||
	{ echo "hosttest: an upstream file differs from src/PROVENANCE" >&2; exit 1; }
nup=$(grep -c '^[0-9a-f]\{64\}  ' "$pkg/src/PROVENANCE")
echo "hosttest: $nup upstream files match src/PROVENANCE"

# the build's copy: src/ and the patches, as build/pkg's driver does it
cp -R "$pkg/src" "$tmp/src"
for p in "$pkg"/patches/*.patch; do
	(cd "$tmp/src" && patch -p1 -s --no-backup-if-mismatch < "$p") ||
		{ echo "hosttest: ${p##*/} does not apply" >&2; exit 1; }
done

for pg in 2048:11 4096:12; do
	nbpp=${pg%:*} shift=${pg#*:}
	kc="$cc -std=gnu89 -w -DTD_NBPP=$nbpp -DTD_PSHIFT=$shift"
	$kc -c -I"$km/zz9ksvc/sdk" -I"$km/zz9ksvc/src" -o "$tmp/wire.o" "$km/zz9ksvc/src/wire.c"
	$kc -c -I"$km/zz9ksvc/sdk" -I"$km/zz9ksvc/test" -o "$tmp/fw.o" "$km/zz9ksvc/test/fw.c"
	$kc -c -D_KERNEL -I"$km/zz9ksvc/test/stub-bus" -I"$km/include" -o "$tmp/bus.o" \
	    "$km/zz9kbus/src/zz9kbus.c"
	$kc -c -I"$km/zz9ksvc/test/stub" -I"$km/include" -I"$km/zz9ksvc/include" \
	    -I"$km/zz9ksvc/src" -I"$km/zz9ksvc/test" -o "$tmp/kern.o" "$pkg/tests/kern.c"
	lc="$cc -std=gnu17 -O1 -DZZ9K_HOST_AMIX=1 -DLIBZZ9K_VERSION=\"host\" -include sys/ioctl.h \
	    -I$tmp/src/include -I$km/zz9ksvc/include"
	$lc -w -c -o "$tmp/host.o" "$tmp/src/zz9k_host.c"
	$lc -Wall -Wextra -Werror -c -o "$tmp/amix.o" "$tmp/src/zz9k_amix.c"
	$lc -Wall -Werror -c -o "$tmp/zt.o" "$tmp/src/zz9k-test.c"
	$cc -std=gnu17 -O1 -c -o "$tmp/shim.o" "$pkg/tests/sysshim.c"
	$cc -std=gnu17 -O1 -Wall -I"$tmp/src/include" -I"$km/zz9ksvc/test" -c -o "$tmp/t.o" \
	    "$pkg/tests/t.c"
	$cc -o "$tmp/t" "$tmp/t.o" "$tmp/host.o" "$tmp/amix.o" "$tmp/kern.o" "$tmp/wire.o" \
	    "$tmp/fw.o" "$tmp/bus.o" "$tmp/shim.o" -lz
	printf 'page %s: ' "$nbpp"
	"$tmp/t"
done
