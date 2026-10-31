#!/bin/sh
# build.sh -- kernel/modules/random's kernel-space packages, random-k30
# (random30) and random-k46 (random46), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/modules/random/pkg/build.sh [k30|k46]...   (default: both)
#
# make dist's kspace step calls it, after the modules step has built
# kernel/modules/random/build/<line>/mod.d/random.  kernel/modules/pkg/kmod.sh
# does the work (its header has the outputs and exit statuses); pin.sh has the
# inputs.  Each line has its own prototype, since the whatis fragment's name
# (/opt/amix/man/whatis.d/<PKG>) is the line's instance.
#
# MIT licence, see kernel/modules/LICENSE in the amix repository.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../pkg/kmod.sh"
kmod_roll "$@"
