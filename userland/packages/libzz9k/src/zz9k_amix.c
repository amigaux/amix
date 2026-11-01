/*
 * zz9k_amix.c -- libzz9k's Amix side (zz9k/amix.h): the pool of boards, read once per
 * process, and zz9k_inflate, which runs on a board that offers the algorithm and in software
 * otherwise, with the same status, result and bytes either way.
 *
 * In AUTO only a board's OK is taken: any other answer of the board is decided again in
 * software and zlib's verdict returned, so there is one answer for every stream (a firmware
 * may judge a corrupt stream that would overfill the destination BAD_REQUEST where zlib says
 * NO_MEMORY).  A ZZ9K_INFLATE_BOARD call returns the board's own status.  A source shorter
 * than the threshold (ZZ9K_INFLATE_BOARD_MIN, zz9k_inflate_threshold) runs in software in
 * AUTO: below it the round trip costs more than the work.
 *
 * The software path is the firmware's one-shot DECOMPRESS of the zlib family done with this
 * system's zlib: inflate with Z_FINISH, the CRC-32 of the output, and the same status for
 * each outcome; and the checks the SDK's request and reply helpers make on the host side
 * (zz9k_request_decompress, zz9k_reply_decompress_result) come first and last, as on the
 * board path.
 *
 * Each board keeps two shared buffers, source and destination, mapped once and reused; one
 * grows (at least doubling) only when a call needs more.  zz9ksvc holds a mapped buffer that
 * is freed until the channel is closed, so when growing runs out of handles or quota the
 * channel is closed and opened again, which gives them all back.
 *
 * A board whose runtime did not answer in time is left out of ZZ9K_INFLATE_AUTO calls for
 * ZZ9K_DOWN_SECS, so a stalled board costs one bound, not one per call; a ZZ9K_INFLATE_BOARD
 * call still asks it, and an answer brings it back.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see LICENSE.
 */
#include <string.h>
#include <time.h>
#include <zlib.h>
#include "zz9k/host.h"
#include "zz9k/compression.h"
#include "zz9k/amix.h"

#define ZZ9K_BUF_MIN	(64UL * 1024)	/* the smallest shared buffer the pool takes */
#define ZZ9K_DOWN_SECS	30		/* how long AUTO calls leave a stalled board alone */

struct pool_board {
  ZZ9KAmixBoard info;
  ZZ9KContext *ctx;		/* 0 after a failure: opened again at the next use */
  ZZ9KSharedBuffer src, dst;	/* data 0: none yet */
  time_t down_until;		/* AUTO calls skip it until then */
};

static struct pool_board pool[ZZ9K_AMIX_NUNIT];
static ZZ9KAmixBoard pool_info[ZZ9K_AMIX_NUNIT];
static int pool_n = -1;		/* -1: not opened yet */
static uint32_t pool_ms;
static uint32_t inflate_min = ZZ9K_INFLATE_BOARD_MIN;

/* open pb's channel on unit and read its catalogue; 0 when the unit has no live board */
static int
board_open(struct pool_board *pb, int unit)
{
  ZZ9KCaps caps;
  ZZ9KServiceInfo svc;

  memset(pb, 0, sizeof(*pb));
  pb->info.unit = unit;
  if (zz9k_open_unit(&pb->ctx, unit) != ZZ9K_STATUS_OK) {
    pb->ctx = 0;
    return 0;
  }
  zz9k_set_offload_timeout_ms(pb->ctx, pool_ms);
  if (zz9k_query_caps(pb->ctx, &caps) != ZZ9K_STATUS_OK) {
    zz9k_close(pb->ctx);
    pb->ctx = 0;
    return 0;
  }
  pb->info.abi_major = caps.abi_major;
  pb->info.abi_minor = caps.abi_minor;
  pb->info.firmware_version = caps.firmware_version;
  pb->info.capability_bits = caps.capability_bits;
  if ((caps.capability_bits & ZZ9K_CAP_SERVICE_DISCOVERY) != 0U &&
      zz9k_query_service(pb->ctx, ZZ9K_SERVICE_CODEC, &svc) == ZZ9K_STATUS_OK) {
    pb->info.codec_flags = svc.flags;
  }
  return 1;
}

/* close pb's channel: its mappings first, so the kernel frees its buffers */
static void
board_drop(struct pool_board *pb)
{
  if (pb->ctx) {
    zz9k_close(pb->ctx);
  }
  pb->ctx = 0;
  memset(&pb->src, 0, sizeof(pb->src));
  memset(&pb->dst, 0, sizeof(pb->dst));
}

/* pb's channel, opened again if a failure closed it; 0 when it cannot be */
static ZZ9KContext *
board_ctx(struct pool_board *pb)
{
  if (!pb->ctx && zz9k_open_unit(&pb->ctx, pb->info.unit) == ZZ9K_STATUS_OK) {
    zz9k_set_offload_timeout_ms(pb->ctx, pool_ms);
  }
  return pb->ctx;		/* zz9k_open_unit leaves it 0 on failure */
}

static void
pool_open(void)
{
  int u;

  if (pool_n >= 0) {
    return;
  }
  pool_n = 0;
  for (u = 0; u < ZZ9K_AMIX_NUNIT; u++) {
    if (board_open(&pool[pool_n], u)) {
      pool_info[pool_n] = pool[pool_n].info;
      pool_n++;
    }
  }
}

int
zz9k_pool(const ZZ9KAmixBoard **boards)
{
  pool_open();
  if (boards) {
    *boards = pool_info;
  }
  return pool_n;
}

/* the first board whose CODEC service has every flag; with skip_down, not a stalled one */
static struct pool_board *
pool_find(uint32_t flags, int skip_down)
{
  int k;

  pool_open();
  if (flags == 0U) {
    return 0;
  }
  for (k = 0; k < pool_n; k++) {
    if ((pool[k].info.codec_flags & flags) == flags &&
        !(skip_down && pool[k].down_until != 0 && time(0) < pool[k].down_until)) {
      return &pool[k];
    }
  }
  return 0;
}

int
zz9k_pool_codec(uint32_t flags)
{
  struct pool_board *pb = pool_find(flags, 0);

  return pb ? pb->info.unit : -1;
}

void
zz9k_pool_timeout(uint32_t ms)
{
  int k;

  pool_ms = ms;
  for (k = 0; pool_n > 0 && k < pool_n; k++) {
    if (pool[k].ctx) {
      zz9k_set_offload_timeout_ms(pool[k].ctx, ms);
    }
  }
}

void
zz9k_inflate_threshold(uint32_t bytes)
{
  inflate_min = bytes;
}

void
zz9k_pool_close(void)
{
  int k;

  for (k = 0; pool_n > 0 && k < pool_n; k++) {
    board_drop(&pool[k]);
  }
  pool_n = -1;
}

/* the CODEC service flag an algorithm needs, 0 for none */
static uint32_t
codec_flag(uint32_t algorithm)
{
  switch (algorithm) {
  case ZZ9K_COMPRESSION_DEFLATE_RAW: return ZZ9K_SERVICE_FLAG_CODEC_DEFLATE_RAW;
  case ZZ9K_COMPRESSION_ZLIB: return ZZ9K_SERVICE_FLAG_CODEC_ZLIB;
  case ZZ9K_COMPRESSION_GZIP: return ZZ9K_SERVICE_FLAG_CODEC_GZIP;
  case ZZ9K_COMPRESSION_LZ4_BLOCK: return ZZ9K_SERVICE_FLAG_CODEC_LZ4_BLOCK;
  case ZZ9K_COMPRESSION_LZMA_ALONE: return ZZ9K_SERVICE_FLAG_CODEC_LZMA_ALONE;
  case ZZ9K_COMPRESSION_LZMA2: return ZZ9K_SERVICE_FLAG_CODEC_LZMA2;
  case ZZ9K_COMPRESSION_LH1:
  case ZZ9K_COMPRESSION_LH5:
  case ZZ9K_COMPRESSION_LH6:
  case ZZ9K_COMPRESSION_LH7: return ZZ9K_SERVICE_FLAG_CODEC_LZH;
  default: return 0U;
  }
}

/* zlib's window bits for an algorithm of the zlib family, 0 for the others */
static int
window_bits(uint32_t algorithm)
{
  switch (algorithm) {
  case ZZ9K_COMPRESSION_DEFLATE_RAW: return -MAX_WBITS;
  case ZZ9K_COMPRESSION_ZLIB: return MAX_WBITS;
  case ZZ9K_COMPRESSION_GZIP: return MAX_WBITS + 16;
  default: return 0;
  }
}

/* b holds at least need bytes, keeping it when it does; the allocation's status */
static int
buf_need(ZZ9KContext *ctx, ZZ9KSharedBuffer *b, uint32_t need)
{
  uint32_t size;
  int status;

  if (b->data && b->length >= need) {
    return ZZ9K_STATUS_OK;
  }
  size = b->data ? b->length * 2U : (uint32_t)ZZ9K_BUF_MIN;
  if (size < need) {
    size = need;
  }
  if (b->data) {
    (void)zz9k_free_shared(ctx, b->handle);
    memset(b, 0, sizeof(*b));
  }
  status = zz9k_alloc_shared(ctx, size, 0, 0, b);
  if (status == ZZ9K_STATUS_NO_MEMORY && size != need) {
    /* the grown size did not fit: exactly what is needed */
    status = zz9k_alloc_shared(ctx, need, 0, 0, b);
  }
  if (status != ZZ9K_STATUS_OK) {
    memset(b, 0, sizeof(*b));
  }
  return status;
}

/* both buffers; when the handles or the quota are spent on held buffers, a fresh channel */
static int
board_buffers(struct pool_board *pb, uint32_t slen, uint32_t dcap)
{
  int round;
  int status = ZZ9K_STATUS_NOT_FOUND;

  for (round = 0; round < 2; round++) {
    if (!board_ctx(pb)) {
      return ZZ9K_STATUS_NOT_FOUND;
    }
    status = buf_need(pb->ctx, &pb->src, slen);
    if (status == ZZ9K_STATUS_OK) {
      status = buf_need(pb->ctx, &pb->dst, dcap);
    }
    if (status == ZZ9K_STATUS_OK) {
      return status;
    }
    board_drop(pb);
    if (status != ZZ9K_STATUS_NO_MEMORY) {
      return status;		/* only handles or quota come back with a fresh channel */
    }
  }
  return status;
}

/*
 * DECOMPRESS on pb: the board's status, or the reason it did not get there (no channel, no
 * buffers, the kernel refused or timed out).  On OK the output is copied to dst.
 */
static int
board_inflate(struct pool_board *pb, uint32_t algorithm, uint32_t flags, const void *src,
              uint32_t src_length, void *dst, uint32_t dst_capacity,
              ZZ9KDecompressResult *result)
{
  ZZ9KDecompressDesc desc;
  int status;

  status = board_buffers(pb, src_length, dst_capacity);
  if (status != ZZ9K_STATUS_OK) {
    if (status == ZZ9K_STATUS_TIMEOUT || status == ZZ9K_STATUS_IO_ERROR) {
      pb->down_until = time(0) + ZZ9K_DOWN_SECS;
    }
    return status;
  }
  memcpy((void *)pb->src.data, src, src_length);
  memset(&desc, 0, sizeof(desc));
  desc.src_handle = pb->src.handle;
  desc.src_length = src_length;
  desc.dst_handle = pb->dst.handle;
  desc.dst_capacity = dst_capacity;
  desc.algorithm = algorithm;
  desc.flags = flags;
  status = zz9k_decompress(pb->ctx, &desc, result);
  switch (status) {
  case ZZ9K_STATUS_OK:
    if (result->bytes_written > dst_capacity) {
      memset(result, 0, sizeof(*result));
      board_drop(pb);
      return ZZ9K_STATUS_INTERNAL_ERROR;
    }
    memcpy(dst, (const void *)pb->dst.data, result->bytes_written);
    pb->down_until = 0;
    return status;
  case ZZ9K_STATUS_NO_MEMORY:	/* no room in dst: the firmware's answer */
  case ZZ9K_STATUS_BAD_REQUEST:	/* a stream it could not decode */
    pb->down_until = 0;
    return status;
  case ZZ9K_STATUS_TIMEOUT:	/* the kernel quarantined the buffers */
  case ZZ9K_STATUS_IO_ERROR:	/* the runtime was reset under them */
    pb->down_until = time(0) + ZZ9K_DOWN_SECS;
    board_drop(pb);
    return status;
  case ZZ9K_STATUS_BAD_HANDLE:
  case ZZ9K_STATUS_NOT_FOUND:
    board_drop(pb);
    return status;
  default:
    return status;
  }
}

/*
 * The firmware's one-shot DECOMPRESS of the zlib family, with the host-side checks of the
 * SDK's reply helper after it.
 */
static int
soft_inflate(uint32_t algorithm, uint32_t flags, const void *src, uint32_t src_length,
             void *dst, uint32_t dst_capacity, ZZ9KDecompressResult *result)
{
  z_stream z;
  int rc;
  int status;
  int wb = window_bits(algorithm);
  uint32_t consumed, written, crc, rflags;

  if (wb == 0) {
    return ZZ9K_STATUS_UNSUPPORTED;
  }
  memset(&z, 0, sizeof(z));
  z.next_in = (Bytef *)src;
  z.avail_in = (uInt)src_length;
  z.next_out = (Bytef *)dst;
  z.avail_out = (uInt)dst_capacity;
  if (inflateInit2(&z, wb) != Z_OK) {
    return ZZ9K_STATUS_INTERNAL_ERROR;
  }
  rc = inflate(&z, Z_FINISH);
  consumed = (uint32_t)z.total_in;
  written = (uint32_t)z.total_out;
  crc = (uint32_t)crc32(crc32(0L, Z_NULL, 0), (const Bytef *)dst, (uInt)written);
  rflags = ZZ9K_DECOMPRESS_RESULT_CHECKSUM_VALID;
  if (rc == Z_STREAM_END) {
    rflags |= ZZ9K_DECOMPRESS_RESULT_STREAM_END;
  }
  if (rc == Z_STREAM_END) {
    status = ZZ9K_STATUS_OK;
  } else if (z.avail_out == 0U) {
    status = ZZ9K_STATUS_NO_MEMORY;
  } else if ((flags & ZZ9K_DECOMPRESS_FLAG_EXPECT_END) != 0U) {
    status = ZZ9K_STATUS_BAD_REQUEST;
  } else if (rc == Z_OK) {
    status = ZZ9K_STATUS_OK;
  } else {
    status = ZZ9K_STATUS_BAD_REQUEST;
  }
  inflateEnd(&z);
  if (status != ZZ9K_STATUS_OK) {
    return status;		/* the host sees the status only */
  }
  if (consumed == 0U || written == 0U) {
    return ZZ9K_STATUS_INTERNAL_ERROR;	/* as zz9k_reply_decompress_result */
  }
  result->bytes_consumed = consumed;
  result->bytes_written = written;
  result->checksum = crc;
  result->algorithm = algorithm;
  result->flags = rflags;
  return ZZ9K_STATUS_OK;
}

int
zz9k_inflate(uint32_t algorithm, uint32_t flags, const void *src, uint32_t src_length,
             void *dst, uint32_t dst_capacity, int how, ZZ9KDecompressResult *result,
             int *ran)
{
  struct pool_board *pb;
  int status;
  int soft = window_bits(algorithm) != 0;

  if (ran) {
    *ran = 0;
  }
  if (!result) {
    return ZZ9K_STATUS_BAD_REQUEST;
  }
  memset(result, 0, sizeof(*result));
  /* zz9k_request_decompress's checks, the same for both paths */
  if (!src || !dst || src_length == 0U || dst_capacity == 0U ||
      !zz9k_compression_algorithm_known(algorithm) ||
      (flags & ~(uint32_t)ZZ9K_DECOMPRESS_FLAG_EXPECT_END) != 0U ||
      (how != ZZ9K_INFLATE_AUTO && how != ZZ9K_INFLATE_BOARD && how != ZZ9K_INFLATE_SOFT)) {
    return ZZ9K_STATUS_BAD_REQUEST;
  }
  /* the board: when asked to, or in AUTO for a source over the threshold (or one only a
     board can do) */
  if (how == ZZ9K_INFLATE_BOARD ||
      (how == ZZ9K_INFLATE_AUTO && (!soft || src_length >= inflate_min))) {
    pb = pool_find(codec_flag(algorithm), how == ZZ9K_INFLATE_AUTO);
    if (pb) {
      status = board_inflate(pb, algorithm, flags, src, src_length, dst, dst_capacity,
                             result);
      if (status == ZZ9K_STATUS_OK || how == ZZ9K_INFLATE_BOARD || !soft) {
        if (status != ZZ9K_STATUS_OK) {
          memset(result, 0, sizeof(*result));
        }
        if (ran) {
          *ran = ZZ9K_INFLATE_BOARD;
        }
        return status;
      }
      /* anything but OK: zlib decides */
      memset(result, 0, sizeof(*result));
    } else if (how == ZZ9K_INFLATE_BOARD || !soft) {
      return pool_n == 0 ? ZZ9K_STATUS_NOT_FOUND : ZZ9K_STATUS_UNSUPPORTED;
    }
  }
  if (!soft) {
    return ZZ9K_STATUS_UNSUPPORTED;
  }
  status = soft_inflate(algorithm, flags, src, src_length, dst, dst_capacity, result);
  if (ran) {
    *ran = ZZ9K_INFLATE_SOFT;
  }
  return status;
}
