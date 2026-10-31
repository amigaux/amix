/* amix-isinf.h -- C99 isinf, which Amix's <math.h> lacks: gcc's builtin.
 * Force-included by build.sh (MAKE_CFLAGS). */
#ifndef isinf
#define isinf(x) __builtin_isinf(x)
#endif
