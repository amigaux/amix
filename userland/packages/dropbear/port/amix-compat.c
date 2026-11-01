/*
 * amix-compat.c -- the functions amix-compat.h declares.  MIT, this
 * repository.
 */
#include <sys/types.h>
#include <sys/time.h>
#include <errno.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <utime.h>
#include <libgen.h>
#include <arpa/inet.h>
#include "amix-compat.h"
#include "fnmatch.h"

/*
 * nanosleep through poll(2), whose timeout is in milliseconds (the clock
 * ticks at 60 Hz, so a sleep is rounded up to a tick).  When a signal ends
 * it early, rem gets what is left, measured with gettimeofday.
 */
int
nanosleep(const struct timespec *req, struct timespec *rem)
{
	struct timeval t0, t1;
	long ms, done;

	if (req->tv_nsec < 0 || req->tv_nsec >= 1000000000L || req->tv_sec < 0) {
		errno = EINVAL;
		return -1;
	}
	ms = (long)req->tv_sec * 1000 + (req->tv_nsec + 999999L) / 1000000L;
	gettimeofday(&t0, NULL);
	if (poll(NULL, 0, (int)ms) == 0)
		return 0;
	if (rem != NULL) {
		gettimeofday(&t1, NULL);
		done = (t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_usec - t0.tv_usec) / 1000;
		if (done < 0)
			done = 0;
		ms -= done;
		if (ms < 0)
			ms = 0;
		rem->tv_sec = ms / 1000;
		rem->tv_nsec = (ms % 1000) * 1000000L;
	}
	errno = EINTR;
	return -1;
}

/*
 * vasprintf over the toolchain's C99 vsnprintf (libamixc99).
 */
int
vasprintf(char **ret, const char *fmt, va_list ap)
{
	char small[128];
	va_list aq;
	int n;

	*ret = NULL;
	va_copy(aq, ap);
	n = vsnprintf(small, sizeof(small), fmt, aq);
	va_end(aq);
	if (n < 0)
		return -1;
	if ((*ret = malloc((size_t)n + 1)) == NULL)
		return -1;
	if (vsnprintf(*ret, (size_t)n + 1, fmt, ap) != n) {
		free(*ret);
		*ret = NULL;
		return -1;
	}
	return n;
}

/*
 * inet_aton over inet_addr (libnsl), whose error value is also the
 * address 255.255.255.255: that one is accepted when it is spelled so.
 */
int
inet_aton(const char *cp, struct in_addr *addr)
{
	unsigned long a;

	a = inet_addr(cp);
	if (a == (unsigned long)-1 && strcmp(cp, "255.255.255.255") != 0)
		return 0;
	if (addr != NULL)
		addr->s_addr = a;
	return 1;
}

/*
 * fnmatch with no flags is the shell's pattern match, gmatch(3G).
 */
int
fnmatch(const char *pattern, const char *string, int flags)
{
	(void)flags;
	return gmatch(string, pattern) ? 0 : FNM_NOMATCH;
}

/*
 * utimes over utime(2): SVR4.0 keeps file times in whole seconds.
 */
int
utimes(const char *path, const struct timeval *tv)
{
	struct utimbuf ub;

	if (tv == NULL)
		return utime(path, NULL);
	ub.actime = tv[0].tv_sec;
	ub.modtime = tv[1].tv_sec;
	return utime(path, &ub);
}
