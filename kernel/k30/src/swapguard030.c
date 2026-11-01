/*
 * swapguard030.c -- swapadd fails with ENOMEM instead of sleeping forever on its anon array.
 *
 * THE BUG.  swapadd allocates a swap area's anon array, 16 bytes per page of the area, as one block:
 * kmem_zalloc(npages * 16, KM_SLEEP).  A block over 4 KiB comes from sptalloc, out of kvseg's fixed 4 MiB
 * (sptmap), which kvm_init's page array (60 bytes per page of memory) already fills to a large part at boot.
 * When no free run of kvseg is large enough, kmem_alloc sleeps on Km_OsizeWanted until some large kmem_free,
 * which may never come: `swap -a`, or the rc script that adds the swap slice's tail at boot, hangs.  Measured on
 * the 68030 module kernel in emulation: about 50 MiB can be added on a 64 MB machine, about 248 MiB on 16 MB;
 * 64 MiB and 252 MiB slept on Km_OsizeWanted.
 *
 * THE FIX.  After the final link tools/swapguard-retarget.py retargets swapadd's callers (swapctl, swapfunc,
 * swapconf) to swapadd_guarded, swapadd's kmem_zalloc of the anon array to swapguard_take, and the
 * initializer of swg_swapadd from swapguard_swapadd to the static swapadd (a call within this file would be a
 * pc-relative branch, with no relocation to retarget; the pointer's initializer always has one).
 * swapadd_guarded works out the array size from (lowblk, nblks) as swapadd does, allocates the array with
 * KM_NOSLEEP -- ENOMEM when kvseg has no run that large -- and leaves it for swapguard_take, which hands it over.
 * When swapadd clamped the area to its device (the first area only) the size differs: swapguard_take frees the
 * block and allocates the smaller one with KM_NOSLEEP, which fits in the run just freed.  A block swapadd did not
 * take (it failed before allocating) is freed on return.  Nothing else in swapadd changes.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/errno.h>
#include <sys/kmem.h>

#define	SWG_PAGESHIFT	11			/* swapadd's page: 2 KiB on the 68030 line */
#define	SWG_PAGE	(1 << SWG_PAGESHIFT)
#define	SWG_ANON	16			/* sizeof (struct anon): bytes of array per page */

extern int sleep();
extern void wakeup();

long swg_magic = 0x53574721;		/* "SWG!" */
long swg_calls = 0;			/* every swapadd */
long swg_nomem = 0;			/* refused with ENOMEM: no run of kvseg that large */
long swg_resized = 0;			/* arrays swapadd asked for at another size (the first area clamped) */
long swg_last = 0;			/* the last array size, bytes */

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
	int error;

	swg_calls++;
	while (swg_busy)
		(void) sleep((caddr_t)&swg_busy, PZERO + 1);
	swg_busy = 1;
	/* swapadd's own rounding: the byte range [lowblk, lowblk + nblks) * 512 narrowed to whole pages */
	start = ((lowblk << 9) + SWG_PAGE - 1) & ~(SWG_PAGE - 1);
	end = ((lowblk + nblks) << 9) & ~(SWG_PAGE - 1);
	size = end > start ? ((end - start) >> SWG_PAGESHIFT) * SWG_ANON : 0;
	if (size != 0) {
		swg_block = (caddr_t)kmem_zalloc(size, KM_NOSLEEP);
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

	if (swg_block != 0 && size == swg_size) {
		p = swg_block;
		swg_block = 0;
		return p;
	}
	swg_resized++;
	if (swg_block != 0) {
		kmem_free(swg_block, swg_size);
		swg_block = 0;
	}
	if ((p = (caddr_t)kmem_zalloc(size, KM_NOSLEEP)) != 0)
		return p;
	return (caddr_t)kmem_zalloc(size, flag);	/* only when the run just freed was taken meanwhile */
}
