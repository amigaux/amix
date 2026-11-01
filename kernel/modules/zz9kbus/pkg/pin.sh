# pin.sh -- zz9kbus-k30 / zz9kbus-k46: the ZZ9000-family board registry as a kernel module
# (amix-dlm C3-5 sec 1), by sha256.  Sourced by build.sh.
#
# The objects are built by make dist's modules step (or `make -C kernel/modules/zz9kbus/
# module`) into kernel/modules/zz9kbus/build/<line>/mod.d/zz9kbus.  Misc module, boot class
# with match= the boards it serves, unload=never, no majors, no depend=.  Board driver
# packages and zz9ksvc need it.
# 1.0.0-1 (2026-11-01): the first.

KM_NAME=zz9kbus
KM_SHORT=zz9kbus
KM_REPO=kernel/modules/zz9kbus
KM_VERSION=1.0.0-1

KM_K30_OBJ=kernel/modules/zz9kbus/build/k30/mod.d/zz9kbus
KM_K30_SHA=20db776b49a85a2f89a9ef5392a29b8d24161494be9692d93805986f3eec2393
KM_K46_OBJ=kernel/modules/zz9kbus/build/k46/mod.d/zz9kbus
KM_K46_SHA=1e571b9a479fe4e033fc869a7b2c1409f4652f974aaf0d87c1a3911114c00638
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=d68305af64c80ad6fb6b1019dd91a3ff2b7a75ee	# the registry with c 55 zz9ksvc and the zz9k short names

KM_LICENCES="\
kernel/modules/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4"

KM_SOURCE_EPOCH=1793491200	# 2026-11-01 00:00 UTC
