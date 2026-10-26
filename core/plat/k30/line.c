/*
 * line.c -- what the 030 line's kernels give the platform hook
 * (core/plat/amiga.c) and the DDI: their build id is kinfo_buildid, which
 * the kernel build stamps into the kinfo driver (amix-kerntools
 * src/kinfo030.c; the 030 kernel has no buildid string); and cputype, which
 * the 68040/68060 kernels define and the 030 kernels do not (DDI v1).
 * Both strong: a kernel that already has a cputype fails to link, which is
 * the moment to drop this one.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
extern char kinfo_buildid[];

long cputype = 30;

char *
plat_buildid(void)
{
	return kinfo_buildid;
}

/*
 * DMA, DDI 1.2 (contract C4-5): the names, and until the 030 provider
 * (S4-62, C4-5 section 5.2) a placeholder that never hands a board
 * memory it may not reach: dma_alloc has no pool and returns 0, so a
 * bus-master driver fails its _load; dma_prepare takes no ownership and
 * counts the call in the record's off_n, as the 040/060 service does
 * with its seam off; dma_addr is the segment's own address.
 */
#define	DR_OFFN		0x4c		/* struct dma_rec, layout version 2 */

int
dma_prepare(char *r, unsigned long pa, unsigned long len, int dir)
{
	(void)pa, (void)len, (void)dir;
	(*(unsigned long *)(r + DR_OFFN))++;
	return -1;
}

void
dma_complete(char *r, unsigned long pa, unsigned long len, int dir)
{
	(void)r, (void)pa, (void)len, (void)dir;
}

unsigned long
dma_addr(char *r, unsigned long pa)
{
	(void)r;
	return pa;
}

char *
dma_alloc(unsigned long len, unsigned long *pa)
{
	(void)len, (void)pa;
	return 0;
}

void
dma_free(char *va, unsigned long len)
{
	(void)va, (void)len;
}
