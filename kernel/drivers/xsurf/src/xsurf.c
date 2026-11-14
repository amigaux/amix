/*
 * xsurf.c -- Individual Computers X-Surf and X-Surf-100 ethernet for Amix:
 * the STREAMS/DLPI provider, interrupts, the tick and the module's entry
 * points.  The chip work is in xs_core.c, the cards' access in xs_boards.c.
 *
 * DLPI: a Style 1 connectionless ethernet provider, as the system's
 * network set-up expects of every ethernet driver (ifup, dhcpc).  Minor
 * number: board in the low nibble, stream slot + 1 in the high one, which
 * the open rewrites (the stock aen driver's scheme, so slink's two opens
 * of /dev/xsf0 get two streams).
 *
 * INTERRUPTS.  The module parameter intr selects them: 2 (the default) puts
 * a handler on the level-2 chain at load, checks it with a real interrupt
 * from the board (a one-word remote read with only RDC unmasked), and only
 * then unmasks the chip's events; 0, or a failed attach or self-test, polls
 * from the tick.  In interrupt mode the tick still runs: it watches for an
 * interrupt that has stopped (events waiting and no claim for XS_STUCK_TICKS
 * ticks), and then masks the chip and polls from then on, saying so once.
 *
 * LEVELS.  Every chip access and the shared state run at IPL 4 (splxs()):
 * the level-2 handler raises to it, the tick runs there, and the write side
 * raises to it around the chip.  IPL 4 holds off level 2 and the clock, so
 * none of them interleaves with another.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "xsk.h"
#include "xsurf.h"

#define XS_MAJOR	56	/* the registry's c 56 xsurf; = .moddata majors */
#define blklen(m)	((int)((m)->b_wptr - (m)->b_rptr))

static int	xsopen(), xsclose(), xswput(), xswsrv();
static int	xs_proto(), xs_xmit(), xs_intr();
static void	xs_ioctl(), xs_wdrain(), xs_tick();

static struct module_info xs_minfo = {
    0x7873, "xsf", XS_ETHERMIN, XS_ETHERMTU, XS_HIWAT, XS_LOWAT,
};
static struct qinit xs_rinit = {
    NULL, NULL, xsopen, xsclose, NULL, &xs_minfo, NULL,
};
static struct qinit xs_winit = {
    xswput, xswsrv, NULL, NULL, NULL, &xs_minfo, NULL,
};
struct streamtab xsurfinfo = {
    &xs_rinit, &xs_winit, NULL, NULL,
};

xs_board_t	xs_board[XS_MAXBOARDS] = { { 0 } };
int		xs_nboards = 0;
static int	xs_tick_id, xs_tick_on;
static long	xs_intr_param;
static unsigned char xs_bcast[XS_ETHERADDRL] = {
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
};
/* the frame being sent: 14 + 1500, and one byte for the even DMA count */
static unsigned char xs_txbuf[XS_ETHERHDR + XS_ETHERMTU + 2];

/* ------------------------------------------------------------------------
 * open and close
 * --------------------------------------------------------------------- */
static int
xsopen(q, devp, flag, sflag, credp)
queue_t *q;
dev_t *devp;
int flag, sflag;
cred_t *credp;
{
    int minor_device, bi, si, s;
    xs_board_t *b;
    xs_stream_t *sp;

    if (sflag == MODOPEN || sflag == CLONEOPEN)
	return EINVAL;
    minor_device = getminor(*devp);
    bi = minor_device & 0x0f;
    si = (minor_device & 0xf0) >> 4;
    if (bi >= xs_nboards || !xs_board[bi].present)
	return ENXIO;		/* no such board: ifup stops here at once */
    b = &xs_board[bi];

    s = splxs();
    if (si == 0) {
	for (si = 0; si < XS_MAXDEV; si++)
	    if (b->s[si].q == NULL)
		break;
    } else
	si--;
    if (si >= XS_MAXDEV) {
	splx(s);
	return ENOSPC;
    }
    sp = &b->s[si];
    if (sp->q) {
	splx(s);
	return EBUSY;
    }
    q->q_ptr = (char *)sp;
    WR(q)->q_ptr = (char *)sp;
    sp->board = bi;
    sp->state = DL_UNBOUND;
    sp->sap = 0;
    sp->q = q;			/* last: the delivery routes on it */
    b->ifs.ifs_active = 1;
    splx(s);

    *devp = makedevice(getmajor(*devp), ((si + 1) << 4) | bi);
    return 0;
}

static int
xsclose(q)
queue_t *q;
{
    xs_stream_t *sp = (xs_stream_t *)q->q_ptr;
    xs_board_t *b;
    int i, s;

    if (sp == NULL)
	return 0;
    b = &xs_board[sp->board];
    s = splxs();
    sp->q = NULL;
    sp->state = DL_UNBOUND;
    sp->sap = 0;
    q->q_ptr = NULL;
    WR(q)->q_ptr = NULL;
    for (i = 0; i < XS_MAXDEV; i++)
	if (b->s[i].q)
	    break;
    if (i >= XS_MAXDEV)
	b->ifs.ifs_active = 0;
    splx(s);
    return 0;
}

/* ------------------------------------------------------------------------
 * the write side
 * --------------------------------------------------------------------- */
static int
xswput(q, mp)
queue_t *q;
mblk_t *mp;
{
    switch (mp->b_datap->db_type) {
    case M_FLUSH:
	if (*mp->b_rptr & FLUSHW) {
	    flushq(q, FLUSHALL);
	    *mp->b_rptr &= ~FLUSHW;
	}
	if (*mp->b_rptr & FLUSHR)
	    qreply(q, mp);
	else
	    freemsg(mp);
	break;

    case M_PROTO:
    case M_PCPROTO:
	/* behind what is queued, in order; queued when it must wait */
	if (q->q_first || !xs_proto(q, mp))
	    putq(q, mp);
	break;

    case M_IOCTL:
    case M_IOCDATA:
	xs_ioctl(q, mp);
	break;

    default:
	freemsg(mp);
	break;
    }
    return 0;
}

static int
xswsrv(q)
queue_t *q;
{
    xs_wdrain(q);
    return 0;
}

/*
 * Run a write queue: each message is handled or, when it must wait (both
 * transmit slots busy, or no memory for an acknowledgement), put back at
 * the head and the queue left.  The tick and a transmit completion call
 * this again, so nothing waits for a back-enable.
 */
static void
xs_wdrain(q)
queue_t *q;
{
    mblk_t *mp;

    while ((mp = getq(q)) != NULL) {
	if (!xs_proto(q, mp)) {
	    putbq(q, mp);
	    break;
	}
    }
}

/* a transmit slot came free (xs_core.c): run every stream's write queue */
void
xs_tx_restart(b)
xs_board_t *b;
{
    int i;

    for (i = 0; i < XS_MAXDEV; i++)
	if (b->s[i].q && WR(b->s[i].q)->q_first)
	    xs_wdrain(WR(b->s[i].q));
}

/* ------------------------------------------------------------------------
 * DLPI
 * --------------------------------------------------------------------- */

/* DL_OK_ACK; 0 when there is no memory (the request waits) */
static int
xs_ok_ack(q, mp, prim)
queue_t *q;
mblk_t *mp;
unsigned long prim;
{
    mblk_t *a;
    dl_ok_ack_t *ok;

    if ((a = allocb(sizeof(dl_ok_ack_t), BPRI_MED)) == NULL)
	return 0;
    a->b_datap->db_type = M_PCPROTO;
    ok = (dl_ok_ack_t *)a->b_wptr;
    ok->dl_primitive = DL_OK_ACK;
    ok->dl_correct_primitive = prim;
    a->b_wptr += sizeof(dl_ok_ack_t);
    freemsg(mp);
    qreply(q, a);
    return 1;
}

/* DL_ERROR_ACK; 0 when there is no memory */
static int
xs_error_ack(q, mp, prim, err)
queue_t *q;
mblk_t *mp;
unsigned long prim, err;
{
    mblk_t *a;
    dl_error_ack_t *e;

    if ((a = allocb(sizeof(dl_error_ack_t), BPRI_MED)) == NULL)
	return 0;
    a->b_datap->db_type = M_PCPROTO;
    e = (dl_error_ack_t *)a->b_wptr;
    e->dl_primitive = DL_ERROR_ACK;
    e->dl_error_primitive = prim;
    e->dl_errno = err;
    e->dl_unix_errno = 0;
    a->b_wptr += sizeof(dl_error_ack_t);
    freemsg(mp);
    qreply(q, a);
    return 1;
}

/*
 * One DLPI request.  1 when it is done with (answered, sent or dropped),
 * 0 when it must wait and stays the caller's, untouched.  State changes
 * only once the answer exists, so a request that waits and is retried
 * acts once.
 */
static int
xs_proto(q, mp)
queue_t *q;
mblk_t *mp;
{
    xs_stream_t *sp = (xs_stream_t *)q->q_ptr;
    xs_board_t *b;
    unsigned long prim;

    if (sp == NULL || blklen(mp) < (int)sizeof(unsigned long)) {
	freemsg(mp);
	return 1;
    }
    b = &xs_board[sp->board];
    prim = ((union DL_primitives *)mp->b_rptr)->dl_primitive;

    switch (prim) {
    case DL_UNITDATA_REQ:
	return xs_xmit(q, b, sp, mp);

    case DL_ATTACH_REQ:
    case DL_DETACH_REQ:
	/* Style 1: nothing to attach; acknowledged, as the clients expect */
	return xs_ok_ack(q, mp, prim);

    case DL_UNBIND_REQ:
	if (!xs_ok_ack(q, mp, prim))
	    return 0;
	sp->state = DL_UNBOUND;
	sp->sap = 0;
	return 1;

    case DL_BIND_REQ:
    {
	dl_bind_req_t *req = (dl_bind_req_t *)mp->b_rptr;
	dl_bind_ack_t *ack;
	mblk_t *a;
	unsigned long sap;

	if (blklen(mp) < (int)sizeof(dl_bind_req_t))
	    return xs_error_ack(q, mp, prim, (unsigned long)DL_BADPRIM);
	sap = req->dl_sap;
	if (sap > 0xffff)
	    return xs_error_ack(q, mp, prim, (unsigned long)DL_BADSAP);
	if ((a = allocb(sizeof(dl_bind_ack_t) + XS_ETHERADDRL, BPRI_MED)) == NULL)
	    return 0;
	a->b_datap->db_type = M_PCPROTO;
	ack = (dl_bind_ack_t *)a->b_wptr;
	ack->dl_primitive = DL_BIND_ACK;
	ack->dl_sap = sap;
	ack->dl_addr_length = XS_ETHERADDRL;
	ack->dl_addr_offset = sizeof(dl_bind_ack_t);
	ack->dl_max_conind = 0;
	ack->dl_growth = 0;
	a->b_wptr += sizeof(dl_bind_ack_t);
	bcopy((caddr_t)b->mac, (caddr_t)a->b_wptr, XS_ETHERADDRL);
	a->b_wptr += XS_ETHERADDRL;
	sp->sap = (unsigned short)sap;
	sp->state = DL_IDLE;
	freemsg(mp);
	qreply(q, a);
	return 1;
    }

    case DL_INFO_REQ:
    {
	dl_info_ack_t *ack;
	mblk_t *a;

	if ((a = allocb(sizeof(dl_info_ack_t) + XS_ETHERADDRL, BPRI_MED)) == NULL)
	    return 0;
	a->b_datap->db_type = M_PCPROTO;
	ack = (dl_info_ack_t *)a->b_wptr;
	bzero((caddr_t)ack, sizeof(dl_info_ack_t));
	ack->dl_primitive = DL_INFO_ACK;
	ack->dl_max_sdu = XS_ETHERMTU;
	ack->dl_min_sdu = 1;
	ack->dl_addr_length = XS_ETHERADDRL;
	ack->dl_mac_type = DL_ETHER;
	ack->dl_current_state = sp->state;
	ack->dl_max_idu = XS_ETHERMTU;
	ack->dl_service_mode = DL_CLDLS;
	ack->dl_provider_style = DL_STYLE1;
	a->b_wptr += sizeof(dl_info_ack_t);
	if (sp->state == DL_IDLE) {
	    ack->dl_addr_offset = sizeof(dl_info_ack_t);
	    bcopy((caddr_t)b->mac, (caddr_t)a->b_wptr, XS_ETHERADDRL);
	    a->b_wptr += XS_ETHERADDRL;
	}
	freemsg(mp);
	qreply(q, a);
	return 1;
    }

    default:
	return xs_error_ack(q, mp, prim, (unsigned long)DL_BADPRIM);
    }
}

/*
 * DL_UNITDATA_REQ: a 6-byte destination inside the request block, the type
 * from the stream's bound SAP, the data from the M_DATA blocks (at most
 * 1500 bytes), padded with zeros to 60.  A malformed request or one on an
 * unbound stream is dropped and counted.  0 when both slots are busy.
 */
static int
xs_xmit(q, b, sp, mp)
queue_t *q;
xs_board_t *b;
xs_stream_t *sp;
mblk_t *mp;
{
    dl_unitdata_req_t *dp = (dl_unitdata_req_t *)mp->b_rptr;
    unsigned long off;
    mblk_t *m;
    int s, len, room, n;

    if (blklen(mp) < (int)sizeof(dl_unitdata_req_t) ||
	dp->dl_dest_addr_length < XS_ETHERADDRL) {
	b->st.tx_bad_req++;
	b->ifs.ifs_oerrors++;
	freemsg(mp);
	return 1;
    }
    off = dp->dl_dest_addr_offset;
    if (off > (unsigned long)(blklen(mp) - XS_ETHERADDRL)) {
	b->st.tx_bad_req++;
	b->ifs.ifs_oerrors++;
	freemsg(mp);
	return 1;
    }
    if (sp->state != DL_IDLE) {
	b->st.tx_unbound++;
	b->ifs.ifs_oerrors++;
	freemsg(mp);
	return 1;
    }

    s = splxs();
    if (!b->running) {
	splx(s);
	b->ifs.ifs_oerrors++;
	freemsg(mp);
	return 1;
    }
    if (xs_tx_free(b) < 0) {
	splx(s);
	return 0;
    }
    bcopy((caddr_t)mp->b_rptr + off, (caddr_t)&xs_txbuf[0], XS_ETHERADDRL);
    bcopy((caddr_t)b->mac, (caddr_t)&xs_txbuf[6], XS_ETHERADDRL);
    xs_txbuf[12] = (sp->sap >> 8) & 0xff;
    xs_txbuf[13] = sp->sap & 0xff;
    len = XS_ETHERHDR;
    room = XS_ETHERMTU;
    for (m = mp->b_cont; m && room > 0; m = m->b_cont) {
	n = blklen(m);
	if (n <= 0)
	    continue;
	if (n > room)
	    n = room;
	bcopy((caddr_t)m->b_rptr, (caddr_t)&xs_txbuf[len], n);
	len += n;
	room -= n;
    }
    if (len < XS_ETHERMIN) {
	bzero((caddr_t)&xs_txbuf[len], XS_ETHERMIN - len);
	len = XS_ETHERMIN;
    }
    xs_txbuf[len] = 0;		/* the even DMA count's extra byte */
    (void)xs_tx_send(b, xs_txbuf, len);
    splx(s);
    freemsg(mp);
    return 1;
}

/*
 * A received frame (xs_core.c), `len' bytes from the destination address
 * on: to every stream bound to its type when it is for this station or
 * broadcast.  A frame of the old trailer encapsulation is not decoded: no
 * stream binds those types, so it counts as rx_no_sap.
 */
void
xs_deliver(b, frame, len)
xs_board_t *b;
unsigned char *frame;
int len;
{
    unsigned short type = (frame[12] << 8) | frame[13];
    int j, matched = 0, dlen = len - XS_ETHERHDR;
    xs_stream_t *sp;
    mblk_t *mp;
    dl_unitdata_ind_t *dp;

    for (j = 0, sp = b->s; j < XS_MAXDEV; j++, sp++) {
	if (sp->q == NULL || sp->state != DL_IDLE || sp->sap != type)
	    continue;
	matched = 1;
	if (bcmp((char *)frame, (char *)b->mac, XS_ETHERADDRL) &&
	    bcmp((char *)frame, (char *)xs_bcast, XS_ETHERADDRL)) {
	    b->st.rx_not_for_us++;
	    continue;
	}
	if (!canput(sp->q->q_next)) {
	    b->st.rx_couldnt_put++;
	    continue;
	}
	if ((mp = allocb(sizeof(dl_unitdata_ind_t) + 2 * XS_ETHERADDRL,
			 BPRI_MED)) == NULL) {
	    b->st.rx_nomem++;
	    continue;
	}
	if ((mp->b_cont = allocb(dlen, BPRI_MED)) == NULL) {
	    freemsg(mp);
	    b->st.rx_nomem++;
	    continue;
	}
	mp->b_datap->db_type = M_PROTO;
	dp = (dl_unitdata_ind_t *)mp->b_wptr;
	dp->dl_primitive = DL_UNITDATA_IND;
	dp->dl_dest_addr_length = XS_ETHERADDRL;
	dp->dl_dest_addr_offset = sizeof(dl_unitdata_ind_t);
	dp->dl_src_addr_length = XS_ETHERADDRL;
	dp->dl_src_addr_offset = sizeof(dl_unitdata_ind_t) + XS_ETHERADDRL;
	dp->dl_reserved = 0;
	mp->b_wptr += sizeof(dl_unitdata_ind_t);
	bcopy((caddr_t)frame, (caddr_t)mp->b_wptr, XS_ETHERADDRL);
	mp->b_wptr += XS_ETHERADDRL;
	bcopy((caddr_t)frame + 6, (caddr_t)mp->b_wptr, XS_ETHERADDRL);
	mp->b_wptr += XS_ETHERADDRL;
	mp->b_cont->b_datap->db_type = M_DATA;
	bcopy((caddr_t)frame + XS_ETHERHDR, (caddr_t)mp->b_cont->b_wptr, dlen);
	mp->b_cont->b_wptr += dlen;
	putnext(sp->q, mp);
	b->st.rx_delivered++;
    }
    if (!matched)
	b->st.rx_no_sap++;
}

/* ------------------------------------------------------------------------
 * ioctls: the status record and the board count
 * --------------------------------------------------------------------- */
static void
xs_ioc_reply(q, mp, err)
queue_t *q;
mblk_t *mp;
int err;
{
    struct iocblk *iocbp = (struct iocblk *)mp->b_rptr;

    if (mp->b_cont) {
	freemsg(mp->b_cont);
	mp->b_cont = NULL;
    }
    mp->b_datap->db_type = err ? M_IOCNAK : M_IOCACK;
    iocbp->ioc_count = 0;
    iocbp->ioc_rval = 0;
    iocbp->ioc_error = err;
    qreply(q, mp);
}

/*
 * Answer with `size' bytes from `data': copied out to the user's address for
 * a transparent ioctl (whose b_cont holds that address), else returned in
 * b_cont.  A malformed request gets EINVAL, no memory ENOMEM.
 */
static void
xs_ioc_data(q, mp, data, size)
queue_t *q;
mblk_t *mp;
caddr_t data;
int size;
{
    struct iocblk *iocbp = (struct iocblk *)mp->b_rptr;
    struct copyreq *cq;
    caddr_t uaddr = 0;
    mblk_t *d;

    if (iocbp->ioc_count == TRANSPARENT) {
	if (mp->b_cont == NULL || blklen(mp->b_cont) < (int)sizeof(caddr_t)) {
	    xs_ioc_reply(q, mp, EINVAL);
	    return;
	}
	uaddr = *(caddr_t *)mp->b_cont->b_rptr;
    }
    if ((d = allocb(size, BPRI_MED)) == NULL) {
	xs_ioc_reply(q, mp, ENOMEM);
	return;
    }
    bcopy(data, (caddr_t)d->b_wptr, size);
    d->b_wptr += size;
    if (mp->b_cont)
	freemsg(mp->b_cont);
    mp->b_cont = d;
    if (iocbp->ioc_count == TRANSPARENT) {
	cq = (struct copyreq *)mp->b_rptr;
	mp->b_datap->db_type = M_COPYOUT;
	mp->b_wptr = mp->b_rptr + sizeof(struct copyreq);
	cq->cq_addr = uaddr;
	cq->cq_size = size;
	cq->cq_flag = 0;
	cq->cq_private = (mblk_t *)0;
    } else {
	mp->b_datap->db_type = M_IOCACK;
	iocbp->ioc_count = size;
	iocbp->ioc_error = 0;
	iocbp->ioc_rval = 0;
    }
    qreply(q, mp);
}

static void
xs_ioctl(q, mp)
queue_t *q;
mblk_t *mp;
{
    struct iocblk *iocbp = (struct iocblk *)mp->b_rptr;
    xs_stream_t *sp = (xs_stream_t *)q->q_ptr;
    xs_board_t *b;
    xsurf_status_t st;
    int s;

    if (mp->b_datap->db_type == M_IOCDATA) {
	/* the stream head's answer to our M_COPYOUT */
	if (((struct copyresp *)mp->b_rptr)->cp_rval) {
	    freemsg(mp);
	    return;
	}
	xs_ioc_reply(q, mp, 0);
	return;
    }
    if (sp == NULL) {
	xs_ioc_reply(q, mp, EINVAL);
	return;
    }
    b = &xs_board[sp->board];

    switch (iocbp->ioc_cmd) {
    case SIOCSIFFLAGS:
    case SIOCGIFFLAGS:
	xs_ioc_reply(q, mp, 0);
	return;

    case XSURF_NUMBER_OF_BOARDS:
	xs_ioc_data(q, mp, (caddr_t)&xs_nboards, sizeof(int));
	return;

    case XSURF_GET_STATUS:
	s = splxs();
	b->st.version = XSURF_STATUS_VERSION;
	b->st.size = sizeof(xsurf_status_t);
	b->st.intr_mode = b->intr;
	b->st.link = XSURF_LINK_UNKNOWN;
	b->st.running = b->running;
	b->st.if_ipackets = b->ifs.ifs_ipackets;
	b->st.if_opackets = b->ifs.ifs_opackets;
	b->st.if_ierrors = b->ifs.ifs_ierrors;
	b->st.if_oerrors = b->ifs.ifs_oerrors;
	st = b->st;
	splx(s);
	xs_ioc_data(q, mp, (caddr_t)&st, sizeof(xsurf_status_t));
	return;

    default:
	xs_ioc_reply(q, mp, EINVAL);
	return;
    }
}

/* ------------------------------------------------------------------------
 * interrupts and the tick
 * --------------------------------------------------------------------- */

/*
 * The level-2 handler, called on every PORTS interrupt with its board.  It
 * claims only when the board's own interrupt bit is set.
 */
static int
xs_intr(arg)
char *arg;
{
    xs_board_t *b = (xs_board_t *)arg;
    int s;

    if (!b->present || !(*b->ops->irq)(b))
	return 0;
    s = splxs();
    if (b->selftest) {
	if (xs_selftest_ack(b))
	    b->selftest_seen = 1;
    } else if (b->intr == XSURF_MODE_INTR) {
	b->st.irq_claims++;
	xs_service(b);
    } else
	xs_chip_mask(b, 0);	/* polled: the chip should not interrupt */
    splx(s);
    return 1;
}

/*
 * Every clock tick, at IPL 4: polled boards are serviced; in interrupt mode
 * the tick only checks that the interrupt still comes.  Then the watchdog,
 * and the write queues a lack of memory or of slots left waiting.
 */
static void
xs_tick(arg)
caddr_t arg;
{
    xs_board_t *b;
    int i, s;

    for (i = 0; i < xs_nboards; i++) {
	b = &xs_board[i];
	if (!b->present)
	    continue;
	s = splxs();
	if (b->intr == XSURF_MODE_POLLED)
	    xs_service(b);
	else if (xs_pending(b) && b->st.irq_claims == b->last_claims) {
	    if (++b->stuck >= XS_STUCK_TICKS) {
		b->intr = XSURF_MODE_POLLED;
		b->st.irq_fallbacks++;
		xs_chip_mask(b, 0);
		cmn_err(CE_NOTE, "xsf%d: interrupts stopped; polled", b->unit);
		xs_service(b);
	    }
	} else
	    b->stuck = 0;
	b->last_claims = b->st.irq_claims;
	xs_watch(b);
	xs_tx_restart(b);
	splx(s);
    }
    if (xs_tick_on)
	xs_tick_id = timeout(xs_tick, (caddr_t)0, 1);
}

/*
 * Attach the handler and prove it with a real interrupt from the board.
 * Runs in _load at IPL 0, where a level-2 interrupt is taken during the
 * wait.  1 = interrupt mode.
 */
static int
xs_selftest(b)
xs_board_t *b;
{
    int e, t, s;

    if ((e = intr_attach(2, xs_intr, (char *)b, "xsurf")) != 0) {
	cmn_err(CE_NOTE, "xsf%d: level-2 attach failed (errno %d)", b->unit, e);
	return 0;
    }
    b->attached = 1;
    s = splxs();
    b->selftest_seen = 0;
    b->selftest = 1;
    xs_selftest_kick(b);
    splx(s);
    for (t = 0; t < XS_SELFTEST_US && !b->selftest_seen; t += 100)
	xs_udelay(100L);
    s = splxs();
    b->selftest = 0;
    xs_chip_mask(b, 0);
    splx(s);
    if (b->selftest_seen)
	return 1;
    (void)intr_detach(2, xs_intr, (char *)b);
    b->attached = 0;
    return 0;
}

/* ------------------------------------------------------------------------
 * the module
 * --------------------------------------------------------------------- */

/*
 * One "name=value" of the manifest's parameter string (separated by spaces;
 * 0 when there are none) as a non-negative decimal, else `dflt'.
 */
static long
xs_param(params, name, dflt)
char *params, *name;
long dflt;
{
    char *p = params, *n;
    long v;

    if (p == 0)
	return dflt;
    while (*p) {
	while (*p == ' ')
	    p++;
	for (n = name; *n && *p == *n; n++, p++)
	    ;
	if (*n == 0 && *p == '=') {
	    p++;
	    if (*p < '0' || *p > '9')
		return dflt;
	    for (v = 0; *p >= '0' && *p <= '9'; p++)
		v = v * 10 + (*p - '0');
	    return (*p == 0 || *p == ' ') ? v : dflt;
	}
	while (*p && *p != ' ')
	    p++;
    }
    return dflt;
}

static void
xs_teardown()
{
    xs_board_t *b;
    int i, s;

    if (xs_tick_on) {
	xs_tick_on = 0;
	untimeout(xs_tick_id);
    }
    for (i = 0; i < xs_nboards; i++) {
	b = &xs_board[i];
	if (b->present) {
	    s = splxs();
	    xs_chip_stop(b);
	    if (b->ops->phy)
		(*b->ops->phy)(b, 0);
	    splx(s);
	}
	if (b->attached) {
	    (void)intr_detach(2, xs_intr, (char *)b);
	    b->attached = 0;
	}
	if (b->ifs_on) {
	    (void)if_detach(&b->ifs);
	    b->ifs_on = 0;
	}
	xs_unmap(b);
	b->present = 0;
    }
    xs_nboards = 0;
}

/*
 * _load: process context, IPL 0, before the core installs the cdevsw row.
 * Find and set up the boards (xs_boards.c), put each on the interface list,
 * start the chips and the tick, then the interrupt and its self-test.  One
 * console line per board names the card, its address and the mode it ended
 * in.  ENXIO without a board; any failure leaves nothing behind.
 */
int
xsurf_load(params)
char *params;
{
    xs_board_t *b;
    int i, e, s, intr;

    xs_intr_param = xs_param(params, "intr", 2L);
    if (xs_intr_param != 0 && xs_intr_param != 2) {
	cmn_err(CE_NOTE, "xsurf: intr=%d is not 0 or 2; using 2", (int)xs_intr_param);
	xs_intr_param = 2;
    }

    if (xs_find_boards() == 0) {
	xs_teardown();
	return ENXIO;
    }
    for (i = 0; i < xs_nboards; i++) {
	b = &xs_board[i];
	b->ifs.ifs_name = "xsf";
	b->ifs.ifs_unit = b->unit;
	b->ifs.ifs_mtu = XS_ETHERMTU;
	b->ifs.ifs_active = 0;
	if ((e = if_attach(&b->ifs)) != 0) {
	    cmn_err(CE_NOTE, "xsf%d: if_attach failed (errno %d)", b->unit, e);
	    xs_teardown();
	    return e;
	}
	b->ifs_on = 1;
	b->intr = XSURF_MODE_POLLED;
	s = splxs();
	xs_chip_init(b, 1);
	splx(s);
    }
    xs_tick_on = 1;
    xs_tick_id = timeout(xs_tick, (caddr_t)0, 1);

    for (i = 0; i < xs_nboards; i++) {
	b = &xs_board[i];
	intr = xs_intr_param == 2 && xs_selftest(b);
	s = splxs();
	b->intr = intr ? XSURF_MODE_INTR : XSURF_MODE_POLLED;
	b->stuck = 0;
	b->last_claims = b->st.irq_claims;
	xs_chip_mask(b, intr);
	splx(s);
	cmn_err(CE_CONT,
	    "xsf%d: %s, Zorro %d at 0x%x, %x:%x:%x:%x:%x:%x, %s\n",
	    b->unit, b->ops->name, (int)b->st.zorro, (int)b->phys,
	    b->mac[0], b->mac[1], b->mac[2], b->mac[3], b->mac[4], b->mac[5],
	    intr ? "interrupt I/O" :
	    xs_intr_param == 2 ? "polled (interrupt self-test failed)" : "polled");
    }
    return 0;
}

/*
 * _unload: every stream closed, else EBUSY; then the reverse of _load: the
 * tick, each chip stopped and masked before its handler comes off, the
 * interface list, the mappings.  unload=never refuses a request; the core
 * still calls this when a load fails after _load returned 0.
 */
int
xsurf_unload()
{
    int i, j;

    for (i = 0; i < xs_nboards; i++)
	for (j = 0; j < XS_MAXDEV; j++)
	    if (xs_board[i].s[j].q)
		return EBUSY;
    xs_teardown();
    return 0;
}

/* _halt: no sleep, interrupts perhaps off: stop and mask the chips */
void
xsurf_halt()
{
    int i;

    xs_tick_on = 0;
    untimeout(xs_tick_id);
    for (i = 0; i < xs_nboards; i++)
	if (xs_board[i].present)
	    xs_chip_stop(&xs_board[i]);
}

#ifndef XS_HOSTTEST
/* the cdevsw row: d_str only; the core installs open and close */
struct mod_drv_data xsurf_drvdata[] = {
    {
	{ 0 }, 0, 0,
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, (struct tty *)0, &xsurfinfo, (int *)0 },
	XS_MAJOR, 1,
    },
};

MOD_DRV_WRAPPER(xsurf, xsurf_load, xsurf_unload, xsurf_halt,
		"X-Surf ethernet (xsf)");
#endif
