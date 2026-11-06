/*
 * swapguard030.c -- swapadd fails with ENOMEM instead of sleeping forever on its anon array.
 *
 * THE BUG.  swapadd allocates a swap area's anon array, 16 bytes per page of the area, as one block:
 * kmem_zalloc(npages * 16, KM_SLEEP).  A block over 4 KiB comes from sptalloc, out of kvseg's fixed size
 * (sptmap), which kvm_init's page array (60 bytes per page of memory) already fills to a large part at boot.
 * When no free run of kvseg is large enough, kmem_alloc sleeps on Km_OsizeWanted until some large kmem_free,
 * which may never come: `swap -a`, or the rc script that adds the swap slice's tail at boot, hangs.
 *
 * THE FIX.  After the final link tools/swapguard-retarget.py retargets swapadd's callers (swapctl, swapfunc,
 * swapconf) to swapadd_guarded, swapadd's kmem_zalloc of the anon array to swapguard_take, and the
 * initializer of swg_swapadd from swapguard_swapadd to the static swapadd (a call within this file would be a
 * pc-relative branch, with no relocation to retarget; the pointer's initializer always has one).
 * swapadd_guarded works out the array size from (lowblk, nblks) as swapadd does.  If swapadd would answer without a new
 * array -- an area being deleted added back with the same start, size and name, the same area again, or an overlap
 * (EEXIST) -- it calls swapadd with nothing allocated, so those answers are stock's.  Otherwise it allocates the array
 * with KM_NOSLEEP and leaves it for swapguard_take, which hands it over; ENOMEM when the array of this one area would
 * take more than an eighth of memory, when kvseg has no run that large, or when taking it would leave kvseg no free
 * run of 1 MiB (SWG_KEEP): kmem's other large requests sleep without a signal until a run that large is free.
 * When swapadd clamped the area to its device (the first area only) the size differs: swapguard_take allocates the
 * smaller block with KM_NOSLEEP while it still holds the larger; if that fails it frees the larger and allocates again
 * at spl7 (IPL 4, kmem's own level on this kernel), so no interrupt that allocates can take the run between the two.
 * swapadd has no failure path for the array and never sees 0: if the allocation still fails, it is retried once a
 * second, never on Km_OsizeWanted.  That can only be a block small enough for kmem's pools, whose growth needs more
 * than the block just freed: a first area clamped to 512 KiB or less.  A block swapadd did not take (it failed before
 * allocating) is freed on return.  Nothing else in swapadd changes.  swapadd's checks of the area against its device
 * (EINVAL) come after the guard's allocation, so a request it would refuse as EINVAL can be ENOMEM when memory is short.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/errno.h>
#include <sys/kmem.h>

#define	SWG_PAGESHIFT	11			/* swapadd's page: 2 KiB on the 68030 line */
#define	SWG_PAGE	(1 << SWG_PAGESHIFT)
#define	SWG_ANON	16			/* sizeof (struct anon): bytes of array per page */
#define	SWG_TRIES	5			/* tries, a second apart, so a refused add takes about 4 s: pages may come back, a run of kvseg may not */

#define	SWG_KEEP	512			/* clicks of kvseg an area must leave free in one run: 1 MiB, for kmem's other KM_SLEEP users */

/* struct swapinfo as swapadd uses it (vm/swap.h of the stock kernel; the offsets are those its code reads) */
#define	SI_VP(si)	(*(caddr_t *)((si) + 0))	/* the common vnode */
#define	SI_START(si)	(*(u_int *)((si) + 8))		/* first byte of the area */
#define	SI_END(si)	(*(u_int *)((si) + 12))		/* byte past it */
#define	SI_NEXT(si)	(*(caddr_t *)((si) + 32))
#define	SI_FLAGS(si)	(*(u_short *)((si) + 36))	/* 4: being deleted; 2: as swapadd's own test */
#define	SI_NPAGES(si)	(*(u_int *)((si) + 40))
#define	SI_NAME(si)	(*(char **)((si) + 48))

extern int maxmem;			/* pages of memory, set by kvm_init */
extern caddr_t swapinfo;		/* swapadd's list of areas */
extern u_int sptmap[];			/* kvseg's map: a header pair, then (size, addr) pairs in clicks up to a size of 0 */
extern caddr_t common_specvp();
extern int strcmp();
extern int sleep();
extern void wakeup();
extern int spl7();
extern int splx();
extern void delay();
extern void bzero();

long swg_magic = 0x53574721;		/* "SWG!" */
long swg_calls = 0;			/* every swapadd */
long swg_nomem = 0;			/* refused with ENOMEM: too large for memory, or no run of kvseg that large */
long swg_resized = 0;			/* arrays swapadd asked for at another size (the first area clamped) */
long swg_last = 0;			/* the last array size, bytes */
long swg_retries = 0;			/* one-second retries of a resized array: no pages for it yet */
long swg_noarray = 0;			/* adds stock answers without a new array: a re-add, a duplicate or an overlap */
long swg_keep = 0;			/* refused because the array would leave less than SWG_KEEP clicks in one run */

static caddr_t swg_block;		/* the array allocated for the swapadd in progress */
static u_int swg_size;
static int swg_busy;

/* swg_swapadd's initializer is retargeted to the static swapadd; this placeholder never runs */
int
swapguard_swapadd()
{
	return EINVAL;
}
int (*swg_swapadd)() = swapguard_swapadd;

/*
 * Would swapadd answer this without allocating an array?  Its loop over the list, before it allocates, in its order:
 * an area being deleted with the same start, size and name is added back as it is; on the same device, the same
 * start and size with flag 2 set is answered at once; an overlap is EEXIST.  start and npages are swapadd's own
 * (the byte range narrowed to whole pages).
 */
static int
swg_needsnone(vp, start, end, npages, name)
	caddr_t vp;
	u_int start, end, npages;
	char *name;
{
	caddr_t si, cvp = common_specvp(vp);

	for (si = swapinfo; si != 0; si = SI_NEXT(si)) {
		if (SI_FLAGS(si) & 4) {
			if (start == SI_START(si) && npages == SI_NPAGES(si) && strcmp(SI_NAME(si), name) == 0)
				return 1;
			continue;
		}
		if (SI_VP(si) != cvp)
			continue;
		if (start == SI_START(si) && npages == SI_NPAGES(si) && (SI_FLAGS(si) & 2))
			return 1;
		if (start < SI_END(si) && end > SI_START(si))
			return 1;
	}
	return 0;
}

/* the largest free run of kvseg, in clicks */
static u_int
swg_largest()
{
	u_int i, big = 0;

	for (i = 2; sptmap[i] != 0; i += 2)
		if (sptmap[i] > big)
			big = sptmap[i];
	return big;
}

int
swapadd_guarded(vp, lowblk, nblks, name)
	caddr_t vp;
	u_int lowblk, nblks;
	char *name;
{
	u_int start, end, size;
	int error, tries;

	swg_calls++;
	while (swg_busy)
		(void) sleep((caddr_t)&swg_busy, PZERO);
	swg_busy = 1;
	/* swapadd's own rounding: the byte range [lowblk, lowblk + nblks) * 512 narrowed to whole pages */
	start = ((lowblk << 9) + SWG_PAGE - 1) & ~(SWG_PAGE - 1);
	end = ((lowblk + nblks) << 9) & ~(SWG_PAGE - 1);
	size = end > start ? ((end - start) >> SWG_PAGESHIFT) * SWG_ANON : 0;
	if (size != 0 && swg_needsnone(vp, start, end, (end - start) >> SWG_PAGESHIFT, name)) {
		swg_noarray++;
		size = 0;
	}
	if (size != 0) {
		/* the array is memory for good: at most an eighth of what the box has, for each area */
		tries = (size >> SWG_PAGESHIFT) > (u_int)maxmem / 8 ? 0 : SWG_TRIES;
		swg_block = 0;
		/* under paging the pages may need a moment to come free: only time helps, so a few seconds of it */
		while (tries-- > 0 && (swg_block = (caddr_t)kmem_zalloc(size, KM_NOSLEEP)) == 0)
			if (tries > 0)
				delay(HZ);
		if (swg_block != 0 && swg_largest() < SWG_KEEP) {
			kmem_free(swg_block, size);
			swg_block = 0;
			swg_keep++;
		}
		if (swg_block == 0) {
			swg_nomem++;
			swg_busy = 0;
			wakeup((caddr_t)&swg_busy);
			return ENOMEM;
		}
		swg_size = size;
		swg_last = size;
	}
	error = (*swg_swapadd)(vp, lowblk, nblks, name);
	if (swg_block != 0) {
		kmem_free(swg_block, swg_size);
		swg_block = 0;
	}
	swg_busy = 0;
	wakeup((caddr_t)&swg_busy);
	return error;
}

caddr_t
swapguard_take(size, flag)
	u_int size;
	int flag;
{
	caddr_t p;
	int s;

	if (swg_block != 0 && size == swg_size) {
		p = swg_block;
		swg_block = 0;
		return p;
	}
	swg_resized++;
	if ((p = (caddr_t)kmem_alloc(size, KM_NOSLEEP)) == 0) {
		s = spl7();
		if (swg_block != 0) {
			kmem_free(swg_block, swg_size);
			swg_block = 0;
		}
		p = (caddr_t)kmem_alloc(size, KM_NOSLEEP);
		splx(s);
	}
	while (p == 0) {
		swg_retries++;
		delay(HZ);
		p = (caddr_t)kmem_alloc(size, KM_NOSLEEP);
	}
	if (swg_block != 0) {
		kmem_free(swg_block, swg_size);
		swg_block = 0;
	}
	bzero(p, size);
	return p;
}
