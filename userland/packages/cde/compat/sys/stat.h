/*
 * sys/stat.h -- Amix's <sys/stat.h> with the POSIX file-type tests it
 * lacks: S_ISLNK and S_ISSOCK (Amix has S_IFLNK and S_IFSOCK).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_SYS_STAT_H
#define AMIX_COMPAT_SYS_STAT_H
#include_next <sys/stat.h>
#if !defined(S_ISLNK) && defined(S_IFLNK)
#define S_ISLNK(m)	(((m) & S_IFMT) == S_IFLNK)
#endif
#if !defined(S_ISSOCK) && defined(S_IFSOCK)
#define S_ISSOCK(m)	(((m) & S_IFMT) == S_IFSOCK)
#endif
#endif
