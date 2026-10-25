/*
 * inflate.c -- raw deflate decoder (see inflate.h), written from RFC 1951.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "inflate.h"

/* the next n bits, least significant first; -1 (as a large value) at end */
static int
bits(struct ax_inflate *s, int n, ax_u32 *v)
{
	while (s->bitcnt < n) {
		if (s->inpos >= s->inlen)
			return AXI_EINPUT;
		s->bitbuf |= (ax_u32)s->in[s->inpos++] << s->bitcnt;
		s->bitcnt += 8;
	}
	*v = s->bitbuf & ((1UL << n) - 1);
	s->bitbuf >>= n;
	s->bitcnt -= n;
	return AXI_OK;
}

/* build canonical tables from n code lengths; 0 = complete or a permitted
 * incomplete single-code set, AXI_ECODES = over-subscribed */
static int
build(struct ax_huff *h, const ax_u8 *length, int n)
{
	ax_u16 offs[AXI_MAXBITS + 1];
	int sym, len, left;

	for (len = 0; len <= AXI_MAXBITS; len++)
		h->count[len] = 0;
	for (sym = 0; sym < n; sym++)
		h->count[length[sym]]++;
	if (h->count[0] == n)
		return AXI_OK;		/* no codes: only valid for unused distances */
	left = 1;
	for (len = 1; len <= AXI_MAXBITS; len++) {
		left <<= 1;
		left -= h->count[len];
		if (left < 0)
			return AXI_ECODES;
	}
	offs[1] = 0;
	for (len = 1; len < AXI_MAXBITS; len++)
		offs[len + 1] = offs[len] + h->count[len];
	for (sym = 0; sym < n; sym++)
		if (length[sym])
			h->symbol[offs[length[sym]]++] = (ax_u16)sym;
	return left;			/* > 0: incomplete */
}

/* decode one symbol, bit by bit (codes are stored most significant first) */
static int
decode(struct ax_inflate *s, const struct ax_huff *h, int *sym)
{
	int code = 0, first = 0, index = 0, len, count;
	ax_u32 b;

	for (len = 1; len <= AXI_MAXBITS; len++) {
		if (bits(s, 1, &b))
			return AXI_EINPUT;
		code |= (int)b;
		count = h->count[len];
		if (code - count < first) {
			*sym = h->symbol[index + (code - first)];
			return AXI_OK;
		}
		index += count;
		first += count;
		first <<= 1;
		code <<= 1;
	}
	return AXI_ESYMBOL;
}

static const ax_u16 lbase[29] = {
	3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
	35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
static const ax_u8 lext[29] = {
	0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
	3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
static const ax_u16 dbase[30] = {
	1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
	257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
	8193, 12289, 16385, 24577 };
static const ax_u8 dext[30] = {
	0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
	7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };

static int
codes(struct ax_inflate *s)
{
	int sym, rc;
	ax_u32 len, dist, x;

	for (;;) {
		if ((rc = decode(s, &s->lit, &sym)) != AXI_OK)
			return rc;
		if (sym < 256) {
			if (s->outpos >= s->outlen)
				return AXI_EOUTPUT;
			s->out[s->outpos++] = (ax_u8)sym;
		} else if (sym == 256) {
			return AXI_OK;
		} else {
			sym -= 257;
			if (sym >= 29)
				return AXI_ESYMBOL;
			if (bits(s, lext[sym], &x))
				return AXI_EINPUT;
			len = lbase[sym] + x;
			if ((rc = decode(s, &s->dist, &sym)) != AXI_OK)
				return rc;
			if (sym >= 30)
				return AXI_ESYMBOL;
			if (bits(s, dext[sym], &x))
				return AXI_EINPUT;
			dist = dbase[sym] + x;
			if (dist > s->outpos)
				return AXI_EDIST;
			if (len > s->outlen - s->outpos)
				return AXI_EOUTPUT;
			while (len--) {
				s->out[s->outpos] = s->out[s->outpos - dist];
				s->outpos++;
			}
		}
	}
}

static int
stored(struct ax_inflate *s)
{
	ax_u32 len;

	s->bitbuf = 0;			/* discard to a byte boundary */
	s->bitcnt = 0;
	if (s->inpos + 4 > s->inlen)
		return AXI_EINPUT;
	len = s->in[s->inpos] | ((ax_u32)s->in[s->inpos + 1] << 8);
	if ((s->in[s->inpos + 2] ^ 0xFF) != (len & 0xFF) ||
	    (s->in[s->inpos + 3] ^ 0xFF) != (len >> 8))
		return AXI_ESTORED;
	s->inpos += 4;
	if (len > s->inlen - s->inpos)
		return AXI_EINPUT;
	if (len > s->outlen - s->outpos)
		return AXI_EOUTPUT;
	while (len--)
		s->out[s->outpos++] = s->in[s->inpos++];
	return AXI_OK;
}

static int
fixed(struct ax_inflate *s)
{
	ax_u8 length[AXI_FIXLCODES];
	int sym;

	for (sym = 0; sym < 144; sym++)
		length[sym] = 8;
	for (; sym < 256; sym++)
		length[sym] = 9;
	for (; sym < 280; sym++)
		length[sym] = 7;
	for (; sym < 288; sym++)
		length[sym] = 8;
	/* all 288 lengths count: symbols 286 and 287 never occur, but leaving
	 * them out would shift every 9-bit code */
	build(&s->lit, length, AXI_FIXLCODES);
	for (sym = 0; sym < AXI_MAXDCODES; sym++)
		length[sym] = 5;
	build(&s->dist, length, AXI_MAXDCODES);
	return codes(s);
}

static int
dynamic(struct ax_inflate *s)
{
	static const ax_u8 order[19] = {
		16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
	ax_u8 length[AXI_MAXLCODES + AXI_MAXDCODES];
	ax_u32 nlen, ndist, ncode, x;
	int index, sym, rc;
	unsigned len;

	if (bits(s, 5, &nlen) || bits(s, 5, &ndist) || bits(s, 4, &ncode))
		return AXI_EINPUT;
	nlen += 257;
	ndist += 1;
	ncode += 4;
	if (nlen > AXI_MAXLCODES || ndist > AXI_MAXDCODES)
		return AXI_ECODES;
	for (index = 0; index < (int)ncode; index++) {
		if (bits(s, 3, &x))
			return AXI_EINPUT;
		length[order[index]] = (ax_u8)x;
	}
	for (; index < 19; index++)
		length[order[index]] = 0;
	if (build(&s->lit, length, 19) != 0)
		return AXI_ECODES;	/* the code-length code must be complete */

	for (index = 0; index < (int)(nlen + ndist);) {
		if ((rc = decode(s, &s->lit, &sym)) != AXI_OK)
			return rc;
		if (sym < 16) {
			length[index++] = (ax_u8)sym;
			continue;
		}
		len = 0;
		if (sym == 16) {
			if (index == 0)
				return AXI_ECODES;
			len = length[index - 1];
			if (bits(s, 2, &x))
				return AXI_EINPUT;
			x += 3;
		} else if (sym == 17) {
			if (bits(s, 3, &x))
				return AXI_EINPUT;
			x += 3;
		} else {
			if (bits(s, 7, &x))
				return AXI_EINPUT;
			x += 11;
		}
		if (index + (int)x > (int)(nlen + ndist))
			return AXI_ECODES;
		while (x--)
			length[index++] = (ax_u8)len;
	}
	if (length[256] == 0)
		return AXI_ECODES;	/* no end-of-block code */
	rc = build(&s->lit, length, (int)nlen);
	if (rc < 0 || (rc > 0 && nlen - s->lit.count[0] != 1))
		return AXI_ECODES;
	rc = build(&s->dist, length + nlen, (int)ndist);
	if (rc < 0 || (rc > 0 && ndist - s->dist.count[0] != 1))
		return AXI_ECODES;
	return codes(s);
}

int
ax_inflate(struct ax_inflate *s, ax_u8 *out, ax_u32 outlen, ax_u32 *outgot,
	   const ax_u8 *in, ax_u32 inlen)
{
	ax_u32 last, type;
	int rc;

	s->in = in;
	s->inlen = inlen;
	s->inpos = 0;
	s->bitbuf = 0;
	s->bitcnt = 0;
	s->out = out;
	s->outlen = outlen;
	s->outpos = 0;
	do {
		if (bits(s, 1, &last) || bits(s, 2, &type))
			return AXI_EINPUT;
		if (type == 0)
			rc = stored(s);
		else if (type == 1)
			rc = fixed(s);
		else if (type == 2)
			rc = dynamic(s);
		else
			rc = AXI_EBLOCK;
		if (rc != AXI_OK)
			return rc;
	} while (!last);
	*outgot = s->outpos;
	return AXI_OK;
}
