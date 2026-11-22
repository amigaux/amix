/*
 * string.h -- Amix's <string.h> and the calls CDE uses that Amix's libc
 * lacks, defined in this directory's lib/amix-compat.c; and strdup and ffs,
 * which libc has but <string.h> declares only when __STDC__ is 0 (GCC
 * defines it as 1).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_STRING_H
#define AMIX_COMPAT_STRING_H
#include_next <string.h>
#ifdef __cplusplus
extern "C" {
#endif
extern char *strtok_r(char *, const char *, char **);
extern size_t strnlen(const char *, size_t);
extern char *strdup(const char *);
extern int ffs(int);
#ifdef __cplusplus
}
#endif
#endif
