# pin.sh -- zz9ksvc-k30 / zz9ksvc-k46: the service channel of ZZ9000-family boards
# (/dev/zz9ksvc0, 1) as a kernel module (amix-dlm C3-5 sec 1, C3-6 sec 4), by sha256.
# Sourced by build.sh.
#
# Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
#
# The objects are built by make dist's modules step (or `make -C kernel/modules/zz9ksvc/
# module`) into kernel/modules/zz9ksvc/build/<line>/mod.d/zz9ksvc.  Demand class
# (majors=c:55, registered to zz9ksvc), unload=allowed, depend=zz9kbus.  The nodes
# /dev/zz9ksvc0 and 1 (c 55 0, c 55 1, 0666) are device entries in the module's class,
# zz9ksvc.  The directory is GPL-3.0-or-later (it carries the ZZ9000 SDK headers): the
# copyright file carries that licence and no other.
# 1.0.0-1 (2026-11-01): the first.

KM_NAME=zz9ksvc
KM_SHORT=zz9ksvc
KM_REPO=kernel/modules/zz9ksvc
KM_VERSION=1.0.0-1

KM_K30_OBJ=kernel/modules/zz9ksvc/build/k30/mod.d/zz9ksvc
KM_K30_SHA=d3a4712bcf48207545f1be5eb71005b7ad0cbd7fa4d1ca7bd338a99eb5857334
KM_K46_OBJ=kernel/modules/zz9ksvc/build/k46/mod.d/zz9ksvc
KM_K46_SHA=f57809022a5492e0d0e0d27995630dc733881bb7f4e80e503bd610341a61f108
KM_K30_DEPS="kernel/modules/zz9kbus/build/k30/mod.d/zz9kbus 20db776b49a85a2f89a9ef5392a29b8d24161494be9692d93805986f3eec2393"
KM_K46_DEPS="kernel/modules/zz9kbus/build/k46/mod.d/zz9kbus 1e571b9a479fe4e033fc869a7b2c1409f4652f974aaf0d87c1a3911114c00638"

KM_KIT_COMMIT=d68305af64c80ad6fb6b1019dd91a3ff2b7a75ee	# the registry with c 55 zz9ksvc

KM_LICENCES="\
kernel/modules/zz9ksvc/LICENSE 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986"

KM_EXTRA_NOTE="This module carries the ZZ9000 SDK v2 headers of BlitterStudio zz9000-firmware
v2.9.1 (commit ffaf221b2600d5c0586f225dcb7721529e7b3bba), GPL-3.0-or-later; the module as a
whole is GPL-3.0-or-later.  Its source is kernel/modules/zz9ksvc in the amix repository."

KM_FILES_COMMON="\
/opt/amix/man/7/zz9ksvc kernel/modules/zz9ksvc/man/zz9ksvc.7 714841887c1dca4755234cc4904d99c3d1ac0732e86d32bcc143cf4c3756f3e0 0644"
KM_WHATIS=kernel/modules/zz9ksvc/pkg/zz9ksvc.whatis
KM_WHATIS_SHA=6206dfb690f2c188e6fedd2655aed397c2dd1d8eb27fb51d8225789de7b7c5d8

KM_SOURCE_EPOCH=1793491200	# 2026-11-01 00:00 UTC
