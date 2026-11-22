/*
 * sys/fs/ufs_fs.h -- Amix's <sys/fs/ufs_fs.h>, which uses MAXFRAG (the
 * fragments per block, 8 in UFS) though no Amix header defines it.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_SYS_FS_UFS_FS_H
#define AMIX_COMPAT_SYS_FS_UFS_FS_H
#ifndef MAXFRAG
#define MAXFRAG	8
#endif
#include_next <sys/fs/ufs_fs.h>
#endif
