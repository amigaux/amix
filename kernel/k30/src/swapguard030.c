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
 * swapadd_guarded works out the array size from (lowblk, nblks) as swapadd does, allocates the array with
 * KM_NOSLEEP -- ENOMEM when kvseg has no run that large, or the array would take more than an eighth of memory -- and
 * leaves it for swapguard_take, which hands it over.
 * When swapadd clamped the area to its device (the first area only) the size differs: swapguard_take allocates the
 * smaller block with KM_NOSLEEP while it still holds the larger; if that fails it frees the larger and allocates again
 * at spl7 (IPL 4, kmem's own level on this kernel), so no interrupt that allocates can take the run between the two.
 * swapadd has no failure path for the array and never sees 0: if the allocation still fails, it is retried once a
 * second, never on Km_OsizeWanted.  That can only be a block small enough for kmem's pools, whose growth needs more
 * than the block just freed: a first area clamped to 512 KiB or less.  A block swapadd did not take (it failed before
 * allocating) is freed on return.  Nothing else in swapadd changes.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/errno.h>
#include <sys/kmem.h>

#define	SWG_PAGESHIFT	11			/* swapadd's page: 2 KiB on the 68030 line */
#define	SWG_PAGE	(1 << SWG_PAGESHIFT)
#define	SWG_ANON	16			/* sizeof (struct anon): bytes of array per page */
#define	SWG_TRIES	5			/* tries, a second apart, so a refused add takes about 4 s: pages may come back, a run of kvseg may not */

extern int maxmem;			/* pages of memory, set by kvm_init */
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
	if (size != 0) {
		/* the array is memory for good: at most an eighth of what the box has */
		tries = (size >> SWG_PAGESHIFT) > (u_int)maxmem / 8 ? 0 : SWG_TRIES;
		swg_block = 0;
		/* under paging the pages may need a moment to come free: only time helps, so a few seconds of it */
		while (tries-- > 0 && (swg_block = (caddr_t)kmem_zalloc(size, KM_NOSLEEP)) == 0)
			if (tries > 0)
				delay(HZ);
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
