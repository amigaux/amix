#ifndef _HOSTTEST_SYS_IMMU_H
#define _HOSTTEST_SYS_IMMU_H
/* The paging names the 030 map arm uses.  phystopfn() is the identity here, so
 * the mock sptalloc() sees the physical address and hands back the mock board
 * page that answers it. */
typedef unsigned long paddr_t;
#define PG_V		1
#define phystopfn(x)	((unsigned long)(x))
#endif
