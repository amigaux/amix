# pin.sh -- xsurf-k30 (xsurf30) / xsurf-k46 (xsurf46): the X-Surf and
# X-Surf-100 ethernet driver as a kernel module (amix-dlm C3-5 sec 1), by
# sha256.  Sourced by build.sh through build/pkg/common/kdrv.sh.
#
# The objects are make dist's drivers step's, out/modules/<line>/xsurf,
# built in the build container from kernel/drivers/xsurf/module.  Boot class
# (match=zorro:1212:64,zorro:1212:17, majors=c:56), no depend=.  The package
# ships the driver's link.d entry for ifup and the nodes /dev/xsf0 and
# /dev/xsf1 (c 56 0 and 1, mode 0600) in the module's class, xsurf.
#
# 1.0.0-1 (2026-11-14): the first package.  Module 1.0.0-1, kabi k30.1.2 /
# k46.1.2, built in amix-toolchain:dist against the kit of amix 1a3e7797
# (gcc-cross-amix 33ebadc).  Needs a kbootset whose registry has c 56 xsurf
# (1.1.0.261114-45 or later); no kbootset= key, no depend.
# 1.0.0-2 (2026-11-14): module 1.0.0-2, the status record's ack_retries
# counted and the console line's station address printed with leading zeros;
# tested in emulation on both lines (README, Tested).  Built in
# amix-toolchain:dist against the kit of amix 1a3e7797.

KM_NAME=xsurf
KM_SHORT=xsurf
KM_REPO=kernel/drivers/xsurf
KM_VERSION=1.0.0-2

KM_K30_SHA=d5541a4ca3bda1cc3aa11cd072eec301765aaae21ef7e2eaf57571655cddfe45
KM_K46_SHA=e7fab154950a9e7c968535c0e30f25ddde8efdbb6a814d97694b326ba405ec12
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=1a3e77979df2f22d613d715742e975e98fb2d5de

KM_LICENCES="\
kernel/drivers/xsurf/LICENSE fbc902eab45736ecf5baf223cbc0db0b03e9a7f3232caa5fdf8ddce4bb27a735
kernel/drivers/xsurf/NOTICE 61cdaa4de14fcb16e351c24244c7637c5b78d45da69a71975aec086f5a3de218"

# the driver's link.d entry, vendor data for ifup, shipped verbatim
KM_FILES_COMMON="\
/etc/inet/link.d/xsurf kernel/drivers/xsurf/link.d/xsurf b4b62296d468f10c4c847d41f6d54a92791d98be710600a91ad84578a1a3e0d3 0444"

KM_SOURCE_EPOCH=1794614400	# 2026-11-14 00:00 UTC
