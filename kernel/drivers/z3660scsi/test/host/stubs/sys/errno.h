#ifndef _HOSTTEST_SYS_ERRNO_H
#define _HOSTTEST_SYS_ERRNO_H
/* Just the errno values z3660.c returns (SVR4 values): ENXIO/ENOMEM from
 * z3660map(), EIO from z3660_rw() when a descriptor will not latch (ZS-05). */
#define EIO    5
#define ENXIO  6
#define ENOMEM 12
#endif
