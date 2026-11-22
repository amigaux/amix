/*
 * fnmatch.h -- POSIX fnmatch for Amix, which has only libgen's gmatch.
 * Defined in this directory's lib/amix-compat.c.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_FNMATCH_H
#define AMIX_COMPAT_FNMATCH_H
#define FNM_NOMATCH	1
#define FNM_NOESCAPE	0x01
#define FNM_PATHNAME	0x02
#define FNM_PERIOD	0x04
#ifdef __cplusplus
extern "C" {
#endif
extern int fnmatch(const char *, const char *, int);
#ifdef __cplusplus
}
#endif
#endif
