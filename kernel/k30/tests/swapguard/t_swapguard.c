/*
 * t_swapguard.c -- src/swapguard030.c's swapguard_take on the host, with kmem and spl stubbed: a resized array is
 * allocated beside the larger block or else freed and allocated again inside one spl7, a failed allocation is retried without a KM_SLEEP, and what swapadd gets
 * is zeroed.  Build: tests/swapguard/run.sh [swapguard030.c].
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int level, fails, nosleep_fail, sleeps, delays;
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
#include SWAPGUARD

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
static int swapadd_called;
static int swapadd_fake(char *vp, unsigned lo, unsigned n, char *name)
{
	(void)vp; (void)lo; (void)n; (void)name;
	swapadd_called++;
	return 0;
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
	return fails != 0;
}
