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
# 1.0.0-3 (2026-11-01): a buffer freed after it was mapped is held until the open's
# close, since the mapping outlives its cookie; the page says so.
# 1.0.0-4 (2026-11-04): the copyright file says where the source is: the amix repository's
# URL and directories, the firmware's URL and commit.  The objects are -3's.

KM_NAME=zz9ksvc
KM_SHORT=zz9ksvc
KM_REPO=kernel/modules/zz9ksvc
KM_VERSION=1.0.0-4

KM_K30_OBJ=kernel/modules/zz9ksvc/build/k30/mod.d/zz9ksvc
KM_K30_SHA=e6703beebf86e6a9df496ae4f440e854eb4d3df6a2dc38dfeb7f70dc8fb66300
KM_K46_OBJ=kernel/modules/zz9ksvc/build/k46/mod.d/zz9ksvc
KM_K46_SHA=656815bcf6639cf7c1bf98110d8229c70455e07e3fb6d52ff3a802f180d86504
KM_K30_DEPS="kernel/modules/zz9kbus/build/k30/mod.d/zz9kbus 24c00be48a7fc76860d34680b57aab417889569979e63bd05479f96414d73703"
KM_K46_DEPS="kernel/modules/zz9kbus/build/k46/mod.d/zz9kbus 6ea8ca203303128f2e8cde46929dc79b36040e3dfcf8a95a257669428ecab776"

KM_KIT_COMMIT=3b53a8aad7c2bca344bfff064ef0b573b06a520f	# PIN gcc-2.7.2.3-33ebadc

KM_LICENCES="\
kernel/modules/zz9ksvc/LICENSE 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986"

KM_EXTRA_NOTE="This module is GPL-3.0-or-later as a whole: it carries the ZZ9000 SDK v2 headers of
BlitterStudio zz9000-firmware v2.9.1, GPL-3.0-or-later,
https://github.com/BlitterStudio/zz9000-firmware, directory sdk/include/zz9k, commit
ffaf221b2600d5c0586f225dcb7721529e7b3bba.

Source.  The corresponding source of this module is in the public amix repository,
https://github.com/amigaux/amix: the directory kernel/modules/zz9ksvc, which holds those
headers too; kernel/modules/zz9kbus, the module it depends on; the ABI kit, kernel/dlm; and
what builds and packages it, build/, kernel/modules/pkg, toolchain/, system/ and
kernel/port/port.pin, which also name the commits of the cross compiler, the kernel port and
the system files the build takes from their own public repositories.  The source for each
release of this package is at that release's revision of amix.  The source files of the object
in this package are unchanged since commit 5f28aeee911ae3ec1dfe554862eef3e816cbc067."

KM_FILES_COMMON="\
/opt/amix/man/7/zz9ksvc kernel/modules/zz9ksvc/man/zz9ksvc.7 4b3be70b587d7b298fc75575f2d124ec0d4d647378447b2d0a0004763f5f9d88 0644"
KM_WHATIS=kernel/modules/zz9ksvc/pkg/zz9ksvc.whatis
KM_WHATIS_SHA=6206dfb690f2c188e6fedd2655aed397c2dd1d8eb27fb51d8225789de7b7c5d8

KM_SOURCE_EPOCH=1793491200	# 2026-11-01 00:00 UTC
