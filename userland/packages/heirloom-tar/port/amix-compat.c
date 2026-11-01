/*
 * amix-compat.c -- the functions amix-compat.h declares.  MIT, this
 * repository.
 */
#include <sys/types.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "amix-compat.h"

#define LL_MAX	9223372036854775807LL
#define LL_MIN	(-LL_MAX - 1)

/*
 * strtoll as C99 has it: leading space, a sign, base 0 (0x hex, 0 octal,
 * else decimal) or 2..36; on overflow LL_MAX or LL_MIN and ERANGE.  The
 * value is gathered unsigned, so no signed arithmetic overflows.
 */
long long
strtoll(const char *s, char **end, int base)
{
	const char *p = s;
	unsigned long long v = 0, lim;
	int neg = 0, any = 0, over = 0, c;

	while (isspace((unsigned char)*p))
		p++;
	if (*p == '-' || *p == '+')
		neg = *p++ == '-';
	if ((base == 0 || base == 16) && p[0] == '0' &&
	    (p[1] == 'x' || p[1] == 'X') && isxdigit((unsigned char)p[2])) {
		p += 2;
		base = 16;
	} else if (base == 0)
		base = *p == '0' ? 8 : 10;
	if (base < 2 || base > 36) {
		errno = EINVAL;
		if (end)
			*end = (char *)s;
		return 0;
	}
	lim = neg ? (unsigned long long)LL_MAX + 1 : (unsigned long long)LL_MAX;
	for (;; p++) {
		c = (unsigned char)*p;
		if (c >= '0' && c <= '9')
			c -= '0';
		else if (c >= 'a' && c <= 'z')
			c -= 'a' - 10;
		else if (c >= 'A' && c <= 'Z')
			c -= 'A' - 10;
		else
			break;
		if (c >= base)
			break;
		any = 1;
		if (over)
			continue;
		if (v > (lim - c) / base)
			over = 1;
		else
			v = v * base + c;
	}
	if (end)
		*end = (char *)(any ? p : s);
	if (over) {
		errno = ERANGE;
		return neg ? LL_MIN : LL_MAX;
	}
	if (neg)
		return v == (unsigned long long)LL_MAX + 1 ? LL_MIN : -(long long)v;
	return (long long)v;
}

long long
atoll(const char *s)
{
	return strtoll(s, (char **)0, 10);
}

/*
 * mkstemp: the template's trailing XXXXXX made unique by mktemp(3C), the
 * file created 0600 with O_EXCL; tried again when another process took
 * the name in between.
 */
int
mkstemp(char *tmpl)
{
	size_t n = strlen(tmpl);
	char save[7];
	int fd, tries;

	if (n < 6 || strcmp(tmpl + n - 6, "XXXXXX") != 0) {
		errno = EINVAL;
		return -1;
	}
	memcpy(save, tmpl + n - 6, 7);
	for (tries = 0; tries < 100; tries++) {
		memcpy(tmpl + n - 6, save, 7);
		if (mktemp(tmpl) == NULL || *tmpl == '\0') {
			errno = EEXIST;
			return -1;
		}
		fd = open(tmpl, O_RDWR | O_CREAT | O_EXCL, 0600);
		if (fd >= 0 || errno != EEXIST)
			return fd;
	}
	return -1;
}
