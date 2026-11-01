/*
 * zz9k-test.c -- libzz9k's acceptance program (zz9k-test(1)): the pool of boards as their
 * catalogues answered, then an inflate of a raw deflate, a zlib and a gzip stream in
 * software and, where a board offers it, on the board, checked against the original and
 * against each other.  Exit status 0 when every check holds, 1 otherwise.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include "zz9k/host.h"
#include "zz9k/amix.h"

#define N	(96UL * 1024)	/* bytes of test data */

static const struct {
  const char *name;
  uint32_t alg;
  int wbits;
  uint32_t flag;	/* the CODEC service flag */
} algs[] = {
  { "raw", ZZ9K_COMPRESSION_DEFLATE_RAW, -MAX_WBITS, ZZ9K_SERVICE_FLAG_CODEC_DEFLATE_RAW },
  { "zlib", ZZ9K_COMPRESSION_ZLIB, MAX_WBITS, ZZ9K_SERVICE_FLAG_CODEC_ZLIB },
  { "gzip", ZZ9K_COMPRESSION_GZIP, MAX_WBITS + 16, ZZ9K_SERVICE_FLAG_CODEC_GZIP },
};

/* alg's stream of n bytes at in into out; its length, 0 when it failed */
static unsigned long
pack(int wbits, const unsigned char *in, unsigned long n, unsigned char *out, unsigned long cap)
{
  z_stream z;
  unsigned long len;

  memset(&z, 0, sizeof(z));
  if (deflateInit2(&z, 6, Z_DEFLATED, wbits, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
    return 0;
  }
  z.next_in = (Bytef *)in;
  z.avail_in = (uInt)n;
  z.next_out = out;
  z.avail_out = (uInt)cap;
  len = deflate(&z, Z_FINISH) == Z_STREAM_END ? z.total_out : 0;
  deflateEnd(&z);
  return len;
}

int
main(int argc, char **argv)
{
  const ZZ9KAmixBoard *b;
  ZZ9KDecompressResult rs, rb;
  unsigned char *orig, *comp, *out;
  unsigned long i, clen;
  int nb, k, st, ran, bad = 0;

  (void)argc;
  (void)argv;
  printf("libzz9k %s, ZZ9000 SDK host API v%d\n", LIBZZ9K_VERSION, ZZ9K_ABI_VERSION_MAJOR);
  nb = zz9k_pool(&b);
  if (nb == 0) {
    printf("boards: none (no /dev/zz9ksvcN answers): software only\n");
  }
  for (k = 0; k < nb; k++) {
    printf("board: unit %d, ABI %u.%u, firmware %08lx, caps %08lx, codec %08lx\n",
           b[k].unit, b[k].abi_major, b[k].abi_minor,
           (unsigned long)b[k].firmware_version, (unsigned long)b[k].capability_bits,
           (unsigned long)b[k].codec_flags);
  }
  orig = malloc(N);
  comp = malloc(N + N / 8 + 64);
  out = malloc(N);
  if (!orig || !comp || !out) {
    printf("FAIL: no memory\n");
    return 1;
  }
  for (i = 0; i < N; i++) {
    orig[i] = (unsigned char)("The quick brown fox jumps over the lazy dog. "[i % 45] ^ (i / 4096));
  }
  for (k = 0; k < 3; k++) {
    clen = pack(algs[k].wbits, orig, N, comp, N + N / 8 + 64);
    if (clen == 0) {
      printf("FAIL %s: deflate\n", algs[k].name);
      bad = 1;
      continue;
    }
    memset(out, 0, N);
    st = zz9k_inflate(algs[k].alg, ZZ9K_DECOMPRESS_FLAG_EXPECT_END, comp, (uint32_t)clen, out,
                      N, ZZ9K_INFLATE_SOFT, &rs, &ran);
    if (st != ZZ9K_STATUS_OK || rs.bytes_written != N || memcmp(out, orig, N) != 0 ||
        rs.checksum != (uint32_t)crc32(0L, orig, (uInt)N)) {
      printf("FAIL %s: software: %s\n", algs[k].name, zz9k_status_name(st));
      bad = 1;
      continue;
    }
    printf("%s: %lu -> %lu bytes, crc %08lx: software ok", algs[k].name, clen,
           (unsigned long)rs.bytes_written, (unsigned long)rs.checksum);
    memset(out, 0, N);
    st = zz9k_inflate(algs[k].alg, ZZ9K_DECOMPRESS_FLAG_EXPECT_END, comp, (uint32_t)clen, out,
                      N, ZZ9K_INFLATE_BOARD, &rb, &ran);
    if (st == ZZ9K_STATUS_NOT_FOUND || st == ZZ9K_STATUS_UNSUPPORTED) {
      printf(", board: %s\n", nb ? "no service" : "none");
    } else if (st != ZZ9K_STATUS_OK || memcmp(&rb, &rs, sizeof(rb)) != 0 ||
               memcmp(out, orig, N) != 0) {
      printf(", board: FAIL (%s)\n", zz9k_status_name(st));
      bad = 1;
    } else {
      printf(", board unit %d ok, the same\n", zz9k_pool_codec(algs[k].flag));
    }
  }
  zz9k_pool_close();
  free(orig);
  free(comp);
  free(out);
  printf("%s\n", bad ? "zz9k-test: FAIL" : "zz9k-test: ok");
  return bad;
}
