/*
 * ramdisk.c -- the RAM disk: block major 20, three units, a root-class loadable module
 * (amix-dlm contracts C4-2 section 8 and C4-3 section 4).  ramdisk/README.md has the whole
 * story; this is the short form.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE at the top of amix-modules.
 *
 *   unit 0   the miniroot image the boot loader placed in memory, when there is one
 *            (ramdisk_image() returns 0).  Its memory is the loader's: it lies outside the
 *            kernel's free lists and the module never allocates or frees it.  The image lies
 *            below VSECT1 (C4-3 section 2), where the kernel maps physical memory one to one,
 *            so its kernel address is phystokv() of its physical address: no page table, no
 *            sptalloc, nothing to map or unmap.  Writable; its contents are lost at power-off.
 *   unit 1   a scratch disk of `size1` KiB (default 512), kmem-backed,
 *   unit 2   a scratch disk of `size2` KiB (default 2048): the memory is allocated at the
 *            first open and freed at the last close, in pieces of at most 256 KiB, each a
 *            kmem_zalloc(KM_NOSLEEP) request (C3-6 section 1.1: no larger request), so a
 *            fresh scratch disk reads as zeros.
 *
 * Stock Amix had a RAM disk on the same major (`ram`, three kmem units of 128 KiB, 512 KiB
 * and 2 MiB, each one allocation).  It could not present a loaded image; this module takes
 * its row (the module kernels have the row free, C4-3 section 3) and keeps its minors 1 and 2
 * as scratch disks of the same default sizes.
 *
 * _load runs in the root pass (C4-2 section 2: level 7, the clock stopped): it reads its two
 * parameters, asks ramdisk_image() for the image and works out unit 0's kernel address.  No
 * sleep, no timeout, no memory request.  Nothing here interrupts or writes memory on its own,
 * so there is no _halt, and no deferred call.
 *
 * Every transfer is a copy by the CPU.  The buffer's side is reached as the stock driver
 * reached it: the physical address vtop() gives for each page of the buffer, at phystokv()
 * of it.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/errno.h>
#include <sys/buf.h>
#include <sys/open.h>
#include <sys/cred.h>
#include <sys/kmem.h>
#include <sys/conf.h>
#include <sys/ddi.h>
#include <sys/moddefs.h>
#include <sys/amixddi.h>

/*
 * The kernel maps physical addresses below VSECT1 one to one, so phystokv() is the
 * identity there; <sys/amixddi.h> gives both names on both lines (amix-dlm docs/abi/ddi.md).
 */

#define RD_MAJOR        20
#define RD_NUNIT        3
#define RD_BSHIFT       9                       /* 512-byte blocks */
#define RD_BSIZE        (1 << RD_BSHIFT)
#define RD_PIECE        (256L << 10)            /* the largest memory request, C3-6 1.1 */
#define RD_MAXKB        16384                   /* a scratch disk's largest size, KiB */
#define RD_MAXPIECE     (RD_MAXKB / 256)
#define RD_SIZE1        512                     /* the defaults, KiB, the stock minors' */
#define RD_SIZE2        2048

extern int printf();
extern void iodone();
extern paddr_t vtop();

struct rd_unit {
	unsigned long   ru_size;                /* bytes, a multiple of 512; 0: no such unit */
	caddr_t         ru_base;                /* unit 0: the image's kernel address */
	int             ru_open;                /* one bit per open type (OTYP_*) */
	int             ru_npiece;              /* scratch: the pieces allocated, 0 until open */
	caddr_t         ru_piece[RD_MAXPIECE];
};

static struct rd_unit rd_unit[RD_NUNIT];

/* the size of a scratch unit's piece i */
static long
rd_piecesize(u, i)
struct rd_unit *u;
int i;
{
	long n = (long)u->ru_size - (long)i * RD_PIECE;

	return n < RD_PIECE ? n : RD_PIECE;
}

static void
rd_free(u)
struct rd_unit *u;
{
	while (u->ru_npiece > 0) {
		u->ru_npiece--;
		kmem_free(u->ru_piece[u->ru_npiece], rd_piecesize(u, u->ru_npiece));
		u->ru_piece[u->ru_npiece] = 0;
	}
}

/* a scratch unit's memory, piece by piece; ENOMEM leaves nothing allocated */
static int
rd_alloc(u)
struct rd_unit *u;
{
	int i, n = (int)((u->ru_size + RD_PIECE - 1) / RD_PIECE);
	caddr_t p;

	for (i = 0; i < n; i++) {
		if ((p = (caddr_t)kmem_zalloc(rd_piecesize(u, i), KM_NOSLEEP)) == 0) {
			rd_free(u);
			return ENOMEM;
		}
		u->ru_piece[i] = p;
		u->ru_npiece = i + 1;
	}
	return 0;
}

/*ARGSUSED*/
static int
ramdiskopen(devp, flag, otyp, crp)
dev_t *devp;
int flag, otyp;
struct cred *crp;
{
	unsigned int m = getminor(*devp);
	struct rd_unit *u;
	int e;

	if (m >= RD_NUNIT)
		return ENXIO;
	if (otyp != OTYP_BLK && otyp != OTYP_MNT && otyp != OTYP_SWP)
		return ENODEV;
	u = &rd_unit[m];
	if (u->ru_size == 0)
		return ENXIO;
	if (m != 0 && u->ru_npiece == 0 && (e = rd_alloc(u)) != 0)
		return e;
	u->ru_open |= 1 << otyp;
	return 0;
}

/*ARGSUSED*/
static int
ramdiskclose(dev, flag, otyp, crp)
dev_t dev;
int flag, otyp;
struct cred *crp;
{
	unsigned int m = getminor(dev);
	struct rd_unit *u;

	if (m >= RD_NUNIT)
		return ENXIO;
	u = &rd_unit[m];
	u->ru_open &= ~(1 << otyp);
	if (m != 0 && u->ru_open == 0)
		rd_free(u);
	return 0;
}

/*
 * The unit's kernel address of byte off, and *np cut so that the run does not leave the
 * piece it starts in.
 */
static caddr_t
rd_addr(u, off, np)
struct rd_unit *u;
unsigned long off, *np;
{
	unsigned long left;

	if (u->ru_base)
		return u->ru_base + off;
	left = RD_PIECE - (off & (RD_PIECE - 1));
	if (*np > left)
		*np = left;
	return u->ru_piece[off / RD_PIECE] + (off & (RD_PIECE - 1));
}

/*
 * A transfer: within the unit, it copies what fits and leaves the rest in b_resid; a read
 * that starts at the end transfers nothing, without an error; anything else outside the
 * unit is ENXIO.  The buffer is taken a page at a time (vtop per page), the unit a piece at
 * a time.
 */
static int
ramdiskstrategy(bp)
struct buf *bp;
{
	unsigned int m = getminor(bp->b_edev);
	struct rd_unit *u;
	unsigned long off, n, c;
	caddr_t a, k, b;

	bp->b_resid = bp->b_bcount;
	if (m >= RD_NUNIT || (u = &rd_unit[m])->ru_size == 0 ||
	    (u->ru_base == 0 && u->ru_npiece == 0) || bp->b_blkno < 0 ||
	    (unsigned long)bp->b_blkno > (u->ru_size >> RD_BSHIFT) ||
	    ((unsigned long)bp->b_blkno == (u->ru_size >> RD_BSHIFT) &&
	    !(bp->b_flags & B_READ) && bp->b_bcount != 0)) {
		bp->b_error = ENXIO;
		bp->b_flags |= B_ERROR;
		iodone(bp);
		return 0;
	}
	off = (unsigned long)bp->b_blkno << RD_BSHIFT;
	n = bp->b_bcount;
	if (n > u->ru_size - off)
		n = u->ru_size - off;
	a = (caddr_t)paddr(bp);
	while (n > 0) {
		c = PAGESIZE - ((unsigned long)a & PAGEOFFSET);
		if (c > n)
			c = n;
		k = rd_addr(u, off, &c);
		b = (caddr_t)phystokv(vtop(a, bp->b_proc));
		if (bp->b_flags & B_READ)
			bcopy(k, b, c);
		else
			bcopy(b, k, c);
		a += c;
		off += c;
		n -= c;
		bp->b_resid -= c;
	}
	iodone(bp);
	return 0;
}

static int
ramdiskprint(dev, str)
dev_t dev;
char *str;
{
	printf("ramdisk %d: %s\n", (int)getminor(dev), str);
	return 0;
}

/* the unit's size in 512-byte blocks, -1 for a unit that does not exist */
static int
ramdisksize(dev)
dev_t dev;
{
	unsigned int m = getminor(dev);

	if (m >= RD_NUNIT || rd_unit[m].ru_size == 0)
		return -1;
	return (int)(rd_unit[m].ru_size >> RD_BSHIFT);
}

/*
 * A size parameter (KiB) from the string the core passes to _load: "name=value ..."
 * records, or 0 (C3-6 section 1.1).  C3-1's int form, decimal; absent gives the default,
 * a value that is not a number or lies outside 0..RD_MAXKB is said and gives the default.
 */
static long
rd_kparam(params, name, dflt)
char *params, *name;
long dflt;
{
	char *p, *n;
	long v;
	int nd;

	if ((p = params) == 0)
		return dflt;
	for (;;) {
		while (*p == ' ')
			p++;
		if (*p == 0)
			return dflt;
		for (n = name; *n && *p == *n; n++, p++)
			;
		if (*n == 0 && *p == '=')
			break;
		while (*p && *p != ' ')
			p++;
	}
	for (p++, v = 0, nd = 0; *p >= '0' && *p <= '9'; p++, nd++)
		v = v <= RD_MAXKB ? v * 10 + (*p - '0') : RD_MAXKB + 1;
	if (nd == 0 || (*p != 0 && *p != ' ') || v > RD_MAXKB) {
		printf("ramdisk: %s is not a size of 0 to %d KiB; %d taken\n", name, RD_MAXKB,
		    (int)dflt);
		return dflt;
	}
	return v;
}

/*
 * The root pass (C4-2 section 2).  No sleep, no memory request: the parameters, the image's
 * address, unit 0's kernel address.  Always 0: with no image the module still gives units 1
 * and 2 (an installed disk that composed it for its scratch units, C4-3 section 4).
 */
static int
ramdisk_load(params)
char *params;
{
	unsigned long pa, sz;

	rd_unit[1].ru_size = (unsigned long)rd_kparam(params, "size1", (long)RD_SIZE1) << 10;
	rd_unit[2].ru_size = (unsigned long)rd_kparam(params, "size2", (long)RD_SIZE2) << 10;
	if (ramdisk_image(&pa, &sz) != 0)
		return 0;
	sz &= ~(unsigned long)(RD_BSIZE - 1);
	if (sz == 0 || pa >= (unsigned long)VSECT1 || sz > (unsigned long)VSECT1 - pa) {
		printf("ramdisk: the image at 0x%x, 0x%x bytes, is not below 0x%x; no unit 0\n",
		    (unsigned)pa, (unsigned)sz, (unsigned)VSECT1);
		return 0;
	}
	rd_unit[0].ru_base = (caddr_t)phystokv(pa);
	rd_unit[0].ru_size = sz;
	printf("ramdisk: unit 0 is the image at 0x%x, %d KiB\n", (unsigned)pa, (int)(sz >> 10));
	return 0;
}

/*
 * unload=never: moduload never calls this, but the core does when the load fails after
 * _load returned 0 (C3-6 section 1.1).  The image is not the module's: only the scratch
 * memory goes.
 */
static int
ramdisk_unload()
{
	int i;

	for (i = 0; i < RD_NUNIT; i++)
		if (rd_unit[i].ru_open)
			return EBUSY;
	for (i = 0; i < RD_NUNIT; i++) {
		rd_free(&rd_unit[i]);
		rd_unit[i].ru_base = 0;
		rd_unit[i].ru_size = 0;
	}
	return 0;
}

/* the block row on major 20 (core patch 0031: a pinned module's block row); no character row */
struct mod_drv_data ramdisk_drvdata[] = {
	{ { ramdiskopen, ramdiskclose, ramdiskstrategy, ramdiskprint, ramdisksize, 0, 0, 0 },
	  RD_MAJOR, 1,
	  { 0 }, 0, 0 }
};

/* _halt: none (C4-2 section 5): nothing here interrupts or writes memory on its own. */
MOD_DRV_WRAPPER(ramdisk, ramdisk_load, ramdisk_unload, 0, "RAM disk /dev/dsk/ram[0-2]");
