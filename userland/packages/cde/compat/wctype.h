/*
 * wctype.h -- wide-character classification for Amix, which has none.
 *
 * Amix's libc knows wchar_t, mbtowc and wctomb (EUC as well), but it has
 * no <wctype.h>, and the locales Amix ships are single-byte.  A wide
 * character here is a byte value: each test is the <ctype.h> test for a
 * value below 256, and false above it.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_WCTYPE_H
#define AMIX_COMPAT_WCTYPE_H

#include <stddef.h>
#include <ctype.h>

#ifndef _WINT_T
#define _WINT_T
typedef long wint_t;
#endif
#ifndef WEOF
#define WEOF ((wint_t)-1)
#endif

#define AMIX_WC_BYTE(c)	((unsigned long)(c) < 256)
static inline int iswalnum(wint_t c)  { return AMIX_WC_BYTE(c) && isalnum((int)c); }
static inline int iswalpha(wint_t c)  { return AMIX_WC_BYTE(c) && isalpha((int)c); }
static inline int iswcntrl(wint_t c)  { return AMIX_WC_BYTE(c) && iscntrl((int)c); }
static inline int iswdigit(wint_t c)  { return AMIX_WC_BYTE(c) && isdigit((int)c); }
static inline int iswgraph(wint_t c)  { return AMIX_WC_BYTE(c) && isgraph((int)c); }
static inline int iswlower(wint_t c)  { return AMIX_WC_BYTE(c) && islower((int)c); }
static inline int iswprint(wint_t c)  { return AMIX_WC_BYTE(c) && isprint((int)c); }
static inline int iswpunct(wint_t c)  { return AMIX_WC_BYTE(c) && ispunct((int)c); }
static inline int iswspace(wint_t c)  { return AMIX_WC_BYTE(c) && isspace((int)c); }
static inline int iswupper(wint_t c)  { return AMIX_WC_BYTE(c) && isupper((int)c); }
static inline int iswxdigit(wint_t c) { return AMIX_WC_BYTE(c) && isxdigit((int)c); }
static inline wint_t towlower(wint_t c) { return AMIX_WC_BYTE(c) ? (wint_t)tolower((int)c) : c; }
static inline wint_t towupper(wint_t c) { return AMIX_WC_BYTE(c) ? (wint_t)toupper((int)c) : c; }

/* wctype and iswctype: a class is one of the tests above, by name */
typedef int wctype_t;
static inline wctype_t
wctype(const char *name)
{
	static const char *const n[] = { "alnum", "alpha", "cntrl", "digit", "graph",
		"lower", "print", "punct", "space", "upper", "xdigit" };
	int i;

	for (i = 0; i < 11; i++) {
		const char *a = n[i], *b = name;
		while (*a && *a == *b) { a++; b++; }
		if (*a == '\0' && *b == '\0')
			return i + 1;
	}
	return 0;
}
static inline int
iswctype(wint_t c, wctype_t t)
{
	switch (t) {
	case 1: return iswalnum(c);
	case 2: return iswalpha(c);
	case 3: return iswcntrl(c);
	case 4: return iswdigit(c);
	case 5: return iswgraph(c);
	case 6: return iswlower(c);
	case 7: return iswprint(c);
	case 8: return iswpunct(c);
	case 9: return iswspace(c);
	case 10: return iswupper(c);
	case 11: return iswxdigit(c);
	}
	return 0;
}

#endif /* AMIX_COMPAT_WCTYPE_H */
