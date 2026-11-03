# package.sh -- cdfs 1.1.0; assignments only.
# From amix-cdfs at kernel/drivers/cdfs/cdfs.pin (platform/amix/mount.c).
NAME=cdfs
PKG=cdfs
VERSION=1.1.0
PKGREV=1
SOURCE_EPOCH=1793664000   # 2026-11-03 00:00 UTC
SUMMARY="cdfs 1.1.0 - the mount helper for the cdfs CD filesystem"
DESC="mount -F cdfs <card>,<unit> <dir>; the filesystem itself is the cdfs-k30/cdfs-k46 kernel module. Installs /usr/lib/fs/cdfs/mount, the helper SVR4's mount(1M) execs for -F cdfs: it mounts read-only (mount(2) with MS_DATA and MS_RDONLY, type cdfs) and records the mount in /etc/mnttab with the mount point as the special, so mount, df and umount(1M) see it; and the mount point /cdrom. The spec is a SCSI card and target (0,2), not a /dev path. Built with GCC 14 from amix-cdfs, the fork the kernel module comes from. BSD 2-clause."
CATEGORY=system
SET=base
LICENSE="BSD-2-Clause"
FORKPIN=kernel/drivers/cdfs/cdfs.pin
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix
SYSTEM_PATHS="/usr/lib/fs/cdfs /cdrom"
DEPENDS=""
