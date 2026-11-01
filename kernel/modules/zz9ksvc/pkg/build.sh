#!/bin/sh
# build.sh -- kernel/modules/zz9ksvc's kernel-space packages, zz9ksvc-k30
# (zz9ksvc30) and zz9ksvc-k46 (zz9ksvc46), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/modules/zz9ksvc/pkg/build.sh [k30|k46]...   (default: both)
#
# make dist's kspace step calls it, after the modules step has built
# kernel/modules/zz9ksvc/build/<line>/mod.d/zz9ksvc.  kernel/modules/pkg/kmod.sh
# does the work (its header has the outputs and exit statuses); pin.sh has the
# inputs.  Each line has its own prototype, since the whatis fragment's name
# (/opt/amix/man/whatis.d/<PKG>) is the line's instance.
#
# Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../pkg/kmod.sh"
kmod_roll "$@"
