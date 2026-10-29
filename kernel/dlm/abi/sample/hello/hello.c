/*
 * hello.c -- the ABI kit's sample module: a misc module that prints its
 * parameters when it loads and says goodbye when it unloads.  A template:
 * a driver keeps this shape and uses MOD_DRV_WRAPPER with its cdevsw row
 * instead (the kit's docs/guide.md and docs/contracts/C3-6.md).
 *
 * K&R C: the kernel compiler runs with -traditional.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */

#include "sys/types.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

static char	greeting[32] = "hello";

/*
 * params: the manifest's "param hello.<name>=<value>" records as one
 * string ("greeting=hi"), or 0; valid only during _load, so copy it.
 */
static int
hello_load(params)
	char *params;
{
	char *p;
	int i;

	for (p = params; p && *p; p++)
		if (strncmp(p, "greeting=", 9) == 0 && (p == params || p[-1] == ' ')) {
			for (p += 9, i = 0; *p && *p != ' ' && i < sizeof(greeting) - 1; )
				greeting[i++] = *p++;
			greeting[i] = 0;
			break;
		}
	printf("hello: %s, on a 680%ld\n", greeting, DDI_CPUTYPE);
	return 0;
}

static int
hello_unload()
{
	printf("hello: goodbye\n");
	return 0;
}

MOD_MISC_WRAPPER(hello, hello_load, hello_unload, "the ABI kit's sample module");
