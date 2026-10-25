/*
 * sys.c -- the AmigaOS calls boot2 makes, through ax_call (amiga.s).
 * Library vector offsets are those of the AmigaOS NDK.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "b2.h"

void *ax_execbase;

#define CALL(base, lvo, r) ax_call((base), (lvo), &(r))

void *
x_allocmem(ax_u32 size, ax_u32 flags)
{
	struct ax_regs r;

	REGS0(r);
	r.d0 = size, r.d1 = flags;
	return (void *)CALL(ax_execbase, -198, r);
}

void
x_freemem(void *p, ax_u32 size)
{
	struct ax_regs r;

	if (!p)
		return;
	REGS0(r);
	r.d0 = size, r.a1 = (ax_u32)p;
	CALL(ax_execbase, -210, r);
}

int
x_doio(void *iob)
{
	struct ax_regs r;

	REGS0(r);
	r.a1 = (ax_u32)iob;
	return (signed char)CALL(ax_execbase, -456, r);
}

void *
x_openlib(const char *name, ax_u32 version)
{
	struct ax_regs r;

	REGS0(r);
	r.a1 = (ax_u32)name, r.d0 = version;
	return (void *)CALL(ax_execbase, -552, r);
}

void
x_closelib(void *lib)
{
	struct ax_regs r;

	if (!lib)
		return;
	REGS0(r);
	r.a1 = (ax_u32)lib;
	CALL(ax_execbase, -414, r);
}

void
x_forbid(void)
{
	struct ax_regs r;

	REGS0(r);
	CALL(ax_execbase, -132, r);
}

void
x_permit(void)
{
	struct ax_regs r;

	REGS0(r);
	CALL(ax_execbase, -138, r);
}

ax_u32
x_typeofmem(const void *p)
{
	struct ax_regs r;

	REGS0(r);
	r.a1 = (ax_u32)p;
	return (ax_u32)CALL(ax_execbase, -534, r);
}

int
x_opendevice(const char *name, ax_u32 unit, void *ioreq, ax_u32 flags)
{
	struct ax_regs r;

	REGS0(r);
	r.a0 = (ax_u32)name, r.d0 = unit, r.a1 = (ax_u32)ioreq, r.d1 = flags;
	return (signed char)CALL(ax_execbase, -444, r);
}

void
x_closedevice(void *ioreq)
{
	struct ax_regs r;

	REGS0(r);
	r.a1 = (ax_u32)ioreq;
	CALL(ax_execbase, -450, r);
}

void *
x_findconfigdev(void *expbase, void *old, long manuf, long prod)
{
	struct ax_regs r;

	REGS0(r);
	r.a0 = (ax_u32)old, r.d0 = (ax_u32)manuf, r.d1 = (ax_u32)prod;
	return (void *)CALL(expbase, -72, r);
}

ax_u16
x_execversion(void)
{
	return *(ax_u16 *)((ax_u8 *)ax_execbase + EXEC_VERSION);
}

void
x_memcpy(void *d, const void *s, ax_u32 n)
{
	ax_u8 *dp = d;
	const ax_u8 *sp = s;

	while (n--)
		*dp++ = *sp++;
}

void
x_memset(void *d, int c, ax_u32 n)
{
	ax_u8 *dp = d;

	while (n--)
		*dp++ = (ax_u8)c;
}

/* the compiler calls these for structure assignment */
void *
memcpy(void *d, const void *s, unsigned long n)
{
	x_memcpy(d, s, n);
	return d;
}

void *
memset(void *d, int c, unsigned long n)
{
	x_memset(d, c, n);
	return d;
}
