/*
 * holdtop.c -- a bench tool: keep the top of the kernel's region allocated,
 * as a software MapROM tool's Kickstart copy or a reset-proof RAM disk
 * does, so a RAM-disk boot (amix-cdboot started after it) has to place its
 * image below the held block (10 section 5.4).  An AmigaDOS program
 * (cross-built with gcc-cross-amix, written as a load file by b2link -h),
 * run from a shell under AmigaOS.
 *
 * usage: holdtop [KIB]        hold the top KIB KiB (default 512)
 *
 * The region is the one boot2 binds the kernel in (ax_bind_region: the
 * largest non-chip region below 0x40000000).  The block is claimed with
 * AllocAbs and never freed: it stays allocated until the next reset, like
 * the memory those tools keep.  Prints the region and the block held.
 * Return code 0, or 20 when nothing could be held.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "b2.h"
#include "bootinfo.h"

#define RETURN_FAIL	20

static void *dosbase;
static long out;		/* the CLI's output file handle */

static long
dos(long lvo, ax_u32 d1, ax_u32 d2, ax_u32 d3)
{
	struct ax_regs r;

	REGS0(r);
	r.d1 = d1, r.d2 = d2, r.d3 = d3;
	return ax_call(dosbase, lvo, &r);
}

static void
put(const char *s)
{
	ax_u32 n = 0;

	while (s[n])
		n++;
	dos(-48, (ax_u32)out, (ax_u32)s, n);	/* Write */
}

static void
putx(ax_u32 v)
{
	static const char x[] = "0123456789abcdef";
	char a[11];
	int i;

	a[0] = '0', a[1] = 'x';
	for (i = 9; i >= 2; i--, v >>= 4)
		a[i] = x[v & 15];
	a[10] = 0;
	put(a);
}

long
ados_main(void *execbase, const char *args, long arglen)
{
	struct ax_memr r[AXB_MAXMEM];
	ax_u8 *mh;
	ax_u32 kib = 0, base, size, top, at;
	long i = 0;
	int n;

	ax_execbase = execbase;		/* adstart.s leaves it to C, as for axtime */
	dosbase = x_openlib("dos.library", 36);
	if (!dosbase)
		return RETURN_FAIL;
	out = dos(-60, 0, 0, 0);			/* Output */
	while (i < arglen && args[i] == ' ')
		i++;
	while (i < arglen && args[i] >= '0' && args[i] <= '9')
		kib = kib * 10 + (ax_u32)(args[i++] - '0');
	if (kib == 0)
		kib = 512;
	x_forbid();
	mh = *(ax_u8 **)((ax_u8 *)ax_execbase + EXEC_MEMLIST);
	for (n = 0; *(ax_u32 *)mh && n < AXB_MAXMEM; mh = *(ax_u8 **)mh, n++) {
		r[n].attr = *(ax_u16 *)(mh + 14);
		r[n].lower = *(ax_u32 *)(mh + 20);
		r[n].upper = *(ax_u32 *)(mh + 24);
	}
	x_permit();
	base = ax_bind_region(r, n, &size);
	top = base + size;
	put("holdtop: the kernel's region ");
	putx(base);
	put("-");
	putx(top);
	if (size <= kib * 1024) {
		put(": too small to hold that\n");
		return RETURN_FAIL;
	}
	at = (top - kib * 1024) & ~7UL;
	if (!x_allocabs(top - at, (void *)at)) {
		put(", its top is already in use\n");
		return RETURN_FAIL;
	}
	put(", held ");
	putx(at);
	put("-");
	putx(top);
	put(" until the next reset\n");
	return 0;
}
