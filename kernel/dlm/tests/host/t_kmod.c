/*
 * t_kmod.c -- km_tail: a root-class module's bss= by the module core's
 * layout rules (C3-5 section 3, C4-4 section 4), on objects built here.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <string.h>
#include "t.h"
#include "kmod.h"

static void
p16(ax_u8 *p, ax_u32 v)
{
	p[0] = (ax_u8)(v >> 8);
	p[1] = (ax_u8)v;
}

static void
p32(ax_u8 *p, ax_u32 v)
{
	p16(p, v >> 16);
	p16(p + 2, v);
}

/* one section header: type, flags, offset, size, alignment, entsize */
static void
sh(ax_u8 *o, ax_u32 type, ax_u32 flags, ax_u32 off, ax_u32 size, ax_u32 al, ax_u32 ent)
{
	memset(o, 0, 40);
	p32(o + 4, type);
	p32(o + 8, flags);
	p32(o + 16, off);
	p32(o + 20, size);
	p32(o + 32, al);
	p32(o + 36, ent);
}

/*
 * .text at 52 (aligned to talign), .bss 10 bytes (4), .bss2 3 bytes
 * (balign), and a symbol table of two commons, 5 bytes aligned to 2 and
 * 8 bytes aligned to calign
 */
static ax_u32
mkobj(ax_u8 *b, ax_u32 talign, ax_u32 balign, ax_u32 calign)
{
	ax_u32 sym = 64, shoff = 128;

	memset(b, 0, 400);
	memcpy(b, "\177ELF\001\002\001", 7);
	p16(b + 16, 1);
	p16(b + 18, 4);
	p32(b + 32, shoff);
	p16(b + 46, 40);
	p16(b + 48, 5);
	p32(b + sym + 16 + 4, 2);	/* common 1: alignment 2, size 5 */
	p32(b + sym + 16 + 8, 5);
	p16(b + sym + 16 + 14, 0xfff2);
	p32(b + sym + 32 + 4, calign);	/* common 2: size 8 */
	p32(b + sym + 32 + 8, 8);
	p16(b + sym + 32 + 14, 0xfff2);
	sh(b + shoff + 40, 1, 6, 52, 8, talign, 0);
	sh(b + shoff + 80, 8, 3, 60, 10, 4, 0);
	sh(b + shoff + 120, 8, 3, 60, 3, balign, 0);
	sh(b + shoff + 160, 2, 0, sym, 48, 4, 16);
	return shoff + 200;
}

void
test_kmod(void)
{
	static ax_u8 b[400];
	char why[128];
	ax_u32 n, tail = 0;

	/* .bss 0..10, .bss2 at 16..19, commons at 20..25 and 32..40 */
	n = mkobj(b, 4, 16, 8);
	T_EQ(km_tail(b, n, &tail, why), 0);
	T_EQ(tail, 40);
	/* an alignment the arena cannot give */
	n = mkobj(b, 4, 32, 8);
	T_EQ(km_tail(b, n, &tail, why), -1);
	T_CHECK(strstr(why, "aligns to 16") != 0);
	n = mkobj(b, 4, 16, 32);
	T_EQ(km_tail(b, n, &tail, why), -1);
	/* .text at 52 cannot run in place aligned to 8 */
	n = mkobj(b, 8, 16, 8);
	T_EQ(km_tail(b, n, &tail, why), -1);
	T_CHECK(strstr(why, "not a multiple") != 0);
	/* no NOBITS and no commons: 0, written even so */
	n = mkobj(b, 4, 16, 8);
	p32(b + 128 + 80 + 8, 0);
	p32(b + 128 + 120 + 8, 0);
	p16(b + 64 + 16 + 14, 1);
	p16(b + 64 + 32 + 14, 1);
	T_EQ(km_tail(b, n, &tail, why), 0);
	T_EQ(tail, 0);
}
