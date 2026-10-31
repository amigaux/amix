#!/bin/sh
# build.sh -- kernel/modules/ramdisk's kernel-space packages, ramdisk-k30
# (ramdisk30) and ramdisk-k46 (ramdisk46), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/modules/ramdisk/pkg/build.sh [k30|k46]...   (default: both)
#
# make dist's kspace step calls it, after the modules step has built
# kernel/modules/ramdisk/build/<line>/mod.d/ramdisk.  kernel/modules/pkg/kmod.sh
# does the work (its header has the outputs and exit statuses); pin.sh has the
# inputs.  Each line has its own prototype, since the whatis fragment's name
# (/opt/amix/man/whatis.d/<PKG>) is the line's instance.
#
# MIT licence, see kernel/modules/LICENSE in the amix repository.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../pkg/kmod.sh"
kmod_roll "$@"
