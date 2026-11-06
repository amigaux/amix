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

static int level, fails, nosleep_fail, sleeps, delays, nsallocs;
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

/* a swapinfo entry laid out at the offsets swapadd reads */
static union { char c[64]; long align; } si;
static void si_set(char *vp, unsigned start, unsigned end, unsigned flags, unsigned npages, char *name)
{
	memset(si.c, 0, sizeof si.c);
	*(char **)(si.c + 0) = vp;
	*(unsigned *)(si.c + 8) = start;
	*(unsigned *)(si.c + 12) = end;
	*(unsigned short *)(si.c + 36) = flags;
	*(unsigned *)(si.c + 40) = npages;
	*(char **)(si.c + 48) = name;
	swapinfo = si.c;
}

/* an add that stock answers from its list: no array is asked for even when memory is short, and stock's answer stands */
static void noarray(const char *what, char *vp, unsigned flags, unsigned start, unsigned end, int ret)
{
	char msg[120];
	int before = swapadd_called, r;

	si_set((char *)0x1000, start, end, flags, (end - start) / 2048, "dev");
	nosleep_fail = 100;
	nsallocs = 0;
	swapadd_ret = ret;
	r = swapadd_guarded(vp, 0, 64 * 4, "dev");
	snprintf(msg, sizeof msg, "%s: swapadd's own answer (%d), no array asked for", what, ret);
	CHECK(r == ret && swapadd_called == before + 1 && nsallocs == 0, msg);
	nosleep_fail = 0;
	swapadd_ret = 0;
	swapinfo = 0;
}

int main(void)
{
	char *got;

	/* maxmem 8000 pages: an array of 1000 pages, each describing 128 pages of swap (4 blocks a page), passes; 1001 fails */
	swg_swapadd = swapadd_fake;
	nosleep_fail = 0;
	CHECK(swapadd_guarded((char *)0, 0, 1000 * 128 * 4, "x") == 0 && swapadd_called == 1, "an array of an eighth of memory is allowed");
	CHECK(swapadd_guarded((char *)0, 0, 1001 * 128 * 4, "x") == ENOMEM && swapadd_called == 1 && swg_nomem == 1,
	    "an array over an eighth of memory is ENOMEM before swapadd runs");

	swg_block = buf[2];
	swg_size = 4000;
	got = swapguard_take(4000, 0);
	CHECK(got == buf[2] && swg_block == 0 && sleeps == 0, "same size: the block is handed over");
	resized(0, "resized, room for both");
	resized(1, "resized, no room beside the larger block");
	CHECK(lvl_alloc == 7, "the second allocation at spl7, in the same spl as the free");
	resized(4, "resized, no memory for four tries");

	/* the area being deleted, the same start (0), size (64 pages) and name: swapadd adds it back with no new array */
	noarray("re-add of an area being deleted", (char *)0x2000, 4, 0, 64 * 2048, 0);
	/* the same device, an overlapping area: stock's EEXIST, not ENOMEM */
	noarray("an overlap on the same device", (char *)0x1000, 0, 32 * 2048, 200 * 2048, 17);
	/* the same area again with flag 2: stock's answer at once */
	noarray("the same area with flag 2", (char *)0x1000, 2, 0, 64 * 2048, 0);

	/* kvseg's largest free run after the array: 600 clicks passes, 400 is under SWG_KEEP (512) and is ENOMEM, freed */
	sptmap[2] = 600;
	freed = 0;
	CHECK(swapadd_guarded((char *)0, 0, 64 * 4, "y") == 0, "an array that leaves a run of 600 clicks is allowed");
	sptmap[2] = 400;
	freed = 0;
	CHECK(swapadd_guarded((char *)0, 0, 64 * 4, "y") == ENOMEM && freed != 0, "an array that leaves a run of 400 clicks is ENOMEM, the block freed");
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
