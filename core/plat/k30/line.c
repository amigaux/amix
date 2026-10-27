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
 * DMA, DDI 1.2 (contract C4-5 section 5): the 030 provider.  On an A4000
 * or A3000 with a Z3660 the kernel runs in the card's DDR, which a Zorro
 * bus master cannot reach.  The kernel takes only the region it is bound
 * in, and boot2 leaves the region below it a 2 KiB page short (10 section
 * 3.2), so motherboard fast RAM below 0x08000000 is free: the pool is its
 * top DMA_POOL bytes, through the identity map that pstart builds over
 * 0-1 GiB, handed out in 16-byte lines.  A segment the board reaches is
 * left where it is; any other is bounced through the pool.  When the
 * kernel itself runs below 0x08000000 everything it allocates is reached:
 * dma_alloc takes the heap through its identity alias and nothing is
 * bounced.  The 68030's data cache is write-through, so only the device's
 * writes need it cleared, at complete.
 */
#ifndef DMA_REACH
#define DMA_REACH	0x08000000UL	/* a Zorro bus master reaches below this */
#define DMA_CHIP	0x00200000UL	/* and above chip memory (host tests move both) */
#endif
#define DMA_POOL	0x20000UL	/* 128 KiB */
#define DMA_MAX		0x10000UL	/* one dma_alloc */
#define DMA_HDR		20
#define DMA_PG		4096UL
#define DMA_NMAP	32		/* the pool's free extents */
#define DMA_NOWN	8		/* records with a bounce at once */
#define DMA_NALLOC	16		/* dma_alloc blocks in heap mode */

/* struct dma_rec, layout version 2 (the 040/060 port's DMA040-SERVICE-RECORD.md) */
#define DR_OFF		0x10
#define DR_STATE	0x14
#define DR_DIR		0x18
#define DR_PA		0x1c
#define DR_LEN		0x20
#define DR_SEQ		0x24
#define DR_PREPTO	0x28
#define DR_PREPFR	0x2c
#define DR_CMPLTO	0x30
#define DR_CMPLFR	0x34
#define DR_PREPOWN	0x38
#define DR_NOPREP	0x3c
#define DR_OVF		0x44
#define DR_OFFN		0x4c
#define RW(r, o)	(*(unsigned int *)((r) + (o)))	/* 32-bit fields */

extern char bootinfo[];
extern char *kmem_alloc(unsigned long, int);
extern void kmem_free(char *, unsigned long);
extern unsigned long vtop(char *, char *);
extern void bcopy(const void *, void *, unsigned long);
extern int printf(const char *, ...);

int		dma_forcebounce;	/* test hook (C4-5 section 5.3): bounce every segment */
int		dma_forcefail;		/* test hook: the next N bounces miss (dma_addr 0) */
unsigned long	dma_pool, dma_poolsz;	/* the pool, or 0 */
int		dma_heap;		/* 1: the kernel runs where the board reaches */
static struct { unsigned long a, n; } map[DMA_NMAP];	/* free extents, by address */
static struct { char *r; unsigned long b; } own[DMA_NOWN];	/* the bounces held */
static struct { unsigned long a, n; } blk[DMA_NALLOC];	/* heap mode's dma_alloc blocks */

#ifndef DMA_HOST
#define SPLHI(s) do { \
	__asm__ __volatile__("movew %%sr,%0" : "=d" (s) : : "memory"); \
	__asm__ __volatile__("movew %0,%%sr" : : "d" ((s) | 0x0700) : "memory"); \
} while (0)
#define SPLX(s)	__asm__ __volatile__("movew %0,%%sr" : : "d" (s) : "memory")
/* the 68030's data cache cleared (CACR CD); a 68020 has none and ignores the bit.
 * movec cacr,d0 / movec d0,cacr as words: this assembler has no movec */
#define DCLEAR() __asm__ __volatile__(".word 0x4e7a,0x0002\n\torl &0x800,%%d0\n\t" \
	".word 0x4e7b,0x0002" : : : "d0", "memory")
#else
#define SPLHI(s)	((s) = 0)
#define SPLX(s)		((void)(s))
extern int dma_host_dclear;
#define DCLEAR()	(dma_host_dclear++)
#endif

static unsigned long
get32(const char *p)
{
	const unsigned char *u = (const unsigned char *)p;

	return (unsigned long)u[0] << 24 | (unsigned long)u[1] << 16 | (unsigned long)u[2] << 8 | u[3];
}

/* inside dma_alloc memory: the pool, or one of heap mode's blocks */
static int
allocated(unsigned long pa, unsigned long n)
{
	int i;

	if (dma_pool)
		return pa >= dma_pool && pa + n <= dma_pool + dma_poolsz && pa + n >= pa;
	for (i = 0; i < DMA_NALLOC; i++)
		if (blk[i].n && pa >= blk[i].a && pa + n <= blk[i].a + blk[i].n && pa + n >= pa)
			return 1;
	return 0;
}

/*
 * The board reaches pa..pa+n.  dma_alloc memory is never bounced, the
 * force-bounce hook's included (C4-5 section 2.2): a bounce of a line the
 * chip wrote would copy stale bytes back over it at complete.
 */
static int
reached(unsigned long pa, unsigned long n)
{
	if (allocated(pa, n))
		return 1;
	return !dma_forcebounce && pa >= DMA_CHIP && pa + n <= DMA_REACH && pa + n >= pa;
}

/* n bytes (a multiple of 16) from the pool's map, or 0 */
static unsigned long
pool_get(unsigned long n)
{
	unsigned long a = 0;
	int i, s;

	SPLHI(s);
	for (i = 0; i < DMA_NMAP && map[i].n; i++)
		if (map[i].n >= n) {
			a = map[i].a;
			map[i].a += n;
			if ((map[i].n -= n) == 0)
				for (; i + 1 < DMA_NMAP; i++)
					map[i] = map[i + 1];
			break;
		}
	SPLX(s);
	return a;
}

/* n bytes at a back into the map, joined with their neighbours */
static void
pool_put(unsigned long a, unsigned long n)
{
	int i, j, s;

	SPLHI(s);
	for (i = 0; i < DMA_NMAP && map[i].n && map[i].a < a; i++)
		;
	if (i > 0 && map[i - 1].a + map[i - 1].n == a) {
		map[i - 1].n += n;
		if (i < DMA_NMAP && map[i].n && a + n == map[i].a) {
			map[i - 1].n += map[i].n;
			for (j = i; j + 1 < DMA_NMAP; j++)
				map[j] = map[j + 1];
			map[DMA_NMAP - 1].n = 0;
		}
	} else if (i < DMA_NMAP && map[i].n && a + n == map[i].a) {
		map[i].a = a;
		map[i].n += n;
	} else if (map[DMA_NMAP - 1].n == 0 && i < DMA_NMAP) {
		for (j = DMA_NMAP - 1; j > i; j--)
			map[j] = map[j - 1];
		map[i].a = a;
		map[i].n = n;
	} else
		printf("dma: the pool's map is full: %d bytes at 0x%x lost\n", (int)n, (unsigned)a);
	SPLX(s);
}

/*
 * At dmainit: the pool from a fast region below 0x08000000 that is not the
 * kernel's own, the top DMA_POOL bytes of the largest one; or the heap, when
 * the kernel itself runs below 0x08000000; or none.
 */
void
plat_line_init(void)
{
	const char *m = bootinfo + 0x440;	/* AXB_MEMORY: AXB_MAXMEM MemHeader copies */
	unsigned long k = (unsigned long)bootinfo, lo, up, best = 0, top = 0;
	int i;

	for (i = 0; i < 16; i++, m += 0x20) {
		if (((const unsigned char *)m)[15] & 0x2)	/* mh_Attributes (14, 16 bits): MEMF_CHIP */
			continue;
		lo = get32(m + 20), up = get32(m + 24);
		if (k >= lo && k < up) {
			dma_heap = up <= DMA_REACH;
			continue;
		}
		if (up <= DMA_REACH && lo >= DMA_CHIP && up > lo && up - lo > best)
			best = up - lo, top = up & ~15UL;
	}
	if (best >= DMA_POOL) {
		dma_pool = top - DMA_POOL, dma_poolsz = DMA_POOL;
		map[0].a = dma_pool, map[0].n = DMA_POOL;
		dma_heap = 0;
	}
	if (dma_pool)
		printf("dma: pool %d KiB at 0x%x\n", (int)(dma_poolsz >> 10), (unsigned)dma_pool);
	else if (!dma_heap)
		printf("dma: no memory a bus master reaches: bus-master DMA is off\n");
}

/* the force-fail hook: a count of bounces to refuse, each one taken off;
 * it clears itself, so it can never be left on (C4-5 section 5.3) */
static int
forcefail(void)
{
	int s, f = 0;

	SPLHI(s);
	if (dma_forcefail > 0)
		dma_forcefail--, f = 1;
	SPLX(s);
	return f;
}

static int
owner(char *r)
{
	int i;

	for (i = 0; i < DMA_NOWN; i++)
		if (own[i].r == r)
			return i;
	return -1;
}

int
dma_prepare(char *r, unsigned long pa, unsigned long len, int dir)
{
	unsigned long b, n = (len + 15) & ~15UL;
	int i, s;

	if (RW(r, DR_OFF)) {
		RW(r, DR_OFFN)++;
		return -1;
	}
	if (pa + len < pa) {
		RW(r, DR_OVF)++;
		return -1;
	}
	if (RW(r, DR_STATE)) {
		RW(r, DR_PREPOWN)++;
		return -1;
	}
	if (!reached(pa, len)) {
		if (forcefail() || n == 0 || (b = pool_get(n)) == 0) {
			RW(r, DR_OFFN)++;	/* a miss: dma_addr gives 0, the driver does not arm */
			return -1;
		}
		SPLHI(s);
		i = owner((char *)0);
		if (i >= 0)
			own[i].r = r, own[i].b = b;
		SPLX(s);
		if (i < 0) {
			pool_put(b, n);
			RW(r, DR_OFFN)++;
			return -1;
		}
		if (dir == 0)		/* TO_DEVICE: the bytes go out from the bounce */
			bcopy((char *)pa, (char *)b, len);
	}
	RW(r, DR_PA) = pa, RW(r, DR_LEN) = len, RW(r, DR_DIR) = (unsigned long)dir;
	RW(r, DR_SEQ)++;
	RW(r, dir ? DR_PREPFR : DR_PREPTO)++;
	RW(r, DR_STATE) = 2;		/* PREPARED */
	return 0;
}

void
dma_complete(char *r, unsigned long pa, unsigned long len, int dir)
{
	int i;

	(void)pa, (void)len;
	if (RW(r, DR_STATE) != 2) {
		RW(r, DR_NOPREP)++;
		return;
	}
	pa = RW(r, DR_PA), len = RW(r, DR_LEN), dir = (int)RW(r, DR_DIR);	/* the owned one */
	if (dir)
		DCLEAR();		/* the device wrote: no stale line may be read */
	if ((i = owner(r)) >= 0) {
		if (dir)
			bcopy((char *)own[i].b, (char *)pa, len);
		pool_put(own[i].b, (len + 15) & ~15UL);
		own[i].r = 0;
	}
	RW(r, dir ? DR_CMPLFR : DR_CMPLTO)++;
	RW(r, DR_STATE) = 0;
}

/* the bounce r holds for pa, or pa when the board reaches it, else 0 (do not arm) */
unsigned long
dma_addr(char *r, unsigned long pa)
{
	int i;

	if (RW(r, DR_STATE) == 2 && RW(r, DR_PA) == pa && (i = owner(r)) >= 0)
		return own[i].b;
	return reached(pa, 1) ? pa : 0;
}

/* len bytes (16-aligned, at most 64 KiB) the board reaches; their address in *pa */
char *
dma_alloc(unsigned long len, unsigned long *pa)
{
	unsigned long n = (len + 15) & ~15UL, a, b, k;
	char *p;
	int i;

	if (len == 0 || len > DMA_MAX)
		return 0;
	if (dma_pool) {
		if ((a = pool_get(n)) == 0)
			return 0;
		*pa = a;
		return (char *)a;
	}
	for (i = 0; i < DMA_NALLOC && blk[i].n; i++)
		;
	if (!dma_heap || i == DMA_NALLOC || (p = kmem_alloc(len + DMA_HDR, 1)) == 0)
		return 0;
	b = vtop(p, 0);
	for (k = DMA_PG - ((unsigned long)p & (DMA_PG - 1)); k < len + DMA_HDR; k += DMA_PG)
		if (vtop(p + k, 0) != b + k)
			b = 0;
	if (b == 0 || b + len + DMA_HDR > DMA_REACH) {
		kmem_free(p, len + DMA_HDR);
		return 0;
	}
	a = (b + 4 + 15) & ~15UL;		/* through the identity map */
	((char **)a)[-1] = p;
	blk[i].a = a, blk[i].n = len;
	*pa = a;
	return (char *)a;
}

void
dma_free(char *va, unsigned long len)
{
	unsigned long a = (unsigned long)va;
	int i;

	if (va == 0)
		return;

	if (dma_pool && a >= dma_pool && a < dma_pool + dma_poolsz)
		pool_put(a, (len + 15) & ~15UL);
	else {
		for (i = 0; i < DMA_NALLOC; i++)
			if (blk[i].a == a)
				blk[i].n = 0;
		kmem_free(((char **)va)[-1], len + DMA_HDR);
	}
}
