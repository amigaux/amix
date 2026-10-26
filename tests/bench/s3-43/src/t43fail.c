/*
 * t43fail.c -- S3-43: a module whose _load attaches an interrupt handler
 * and then fails (EIO).  The core calls its _unload, which forgets the
 * handler too; the backstop removes it, and the kernel is as it was
 * (80 section 3).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/errno.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

static int
t43fail_intr(arg)
	char *arg;
{
	return 0;
}

static int
t43fail_load(params)
	char *params;
{
	intr_attach(6, t43fail_intr, (char *)0, "t43fail");
	printf("t43fail: handler attached, failing with EIO\n");
	return EIO;
}

static int
t43fail_unload()
{
	return 0;
}

MOD_MISC_WRAPPER(t43fail, t43fail_load, t43fail_unload, "S3-43 failing load");
