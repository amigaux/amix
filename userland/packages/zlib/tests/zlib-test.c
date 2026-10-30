/*
 * zlib-test.c -- prove the packaged libz.a actually works, ON THE BOX.
 *
 * Shipped in the package (/opt/amix/bin/zlib-test) for the same reason
 * libacompat ships acompat-test: a package that installs files proves the
 * PACKAGING worked; a binary linked against exactly the archive in the package
 * and run on the box proves the PAYLOAD worked -- on this libc, with this code
 * generator, at this word order.
 *
 * Three checks, chosen so a byte-order or struct-packing mistake cannot pass:
 *
 *   1. crc32 and adler32 of a fixed string against constants that are defined
 *      by the algorithms themselves (not by any zlib version), computed on the
 *      host with a different zlib.  These are the endianness canaries: the two
 *      checksums walk the bytes in opposite arithmetic, so a wrong-endian build
 *      misses at least one.
 *
 *   2. A multi-megabyte deflate -> inflate round trip over a buffer that mixes
 *      a repeating pattern (so deflate has real matches to encode) with a
 *      deterministic PRNG stream (so the literal/length machinery is exercised
 *      too), then memcmp back to the original.  A bitstream deflate writes and
 *      inflate cannot read back byte-exactly is the struct-packing failure, and
 *      it is invisible to an exit status.
 *
 *   3. inflate of a zlib stream produced by the HOST's zlib (embedded below as
 *      bytes).  Cross-decompression is the half of the smoke that catches a
 *      header/window mistake the round trip would hide, because both ends of a
 *      round trip share the same bug.
 *
 * No gzprintf()/gz* file API is touched, so this program pulls neither vsnprintf
 * nor any stdio buffering surface -- it links from libz.a alone (plus libc).
 * Prints a line per check and a final verdict; exits non-zero on any failure.
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "zlib.h"

#define BUFSZ (4u * 1024u * 1024u)

/* The fixed string and its algorithm-defined checksums (host-computed). */
static const char FOX[] = "The quick brown fox jumps over the lazy dog";
#define FOX_CRC32   0x414FA339UL
#define FOX_ADLER32 0x5BDC0FDAUL

/*
 * A zlib stream (RFC 1950) of the exact bytes of FOX, produced on the host by
 * compress2(...,Z_DEFAULT_COMPRESSION).  Decompressing this on the box proves
 * the box's inflate reads a stream a different machine's deflate wrote.
 */
static const unsigned char FOX_ZLIB[] = {
    0x78, 0x9c, 0x0b, 0xc9, 0x48, 0x55, 0x28, 0x2c, 0xcd, 0x4c, 0xce, 0x56,
    0x48, 0x2a, 0xca, 0x2f, 0xcf, 0x53, 0x48, 0xcb, 0xaf, 0x50, 0xc8, 0x2a,
    0xcd, 0x2d, 0x28, 0x56, 0xc8, 0x2f, 0x4b, 0x2d, 0x52, 0x28, 0x01, 0x4a,
    0xe7, 0x24, 0x56, 0x55, 0x2a, 0xa4, 0xe4, 0xa7, 0x03, 0x00, 0x5b, 0xdc,
    0x0f, 0xda
};

static int check_checksums(void)
{
    uLong c = crc32(0L, Z_NULL, 0);
    uLong a = adler32(0L, Z_NULL, 0);
    c = crc32(c, (const Bytef *)FOX, (uInt)strlen(FOX));
    a = adler32(a, (const Bytef *)FOX, (uInt)strlen(FOX));
    printf("  crc32   = 0x%08lX (want 0x%08lX)  %s\n",
           (unsigned long)c, FOX_CRC32, c == FOX_CRC32 ? "ok" : "FAIL");
    printf("  adler32 = 0x%08lX (want 0x%08lX)  %s\n",
           (unsigned long)a, FOX_ADLER32, a == FOX_ADLER32 ? "ok" : "FAIL");
    return (c == FOX_CRC32 && a == FOX_ADLER32) ? 0 : 1;
}

static int check_roundtrip(void)
{
    Bytef *orig, *comp, *back;
    uLong complen, backlen;
    unsigned long seed = 0x12345678UL;
    unsigned i;
    int rc;

    orig = (Bytef *)malloc(BUFSZ);
    complen = compressBound(BUFSZ);
    comp = (Bytef *)malloc(complen);
    back = (Bytef *)malloc(BUFSZ);
    if (!orig || !comp || !back) {
        printf("  round-trip: FAIL (out of memory)\n");
        free(orig); free(comp); free(back);
        return 1;
    }

    for (i = 0; i < BUFSZ; i++) {
        if ((i & 0x3f) < 0x20) {
            orig[i] = (Bytef)('A' + (i % 26));      /* compressible run */
        } else {
            seed = seed * 1103515245UL + 12345UL;   /* LCG, incompressible */
            orig[i] = (Bytef)(seed >> 16);
        }
    }

    rc = compress2(comp, &complen, orig, BUFSZ, Z_BEST_COMPRESSION);
    if (rc != Z_OK) {
        printf("  round-trip: FAIL (compress2 rc=%d)\n", rc);
        free(orig); free(comp); free(back);
        return 1;
    }

    backlen = BUFSZ;
    rc = uncompress(back, &backlen, comp, complen);
    if (rc != Z_OK) {
        printf("  round-trip: FAIL (uncompress rc=%d)\n", rc);
        free(orig); free(comp); free(back);
        return 1;
    }

    if (backlen != BUFSZ || memcmp(orig, back, BUFSZ) != 0) {
        printf("  round-trip: FAIL (%lu bytes back, content mismatch)\n",
               (unsigned long)backlen);
        free(orig); free(comp); free(back);
        return 1;
    }

    printf("  round-trip: ok (%u -> %lu -> %u bytes, ratio %lu%%)\n",
           BUFSZ, (unsigned long)complen, BUFSZ,
           (unsigned long)(complen * 100UL / BUFSZ));
    free(orig); free(comp); free(back);
    return 0;
}

static int check_host_stream(void)
{
    Bytef out[128];
    uLong outlen = sizeof(out);
    int rc = uncompress(out, &outlen, FOX_ZLIB, (uLong)sizeof(FOX_ZLIB));
    if (rc != Z_OK) {
        printf("  host-stream: FAIL (uncompress rc=%d)\n", rc);
        return 1;
    }
    if (outlen != strlen(FOX) || memcmp(out, FOX, outlen) != 0) {
        printf("  host-stream: FAIL (got %lu bytes)\n", (unsigned long)outlen);
        return 1;
    }
    printf("  host-stream: ok (inflated %lu host bytes to \"%.*s\")\n",
           (unsigned long)sizeof(FOX_ZLIB), (int)outlen, (char *)out);
    return 0;
}

int main(void)
{
    int bad = 0;
    printf("zlib-test: linked against zlib %s\n", zlibVersion());
    bad += check_checksums();
    bad += check_roundtrip();
    bad += check_host_stream();
    if (bad == 0) {
        printf("zlib-test: PASS\n");
        return 0;
    }
    printf("zlib-test: %d FAILED\n", bad);
    return 1;
}
