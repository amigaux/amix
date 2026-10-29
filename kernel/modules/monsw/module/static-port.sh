#!/bin/sh
# static-port.sh -- prove that monsw/src/monsw.c, compiled without MONSW_MODULE, gives the
# same object as the 68040/68060 port's static copy (amix-040-060-port src/monsw.c), with the
# flags of the port's relink pass (relink-040-monsw.sh): AMIX_KERNEL_CFLAGS with -m68040,
# the port's Model-B sysroot, and <sys/monsw.h> from this repository's include/.
#
#   usage: sh monsw/module/static-port.sh [port-checkout]
#
# The port checkout (default amix-040-060-port beside the amix checkout, at the commit of
# kernel/port/port.pin) is only read: its src/monsw.c (PORT_MONSW_C overrides) and
# build/sysroot-modelb (made by the port's src/mk_modelb_sysroot.sh).  AMIX_KERNEL_CFLAGS
# comes from gcc-cross-amix's build/env.sh, sourced by the caller.  Exit 0 when the two
# objects are byte-identical.
set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
port=${1:-$top/../../../amix-040-060-port}
src=${PORT_MONSW_C:-$port/src/monsw.c}
[ -n "$AMIX_KERNEL_CFLAGS" ] || { echo "static-port: source gcc-cross-amix's build/env.sh first" >&2; exit 2; }
[ -f "$src" ] || { echo "static-port: no $src" >&2; exit 2; }
[ -d "$port/build/sysroot-modelb/usr/include" ] || { echo "static-port: no $port/build/sysroot-modelb (the port's src/mk_modelb_sysroot.sh makes it)" >&2; exit 2; }
out=$top/monsw/build/static-port
mkdir -p "$out"
AMIX_SYSROOT=$port/build/sysroot-modelb
export AMIX_SYSROOT
cf=$(echo "$AMIX_KERNEL_CFLAGS" | sed 's/-m68020/-m68040/')
m68k-cbm-sysv4-gcc $cf -I"$top/include" -c "$top/monsw/src/monsw.c" -o "$out/monsw-here.o"
m68k-cbm-sysv4-gcc $cf -I"$top/include" -c "$src" -o "$out/monsw-port.o"
cd "$out" && sha256sum monsw-here.o monsw-port.o
if cmp -s monsw-here.o monsw-port.o; then
	echo "static-port: identical"
else
	echo "static-port: the objects differ" >&2
	exit 1
fi
