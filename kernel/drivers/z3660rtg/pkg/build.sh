#!/bin/sh
# build.sh -- kernel/drivers/z3660rtg's kernel-space packages, z3660rtg-k30
# (zrtg30) and z3660rtg-k46 (zrtg46), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/drivers/z3660rtg/pkg/build.sh [z3660rtg]
#
# make dist's kspace step calls it, after the drivers step has built
# out/modules/<line>/z3660rtg from the fork at kernel/drivers/z3660rtg/z3660rtg.pin.
# build/pkg/common/kdrv.sh does the work (its header has the outputs and exit
# statuses); pin.sh has the inputs.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../../build/pkg/common/kdrv.sh"
kdrv_roll "$@"
