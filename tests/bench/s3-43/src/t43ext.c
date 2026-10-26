/*
 * t43ext.c -- S3-43: a module that is in no generation.  Outside
 * development load the core refuses it (M-SIG3); under development load
 * it loads, and the console says so.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

static int
t43ext_load(params)
	char *params;
{
	printf("t43ext: loaded\n");
	return 0;
}

static int
t43ext_unload()
{
	return 0;
}

MOD_MISC_WRAPPER(t43ext, t43ext_load, t43ext_unload, "S3-43 outside the generation");
