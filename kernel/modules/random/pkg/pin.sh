# pin.sh -- random-k30 / random-k46: /dev/random and /dev/urandom as a kernel
# module (amix-dlm C3-5 sec 1, C3-6 sec 4), by sha256.  Sourced by build.sh.
#
# Not built here: make dist's modules step (or `make -C kernel/modules/random/
# module`) builds the object with the kit of each line into
#   kernel/modules/random/build/<line>/mod.d/random
# and the release is kernel/modules/random/module/VERSION.  build.sh verifies
# each object against the pins, checks VERSION, runs the kit's modcheck.py and
# rolls the object verbatim, with the files of KM_FILES beside it.
#
# Demand class (majors=c:48, registered to random since dlm a8719fb),
# unload=never, no param, no depend=.  The nodes /dev/random (c 48 0) and
# /dev/urandom (c 48 1) are device entries in the module's class, random
# (C3-5 v18 sec 1.2).
# -1 (2026-10-31): amix 3d4a48d (landed 516d467), kit 7a68948.

KM_NAME=random
KM_SHORT=random
KM_REPO=kernel/modules/random
KM_VERSION=1.0.0-1

KM_K30_OBJ=kernel/modules/random/build/k30/mod.d/random
KM_K30_SHA=680d975290028065825af793433ae5ea960bd3682a28cfc4e63f013e215450cf
KM_K46_OBJ=kernel/modules/random/build/k46/mod.d/random
KM_K46_SHA=f223164c7cecb10217f2905f78c69ab3269987cad5689953c623a8fc0d301bde
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=7a68948b9dd41adb4f4d0aee1f4459aca2d0ef8a	# c 48 random in the registry

KM_LICENCES="\
kernel/modules/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4"

# the files beside the module: the boot step (its rc2.d and rc0.d names are
# copies, not links: a kernel-space package is pure files), the pages and the
# whatis fragment, whose name is the package instance (build.sh adds it)
KM_FILES_COMMON="\
/etc/init.d/randseed kernel/modules/random/rc/randseed 40ec4d84a5b66ce8b070e161805b251514b0f1f2b4b5a72ed7af8a4d378149fe 0744
/etc/rc2.d/S21randseed kernel/modules/random/rc/randseed 40ec4d84a5b66ce8b070e161805b251514b0f1f2b4b5a72ed7af8a4d378149fe 0744
/etc/rc0.d/K02randseed kernel/modules/random/rc/randseed 40ec4d84a5b66ce8b070e161805b251514b0f1f2b4b5a72ed7af8a4d378149fe 0744
/opt/amix/man/7/random kernel/modules/random/man/random.7 69ee2d9e52a59421ad23cf188cb27a3fbce69a3a03049f80f42fae9ed05a5f24 0644
/opt/amix/man/1m/randseed kernel/modules/random/man/randseed.1m 696a48cc135c9a39cee162ff6e283ba1e84b1ce9b15ae8f2c8b15b1a10bc8c5f 0644"
KM_WHATIS=kernel/modules/random/pkg/random.whatis
KM_WHATIS_SHA=5b6711c0c00aa87f41e519dca5a49e488554bac480d95b9d1bfeb7d3415c2a50

KM_SOURCE_EPOCH=1793404800	# 2026-10-31 00:00 UTC
