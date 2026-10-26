/*
 * t43leak.c -- S3-43: a module whose _unload forgets the interrupt
 * handler its _load attached.  The core's backstop removes it after the
 * unload and names it on the console.  The handler declines every
 * interrupt (it has no board), so the stock CIA-B handling goes on.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

static int
t43leak_intr(arg)
	char *arg;
{
	return 0;
}

static int
t43leak_load(params)
	char *params;
{
	int e = intr_attach(6, t43leak_intr, (char *)0, "t43leak");

	printf("t43leak: level-6 handler attached (%d)\n", e);
	return e;
}

static int
t43leak_unload()
{
	printf("t43leak: unloading without intr_detach\n");
	return 0;
}

MOD_MISC_WRAPPER(t43leak, t43leak_load, t43leak_unload, "S3-43 forgetful unload");
