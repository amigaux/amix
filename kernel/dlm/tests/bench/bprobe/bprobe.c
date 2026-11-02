/*
 * bprobe.c -- bprobe at boot on metal: does a bus error on an empty Zorro
 * III address come back as bprobe's 1, and how long does it take?  The
 * same source builds two test modules (README.md beside it):
 *
 *   bproot  class root: _load runs in marc_root, level 7, the clock
 *           stopped (contract C4-2 section 2);
 *   bpboot  class boot: _load runs in marc_post (modadmin -B): at the
 *           pass's own level, inside spl7() (level 4 in these kernels:
 *           docs/abi/ddi.md), and with the status register at 0x2700.
 *
 * Each pass probes, reading one byte with bprobe(addr, -1):
 *   1. the custom chips (0xdff004, VPOSR): decoded on every Amiga, so 0;
 *   2. the empty address (default 0x20000000, parameter empty=), twice:
 *      on an A4000 nothing answers there, Buster ends the cycle with a
 *      bus error after its Zorro III timeout, and bprobe should give 1;
 *      skipped when a board in the boot list covers it;
 *   3. with a Z3660 whose window lies below 0x40000000 (autocon
 *      0x144b0001), its MAC_HI register (base + 0x198), then the word
 *      itself: the read a guarded window probe makes.
 * A line "probing ..." comes before every bus access that can fault, so
 * a hang names its address.  Each probe is timed with CIA-B's TOD
 * counter, which counts horizontal syncs (64 us on PAL, 63.56 us on
 * NTSC) and runs at any interrupt level.  Nothing is written anywhere.
 * _load returns ENXIO: the module is never linked.
 *
 * Built with the ABI kit (root/ and boot/ beside this file).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/param.h"
#include "sys/errno.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern long	lbolt;
extern char	bootinfo[];
extern int	autocon(), bprobe(), printf(), spl7(), splx();

#define	VPOSR	0x00dff004	/* the custom chips: decoded on every Amiga */
#define	TODHI	0x00bfda00	/* CIA-B TOD, high byte: reading it latches */
#define	TODMID	0x00bfd900
#define	TODLO	0x00bfd800	/* reading it releases the latch */
#define	EMPTY	0x20000000	/* Zorro III space no board of the A4000D holds */
#define	VSECT1	0x40000000	/* the end of the kernel's identity map */
#define	Z3660	0x144b0001	/* the Z3660's AutoConfig id */
#define	MAC_HI	0x198		/* its read-only-safe identity register */

/* the boot list (loader/common/bootinfo.h: AXB_AUTOCON, AXB_CFGSIZE,
 * AXB_MAXBOARDS; a ConfigDev with cd_BoardAddr at +32, cd_BoardSize at +36,
 * the manufacturer at +20 and the product at +17) */
#define	B_CFG	0x44
#define	B_MAX	16

#ifdef BP_ROOT
#define	TAG	"bproot"
#else
#define	TAG	"bpboot"
#endif

static int	ntsc;		/* from VPOSR: the TOD's tick */
static int	bad;		/* root pass: a level other than 7, or lbolt moved */
static long	lb0;

#define	R8(a)	(*(volatile unsigned char *)(a))
#define	R16(a)	(*(volatile unsigned short *)(a))

static int
level()
{
	unsigned short s;

	__asm__ __volatile__("movew %%sr,%0" : "=d" (s));
	return (s >> 8) & 7;
}

static unsigned long
tod()
{
	unsigned long h, m, l;

	h = R8(TODHI);
	m = R8(TODMID);
	l = R8(TODLO);
	return h << 16 | m << 8 | l;
}

/* TOD ticks to microseconds */
static unsigned long
usec(t)
	unsigned long t;
{
	t &= 0xffffff;
	return ntsc ? t * 6356 / 100 : t * 64;
}

static unsigned long
get32(p)
	char *p;
{
	unsigned char *u = (unsigned char *)p;

	return (unsigned long)u[0] << 24 | (unsigned long)u[1] << 16 | u[2] << 8 | u[3];
}

/* one byte read through bprobe, timed; returns bprobe's answer */
static int
probe(pass, what, a)
	char *pass, *what;
	unsigned long a;
{
	unsigned long t0, t1;
	int r, l;

	printf("%s: %s: probing %s at %x\n", TAG, pass, what, (int)a);
	t0 = tod();
	r = bprobe((caddr_t)a, -1);
	t1 = tod();
	l = level();
	printf("%s: %s: bprobe %s (%x, read) -> %d (%s) in %d us (%d TOD ticks), level %d%s\n",
	    TAG, pass, what, (int)a, r, r == 0 ? "no fault" : r == 1 ? "bus error caught" : "?",
	    (int)usec(t1 - t0), (int)((t1 - t0) & 0xffffff), l,
#ifdef BP_ROOT
	    lbolt == lb0 ? ", lbolt unmoved" : ", lbolt MOVED");
	if (l != 7 || lbolt != lb0)
		bad++;
#else
	    "");
#endif
	return r;
}

/* is a in a board of the boot list?  The board's name goes to the console. */
static int
covered(a)
	unsigned long a;
{
	unsigned long base, size, id;
	char *c;
	int i;

	for (i = 0; i < B_MAX; i++) {
		c = bootinfo + i * B_CFG;
		id = get32(c + 20) >> 16 << 16 | ((unsigned char *)c)[17];
		if (id >> 16 == 0)
			break;
		base = get32(c + 32);
		size = get32(c + 36);
		if (a >= base && a - base < size) {
			printf("%s: %x lies in board %x (base %x size %x): not probed\n",
			    TAG, (int)a, (int)id, (int)base, (int)size);
			return 1;
		}
	}
	return 0;
}

/* the parameter empty=<hex>, as the manifest passes it (0: skip) */
static unsigned long
empty_param(params)
	char *params;
{
	unsigned long v = EMPTY;
	char *p;
	int c;

	for (p = params; p && *p; p++) {
		if ((p == params || p[-1] == ' ') && bcmp(p, "empty=", 6) == 0) {
			for (v = 0, p += 6; (c = *p) && c != ' '; p++) {
				if (c == 'x' || c == 'X')
					v = 0;
				else if (c >= '0' && c <= '9')
					v = v * 16 + c - '0';
				else if (c >= 'a' && c <= 'f')
					v = v * 16 + c - 'a' + 10;
				else if (c >= 'A' && c <= 'F')
					v = v * 16 + c - 'A' + 10;
			}
			break;
		}
	}
	return v;
}

/* one pass of the probes; the verdict line */
static void
pass(name, params)
	char *name, *params;
{
	unsigned base = 0, size = 0;
	unsigned long e = empty_param(params);
	int good, r1 = -1, r2 = -1, z = -1;

	good = probe(name, "custom chips", (unsigned long)VPOSR);
	if (e == 0)
		printf("%s: %s: empty=0: the empty address is not probed\n", TAG, name);
	else if (e >= VSECT1)
		printf("%s: %s: %x is above the identity map: a fault there is the MMU's, "
		    "not the bus's; not probed\n", TAG, name, (int)e);
	else if (!covered(e)) {
		r1 = probe(name, "empty Zorro III", e);
		r2 = probe(name, "empty Zorro III again", e);
	}
	if (autocon(Z3660, 0, &base, &size) && base && base < VSECT1) {
		z = probe(name, "Z3660 MAC_HI", (unsigned long)base + MAC_HI);
		if (z == 0)
			printf("%s: %s: Z3660 MAC_HI word %x\n", TAG, name,
			    (int)R16((unsigned long)base + MAC_HI));
	} else
		printf("%s: %s: no Z3660 window below %x (autocon base %x)\n", TAG, name,
		    VSECT1, base);
	printf("%s: %s: RESULT good=%s empty=%s z3660=%s%s\n", TAG, name,
	    good == 0 ? "ok" : "FAIL",
	    r1 < 0 ? "skipped" : r1 == 1 && r2 == 1 ? "caught" : r1 == 0 && r2 == 0 ? "NO-FAULT" : "MIXED",
	    z < 0 ? "absent" : z == 0 ? "ok" : "FAIL",
#ifdef BP_ROOT
	    bad ? " level=FAIL" : " level=ok");
#else
	    "");
#endif
}

static int
bprobe_load(params)
	char *params;
{
	unsigned short v = R16(VPOSR);
	int s;
#ifndef BP_ROOT
	unsigned long t0, t1;
	long l0;
	volatile int spin;
	unsigned short sr7;
#endif

	ntsc = (v >> 8 & 0x10) != 0;	/* Agnus id bit 4: NTSC */
	lb0 = lbolt;
	printf("%s: level %d, lbolt %x, VPOSR %x (%s), params '%s'\n", TAG, level(), (int)lb0,
	    (int)v, ntsc ? "NTSC, TOD tick 63.56 us" : "PAL, TOD tick 64 us",
	    params ? params : "");
#ifdef BP_ROOT
	pass("root pass", params);
	s = 0;
#else
	/* the TOD against the clock, where the clock runs */
	l0 = lbolt;
	t0 = tod();
	for (spin = 0; spin < 2000000; spin++)
		;
	t1 = tod();
	printf("%s: TOD check: %d us by the TOD, %d lbolt ticks (HZ %d) over a spin\n", TAG,
	    (int)usec(t1 - t0), (int)(lbolt - l0), HZ);
	pass("boot pass", params);
	s = spl7();		/* level 4 in these kernels (ddi.md: no spl masks level 6) */
	pass("boot pass at spl7 (level 4)", params);
	splx(s);
	/* level 7 itself, as the root pass runs and as a driver that writes the
	 * status register gets it: the clock stops until it is restored */
	__asm__ __volatile__("movew %%sr,%0" : "=d" (sr7));
	__asm__ __volatile__("movew %0,%%sr" : : "d" ((unsigned short)0x2700));
	pass("boot pass at level 7", params);
	__asm__ __volatile__("movew %0,%%sr" : : "d" (sr7));
#endif
	return ENXIO;		/* never linked */
}

static int
bprobe_unload()
{
	return 0;
}

#ifdef BP_ROOT
MOD_MISC_WRAPPER(bproot, bprobe_load, bprobe_unload, "bprobe test, root pass");
#else
MOD_MISC_WRAPPER(bpboot, bprobe_load, bprobe_unload, "bprobe test, boot pass");
#endif
