/*
 * sys/zz9ksvc.h -- the ioctl interface of /dev/zz9ksvcN, the core-1 service channel of a
 * ZZ9000-family board (zz9ksvc(7)).
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 *
 * Each open is its own client: it has up to ZZS_NHANDLE buffers, ZZS_MAXOUT requests in
 * flight and ZZS_QUOTA bytes of buffers.  A buffer is named by its handle, 0 ..
 * ZZS_NHANDLE - 1, never by an address; mmap(2) maps one by the cookie ZZSIOC_ALLOC gave
 * (MAP_SHARED, offset = cookie + a page-aligned offset into it).  In a request payload
 * (the firmware's big-endian layout for the opcode) a buffer reference is the handle in
 * the firmware handle's place; the kernel checks it and the range used, and puts the
 * firmware's handle there.  When the board, its bootstrap block or its runtime is
 * missing, open(2) gives ENXIO: use the software path.
 */
#ifndef _SYS_ZZ9KSVC_H
#define _SYS_ZZ9KSVC_H

#define ZZS_NHANDLE	16		/* buffers per open */
#define ZZS_MAXOUT	4		/* requests in flight per open */
#define ZZS_QUOTA	(8L * 1024 * 1024)	/* bytes of buffers per open */
#define ZZS_PAYLOAD	48		/* bytes of a request or reply payload */
#define ZZS_WAITMS	10000		/* ZZSIOC_WAIT's default bound, in ms */

#define ZZSIOC		('z' << 8)
#define ZZSIOC_INFO	(ZZSIOC | 1)	/* struct zzs_info *: out */
#define ZZSIOC_ALLOC	(ZZSIOC | 2)	/* struct zzs_alloc *: in, out */
#define ZZSIOC_FREE	(ZZSIOC | 3)	/* int: the handle */
#define ZZSIOC_SUBMIT	(ZZSIOC | 4)	/* struct zzs_submit *: in, out */
#define ZZSIOC_WAIT	(ZZSIOC | 5)	/* struct zzs_wait *: in, out */
#define ZZSIOC_STATS	(ZZSIOC | 6)	/* struct zzs_stats *: out; root only */
#define ZZSIOC_RESET	(ZZSIOC | 7)	/* none; root only: forget the runtime's state */

struct zzs_info {
	long	zi_unit;
	long	zi_id;		/* board id: manufacturer << 16 | product */
	long	zi_abimajor, zi_abiminor;
	long	zi_caps;	/* the descriptor's capability bits */
	long	zi_reqn, zi_cmpn;	/* ring sizes */
	long	zi_nhandle, zi_maxout, zi_quota;	/* this open's limits */
	long	zi_used;	/* bytes of buffers this open holds */
};

#define ZZS_ALLOC_CARDONLY	1	/* the buffer stays on the card: no mmap */

struct zzs_alloc {
	long	za_length;	/* in: bytes; out: bytes allocated (page multiple) */
	long	za_flags;	/* in: ZZS_ALLOC_* */
	long	za_handle;	/* out */
	long	za_cookie;	/* out: mmap offset of the buffer's first byte, or -1 */
};

struct zzs_submit {
	long		zs_opcode;
	long		zs_len;		/* payload bytes, at most ZZS_PAYLOAD */
	unsigned char	zs_payload[ZZS_PAYLOAD];
	long		zs_id;		/* out: the request, for ZZSIOC_WAIT */
};

struct zzs_wait {
	long		zw_id;		/* in */
	long		zw_ms;		/* in: bound in ms, 0 = ZZS_WAITMS */
	long		zw_status;	/* out: the firmware's status */
	long		zw_len;		/* out: reply payload bytes */
	unsigned char	zw_payload[ZZS_PAYLOAD];	/* out */
};

struct zzs_stats {
	long	zt_submitted, zt_completed, zt_timedout, zt_quarantined;
	long	zt_stray;	/* completions that matched no request */
	long	zt_polls;	/* clock ticks spent polling */
	long	zt_opens;	/* opens now, closed ones still holding buffers included */
	long	zt_quar;	/* buffers in quarantine now */
};

#endif /* _SYS_ZZ9KSVC_H */
