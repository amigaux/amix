/*
 * compat/wctype.h - minimal <wctype.h> for the Amix (SVR4.0) cross build.
 * Only the classifiers used by libadm/puttext.c.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license (see amixcompat.h).
 */

#ifndef AMIX_COMPAT_WCTYPE_H
#define AMIX_COMPAT_WCTYPE_H

#include <stdlib.h>	/* wchar_t */

#ifndef AMIX_HAVE_WINT_T
#define AMIX_HAVE_WINT_T
typedef long wint_t;
#endif

#ifndef WEOF
#define WEOF ((wint_t)-1)
#endif

extern int iswspace(wchar_t);	/* compat/amixcompat.c */
extern int iswprint(wchar_t);	/* compat/amixcompat.c */
extern int iswalpha(wchar_t);	/* compat/amixcompat.c */
extern int iswdigit(wchar_t);	/* compat/amixcompat.c */

#endif /* AMIX_COMPAT_WCTYPE_H */
