/*
 * stdlib.h -- Amix's <stdlib.h> and the calls CDE uses that Amix's libc
 * lacks, defined in this directory's lib/amix-compat.c.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_STDLIB_H
#define AMIX_COMPAT_STDLIB_H
#include_next <stdlib.h>
#ifdef __cplusplus
extern "C" {
#endif
extern int mkstemp(char *);
/* libc's pseudo-terminal calls, which no Amix header declares, and
 * posix_openpt (compat: open /dev/ptmx) */
extern int grantpt(int);
extern int unlockpt(int);
extern char *ptsname(int);
extern int posix_openpt(int);
#ifdef __cplusplus
}
#endif
#endif
