/*
 * fnmatch.c -- fnmatch(3) for CDE, which Amix's C library lacks; a member of its
 * own in libamixcompat-cde.a, so a program that links another one first
 * (dtksh: libast's) takes that one alone.
 * MIT licence, see LICENSE in userland/packages.
 */
#include <string.h>
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
