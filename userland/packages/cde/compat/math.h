/*
 * math.h -- Amix's <math.h> and the C99 calls CDE uses that Amix's libm
 * predates, defined in this directory's lib/amix-compat.c.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_MATH_H
#define AMIX_COMPAT_MATH_H
#include_next <math.h>
#ifdef __cplusplus
extern "C" {
#endif
extern double round(double);
#ifdef __cplusplus
}
#endif
#endif
