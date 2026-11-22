/*
 * stdio.h -- Amix's <stdio.h> and the calls CDE uses that Amix's libc
 * lacks, defined in this directory's lib/amix-compat.c.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_STDIO_H
#define AMIX_COMPAT_STDIO_H
#include_next <stdio.h>
#include <stdarg.h>
#ifdef __cplusplus
extern "C" {
#endif
extern int asprintf(char **, const char *, ...);
extern int vasprintf(char **, const char *, va_list);
#ifdef __cplusplus
}
#endif
#endif
