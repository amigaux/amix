#!/bin/sh
# build.sh -- kernel/drivers/gayle-ide's kernel-space packages, gayle-k30
# (gayle30) and gayle-k46 (gayle46), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/drivers/gayle-ide/pkg/build.sh [gayle]
#
# make dist's kspace step calls it, after the drivers step has built
# out/modules/<line>/gayle from the fork at kernel/drivers/gayle-ide/gayle-ide.pin.
# build/pkg/common/kdrv.sh does the work (its header has the outputs and exit
# statuses); pin.sh has the inputs.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../../build/pkg/common/kdrv.sh"
kdrv_roll "$@"
