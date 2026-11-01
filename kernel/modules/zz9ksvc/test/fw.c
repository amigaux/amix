/*
 * fw.c -- a stand-in for the board's runtime, for zz9ksvc's host test: a mailbox in host
 * memory laid out by the ZZ9000 SDK v2 ABI, and a step function that answers the request
 * ring the way the firmware would, with faults on demand.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 */
#include <string.h>
#include "zz9k/abi.h"
#include "fw.h"

unsigned char fw_mbox[FW_MBOXLEN];
struct fw_state fw;

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
	fw.next_arm = FW_HEAP_ARM;
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
		uint32_t arm = fw.next_arm;

		fw.last_align = align;
		fw.last_alloc_flags = zz9k_get_be32(rq->payload + 8);
		if (fw.alloc_status) {
			complete(rq, fw.alloc_status, 0, 0);
			return;
		}
		if (align && arm % align)
			arm += align - arm % align;
		fw.next_arm = arm + len;
		if (fw.alloc_outside)
			arm = FW_HEAP_ARM + FW_HEAP_LEN;	/* outside the window, this one only */
		put32(p->handle, fw.next_handle);
		put32(p->arm_addr, arm);
		put32(p->length, len + fw.alloc_extra);
		for (i = 0; i < FW_NBUF; i++)
			if (!fw.live[i]) {
				fw.live[i] = fw.next_handle;
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
	put32(reply, 0x5a5a394b);
	complete(rq, fw.status ? fw.status : ZZ9K_STATUS_OK, reply, 16);
}

/*
 * One step of the runtime: take the queued requests in order.  A request is held while
 * fw.hold is set (it times out), or for fw.delay steps; held ones are answered once the
 * hold is lifted.
 */
void
fw_step(void)
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
