/*
 * inflate.h -- a raw deflate (RFC 1951) decoder for the loader.
 *
 * The whole output is decoded into one caller buffer, so back-references
 * are read from the output itself and no sliding window is kept.  No
 * allocation and no writable static data; the decoder state (about 3.3 KB)
 * lives in a caller-provided struct.  Written from RFC 1951.
 *
 * Codes of up to AXI_FAST bits are decoded with one table lookup; longer
 * (rare) codes bit by bit.  The bit-at-a-time decoder alone ran at 45-53
 * KiB/s on a 25 MHz 68030 (M-LD8, 2026-10-26).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef INFLATE_H
#define INFLATE_H

#include "axtypes.h"

#define AXI_MAXBITS	15
#define AXI_MAXLCODES	286	/* in a dynamic block */
#define AXI_FIXLCODES	288	/* the fixed code has 288, two never used */
#define AXI_MAXDCODES	30
#define AXI_FAST	9	/* bits decoded by one table lookup */

struct ax_huff {
	ax_u16 count[AXI_MAXBITS + 1];	/* codes of each length */
	ax_u16 symbol[AXI_FIXLCODES];	/* symbols in canonical order */
	/* indexed by the next AXI_FAST input bits: (code length << 9) |
	 * symbol for a code of at most AXI_FAST bits, else 0 */
	ax_u16 fast[1 << AXI_FAST];
};

struct ax_inflate {
	const ax_u8 *in;
	ax_u32 inlen, inpos;
	ax_u32 bitbuf;
	int bitcnt;
	ax_u8 *out;
	ax_u32 outlen, outpos;
	struct ax_huff lit, dist;
};

#define AXI_OK		0
#define AXI_EINPUT	(-1)	/* ran out of input */
#define AXI_EOUTPUT	(-2)	/* output would exceed the buffer */
#define AXI_EBLOCK	(-3)	/* reserved block type */
#define AXI_ESTORED	(-4)	/* stored block length check failed */
#define AXI_ECODES	(-5)	/* bad code lengths */
#define AXI_EDIST	(-6)	/* distance beyond the start of the output */
#define AXI_ESYMBOL	(-7)	/* invalid symbol */

/* decode in[0..inlen) into out[0..outlen); *outgot = bytes produced */
int ax_inflate(struct ax_inflate *s, ax_u8 *out, ax_u32 outlen, ax_u32 *outgot,
	       const ax_u8 *in, ax_u32 inlen);

#endif
