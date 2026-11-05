/*
 * b2memcap.c -- test helper: what core_boot hands the kernel, and says, for
 * the memory of a box (loader/boot2/core.c, compiled in whole; boot2 and
 * amix-cdboot link that one object).  Each case gives a line and exec's
 * regions; memory_cap must leave the expected tops and print the expected
 * line, or nothing.  Prints each case's line for the record; exit status 0
 * when all hold.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include "core.c"

static char said[256];

void
con_say(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vsprintf(said, fmt, ap);
	va_end(ap);
}

/* core_boot's other calls: the cases never reach them */
static void never(void) { fputs("b2memcap: unexpected call\n", stderr); exit(2); }
void *ax_execbase;
long ax_call(void *b, long l, struct ax_regs *r) { (void)b, (void)l, (void)r; never(); return 0; }
long ax_super(void (*f)(void), void *a) { (void)f, (void)a; never(); return 0; }
void ax_probe(void) { never(); }
void ax_handoff(void) { never(); }
void ax_handoff_end(void) { never(); }
void *x_allocmem(ax_u32 s, ax_u32 f) { (void)s, (void)f; never(); return 0; }
void x_freemem(void *p, ax_u32 s) { (void)p, (void)s; never(); }
void *x_allocabs(ax_u32 s, void *l) { (void)s, (void)l; never(); return 0; }
void *x_openlib(const char *n, ax_u32 v) { (void)n, (void)v; never(); return 0; }
void *x_findconfigdev(void *e, void *o, long m, long p) { (void)e, (void)o, (void)m, (void)p; never(); return 0; }
ax_u16 x_execversion(void) { never(); return 0; }
void x_memcpy(void *d, const void *s, ax_u32 n) { memcpy(d, s, n); }
void x_memset(void *d, int c, ax_u32 n) { memset(d, c, n); }
void con_init(ax_u32 b) { (void)b; never(); }
void con_screen(void) { never(); }
void in_init(void *p) { (void)p; never(); }
int menu_window(ax_u32 d, ax_u8 k[16]) { (void)d, (void)k; never(); return 0; }
ax_u32 menu_previous(const struct ax_ctl *c) { (void)c; never(); return 0; }
ax_u32 menu_run(const struct ax_ctl *c, ax_u32 f, ax_u32 cp, int *s, int *d) { (void)c, (void)f, (void)cp, (void)s, (void)d; never(); return 0; }

#define MB(n)	((ax_u32)(n) << 20)
#define CHIP	{ 0x3, 0x400, 0x200000, 0x200000 }

struct region { ax_u32 attr, lower, upper, want; };
struct mcase {
	const char *line;
	const char *say;		/* "" = nothing */
	struct region r[4];
};

#define K30S(n, of)	"k30 kernel: using " #n " MiB of the " #of " MiB here\n"
#define K46S(n, of)	"k46 kernel: using " #n " MiB of the " #of " MiB here\n"
#define FAST(base, mb, wantmb)	{ 0x5, (base) + 0x20, (base) + MB(mb), (base) + MB(wantmb) }
#define BANK	0x08000000UL
#define BELOW(mb)	{ 0x5, BANK - MB(mb) + 0x20, BANK, BANK }	/* touching the bank */
#define SHORT(mb)	{ 0x5, BANK - MB(mb) + 0x20, BANK, BANK - 0x800 }	/* a page short */

static const struct mcase cases[] = {
	/* k30: over, at and under 64 MiB */
	{ "k30", K30S(64, 128), { CHIP, FAST(BANK, 128, 64) } },
	{ "k30", K30S(64, 256), { CHIP, FAST(BANK, 256, 64) } },
	{ "k30", K30S(64, 65), { CHIP, { 0x5, BANK + 0x20, BANK + MB(64) + 0x10000, BANK + MB(64) } } },
	{ "k30", "", { CHIP, FAST(BANK, 64, 64) } },
	{ "k30", "", { CHIP, FAST(BANK, 32, 32) } },
	{ "k30", "", { CHIP, FAST(0x07000000UL, 16, 16) } },
	/* k30: a touching bank goes to the DMA pool, a page short, whatever the size */
	{ "k30", K30S(64, 128), { CHIP, SHORT(16), FAST(BANK, 128, 64) } },
	{ "k30", "", { CHIP, SHORT(16), FAST(BANK, 64, 64) } },
	{ "k30", "", { CHIP, SHORT(16), FAST(BANK, 32, 32) } },
	/* Zorro III memory is never the kernel's and is never cut */
	{ "k30", K30S(64, 128), { CHIP, FAST(BANK, 128, 64), { 0x5, 0x40000020UL, 0x48000000UL, 0x48000000UL } } },
	{ "k30", "", { CHIP, FAST(BANK, 32, 32), { 0x5, 0x40000020UL, 0x48000000UL, 0x48000000UL } } },
	/* k46: over, at and under 128 MiB */
	{ "k46", K46S(128, 256), { CHIP, FAST(BANK, 256, 128) } },
	{ "k46", K46S(128, 129), { CHIP, { 0x5, BANK + 0x20, BANK + MB(128) + 0x10000, BANK + MB(128) } } },
	{ "k46", "", { CHIP, FAST(BANK, 128, 128) } },
	{ "k46", "", { CHIP, FAST(BANK, 64, 64) } },
	/* k46: a touching bank stays joined and counts */
	{ "k46", K46S(128, 144), { CHIP, BELOW(16), FAST(BANK, 128, 112) } },
	{ "k46", K46S(128, 272), { CHIP, BELOW(16), FAST(BANK, 256, 112) } },
	{ "k46", "", { CHIP, BELOW(16), FAST(BANK, 112, 112) } },
	{ "k46", "", { CHIP, BELOW(16), FAST(BANK, 64, 64) } },
	{ "k46", K46S(128, 192), { CHIP, BELOW(64), FAST(BANK, 128, 64) } },
	/* k46: one over half the cap would leave too little: out, a page short */
	{ "k46", K46S(128, 256), { CHIP, SHORT(96), FAST(BANK, 256, 128) } },
	/* a bank of its own, as without a card */
	{ "k46", "", { CHIP, FAST(0x07000000UL, 16, 16) } }
};

int
main(void)
{
	static struct work ww;
	unsigned i;
	int j, n, bad = 0;

	w = &ww;
	for (i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
		const struct mcase *c = &cases[i];
		struct ax_memr mr[4];
		ax_u32 room;

		for (n = 0; n < 4 && c->r[n].upper; n++) {
			ax_u8 *m = w->mems + n * AXB_MEMSIZE;

			memset(m, 0, AXB_MEMSIZE);
			AX_PUT16(m + 14, c->r[n].attr);
			AX_PUT32(m + 20, c->r[n].lower);
			AX_PUT32(m + 24, c->r[n].upper);
			mr[n].attr = (ax_u16)c->r[n].attr;
			mr[n].lower = c->r[n].lower;
			mr[n].upper = c->r[n].upper;
		}
		vaddr = ax_bind_region(mr, n, &room);
		linecap = c->line[1] == '3' ? AX_K30_MEMCAP : AX_K46_MEMCAP;
		man.line = (char *)c->line;
		said[0] = 0;
		memory_cap(n);
		printf("%s, %d regions: %s", c->line, n, said[0] ? said : "(nothing)\n");
		if (strcmp(said, c->say)) {
			printf("  FAILED: expected \"%s\"\n", c->say);
			bad = 1;
		}
		for (j = 0; j < n; j++)
			if (AX_GET32(w->mems + j * AXB_MEMSIZE + 24) != c->r[j].want) {
				printf("  FAILED: region %d ends at %08x, expected %08x\n", j,
				       (unsigned)AX_GET32(w->mems + j * AXB_MEMSIZE + 24),
				       (unsigned)c->r[j].want);
				bad = 1;
			}
	}
	printf("b2memcap: %s\n", bad ? "FAILED" : "ok");
	return bad;
}
