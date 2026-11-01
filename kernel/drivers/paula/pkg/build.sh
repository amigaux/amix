#!/bin/sh
# build.sh -- kernel/drivers/paula's kernel-space packages, paula-k30
# (paula30) and paula-k46 (paula46), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/drivers/paula/pkg/build.sh [paula]
#
# make dist's kspace step calls it, after the drivers step has built
# out/modules/<line>/paula from the fork at kernel/drivers/paula/paula.pin.
# build/pkg/common/kdrv.sh does the work (its header has the outputs and exit
# statuses); pin.sh has the inputs.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../../build/pkg/common/kdrv.sh"
kdrv_roll "$@"
