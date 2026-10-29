/*
 * u4big.c -- U4 (kernel/dlm docs/spec/90-measurements.md): large kmem
 * requests, which the kernel routes to sptalloc, return or fail, never
 * hang.  Its _load asks kmem_zalloc for 64 KiB up to 2 MiB (the largest
 * module image, C3-1), first with KM_NOSLEEP and then with KM_SLEEP, in
 * the process context a module load has.  Each request's line is printed
 * before the call, so a hang shows which one; the lbolt ticks it took and
 * the address follow, and the memory is given back.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/kmem.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();
extern long	lbolt;

static int
u4big_load(params)
	char *params;
{
	static long sizes[] = { 65536L, 262144L, 524288L, 1048576L, 2097152L, 0 };
	static int flag[] = { KM_NOSLEEP, KM_SLEEP };
	static char *fname[] = { "KM_NOSLEEP", "KM_SLEEP" };
	long t;
	char *p;
	int f, k;

	for (f = 0; f < 2; f++)
		for (k = 0; sizes[k]; k++) {
			printf("u4big: kmem_zalloc(%d, %s) ...\n", (int)sizes[k], fname[f]);
			t = lbolt;
			p = (char *)kmem_zalloc((size_t)sizes[k], flag[f]);
			printf("u4big: ... %s at 0x%x after %d ticks\n", p ? "memory" : "failed",
			    (int)p, (int)(lbolt - t));
			if (p)
				kmem_free(p, (size_t)sizes[k]);
		}
	return 0;
}

static int
u4big_unload()
{
	return 0;
}

MOD_MISC_WRAPPER(u4big, u4big_load, u4big_unload, "U4 large kmem probe");
