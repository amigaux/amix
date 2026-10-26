/*
 * line.c -- what the 68040/68060 line's kernels give the platform hook
 * (core/plat/amiga.c): their build id is the buildid string, which uname -m
 * shows.  cputype they define themselves, and dev_kvmap/dev_kvunmap are the
 * port's own (devkvmap040.o, linked by the kernel build); and DMA.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
extern char buildid[];

char *
plat_buildid(void)
{
	return buildid;
}

/*
 * DMA, DDI 1.2 (contract C4-5): dma_prepare and dma_complete are the
 * port's (dma_cache040.s, linked by the kernel build).  The rest is here.
 * On this line the kernel's memory below 0x40000000 is mapped one to one
 * and reached through DTT0 cache-inhibited, which a Zorro III bus master
 * reaches: dma_alloc takes kernel memory and keeps it only when it lies
 * there, so a heap that does not fails a driver's _load instead of
 * handing a board the wrong memory.
 */
#ifndef DMA_IDTOP
#define DMA_IDTOP	0x40000000UL	/* the identity map's top (host tests move it) */
#endif
#define DMA_MAX		0x10000UL	/* one call */
#define DMA_HDR		20		/* the block's own pointer, then up to 16 to align */

extern char *kmem_alloc(unsigned long, int);
extern void kmem_free(char *, unsigned long);
extern unsigned long vtop(char *, char *);

/* the address the device is armed with: on this line the segment's own */
unsigned long
dma_addr(char *r, unsigned long pa)
{
	(void)r;
	return pa;
}

/* len bytes, 16-aligned, identity-mapped; its physical address in *pa; 0 when none */
char *
dma_alloc(unsigned long len, unsigned long *pa)
{
	char *p, *va;
	unsigned long a;

	if (len == 0 || len > DMA_MAX || (p = kmem_alloc(len + DMA_HDR, 1)) == 0)
		return 0;			/* 1: KM_NOSLEEP, the root pass's rule */
	a = ((unsigned long)p + 4 + 15) & ~15UL;
	va = (char *)a;
	if (a + len > DMA_IDTOP || vtop(va, 0) != a || vtop(va + len - 1, 0) != a + len - 1) {
		kmem_free(p, len + DMA_HDR);
		return 0;
	}
	((char **)va)[-1] = p;
	*pa = a;
	return va;
}

void
dma_free(char *va, unsigned long len)
{
	if (va)
		kmem_free(((char **)va)[-1], len + DMA_HDR);
}
