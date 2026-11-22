/*
 * nl_types.h -- Amix's <nl_types.h> with XPG4's NL_CAT_LOCALE, which it
 * predates.  SVR4's catopen takes 0 for its flag and finds the catalog from
 * NLSPATH and LANG, so the flag is 0 here.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_NL_TYPES_H
#define AMIX_COMPAT_NL_TYPES_H
#include_next <nl_types.h>
#ifndef NL_CAT_LOCALE
#define NL_CAT_LOCALE	0
#endif
#endif
