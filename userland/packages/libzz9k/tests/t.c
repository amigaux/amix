/*
 * t.c -- libzz9k's host test: the library (zz9k_host.c with the Amix patch, zz9k_amix.c)
 * against kernel/modules' zz9ksvc and its stand-in runtimes (kern.c), the system calls
 * routed by sysshim.c.  Each scenario is a fresh box; after each, nothing of the library's
 * may be left in the kernel, in the runtimes or in the address space.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <zlib.h>
#include "zz9k/host.h"
#include "zz9k/compression.h"
#include "zz9k/request.h"
#include "zz9k/amix.h"
#include "fw.h"

extern int kt_setup(int, int), kt_teardown(void), kt_opens(void), kt_kmem(void);
extern void kt_drain(void), kt_run(int);
extern int sh_maps_live(void), sh_fds_live(void), sh_bad, sh_maps;

static int checks;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); \
	printf(__VA_ARGS__); printf("\n"); exit(1); } checks++; } while (0)

#define NORIG	(300UL * 1024)
static unsigned char orig[NORIG], comp[NORIG + NORIG / 8 + 64];
static unsigned char *outb, *outs;
#define NOUT	(8UL * 1024 * 1024)

static const uint32_t alg3[3] = {
	ZZ9K_COMPRESSION_DEFLATE_RAW, ZZ9K_COMPRESSION_ZLIB, ZZ9K_COMPRESSION_GZIP
};

/* alg's stream of n bytes of orig in comp; its length */
static unsigned long
pack(uint32_t alg, unsigned long n)
{
	z_stream z;
	int wb = alg == ZZ9K_COMPRESSION_DEFLATE_RAW ? -MAX_WBITS :
	    alg == ZZ9K_COMPRESSION_ZLIB ? MAX_WBITS : MAX_WBITS + 16;
	unsigned long len;

	memset(&z, 0, sizeof z);
	deflateInit2(&z, 6, Z_DEFLATED, wb, 8, Z_DEFAULT_STRATEGY);
	z.next_in = orig;
	z.avail_in = (uInt)n;
	z.next_out = comp;
	z.avail_out = sizeof comp;
	len = deflate(&z, Z_FINISH) == Z_STREAM_END ? z.total_out : 0;
	deflateEnd(&z);
	if (len == 0) {
		printf("FAIL: the test's deflate\n");
		exit(1);
	}
	return len;
}

/*
 * The same call AUTO and SOFT: the same status, the same result, the same bytes; AUTO ran
 * where expected (want_ran: ZZ9K_INFLATE_BOARD, _SOFT, or 0 for a refusal before either).
 */
static void
same(const char *what, uint32_t alg, uint32_t flags, const void *src, uint32_t slen,
    uint32_t dcap, int want, int want_ran)
{
	ZZ9KDecompressResult rb, rs;
	int sb, ss, ranb, rans;

	memset(outb, 0x55, dcap);
	memset(outs, 0xaa, dcap);
	sb = zz9k_inflate(alg, flags, src, slen, outb, dcap, ZZ9K_INFLATE_AUTO, &rb, &ranb);
	ss = zz9k_inflate(alg, flags, src, slen, outs, dcap, ZZ9K_INFLATE_SOFT, &rs, &rans);
	CHECK(sb == want && ss == want, "%s: board path %s, software %s, want %s", what,
	    zz9k_status_name(sb), zz9k_status_name(ss), zz9k_status_name(want));
	CHECK(memcmp(&rb, &rs, sizeof rb) == 0, "%s: the results differ", what);
	if (sb == ZZ9K_STATUS_OK)
		CHECK(memcmp(outb, outs, rb.bytes_written) == 0, "%s: the bytes differ", what);
	CHECK(ranb == want_ran, "%s: ran %d, want %d", what, ranb, want_ran);
}

/* nothing of the library's left anywhere */
static void
clean(const char *what)
{
	int i;

	zz9k_pool_close();
	kt_drain();
	CHECK(kt_opens() == 0, "%s: %d opens left in the kernel", what, kt_opens());
	CHECK(sh_maps_live() == 0 && sh_fds_live() == 0 && sh_bad == 0,
	    "%s: %d mappings, %d descriptors left, %d bad unmaps", what, sh_maps_live(),
	    sh_fds_live(), sh_bad);
	for (i = 0; i < FW_NINST; i++)
		CHECK(fw_st[i].reqn == 0 || (fw_st[i].nlive == 0 && fw_st[i].bad_free == 0),
		    "%s: runtime %d holds %d buffers (%d bad frees)", what, i, fw_st[i].nlive,
		    fw_st[i].bad_free);
}

static void
formats(const char *what, int want_ran)
{
	char w[64];
	unsigned long n, k;

	for (k = 0; k < 3; k++) {
		n = pack(alg3[k], NORIG);
		sprintf(w, "%s: alg %lu", what, (unsigned long)alg3[k]);
		same(w, alg3[k], 0, comp, n, NORIG, ZZ9K_STATUS_OK, want_ran);
		CHECK(memcmp(outb, orig, NORIG) == 0, "%s: not the original", w);
	}
}

int
main(void)
{
	const ZZ9KAmixBoard *b;
	ZZ9KDecompressResult r;
	unsigned long i, n;
	int ran, k;

	outb = malloc(NOUT);
	outs = malloc(NOUT);
	for (i = 0; i < NORIG; i++)
		orig[i] = (unsigned char)("The quick brown fox jumps over the lazy dog. "[i % 45] ^ (i >> 12));

	/* 1. no board: the node gives ENXIO; "no service", and software does it */
	CHECK(kt_setup(0, 0) == ENXIO, "no board: _load");
	CHECK(zz9k_pool(&b) == 0, "no boards in the pool");
	CHECK(zz9k_pool_codec(ZZ9K_SERVICE_FLAG_CODEC_ZLIB) == -1, "no codec");
	{
		ZZ9KContext *c;
		ZZ9KBoard bd;

		CHECK(zz9k_open(&c) == ZZ9K_STATUS_NOT_FOUND && c == 0, "zz9k_open: NOT_FOUND");
		CHECK(zz9k_find_board(&bd) == ZZ9K_STATUS_NOT_FOUND, "zz9k_find_board: NOT_FOUND");
	}
	n = pack(ZZ9K_COMPRESSION_GZIP, NORIG);
	CHECK(zz9k_inflate(ZZ9K_COMPRESSION_GZIP, 0, comp, n, outb, NORIG, ZZ9K_INFLATE_BOARD, &r,
	    &ran) == ZZ9K_STATUS_NOT_FOUND && ran == 0, "board only, no board: NOT_FOUND");
	formats("no board", ZZ9K_INFLATE_SOFT);
	clean("no board");

	/* 2. one board with the zlib family: the board does it, the same as software */
	CHECK(kt_setup(1, 0) == 0, "one board: _load");
	CHECK(zz9k_pool(&b) == 1 && b[0].unit == 0 && b[0].abi_major == 2 &&
	    (b[0].codec_flags & ZZ9K_SERVICE_FLAG_CODEC_GZIP) &&
	    (b[0].capability_bits & ZZ9K_CAP_COMPRESSION), "the catalogue: unit %d abi %u codec %lx",
	    b[0].unit, b[0].abi_major, (unsigned long)b[0].codec_flags);
	CHECK(zz9k_pool_codec(ZZ9K_SERVICE_FLAG_CODEC_ZLIB | ZZ9K_SERVICE_FLAG_CODEC_GZIP) == 0 &&
	    zz9k_pool_codec(ZZ9K_SERVICE_FLAG_CODEC_LZ4_BLOCK) == -1, "codec lookups");
	formats("one board", ZZ9K_INFLATE_BOARD);
	CHECK(fw_st[0].nlive == 2, "two buffers, reused: %d live", fw_st[0].nlive);
	/* the outcomes that are not OK, the same either way */
	n = pack(ZZ9K_COMPRESSION_ZLIB, 50000);
	same("no room", ZZ9K_COMPRESSION_ZLIB, 0, comp, n, 1000, ZZ9K_STATUS_NO_MEMORY, ZZ9K_INFLATE_BOARD);
	same("truncated, EXPECT_END", ZZ9K_COMPRESSION_ZLIB, ZZ9K_DECOMPRESS_FLAG_EXPECT_END, comp, n / 2,
	    NORIG, ZZ9K_STATUS_BAD_REQUEST, ZZ9K_INFLATE_BOARD);
	same("truncated", ZZ9K_COMPRESSION_ZLIB, 0, comp, n / 2, NORIG, ZZ9K_STATUS_BAD_REQUEST,
	    ZZ9K_INFLATE_BOARD);
	same("whole, EXPECT_END", ZZ9K_COMPRESSION_ZLIB, ZZ9K_DECOMPRESS_FLAG_EXPECT_END, comp, n, NORIG,
	    ZZ9K_STATUS_OK, ZZ9K_INFLATE_BOARD);
	comp[n / 3] ^= 0x5a;
	same("corrupt", ZZ9K_COMPRESSION_ZLIB, 0, comp, n, NORIG, ZZ9K_STATUS_BAD_REQUEST, ZZ9K_INFLATE_BOARD);
	same("unknown flag", ZZ9K_COMPRESSION_ZLIB, 4, comp, n, NORIG, ZZ9K_STATUS_BAD_REQUEST, 0);
	same("unknown algorithm", 77, 0, comp, n, NORIG, ZZ9K_STATUS_BAD_REQUEST, 0);
	same("empty source", ZZ9K_COMPRESSION_ZLIB, 0, comp, 0, NORIG, ZZ9K_STATUS_BAD_REQUEST, 0);
	{
		/* a stream of nothing: the reply helper's check makes it INTERNAL_ERROR on the board
		   path; software says the same (after the board path fell back to it) */
		z_stream z;
		unsigned char e0[32];
		uLong l;

		memset(&z, 0, sizeof z);
		deflateInit2(&z, 6, Z_DEFLATED, MAX_WBITS + 16, 8, Z_DEFAULT_STRATEGY);
		z.next_out = e0;
		z.avail_out = sizeof e0;
		deflate(&z, Z_FINISH);
		l = z.total_out;
		deflateEnd(&z);
		same("empty output", ZZ9K_COMPRESSION_GZIP, 0, e0, (uint32_t)l, 100,
		    ZZ9K_STATUS_INTERNAL_ERROR, ZZ9K_INFLATE_SOFT);
	}
	/* an algorithm the board does not offer and software cannot do */
	CHECK(zz9k_inflate(ZZ9K_COMPRESSION_LZ4_BLOCK, 0, comp, n, outb, NORIG, ZZ9K_INFLATE_AUTO,
	    &r, &ran) == ZZ9K_STATUS_UNSUPPORTED, "LZ4 with no LZ4 anywhere: UNSUPPORTED");
	/* growing: every new size a new buffer; when the held ones use up the handles or the
	   quota, the channel is opened again and the call still runs on the board */
	n = pack(ZZ9K_COMPRESSION_ZLIB, 20000);
	k = fw_st[0].nfree;
	for (i = 64UL * 1024; i <= 6UL * 1024 * 1024; i += i / 2) {
		CHECK(zz9k_inflate(ZZ9K_COMPRESSION_ZLIB, 0, comp, n, outb, (uint32_t)i,
		    ZZ9K_INFLATE_AUTO, &r, &ran) == ZZ9K_STATUS_OK && ran == ZZ9K_INFLATE_BOARD &&
		    r.bytes_written == 20000 && memcmp(outb, orig, 20000) == 0, "dst %lu: %d", i, ran);
		CHECK(kt_opens() == 1, "one channel: %d", kt_opens());
	}
	CHECK(fw_st[0].nfree > k, "the held buffers were given back on the way: %d", fw_st[0].nfree - k);
	CHECK(zz9k_inflate(ZZ9K_COMPRESSION_ZLIB, 0, comp, n, outb, (uint32_t)NOUT,
	    ZZ9K_INFLATE_AUTO, &r, &ran) == ZZ9K_STATUS_OK && ran == ZZ9K_INFLATE_SOFT,
	    "a call that cannot fit the board's quota runs in software");
	/* the SDK's own API on the Amix branch */
	{
		ZZ9KContext *c;
		ZZ9KBoard bd;
		ZZ9KCaps caps;
		ZZ9KSharedBuffer s, d, x, y;
		ZZ9KDecompressDesc desc;
		ZZ9KRequest rq;
		ZZ9KMailboxEntry me;
		uint8_t pl[4] = { 'p', 'i', 'n', 'g' }, rp[48];
		uint32_t rl = sizeof rp, id;
		int base = kt_opens();

		CHECK(zz9k_find_board(&bd) == ZZ9K_STATUS_OK && bd.zorro_version == 3 && bd.product == 1,
		    "zz9k_find_board: zorro %u product %u", bd.zorro_version, bd.product);
		CHECK(zz9k_open(&c) == ZZ9K_STATUS_OK && zz9k_unit(c) == 0, "zz9k_open: unit 0");
		CHECK(zz9k_ping(c, pl, 4, rp, &rl) == ZZ9K_STATUS_OK, "zz9k_ping");
		CHECK(zz9k_query_caps(c, &caps) == ZZ9K_STATUS_OK && caps.abi_major == 2, "zz9k_query_caps");
		CHECK(zz9k_alloc_shared(c, 5000, 0, 0, &s) == ZZ9K_STATUS_OK && s.data && s.length >= 5000,
		    "zz9k_alloc_shared: mapped");
		CHECK(zz9k_alloc_shared(c, 70000, 0, 0, &d) == ZZ9K_STATUS_OK && d.data, "a second");
		CHECK(zz9k_alloc_shared(c, 100, 0, ZZ9K_ALLOC_CARD_ONLY, &x) == ZZ9K_STATUS_OK && !x.data,
		    "card-only: no mapping");
		CHECK(zz9k_alloc_shared(c, 100, 1UL << 20, 0, &y) == ZZ9K_STATUS_UNSUPPORTED && !y.data,
		    "an alignment over a page");
		n = pack(ZZ9K_COMPRESSION_ZLIB, 60000);
		memcpy((void *)s.data, comp, n);
		memset(&desc, 0, sizeof desc);
		desc.src_handle = s.handle;
		desc.src_length = (uint32_t)n;
		desc.dst_handle = d.handle;
		desc.dst_capacity = d.length;
		desc.algorithm = ZZ9K_COMPRESSION_ZLIB;
		CHECK(zz9k_decompress(c, &desc, &r) == ZZ9K_STATUS_OK && r.bytes_written == 60000 &&
		    memcmp((const void *)d.data, orig, 60000) == 0, "zz9k_decompress by handles");
		CHECK(zz9k_mem_copy(c, d.handle, 0, s.handle, 0, 16) == ZZ9K_STATUS_UNSUPPORTED,
		    "an opcode the kernel does not pass on: UNSUPPORTED");
		zz9k_request_ping(&rq, pl, 4);
		CHECK(zz9k_submit(c, &rq, &id) == ZZ9K_STATUS_UNSUPPORTED &&
		    zz9k_poll(c, &me) == ZZ9K_STATUS_UNSUPPORTED, "no raw ring access");
		CHECK(zz9k_free_shared(c, 99) == ZZ9K_STATUS_BAD_HANDLE, "a handle out of range");
		CHECK(zz9k_free_shared(c, s.handle) == ZZ9K_STATUS_OK && zz9k_free_shared(c, x.handle) ==
		    ZZ9K_STATUS_OK, "zz9k_free_shared");
		zz9k_close(c);	/* d still allocated and mapped: the close gives it back */
		kt_drain();
		CHECK(kt_opens() == base, "zz9k_close gave its channel back: %d opens, %d before",
		    kt_opens(), base);
	}
	clean("one board");

	/* 3. two boards: each call goes to the first board that offers its algorithm */
	CHECK(kt_setup(2, 0) == 0, "two boards: _load");
	fw_st[0].codec_flags = ZZ9K_SERVICE_FLAG_CODEC_ZLIB;
	CHECK(zz9k_pool(&b) == 2 && b[0].unit == 0 && b[1].unit == 1 &&
	    b[0].codec_flags == ZZ9K_SERVICE_FLAG_CODEC_ZLIB, "the pool: two boards");
	CHECK(zz9k_pool_codec(ZZ9K_SERVICE_FLAG_CODEC_GZIP) == 1 &&
	    zz9k_pool_codec(ZZ9K_SERVICE_FLAG_CODEC_ZLIB) == 0, "gzip on unit 1, zlib on unit 0");
	fw_st[0].last_op = fw_st[1].last_op = 0;
	n = pack(ZZ9K_COMPRESSION_GZIP, NORIG);
	same("gzip, two boards", ZZ9K_COMPRESSION_GZIP, 0, comp, n, NORIG, ZZ9K_STATUS_OK, ZZ9K_INFLATE_BOARD);
	CHECK(fw_st[1].last_op == fw_op_decompress() && fw_st[0].last_op != fw_op_decompress(),
	    "gzip ran on unit 1's runtime");
	n = pack(ZZ9K_COMPRESSION_ZLIB, NORIG);
	same("zlib, two boards", ZZ9K_COMPRESSION_ZLIB, 0, comp, n, NORIG, ZZ9K_STATUS_OK, ZZ9K_INFLATE_BOARD);
	CHECK(fw_st[0].last_op == fw_op_decompress(), "zlib ran on unit 0's runtime");
	clean("two boards");

	/* 4. unit 0's board has no runtime (its node gives ENXIO): the pool is unit 1 */
	CHECK(kt_setup(2, 1) == 0, "unit 0 dead, unit 1 live: _load");
	CHECK(zz9k_pool(&b) == 1 && b[0].unit == 1, "the pool skips unit 0");
	{
		ZZ9KContext *c;

		CHECK(zz9k_open_unit(&c, 0) == ZZ9K_STATUS_NOT_FOUND, "unit 0: NOT_FOUND");
		CHECK(zz9k_open(&c) == ZZ9K_STATUS_OK && zz9k_unit(c) == 1, "zz9k_open takes unit 1");
		zz9k_close(c);
	}
	formats("unit 1 only", ZZ9K_INFLATE_BOARD);
	clean("unit 1 only");

	/* 5. a board with no CODEC service: no service; software does it */
	CHECK(kt_setup(1, 0) == 0, "no codec: _load");
	fw_st[0].codec_flags = 0;
	CHECK(zz9k_pool(&b) == 1 && b[0].codec_flags == 0, "the catalogue has no codec");
	n = pack(ZZ9K_COMPRESSION_ZLIB, 10000);
	CHECK(zz9k_inflate(ZZ9K_COMPRESSION_ZLIB, 0, comp, n, outb, NORIG, ZZ9K_INFLATE_BOARD, &r,
	    &ran) == ZZ9K_STATUS_UNSUPPORTED, "board only: UNSUPPORTED");
	formats("no codec", ZZ9K_INFLATE_SOFT);
	clean("no codec");

	/* 6. a board whose runtime does not answer its catalogue: not in the pool */
	CHECK(kt_setup(1, 0) == 0, "caps fail: _load");
	fw_st[0].no_caps = 1;
	CHECK(zz9k_pool(&b) == 0, "a board without a catalogue is left out");
	formats("no catalogue", ZZ9K_INFLATE_SOFT);
	clean("no catalogue");

	/* 7. the runtime stops answering: the call times out and runs in software; the board
	   is used again once it answers */
	CHECK(kt_setup(1, 0) == 0, "timeout: _load");
	zz9k_pool_timeout(200);
	n = pack(ZZ9K_COMPRESSION_GZIP, 100000);
	same("before", ZZ9K_COMPRESSION_GZIP, 0, comp, n, NORIG, ZZ9K_STATUS_OK, ZZ9K_INFLATE_BOARD);
	fw_st[0].hold = 1;
	CHECK(zz9k_inflate(ZZ9K_COMPRESSION_GZIP, 0, comp, n, outb, NORIG, ZZ9K_INFLATE_AUTO, &r,
	    &ran) == ZZ9K_STATUS_OK && ran == ZZ9K_INFLATE_SOFT && memcmp(outb, orig, 100000) == 0,
	    "timed out on the board: software, ran %d", ran);
	CHECK(zz9k_inflate(ZZ9K_COMPRESSION_GZIP, 0, comp, n, outb, NORIG, ZZ9K_INFLATE_BOARD, &r,
	    &ran) == ZZ9K_STATUS_TIMEOUT, "board only: TIMEOUT");
	k = fw_st[0].steps;
	CHECK(zz9k_inflate(ZZ9K_COMPRESSION_GZIP, 0, comp, n, outb, NORIG, ZZ9K_INFLATE_AUTO, &r,
	    &ran) == ZZ9K_STATUS_OK && ran == ZZ9K_INFLATE_SOFT && fw_st[0].steps == k,
	    "a stalled board is left out of AUTO calls: software at once, no tick waited");
	fw_st[0].hold = 0;
	kt_drain();
	CHECK(kt_opens() == 0, "the timed-out channels were reaped once the runtime answered: %d",
	    kt_opens());
	CHECK(zz9k_inflate(ZZ9K_COMPRESSION_GZIP, 0, comp, n, outb, NORIG, ZZ9K_INFLATE_BOARD, &r,
	    &ran) == ZZ9K_STATUS_OK && memcmp(outb, orig, 100000) == 0, "board only: answered again");
	same("after", ZZ9K_COMPRESSION_GZIP, 0, comp, n, NORIG, ZZ9K_STATUS_OK, ZZ9K_INFLATE_BOARD);
	zz9k_pool_timeout(0);
	clean("timeout");

	CHECK(kt_teardown() == 0 && kt_kmem() == 0, "unloaded; kernel memory all freed: %d", kt_kmem());
	CHECK(sh_maps > 0, "mappings were made: %d", sh_maps);
	printf("libzz9k hosttest: ok (%d checks)\n", checks);
	return 0;
}
