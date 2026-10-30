/*
 * compat/wchar.h - minimal <wchar.h> for the Amix (SVR4.0) cross build.
 * SVR4.0 has no <wchar.h>; wchar_t and the multibyte/wide conversion
 * routines (mbstowcs, wcstombs, wctomb) live in <stdlib.h> and are
 * present in libc.  Only what libadm/puttext.c needs is provided here.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license (see amixcompat.h).
 */

#ifndef AMIX_COMPAT_WCHAR_H
#define AMIX_COMPAT_WCHAR_H

#include <stdlib.h>	/* wchar_t, MB_CUR_MAX, mbstowcs, wcstombs, wctomb */

#ifndef AMIX_HAVE_WINT_T
#define AMIX_HAVE_WINT_T
typedef long wint_t;
#endif

#ifndef WEOF
#define WEOF ((wint_t)-1)
#endif

extern int wcwidth(wchar_t);	/* compat/amixcompat.c */

#endif /* AMIX_COMPAT_WCHAR_H */
