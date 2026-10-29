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

/* the lookup table: each code of at most AXI_FAST bits, bit-reversed (the
 * stream sends codes most significant bit first into an LSB-first bit
 * buffer), in every slot whose low bits it matches */
static void
fill(struct ax_huff *h)
{
	unsigned code = 0, rev, i, b;
	int len, k, index = 0;

	for (i = 0; i < (1U << AXI_FAST); i++)
		h->fast[i] = 0;
	for (len = 1; len <= AXI_FAST; len++, code <<= 1)
		for (k = 0; k < h->count[len]; k++, code++, index++) {
			for (rev = 0, b = 0; b < (unsigned)len; b++)
				rev |= ((code >> b) & 1) << (len - 1 - b);
			for (i = rev; i < (1U << AXI_FAST); i += 1U << len)
				h->fast[i] = (ax_u16)((len << 9) | h->symbol[index]);
		}
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
	fill(h);
	return left;			/* > 0: incomplete */
}

/* decode one symbol, bit by bit (codes are stored most significant first);
 * returns the symbol, or a negative AXI_E code */
static int
slow(struct ax_inflate *s, const struct ax_huff *h)
{
	int code = 0, first = 0, index = 0, len, count;
	ax_u32 b;

	for (len = 1; len <= AXI_MAXBITS; len++) {
		if (bits(s, 1, &b))
			return AXI_EINPUT;
		code |= (int)b;
		count = h->count[len];
		if (code - count < first)
			return h->symbol[index + (code - first)];
		index += count;
		first += count;
		first <<= 1;
		code <<= 1;
	}
	return AXI_ESYMBOL;
}

/* decode one symbol: one lookup for a short code, else bit by bit */
static int
decode(struct ax_inflate *s, const struct ax_huff *h, int *sym)
{
	unsigned e;

	while (s->bitcnt < AXI_FAST && s->inpos < s->inlen) {
		s->bitbuf |= (ax_u32)s->in[s->inpos++] << s->bitcnt;
		s->bitcnt += 8;
	}
	e = h->fast[s->bitbuf & ((1U << AXI_FAST) - 1)];
	if (e && (int)(e >> 9) <= s->bitcnt) {
		s->bitbuf >>= e >> 9;
		s->bitcnt -= (int)(e >> 9);
		*sym = (int)(e & 511);
		return AXI_OK;
	}
	*sym = slow(s, h);
	return *sym < 0 ? *sym : AXI_OK;
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

/*
 * The literal/length and distance codes of one block.  The hot loop keeps
 * the bit buffer and both positions in locals (registers), and writes
 * them back only around the bit-by-bit path for a long code and on exit.
 */
#define LOAD()	(bb = s->bitbuf, bc = s->bitcnt, inpos = s->inpos, outpos = s->outpos)
#define SAVE()	(s->bitbuf = bb, s->bitcnt = bc, s->inpos = inpos, s->outpos = outpos)
#define NEED(n)	while (bc < (n) && inpos < inlen) { \
			bb |= (ax_u32)in[inpos++] << bc; \
			bc += 8; \
		}

static int
codes(struct ax_inflate *s)
{
	const ax_u8 *in = s->in;
	ax_u8 *out = s->out, *o, *from;
	ax_u32 inlen = s->inlen, outlen = s->outlen, inpos, outpos, bb, len, dist;
	int bc, sym, n;
	unsigned e;

	LOAD();
	for (;;) {
		NEED(AXI_FAST);
		e = s->lit.fast[bb & ((1U << AXI_FAST) - 1)];
		if (e && (int)(e >> 9) <= bc) {
			bb >>= e >> 9;
			bc -= (int)(e >> 9);
			sym = (int)(e & 511);
		} else {
			SAVE();
			sym = slow(s, &s->lit);
			LOAD();
			if (sym < 0)
				return sym;
		}
		if (sym < 256) {
			if (outpos >= outlen) {
				SAVE();
				return AXI_EOUTPUT;
			}
			out[outpos++] = (ax_u8)sym;
			continue;
		}
		if (sym == 256) {
			SAVE();
			return AXI_OK;
		}
		sym -= 257;
		if (sym >= 29) {
			SAVE();
			return AXI_ESYMBOL;
		}
		n = lext[sym];
		NEED(n);
		if (bc < n) {
			SAVE();
			return AXI_EINPUT;
		}
		len = lbase[sym] + (bb & ((1UL << n) - 1));
		bb >>= n;
		bc -= n;
		NEED(AXI_FAST);
		e = s->dist.fast[bb & ((1U << AXI_FAST) - 1)];
		if (e && (int)(e >> 9) <= bc) {
			bb >>= e >> 9;
			bc -= (int)(e >> 9);
			sym = (int)(e & 511);
		} else {
			SAVE();
			sym = slow(s, &s->dist);
			LOAD();
			if (sym < 0)
				return sym;
		}
		if (sym >= 30) {
			SAVE();
			return AXI_ESYMBOL;
		}
		n = dext[sym];
		NEED(n);
		if (bc < n) {
			SAVE();
			return AXI_EINPUT;
		}
		dist = dbase[sym] + (bb & ((1UL << n) - 1));
		bb >>= n;
		bc -= n;
		if (dist > outpos || len > outlen - outpos) {
			SAVE();
			return dist > outpos ? AXI_EDIST : AXI_EOUTPUT;
		}
		o = out + outpos;
		from = o - dist;
		outpos += len;
		while (len--)
			*o++ = *from++;
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
