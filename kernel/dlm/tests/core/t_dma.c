/*
 * t_dma.c -- the DMA names of core/plat/k46/line.c on the host (contract
 * C4-5 sections 2.3 and 3): dma_alloc over a stand-in heap whose virtual
 * addresses (buffer A) are not its physical ones (buffer B), as on the
 * 68040/68060 kernels: the module gets the physical alias, 16-aligned,
 * the block is purged by physical line at alloc and at free, and memory
 * that is not physically contiguous is refused.  Built with DMA_IDTOP at
 * the top of the host's address space, since host addresses lie above
 * 1 GiB.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <string.h>

char buildid[] = "68060-261101-01";
char *plat_buildid(void);
unsigned long dma_addr(char *, unsigned long);
char *dma_alloc(unsigned long, unsigned long *);
void dma_free(char *, unsigned long);

static char heap[0x30000], phys[0x30000];	/* A, the heap's VAs; B, its pages */
static char *last_p, *freed_p;
static unsigned long last_n, freed_n, alloc_flag;
static unsigned long purged[8][2];
static int npurge, nomem, gap_at;		/* gap_at: a page that is not the next one */

char *
kmem_alloc(unsigned long n, int flag)
{
	alloc_flag = (unsigned long)flag;
	if (nomem)
		return 0;
	last_n = n;
	return last_p = heap + 0x1003;		/* an odd start, as a heap may give */
}

void
kmem_free(char *p, unsigned long n)
{
	freed_p = p, freed_n = n;
}

unsigned long
vtop(char *va, char *proc)
{
	unsigned long o = (unsigned long)(va - heap);

	(void)proc;
	if (gap_at && o >= (unsigned long)gap_at)
		o += 4096;
	return (unsigned long)(phys + o);
}

int
dma_prepare(char *r, unsigned long pa, unsigned long len, int dir)
{
	(void)r;
	if (dir == 1 && npurge < 8)
		purged[npurge][0] = pa, purged[npurge++][1] = len;
	return 0;
}

void
dma_complete(char *r, unsigned long pa, unsigned long len, int dir)
{
	(void)r, (void)pa, (void)len, (void)dir;
}

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
	unsigned long pa = 0, base;
	char *va;

	va = dma_alloc(1300, &pa);
	base = vtop(last_p, 0);
	check(va && ((unsigned long)va & 15) == 0 && pa == (unsigned long)va,
	    "dma_alloc: 16-aligned, its pointer its physical address");
	check(va >= phys && va < phys + sizeof phys && va >= (char *)base + 4 &&
	    va + 1300 <= (char *)base + last_n,
	    "dma_alloc: the module's pointer is the physical alias, inside the block");
	check(alloc_flag == 1 && ((char **)va)[-1] == last_p, "dma_alloc: KM_NOSLEEP, the heap address kept");
	check(npurge == 1 && purged[0][0] == base && purged[0][1] == last_n,
	    "dma_alloc: the block pushed and invalidated by physical line");
	dma_free(va, 1300);
	check(freed_p == last_p && freed_n == last_n && npurge == 2 && purged[1][0] == base,
	    "dma_free: purged again, then the heap block and size given back");
	check(dma_alloc(0, &pa) == 0 && dma_alloc(0x10001, &pa) == 0,
	    "dma_alloc: 0 bytes or more than 64 KiB -> 0");
	check(dma_alloc(0x10000, &pa) != 0, "dma_alloc: 64 KiB exactly, over pages that are contiguous");
	gap_at = 0x3000;
	freed_p = 0;
	check(dma_alloc(0x4000, &pa) == 0 && freed_p == last_p,
	    "dma_alloc: pages not physically contiguous -> 0, the block given back");
	gap_at = 0;
	nomem = 1;
	check(dma_alloc(64, &pa) == 0, "dma_alloc: no memory -> 0");
	check(dma_addr((char *)0, 0x07f01230UL) == 0x07f01230UL, "dma_addr: the segment's own address");
	(void)plat_buildid;
	return fails != 0;
}
