#!/bin/sh
# build.sh -- kernel/drivers/gayle-ide's kernel-space packages, amix-dlm C3-5
# sec 1: gayle-k30 (gayle30) and gayle-k46 (gayle46), recipe pkg/gayle/, and
# buddha-k30 (buddha30) and buddha-k46 (buddha46), recipe pkg/buddha/.
#
# usage: sh kernel/drivers/gayle-ide/pkg/build.sh [gayle] [buddha]
#
# make dist's kspace step calls it, after the drivers step has built
# out/modules/<line>/gayle and .../buddha from the fork at
# kernel/drivers/gayle-ide/gayle-ide.pin.  build/pkg/common/kdrv.sh does the
# work (its header has the outputs and exit statuses); each pin.sh has its
# recipe's inputs.  buddha rolls once the pinned fork has module/buddha.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../../build/pkg/common/kdrv.sh"
kdrv_roll "$@"
