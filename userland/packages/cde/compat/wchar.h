/*
 * wchar.h -- wide-character strings and I/O for Amix, which has no
 * <wchar.h>.  The functions are in this directory's lib/amix-compat.c;
 * wchar_t is Amix's own (<stdlib.h>), and a character is converted with
 * Amix's mbtowc and wctomb.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_WCHAR_H
#define AMIX_COMPAT_WCHAR_H

#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <wctype.h>

#ifdef __cplusplus
extern "C" {
#endif
extern size_t wcslen(const wchar_t *);
extern wchar_t *wcscpy(wchar_t *, const wchar_t *);
extern wchar_t *wcsncpy(wchar_t *, const wchar_t *, size_t);
extern wchar_t *wcscat(wchar_t *, const wchar_t *);
extern wchar_t *wcschr(const wchar_t *, wchar_t);
extern wchar_t *wcswcs(const wchar_t *, const wchar_t *);
extern int wcwidth(wchar_t);
extern int wcswidth(const wchar_t *, size_t);
extern wint_t fgetwc(FILE *);
extern wint_t fputwc(wchar_t, FILE *);
extern int fwprintf(FILE *, const wchar_t *, ...);
extern wint_t getwc(FILE *);
extern wint_t putwc(wchar_t, FILE *);
#ifdef __cplusplus
}
#endif

#endif /* AMIX_COMPAT_WCHAR_H */
