/*
 * t44intr.c -- S3-44 (M-INT1, bench half): the core's interrupt chains on
 * a kernel of record.  Its _load attaches a counting handler to level 2
 * and two to level 6 (one that claims every call, then one that counts),
 * and raises PORTS and EXTER once from software, as z3660eth's self-test
 * does.  Its _unload prints the counts and detaches.  Every handler of a
 * chain is called every time (30 section 4): the level-6 counter sees as
 * many calls as the claimer.  No handler calls the DDI: level 6 is masked
 * by no spl.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

#define	INTREQ		0xDFF09C	/* Paula INTREQ, identity-mapped */
#define	SETCLR		0x8000
#define	EXTER		0x2000		/* level 6 */
#define	PORTS		0x0008		/* level 2 */
#define	SPIN		200000
#define	RAISE(bits)	(*(volatile unsigned short *)INTREQ = (unsigned short)(SETCLR | (bits)))

static long		n2, n6c, n6;
static volatile int	want2, want6;

static int
t44_h2(arg)
	char *arg;
{
	n2++;
	want2 = 0;
	return 0;
}

static int
t44_h6claim(arg)
	char *arg;
{
	n6c++;
	return 1;
}

static int
t44_h6(arg)
	char *arg;
{
	n6++;
	want6 = 0;
	return 0;
}

/* raise bits from software, wait for the handler to see it: the spins, or -1 */
static int
t44_raise(bits, flag)
	int bits;
	volatile int *flag;
{
	int i;

	*flag = 1;
	RAISE(bits);
	for (i = 0; i < SPIN; i++)
		if (!*flag)
			return i;
	*flag = 0;
	return -1;
}

static int
t44intr_load(params)
	char *params;
{
	int e2, e6c, e6;

	e2 = intr_attach(2, t44_h2, (char *)0, "t44intr");
	e6c = intr_attach(6, t44_h6claim, (char *)0, "t44intr");
	e6 = intr_attach(6, t44_h6, (char *)0, "t44intr");
	printf("t44intr: attached: level 2 counter %d, level 6 claimer %d, counter %d\n", e2, e6c, e6);
	if (e2 || e6c || e6) {
		(void)intr_detach(2, t44_h2, (char *)0);
		(void)intr_detach(6, t44_h6claim, (char *)0);
		(void)intr_detach(6, t44_h6, (char *)0);
		return e2 ? e2 : e6c ? e6c : e6;
	}
	e2 = t44_raise(PORTS, &want2);
	e6 = t44_raise(EXTER, &want6);
	printf("t44intr: software PORTS seen after %d spins, EXTER after %d (-1: never)\n", e2, e6);
	return 0;
}

static int
t44intr_unload()
{
	int e2, e6c, e6;

	printf("t44intr: level 2: %d calls; level 6: claimer %d calls, counter %d calls\n",
	    (int)n2, (int)n6c, (int)n6);
	e2 = intr_detach(2, t44_h2, (char *)0);
	e6c = intr_detach(6, t44_h6claim, (char *)0);
	e6 = intr_detach(6, t44_h6, (char *)0);
	printf("t44intr: detached %d %d %d; again %d\n", e2, e6c, e6,
	    intr_detach(2, t44_h2, (char *)0));
	return 0;
}

MOD_MISC_WRAPPER(t44intr, t44intr_load, t44intr_unload, "S3-44 interrupt chains");
