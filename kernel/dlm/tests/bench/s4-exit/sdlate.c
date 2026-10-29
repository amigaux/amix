/*
 * sdlate.c -- the stage-4 exit row "sd_register after sd's first open"
 * (contract C4-1 section 3, docs/abi/ddi.md): a boot-class module whose
 * _load, at the first sysinit entry, long after the root's open closed
 * registration, calls sd_register once.  The row passes when the core
 * prints its line and the call returns EBUSY.  It returns ENXIO, so
 * nothing stays linked.
 *
 * Built with the ABI kit (Makefile beside it); tests/bench/README.md.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/errno.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

/* never called: registration is closed */
static int
sdlate_queue(c, cp)
	unsigned c;
	char *cp;
{
	return 0;
}

static int
sdlate_load(params)
	char *params;
{
	int e = sd_register(sdlate_queue, 0, (char *)0, "sdlate", 1);

	printf("sdlate: sd_register -> %d, %s\n", e,
	    e == EBUSY ? "PASS: refused after sd's first open" : "FAIL: not EBUSY");
	return ENXIO;		/* silent, not linked */
}

static int
sdlate_unload()
{
	return 0;
}

MOD_MISC_WRAPPER(sdlate, sdlate_load, sdlate_unload, "stage-4 exit: sd_register after the first open");
