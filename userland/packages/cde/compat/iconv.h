/*
 * iconv.h -- character set conversion for Amix, which has no iconv.
 *
 * Only the identity is supported: a conversion between two names of the
 * same single-byte set (the same name, or both among ISO-8859-1, ASCII, C
 * and POSIX in their usual spellings) copies the bytes; any other pair
 * fails at iconv_open with EINVAL, which CDE's callers treat as "no
 * conversion".  Amix's locales are single-byte.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_ICONV_H
#define AMIX_COMPAT_ICONV_H

#include <stddef.h>
#include <errno.h>
#include <string.h>
#include <ctype.h>

typedef void *iconv_t;

static inline int
amix_iconv_latin1(const char *n)
{
	static const char *const names[] = { "iso-8859-1", "iso8859-1", "iso_8859-1",
		"latin1", "ascii", "us-ascii", "ansi_x3.4-1968", "c", "posix", 0 };
	char low[32];
	int i;

	for (i = 0; n[i] && i < 31; i++)
		low[i] = (char)tolower((unsigned char)n[i]);
	low[i] = '\0';
	for (i = 0; names[i]; i++)
		if (strcmp(low, names[i]) == 0)
			return 1;
	return 0;
}

static inline iconv_t
iconv_open(const char *to, const char *from)
{
	if (strcmp(to, from) == 0 || (amix_iconv_latin1(to) && amix_iconv_latin1(from)))
		return (iconv_t)1;
	errno = EINVAL;
	return (iconv_t)-1;
}

static inline size_t
iconv(iconv_t cd, char **in, size_t *inleft, char **out, size_t *outleft)
{
	size_t n;

	if (cd != (iconv_t)1) {
		errno = EBADF;
		return (size_t)-1;
	}
	if (in == NULL || *in == NULL)
		return 0;
	n = *inleft < *outleft ? *inleft : *outleft;
	memcpy(*out, *in, n);
	*in += n; *out += n; *inleft -= n; *outleft -= n;
	if (*inleft > 0) {
		errno = E2BIG;
		return (size_t)-1;
	}
	return 0;
}

static inline int
iconv_close(iconv_t cd)
{
	(void)cd;
	return 0;
}

#endif /* AMIX_COMPAT_ICONV_H */
