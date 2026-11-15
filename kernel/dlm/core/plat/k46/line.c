/*
 * line.c -- what the 68040/68060 line's kernels give the platform hook
 * (core/plat/amiga.c): their build id is the buildid string, which uname -m
 * shows.  cputype they define themselves, and dev_kvmap/dev_kvunmap are the
 * port's own (devkvmap040.o, linked by the kernel build); DMA; and the
 * framebuffer cache class, fb_register.
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
 * The kernel heap's addresses lie in the kernel map above 0x40000000, but
 * its pages are kernel RAM below it, which DTT0 maps one to one and
 * cache-inhibited.  So dma_alloc takes heap memory, checks that its pages
 * are physically contiguous below 0x40000000, and gives the module the
 * physical address as its pointer: the board and the CPU then see the
 * same bytes with no cache between.  The heap mapping's own cache lines
 * are pushed and invalidated by physical line at alloc and at free, so
 * neither the module nor the heap's next user reads a stale line.
 */
#ifndef DMA_IDTOP
#define DMA_IDTOP	0x40000000UL	/* DTT0's top (host tests move it) */
#endif
#define DMA_MAX		0x10000UL	/* one call */
#define DMA_HDR		20		/* the heap address, then up to 16 to align */
#define DMA_PG		4096UL
#define DMA_RECSZ	0x60		/* struct dma_rec, layout version 2 */

extern char *kmem_alloc(unsigned long, int);
extern void kmem_free(char *, unsigned long);
extern unsigned long vtop(char *, char *);
extern int dma_prepare(char *, unsigned long, unsigned long, int);
extern void dma_complete(char *, unsigned long, unsigned long, int);

/* nothing at dmainit on this line: dma_alloc needs no pool */
void
plat_line_init(void)
{
}

/* the address the device is armed with: on this line the segment's own */
unsigned long
dma_addr(char *r, unsigned long pa)
{
	(void)r;
	return pa;
}

/* push and invalidate n bytes at physical pa: the port's service, FROM_DEVICE */
static void
purge(unsigned long pa, unsigned long n)
{
	char r[DMA_RECSZ];
	int i;

	for (i = 0; i < DMA_RECSZ; i++)
		r[i] = 0;
	if (dma_prepare(r, pa, n, 1) == 0)
		dma_complete(r, pa, n, 1);
}

/* the physical address of n bytes at va if contiguous below DMA_IDTOP, else 0 */
static unsigned long
contig(char *va, unsigned long n)
{
	unsigned long pa = vtop(va, 0), k;

	if (pa == 0 || pa + n > DMA_IDTOP || pa + n < pa)
		return 0;
	for (k = DMA_PG - ((unsigned long)va & (DMA_PG - 1)); k < n; k += DMA_PG)
		if (vtop(va + k, 0) != pa + k)
			return 0;
	return vtop(va + n - 1, 0) == pa + n - 1 ? pa : 0;
}

/* len bytes, 16-aligned, through DTT0; their physical address in *pa; 0 when none */
char *
dma_alloc(unsigned long len, unsigned long *pa)
{
	char *p, *va;
	unsigned long n = len + DMA_HDR, base, a;

	if (len == 0 || len > DMA_MAX || (p = kmem_alloc(n, 1)) == 0)
		return 0;			/* 1: KM_NOSLEEP, the root pass's rule */
	if ((base = contig(p, n)) == 0) {
		kmem_free(p, n);
		return 0;
	}
	purge(base, n);
	a = (base + 4 + 15) & ~15UL;		/* the block through DTT0 */
	va = (char *)a;
	((char **)va)[-1] = p;
	*pa = a;
	return va;
}

void
dma_free(char *va, unsigned long len)
{
	unsigned long n = len + DMA_HDR;
	char *p;

	if (va == 0)
		return;
	p = ((char **)va)[-1];
	purge(vtop(p, 0), n);
	kmem_free(p, n);
}

/*
 * The empty inode table (core/plat/amiga.c): n bytes of kernel virtual
 * space, read-only, every page mapped to one zeroed page.  The zeroed page
 * is one fresh frame from sptalloc (base 0), cleared here.  The run is
 * sptalloc's too, mapped at first to the frames from the zeroed page's on;
 * each leaf is then pointed at the zeroed page, its old frame checked
 * first, as devkvmap040.s's cache-mode change does, so no page-table
 * writer the port has not seen is added.  segkmem_setprot then clears the
 * write bit in every leaf and flushes (cpusha dc, pflusha).  Nothing reads
 * the run before that, and the 68040/68060 do not load speculatively, so
 * the frames it pointed at for a moment leave no cache lines.  sptalloc's
 * leaves are cacheable write-through, which a page of zeros keeps.  On a
 * failure both are given back: the run by sptfree flag 0 (the leaves
 * cleared, no page released: its frames are not its own), the page by
 * flag 1.
 */
#define ZW_PG		4096
#define ZW_SHIFT	12
#define ZW_NOSLEEP	1		/* sptalloc's flag bit 0 */
#define ZW_READ		1		/* PROT_READ */

extern char kvseg[];			/* struct seg kvseg */
extern char *sptalloc(int, int, int, int);
extern void sptfree(char *, int, int);
extern unsigned long *vatosde(char *);
extern unsigned long *vatopte(char *, unsigned long *);
extern void segkmem_setprot(char *, char *, unsigned long, unsigned long);
extern int printf(const char *, ...);

char *
plat_line_zwin(unsigned long nbytes)
{
	unsigned long n = (nbytes + ZW_PG - 1) / ZW_PG, zpte, zpfn, i, *p;
	char *zp, *va;

	if (n == 0 || (zp = sptalloc(1, 0, 0, ZW_NOSLEEP)) == 0)
		return 0;
	for (i = 0; i < ZW_PG; i++)
		zp[i] = 0;
	zpte = *vatopte(zp, vatosde(zp));
	zpfn = zpte >> ZW_SHIFT;
	if ((va = sptalloc((int)n, 0, (int)zpfn, ZW_NOSLEEP)) == 0) {
		sptfree(zp, 1, 1);
		return 0;
	}
	for (i = 0; i < n; i++) {
		p = vatopte(va + i * ZW_PG, vatosde(va + i * ZW_PG));
		if ((*p >> ZW_SHIFT) != zpfn + i) {
			printf("dlm: empty inode table: leaf %d maps frame 0x%x, not 0x%x\n",
			    (int)i, (unsigned)(*p >> ZW_SHIFT), (unsigned)(zpfn + i));
			sptfree(va, (int)n, 0);
			sptfree(zp, 1, 1);
			return 0;
		}
		*p = (*p & (ZW_PG - 1)) | (zpte & ~(ZW_PG - 1));
	}
	segkmem_setprot(kvseg, va, n * ZW_PG, ZW_READ);
	return va;
}

/*
 * fb_register(pa, len), DDI k46.1.6 (contract C3-6 section 5): a module's
 * framebuffer window into the cache class a static driver gets from the
 * port's hat_cm_fb_add (hat040.s).  A page with no page structure, which
 * is what a driver's d_mmap hands out, is mapped non-cacheable serialised
 * (0x40); inside a registered window it is mapped non-cacheable, not
 * serialised (0x60), so stores drain through the 68060's store buffer.
 * The port's table has two slots and an installed interval never changes
 * or goes: a user mapping can outlive the open and the module, and a page
 * classed two ways is the alias the port's page-table rules refuse.  So
 * a slot is held for the rest of the boot by the module that took it, by
 * name: after an unload the same module may ask for the same window again
 * (0), anyone else is refused.
 *
 * From the module's _load only (dlm_curname, core 0056), so before any
 * open or mapping of its device, as the port's contract asks.  The window
 * is page-aligned and inside one AutoConfig board's window that is not RAM
 * (plat_board_window, core/plat/amiga.c).  0; EINVAL (outside _load, an
 * empty, unaligned or wrapping range, not inside one device board);
 * EBUSY (it overlaps a window someone else holds, or one the kernel's own
 * drivers installed); ENOSPC (both slots held).  Each refusal has one
 * console line; the driver keeps the serialised class and works on.
 */
#define FB_SLOTS	2		/* hat040.s: hat_cm_fb, two {lo, hi} pairs */
#define FB_NAMELEN	15		/* MODMAXNAMELEN */
#ifndef EINVAL
#define EBUSY		16		/* <sys/errno.h> */
#define EINVAL		22
#define ENOSPC		28
#endif

extern unsigned long hat_cm_fb[2 * FB_SLOTS];	/* the port's table, read here only */
extern int hat_cm_fb_add(unsigned long, unsigned long);
extern char *dlm_curname(void);
extern int plat_board_window(unsigned long, unsigned long);

static struct {
	unsigned long lo, hi;		/* page frames, [lo, hi) */
	char name[FB_NAMELEN + 1];	/* its holder */
} fbheld[FB_SLOTS];

static int
fb_same(const char *a, const char *b)
{
	int i;

	for (i = 0; i < FB_NAMELEN && a[i] == b[i]; i++)
		if (a[i] == 0)
			return 1;
	return i == FB_NAMELEN;
}

/* the holder of the installed window [lo, hi), or 0 for the kernel's own */
static const char *
fb_holder(unsigned long lo, unsigned long hi)
{
	int i;

	for (i = 0; i < FB_SLOTS; i++)
		if (fbheld[i].name[0] && fbheld[i].lo == lo && fbheld[i].hi == hi)
			return fbheld[i].name;
	return 0;
}

int
fb_register(unsigned long pa, unsigned long len)
{
	char *me = dlm_curname();
	unsigned long lo, hi, klo, khi;
	const char *h;
	int i, k, nfree = 0;

	if (me == 0) {
		printf("dlm: fb_register: not from a module's _load\n");
		return EINVAL;
	}
	if (len == 0 || ((pa | len) & (DMA_PG - 1)) || pa + len - 1 < pa ||
	    !plat_board_window(pa, len)) {
		printf("dlm: %s: fb_register 0x%x+0x%x: not page-aligned inside one device board\n",
		    me, (unsigned)pa, (unsigned)len);
		return EINVAL;
	}
	lo = pa >> 12;
	hi = lo + (len >> 12);
	for (i = 0; i < FB_SLOTS; i++) {
		klo = hat_cm_fb[2 * i];
		khi = hat_cm_fb[2 * i + 1];
		if (klo == 0 && khi == 0) {
			nfree++;
			continue;
		}
		if (lo >= khi || klo >= hi)
			continue;
		h = fb_holder(klo, khi);
		if (klo == lo && khi == hi && h && fb_same(h, me))
			return 0;		/* its own, from an earlier load */
		printf("dlm: %s: fb_register 0x%x+0x%x: overlaps the window %s holds\n",
		    me, (unsigned)pa, (unsigned)len, h ? h : "the kernel");
		return EBUSY;
	}
	if (nfree == 0 || hat_cm_fb_add(lo, hi) != 1) {
		printf("dlm: %s: fb_register 0x%x+0x%x: both framebuffer slots are held\n",
		    me, (unsigned)pa, (unsigned)len);
		return ENOSPC;
	}
	for (k = 0; k < FB_SLOTS && fbheld[k].name[0]; k++)
		;
	if (k < FB_SLOTS) {
		fbheld[k].lo = lo;
		fbheld[k].hi = hi;
		for (i = 0; i < FB_NAMELEN && me[i]; i++)
			fbheld[k].name[i] = me[i];
		fbheld[k].name[i] = 0;
	}
	printf("dlm: %s: framebuffer 0x%x+0x%x non-cacheable, not serialised\n",
	    me, (unsigned)pa, (unsigned)len);
	return 0;
}
