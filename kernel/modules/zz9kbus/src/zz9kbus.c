/*
 * zz9kbus.c -- the registry between ZZ9000-family board drivers and zz9ksvc
 * (include/zz9kbus.h has the interface).  A misc module of a few hundred bytes:
 * board drivers and zz9ksvc name it in depend=, so the core loads it before them.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see kernel/modules/LICENSE in the amix repository.
 *
 * Everything runs in process context (a board driver's _load and _unload, zz9ksvc's
 * _load, open and _unload), never at interrupt level, so the table needs no spl.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/errno.h>
#include <sys/moddefs.h>
#include <zz9kbus.h>

static struct zz9kbus_board *zz9kbus_tab[ZZ9KBUS_NUNIT];

int
zz9kbus_register(bp)
struct zz9kbus_board *bp;
{
	int u;

	if (bp == 0 || bp->zb_version != ZZ9KBUS_VERSION || bp->zb_bread == 0 ||
	    bp->zb_doorbell == 0 || bp->zb_heapphys == 0 || bp->zb_bsize <= 0)
		return EINVAL;
	for (u = 0; u < ZZ9KBUS_NUNIT; u++)
		if (zz9kbus_tab[u] == bp)
			return EBUSY;
	for (u = 0; u < ZZ9KBUS_NUNIT; u++)
		if (zz9kbus_tab[u] == 0) {
			bp->zb_unit = u;
			bp->zb_hold = 0;
			zz9kbus_tab[u] = bp;
			return 0;
		}
	return ENOSPC;
}

int
zz9kbus_unregister(bp)
struct zz9kbus_board *bp;
{
	int u;

	for (u = 0; u < ZZ9KBUS_NUNIT; u++)
		if (zz9kbus_tab[u] == bp && bp != 0) {
			if (bp->zb_hold > 0)
				return EBUSY;
			zz9kbus_tab[u] = 0;
			bp->zb_unit = -1;
			return 0;
		}
	return EINVAL;
}

struct zz9kbus_board *
zz9kbus_get(unit)
int unit;
{
	struct zz9kbus_board *bp;

	if (unit < 0 || unit >= ZZ9KBUS_NUNIT || (bp = zz9kbus_tab[unit]) == 0)
		return 0;
	bp->zb_hold++;
	return bp;
}

void
zz9kbus_put(bp)
struct zz9kbus_board *bp;
{
	if (bp != 0 && bp->zb_hold > 0)
		bp->zb_hold--;
}

static int
zz9kbus_load(params)
char *params;
{
	return 0;
}

/* unload=never: board drivers keep pointers into the table's boards */
static int
zz9kbus_unload()
{
	int u;

	for (u = 0; u < ZZ9KBUS_NUNIT; u++)
		if (zz9kbus_tab[u] != 0)
			return EBUSY;
	return 0;
}

MOD_MISC_WRAPPER(zz9kbus, zz9kbus_load, zz9kbus_unload, "ZZ9000-family board registry");
