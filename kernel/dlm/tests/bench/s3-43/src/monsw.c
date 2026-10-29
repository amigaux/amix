/*
 * monsw.c -- S3-43: a stand-in for monsw (S3-27), a character driver on
 * major 52 (registered to monsw), demand class and pinned as C3-6 has it,
 * so the dependency row (monsw before z3660rtg) runs before the real
 * module exists.  Its device reads as empty.  The rows install it on a
 * test box only, never beside the real package.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/conf.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

static int monsw_open() { return 0; }
static int monsw_close() { return 0; }
static int monsw_read() { return 0; }
static int monsw_write() { return 0; }
static int monsw_ioctl() { return 0; }

static int
monsw_load(params)
	char *params;
{
	printf("monsw: the S3-43 stand-in, loaded\n");
	return 0;
}

static int
monsw_unload()
{
	return 0;
}

struct mod_drv_data monsw_drvdata[] = {
	{ { 0 }, 0, 0, { monsw_open, monsw_close, monsw_read, monsw_write, monsw_ioctl }, 52, 1 }
};
MOD_DRV_WRAPPER(monsw, monsw_load, monsw_unload, 0, "S3-43 stand-in for monsw");
