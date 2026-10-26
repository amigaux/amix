/*
 * z3660rtg.c -- S3-43: a stand-in for z3660rtg (S3-26), a character
 * driver on major 49 (registered to z3660rtg), demand class, depending on
 * monsw and allowed to unload as C3-6 has it: its first open loads monsw
 * first.  Its device reads as empty.  The rows install it on a test box
 * only, never beside the real package.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/conf.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

static int zrtg_open() { return 0; }
static int zrtg_close() { return 0; }
static int zrtg_read() { return 0; }
static int zrtg_write() { return 0; }
static int zrtg_ioctl() { return 0; }

static int
zrtg_load(params)
	char *params;
{
	printf("z3660rtg: the S3-43 stand-in, loaded\n");
	return 0;
}

static int
zrtg_unload()
{
	printf("z3660rtg: the S3-43 stand-in, unloaded\n");
	return 0;
}

struct mod_drv_data z3660rtg_drvdata[] = {
	{ { 0 }, 0, 0, { zrtg_open, zrtg_close, zrtg_read, zrtg_write, zrtg_ioctl }, 49, 1 }
};
MOD_DRV_WRAPPER(z3660rtg, zrtg_load, zrtg_unload, 0, "S3-43 stand-in for z3660rtg");
