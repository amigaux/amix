# pin.sh -- cdfs-k30 / cdfs-k46: the read-only CD filesystem (ISO 9660,
# Joliet, Rock Ridge, UDF, HFS) as a DEMAND-class kernel module (amix-dlm C3-5
# sec 1, C4-6), by sha256.  Sourced by kdrv.sh.
#
# The objects are make dist's drivers step's: the fork at
# kernel/drivers/cdfs/cdfs.pin built with this checkout's kit (kabi 1.4) into
# out/modules/<line>/cdfs.  The licence, NOTICE and module/VERSION are the
# fork's, in out/cache/forks/cdfs/.
#
# Demand class (match=always, fs=cdfs, unload=never), kabi k30.1.4 / k46.1.4:
# it loads at its first mount, which needs a module kernel of kabi minor 4
# composed by kbootset -31 or later.  cdfs cannot mount a root
# (vfs_mountroot returns EROFS).
# 1.1.0-5 (2026-11-01): the module 1.1.0-4 (fork e63c513), the same objects
# as the earlier 1.1.0-4 package, first rolled from amix.
# 1.1.0-6 (2026-11-01): the same module 1.1.0-4, built with the kit of toolchain
# pin gcc-2.7.2.3-33ebadc: the objects differ from 1.1.0-5 only in that tag.
# 1.1.0-7 (2026-11-02): the module 1.1.0-5 (fork 215936f): memset by bzero,
# no CDDA and no read-ahead on the AMIX kernel.

KM_NAME=cdfs
KM_SHORT=cdfs
KM_REPO=kernel/drivers/cdfs
KM_VERSION=1.1.0-5
KM_PKG_VERSION=1.1.0-7
KM_VERSION_FILE=out/cache/forks/cdfs/platform/amix-kernel/module/VERSION

KM_K30_SHA=01c02625064bb3b320418bfa5da1b338b88713a17ffab1b297b532c09ae4692e
KM_K46_SHA=75c9d3f53f2b072ed3ee4c51d26a48ea52b99aeef1e317813aef7b352f76e77a

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

# the fork's platform/amix-kernel/module/Makefile PAGESHIFT_OK: the k46 shifts
# by 11 in these functions are CD-sector divisions (offset / 2048), not page
# arithmetic; modcheck waives them there only
KM_PAGESHIFT_OK=cdfs_bytes_to_dev_blocks,iso_walk,iso_readlink,joliet_readdir,odfs_iso_merge_multi_extent,udf_mount,udf_read_bytes

KM_LICENCES="\
out/cache/forks/cdfs/LICENSE df5ce5f5f4957fa2acf3f62e2003de839cba331dad7f0721c58912e4f3710483
out/cache/forks/cdfs/NOTICE a93291f3425725079162f6556ad8e33083da8f14d865710923f57a29f9147cf3"

KM_EXTRA_NOTE="cdfs is a demand-class module: it loads at its first mount (mount -F
cdfs), on a module kernel of kabi minor 4 composed by kbootset -31 or later,
and is never unloaded.  'disable' in /etc/conf/modreg.local.d/cdfs keeps it
out.  cdfs cannot mount a root (vfs_mountroot returns EROFS): the 1.1 media
root on a RAM disk and mount the CD with cdfs.
The module is built from amix-cdfs's portable core and backends and its
platform/amix-kernel glue (BSD 2-clause, LICENSE below); the optional
3rdparty/libcodesets is not linked in."

KM_SOURCE_EPOCH=1793577600	# 2026-11-02 00:00 UTC
