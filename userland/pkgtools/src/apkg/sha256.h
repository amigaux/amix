/*
 * sha256.h -- SHA-256 (FIPS 180-4), C89, no allocation.  Not linked into
 * boot2 today: whether the loader checks SHA-256 as well as CRC-32 is
 * decided by its cost on a 25 MHz 68030 (M-LD7, docs/spec/10-boot-loader.md
 * §5.1); tools/axtime measures it.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef SHA256_H
#define SHA256_H

#include "axtypes.h"

struct ax_sha256 {
	ax_u32 h[8];
	ax_u32 lo, hi;		/* message length in bytes, 64 bits */
	ax_u32 n;		/* bytes waiting in buf */
	ax_u8 buf[64];
};

void ax_sha256_init(struct ax_sha256 *s);
void ax_sha256_update(struct ax_sha256 *s, const ax_u8 *p, ax_u32 len);
void ax_sha256_final(struct ax_sha256 *s, ax_u8 out[32]);
/* one-shot */
void ax_sha256(const ax_u8 *p, ax_u32 len, ax_u8 out[32]);

#endif
