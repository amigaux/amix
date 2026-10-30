/*
 * This code implements the MD5 message-digest algorithm.
 * The algorithm is due to Ron Rivest.  This code was
 * written by Colin Plumb in 1993, no copyright is claimed.
 * This code is in the public domain; do with it what you wish.
 *
 * Equivalent code is available from RSA Data Security, Inc.
 * This code has been tested against that, and is equivalent,
 * except that you don't need to include two pages of legalese
 * with every copy.
 *
 * Vendored for apkg (Amix remote package client).  The only local
 * changes: uint32 typedef'd to unsigned int (32 bits on both the
 * m68k/SVR4 target and modern hosts), ANSI prototypes kept, and
 * byte order selected with -DHIGHFIRST from the Makefile for
 * big-endian (m68k) builds.
 */

#ifndef MD5_H
#define MD5_H

typedef unsigned int uint32;

struct MD5Context {
    uint32 buf[4];
    uint32 bits[2];
    unsigned char in[64];
};

void MD5Init(struct MD5Context *context);
void MD5Update(struct MD5Context *context, unsigned char const *buf,
               unsigned len);
void MD5Final(unsigned char digest[16], struct MD5Context *context);
void MD5Transform(uint32 buf[4], uint32 const in[16]);

typedef struct MD5Context MD5_CTX;

#endif /* MD5_H */
