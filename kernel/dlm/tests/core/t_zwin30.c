/*
 * t_zwin30.c -- the empty inode table of core/plat/k30/line.c on the host:
 * plat_line_zwin() takes its run from sptmap (rmalloc) and maps each page
 * by its own segkmem_mapin call, PROT_READ, to one zeroed 2 KiB page.
 * The stand-ins keep the page-table entries as the stock segkmem_mapin
 * writes them: the physical address, PG_W (the 68030's WP bit) for
 * PROT_READ, PG_V; and a call of several pages steps the frame, which is
 * why the code must not make one.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <string.h>

#define PG	2048UL
#define PG_V	0x01UL
#define PG_W	0x04UL		/* fault on write */
#define NPTE	256

char bootinfo[0x778];
char kinfo_buildid[] = "030-261101-01";
char sptmap[16], kvseg[16];
int dma_host_dclear;
static unsigned long pte[NPTE];		/* the run's entries, from VA 0x100 << 11 */
static unsigned long next = 0x100;	/* rmalloc's next index, 0 when the map is empty */
static int calls, multi, badargs;

void bcopy(const void *s, void *d, unsigned long n) { memmove(d, s, n); }
char *kmem_alloc(unsigned long n, int f) { (void)n, (void)f; return 0; }
void kmem_free(char *p, unsigned long n) { (void)p, (void)n; }
unsigned long vtop(char *va, char *p) { (void)p; return (unsigned long)va; }	/* identity */

unsigned long
rmalloc(char *map, unsigned long n)
{
	unsigned long i = next;

	if (map != sptmap || next == 0 || n > NPTE)
		return 0;
	next += n;
	return i;
}

/* the stock body: per page, the template's address, WP from the
 * protection, PG_V; the frame steps after each page */
void
segkmem_mapin(char *seg, char *addr, unsigned long len, unsigned long prot, unsigned long pa, int flags)
{
	unsigned long i, k = ((unsigned long)addr >> 11) - 0x100;

	calls++;
	if (seg != kvseg || flags != 1 || (prot != 1 && prot != 2) || ((unsigned long)addr & (PG - 1)))
		badargs++;
	if (len != PG)
		multi++;
	for (i = 0; i < len / PG && k + i < NPTE; i++, pa += PG)
		pte[k + i] = (pa & ~(PG - 1)) | (prot == 1 ? PG_W : 0) | PG_V;
}

char *plat_line_zwin(unsigned long);

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
	unsigned long n = (600UL * 200 + PG - 1) / PG, i, pa, same = 1, ro = 1;
	char *va, *zp;
	int zero = 1;

	va = plat_line_zwin(600UL * 200);
	check(va == (char *)(0x100UL << 11), "zwin30: the run's address is its sptmap index << PNUMSHFT");
	check(n == 59 && calls == 59 && multi == 0 && badargs == 0,
	    "zwin30: 59 pages for ninode 600, one segkmem_mapin of one page each (kvseg, PROT_READ, PTELD_LOCK)");
	pa = pte[0] & ~(PG - 1);
	for (i = 0; i < n; i++) {
		same &= (pte[i] & ~(PG - 1)) == pa;
		ro &= (pte[i] & (PG_W | PG_V)) == (PG_W | PG_V);
	}
	check(same && pte[n] == 0, "zwin30: every page maps the same frame, and nothing past the run");
	check(ro, "zwin30: every entry valid and write-protected (PG_W)");
	check((pa & (PG - 1)) == 0, "zwin30: the zeroed page is 2 KiB aligned");
	zp = (char *)pa;
	for (i = 0; i < PG; i++)
		zero &= zp[i] == 0;
	check(zero, "zwin30: the page reads zeros");
	memset(zp, 0x5a, PG);
	memset(pte, 0, sizeof pte);
	next = 0x100;
	calls = 0;
	va = plat_line_zwin(600UL * 200);
	zero = 1;
	for (i = 0; i < PG; i++)
		zero &= zp[i] == 0;
	check(va != 0 && (pte[0] & ~(PG - 1)) == pa && zero, "zwin30: the page is cleared before it is mapped");
	next = 0;
	calls = 0;
	check(plat_line_zwin(600UL * 200) == 0 && calls == 0, "zwin30: sptmap exhausted: no window, nothing mapped");
	check(plat_line_zwin(0) == 0, "zwin30: no inodes, no window");
	printf("t_zwin30: %d failed\n", fails);
	return fails != 0;
}
