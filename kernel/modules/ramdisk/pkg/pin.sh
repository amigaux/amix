# pin.sh -- ramdisk-k30 / ramdisk-k46: the RAM disk (block major 20, unit 0
# the loader-placed miniroot, units 1-2 scratch disks) as a root-class kernel
# module (amix-dlm C3-5 sec 1, C4-2 sec 8), by sha256.  Sourced by build.sh.
#
# The objects are built by make dist's modules step (or `make -C
# kernel/modules/ramdisk/module`) into kernel/modules/ramdisk/build/<line>/
# mod.d/ramdisk.  Root class (majors=b:20), unload=never, params size1 and
# size2, no depend=.  The nodes /dev/dsk/ram0-2 are device entries in the
# module's class, ramdisk.
# 1.0.0-4 (2026-10-31): rolled from kernel/modules; the object and the payload
# are 1.0.0-3's.

KM_NAME=ramdisk
KM_SHORT=ramdisk
KM_REPO=kernel/modules/ramdisk
KM_VERSION=1.0.0-4

KM_K30_OBJ=kernel/modules/ramdisk/build/k30/mod.d/ramdisk
KM_K30_SHA=5523d8533d50840619d0a686bfbb02cf2eae50dee8746fbbd7561acea890c873
KM_K46_OBJ=kernel/modules/ramdisk/build/k46/mod.d/ramdisk
KM_K46_SHA=054467f6feadfa253b490cce95fa1350195cf6b3a8eefdaa4a14b47865f07bb6
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=7a68948b9dd41adb4f4d0aee1f4459aca2d0ef8a

KM_LICENCES="\
kernel/modules/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4"

KM_SOURCE_EPOCH=1793404800	# 2026-10-31 00:00 UTC
