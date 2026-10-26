/*
 * t_deflate.c -- the box kbootset's deflate (kbootset/kdeflate.c) against
 * the loader's inflate: every input comes back byte for byte, a zero block
 * shrinks to almost nothing, and input it cannot shrink is left raw.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdlib.h>
#include <string.h>
#include "t.h"
#include "inflate.h"
#include "kdeflate.h"

static int
round_trip(const ax_u8 *in, ax_u32 n, ax_u32 *stored)
{
	static struct ax_inflate st;
	ax_u8 *z, *back;
	ax_u32 zn = 0, got = 0;
	int ok;

	if ((z = kb_deflate(in, n, &zn)) == 0)
		return -1;			/* not smaller */
	back = (ax_u8 *)malloc(n);
	ok = back && ax_inflate(&st, back, n, &got, z, zn) == AXI_OK && got == n && !memcmp(back, in, n);
	free(back);
	free(z);
	*stored = zn;
	return ok;
}

void
test_deflate(void)
{
	static ax_u8 buf[600000];
	ax_u32 i, s = 0, x = 12345;

	/* a kernel's shape: code-like bytes, then a 384 KiB zero arena */
	for (i = 0; i < 200000; i++)
		buf[i] = (ax_u8)("\x4e\x75\x20\x6f\x00\x04\x48\xe7\x30\x30"[i % 10] ^ (i / 997));
	memset(buf + 200000, 0, 393216);
	T_EQ(round_trip(buf, 593216, &s), 1);
	T_CHECK(s < 200000);			/* the arena costs almost nothing */
	/* runs longer than a match, matches at the window's far edge */
	memset(buf, 'a', 70000);
	for (i = 0; i < 40000; i++)
		buf[70000 + i] = (ax_u8)(i % 251);
	memcpy(buf + 110000, buf + 70000, 40000);
	T_EQ(round_trip(buf, 150000, &s), 1);
	/* noise: no gain, left raw */
	for (i = 0; i < 65536; i++) {
		x = x * 1103515245UL + 12345;
		buf[i] = (ax_u8)(x >> 16);
	}
	T_EQ(round_trip(buf, 65536, &s), -1);
	/* the smallest inputs */
	T_EQ(round_trip((const ax_u8 *)"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 40, &s), 1);
	T_EQ(kb_deflate(buf, 0, &s) == 0, 1);
}
