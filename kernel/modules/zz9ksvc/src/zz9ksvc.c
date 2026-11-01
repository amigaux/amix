/*
 * zz9ksvc.c -- the core-1 service channel of ZZ9000-family boards: /dev/zz9ksvcN, a
 * demand-class loadable module for both kernel lines.  zz9ksvc/README.md has the whole
 * story; this is the short form.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 *
 * The board comes from zz9kbus (include/zz9kbus.h): at _load, the board of each unit whose
 * bootstrap block and mailbox descriptor check out (src/wire.c) is taken and held.  With
 * none, _load fails ENXIO and the module is not kept, so the open fails ENXIO: the client
 * uses its software path.
 *
 * Every open is a clone: its minor becomes a slot of its own, with its own buffers (handles
 * 0-15), at most ZZS_MAXOUT requests in flight and ZZS_QUOTA bytes.  The kernel builds every
 * mailbox entry: it assigns the request id, lets through only the opcodes src/wire.c lists,
 * and puts the firmware's handle in place of each handle the client names after checking
 * the buffer is this open's and the range used lies inside it.  No address from a client
 * reaches the firmware, and no firmware address reaches a client.
 *
 * Completions are polled from a timeout() callout every clock tick, and only while
 * anything is in flight, quarantined or owed a free.  A wait is bounded, in rounds of
 * ZZS_ROUND ticks, and a signal ends it with EINTR (the request stays, to be waited for
 * again).  A request that times out is orphaned and the buffers it refers to are
 * quarantined: the firmware may still write them, so they are neither freed nor handed
 * out again until its completion arrives or the runtime is reset (ZZSIOC_RESET).  The
 * same happens to an open's buffers when it closes with requests in flight: the closed
 * open stays until they are released.  At most ZZS_NQUAR buffers can be quarantined:
 * a request that could take the count over it is refused with EAGAIN.
 *
 * mmap(2) maps a buffer by its cookie only: the offset encodes the handle and a generation
 * (so a freed and reused handle does not map the new buffer through an old cookie), and
 * d_mmap returns the page of the buffer's physical range that the board driver vouched for
 * (zb_heapphys) or -1.  ZZSIOC_STATS and ZZSIOC_RESET are root's.
 *
 * The callout runs at the clock's level; process-context code takes the tables at spl4.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/errno.h>
#include <sys/file.h>
#include <sys/cred.h>
#include <sys/kmem.h>
#include <sys/immu.h>
#include <sys/conf.h>
#include <sys/ddi.h>
#include <sys/moddefs.h>
#include <sys/amixddi.h>
#include <zz9kbus.h>
#include <sys/zz9ksvc.h>
#include "wire.h"

#define ZZS_MAJOR	55		/* the registry's (kit registry/majors) */
#define ZZS_NOPEN	32		/* opens per unit */
#define ZZS_NREQ	16		/* requests in flight per unit, the kernel's own included */
#define ZZS_NQUAR	32		/* quarantined buffers, all units */
#define ZZS_ROUND	(2 * HZ)	/* the longest single sleep of a wait */
#define ZZS_CLONE(u, s)	(ZZ9KBUS_NUNIT + (u) * ZZS_NOPEN + (s))
#define ZZS_PAGE	NBPP		/* the line's page: 2 KiB on k30, 4 KiB on k46 */
#define ZZS_ROUNDUP(n)	(((n) + ZZS_PAGE - 1) & ~(unsigned long)(ZZS_PAGE - 1))

/* the mmap cookie: generation in bits 28-30, handle + 1 in 23-27, the offset below */
#define ZZS_COOKIE(h, g)	((long)((((g) & 7) << 28) | (((h) + 1) << 23)))
#define ZZS_CK_H(off)		((int)(((off) >> 23) & 0x1f) - 1)
#define ZZS_CK_G(off)		((int)(((off) >> 28) & 7))
#define ZZS_CK_OFF(off)		((unsigned long)(off) & 0x7fffff)

#define ZB_FREE	0
#define ZB_LIVE	1	/* allocated and usable */
#define ZB_QUAR	2	/* a timed-out request refers to it: kept until that completes */
#define ZB_DEAD	3	/* the runtime was reset: gone on the card; the slot waits for FREE */

struct zzs_buf {
	int		b_state;
	int		b_gen;		/* 0-7, in the cookie */
	int		b_busy;		/* requests in flight that refer to it */
	int		b_tofree;	/* free it when it is released */
	unsigned long	b_fwh;		/* the firmware's handle */
	unsigned long	b_len;		/* bytes, a page multiple */
	unsigned long	b_phys;		/* where it lies; 0 for a card-only buffer */
};

struct zzs_open {
	int		o_unit;
	int		o_slot;
	int		o_closed;	/* closed; stays while buffers are quarantined */
	int		o_nout;		/* requests submitted and not yet waited for */
	unsigned long	o_bytes;
	struct zzs_buf	o_buf[ZZS_NHANDLE];
};

#define ZR_FREE		0
#define ZR_OUT		1	/* queued; its open may sleep on it */
#define ZR_DONE		2	/* completed; the reply waits for ZZSIOC_WAIT */
#define ZR_ORPHAN	3	/* timed out or abandoned: its completion only releases */
#define ZR_LOST		4	/* the runtime was reset under it */

#define ZK_USER		0
#define ZK_ALLOC		1	/* the kernel's ALLOC_SHARED for ZZSIOC_ALLOC */
#define ZK_FREE		2	/* the kernel's FREE_SHARED */

struct zzs_req {
	int		q_state;
	int		q_kind;
	unsigned long	q_id;
	struct zzs_open	*q_op;
	int		q_nref;
	int		q_ref[2];	/* handles it refers to */
	struct zzw_entry q_e;		/* the request; the reply once done */
};

struct zzs_unit {
	struct zz9kbus_board *u_bp;	/* held while ready */
	int		u_ready;
	struct zzw_ring	u_ring;
	unsigned long	u_nextid;
	struct zzs_open	*u_open[ZZS_NOPEN];
	struct zzs_req	u_req[ZZS_NREQ];
};

extern int timeout(), untimeout(), sleep(), drv_priv(), copyin(), copyout();
extern void wakeup();
extern caddr_t kmem_zalloc();
extern void kmem_free();
extern clock_t lbolt;

static struct zzs_unit zzs_unit[ZZ9KBUS_NUNIT];
static int zzs_quar;		/* buffers in ZB_QUAR */
static int zzs_reserve;		/* references of client requests in flight */
static int zzs_tickid;		/* the polling callout, 0 when idle */
static struct zzs_stats zzs_st;

static void zzs_tick();

/* ---- tables ---- */

static struct zzs_open *
zzs_open_of(dev)
dev_t dev;
{
	int m = getminor(dev) - ZZ9KBUS_NUNIT;

	if (m < 0 || m >= ZZ9KBUS_NUNIT * ZZS_NOPEN)
		return 0;
	return zzs_unit[m / ZZS_NOPEN].u_open[m % ZZS_NOPEN];
}

static struct zzs_req *
zzs_req_new(up)
struct zzs_unit *up;
{
	int i;

	for (i = 0; i < ZZS_NREQ; i++)
		if (up->u_req[i].q_state == ZR_FREE) {
			bzero((caddr_t)&up->u_req[i], sizeof up->u_req[i]);
			return &up->u_req[i];
		}
	return 0;
}

/* anything for the callout to do */
static int
zzs_pending()
{
	struct zzs_unit *up;
	int u, i, h;

	for (u = 0; u < ZZ9KBUS_NUNIT; u++) {
		up = &zzs_unit[u];
		for (i = 0; i < ZZS_NREQ; i++)
			if (up->u_req[i].q_state == ZR_OUT || up->u_req[i].q_state == ZR_ORPHAN)
				return 1;
		for (i = 0; i < ZZS_NOPEN; i++)
			if (up->u_open[i] != 0) {
				if (up->u_open[i]->o_closed)
					return 1;
				for (h = 0; h < ZZS_NHANDLE; h++)
					if (up->u_open[i]->o_buf[h].b_tofree)
						return 1;
			}
	}
	return 0;
}

static void
zzs_arm()
{
	if (zzs_tickid == 0 && zzs_pending())
		zzs_tickid = timeout(zzs_tick, (caddr_t)0, 1);
}

/* queue rq on unit up: assign its id, put it on the ring, ring the doorbell */
static int
zzs_send(up, rq)
struct zzs_unit *up;
struct zzs_req *rq;
{
	int e;

	if (++up->u_nextid == 0)
		up->u_nextid = 1;
	rq->q_id = up->u_nextid;
	rq->q_e.e_id = rq->q_id;
	rq->q_e.e_cookie = 0;
	if ((e = zzw_put(up->u_bp->zb_mbox, &up->u_ring, &rq->q_e)) != 0)
		return e;
	if (up->u_ring.r_caps & zzw_cap_doorbell)
		(*up->u_bp->zb_doorbell)(up->u_bp->zb_ctx);
	rq->q_state = ZR_OUT;
	zzs_st.zt_submitted++;
	return 0;
}

/* free buffer b of op on the card; if that cannot be queued now, the callout retries */
static void
zzs_kfree(up, op, b)
struct zzs_unit *up;
struct zzs_open *op;
struct zzs_buf *b;
{
	struct zzs_req *rq;

	if (b->b_state != ZB_DEAD) {
		if (!up->u_ready || (rq = zzs_req_new(up)) == 0) {
			b->b_tofree = 1;
			return;
		}
		rq->q_kind = ZK_FREE;
		zzw_free_req(&rq->q_e, b->b_fwh);
		if (zzs_send(up, rq) != 0) {
			rq->q_state = ZR_FREE;
			b->b_tofree = 1;
			return;
		}
	}
	op->o_bytes -= b->b_len;
	b->b_state = ZB_FREE;
	b->b_tofree = 0;
	b->b_busy = 0;
	b->b_gen = (b->b_gen + 1) & 7;
}

/* a request that referred to buffers of op no longer can make the firmware write them */
static void
zzs_unref(up, rq)
struct zzs_unit *up;
struct zzs_req *rq;
{
	struct zzs_buf *b;
	int i;

	for (i = 0; i < rq->q_nref; i++) {
		b = &rq->q_op->o_buf[rq->q_ref[i]];
		if (b->b_busy > 0)
			b->b_busy--;
		if (b->b_busy == 0 && b->b_state == ZB_QUAR) {
			b->b_state = ZB_LIVE;
			zzs_quar--;
			if (rq->q_op->o_closed)
				b->b_tofree = 1;
		}
		if (b->b_busy == 0 && b->b_tofree && b->b_state == ZB_LIVE)
			zzs_kfree(up, rq->q_op, b);
	}
	rq->q_nref = 0;
}

/* a closed open whose buffers are all gone and that no request refers to is freed */
static void
zzs_reap(up)
struct zzs_unit *up;
{
	struct zzs_open *op;
	int s, i, h, busy;

	for (s = 0; s < ZZS_NOPEN; s++) {
		if ((op = up->u_open[s]) == 0 || !op->o_closed)
			continue;
		busy = 0;
		for (h = 0; h < ZZS_NHANDLE; h++)
			if (op->o_buf[h].b_state != ZB_FREE)
				busy = 1;
		for (i = 0; i < ZZS_NREQ; i++)
			if (up->u_req[i].q_state != ZR_FREE && up->u_req[i].q_op == op)
				busy = 1;
		if (!busy) {
			up->u_open[s] = 0;
			kmem_free((caddr_t)op, sizeof *op);
		}
	}
}

/* time out (or abandon) rq: orphan it and quarantine what it refers to */
static void
zzs_orphan(rq)
struct zzs_req *rq;
{
	struct zzs_buf *b;
	int i;

	if (rq->q_kind == ZK_USER) {
		for (i = 0; i < rq->q_nref; i++) {
			b = &rq->q_op->o_buf[rq->q_ref[i]];
			if (b->b_state == ZB_LIVE) {
				b->b_state = ZB_QUAR;
				zzs_quar++;
				zzs_st.zt_quarantined++;
			}
		}
		zzs_reserve -= rq->q_nref;
		rq->q_op->o_nout--;
	}
	rq->q_state = ZR_ORPHAN;
}

/* take every completion unit up has: the callout's work for one unit */
static void
zzs_poll(up)
struct zzs_unit *up;
{
	struct zzw_entry e;
	struct zzs_req *rq;
	unsigned long fwh, arm, len;
	int i, n, s, h;

	if (!up->u_ready)
		return;
	for (n = 0; n < (int)up->u_ring.r_cmpn; n++) {
		if (zzw_take(up->u_bp->zb_mbox, &up->u_ring, &e) != 0)
			break;
		rq = 0;
		for (i = 0; i < ZZS_NREQ; i++)
			if ((up->u_req[i].q_state == ZR_OUT || up->u_req[i].q_state == ZR_ORPHAN) &&
			    up->u_req[i].q_id == e.e_id) {
				rq = &up->u_req[i];
				break;
			}
		if (rq == 0) {
			zzs_st.zt_stray++;
			continue;
		}
		zzs_st.zt_completed++;
		if (rq->q_kind == ZK_FREE) {
			rq->q_state = ZR_FREE;
			continue;
		}
		if (rq->q_state == ZR_ORPHAN) {
			if (rq->q_kind == ZK_ALLOC && zzw_alloc_reply(&e, &fwh, &arm, &len) == 0) {
				/* the buffer a timed-out ZZSIOC_ALLOC got: give it back */
				rq->q_kind = ZK_FREE;
				zzw_free_req(&rq->q_e, fwh);
				if (zzs_send(up, rq) != 0)
					rq->q_state = ZR_FREE;
				continue;
			}
			if (rq->q_kind == ZK_USER)
				zzs_unref(up, rq);
			rq->q_state = ZR_FREE;
			continue;
		}
		rq->q_e = e;
		if (rq->q_kind == ZK_USER) {
			zzs_reserve -= rq->q_nref;
			zzs_unref(up, rq);
		}
		rq->q_state = ZR_DONE;
		wakeup((caddr_t)rq);
	}
	/* frees owed, then closed opens that are done */
	for (s = 0; s < ZZS_NOPEN; s++)
		if (up->u_open[s] != 0)
			for (h = 0; h < ZZS_NHANDLE; h++)
				if (up->u_open[s]->o_buf[h].b_tofree &&
				    up->u_open[s]->o_buf[h].b_busy == 0 &&
				    up->u_open[s]->o_buf[h].b_state == ZB_LIVE)
					zzs_kfree(up, up->u_open[s], &up->u_open[s]->o_buf[h]);
	zzs_reap(up);
}

/*ARGSUSED*/
static void
zzs_tick(arg)
caddr_t arg;
{
	int u;

	zzs_tickid = 0;
	zzs_st.zt_polls++;
	for (u = 0; u < ZZ9KBUS_NUNIT; u++)
		zzs_poll(&zzs_unit[u]);
	zzs_arm();
}

/*
 * Wait at spl4 for rq (of op) to leave ZR_OUT, at most ticks ticks, in rounds.  0: done
 * or lost; EINTR: a signal (rq stays ZR_OUT); ETIMEDOUT: rq is orphaned.
 */
static int
zzs_await(rq, op, ticks)
struct zzs_req *rq;
struct zzs_open *op;
long ticks;
{
	clock_t end = lbolt + ticks;
	long left;
	int id, sig;

	zzs_arm();
	while (rq->q_state == ZR_OUT) {
		left = (long)(end - lbolt);
		if (left <= 0) {
			zzs_orphan(rq);
			zzs_st.zt_timedout++;
			return ETIMEDOUT;
		}
		if (left > ZZS_ROUND)
			left = ZZS_ROUND;
		id = timeout(wakeup, (caddr_t)rq, left);
		sig = sleep((caddr_t)rq, (PZERO + 1) | PCATCH);
		untimeout(id);
		if (sig)
			return EINTR;
	}
	return 0;
}

/* ---- entry points ---- */

/*ARGSUSED*/
static int
zzsopen(devp, flag, otyp, cr)
dev_t *devp;
int flag, otyp;
struct cred *cr;
{
	struct zzs_unit *up;
	struct zzs_open *op;
	int u = getminor(*devp), s, x;

	if (u < 0 || u >= ZZ9KBUS_NUNIT || !zzs_unit[u].u_ready)
		return ENXIO;
	up = &zzs_unit[u];
	if ((op = (struct zzs_open *)kmem_zalloc(sizeof *op, KM_NOSLEEP)) == 0)
		return ENOMEM;
	x = spl4();
	for (s = 0; s < ZZS_NOPEN; s++)
		if (up->u_open[s] == 0)
			break;
	if (s == ZZS_NOPEN) {
		splx(x);
		kmem_free((caddr_t)op, sizeof *op);
		return EAGAIN;
	}
	op->o_unit = u;
	op->o_slot = s;
	up->u_open[s] = op;
	splx(x);
	*devp = makedevice(getmajor(*devp), ZZS_CLONE(u, s));
	return 0;
}

/* the last close of a clone: free its buffers, or quarantine those still in use */
/*ARGSUSED*/
static int
zzsclose(dev, flag, otyp, cr)
dev_t dev;
int flag, otyp;
struct cred *cr;
{
	struct zzs_open *op = zzs_open_of(dev);
	struct zzs_unit *up;
	struct zzs_req *rq;
	int i, h, x;

	if (op == 0 || op->o_closed)
		return 0;
	up = &zzs_unit[op->o_unit];
	x = spl4();
	op->o_closed = 1;
	for (i = 0; i < ZZS_NREQ; i++) {
		rq = &up->u_req[i];
		if (rq->q_state == ZR_FREE || rq->q_op != op)
			continue;
		if (rq->q_state == ZR_OUT)
			zzs_orphan(rq);
		else if (rq->q_state == ZR_DONE || rq->q_state == ZR_LOST)
			rq->q_state = ZR_FREE;
	}
	op->o_nout = 0;
	for (h = 0; h < ZZS_NHANDLE; h++) {
		if (op->o_buf[h].b_state == ZB_LIVE && op->o_buf[h].b_busy == 0)
			zzs_kfree(up, op, &op->o_buf[h]);
		else if (op->o_buf[h].b_state == ZB_DEAD)
			zzs_kfree(up, op, &op->o_buf[h]);
		else if (op->o_buf[h].b_state == ZB_QUAR)
			op->o_buf[h].b_tofree = 1;
	}
	zzs_reap(up);
	zzs_arm();
	splx(x);
	return 0;
}

static int
zzs_alloc(up, op, arg)
struct zzs_unit *up;
struct zzs_open *op;
caddr_t arg;
{
	struct zzs_alloc za;
	struct zzs_req *rq;
	struct zzs_buf *b;
	unsigned long len, fwh, arm, flen, phys = 0;
	int h, e, x;

	if (copyin(arg, (caddr_t)&za, sizeof za))
		return EFAULT;
	if (za.za_length <= 0 || za.za_length > ZZS_QUOTA || (za.za_flags & ~ZZS_ALLOC_CARDONLY))
		return EINVAL;
	len = ZZS_ROUNDUP((unsigned long)za.za_length);
	x = spl4();
	for (h = 0; h < ZZS_NHANDLE; h++)
		if (op->o_buf[h].b_state == ZB_FREE && !op->o_buf[h].b_tofree)
			break;
	if (h == ZZS_NHANDLE || op->o_bytes + len > ZZS_QUOTA) {
		splx(x);
		return ENOSPC;
	}
	if ((rq = zzs_req_new(up)) == 0) {
		splx(x);
		return EAGAIN;
	}
	rq->q_kind = ZK_ALLOC;
	rq->q_op = op;
	zzw_alloc_req(&rq->q_e, len, (unsigned long)ZZS_PAGE, (int)(za.za_flags & ZZS_ALLOC_CARDONLY),
	    up->u_ring.r_caps);
	if ((e = zzs_send(up, rq)) != 0) {
		rq->q_state = ZR_FREE;
		splx(x);
		return e;
	}
	if ((e = zzs_await(rq, op, (long)ZZS_WAITMS * HZ / 1000)) != 0) {
		if (e == EINTR)
			zzs_orphan(rq);	/* its completion gives the buffer back */
		splx(x);
		return e;
	}
	if (rq->q_state == ZR_LOST) {
		rq->q_state = ZR_FREE;
		splx(x);
		return EIO;
	}
	e = zzw_alloc_reply(&rq->q_e, &fwh, &arm, &flen);
	rq->q_state = ZR_FREE;
	if (e != 0) {
		splx(x);
		return zzw_errno(rq->q_e.e_status) ? zzw_errno(rq->q_e.e_status) : EIO;
	}
	b = &op->o_buf[h];
	b->b_fwh = fwh;
	b->b_len = len;
	b->b_phys = 0;
	b->b_busy = 0;
	b->b_tofree = 0;
	b->b_state = ZB_LIVE;
	op->o_bytes += len;
	/* a mappable buffer must lie, whole and page-aligned, in the host-visible heap */
	if (flen < len || (!(za.za_flags & ZZS_ALLOC_CARDONLY) &&
	    ((*up->u_bp->zb_heapphys)(up->u_bp->zb_ctx, arm, len, &phys) != 0 ||
	    phys == 0 || (phys & (ZZS_PAGE - 1)) != 0))) {
		zzs_kfree(up, op, b);
		zzs_arm();
		splx(x);
		return EIO;
	}
	if (!(za.za_flags & ZZS_ALLOC_CARDONLY))
		b->b_phys = phys;
	splx(x);
	za.za_length = len;
	za.za_handle = h;
	za.za_cookie = (za.za_flags & ZZS_ALLOC_CARDONLY) ? -1 : ZZS_COOKIE(h, b->b_gen);
	if (copyout((caddr_t)&za, arg, sizeof za))
		return EFAULT;
	return 0;
}

static int
zzs_submit(up, op, arg, cr)
struct zzs_unit *up;
struct zzs_open *op;
caddr_t arg;
struct cred *cr;
{
	struct zzs_submit zs;
	struct zzw_refs rf;
	struct zzs_req *rq;
	struct zzs_buf *b;
	unsigned long h, off, len;
	int i, e, x, kind;

	if (copyin(arg, (caddr_t)&zs, sizeof zs))
		return EFAULT;
	if (zs.zs_len < 0 || zs.zs_len > ZZS_PAYLOAD)
		return EINVAL;
	kind = zzw_policy((unsigned long)zs.zs_opcode, &rf);
	if (kind == ZZW_DENY)
		return EINVAL;
	if (kind == ZZW_PRIV && (e = drv_priv(cr)) != 0)
		return e;
	x = spl4();
	/* every reference: this open's live buffer, the range inside it */
	for (i = 0; i < rf.rf_n; i++) {
		h = zzw_get32(zs.zs_payload + rf.rf_hoff[i]);
		off = zzw_get32(zs.zs_payload + rf.rf_ooff[i]);
		len = zzw_get32(zs.zs_payload + rf.rf_loff[i]);
		if (h >= ZZS_NHANDLE || op->o_buf[h].b_state != ZB_LIVE || op->o_buf[h].b_tofree) {
			splx(x);
			return EBADF;
		}
		b = &op->o_buf[h];
		if (off > b->b_len || len > b->b_len - off) {
			splx(x);
			return EINVAL;
		}
	}
	if (op->o_nout >= ZZS_MAXOUT || zzs_quar + zzs_reserve + rf.rf_n > ZZS_NQUAR ||
	    (rq = zzs_req_new(up)) == 0) {
		splx(x);
		return EAGAIN;
	}
	rq->q_kind = ZK_USER;
	rq->q_op = op;
	rq->q_e.e_op = zs.zs_opcode;
	rq->q_e.e_flags = zzw_inline_flag;
	rq->q_e.e_len = zs.zs_len;
	bcopy((caddr_t)zs.zs_payload, (caddr_t)rq->q_e.e_payload, ZZS_PAYLOAD);
	for (i = 0; i < rf.rf_n; i++) {
		h = zzw_get32(zs.zs_payload + rf.rf_hoff[i]);
		rq->q_ref[i] = h;
		zzw_put32(rq->q_e.e_payload + rf.rf_hoff[i], op->o_buf[h].b_fwh);
	}
	if ((e = zzs_send(up, rq)) != 0) {
		rq->q_state = ZR_FREE;
		splx(x);
		return e;
	}
	rq->q_nref = rf.rf_n;
	for (i = 0; i < rf.rf_n; i++)
		op->o_buf[rq->q_ref[i]].b_busy++;
	zzs_reserve += rf.rf_n;
	op->o_nout++;
	zzs_arm();
	splx(x);
	zs.zs_id = rq->q_id;
	if (copyout((caddr_t)&zs, arg, sizeof zs))
		return EFAULT;
	return 0;
}

static int
zzs_wait(up, op, arg)
struct zzs_unit *up;
struct zzs_open *op;
caddr_t arg;
{
	struct zzs_wait zw;
	struct zzs_req *rq;
	long ticks;
	int i, e, x;

	if (copyin(arg, (caddr_t)&zw, sizeof zw))
		return EFAULT;
	if (zw.zw_ms < 0 || zw.zw_ms > 600000)
		return EINVAL;
	ticks = (zw.zw_ms ? zw.zw_ms : ZZS_WAITMS) * HZ / 1000;
	if (ticks < 1)
		ticks = 1;
	x = spl4();
	rq = 0;
	for (i = 0; i < ZZS_NREQ; i++)
		if (up->u_req[i].q_kind == ZK_USER && up->u_req[i].q_op == op &&
		    up->u_req[i].q_id == (unsigned long)zw.zw_id &&
		    (up->u_req[i].q_state == ZR_OUT || up->u_req[i].q_state == ZR_DONE ||
		    up->u_req[i].q_state == ZR_LOST))
			rq = &up->u_req[i];
	if (rq == 0) {
		splx(x);
		return EINVAL;
	}
	if ((e = zzs_await(rq, op, ticks)) != 0) {
		splx(x);
		return e;
	}
	if (rq->q_state == ZR_LOST) {
		rq->q_state = ZR_FREE;
		op->o_nout--;
		splx(x);
		return EIO;
	}
	zw.zw_status = rq->q_e.e_status;
	zw.zw_len = rq->q_e.e_len;
	bcopy((caddr_t)rq->q_e.e_payload, (caddr_t)zw.zw_payload, ZZS_PAYLOAD);
	rq->q_state = ZR_FREE;
	op->o_nout--;
	splx(x);
	if (copyout((caddr_t)&zw, arg, sizeof zw))
		return EFAULT;
	return 0;
}

/* the runtime restarted: everything it held is gone; check the descriptor again */
static void
zzs_reset(up)
struct zzs_unit *up;
{
	struct zzs_open *op;
	struct zzs_req *rq;
	int i, s, h;

	for (i = 0; i < ZZS_NREQ; i++) {
		rq = &up->u_req[i];
		if (rq->q_state == ZR_OUT || rq->q_state == ZR_DONE) {
			if (rq->q_kind == ZK_USER && rq->q_state == ZR_OUT)
				zzs_reserve -= rq->q_nref;
			if (rq->q_kind == ZK_USER) {
				rq->q_state = ZR_LOST;
				wakeup((caddr_t)rq);
			} else {
				rq->q_state = rq->q_kind == ZK_ALLOC ? ZR_LOST : ZR_FREE;
				wakeup((caddr_t)rq);
			}
		} else if (rq->q_state == ZR_ORPHAN)
			rq->q_state = ZR_FREE;
		rq->q_nref = 0;
	}
	for (s = 0; s < ZZS_NOPEN; s++) {
		if ((op = up->u_open[s]) == 0)
			continue;
		for (h = 0; h < ZZS_NHANDLE; h++) {
			if (op->o_buf[h].b_state == ZB_QUAR)
				zzs_quar--;
			if (op->o_buf[h].b_state != ZB_FREE) {
				op->o_buf[h].b_state = op->o_closed ? ZB_FREE : ZB_DEAD;
				op->o_bytes -= op->o_closed ? op->o_buf[h].b_len : 0;
				op->o_buf[h].b_busy = 0;
				op->o_buf[h].b_tofree = 0;
				op->o_buf[h].b_gen = (op->o_buf[h].b_gen + 1) & 7;
			}
		}
	}
	zzs_reap(up);
	if (zzw_attach(up->u_bp->zb_mbox, up->u_bp->zb_mboxlen, &up->u_ring) != 0)
		up->u_ready = 0;
}

/*ARGSUSED*/
static int
zzsioctl(dev, cmd, arg, mode, cr, rvp)
dev_t dev;
int cmd;
caddr_t arg;
int mode;
struct cred *cr;
int *rvp;
{
	struct zzs_open *op = zzs_open_of(dev);
	struct zzs_unit *up;
	struct zzs_info zi;
	struct zzs_stats zt;
	int e, x, u, s, h;

	if (op == 0 || op->o_closed)
		return ENXIO;
	up = &zzs_unit[op->o_unit];
	switch (cmd) {
	case ZZSIOC_INFO:
		bzero((caddr_t)&zi, sizeof zi);
		zi.zi_unit = op->o_unit;
		zi.zi_id = up->u_bp ? up->u_bp->zb_id : 0;
		zi.zi_abimajor = up->u_ring.r_major;
		zi.zi_abiminor = up->u_ring.r_minor;
		zi.zi_caps = up->u_ring.r_caps;
		zi.zi_reqn = up->u_ring.r_reqn;
		zi.zi_cmpn = up->u_ring.r_cmpn;
		zi.zi_nhandle = ZZS_NHANDLE;
		zi.zi_maxout = ZZS_MAXOUT;
		zi.zi_quota = ZZS_QUOTA;
		zi.zi_used = op->o_bytes;
		return copyout((caddr_t)&zi, arg, sizeof zi) ? EFAULT : 0;
	case ZZSIOC_ALLOC:
		return up->u_ready ? zzs_alloc(up, op, arg) : ENXIO;
	case ZZSIOC_FREE:
		h = (int)arg;
		if (h < 0 || h >= ZZS_NHANDLE || op->o_buf[h].b_state == ZB_FREE ||
		    op->o_buf[h].b_tofree)
			return EINVAL;
		x = spl4();
		if (op->o_buf[h].b_busy > 0 && op->o_buf[h].b_state == ZB_LIVE) {
			splx(x);
			return EBUSY;
		}
		if (op->o_buf[h].b_state == ZB_QUAR)
			op->o_buf[h].b_tofree = 1;
		else
			zzs_kfree(up, op, &op->o_buf[h]);
		zzs_arm();
		splx(x);
		return 0;
	case ZZSIOC_SUBMIT:
		return up->u_ready ? zzs_submit(up, op, arg, cr) : ENXIO;
	case ZZSIOC_WAIT:
		return zzs_wait(up, op, arg);
	case ZZSIOC_STATS:
		if ((e = drv_priv(cr)) != 0)
			return e;
		x = spl4();
		zt = zzs_st;
		zt.zt_quar = zzs_quar;
		zt.zt_opens = 0;
		for (u = 0; u < ZZ9KBUS_NUNIT; u++)
			for (s = 0; s < ZZS_NOPEN; s++)
				if (zzs_unit[u].u_open[s] != 0)
					zt.zt_opens++;
		splx(x);
		return copyout((caddr_t)&zt, arg, sizeof zt) ? EFAULT : 0;
	case ZZSIOC_RESET:
		if ((e = drv_priv(cr)) != 0)
			return e;
		if (up->u_bp == 0)
			return ENXIO;
		x = spl4();
		zzs_reset(up);
		splx(x);
		return up->u_ready ? 0 : ENXIO;
	}
	return EINVAL;
}

/* a page of a buffer this open holds, by cookie; -1 for anything else */
/*ARGSUSED*/
static int
zzsmmap(dev, off, prot)
dev_t dev;
off_t off;
int prot;
{
	struct zzs_open *op = zzs_open_of(dev);
	struct zzs_buf *b;
	int h;

	if (op == 0 || op->o_closed || off < 0)
		return -1;
	h = ZZS_CK_H(off);
	if (h < 0 || h >= ZZS_NHANDLE)
		return -1;
	b = &op->o_buf[h];
	if (b->b_state != ZB_LIVE || b->b_tofree || b->b_phys == 0 || b->b_gen != ZZS_CK_G(off) ||
	    ZZS_CK_OFF(off) >= b->b_len)
		return -1;
	return (int)phystopfn(b->b_phys + ZZS_CK_OFF(off));
}

static int
zz9ksvc_load(params)
char *params;
{
	struct zz9kbus_board *bp;
	struct zzs_unit *up;
	int u, n = 0;

	for (u = 0; u < ZZ9KBUS_NUNIT; u++) {
		up = &zzs_unit[u];
		if ((bp = zz9kbus_get(u)) == 0)
			continue;
		if (bp->zb_mbox == 0 || (*bp->zb_bread)(bp->zb_ctx, 0) != zzw_boot_magic ||
		    zzw_attach(bp->zb_mbox, bp->zb_mboxlen, &up->u_ring) != 0) {
			zz9kbus_put(bp);
			continue;
		}
		up->u_bp = bp;
		up->u_nextid = 0;
		up->u_ready = 1;
		n++;
	}
	return n ? 0 : ENXIO;
}

/* unload=allowed: refused while any open, closed opens waiting included, or request remains */
static int
zz9ksvc_unload()
{
	struct zzs_unit *up;
	int u, i;

	for (u = 0; u < ZZ9KBUS_NUNIT; u++) {
		up = &zzs_unit[u];
		for (i = 0; i < ZZS_NOPEN; i++)
			if (up->u_open[i] != 0)
				return EBUSY;
		for (i = 0; i < ZZS_NREQ; i++)
			if (up->u_req[i].q_state != ZR_FREE)
				return EBUSY;
	}
	if (zzs_tickid != 0) {
		untimeout(zzs_tickid);
		zzs_tickid = 0;
	}
	for (u = 0; u < ZZ9KBUS_NUNIT; u++) {
		up = &zzs_unit[u];
		if (up->u_bp != 0)
			zz9kbus_put(up->u_bp);
		up->u_bp = 0;
		up->u_ready = 0;
	}
	return 0;
}

struct mod_drv_data zz9ksvc_drvdata[] = {
	{ { 0 }, 0, 0,
	  { zzsopen, zzsclose, 0, 0, zzsioctl, zzsmmap },
	  ZZS_MAJOR, 1 }
};

/* _halt: none: the board driver owns the board and stops it */
MOD_DRV_WRAPPER(zz9ksvc, zz9ksvc_load, zz9ksvc_unload, 0, "ZZ9000-family service channel /dev/zz9ksvcN");
