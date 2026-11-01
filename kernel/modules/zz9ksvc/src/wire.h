/*
 * wire.h -- what src/wire.c (the only file that includes the ZZ9000 SDK headers,
 * compiled as ANSI C) gives the rest of zz9ksvc (compiled -traditional with the
 * kernel headers): the mailbox protocol and the request policy, in plain types.
 * Calls across the two use int, long and pointers only.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 */
#ifndef ZZ9KSVC_WIRE_H
#define ZZ9KSVC_WIRE_H

#define ZZW_PAYLOAD	48	/* bytes of an entry's payload */

/* an entry in host order */
struct zzw_entry {
	unsigned long	e_id;		/* request_id */
	unsigned long	e_op;		/* opcode */
	unsigned long	e_status;
	unsigned long	e_flags;
	unsigned long	e_len;		/* payload_len */
	unsigned long	e_cookie;	/* user_cookie */
	unsigned char	e_payload[ZZW_PAYLOAD];	/* big-endian, as on the wire */
};

/* the rings, from a checked descriptor */
struct zzw_ring {
	unsigned long	r_reqoff, r_reqn;	/* request ring: byte offset, entries */
	unsigned long	r_cmpoff, r_cmpn;	/* completion ring */
	unsigned long	r_caps;			/* capability_bits */
	unsigned long	r_major, r_minor;	/* ABI version */
};

/* what a request may carry, by opcode (zzw_policy) */
#define ZZW_DENY	0	/* not allowed through the node */
#define ZZW_PLAIN	1	/* inline payload, no buffer references */
#define ZZW_PRIV	2	/* as PLAIN, for root only */
#define ZZW_REFS	3	/* carries buffer references: rf_n of them */

struct zzw_refs {
	int	rf_n;		/* references, at most 2 */
	int	rf_hoff[2];	/* payload offset of the handle (4 bytes) */
	int	rf_ooff[2];	/* of the byte offset into the buffer */
	int	rf_loff[2];	/* of the byte length from there */
};

/* errnos the protocol functions return; 0 is success */
extern int zzw_attach();	/* (mbox, len, ring): 0, ENXIO (no runtime), EIO (bad descriptor) */
extern int zzw_put();		/* (mbox, ring, entry): 0, EAGAIN (ring full), EIO (bad cursor) */
extern int zzw_take();		/* (mbox, ring, entry): 0, EAGAIN (ring empty), EIO (bad cursor) */
extern int zzw_policy();	/* (op, refs): ZZW_DENY .. ZZW_REFS */
extern int zzw_errno();		/* (status): an errno for a firmware status, 0 for OK */
extern unsigned long zzw_get32();	/* (p): the big-endian word at p */
extern void zzw_put32();	/* (p, v) */
extern void zzw_alloc_req();	/* (entry, len, align, cardonly, caps): an ALLOC_SHARED request */
extern int zzw_alloc_reply();	/* (entry, fwh, arm, len): 0 or EIO */
extern void zzw_free_req();	/* (entry, fwh): a FREE_SHARED request */
extern unsigned long zzw_boot_magic;	/* the bootstrap block's first register */
extern unsigned long zzw_inline_flag;	/* the entry flag for an inline payload */
extern unsigned long zzw_cap_doorbell;	/* the capability bit: ring the doorbell */

#endif /* ZZ9KSVC_WIRE_H */
