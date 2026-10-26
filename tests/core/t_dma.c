/*
 * t_dma.c -- the DMA names of core/plat/k46/line.c on the host (contract
 * C4-5 sections 2.3 and 3): dma_alloc's alignment, size limit and
 * identity check over a stand-in kmem_alloc and vtop, dma_free giving the
 * block back, dma_addr the identity.  Built with DMA_IDTOP at the top of
 * the host's address space, since host addresses lie above 1 GiB.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>

char buildid[] = "68060-261101-01";
char *plat_buildid(void);
unsigned long dma_addr(char *, unsigned long);
char *dma_alloc(unsigned long, unsigned long *);
void dma_free(char *, unsigned long);

static char *last_p;
static unsigned long last_n, freed_n, alloc_flag;
static char *freed_p;
static int shift_at;		/* nonzero: vtop is off by one page from there */
static int nomem;

char *
kmem_alloc(unsigned long n, int flag)
{
	alloc_flag = (unsigned long)flag;
	if (nomem)
		return 0;
	last_n = n;
	/* an odd start, as a heap may give: dma_alloc must align it */
	return last_p = (char *)malloc(n + 7) + 3;
}

void
kmem_free(char *p, unsigned long n)
{
	freed_p = p, freed_n = n;
}

unsigned long
vtop(char *va, char *proc)
{
	(void)proc;
	if (shift_at && va >= last_p + shift_at)
		return (unsigned long)va + 4096;
	return (unsigned long)va;
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
	unsigned long pa = 0;
	char *va;

	va = dma_alloc(1300, &pa);
	check(va && ((unsigned long)va & 15) == 0 && pa == (unsigned long)va,
	    "dma_alloc: 16-aligned, its physical address the identity");
	check(alloc_flag == 1 && va >= last_p + 4 && va + 1300 <= last_p + last_n,
	    "dma_alloc: KM_NOSLEEP, inside the block with room for its pointer");
	dma_free(va, 1300);
	check(freed_p == last_p && freed_n == last_n, "dma_free: the block and size kmem_alloc gave");
	check(dma_alloc(0, &pa) == 0 && dma_alloc(0x10001, &pa) == 0,
	    "dma_alloc: 0 bytes or more than 64 KiB -> 0");
	check(dma_alloc(0x10000, &pa) != 0, "dma_alloc: 64 KiB exactly");
	shift_at = 64;
	freed_p = 0;
	check(dma_alloc(1300, &pa) == 0 && freed_p == last_p,
	    "dma_alloc: memory not mapped one to one -> 0, the block given back");
	shift_at = 0;
	nomem = 1;
	check(dma_alloc(64, &pa) == 0, "dma_alloc: no memory -> 0");
	check(dma_addr((char *)0, 0x07f01230UL) == 0x07f01230UL, "dma_addr: the segment's own address");
	(void)plat_buildid;
	return fails != 0;
}
