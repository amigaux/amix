#!/bin/sh
# build.sh -- kernel/drivers/cdfs's kernel-space packages, cdfs-k30
# (cdfs30) and cdfs-k46 (cdfs46), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/drivers/cdfs/pkg/build.sh [cdfs]
#
# make dist's kspace step calls it, after the drivers step has built
# out/modules/<line>/cdfs from the fork at kernel/drivers/cdfs/cdfs.pin.
# build/pkg/common/kdrv.sh does the work (its header has the outputs and exit
# statuses); pin.sh has the inputs.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../../build/pkg/common/kdrv.sh"
kdrv_roll "$@"
