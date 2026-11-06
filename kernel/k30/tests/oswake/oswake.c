/*
 * oswake.c -- is an oversize kmem sleeper woken when the kernel map's room comes back?  A test module, never
 * installed: it loads by path (modadmin -l /tmp/oswake) in a development-load boot (kbootset next devload).
 *
 * It takes the kernel map with KM_NOSLEEP pieces: large ones down to 64 KiB, then 4 KiB ones, each pool of which is
 * 8 pages of the map and wholly this module's, then 8 KiB ones until no run of 5 pages is left.  It then asks one
 * KM_SLEEP request of OSWAKE_REQ bytes (above 4 KiB, so it sleeps on Km_OsizeWanted).  A timeout OSWAKE_SECS seconds
 * later frees the 4 KiB pieces, so the only room that comes back comes through kmem_freepool's pool retirements; a
 * second one, OSWAKE_SECS after that, frees the rest, each a direct kmem_free.  The module prints which of the two the
 * request came back after.  Stock wakes only on the second: kmem_freepool compares clicks with Km_OsizeWanted's bytes.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/param.h"
#include "sys/kmem.h"
#include "sys/errno.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

#ifndef OSWAKE_REQ
#define OSWAKE_REQ	8800		/* UDPMSGSIZE: the NFS client's cku_outbuf */
#endif
#ifndef OSWAKE_SECS
#define OSWAKE_SECS	60
#endif

extern long	lbolt;
extern int	printf(), timeout(), spl7(), splx();
extern void	wakeup();
extern int	sleep();

struct piece {
	struct piece	*next;
	long		size;
};

static long	sizes[] = { 1048576, 262144, 65536, 4096, 8192, 0 };
static struct piece *held;
static long	nheld, bheld;
static long	t_small, t_large;

/* gives back the pieces of at most `limit` bytes */
static void
release(arg)
	caddr_t arg;
{
	long limit = (long)arg, b = 0;
	struct piece *p, *n, *keep = 0;
	int s;

	s = spl7();
	p = held;
	held = 0;
	splx(s);
	for (; p; p = n) {
		n = p->next;
		if (p->size > limit) {
			p->next = keep;
			keep = p;
			continue;
		}
		b += p->size;
		kmem_free((caddr_t)p, p->size);
	}
	s = spl7();
	held = keep;
	if (limit <= 4096)
		t_small = lbolt;
	else {
		t_large = lbolt;
		wakeup((caddr_t)&t_large);
	}
	splx(s);
	printf("oswake: released %d bytes of pieces up to %d at lbolt %d\n", (int)b, (int)limit, (int)lbolt);
}

static int
oswake_load(params)
	char *params;
{
	int secs = OSWAKE_SECS, req = OSWAKE_REQ, i, s;
	long t0, t1;
	struct piece *p;
	caddr_t q;

	nheld = bheld = t_small = t_large = 0;
	for (i = 0; sizes[i]; i++)
		while ((p = (struct piece *)kmem_alloc(sizes[i], KM_NOSLEEP)) != 0) {
			p->next = held;
			p->size = sizes[i];
			held = p;
			nheld++;
			bheld += sizes[i];
		}
	printf("oswake: drained %d pieces, %d bytes at lbolt %d; req %d, small release in %d s, large in %d s\n",
	    (int)nheld, (int)bheld, (int)lbolt, req, secs, 2 * secs);
	(void)timeout(release, (caddr_t)4096, secs * HZ);
	(void)timeout(release, (caddr_t)0x7fffffff, 2 * secs * HZ);
	t0 = lbolt;
	q = kmem_alloc(req, KM_SLEEP);
	t1 = lbolt;
	printf("oswake: %d KM_SLEEP returned %s after %d ticks: %s\n", req, q ? "memory" : "NULL", (int)(t1 - t0),
	    t_large ? "WOKEN ONLY BY THE LARGE FREES" : t_small ? "WOKEN AFTER THE POOL RETIREMENTS" : "at once");
	if (q)
		kmem_free(q, req);
	s = spl7();
	while (t_large == 0)
		(void)sleep((caddr_t)&t_large, PZERO + 1);
	splx(s);
	return ENXIO;		/* one shot: not kept */
}

static int
oswake_unload()
{
	return 0;
}

MOD_MISC_WRAPPER(oswake, oswake_load, oswake_unload, "kmem test: an oversize KM_SLEEP request and what wakes it");
