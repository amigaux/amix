/*
 * wire.c -- the ZZ9000 SDK v2 mailbox protocol and zz9ksvc's request policy.  The only
 * file of zz9ksvc that includes the SDK headers (sdk/zz9k, verbatim); compiled as ANSI C
 * (module/Makefile), since the headers are C99 and the rest of the module is compiled
 * -traditional.  Its interface to the rest is wire.h, in plain types.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 *
 * The mailbox (descriptor and rings) lies in board memory the board driver mapped.  All of
 * it is big-endian, read and written a byte at a time through volatile pointers, so the
 * order of the stores is the program order.  The host writes a request at request_tail and
 * advances the tail; the firmware advances request_head.  The firmware writes completions
 * at completion_tail; the host takes them at completion_head and advances it.  Every
 * cursor read is checked against its ring before it is used.  No 64-bit arithmetic here:
 * the kernels export only the unsigned 64-bit helpers.
 */
#include <sys/errno.h>
#include "zz9k/abi.h"
#include "wire.h"

unsigned long zzw_boot_magic = ZZ9K_REG_SDK_MAGIC_VALUE;
unsigned long zzw_inline_flag = ZZ9K_ENTRY_INLINE_PAYLOAD;
unsigned long zzw_cap_doorbell = ZZ9K_CAP_DOORBELL;

unsigned long
zzw_get32(const unsigned char *p)
{
	return zz9k_get_be32(p);
}

void
zzw_put32(unsigned char *p, unsigned long v)
{
	zz9k_put_be32(p, (uint32_t)v);
}

/*
 * Check the descriptor at mbox (len bytes mapped) and fill ring.  ENXIO: no runtime there
 * (no magic, another ABI major, no mailbox capability); EIO: a descriptor that does not
 * fit what is mapped.
 */
int
zzw_attach(char *mbox, unsigned long len, struct zzw_ring *r)
{
	volatile ZZ9KMailboxDescriptor *d = (volatile ZZ9KMailboxDescriptor *)mbox;
	unsigned long dsize, end;

	if (mbox == 0 || len < ZZ9K_MAILBOX_DESCRIPTOR_SIZE)
		return ENXIO;
	if (zz9k_get_be32(d->magic) != ZZ9K_ABI_MAGIC ||
	    zz9k_get_be16(d->abi_major) != ZZ9K_ABI_VERSION_MAJOR)
		return ENXIO;
	r->r_caps = zz9k_get_be32(d->capability_bits);
	if ((r->r_caps & ZZ9K_CAP_MAILBOX) == 0)
		return ENXIO;
	r->r_major = zz9k_get_be16(d->abi_major);
	r->r_minor = zz9k_get_be16(d->abi_minor);
	dsize = zz9k_get_be32(d->descriptor_size);
	r->r_reqoff = zz9k_get_be32(d->request_ring_offset);
	r->r_reqn = zz9k_get_be32(d->request_ring_entries);
	r->r_cmpoff = zz9k_get_be32(d->completion_ring_offset);
	r->r_cmpn = zz9k_get_be32(d->completion_ring_entries);
	if (dsize < ZZ9K_MAILBOX_DESCRIPTOR_SIZE || dsize > len)
		return EIO;
	if (r->r_reqn < 2 || r->r_cmpn < 2 || r->r_reqn > 4096 || r->r_cmpn > 4096)
		return EIO;
	if (r->r_reqoff < dsize || r->r_cmpoff < dsize || (r->r_reqoff & 3) || (r->r_cmpoff & 3))
		return EIO;
	/* each ring inside the mapping, no wrap: offsets and sizes are below 2^28 here */
	end = r->r_reqoff + r->r_reqn * ZZ9K_MAILBOX_ENTRY_SIZE;
	if (r->r_reqoff > len || end > len || end < r->r_reqoff)
		return EIO;
	end = r->r_cmpoff + r->r_cmpn * ZZ9K_MAILBOX_ENTRY_SIZE;
	if (r->r_cmpoff > len || end > len || end < r->r_cmpoff)
		return EIO;
	/* the two rings must not overlap */
	if (r->r_reqoff < r->r_cmpoff + r->r_cmpn * ZZ9K_MAILBOX_ENTRY_SIZE &&
	    r->r_cmpoff < r->r_reqoff + r->r_reqn * ZZ9K_MAILBOX_ENTRY_SIZE)
		return EIO;
	return 0;
}

static void
wire_out(volatile ZZ9KMailboxWireEntry *w, const struct zzw_entry *e)
{
	int i;

	zz9k_put_be32(w->request_id, (uint32_t)e->e_id);
	zz9k_put_be16(w->opcode, (uint16_t)e->e_op);
	zz9k_put_be16(w->status, (uint16_t)ZZ9K_STATUS_QUEUED);
	zz9k_put_be16(w->flags, (uint16_t)e->e_flags);
	zz9k_put_be16(w->payload_len, (uint16_t)e->e_len);
	zz9k_put_be32(w->user_cookie, (uint32_t)e->e_cookie);
	for (i = 0; i < ZZW_PAYLOAD; i++)
		w->payload[i] = e->e_payload[i];
}

static void
wire_in(struct zzw_entry *e, const volatile ZZ9KMailboxWireEntry *w)
{
	int i;

	e->e_id = zz9k_get_be32(w->request_id);
	e->e_op = zz9k_get_be16(w->opcode);
	e->e_status = zz9k_get_be16(w->status);
	e->e_flags = zz9k_get_be16(w->flags);
	e->e_len = zz9k_get_be16(w->payload_len);
	e->e_cookie = zz9k_get_be32(w->user_cookie);
	for (i = 0; i < ZZW_PAYLOAD; i++)
		e->e_payload[i] = w->payload[i];
}

/* queue e (its status set QUEUED) on the request ring and advance the tail; the caller
   rings the doorbell when the descriptor has zzw_cap_doorbell */
int
zzw_put(char *mbox, const struct zzw_ring *r, const struct zzw_entry *e)
{
	volatile ZZ9KMailboxDescriptor *d = (volatile ZZ9KMailboxDescriptor *)mbox;
	volatile ZZ9KMailboxWireEntry *ring =
	    (volatile ZZ9KMailboxWireEntry *)(mbox + r->r_reqoff);
	unsigned long head, tail, next;

	if (e->e_len > ZZW_PAYLOAD)
		return EIO;
	head = zz9k_get_be32(d->request_head);
	tail = zz9k_get_be32(d->request_tail);
	if (head >= r->r_reqn || tail >= r->r_reqn)
		return EIO;
	next = tail + 1 == r->r_reqn ? 0 : tail + 1;
	if (next == head)
		return EAGAIN;
	wire_out(&ring[tail], e);
	zz9k_put_be32(d->request_tail, (uint32_t)next);
	return 0;
}

/* take the next completion into e and advance the head */
int
zzw_take(char *mbox, const struct zzw_ring *r, struct zzw_entry *e)
{
	volatile ZZ9KMailboxDescriptor *d = (volatile ZZ9KMailboxDescriptor *)mbox;
	volatile ZZ9KMailboxWireEntry *ring =
	    (volatile ZZ9KMailboxWireEntry *)(mbox + r->r_cmpoff);
	unsigned long head, tail;

	head = zz9k_get_be32(d->completion_head);
	tail = zz9k_get_be32(d->completion_tail);
	if (head >= r->r_cmpn || tail >= r->r_cmpn)
		return EIO;
	if (head == tail)
		return EAGAIN;
	wire_in(e, &ring[head]);
	if (e->e_len > ZZW_PAYLOAD)
		e->e_len = ZZW_PAYLOAD;
	zz9k_put_be32(d->completion_head, (uint32_t)(head + 1 == r->r_cmpn ? 0 : head + 1));
	return 0;
}

/*
 * What a request through the node may be.  An opcode not listed is refused; the list
 * grows one row per opcode as services are added.  REFS rows name, for each buffer the
 * payload refers to, the offsets of its handle, of the byte offset into it and of the
 * length used from there, so the kernel can translate the handle and check the range.
 */
#define OFF(type, member)	((int)offsetof(type, member))

int
zzw_policy(unsigned long op, struct zzw_refs *rf)
{
	rf->rf_n = 0;
	switch (op) {
	case ZZ9K_OP_NOP:
	case ZZ9K_OP_PING:
	case ZZ9K_OP_QUERY_CAPS:
	case ZZ9K_OP_QUERY_SERVICE:
		return ZZW_PLAIN;
	case ZZ9K_OP_MODULE_STATUS:
		return ZZW_PRIV;
	case ZZ9K_OP_DECOMPRESS:
		rf->rf_n = 2;
		rf->rf_hoff[0] = OFF(ZZ9KDecompressPayload, src_handle);
		rf->rf_ooff[0] = OFF(ZZ9KDecompressPayload, src_offset);
		rf->rf_loff[0] = OFF(ZZ9KDecompressPayload, src_length);
		rf->rf_hoff[1] = OFF(ZZ9KDecompressPayload, dst_handle);
		rf->rf_ooff[1] = OFF(ZZ9KDecompressPayload, dst_offset);
		rf->rf_loff[1] = OFF(ZZ9KDecompressPayload, dst_capacity);
		return ZZW_REFS;
	case ZZ9K_OP_DECOMPRESS_TEST:
		rf->rf_n = 1;
		rf->rf_hoff[0] = OFF(ZZ9KDecompressTestPayload, src_handle);
		rf->rf_ooff[0] = OFF(ZZ9KDecompressTestPayload, src_offset);
		rf->rf_loff[0] = OFF(ZZ9KDecompressTestPayload, src_length);
		return ZZW_REFS;
	}
	return ZZW_DENY;
}

int
zzw_errno(unsigned long status)
{
	switch (status) {
	case ZZ9K_STATUS_OK:
		return 0;
	case ZZ9K_STATUS_BUSY:
		return EAGAIN;
	case ZZ9K_STATUS_UNSUPPORTED:
	case ZZ9K_STATUS_NOT_FOUND:
	case ZZ9K_STATUS_MODULE_MISSING:
	case ZZ9K_STATUS_MODULE_MISMATCH:
		return ENXIO;
	case ZZ9K_STATUS_BAD_REQUEST:
	case ZZ9K_STATUS_BAD_HANDLE:
		return EINVAL;
	case ZZ9K_STATUS_NO_MEMORY:
		return ENOMEM;
	case ZZ9K_STATUS_TIMEOUT:
		return ETIMEDOUT;
	case ZZ9K_STATUS_CANCELLED:
		return EINTR;
	}
	return EIO;
}

/* an ALLOC_SHARED request for len bytes at align; mappable unless cardonly */
void
zzw_alloc_req(struct zzw_entry *e, unsigned long len, unsigned long align, int cardonly,
    unsigned long caps)
{
	ZZ9KAllocSharedPayload *p = (ZZ9KAllocSharedPayload *)e->e_payload;
	unsigned long flags = 0;
	int i;

	for (i = 0; i < ZZW_PAYLOAD; i++)
		e->e_payload[i] = 0;
	if (cardonly)
		flags = ZZ9K_ALLOC_CARD_ONLY;
	else if (caps & ZZ9K_CAP_HOST_WINDOW_HEAP)
		flags = ZZ9K_ALLOC_HOST_WINDOW;
	zz9k_put_be32(p->length, (uint32_t)len);
	zz9k_put_be32(p->alignment, (uint32_t)align);
	zz9k_put_be32(p->flags, (uint32_t)flags);
	e->e_op = ZZ9K_OP_ALLOC_SHARED;
	e->e_flags = ZZ9K_ENTRY_INLINE_PAYLOAD;
	e->e_len = sizeof(ZZ9KAllocSharedPayload);
}

/* the buffer an ALLOC_SHARED completion gives: handle, firmware address, length */
int
zzw_alloc_reply(const struct zzw_entry *e, unsigned long *fwh, unsigned long *arm,
    unsigned long *len)
{
	const ZZ9KSharedBufferInfoPayload *p = (const ZZ9KSharedBufferInfoPayload *)e->e_payload;

	if (e->e_status != ZZ9K_STATUS_OK || e->e_len < 12)
		return EIO;
	*fwh = zz9k_get_be32(p->handle);
	*arm = zz9k_get_be32(p->arm_addr);
	*len = zz9k_get_be32(p->length);
	if (*fwh == ZZ9K_INVALID_HANDLE)
		return EIO;
	return 0;
}

void
zzw_free_req(struct zzw_entry *e, unsigned long fwh)
{
	ZZ9KFreeSharedPayload *p = (ZZ9KFreeSharedPayload *)e->e_payload;
	int i;

	for (i = 0; i < ZZW_PAYLOAD; i++)
		e->e_payload[i] = 0;
	zz9k_put_be32(p->handle, (uint32_t)fwh);
	e->e_op = ZZ9K_OP_FREE_SHARED;
	e->e_flags = ZZ9K_ENTRY_INLINE_PAYLOAD;
	e->e_len = sizeof(ZZ9KFreeSharedPayload);
}
