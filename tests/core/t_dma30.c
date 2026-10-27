/*
 * t_dma30.c -- the 030 DMA provider of core/plat/k30/line.c on the host
 * (contract C4-5 section 5): the pool found in bootinfo's memory list, the
 * bounce of a segment the board cannot reach and of every one under the
 * force-bounce hook, the copies each way, the data cache cleared for the
 * device's writes, a miss that dma_addr answers with 0, and the heap mode
 * of a kernel that runs where the board reaches.
 *
 * "Physical" memory is a 1 MiB mapping at 0x20000000 (built non-PIE, so
 * bootinfo too lies below 4 GiB): chip below 0x20010000, the board's reach
 * up to 0x20080000 (DMA_CHIP, DMA_REACH), "DDR" above it.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#define _DEFAULT_SOURCE
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>

#define RAM	0x20000000UL
#define POOL	0x20000UL

char bootinfo[0x778];
char kinfo_buildid[] = "030-261101-01";
int dma_host_dclear;
extern int dma_forcebounce, dma_forcefail, dma_heap;
extern unsigned long dma_pool, dma_poolsz;
void plat_line_init(void);
int dma_prepare(char *, unsigned long, unsigned long, int);
void dma_complete(char *, unsigned long, unsigned long, int);
unsigned long dma_addr(char *, unsigned long);
char *dma_alloc(unsigned long, unsigned long *);
void dma_free(char *, unsigned long);

void bcopy(const void *s, void *d, unsigned long n) { memmove(d, s, n); }
static unsigned long heap_at = RAM + 0x20003;	/* an odd start */
char *kmem_alloc(unsigned long n, int f) { (void)n, (void)f; return (char *)heap_at; }
static char *freed;
void kmem_free(char *p, unsigned long n) { (void)n; freed = p; }
unsigned long vtop(char *va, char *p) { (void)p; return (unsigned long)va; }

static void
put32(char *p, unsigned long v)
{
	p[0] = (char)(v >> 24), p[1] = (char)(v >> 16), p[2] = (char)(v >> 8), p[3] = (char)v;
}

/* bootinfo memory[] entry i: attributes, lower, upper */
static void
mem(int i, int attr, unsigned long lo, unsigned long up)
{
	char *m = bootinfo + 0x440 + 0x20 * i;

	m[14] = (char)(attr >> 8), m[15] = (char)attr;
	put32(m + 20, lo), put32(m + 24, up);
}

#define RW(r, o)	(*(unsigned int *)((r) + (o)))
static int fails;

static void
check(int ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	fails += !ok;
}

int
main(void)
{
	char r[0x60], *ddr = (char *)(RAM + 0x90000), *near = (char *)(RAM + 0x30000), *v, *st;
	unsigned long pa, b, kb = (unsigned long)bootinfo & ~0xfffUL;

	if (mmap((void *)RAM, 0x100000, PROT_READ | PROT_WRITE,
	    MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) != (void *)RAM) {
		printf("FAIL no mapping at 0x%lx\n", RAM);
		return 1;
	}
	mem(0, 0x0003, RAM, RAM + 0x10000);			/* chip */
	mem(1, 0x0005, RAM + 0x10000, RAM + 0x80000);		/* motherboard fast */
	mem(2, 0x0005, kb, kb + 0x100000);			/* the kernel's own */
	plat_line_init();
	check(dma_pool == RAM + 0x80000 - POOL && dma_poolsz == POOL && !dma_heap,
	    "init: the pool is the top 128 KiB of the reachable region, not the kernel's");

	v = dma_alloc(1300, &pa);
	check(v && pa == (unsigned long)v && pa == dma_pool && !(pa & 15),
	    "dma_alloc: from the pool, 16-aligned, its pointer its address");

	memset(r, 0, sizeof r);
	memcpy(ddr, "to the device", 14);
	check(dma_prepare(r, (unsigned long)ddr, 14, 0) == 0 && RW(r, 0x14) == 2,
	    "prepare TO_DEVICE of an unreachable segment: PREPARED");
	b = dma_addr(r, (unsigned long)ddr);
	check(b >= dma_pool && b < dma_pool + POOL && !(b & 15) && !memcmp((char *)b, "to the device", 14),
	    "dma_addr: the bounce, 16-aligned, holding the bytes");
	dma_complete(r, (unsigned long)ddr, 14, 0);
	check(RW(r, 0x14) == 0 && RW(r, 0x30) == 1, "complete: the segment given up, counted");

	memset(ddr, 0, 32);
	dma_host_dclear = 0;
	check(dma_prepare(r, (unsigned long)ddr, 20, 1) == 0, "prepare FROM_DEVICE of an unreachable segment");
	b = dma_addr(r, (unsigned long)ddr);
	memcpy((char *)b, "from the device!!!!", 20);	/* the board writes the bounce */
	dma_complete(r, (unsigned long)ddr, 20, 1);
	check(dma_host_dclear == 1 && !memcmp(ddr, "from the device!!!!", 20),
	    "complete FROM_DEVICE: the data cache cleared, the bytes copied back");

	check(dma_prepare(r, (unsigned long)near, 512, 1) == 0 && dma_addr(r, (unsigned long)near) ==
	    (unsigned long)near, "a segment the board reaches is not bounced");
	check(dma_prepare(r, (unsigned long)near, 512, 1) != 0 && RW(r, 0x38) == 1,
	    "a prepare while a segment is owned is refused");
	dma_complete(r, (unsigned long)near, 512, 1);

	/* the force-bounce hook leaves dma_alloc memory alone (C4-5 2.2): a
	 * FROM sync over a line the chip wrote must not copy stale bytes back */
	dma_forcebounce = 1;
	st = dma_alloc(64, &pa);
	memcpy(st, "chip status", 12);
	check(st && dma_prepare(r, pa, 16, 1) == 0 && dma_addr(r, pa) == pa,
	    "force-bounce leaves a pool segment reachable: not bounced");
	dma_complete(r, pa, 16, 1);
	check(!memcmp(st, "chip status", 12), "and its complete leaves the chip's bytes as they are");
	dma_free(st, 64);
	check(dma_prepare(r, (unsigned long)near, 64, 0) == 0 &&
	    dma_addr(r, (unsigned long)near) != (unsigned long)near,
	    "the force-bounce hook bounces a reachable segment");
	dma_complete(r, (unsigned long)near, 64, 0);
	dma_forcebounce = 0;

	dma_forcefail = 2;
	check(dma_prepare(r, (unsigned long)near, 64, 0) == 0 &&
	    dma_addr(r, (unsigned long)near) == (unsigned long)near && dma_forcefail == 2,
	    "the force-fail hook leaves a reachable segment alone, and its count with it");
	dma_complete(r, (unsigned long)near, 64, 0);
	check(dma_prepare(r, (unsigned long)ddr, 64, 0) != 0 && dma_addr(r, (unsigned long)ddr) == 0 &&
	    dma_forcefail == 1 && dma_prepare(r, (unsigned long)ddr, 64, 0) != 0 && dma_forcefail == 0 &&
	    RW(r, 0x4c) == 2, "the force-fail hook: N bounces miss (dma_addr 0), one off the count each");
	check(dma_prepare(r, (unsigned long)ddr, 64, 0) == 0 && dma_addr(r, (unsigned long)ddr) != 0,
	    "and at 0 it has cleared itself: the next bounce is taken");
	dma_complete(r, (unsigned long)ddr, 64, 0);
	RW(r, 0x4c) = 0;
	check(dma_prepare(r, (unsigned long)ddr, POOL, 0) != 0 && RW(r, 0x4c) == 1 &&
	    dma_addr(r, (unsigned long)ddr) == 0,
	    "no bounce to be had: a miss, and dma_addr gives 0 (do not arm)");
	RW(r, 0x10) = 1;
	check(dma_prepare(r, (unsigned long)near, 64, 0) != 0 && RW(r, 0x4c) == 2,
	    "the seam off: counted, nothing owned");
	RW(r, 0x10) = 0;
	dma_complete(r, (unsigned long)near, 64, 0);
	check(RW(r, 0x3c) == 1, "a complete with nothing prepared: counted");

	dma_free(v, 1300);
	check(dma_alloc(POOL, &pa) == 0 && dma_alloc(0x10000, &pa) == (char *)dma_pool &&
	    dma_alloc(0x10000, &pa) == (char *)(dma_pool + 0x10000) && dma_alloc(16, &pa) == 0,
	    "the pool whole again after every free: two 64 KiB blocks fill it");

	/* a kernel bound where the board reaches, no other region: the heap */
	memset(bootinfo, 0, sizeof bootinfo);
	mem(0, 0x0003, RAM, RAM + 0x10000);
	dma_pool = dma_poolsz = 0;
	if (kb < RAM) {
		mem(1, 0x0005, kb, kb + 0x100000);	/* bootinfo itself lies below the reach */
		plat_line_init();
		v = dma_alloc(1300, &pa);
		check(dma_heap && !dma_pool && v && pa == (unsigned long)v && !(pa & 15) &&
		    ((char **)v)[-1] == (char *)heap_at, "heap mode: the block through its identity alias");
		dma_free(v, 1300);
		v = dma_alloc(1300, &pa);
		dma_forcebounce = 1;
		check(dma_prepare(r, pa + 16, 16, 1) == 0 && dma_addr(r, pa + 16) == pa + 16,
		    "heap mode: force-bounce leaves a dma_alloc block reachable");
		dma_complete(r, pa + 16, 16, 1);
		dma_forcebounce = 0;
		dma_free(v, 1300);
		check(freed == (char *)heap_at, "heap mode: dma_free gives the heap block back");
	}
	return fails != 0;
}
