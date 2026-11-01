#!/bin/sh
# build.sh -- kernel/drivers/z3660scsi's kernel-space packages, z3660scsi-k30
# (zscsi30) and z3660scsi-k46 (zscsi46), from the objects make dist's drivers
# step builds.  build/pkg/common/kdrv.sh does the work; pin.sh has the inputs.
#
# MIT licence, see kernel/drivers/z3660scsi/LICENSE in the amix repository.
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../../build/pkg/common/kdrv.sh"
kdrv_roll "$@"
