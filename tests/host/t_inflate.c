/*
 * t_inflate.c -- the inflate decoder against zlib's raw deflate output:
 * stored, fixed and dynamic blocks, many sizes, and damaged input.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include "t.h"
#include "inflate.h"

static struct ax_inflate st;

/* raw deflate with zlib; returns the compressed length */
static unsigned long
zdeflate(const unsigned char *in, unsigned long n, unsigned char *out, unsigned long cap,
	 int level, int strategy)
{
	z_stream z;

	memset(&z, 0, sizeof(z));
	deflateInit2(&z, level, Z_DEFLATED, -15, 9, strategy);
	z.next_in = (unsigned char *)in;
	z.avail_in = n;
	z.next_out = out;
	z.avail_out = cap;
	deflate(&z, Z_FINISH);
	deflateEnd(&z);
	return cap - z.avail_out;
}

static void
fill(unsigned char *p, unsigned long n, int kind, unsigned seed)
{
	unsigned long i;
	static const char words[] = "amix kernel module loader store generation ";

	srand(seed);
	for (i = 0; i < n; i++) {
		if (kind == 0)
			p[i] = (unsigned char)rand();
		else if (kind == 1)
			p[i] = (unsigned char)words[(i + rand() % 3) % (sizeof(words) - 1)];
		else
			p[i] = (unsigned char)(i / 1000);
	}
}

static int
roundtrip(unsigned long n, int kind, int level, int strategy)
{
	unsigned char *src = malloc(n + 1), *z = malloc(n + n / 2 + 1024), *dst = malloc(n + 1);
	unsigned long zn;
	ax_u32 got = 0;
	int rc, ok;

	fill(src, n, kind, (unsigned)(n + kind));
	zn = zdeflate(src, n, z, n + n / 2 + 1024, level, strategy);
	rc = ax_inflate(&st, dst, n, &got, z, zn);
	ok = rc == AXI_OK && got == n && memcmp(src, dst, n) == 0;
	free(src);
	free(z);
	free(dst);
	return ok;
}

void
test_inflate(void)
{
	static const unsigned long sizes[] = { 0, 1, 2, 100, 4095, 65536, 300000 };
	unsigned i;
	int kind;
	unsigned char src[2000], z[4000], dst[2000];
	unsigned long zn;
	ax_u32 got;

	for (i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++)
		for (kind = 0; kind < 3; kind++) {
			T_CHECK(roundtrip(sizes[i], kind, 0, Z_DEFAULT_STRATEGY));	/* stored */
			T_CHECK(roundtrip(sizes[i], kind, 6, Z_FIXED));			/* fixed */
			T_CHECK(roundtrip(sizes[i], kind, 9, Z_DEFAULT_STRATEGY));	/* dynamic */
			T_CHECK(roundtrip(sizes[i], kind, 1, Z_HUFFMAN_ONLY));
			T_CHECK(roundtrip(sizes[i], kind, 9, Z_RLE));
		}

	/* damaged input */
	fill(src, sizeof(src), 1, 7);
	zn = zdeflate(src, sizeof(src), z, sizeof(z), 9, Z_DEFAULT_STRATEGY);
	T_EQ(ax_inflate(&st, dst, sizeof(src), &got, z, zn - 3), AXI_EINPUT);	/* truncated */
	T_EQ(ax_inflate(&st, dst, sizeof(src) - 1, &got, z, zn), AXI_EOUTPUT);	/* buffer short */
	z[0] |= 0x06;								/* block type 3 */
	T_EQ(ax_inflate(&st, dst, sizeof(src), &got, z, zn), AXI_EBLOCK);
	/* a stored block whose length check fails */
	z[0] = 0x01; z[1] = 0x05; z[2] = 0x00; z[3] = 0x00; z[4] = 0x00;
	T_EQ(ax_inflate(&st, dst, sizeof(src), &got, z, 10), AXI_ESTORED);
	/* a distance before the start of the output: fixed block, first symbol
	 * a length code (257 = 0000001, 7 bits), distance code 0 */
	z[0] = 0x03; z[1] = 0x02; z[2] = 0x00; z[3] = 0x00;
	T_EQ(ax_inflate(&st, dst, sizeof(src), &got, z, 4), AXI_EDIST);
}
