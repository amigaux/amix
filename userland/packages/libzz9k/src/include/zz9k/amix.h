/*
 * zz9k/amix.h -- libzz9k's Amix side: a unit's channel, the pool of boards, and calls that
 * give the same result with or without a board.
 *
 * On Amix a ZZ9000-family board's services are reached through the kernel module zz9ksvc,
 * /dev/zz9ksvc0 and /dev/zz9ksvc1 (zz9ksvc(7)).  The SDK's host API (zz9k/host.h) works
 * there on one unit's channel: zz9k_open takes the first unit that answers, zz9k_open_unit
 * a given one.  The pool below opens every unit once per process, reads each board's
 * capability catalogue, and is what the fallback calls use.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see LICENSE.
 */
#ifndef ZZ9K_AMIX_H
#define ZZ9K_AMIX_H

#include "zz9k/host.h"

#define ZZ9K_AMIX_NUNIT	2	/* /dev/zz9ksvc0 and 1 */

/* the channel of one unit: ZZ9K_STATUS_NOT_FOUND when it has no board with a runtime */
int zz9k_open_unit(ZZ9KContext **ctx, int unit);
/* the unit of a context opened on Amix */
int zz9k_unit(const ZZ9KContext *ctx);

/* one board of the pool, as its catalogue answered */
typedef struct ZZ9KAmixBoard {
  int unit;
  uint16_t abi_major, abi_minor;
  uint32_t firmware_version;
  uint32_t capability_bits;	/* QUERY_CAPS */
  uint32_t codec_flags;		/* the CODEC service's ZZ9K_SERVICE_FLAG_CODEC_*; 0: none */
} ZZ9KAmixBoard;

/* the boards of the pool (opened at the first call); returns how many, 0 when none */
int zz9k_pool(const ZZ9KAmixBoard **boards);
/* the unit of the first board whose CODEC service has every flag in flags, or -1 */
int zz9k_pool_codec(uint32_t flags);
/* the bound of each board request, in ms (0: the kernel's own, 10 s) */
void zz9k_pool_timeout(uint32_t ms);
/* close every channel; the next call opens the pool again */
void zz9k_pool_close(void);

/* how zz9k_inflate may run */
#define ZZ9K_INFLATE_AUTO	0	/* a board that offers it, else software; see below */
#define ZZ9K_INFLATE_BOARD	1	/* a board only */
#define ZZ9K_INFLATE_SOFT	2	/* software only */

/* AUTO runs a source shorter than this many bytes in software (the board's round trip
   costs more); zz9k_inflate_threshold sets it for the process */
#define ZZ9K_INFLATE_BOARD_MIN	1024
void zz9k_inflate_threshold(uint32_t bytes);

/*
 * Decompress src_length bytes at src into at most dst_capacity bytes at dst, as the SDK's
 * DECOMPRESS does: ZZ9K_COMPRESSION_DEFLATE_RAW, _ZLIB or _GZIP, flags 0 or
 * ZZ9K_DECOMPRESS_FLAG_EXPECT_END.  The status and, on ZZ9K_STATUS_OK, the result (bytes
 * consumed and written, the CRC-32 of the output, the algorithm, the result flags) and the
 * bytes at dst are the same on a board and in software: in AUTO only a board's OK is taken,
 * any other answer is decided again in software.  ZZ9K_INFLATE_BOARD returns the board's own
 * status.  Other algorithms run on a board only.  *ran (may be 0) says where it ran:
 * ZZ9K_INFLATE_BOARD or ZZ9K_INFLATE_SOFT.
 * With ZZ9K_INFLATE_BOARD and no board offering it: ZZ9K_STATUS_NOT_FOUND when there is
 * no board, ZZ9K_STATUS_UNSUPPORTED when none has the service.
 */
int zz9k_inflate(uint32_t algorithm, uint32_t flags, const void *src, uint32_t src_length,
                 void *dst, uint32_t dst_capacity, int how, ZZ9KDecompressResult *result,
                 int *ran);

#endif
