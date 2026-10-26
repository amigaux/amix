/*
 * kdeflate.c -- a raw deflate (RFC 1951) for the kbootset that runs on the
 * box, which has no zlib: one final block with the fixed Huffman codes,
 * LZ77 over a 32 KiB window, the longest of up to CHAIN earlier places with
 * the same 3-byte hash, one byte of lazy matching.  It compresses what
 * the stores hold well enough (the arena's zero block to nothing, code
 * about 60 %), and the loader's own inflate reads it.  The host build
 * keeps zlib, so the media of record stay byte for byte as they were.
 *
 * Portable C89.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdlib.h>
#include <string.h>
#include "kdeflate.h"

#define WIN	32768UL
#define HBITS	15
#define MAXLEN	258
#define CHAIN	128

struct bw {
	ax_u8 *p;
	ax_u32 n, cap;
	ax_u32 acc;
	int nb;
};

static int
put(struct bw *w, ax_u32 v, int n)	/* n bits of v, least significant first */
{
	w->acc |= v << w->nb;
	w->nb += n;
	while (w->nb >= 8) {
		if (w->n == w->cap)
			return -1;
		w->p[w->n++] = (ax_u8)w->acc;
		w->acc >>= 8;
		w->nb -= 8;
	}
	return 0;
}

static int
huff(struct bw *w, ax_u32 code, int n)	/* a Huffman code, most significant bit first */
{
	ax_u32 r = 0;
	int i;

	for (i = 0; i < n; i++)
		r = r << 1 | (code >> i & 1);
	return put(w, r, n);
}

static int
lit(struct bw *w, unsigned v)		/* the fixed literal/length code of v */
{
	if (v < 144)
		return huff(w, 0x30 + v, 8);
	if (v < 256)
		return huff(w, 0x190 + v - 144, 9);
	if (v < 280)
		return huff(w, v - 256, 7);
	return huff(w, 0xc0 + v - 280, 8);
}

static const unsigned short lbase[29] = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27,
	31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
static const unsigned char lext[29] = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3,
	3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
static const unsigned short dbase[30] = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129,
	193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
static const unsigned char dext[30] = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7,
	8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };

static int
match(struct bw *w, unsigned len, ax_u32 dist)
{
	int c, d;

	for (c = 28; lbase[c] > len; c--)
		;
	for (d = 29; dbase[d] > dist; d--)
		;
	return lit(w, 257 + c) || put(w, len - lbase[c], lext[c]) ||
	       huff(w, d, 5) || put(w, dist - dbase[d], dext[d]);
}

#define HASH(p)	((((ax_u32)(p)[0] << 10) ^ ((ax_u32)(p)[1] << 5) ^ (p)[2]) & ((1UL << HBITS) - 1))

static long *head, *prev;		/* the newest place of each hash; the one before */

static void
insert(const ax_u8 *in, ax_u32 i)
{
	ax_u32 h = HASH(in + i);

	prev[i & (WIN - 1)] = head[h];
	head[h] = (long)i;
}

/* the longest earlier match for in[i...]: its length (0 below 3), *at */
static unsigned
longest(const ax_u8 *in, ax_u32 n, ax_u32 i, ax_u32 *at)
{
	ax_u32 lim = n - i < MAXLEN ? n - i : MAXLEN, len;
	long c = head[HASH(in + i)];
	unsigned best = 0;
	int k;

	for (k = 0; k < CHAIN && c >= 0 && i - (ax_u32)c <= WIN; k++) {
		if (in[(ax_u32)c + best] == in[i + best]) {
			for (len = 0; len < lim && in[(ax_u32)c + len] == in[i + len]; len++)
				;
			if (len > best) {
				best = len;
				*at = (ax_u32)c;
				if (len == lim)
					break;
			}
		}
		c = prev[(ax_u32)c & (WIN - 1)];
	}
	return best >= 3 ? best : 0;
}

ax_u8 *
kb_deflate(const ax_u8 *in, ax_u32 n, ax_u32 *outn)
{
	struct bw w;
	ax_u32 i = 0, k, at = 0, at2;
	unsigned len, len2;
	int bad;

	if (n == 0)
		return 0;
	head = (long *)malloc(sizeof(long) << HBITS);
	prev = (long *)malloc(sizeof(long) * WIN);
	if (!head || !prev) {
		free(head);
		free(prev);
		return 0;
	}
	w.cap = n;			/* not smaller than the input: no use */
	w.n = 0;
	w.acc = 0;
	w.nb = 0;
	if ((w.p = (ax_u8 *)malloc(w.cap)) == 0) {
		free(head);
		free(prev);
		return 0;
	}
	for (k = 0; k < (1UL << HBITS); k++)
		head[k] = -1;
	bad = put(&w, 1, 1) || put(&w, 1, 2);	/* BFINAL, BTYPE 01: fixed codes */
	while (!bad && i < n) {
		len = i + 3 <= n ? longest(in, n, i, &at) : 0;
		if (len && len < MAXLEN && i + 4 <= n) {	/* lazy: a longer one a byte on? */
			insert(in, i);
			len2 = longest(in, n, i + 1, &at2);
			if (len2 > len) {
				bad = lit(&w, in[i++]);
				len = len2;
				at = at2;
			} else {
				bad = match(&w, len, i - at);
				for (k = 1; k < len && i + k + 3 <= n; k++)
					insert(in, i + k);
				i += len;
				continue;
			}
		}
		if (bad)
			break;
		if (len) {
			bad = match(&w, len, i - at);
			for (k = 0; k < len && i + k + 3 <= n; k++)
				insert(in, i + k);
			i += len;
		} else {
			if (i + 3 <= n)
				insert(in, i);
			bad = lit(&w, in[i++]);
		}
	}
	bad = bad || lit(&w, 256) || (w.nb && put(&w, 0, 8 - w.nb));
	free(head);
	free(prev);
	if (bad) {
		free(w.p);
		return 0;
	}
	*outn = w.n;
	return w.p;
}
