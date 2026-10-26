/*
 * sha256.c -- SHA-256 (FIPS 180-4) for a 32-bit big-endian CPU with few
 * registers: the whole 64-word schedule first, then eight rounds per pass
 * with the working variables renamed rather than shifted.  On the 68030
 * the shifting form ran at half speed under GCC 14, which spilled the
 * shifted variables (docs/measurements/2026-10-26-hashbench.md).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sha256.h"

static const ax_u32 k[64] = {
	0x428a2f98UL, 0x71374491UL, 0xb5c0fbcfUL, 0xe9b5dba5UL, 0x3956c25bUL, 0x59f111f1UL,
	0x923f82a4UL, 0xab1c5ed5UL, 0xd807aa98UL, 0x12835b01UL, 0x243185beUL, 0x550c7dc3UL,
	0x72be5d74UL, 0x80deb1feUL, 0x9bdc06a7UL, 0xc19bf174UL, 0xe49b69c1UL, 0xefbe4786UL,
	0x0fc19dc6UL, 0x240ca1ccUL, 0x2de92c6fUL, 0x4a7484aaUL, 0x5cb0a9dcUL, 0x76f988daUL,
	0x983e5152UL, 0xa831c66dUL, 0xb00327c8UL, 0xbf597fc7UL, 0xc6e00bf3UL, 0xd5a79147UL,
	0x06ca6351UL, 0x14292967UL, 0x27b70a85UL, 0x2e1b2138UL, 0x4d2c6dfcUL, 0x53380d13UL,
	0x650a7354UL, 0x766a0abbUL, 0x81c2c92eUL, 0x92722c85UL, 0xa2bfe8a1UL, 0xa81a664bUL,
	0xc24b8b70UL, 0xc76c51a3UL, 0xd192e819UL, 0xd6990624UL, 0xf40e3585UL, 0x106aa070UL,
	0x19a4c116UL, 0x1e376c08UL, 0x2748774cUL, 0x34b0bcb5UL, 0x391c0cb3UL, 0x4ed8aa4aUL,
	0x5b9cca4fUL, 0x682e6ff3UL, 0x748f82eeUL, 0x78a5636fUL, 0x84c87814UL, 0x8cc70208UL,
	0x90befffaUL, 0xa4506cebUL, 0xbef9a3f7UL, 0xc67178f2UL
};

#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define S0(x) (ROR(x, 2) ^ ROR(x, 13) ^ ROR(x, 22))
#define S1(x) (ROR(x, 6) ^ ROR(x, 11) ^ ROR(x, 25))
#define CH(x, y, z) ((z) ^ ((x) & ((y) ^ (z))))
#define MAJ(x, y, z) (((x) & (y)) | ((z) & ((x) | (y))))

/* one round with the eight working variables named, not shifted: eight
 * rounds per pass rename them back, so nothing moves between rounds */
#define ROUND(a, b, c, d, e, f, g, h, j) \
	t = h + S1(e) + CH(e, f, g) + kp[j] + wp[j]; \
	d += t; \
	h = t + S0(a) + MAJ(a, b, c)

static void
block(ax_u32 h[8], const ax_u8 *p)
{
	ax_u32 w[64], a, b, c, d, e, f, g, hh, t, s0, s1;
	const ax_u32 *kp;
	ax_u32 *wp;
	int i;

	for (i = 0; i < 16; i++)
		w[i] = AX_GET32(p + 4 * i);
	for (i = 16; i < 64; i++) {	/* the whole schedule first */
		s0 = w[i - 15];
		s1 = w[i - 2];
		w[i] = w[i - 16] + w[i - 7] + (ROR(s0, 7) ^ ROR(s0, 18) ^ (s0 >> 3)) +
		    (ROR(s1, 17) ^ ROR(s1, 19) ^ (s1 >> 10));
	}
	a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
	for (kp = k, wp = w; wp < w + 64; kp += 8, wp += 8) {
		ROUND(a, b, c, d, e, f, g, hh, 0);
		ROUND(hh, a, b, c, d, e, f, g, 1);
		ROUND(g, hh, a, b, c, d, e, f, 2);
		ROUND(f, g, hh, a, b, c, d, e, 3);
		ROUND(e, f, g, hh, a, b, c, d, 4);
		ROUND(d, e, f, g, hh, a, b, c, 5);
		ROUND(c, d, e, f, g, hh, a, b, 6);
		ROUND(b, c, d, e, f, g, hh, a, 7);
	}
	h[0] += a, h[1] += b, h[2] += c, h[3] += d, h[4] += e, h[5] += f, h[6] += g, h[7] += hh;
}

void
ax_sha256_init(struct ax_sha256 *s)
{
	s->h[0] = 0x6a09e667UL, s->h[1] = 0xbb67ae85UL, s->h[2] = 0x3c6ef372UL;
	s->h[3] = 0xa54ff53aUL, s->h[4] = 0x510e527fUL, s->h[5] = 0x9b05688cUL;
	s->h[6] = 0x1f83d9abUL, s->h[7] = 0x5be0cd19UL;
	s->lo = s->hi = s->n = 0;
}

void
ax_sha256_update(struct ax_sha256 *s, const ax_u8 *p, ax_u32 len)
{
	if ((s->lo += len) < len)
		s->hi++;
	if (s->n) {
		while (len && s->n < 64)
			s->buf[s->n++] = *p++, len--;
		if (s->n < 64)
			return;
		block(s->h, s->buf);
		s->n = 0;
	}
	for (; len >= 64; p += 64, len -= 64)
		block(s->h, p);
	while (len--)
		s->buf[s->n++] = *p++;
}

void
ax_sha256_final(struct ax_sha256 *s, ax_u8 out[32])
{
	ax_u32 hi = (s->hi << 3) | (s->lo >> 29), lo = s->lo << 3;
	int i;

	s->buf[s->n++] = 0x80;
	if (s->n > 56) {
		while (s->n < 64)
			s->buf[s->n++] = 0;
		block(s->h, s->buf);
		s->n = 0;
	}
	while (s->n < 56)
		s->buf[s->n++] = 0;
	AX_PUT32(s->buf + 56, hi);
	AX_PUT32(s->buf + 60, lo);
	block(s->h, s->buf);
	for (i = 0; i < 8; i++)
		AX_PUT32(out + 4 * i, s->h[i]);
}

void
ax_sha256(const ax_u8 *p, ax_u32 len, ax_u8 out[32])
{
	struct ax_sha256 s;

	ax_sha256_init(&s);
	ax_sha256_update(&s, p, len);
	ax_sha256_final(&s, out);
}
