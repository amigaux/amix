/*
 * t43boot.c -- S3-43: a boot-class misc module that may be unloaded.  It
 * prints its parameters when it loads (the manifest's param records reach
 * _load as one string) and says goodbye when it unloads.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

static int
t43boot_load(params)
	char *params;
{
	printf("t43boot: loaded, params \"%s\"\n", params ? params : "");
	return 0;
}

static int
t43boot_unload()
{
	printf("t43boot: goodbye\n");
	return 0;
}

MOD_MISC_WRAPPER(t43boot, t43boot_load, t43boot_unload, "S3-43 boot-class module");
