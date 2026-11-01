#!/bin/bash
#
# build.sh -- build dbbench, the crypto measurement behind README.md's
# table, for the box (small and fast code) and for the build host.
#
#     sh build/pkg/pkgbuild.sh userland/packages/dropbear     # first: the tree
#     bash userland/packages/dropbear/tests/bench/build.sh <out dir>
#
# Takes the source tree the package build left (out/pkg/dropbear/work/,
# or under AMIX_BUILD_ROOT) and its compiler, rebuilds libtomcrypt,
# libtommath and the key-exchange objects with every algorithm Dropbear can
# offer (measure-options.h) and libtomcrypt's self tests, and links
# <out>/dbbench-1 (DROPBEAR_SMALL_CODE, as shipped), <out>/dbbench-0
# (unrolled) and <out>/dbbench-host.  Run `dbbench 5' on the box and
# `dbbench-host 1' here: every KAT line must say ok, and every DIGEST line
# must be the same on both.  The RSA keys are made here with openssl and
# are thrown away with the out dir.
# MIT, this repository.

set -eu
O=$(mkdir -p "${1:?usage: build.sh <out dir>}" && cd "$1" && pwd)
B=$(cd "$(dirname "$0")" && pwd)
PK=$(cd "$B/../.." && pwd)
TOP=$(cd "$PK/../../.." && pwd)
TREE=${AMIX_BUILD_ROOT:-$TOP/out/pkg}/dropbear/work/dropbear-2026.94
[ -f "$TREE/Makefile" ] || { echo "build.sh: no $TREE; build the package first" >&2; exit 1; }
CC68=$(sed -n 's/^CC=//p' "$TREE/Makefile")
CF68="-m68020-60 -mno-strict-align -O2 -Wall -fno-strict-overflow -Wno-pointer-sign -include $TOP/build/pkg/common/gcc14/amix-decls.h -include $PK/port/amix-compat.h -I$PK/port/include -DLTC_TEST"
OBJS="obj/curve25519.o obj/mlkem768.o obj/sntrup761.o obj/dh_groups.o obj/compat.o obj/dbctype.o"
DEFS="-I. -I./src -I./libtomcrypt/src/headers -I$O -DLOCALOPTIONS_H_EXISTS -DDROPBEAR_SERVER -DDROPBEAR_CLIENT"

# throwaway RSA keys, as n, e, d in hex
{
	echo "/* throwaway bench keys, made by build.sh */"
	for b in 2048 3072; do
		openssl genrsa -traditional $b 2>/dev/null | openssl rsa -traditional -outform DER 2>/dev/null |
			openssl asn1parse -inform DER | sed -n 's/.*INTEGER *:\([0-9A-F]*\)$/\1/p' |
			awk -v b=$b 'NR == 2 { print "static const char *rsa" b "_n = \"" $0 "\";" }
			             NR == 3 { print "static const char *rsa" b "_e = \"" $0 "\";" }
			             NR == 4 { print "static const char *rsa" b "_d = \"" $0 "\";" }'
	done
} > "$O/rsakeys.h"
[ "$(grep -c '^static' "$O/rsakeys.h")" = 6 ] || { echo "build.sh: openssl made no keys" >&2; exit 1; }

for small in 1 0; do
	T=$O/tree-$small
	rm -rf -- "${T:?}"; cp -r "$TREE" "$T"; cd "$T"
	{ cat "$B/measure-options.h"; echo "#define DROPBEAR_SMALL_CODE $small"; } > localoptions.h
	make clean > /dev/null 2>&1 || :
	make CC="$CC68" CFLAGS="$CF68" libtomcrypt/libtomcrypt.a libtommath/libtommath.a $OBJS > "$O/make-$small.log" 2>&1
	$CC68 $CF68 -DBENCH_SMALL=$small $DEFS -c "$B/dbbench.c" -o dbbench.o
	$CC68 -o "$O/dbbench-$small" dbbench.o $OBJS libtomcrypt/libtomcrypt.a libtommath/libtommath.a
	echo "built $O/dbbench-$small"
done

# the host build: the same source, configured for the host
T=$O/tree-host
rm -rf -- "${T:?}"; mkdir -p "$T"
tar xjf "${AMIX_BUILD_ROOT:-$TOP/out/pkg}/dropbear/src/dropbear-2026.94.tar.bz2" -C "$T" --strip-components=1
cd "$T"
./configure --disable-zlib --enable-bundled-libtom > "$O/host-configure.log" 2>&1
sed 's/^CFLAGS += /override CFLAGS += /' libtommath/Makefile > libtommath/Makefile.h && mv libtommath/Makefile.h libtommath/Makefile
{ cat "$B/measure-options.h"; echo "#define DROPBEAR_SMALL_CODE 1"; } > localoptions.h
make CFLAGS="-O2 -DLTC_TEST" libtomcrypt/libtomcrypt.a libtommath/libtommath.a $OBJS > "$O/make-host.log" 2>&1
gcc -O2 -DLTC_TEST -DBENCH_SMALL=1 $DEFS -c "$B/dbbench.c" -o dbbench.o
gcc -o "$O/dbbench-host" dbbench.o $OBJS libtomcrypt/libtomcrypt.a libtommath/libtommath.a
echo "built $O/dbbench-host"
