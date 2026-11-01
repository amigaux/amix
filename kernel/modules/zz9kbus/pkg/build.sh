#!/bin/sh
# build.sh -- kernel/modules/zz9kbus's kernel-space packages, zz9kbus-k30
# (zz9kbus30) and zz9kbus-k46 (zz9kbus46), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/modules/zz9kbus/pkg/build.sh [k30|k46]...   (default: both)
#
# make dist's kspace step calls it, after the modules step has built
# kernel/modules/zz9kbus/build/<line>/mod.d/zz9kbus.  kernel/modules/pkg/kmod.sh
# does the work (its header has the outputs and exit statuses); pin.sh has the
# inputs.  One prototype serves both lines.
#
# MIT licence, see kernel/modules/LICENSE in the amix repository.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../pkg/kmod.sh"
kmod_roll "$@"
