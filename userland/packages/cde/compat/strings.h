/*
 * strings.h -- the BSD string header, which Amix lacks: <string.h>, the
 * case-insensitive compares (libamixc99 has them), and the old BSD names
 * as the standard calls.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_STRINGS_H
#define AMIX_COMPAT_STRINGS_H
#include <string.h>
#ifdef __cplusplus
extern "C" {
#endif
extern int strcasecmp(const char *, const char *);
extern int strncasecmp(const char *, const char *, size_t);
#ifdef __cplusplus
}
#endif
#ifndef bcopy
#define bcopy(s, d, n)	memmove((d), (s), (n))
#endif
#ifndef bzero
#define bzero(d, n)	memset((d), 0, (n))
#endif
#ifndef bcmp
#define bcmp(a, b, n)	memcmp((a), (b), (n))
#endif
#ifndef index
#define index(s, c)	strchr((s), (c))
#endif
#ifndef rindex
#define rindex(s, c)	strrchr((s), (c))
#endif
#endif
