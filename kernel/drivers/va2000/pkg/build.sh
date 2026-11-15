#!/bin/sh
# build.sh -- kernel/drivers/va2000's kernel-space packages, va2000-k30
# (va200030) and va2000-k46 (va200046), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/drivers/va2000/pkg/build.sh [va2000]
#
# make dist's kspace step calls it, after the drivers step has built
# out/modules/<line>/va2000 from the fork at kernel/drivers/va2000/va2000.pin.
# build/pkg/common/kdrv.sh does the work (its header has the outputs and exit
# statuses); pin.sh has the inputs.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../../build/pkg/common/kdrv.sh"
kdrv_roll "$@"
