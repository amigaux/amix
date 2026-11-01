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
# 1.0.0-2 (2026-11-01): rebuilt on kit 3b53a8a (gcc-cross-amix 33ebadc); the
# code is unchanged, only .moddata cc= differs (gcc-2.7.2.3-33ebadc).

KM_NAME=zz9ksvc
KM_SHORT=zz9ksvc
KM_REPO=kernel/modules/zz9ksvc
KM_VERSION=1.0.0-2

KM_K30_OBJ=kernel/modules/zz9ksvc/build/k30/mod.d/zz9ksvc
KM_K30_SHA=44e03e1d3842422f0909e46b1955b99161d7edf94dcf85f99e5536655f1de351
KM_K46_OBJ=kernel/modules/zz9ksvc/build/k46/mod.d/zz9ksvc
KM_K46_SHA=6e860b5b63113fa64daea7c69ddcfc2932e59116cf9c2a5ee5832118e601571b
KM_K30_DEPS="kernel/modules/zz9kbus/build/k30/mod.d/zz9kbus 24c00be48a7fc76860d34680b57aab417889569979e63bd05479f96414d73703"
KM_K46_DEPS="kernel/modules/zz9kbus/build/k46/mod.d/zz9kbus 6ea8ca203303128f2e8cde46929dc79b36040e3dfcf8a95a257669428ecab776"

KM_KIT_COMMIT=3b53a8aad7c2bca344bfff064ef0b573b06a520f	# PIN gcc-2.7.2.3-33ebadc

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
