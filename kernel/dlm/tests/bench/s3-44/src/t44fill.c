/*
 * t44fill.c -- S3-44: fills the level-6 chain.  Its _load attaches one
 * declining handler per slot until intr_attach refuses (ECONFIG, 168, on
 * a full chain), and keeps them: a driver that attaches next falls back
 * to polled.  Its _unload detaches them all.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

#define	NTRY	16

static char	slot[NTRY];
static int	nheld;

static int
t44fill_h6(arg)
	char *arg;
{
	return 0;
}

static int
t44fill_load(params)
	char *params;
{
	int e = 0;

	for (nheld = 0; nheld < NTRY; nheld++)
		if ((e = intr_attach(6, t44fill_h6, slot + nheld, "t44fill")) != 0)
			break;
	printf("t44fill: level 6 took %d handlers, then error %d\n", nheld, e);
	return 0;
}

static int
t44fill_unload()
{
	int i, n = 0;

	for (i = 0; i < nheld; i++)
		if (intr_detach(6, t44fill_h6, slot + i) == 0)
			n++;
	printf("t44fill: %d of %d detached\n", n, nheld);
	return 0;
}

MOD_MISC_WRAPPER(t44fill, t44fill_load, t44fill_unload, "S3-44 full level-6 chain");
