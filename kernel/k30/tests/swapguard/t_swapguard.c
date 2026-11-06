/*
 * t_swapguard.c -- src/swapguard030.c's swapguard_take on the host, with kmem and spl stubbed: a resized array is
 * allocated beside the larger block or else freed and allocated again inside one spl7, a failed allocation is retried without a KM_SLEEP, and what swapadd gets
 * is zeroed; swapadd_guarded allocates nothing for an add stock answers without an array (a re-add of an area being
 * deleted, a duplicate, an overlap) and refuses an array that would leave kvseg no free run of SWG_KEEP clicks.
 * Build: tests/swapguard/run.sh [swapguard030.c].
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

static int level, fails, nosleep_fail, sleeps, delays, nsallocs;
static void sptmap_take(unsigned clicks);
static int lvl_free = -1, lvl_alloc = -1;
static char *freed;
static unsigned freed_size;
static char buf[4][8192];
static int nbuf;

static char *k_alloc(unsigned size, int flag)
{
	(void)size;
	if (flag == 0) {
		sleeps++;
		return buf[nbuf++ & 3];
	}
	lvl_alloc = level;
	nsallocs++;
	if (nosleep_fail > 0) {
		nosleep_fail--;
		return 0;
	}
	if (size > 4096)	/* a block over kmem's pools comes out of kvseg's largest run (sptmap[2] in this model) */
		sptmap_take((size + 2047) / 2048);
	memset(buf[nbuf & 3], 0x55, sizeof buf[0]);
	return buf[nbuf++ & 3];
}
#define kmem_alloc	k_alloc
#define kmem_zalloc	k_alloc
static void kmem_free_stub(char *p, unsigned size)
{
	lvl_free = level;
	freed = p;
	freed_size = size;
}
#define kmem_free	kmem_free_stub
#define sleep	k_sleep
#define wakeup	k_wakeup
#define spl7	k_spl7
#define splx	k_splx
#define delay	k_delay
#define bzero	k_bzero

int maxmem = 8000;
char *swapinfo;				/* the list swapadd walks; empty unless a case sets it */
unsigned int sptmap[8] = { 4, 0, 1000, 100, 0, 0, 0, 0 };	/* one free run of 1000 clicks */
#include SWAPGUARD
char *common_specvp(char *vp) { return vp; }
static void sptmap_take(unsigned clicks) { sptmap[2] -= clicks < sptmap[2] ? clicks : sptmap[2]; }

#undef sleep
#undef wakeup
#undef spl7
#undef splx
#undef delay
#undef bzero
int k_sleep(char *c, int p) { (void)c; (void)p; return 0; }
void k_wakeup(char *c) { (void)c; }
int k_spl7(void) { int s = level; level = 7; return s; }
int k_splx(int s) { int o = level; level = s; return o; }
void k_delay(int t) { (void)t; delays++; }
void k_bzero(char *p, unsigned n) { memset(p, 0, n); }

#define CHECK(c, m)	do { int c_ = (c); printf("%s %s\n", c_ ? "PASS" : "FAIL", m); fails += !c_; } while (0)

/* failures: how many NOSLEEP requests fail, the first being the one made while the larger block is held */
static void resized(int failures, const char *what)
{
	char *got, msg[100];
	int retries = failures > 1 ? failures - 1 : 0;

	nosleep_fail = failures;
	sleeps = delays = 0;
	lvl_free = lvl_alloc = -1;
	swg_block = buf[3];
	swg_size = 8000;
	got = swapguard_take(4000, 0);
	snprintf(msg, sizeof msg, "%s: no KM_SLEEP request", what);
	CHECK(sleeps == 0, msg);
	snprintf(msg, sizeof msg, "%s: the old block freed, %s", what, failures ? "at spl7" : "with no spl");
	CHECK(lvl_free == (failures ? 7 : 0) && freed == buf[3] && freed_size == 8000, msg);
	snprintf(msg, sizeof msg, "%s: spl back at 0", what);
	CHECK(level == 0, msg);
	snprintf(msg, sizeof msg, "%s: the array is non-null and zeroed", what);
	CHECK(got != 0 && got[0] == 0 && got[3999] == 0, msg);
	snprintf(msg, sizeof msg, "%s: %d one-second retries", what, retries);
	CHECK(delays == retries, msg);
}

/* a stand-in for swapadd: what the guard calls through swg_swapadd */
static int swapadd_called, swapadd_ret;
static int swapadd_fake(char *vp, unsigned lo, unsigned n, char *name)
{
	(void)vp; (void)lo; (void)n; (void)name;
	swapadd_called++;
	return swapadd_ret;
}

/* swapinfo entries laid out as the 68030 kernel's: 32-bit pointers at swapadd's offsets, so the list lives below 4 GiB */
static char *low;			/* MAP_32BIT memory: entries at low + 64 * k, names at low + 1024 */
static char *si_at(int k, char *vp, unsigned start, unsigned end, unsigned flags, unsigned npages, const char *name, char *next)
{
	char *e = low + 64 * k, *nm = low + 1024 + 32 * k;

	memset(e, 0, 64);
	strcpy(nm, name);
	*(unsigned *)(e + 0) = (unsigned)(unsigned long)vp;
	*(unsigned *)(e + 8) = start;
	*(unsigned *)(e + 12) = end;
	*(unsigned *)(e + 32) = (unsigned)(unsigned long)next;
	*(unsigned short *)(e + 36) = flags;
	*(unsigned *)(e + 40) = npages;
	*(unsigned *)(e + 48) = (unsigned)(unsigned long)nm;
	return e;
}

/* the area asked for in every list case: device 0x1000, blocks 0..256 (64 pages, bytes 0..0x20000), name "dev" */
#define REQ_VP	((char *)0x1000)
#define REQ_END	(64 * 2048)

/* an add against the list: want_array says whether the guard must ask for an array (memory short, so it ends ENOMEM)
 * or leave the answer to swapadd (whose answer here is ret) */
static void walk(const char *what, char *list, int want_array, int ret)
{
	char msg[160];
	int before = swapadd_called, r;

	swapinfo = list;
	nosleep_fail = 100;
	nsallocs = 0;
	swapadd_ret = ret;
	r = swapadd_guarded(REQ_VP, 0, 64 * 4, "dev");
	if (want_array)
		snprintf(msg, sizeof msg, "%s: an array asked for (ENOMEM, memory short)", what);
	else
		snprintf(msg, sizeof msg, "%s: swapadd's own answer (%d), no array asked for", what, ret);
	CHECK(want_array ? r == ENOMEM && nsallocs > 0 && swapadd_called == before
	    : r == ret && nsallocs == 0 && swapadd_called == before + 1, msg);
	nosleep_fail = 0;
	swapadd_ret = 0;
	swapinfo = 0;
}

int main(void)
{
	char *got;

	low = mmap((void *)0, 4096, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_32BIT, -1, 0);
	if (low == MAP_FAILED || (unsigned long)low + 4096 > 0xffffffffUL) {
		printf("FAIL no memory below 4 GiB for the list\n");
		return 1;
	}
	swg_swapadd = swapadd_fake;
	nosleep_fail = 0;

	/* the eighth applies once an area exists (maxmem 8000: 1000 array pages pass, 1001 fail); the first area is exempt */
	swapinfo = si_at(9, (char *)0x9000, 0, 2048, 0, 1, "other", 0);
	sptmap[2] = 100000;
	CHECK(swapadd_guarded((char *)0, 0, 1000 * 128 * 4, "x") == 0 && swapadd_called == 1, "an array of an eighth of memory is allowed");
	CHECK(swapadd_guarded((char *)0, 0, 1001 * 128 * 4, "x") == ENOMEM && swapadd_called == 1 && swg_nomem == 1,
	    "an array over an eighth of memory is ENOMEM before swapadd runs");
	swapinfo = 0;
	sptmap[2] = 100000;
	CHECK(swapadd_guarded((char *)0, 0, 1001 * 128 * 4, "x") == 0 && swapadd_called == 2, "the first area is exempt from the eighth");
	sptmap[2] = 1000;

	swg_block = buf[2];
	swg_size = 4000;
	got = swapguard_take(4000, 0);
	CHECK(got == buf[2] && swg_block == 0 && sleeps == 0, "same size: the block is handed over");
	resized(0, "resized, room for both");
	resized(1, "resized, no room beside the larger block");
	CHECK(lvl_alloc == 7, "the second allocation at spl7, in the same spl as the free");
	resized(4, "resized, no memory for four tries");

	/* the list walk: the first entry not the one, a match further down, a deleting entry kept out of the overlap test */
	{
		char *other = si_at(1, (char *)0x3000, 0, REQ_END, 0, 64, "elsewhere", 0);
		char *dele, *dup, *ovl, *far;

		dele = si_at(2, (char *)0x7000, 0, REQ_END, 4, 64, "dev", 0);
		walk("re-add of an area being deleted, second in the list", si_at(3, (char *)0x3000, 0, REQ_END, 0, 64, "elsewhere", dele), 0, 0);
		dup = si_at(4, REQ_VP, 0, REQ_END, 2, 64, "dev", 0);
		walk("the same area with flag 2, second in the list", si_at(5, (char *)0x3000, 0, REQ_END, 0, 64, "elsewhere", dup), 0, 0);
		ovl = si_at(6, REQ_VP, 32 * 2048, 200 * 2048, 0, 168, "dev", 0);
		walk("an overlap on the same device, third in the list", si_at(7, (char *)0x3000, 0, REQ_END, 0, 64, "a", si_at(8, (char *)0x4000, 0, REQ_END, 0, 64, "b", ovl)), 0, 17);
		/* a deleting entry on the same device that overlaps but is not the one: no overlap test for it, an array */
		far = si_at(10, REQ_VP, 300 * 2048, 400 * 2048, 0, 100, "dev", 0);
		walk("an overlapping area being deleted under another name, then a far area: an array", si_at(11, REQ_VP, 0, REQ_END, 4, 64, "old", far), 1, 0);
		walk("one area on another device: an array", other, 1, 0);
		walk("a deleting area of the same name but another size: an array", si_at(12, REQ_VP, 0, 2 * REQ_END, 4, 128, "dev", 0), 1, 0);
	}

	/* the reserve: an array out of kvseg that leaves its largest run under 512 clicks is ENOMEM, the block freed */
	swapinfo = si_at(9, (char *)0x9000, 0, 2048, 0, 1, "other", 0);
	sptmap[2] = 1200;
	CHECK(swapadd_guarded((char *)0, 0, 600 * 128 * 4 / 16 * 16, "y") == 0, "an array of 600 clicks from a run of 1200 is allowed");
	sptmap[2] = 1000;
	freed = 0;
	{ long k0 = swg_keep;

	CHECK(swapadd_guarded((char *)0, 0, 600 * 128 * 4, "y") == ENOMEM && freed != 0 && swg_keep == k0 + 1,
	    "an array of 600 clicks from a run of 1000 leaves 400: ENOMEM, the block freed");
	}
	sptmap[2] = 400;
	CHECK(swapadd_guarded((char *)0, 0, 64 * 4, "y") == 0, "a pool-sized array with the run already at 400: allowed, kvseg untouched");
	swapinfo = 0;
	sptmap[2] = 1000;
	CHECK(swapadd_guarded((char *)0, 0, 600 * 128 * 4, "y") == 0, "the first area is exempt from the reserve");
	sptmap[2] = 1000;

	/* no run for the array: tried SWG_TRIES (5) times, a second apart, then ENOMEM; a run free on the third try is taken */
	nosleep_fail = 5;
	delays = 0;
	CHECK(swapadd_guarded((char *)0, 0, 64 * 4, "z") == ENOMEM && delays == 4, "no run for five tries: ENOMEM after 4 one-second waits");
	nosleep_fail = 2;
	delays = 0;
	CHECK(swapadd_guarded((char *)0, 0, 64 * 4, "z") == 0 && delays == 2, "a run free on the third try: taken after 2 waits");
	nosleep_fail = 0;
	return fails != 0;
}
