/*
 * kmhog.c -- kernel memory exhaustion for the low-memory rows: built as
 * two misc modules that are never installed.  They load by path
 * (modadmin -l /tmp/kmhold) in a development-load boot (kbootset next
 * devload), the only boot in which a module outside the manifest loads.
 *
 * Both drain the kernel allocator with KM_NOSLEEP pieces, largest first
 * (1 MiB down to 16 bytes), until even a 16-byte request fails, and give
 * every piece back from a timeout `secs` seconds later (param, default
 * 20), so a box starved by the row recovers by itself.
 *
 * kmhold  keeps the pieces and stays linked: the next allocation anyone
 *         makes finds the allocator empty until the release.  Its first
 *         line says how much it drained, so two loads around an event
 *         measure what the event kept: the release line names the bytes.
 *         modadmin -U kmhold releases early.
 * kmsleep then asks one 4096-byte KM_SLEEP request and says after how
 *         many ticks it returned: at once, or only when the release ran
 *         (it waited for memory).  It returns ENXIO, so it is not kept.
 *
 * A test module: it breaks C3-6's first-use rule on purpose (kmsleep's
 * KM_SLEEP).  tests/bench/README.md, the low-memory rows.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/param.h"
#include "sys/kmem.h"
#include "sys/errno.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern long	lbolt;
extern int	printf(), timeout(), spl7(), splx();
extern void	untimeout();

struct piece {
	struct piece	*next;
	long		size;
};

static long	sizes[] = { 1048576, 262144, 65536, 16384, 4096, 1024, 256, 64, 16, 0 };
static struct piece *held;
static long	nheld, bheld;
static int	toid;		/* the pending release, or 0 */

static int
secs_of(params)
	char *params;
{
	int n = 20;
	char *p;

	for (p = params; p && *p; p++)
		if ((p == params || p[-1] == ' ') && p[0] == 's' && p[1] == 'e' &&
		    p[2] == 'c' && p[3] == 's' && p[4] == '=') {
			for (p += 5, n = 0; *p >= '0' && *p <= '9'; p++)
				n = n * 10 + *p - '0';
			break;
		}
	return n > 0 ? n : 20;
}

static void
drain()
{
	struct piece *p;
	int i;

	nheld = bheld = 0;
	for (i = 0; sizes[i]; i++)
		while ((p = (struct piece *)kmem_alloc(sizes[i], KM_NOSLEEP)) != 0) {
			p->next = held;
			p->size = sizes[i];
			held = p;
			nheld++;
			bheld += sizes[i];
		}
}

/* from the timeout, or from _unload / kmsleep when it has not run */
static void
release(arg)
	caddr_t arg;
{
	struct piece *p, *n;
	long b = 0;
	int s;

	s = spl7();
	p = held;
	held = 0;
	toid = 0;
	splx(s);
	for (; p; p = n) {
		n = p->next;
		b += p->size;
		kmem_free((caddr_t)p, p->size);
	}
	printf("%s: released %d bytes at lbolt %d\n", MODNAME, (int)b, (int)lbolt);
}

static int
kmhog_load(params)
	char *params;
{
	int secs = secs_of(params);
#ifdef KMSLEEP
	long t0, t1;
	caddr_t q;
	int waited;
#endif

	drain();
	printf("%s: drained %d pieces, %d bytes at lbolt %d; release in %d s\n",
	    MODNAME, (int)nheld, (int)bheld, (int)lbolt, secs);
	toid = timeout(release, (caddr_t)0, secs * HZ);
#ifndef KMSLEEP
	return 0;
#else
	t0 = lbolt;
	q = kmem_alloc(4096, KM_SLEEP);
	t1 = lbolt;
	waited = (toid == 0);	/* the release ran while we slept */
	printf("kmsleep: 4096 KM_SLEEP returned %s after %d ticks (HZ %d): %s\n",
	    q ? "memory" : "NULL", (int)(t1 - t0), HZ,
	    waited ? "it WAITED for the release" : "at once, from what was left");
	if (q)
		kmem_free(q, 4096);
	if (toid) {
		untimeout(toid);
		release((caddr_t)0);
	}
	return ENXIO;		/* one shot: not kept */
#endif
}

static int
kmhog_unload()
{
	if (toid) {
		untimeout(toid);
		release((caddr_t)0);
	}
	return 0;
}

#ifdef KMSLEEP
MOD_MISC_WRAPPER(kmsleep, kmhog_load, kmhog_unload, "low-memory row: a 4 KiB KM_SLEEP on an empty allocator");
#else
MOD_MISC_WRAPPER(kmhold, kmhog_load, kmhog_unload, "low-memory row: drain kernel memory and hold it");
#endif
