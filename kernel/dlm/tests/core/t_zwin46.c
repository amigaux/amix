/*
 * t_zwin46.c -- the empty inode table of core/plat/k46/line.c on the host:
 * plat_line_zwin() takes one fresh frame from sptalloc (base 0) and clears
 * it, takes the run from sptalloc mapped to the frames from that one on,
 * checks each leaf's frame and points it at the zeroed page, keeping its
 * low bits, then write-protects the run with segkmem_setprot.  The stand-ins
 * keep 4-byte leaves as the port's sptalloc writes them (frame << 12, the
 * resident bits); segkmem_setprot sets the 68040's W bit (0x04) for
 * PROT_READ.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <string.h>

#define PG	4096UL
#define W	0x04UL
#define ZPFN	0x3f2UL			/* the zeroed page's frame */
#define RUN	0x40180000UL		/* the run's address (never dereferenced) */
#define NLEAF	64

char kvseg[16];
char buildid[] = " 68060-261101-01";
static char zpage[PG] __attribute__((aligned(4096)));
static unsigned long zleaf, leaf[NLEAF], sde;
static int skew = -1, runfail, sleepy, badpte, nfree, setprot_calls;
static struct { char *va; int n, flag; } freed[4];
static struct { char *seg, *va; unsigned long len, prot; } sp;

/* t_dma.c's own stand-ins are not needed here: the DMA half of line.c only links */
char *kmem_alloc(unsigned long n, int f) { (void)n, (void)f; return 0; }
void kmem_free(char *p, unsigned long n) { (void)p, (void)n; }
unsigned long vtop(char *va, char *p) { (void)va, (void)p; return 0; }
int dma_prepare(char *r, unsigned long pa, unsigned long l, int d) { (void)r, (void)pa, (void)l, (void)d; return 0; }
void dma_complete(char *r, unsigned long pa, unsigned long l, int d) { (void)r, (void)pa, (void)l, (void)d; }

char *
sptalloc(int n, int mode, int base, int flag)
{
	int i;

	(void)mode;
	if (!(flag & 1))
		sleepy++;
	if (base == 0) {
		memset(zpage, 0xa5, PG);	/* a fresh frame is not zero */
		zleaf = (ZPFN << 12) | 0x19;	/* resident, used, modified */
		return zpage;
	}
	if (runfail || n > NLEAF)
		return 0;
	for (i = 0; i < n; i++)
		leaf[i] = ((unsigned long)(base + i + (i == skew)) << 12) | 0x01;
	return (char *)RUN;
}

void
sptfree(char *va, int n, int flag)
{
	if (nfree < 4) {
		freed[nfree].va = va, freed[nfree].n = n, freed[nfree].flag = flag;
		nfree++;
	}
}

unsigned long *vatosde(char *va) { (void)va; return &sde; }

unsigned long *
vatopte(char *va, unsigned long *sdep)
{
	unsigned long a = (unsigned long)va;

	if (sdep != &sde)
		badpte++;
	if (va == zpage)
		return &zleaf;
	if (a >= RUN && a < RUN + NLEAF * PG && !(a & (PG - 1)))
		return &leaf[(a - RUN) / PG];
	badpte++;
	return &sde;
}

void
segkmem_setprot(char *seg, char *va, unsigned long len, unsigned long prot)
{
	unsigned long i;

	setprot_calls++;
	sp.seg = seg, sp.va = va, sp.len = len, sp.prot = prot;
	for (i = 0; i < len / PG && i < NLEAF; i++)
		leaf[i] = prot == 1 ? leaf[i] | W : leaf[i] & ~W;
}

char *plat_line_zwin(unsigned long);

static int fails;

static void
check(int ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	fails += !ok;
}

static void
reset(void)
{
	memset(leaf, 0, sizeof leaf);
	memset(freed, 0, sizeof freed);
	nfree = setprot_calls = sleepy = badpte = 0;
}

int
main(void)
{
	unsigned long n = (600UL * 200 + PG - 1) / PG, i;
	int same = 1, ro = 1, low = 1, zero = 1;
	char *va;

	reset();
	va = plat_line_zwin(600UL * 200);
	check(va == (char *)RUN && n == 30, "zwin46: 30 pages for ninode 600, at sptalloc's run");
	for (i = 0; i < n; i++) {
		same &= leaf[i] >> 12 == ZPFN;
		ro &= (leaf[i] & W) != 0;
		low &= (leaf[i] & 0x1fb) == 0x01;	/* sptalloc's bits kept, W the only one added */
	}
	check(same && leaf[n] == 0, "zwin46: every leaf maps the zeroed page's frame, nothing past the run");
	check(low, "zwin46: each leaf keeps sptalloc's low bits");
	check(ro && setprot_calls == 1 && sp.seg == kvseg && sp.va == va && sp.len == n * PG && sp.prot == 1,
	    "zwin46: segkmem_setprot(&kvseg, run, 30 pages, PROT_READ): every leaf write-protected");
	for (i = 0; i < PG; i++)
		zero &= zpage[i] == 0;
	check(zero, "zwin46: the fresh frame is cleared before it is mapped");
	check(sleepy == 0 && badpte == 0 && nfree == 0, "zwin46: both sptallocs without sleep, page tables found, nothing freed");

	reset();
	skew = 3;
	check(plat_line_zwin(600UL * 200) == 0, "zwin46: a leaf on a frame other than expected: no window");
	check(nfree == 2 && freed[0].va == (char *)RUN && freed[0].n == 30 && freed[0].flag == 0 &&
	    freed[1].va == zpage && freed[1].n == 1 && freed[1].flag == 1 && setprot_calls == 0,
	    "zwin46: then the run is freed with flag 0 (leaves cleared, no frame released) and the page with flag 1");
	skew = -1;

	reset();
	runfail = 1;
	check(plat_line_zwin(600UL * 200) == 0 && nfree == 1 && freed[0].va == zpage && freed[0].flag == 1,
	    "zwin46: no run to be had: no window, the page given back");
	runfail = 0;
	check(plat_line_zwin(0) == 0, "zwin46: no inodes, no window");
	printf("t_zwin46: %d failed\n", fails);
	return fails != 0;
}
