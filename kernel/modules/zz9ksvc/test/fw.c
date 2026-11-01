/*
 * fw.c -- a stand-in for the board's runtime, for zz9ksvc's host test: a mailbox in host
 * memory laid out by the ZZ9000 SDK v2 ABI, and a step function that answers the request
 * ring the way the firmware would, with faults on demand.  The host-visible heap has host
 * memory behind it (fw_heap), placed first fit, so a freed range is handed out again as a
 * real heap would; DECOMPRESS of DEFLATE_RAW, ZLIB and GZIP inflates with the host's zlib
 * exactly as the firmware's one-shot decompress does (inflate with Z_FINISH, the CRC-32 of
 * the output), and algorithm 0, no real algorithm, gets the fixed reply the policy rows use.
 * QUERY_CAPS and QUERY_SERVICE answer as the firmware does.  There are FW_NINST runtimes,
 * one per unit; fw and fw_mbox name fw_cur's, and fw_step steps every one that was set up.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 */
#include <string.h>
#include <zlib.h>
#include "zz9k/abi.h"
#include "fw.h"

unsigned char fw_mboxes[FW_NINST][FW_MBOXLEN];
static unsigned char fw_heaps[FW_NINST][FW_HEAP_LEN];
struct fw_state fw_st[FW_NINST];
int fw_cur;
#define fw_heap	(fw_heaps[fw_cur])

static void
put32(volatile uint8_t *p, uint32_t v) { zz9k_put_be32(p, v); }

void
fw_init(int reqn, int cmpn, unsigned long caps)
{
	ZZ9KMailboxDescriptor *d = (ZZ9KMailboxDescriptor *)fw_mbox;

	memset(fw_mbox, 0, sizeof fw_mbox);
	memset(&fw, 0, sizeof fw);
	put32(d->magic, ZZ9K_ABI_MAGIC);
	zz9k_put_be16(d->abi_major, ZZ9K_ABI_VERSION_MAJOR);
	zz9k_put_be16(d->abi_minor, ZZ9K_ABI_VERSION_MINOR);
	put32(d->descriptor_size, ZZ9K_MAILBOX_DESCRIPTOR_SIZE);
	put32(d->request_ring_offset, 128);
	put32(d->request_ring_entries, reqn);
	put32(d->completion_ring_offset, 128 + reqn * 64);
	put32(d->completion_ring_entries, cmpn);
	put32(d->capability_bits, caps ? caps : (ZZ9K_CAP_MAILBOX | ZZ9K_CAP_DOORBELL |
	    ZZ9K_CAP_SHARED_ALLOC | ZZ9K_CAP_COMPRESSION));
	fw.reqn = reqn;
	fw.cmpn = cmpn;
	fw.next_handle = 0x100;
	fw.codec_flags = ZZ9K_SERVICE_FLAG_CODEC_DEFLATE_RAW | ZZ9K_SERVICE_FLAG_CODEC_ZLIB |
	    ZZ9K_SERVICE_FLAG_CODEC_GZIP | ZZ9K_SERVICE_FLAG_CODEC_CHECKSUM;
}

/* runtime inst's heap memory at a firmware address, or 0 */
unsigned char *
fw_heap_of(int inst, unsigned long arm)
{
	if (inst < 0 || inst >= FW_NINST || arm < FW_HEAP_ARM || arm >= FW_HEAP_ARM + FW_HEAP_LEN)
		return 0;
	return fw_heaps[inst] + (arm - FW_HEAP_ARM);
}

/* the runtime restarted: every buffer it held is forgotten, the heap is empty again */
void
fw_restart(void)
{
	memset(fw.live, 0, sizeof fw.live);
	fw.nlive = 0;
}

/* the host memory behind a firmware address of the heap, or 0 */
unsigned char *
fw_heap_at(unsigned long arm)
{
	if (arm < FW_HEAP_ARM || arm >= FW_HEAP_ARM + FW_HEAP_LEN)
		return 0;
	return fw_heap + (arm - FW_HEAP_ARM);
}

unsigned long fw_alg_raw(void) { return ZZ9K_COMPRESSION_DEFLATE_RAW; }
unsigned long fw_alg_zlib(void) { return ZZ9K_COMPRESSION_ZLIB; }
unsigned long fw_alg_gzip(void) { return ZZ9K_COMPRESSION_GZIP; }

/* the test's own data: alg's stream of src in dst (its length, 0 when it does not fit), a CRC */
unsigned long
fw_deflate(unsigned long alg, const unsigned char *src, unsigned long n, unsigned char *dst,
    unsigned long cap)
{
	z_stream z;
	int wb = alg == ZZ9K_COMPRESSION_DEFLATE_RAW ? -MAX_WBITS :
	    alg == ZZ9K_COMPRESSION_ZLIB ? MAX_WBITS : MAX_WBITS + 16;
	unsigned long out;

	memset(&z, 0, sizeof z);
	if (deflateInit2(&z, 6, Z_DEFLATED, wb, 8, Z_DEFAULT_STRATEGY) != Z_OK)
		return 0;
	z.next_in = (unsigned char *)src;
	z.avail_in = n;
	z.next_out = dst;
	z.avail_out = cap;
	out = deflate(&z, Z_FINISH) == Z_STREAM_END ? z.total_out : 0;
	deflateEnd(&z);
	return out;
}

unsigned long
fw_crc32(const unsigned char *p, unsigned long n)
{
	return crc32(crc32(0L, Z_NULL, 0), p, (uInt)n);
}

/* first fit: the lowest aligned address whose range no live buffer overlaps; 0 when none */
static unsigned long
place(unsigned long len, unsigned long align)
{
	unsigned long a = FW_HEAP_ARM;
	int i, moved;

	do {
		moved = 0;
		if (align && a % align)
			a += align - a % align;
		for (i = 0; i < FW_NBUF; i++)
			if (fw.live[i] && fw.live_arm[i] < a + len && a < fw.live_arm[i] + fw.live_len[i]) {
				a = fw.live_arm[i] + fw.live_len[i];
				moved = 1;
			}
	} while (moved);
	return a + len <= FW_HEAP_ARM + FW_HEAP_LEN ? a : 0;
}

/* a live buffer's slot by the firmware's handle, or -1 */
static int
slot_of(uint32_t h)
{
	int i;

	for (i = 0; i < FW_NBUF; i++)
		if (fw.live[i] == h)
			return i;
	return -1;
}

/*
 * DECOMPRESS of a zlib-family stream, as the firmware's one-shot decompress: the payload is
 * src handle, offset, length, dst handle, offset, capacity, algorithm, flags.  The reply's
 * payload is bytes consumed, written, the CRC-32 of the output, the algorithm and the flags.
 */
static unsigned
inflate_req(const uint8_t *p, uint8_t *reply)
{
	int s = slot_of(zz9k_get_be32(p)), d = slot_of(zz9k_get_be32(p + 12));
	uint32_t soff = zz9k_get_be32(p + 4), slen = zz9k_get_be32(p + 8);
	uint32_t doff = zz9k_get_be32(p + 16), dcap = zz9k_get_be32(p + 20);
	uint32_t alg = zz9k_get_be32(p + 24), flags = zz9k_get_be32(p + 28);
	unsigned char *src, *dst;
	z_stream z;
	int wb, rc;
	uint32_t rflags;

	if (s < 0 || d < 0)
		return ZZ9K_STATUS_BAD_HANDLE;
	if (alg == ZZ9K_COMPRESSION_DEFLATE_RAW)
		wb = -MAX_WBITS;
	else if (alg == ZZ9K_COMPRESSION_ZLIB)
		wb = MAX_WBITS;
	else if (alg == ZZ9K_COMPRESSION_GZIP)
		wb = MAX_WBITS + 16;
	else
		return ZZ9K_STATUS_UNSUPPORTED;
	if (slen == 0 || dcap == 0 || soff > fw.live_len[s] || slen > fw.live_len[s] - soff ||
	    doff > fw.live_len[d] || dcap > fw.live_len[d] - doff)
		return ZZ9K_STATUS_BAD_REQUEST;
	if ((flags & ~(uint32_t)ZZ9K_DECOMPRESS_FLAG_EXPECT_END) != 0)
		return ZZ9K_STATUS_UNSUPPORTED;
	if ((src = fw_heap_at(fw.live_arm[s])) == 0 || (dst = fw_heap_at(fw.live_arm[d])) == 0)
		return ZZ9K_STATUS_BAD_REQUEST;
	src += soff;
	dst += doff;
	memset(&z, 0, sizeof z);
	z.next_in = src;
	z.avail_in = slen;
	z.next_out = dst;
	z.avail_out = dcap;
	if (inflateInit2(&z, wb) != Z_OK)
		return ZZ9K_STATUS_INTERNAL_ERROR;
	rc = inflate(&z, Z_FINISH);
	rflags = ZZ9K_DECOMPRESS_RESULT_CHECKSUM_VALID | (rc == Z_STREAM_END ? ZZ9K_DECOMPRESS_RESULT_STREAM_END : 0);
	zz9k_put_be32(reply + 0, (uint32_t)z.total_in);
	zz9k_put_be32(reply + 4, (uint32_t)z.total_out);
	zz9k_put_be32(reply + 8, (uint32_t)crc32(crc32(0L, Z_NULL, 0), dst, (uInt)z.total_out));
	zz9k_put_be32(reply + 12, alg);
	zz9k_put_be32(reply + 16, rflags);
	inflateEnd(&z);
	if (rc == Z_STREAM_END)
		return ZZ9K_STATUS_OK;
	if (z.avail_out == 0)
		return ZZ9K_STATUS_NO_MEMORY;
	if (flags & ZZ9K_DECOMPRESS_FLAG_EXPECT_END)
		return ZZ9K_STATUS_BAD_REQUEST;
	return rc == Z_OK ? ZZ9K_STATUS_OK : ZZ9K_STATUS_BAD_REQUEST;
}

unsigned long fw_caps_mailbox(void) { return ZZ9K_CAP_MAILBOX; }
unsigned long fw_op_decompress(void) { return ZZ9K_OP_DECOMPRESS; }
unsigned long fw_op_decompress_test(void) { return ZZ9K_OP_DECOMPRESS_TEST; }
unsigned long fw_op_ping(void) { return ZZ9K_OP_PING; }
unsigned long fw_op_query_caps(void) { return ZZ9K_OP_QUERY_CAPS; }
unsigned long fw_op_module_status(void) { return ZZ9K_OP_MODULE_STATUS; }
unsigned long fw_op_mem_copy(void) { return ZZ9K_OP_MEM_COPY; }
unsigned long fw_status_ok(void) { return ZZ9K_STATUS_OK; }
unsigned long fw_status_bad_handle(void) { return ZZ9K_STATUS_BAD_HANDLE; }

/* corrupt the descriptor in one of several ways (for the attach checks) */
void
fw_break(int how)
{
	ZZ9KMailboxDescriptor *d = (ZZ9KMailboxDescriptor *)fw_mbox;

	switch (how) {
	case 1: put32(d->magic, 0x12345678); break;
	case 2: zz9k_put_be16(d->abi_major, 1); break;
	case 3: put32(d->capability_bits, 0); break;
	case 4: put32(d->request_ring_entries, 1); break;
	case 5: put32(d->completion_ring_offset, FW_MBOXLEN - 64); break;	/* past the end */
	case 6: put32(d->completion_ring_offset, 128 + 64); break;		/* overlaps */
	case 7: put32(d->request_ring_offset, 64); break;			/* in the descriptor */
	case 8: put32(d->request_head, 9999); break;				/* bad cursor */
	}
}

static void
complete(const ZZ9KMailboxWireEntry *rq, unsigned status, const uint8_t *payload, unsigned len)
{
	ZZ9KMailboxDescriptor *d = (ZZ9KMailboxDescriptor *)fw_mbox;
	ZZ9KMailboxWireEntry *ring = (ZZ9KMailboxWireEntry *)(fw_mbox +
	    zz9k_get_be32(d->completion_ring_offset));
	uint32_t tail = zz9k_get_be32(d->completion_tail);
	ZZ9KMailboxWireEntry *c = &ring[tail];

	memcpy(c, rq, sizeof *c);
	zz9k_put_be16(c->status, (uint16_t)status);
	zz9k_put_be16(c->payload_len, (uint16_t)len);
	memset(c->payload, 0, sizeof c->payload);
	if (payload)
		memcpy(c->payload, payload, len);
	put32(d->completion_tail, (tail + 1) % fw.cmpn);
}

/* a completion for a request id nobody sent */
void
fw_stray(unsigned long id)
{
	ZZ9KMailboxWireEntry w;

	memset(&w, 0, sizeof w);
	put32(w.request_id, (uint32_t)id);
	zz9k_put_be16(w.opcode, ZZ9K_OP_PING);
	complete(&w, ZZ9K_STATUS_OK, 0, 0);
}

static void
answer(const ZZ9KMailboxWireEntry *rq)
{
	uint16_t op = zz9k_get_be16(rq->opcode);
	uint8_t reply[48];
	int i;

	memset(reply, 0, sizeof reply);
	if (fw.park_op && op == fw.park_op && fw.nparked < 8) {
		memcpy(fw.parked[fw.nparked++], rq, 64);
		return;
	}
	fw.last_op = op;
	memcpy(fw.last_payload, rq->payload, 48);
	if (zz9k_get_be16(rq->status) != ZZ9K_STATUS_QUEUED)
		fw.not_queued++;
	if (op == ZZ9K_OP_ALLOC_SHARED) {
		ZZ9KSharedBufferInfoPayload *p = (ZZ9KSharedBufferInfoPayload *)reply;
		uint32_t len = zz9k_get_be32(rq->payload);
		uint32_t align = zz9k_get_be32(rq->payload + 4);
		uint32_t arm;

		fw.last_align = align;
		fw.last_alloc_flags = zz9k_get_be32(rq->payload + 8);
		if (fw.alloc_status) {
			complete(rq, fw.alloc_status, 0, 0);
			return;
		}
		if (fw.alloc_at) {
			arm = fw.alloc_at;
			fw.alloc_at = 0;
		} else if ((arm = place(len, align)) == 0) {
			complete(rq, ZZ9K_STATUS_NO_MEMORY, 0, 0);
			return;
		}
		if (fw.alloc_outside)
			arm = FW_HEAP_ARM + FW_HEAP_LEN;	/* outside the window, this one only */
		put32(p->handle, fw.next_handle);
		put32(p->arm_addr, arm);
		put32(p->length, len + fw.alloc_extra);
		for (i = 0; i < FW_NBUF; i++)
			if (!fw.live[i]) {
				fw.live[i] = fw.next_handle;
				fw.live_arm[i] = arm;
				fw.live_len[i] = len;
				break;
			}
		fw.nlive++;
		fw.nalloc++;
		fw.next_handle++;
		complete(rq, ZZ9K_STATUS_OK, reply, sizeof *p);
		return;
	}
	if (op == ZZ9K_OP_FREE_SHARED) {
		uint32_t h = zz9k_get_be32(rq->payload);

		for (i = 0; i < FW_NBUF; i++)
			if (fw.live[i] == h) {
				fw.live[i] = 0;
				fw.nlive--;
				break;
			}
		if (i == FW_NBUF)
			fw.bad_free++;
		fw.nfree++;
		complete(rq, ZZ9K_STATUS_OK, 0, 0);
		return;
	}
	if (op == ZZ9K_OP_DECOMPRESS && zz9k_get_be32(rq->payload + 24) != 0) {
		unsigned st = fw.dec_status ? fw.dec_status : inflate_req(rq->payload, reply);

		/* as the firmware: the whole result payload on OK, none otherwise */
		complete(rq, st, st == ZZ9K_STATUS_OK ? reply : 0,
		    st == ZZ9K_STATUS_OK ? (unsigned)sizeof(ZZ9KDecompressResultPayload) : 0);
		return;
	}
	if (op == ZZ9K_OP_DECOMPRESS || op == ZZ9K_OP_DECOMPRESS_TEST) {
		uint32_t h = zz9k_get_be32(rq->payload);

		for (i = 0; i < FW_NBUF; i++)
			if (fw.live[i] == h)
				break;
		if (i == FW_NBUF) {
			complete(rq, ZZ9K_STATUS_BAD_HANDLE, 0, 0);
			return;
		}
		put32(reply, 1234);	/* bytes produced */
		complete(rq, fw.status ? fw.status : ZZ9K_STATUS_OK, reply, 8);
		return;
	}
	if (op == ZZ9K_OP_QUERY_CAPS) {
		ZZ9KMailboxDescriptor *d = (ZZ9KMailboxDescriptor *)fw_mbox;

		if (fw.no_caps) {
			complete(rq, ZZ9K_STATUS_INTERNAL_ERROR, 0, 0);
			return;
		}
		put32(reply + 0, ZZ9K_ABI_MAGIC);
		zz9k_put_be16(reply + 4, ZZ9K_ABI_VERSION_MAJOR);
		zz9k_put_be16(reply + 6, ZZ9K_ABI_VERSION_MINOR);
		put32(reply + 8, zz9k_get_be32(d->capability_bits) | ZZ9K_CAP_SERVICE_DISCOVERY);
		put32(reply + 12, 48);
		put32(reply + 16, FW_NBUF);
		put32(reply + 24, 0x00020901);
		put32(reply + 28, fw.reqn);
		put32(reply + 32, fw.cmpn);
		complete(rq, ZZ9K_STATUS_OK, reply, 40);
		return;
	}
	if (op == ZZ9K_OP_QUERY_SERVICE) {
		uint32_t id = zz9k_get_be32(rq->payload);

		if (id != ZZ9K_SERVICE_CODEC || fw.codec_flags == 0) {
			complete(rq, ZZ9K_STATUS_NOT_FOUND, 0, 0);
			return;
		}
		put32(reply + 0, id);
		put32(reply + 4, 1);
		put32(reply + 12, fw.codec_flags);
		put32(reply + 16, ZZ9K_OP_DECOMPRESS);
		put32(reply + 20, 1);
		put32(reply + 24, 48);
		memcpy(reply + 28, "codec", 5);
		complete(rq, ZZ9K_STATUS_OK, reply, 48);
		return;
	}
	put32(reply, 0x5a5a394b);
	complete(rq, fw.status ? fw.status : ZZ9K_STATUS_OK, reply, 16);
}

/*
 * One step of the runtime: take the queued requests in order.  A request is held while
 * fw.hold is set (it times out), or for fw.delay steps; held ones are answered once the
 * hold is lifted.
 */
static void step1(void);

void
fw_step(void)
{
	int save = fw_cur, i;

	for (i = 0; i < FW_NINST; i++)
		if (fw_st[i].reqn != 0) {
			fw_cur = i;
			step1();
		}
	fw_cur = save;
}

static void
step1(void)
{
	ZZ9KMailboxDescriptor *d = (ZZ9KMailboxDescriptor *)fw_mbox;
	ZZ9KMailboxWireEntry *ring;
	uint32_t head, tail;

	fw.steps++;
	if (fw.hold || fw.dead)
		return;
	if (fw.wait > 0) {
		fw.wait--;
		return;
	}
	ring = (ZZ9KMailboxWireEntry *)(fw_mbox + zz9k_get_be32(d->request_ring_offset));
	head = zz9k_get_be32(d->request_head);
	tail = zz9k_get_be32(d->request_tail);
	while (head != tail) {
		uint32_t ct = zz9k_get_be32(d->completion_tail);
		uint32_t ch = zz9k_get_be32(d->completion_head);

		if ((ct + 1) % fw.cmpn == ch)
			break;			/* completion ring full: later */
		answer(&ring[head]);
		head = (head + 1) % fw.reqn;
		put32(d->request_head, head);
		fw.wait = fw.delay;
		if (fw.wait > 0)
			break;
	}
}

/* answer the parked requests now */
void
fw_unpark(void)
{
	int i, n = fw.nparked;

	fw.park_op = 0;
	fw.nparked = 0;
	for (i = 0; i < n; i++)
		answer((const ZZ9KMailboxWireEntry *)fw.parked[i]);
}

/* how many requests are queued and not yet taken */
int
fw_queued(void)
{
	ZZ9KMailboxDescriptor *d = (ZZ9KMailboxDescriptor *)fw_mbox;
	uint32_t head = zz9k_get_be32(d->request_head), tail = zz9k_get_be32(d->request_tail);

	return (int)((tail + fw.reqn - head) % fw.reqn);
}
