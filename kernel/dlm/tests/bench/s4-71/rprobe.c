/*
 * rprobe.c -- S4-71's root-context probe (contract C4-2 section 2): a
 * root-class module whose _load, in marc_root, calls each DDI name C4-2
 * lets a root-class _load call although ddi.md marks it proc, and after
 * each one reads the status register's level and lbolt.  The row passes
 * when every call returns, the level stays 7 and lbolt does not move.
 * It returns ENXIO, so nothing stays linked.
 *
 * Built with the ABI kit (Makefile beside it); tests/bench/README.md, S4-71.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/param.h"
#include "sys/immu.h"
#include "sys/kmem.h"
#include "sys/errno.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern long	lbolt;
extern caddr_t	sptalloc();
extern void	sptfree();
extern int	autocon(), bprobe(), printf();
#ifdef k46_LINE
extern caddr_t	dev_kvmap();
extern void	dev_kvunmap();
#endif

#define	CUSTOM	0x00dff000	/* the custom chips: decoded on every Amiga */
#define	NOWHERE	0x7fff0000	/* Zorro III space no board holds */
#define	Z3660	0x144b0001	/* the Z3660's AutoConfig id */

static int	bad;		/* a level other than 7, or a moved lbolt */
static long	lb0;

static int
level()
{
	unsigned short s;

	__asm__ __volatile__("movew %%sr,%0" : "=d" (s));
	return (s >> 8) & 7;
}

/* after each call: its level, and the clock still stopped */
static void
after(what, v)
	char *what;
	long v;
{
	int l = level();

	if (l != 7 || lbolt != lb0)
		bad++;
	printf("rprobe: %s -> %x, level %d, lbolt %s\n", what, (int)v, l,
	    lbolt == lb0 ? "unmoved" : "MOVED");
}

static int
rprobe_load(params)
	char *params;
{
	unsigned base = 0, size = 0;
	volatile int spin;
	caddr_t va;
	char *p;

	lb0 = lbolt;
	printf("rprobe: root pass, level %d, lbolt %x\n", level(), (int)lb0);
	for (spin = 0; spin < 2000000; spin++)	/* about a tenth of a second */
		;
	after("a spin of 2000000", (long)spin);
	after("bprobe custom chips (dff004, read)", (long)bprobe((caddr_t)(CUSTOM + 4), -1));
	after("bprobe Zorro III nowhere (7fff0000, read)", (long)bprobe((caddr_t)NOWHERE, -1));
	after("autocon Z3660 (144b0001, index 0)", (long)autocon(Z3660, 0, &base, &size));
	if (base)
		printf("rprobe: autocon base %x size %x\n", base, size);
	va = sptalloc(1, PG_V, phystopfn((paddr_t)CUSTOM), 0);
	after("sptalloc 1 page of the custom chips", (long)va);
	if (va) {
		printf("rprobe: vposr through it %x\n", (int)*(volatile unsigned short *)(va + 4));
		sptfree(va, 1, 1);
		after("sptfree (flag 1)", 0L);
	}
#ifdef k46_LINE
	va = dev_kvmap((paddr_t)CUSTOM, 0x1000, 0x40, 1);
	after("dev_kvmap custom chips (cm 0x40, no sleep)", (long)va);
	if (va) {
		dev_kvunmap(va, 0x1000);
		after("dev_kvunmap", 0L);
	}
#endif
	p = kmem_alloc(65536, KM_NOSLEEP);
	after("kmem_alloc 65536 KM_NOSLEEP", (long)p);
	if (p) {
		kmem_free(p, 65536);
		after("kmem_free", 0L);
	}
	printf("rprobe: %s\n", bad ? "FAIL: a call left level 7 or let the clock run" :
	    "PASS: every call returned at level 7 with the clock stopped");
	return ENXIO;		/* silent, not linked (C4-2 section 2) */
}

static int
rprobe_unload()
{
	return 0;
}

MOD_MISC_WRAPPER(rprobe, rprobe_load, rprobe_unload, "S4-71 root-context probe");
