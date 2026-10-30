/*
 * di_ops.c - 64-bit ("DImode") integer helper routines for gcc 2.7.2.3
 * on m68k SVR4 (Amix).  The gcc-cross-amix toolchain ships NO libgcc.a,
 * but gcc emits library calls for 64-bit divide/modulo/shift and
 * double<->long long conversion (verified by compiling test code and
 * inspecting the undefined symbols).  This file provides exactly those
 * entry points with the standard libgcc names and C-level ABI.
 *
 * IMPORTANT: the implementations only ever use 32-bit arithmetic
 * internally (via a hi/lo union) - any 64-bit /, %, or shift inside
 * these functions would recurse into themselves.
 *
 * Built into build-amix/lib/libgcc.a by build-amix.sh; every tool links
 * with "-lgcc -lc".
 *
 * This is an original, independent implementation (NOT derived from the
 * GNU libgcc sources).
 *
 * Copyright (c) 2026 Jussi Alanärä
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
 */

typedef long long DI;
typedef unsigned long long UDI;
typedef unsigned long UL;

/* m68k is big-endian: high word first */
union dd {
	UDI	ll;
	struct {
		UL	hi;
		UL	lo;
	} s;
};

/*
 * 64/64 -> 64 unsigned divide and remainder, classic bit-by-bit
 * shift-subtract; 64 iterations, 32-bit operations only.
 */
static void
udivmod64(UDI num, UDI den, UDI *quot, UDI *rem)
{
	union dd n, d, q, r;
	int i;
	UL nbit;

	n.ll = num;
	d.ll = den;
	q.s.hi = q.s.lo = 0;
	r.s.hi = r.s.lo = 0;

	if (d.s.hi == 0 && d.s.lo == 0) {
		/* divide by zero: mimic hardware trap-free garbage (all 1s) */
		if (quot != 0) {
			q.s.hi = q.s.lo = 0xffffffffUL;
			*quot = q.ll;
		}
		if (rem != 0) {
			r.s.hi = r.s.lo = 0;
			*rem = r.ll;
		}
		return;
	}

	for (i = 0; i < 64; i++) {
		/* nbit = msb of n; n <<= 1 */
		nbit = (n.s.hi >> 31) & 1;
		n.s.hi = (n.s.hi << 1) | ((n.s.lo >> 31) & 1);
		n.s.lo = n.s.lo << 1;

		/* r = (r << 1) | nbit */
		r.s.hi = (r.s.hi << 1) | ((r.s.lo >> 31) & 1);
		r.s.lo = (r.s.lo << 1) | nbit;

		/* q <<= 1 */
		q.s.hi = (q.s.hi << 1) | ((q.s.lo >> 31) & 1);
		q.s.lo = q.s.lo << 1;

		/* if (r >= d) { r -= d; q |= 1; } (32-bit compare/borrow) */
		if (r.s.hi > d.s.hi ||
		    (r.s.hi == d.s.hi && r.s.lo >= d.s.lo)) {
			if (r.s.lo < d.s.lo)
				r.s.hi--;	/* borrow */
			r.s.lo -= d.s.lo;
			r.s.hi -= d.s.hi;
			q.s.lo |= 1;
		}
	}

	if (quot != 0)
		*quot = q.ll;
	if (rem != 0)
		*rem = r.ll;
}

/* negate a 64-bit value using 32-bit ops (two's complement) */
static UDI
neg64(UDI v)
{
	union dd a;

	a.ll = v;
	a.s.hi = ~a.s.hi;
	a.s.lo = ~a.s.lo;
	a.s.lo += 1;
	if (a.s.lo == 0)
		a.s.hi += 1;
	return (a.ll);
}

UDI
__udivdi3(UDI n, UDI d)
{
	UDI q;

	udivmod64(n, d, &q, 0);
	return (q);
}

UDI
__umoddi3(UDI n, UDI d)
{
	UDI r;

	udivmod64(n, d, 0, &r);
	return (r);
}

DI
__divdi3(DI n, DI d)
{
	union dd a, b;
	int neg = 0;
	UDI un, ud, q;

	a.ll = (UDI)n;
	b.ll = (UDI)d;
	un = (UDI)n;
	ud = (UDI)d;
	if (a.s.hi & 0x80000000UL) {
		un = neg64(un);
		neg = !neg;
	}
	if (b.s.hi & 0x80000000UL) {
		ud = neg64(ud);
		neg = !neg;
	}
	udivmod64(un, ud, &q, 0);
	if (neg)
		q = neg64(q);
	return ((DI)q);
}

DI
__moddi3(DI n, DI d)
{
	union dd a, b;
	int neg = 0;
	UDI un, ud, r;

	a.ll = (UDI)n;
	b.ll = (UDI)d;
	un = (UDI)n;
	ud = (UDI)d;
	if (a.s.hi & 0x80000000UL) {
		un = neg64(un);
		neg = 1;	/* C89/C99: remainder takes sign of dividend */
	}
	if (b.s.hi & 0x80000000UL)
		ud = neg64(ud);
	udivmod64(un, ud, 0, &r);
	if (neg)
		r = neg64(r);
	return ((DI)r);
}

DI
__ashldi3(DI u, int b)
{
	union dd a;

	if (b <= 0)
		return (u);
	a.ll = (UDI)u;
	if (b >= 64) {
		a.s.hi = a.s.lo = 0;
	} else if (b >= 32) {
		a.s.hi = a.s.lo << (b - 32);
		a.s.lo = 0;
	} else {
		a.s.hi = (a.s.hi << b) | (a.s.lo >> (32 - b));
		a.s.lo = a.s.lo << b;
	}
	return ((DI)a.ll);
}

UDI
__lshrdi3(UDI u, int b)
{
	union dd a;

	if (b <= 0)
		return (u);
	a.ll = u;
	if (b >= 64) {
		a.s.hi = a.s.lo = 0;
	} else if (b >= 32) {
		a.s.lo = a.s.hi >> (b - 32);
		a.s.hi = 0;
	} else {
		a.s.lo = (a.s.lo >> b) | (a.s.hi << (32 - b));
		a.s.hi = a.s.hi >> b;
	}
	return (a.ll);
}

DI
__ashrdi3(DI u, int b)
{
	union dd a;
	UL sign;

	if (b <= 0)
		return (u);
	a.ll = (UDI)u;
	sign = (a.s.hi & 0x80000000UL) ? 0xffffffffUL : 0;
	if (b >= 64) {
		a.s.hi = a.s.lo = sign;
	} else if (b >= 32) {
		a.s.lo = (b == 32) ? a.s.hi :
		    ((a.s.hi >> (b - 32)) |
		    (sign ? (0xffffffffUL << (64 - b)) : 0));
		a.s.hi = sign;
	} else {
		a.s.lo = (a.s.lo >> b) | (a.s.hi << (32 - b));
		a.s.hi = (a.s.hi >> b) |
		    (sign ? (0xffffffffUL << (32 - b)) : 0);
	}
	return ((DI)a.ll);
}

/*
 * double -> long long / unsigned long long, and back.
 *
 * NOTE: only SIGNED long <-> double conversions are used, in pieces
 * small enough to always fit a signed 32-bit long.  gcc 2.7 compiles
 * unsigned SImode <-> double with an "fcmp.d %fpN,&<imm>" sequence
 * that the binutils 2.8.1 m68k-svr4 assembler rejects (verified);
 * signed conversions are single fintrz/fmove.l instructions.
 */
#define TWO32	4294967296.0
#define TWO16	65536.0

/* double in [0, 2^32) -> 32 bits, via two signed 16-bit pieces */
static UL
dtoul32(double d)
{
	long h16, l16;

	h16 = (long)(d / TWO16);		/* < 2^16: fits signed */
	l16 = (long)(d - ((double)h16 * TWO16));/* < 2^16: fits signed */
	return (((UL)h16 << 16) | ((UL)l16 & 0xffffUL));
}

/* 32 unsigned bits -> double, via two signed 16-bit pieces */
static double
ul32tod(UL v)
{
	return (((double)(long)((v >> 16) & 0xffffUL)) * TWO16 +
	    (double)(long)(v & 0xffffUL));
}

DI
__fixdfdi(double d)
{
	union dd a;
	int neg = 0;
	long hi;

	if (d < 0) {
		neg = 1;
		d = -d;
	}
	hi = (long)(d / TWO32);			/* < 2^31: fits signed */
	a.s.hi = (UL)hi;
	a.s.lo = dtoul32(d - ((double)hi * TWO32));
	if (neg)
		return ((DI)neg64(a.ll));
	return ((DI)a.ll);
}

UDI
__fixunsdfdi(double d)
{
	union dd a;
	long hi;

	if (d < 0)
		return (0);
	hi = (long)(d / TWO32);
	a.s.hi = (UL)hi;
	a.s.lo = dtoul32(d - ((double)hi * TWO32));
	return (a.ll);
}

double
__floatdidf(DI u)
{
	union dd a;
	int neg = 0;
	double d;

	a.ll = (UDI)u;
	if (a.s.hi & 0x80000000UL) {
		a.ll = neg64(a.ll);
		neg = 1;
	}
	d = ul32tod(a.s.hi) * TWO32 + ul32tod(a.s.lo);
	return (neg ? -d : d);
}

/*
 * 64-bit three-way compares (gcc emits calls for some comparison
 * shapes at -O; cheap to provide).  Return 0/1/2 for </==/>.
 */
int
__cmpdi2(DI x, DI y)
{
	union dd a, b;
	long ahi, bhi;

	a.ll = (UDI)x;
	b.ll = (UDI)y;
	ahi = (long)a.s.hi;
	bhi = (long)b.s.hi;
	if (ahi < bhi)
		return (0);
	if (ahi > bhi)
		return (2);
	if (a.s.lo < b.s.lo)
		return (0);
	if (a.s.lo > b.s.lo)
		return (2);
	return (1);
}

int
__ucmpdi2(UDI x, UDI y)
{
	union dd a, b;

	a.ll = x;
	b.ll = y;
	if (a.s.hi < b.s.hi)
		return (0);
	if (a.s.hi > b.s.hi)
		return (2);
	if (a.s.lo < b.s.lo)
		return (0);
	if (a.s.lo > b.s.lo)
		return (2);
	return (1);
}

/* 64-bit negate (gcc may emit __negdi2 at -O0; harmless to provide) */
DI
__negdi2(DI u)
{
	return ((DI)neg64((UDI)u));
}

/* long long -> float (via the double conversion above) */
float
__floatdisf(DI u)
{
	return ((float)__floatdidf(u));
}
