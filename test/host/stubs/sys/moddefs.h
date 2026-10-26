#ifndef _HOSTTEST_SYS_MODDEFS_H
#define _HOSTTEST_SYS_MODDEFS_H
/* The harness calls a4091_load/a4091_halt directly: no wrapper. */
#define MOD_HDRV_WRAPPER(p, load, unload, halt, desc)	extern int p##_no_wrapper
#endif
