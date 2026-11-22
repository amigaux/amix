/*
 * amix-compat.c -- the C library calls CDE uses that Amix (SVR4.0) lacks
 * and the toolchain's libamixc99 does not provide.  Declared in this
 * directory's overlay headers.
 * MIT licence, see LICENSE in userland/packages.
 */
#include <sys/types.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/*
 * mkstemp: replace the trailing XXXXXX of tmpl with letters and digits and
 * create the file, O_EXCL, mode 0600; another name on EEXIST.  Returns the
 * open descriptor, or -1 with errno set (EINVAL for a template without
 * six trailing X's).
 */
int
mkstemp(char *tmpl)
{
	static const char set[] =
		"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
	static unsigned long seq;
	size_t len = strlen(tmpl);
	char *x;
	unsigned long v;
	int tries, i, fd;

	if (len < 6 || strcmp(tmpl + len - 6, "XXXXXX") != 0) {
		errno = EINVAL;
		return -1;
	}
	x = tmpl + len - 6;
	for (tries = 0; tries < 10000; tries++) {
		v = ((unsigned long)getpid() << 16) ^ (unsigned long)time(NULL)
		    ^ (++seq * 2654435761UL);
		for (i = 0; i < 6; i++) {
			x[i] = set[v % 62];
			v /= 62;
		}
		fd = open(tmpl, O_RDWR | O_CREAT | O_EXCL, 0600);
		if (fd >= 0 || errno != EEXIST)
			return fd;
	}
	errno = EEXIST;
	return -1;
}

/*
 * strtok_r: strtok with the position kept in *save instead of a static.
 */
char *
strtok_r(char *s, const char *delim, char **save)
{
	char *tok;

	if (s == NULL)
		s = *save;
	if (s == NULL)
		return NULL;
	s += strspn(s, delim);
	if (*s == '\0') {
		*save = NULL;
		return NULL;
	}
	tok = s;
	s += strcspn(s, delim);
	if (*s != '\0')
		*s++ = '\0';
	else
		s = NULL;
	*save = s;
	return tok;
}

/*
 * Wide-character strings and I/O (compat <wchar.h>).  Amix's locales are
 * single-byte; a character is converted with Amix's mbtowc and wctomb.
 */
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <wchar.h>

size_t
wcslen(const wchar_t *s)
{
	const wchar_t *p = s;

	while (*p)
		p++;
	return (size_t)(p - s);
}

wchar_t *
wcscpy(wchar_t *d, const wchar_t *s)
{
	wchar_t *r = d;

	while ((*d++ = *s++) != 0)
		;
	return r;
}

wchar_t *
wcsncpy(wchar_t *d, const wchar_t *s, size_t n)
{
	wchar_t *r = d;

	for (; n > 0 && *s; n--)
		*d++ = *s++;
	for (; n > 0; n--)
		*d++ = 0;
	return r;
}

wchar_t *
wcscat(wchar_t *d, const wchar_t *s)
{
	wcscpy(d + wcslen(d), s);
	return d;
}

wchar_t *
wcschr(const wchar_t *s, wchar_t c)
{
	for (;; s++) {
		if (*s == c)
			return (wchar_t *)s;
		if (*s == 0)
			return NULL;
	}
}

wchar_t *
wcswcs(const wchar_t *s, const wchar_t *f)
{
	size_t n = wcslen(f), i;

	if (n == 0)
		return (wchar_t *)s;
	for (; *s; s++) {
		for (i = 0; i < n && s[i] == f[i]; i++)
			;
		if (i == n)
			return (wchar_t *)s;
	}
	return NULL;
}

/* columns a character takes: 0 for NUL, -1 for a non-printing one, else 1 */
int
wcwidth(wchar_t c)
{
	if (c == 0)
		return 0;
	if ((unsigned long)c < 256)
		return isprint((int)c) ? 1 : -1;
	return 1;
}

int
wcswidth(const wchar_t *s, size_t n)
{
	int w = 0, cw;

	for (; n > 0 && *s; n--, s++) {
		if ((cw = wcwidth(*s)) < 0)
			return -1;
		w += cw;
	}
	return w;
}

wint_t
fgetwc(FILE *f)
{
	char buf[8];
	wchar_t wc;
	int c, n = 0;

	while (n < (int)sizeof buf) {
		if ((c = getc(f)) == EOF)
			return WEOF;
		buf[n++] = (char)c;
		if (mbtowc(&wc, buf, (size_t)n) >= 0)
			return (wint_t)wc;
	}
	return WEOF;
}

wint_t
fputwc(wchar_t wc, FILE *f)
{
	char buf[8];
	int n, i;

	if ((n = wctomb(buf, wc)) < 0)
		return WEOF;
	for (i = 0; i < n; i++)
		if (putc(buf[i], f) == EOF)
			return WEOF;
	return (wint_t)wc;
}

/*
 * fwprintf: the format narrowed with wctomb and handed to vfprintf, with
 * %lc as %c (a wint_t is an int's size here, and a character one byte).
 * %ls is not supported; nothing in CDE passes one.
 */
#include <stdarg.h>

int
fwprintf(FILE *f, const wchar_t *fmt, ...)
{
	char nf[1024];
	size_t n = 0;
	int k, r;
	va_list ap;

	for (; *fmt && n + 8 < sizeof nf; fmt++) {
		if (fmt[0] == L'%' && fmt[1] == L'l' && fmt[2] == L'c') {
			nf[n++] = '%';
			nf[n++] = 'c';
			fmt += 2;
			continue;
		}
		if ((k = wctomb(nf + n, *fmt)) < 0)
			nf[n++] = '?';
		else
			n += (size_t)k;
	}
	nf[n] = '\0';
	va_start(ap, fmt);
	r = vfprintf(f, nf, ap);
	va_end(ap);
	return r;
}

wint_t
getwc(FILE *f)
{
	return fgetwc(f);
}

wint_t
putwc(wchar_t wc, FILE *f)
{
	return fputwc(wc, f);
}

/*
 * vasprintf, asprintf: print into a buffer malloc'd to fit (vsnprintf
 * from the toolchain's libamixc99 measures it).  -1 and *strp NULL on
 * failure.
 */
int
vasprintf(char **strp, const char *fmt, va_list ap)
{
	va_list aq;
	int n;

	*strp = NULL;
	va_copy(aq, ap);
	n = vsnprintf(NULL, 0, fmt, aq);
	va_end(aq);
	if (n < 0 || (*strp = malloc((size_t)n + 1)) == NULL)
		return -1;
	return vsnprintf(*strp, (size_t)n + 1, fmt, ap);
}

int
asprintf(char **strp, const char *fmt, ...)
{
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = vasprintf(strp, fmt, ap);
	va_end(ap);
	return n;
}

/*
 * posix_openpt: the master side of a STREAMS pseudo-terminal, SVR4's
 * /dev/ptmx (grantpt, unlockpt and ptsname are libc's).
 */
int
posix_openpt(int oflag)
{
	return open("/dev/ptmx", oflag);
}

/*
 * getdomainname: the secure RPC domain, SVR4's sysinfo(SI_SRPC_DOMAIN).
 */
#include <sys/utsname.h>
#include <sys/systeminfo.h>

int
getdomainname(char *name, int len)
{
	return sysinfo(SI_SRPC_DOMAIN, name, (long)len) < 0 ? -1 : 0;
}

/*
 * madvise: SVR4's memcntl(addr, len, MC_ADVISE, advice, 0, 0).
 */
#include <sys/mman.h>

int
madvise(void *addr, size_t len, int advice)
{
	return memcntl((caddr_t)addr, len, MC_ADVISE, (caddr_t)(long)advice, 0, 0);
}

/*
 * fnmatch: shell pattern matching, POSIX.  *, ?, [...] with ranges and !
 * or ^ to negate, \ to quote unless FNM_NOESCAPE; with FNM_PATHNAME a /
 * is matched only by a /, with FNM_PERIOD a leading . only by a . (after a
 * / too, with FNM_PATHNAME).  0 on a match, FNM_NOMATCH otherwise.
 */
#include <fnmatch.h>

static int
amix_fnm_leading(const char *s, const char *start, int flags)
{
	return (flags & FNM_PERIOD) && *s == '.' &&
	    (s == start || ((flags & FNM_PATHNAME) && s[-1] == '/'));
}

static int
amix_fnm(const char *p, const char *s, const char *start, int flags)
{
	for (;;) {
		char c = *p++;

		switch (c) {
		case '\0':
			return *s == '\0' ? 0 : FNM_NOMATCH;
		case '?':
			if (*s == '\0' || ((flags & FNM_PATHNAME) && *s == '/') ||
			    amix_fnm_leading(s, start, flags))
				return FNM_NOMATCH;
			s++;
			break;
		case '*':
			if (amix_fnm_leading(s, start, flags))
				return FNM_NOMATCH;
			while (*p == '*')
				p++;
			if (*p == '\0')
				return ((flags & FNM_PATHNAME) && strchr(s, '/')) ? FNM_NOMATCH : 0;
			for (; *s; s++) {
				if (amix_fnm(p, s, start, flags & ~FNM_PERIOD) == 0)
					return 0;
				if ((flags & FNM_PATHNAME) && *s == '/')
					break;
			}
			return amix_fnm(p, s, start, flags & ~FNM_PERIOD);
		case '[': {
			int neg, ok = 0;
			const char *q = p;

			if (*s == '\0' || ((flags & FNM_PATHNAME) && *s == '/') ||
			    amix_fnm_leading(s, start, flags))
				return FNM_NOMATCH;
			neg = (*q == '!' || *q == '^');
			if (neg)
				q++;
			do {
				char lo = *q++, hi;

				if (lo == '\0')		/* no closing ]: an ordinary [ */
					goto literal;
				if (lo == '\\' && !(flags & FNM_NOESCAPE) && *q)
					lo = *q++;
				hi = lo;
				if (*q == '-' && q[1] && q[1] != ']') {
					hi = q[1];
					q += 2;
					if (hi == '\\' && !(flags & FNM_NOESCAPE) && *q)
						hi = *q++;
				}
				if ((unsigned char)*s >= (unsigned char)lo &&
				    (unsigned char)*s <= (unsigned char)hi)
					ok = 1;
			} while (*q != ']');
			if (ok == neg)
				return FNM_NOMATCH;
			p = q + 1;
			s++;
			break;
		}
		case '\\':
			if (!(flags & FNM_NOESCAPE) && *p)
				c = *p++;
			/* FALLTHROUGH */
		default:
		literal:
			if (*s != c)
				return FNM_NOMATCH;
			s++;
			break;
		}
	}
}

int
fnmatch(const char *pattern, const char *string, int flags)
{
	return amix_fnm(pattern, string, string, flags);
}

/* strnlen: strlen, looking at most n bytes */
size_t
strnlen(const char *s, size_t n)
{
	size_t i;

	for (i = 0; i < n && s[i]; i++)
		;
	return i;
}

/*
 * round: to the nearest integer, halfway cases away from zero (C99).
 * Without libm, so that every program linking this library need not:
 * from 2^52 up a double is already an integer (and a NaN fails the test);
 * a zero is returned as it is, keeping its sign.
 */
double
round(double x)
{
	double a = x < 0.0 ? -x : x, t;

	if (!(a < 4503599627370496.0) || a == 0.0)
		return x;
	t = (double)(long long)a;
	if (a - t >= 0.5)
		t += 1.0;
	return x < 0.0 ? -t : t;
}
