/*
 * t_core.c -- host tests of xsurf.c and xs_core.c against the model chip
 * and kernel (mock.c).  Each test boots the module, drives it through its
 * STREAMS entry points, the tick and the interrupt, and checks what reached
 * the wire, what went upstream and the status record.
 */
#include "hostk.h"
#include "xsurf.h"
#include "mock.h"

extern struct streamtab xsurfinfo;
extern int	xsurf_load(), xsurf_unload();
extern void	xsurf_halt();
void		(*host_upstream_hook)();

static int	n_checks, n_fail;
static char	*cur;
#define CHECK(c) do { n_checks++; if (!(c)) { n_fail++; \
	printf("FAIL %s: %s (line %d)\n", cur, #c, __LINE__); } } while (0)

static unsigned char MAC[6] = { 0x00, 0x80, 0x10, 0x12, 0x34, 0x56 };
static unsigned char PEER[6] = { 0x02, 0x00, 0x00, 0x00, 0x00, 0x99 };
static unsigned char OTHER[6] = { 0x02, 0x00, 0x00, 0x00, 0x00, 0x77 };
static unsigned char BCAST[6] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };

#define B	(&xs_board[0])

/* ---------------- streams ---------------- */
struct strm { queue_t rq, wq, head; dev_t dev; int open; };
static struct strm S[8];

static int
s_open_flag(struct strm *s, int minor, int sflag)
{
    int e;

    memset(s, 0, sizeof *s);
    s->rq.q_read = 1;
    s->rq.q_other = &s->wq;
    s->wq.q_other = &s->rq;
    s->rq.q_next = &s->head;
    s->dev = makedevice(56, minor);
    e = (*xsurfinfo.st_rdinit->qi_qopen)(&s->rq, &s->dev, 0, sflag, NULL);
    s->open = e == 0;
    return e;
}

static int
s_open(struct strm *s, int minor)
{
    return s_open_flag(s, minor, 0);
}

static mblk_t *
s_up(struct strm *s)
{
    mblk_t *mp = s->head.up_first;

    if (mp) {
	s->head.up_first = mp->b_next;
	if (s->head.up_first == NULL)
	    s->head.up_last = NULL;
	mp->b_next = NULL;
    }
    return mp;
}

static int
s_upcount(struct strm *s)
{
    int n = 0;
    mblk_t *mp;

    for (mp = s->head.up_first; mp; mp = mp->b_next)
	n++;
    return n;
}

static void
s_drain(struct strm *s)
{
    mblk_t *mp;

    while ((mp = s_up(s)) != NULL)
	freemsg(mp);
}

static void
s_close(struct strm *s)
{
    if (!s->open)
	return;
    (*xsurfinfo.st_rdinit->qi_qclose)(&s->rq);
    flushq(&s->wq, FLUSHALL);
    s_drain(s);
    s->open = 0;
}

static void
s_put(struct strm *s, mblk_t *mp)
{
    (*xsurfinfo.st_wrinit->qi_putp)(&s->wq, mp);
}

/* ---------------- messages ---------------- */
static mblk_t *
proto(int size, ulong prim)
{
    mblk_t *mp = allocb(size, BPRI_MED);

    mp->b_datap->db_type = M_PROTO;
    memset(mp->b_wptr, 0, size);
    if (size >= (int)sizeof(ulong))
	*(ulong *)mp->b_wptr = prim;
    mp->b_wptr += size;
    return mp;
}

static mblk_t *
bind_req(ulong sap)
{
    mblk_t *mp = proto(sizeof(dl_bind_req_t), DL_BIND_REQ);

    ((dl_bind_req_t *)mp->b_rptr)->dl_sap = sap;
    return mp;
}

static mblk_t *
unitdata(unsigned char *dest, int dlen, long off, int datalen, int seq)
{
    mblk_t *mp = proto(sizeof(dl_unitdata_req_t) + 8, DL_UNITDATA_REQ);
    dl_unitdata_req_t *u = (dl_unitdata_req_t *)mp->b_rptr;
    int i;

    u->dl_dest_addr_length = dlen;
    u->dl_dest_addr_offset = off;
    if (off >= 0 && off + 6 <= (long)(sizeof(dl_unitdata_req_t) + 8))
	memcpy(mp->b_rptr + off, dest, 6);
    if (datalen > 0) {
	mp->b_cont = allocb(datalen, BPRI_MED);
	for (i = 0; i < datalen; i++)
	    mp->b_cont->b_wptr[i] = (seq + i) & 0xff;
	mp->b_cont->b_wptr += datalen;
	mp->b_cont->b_datap->db_type = M_DATA;
    }
    return mp;
}

static mblk_t *
send_ok(unsigned char *dest, int datalen, int seq)
{
    return unitdata(dest, 6, sizeof(dl_unitdata_req_t), datalen, seq);
}

static ulong
prim_of(mblk_t *mp)
{
    return *(ulong *)mp->b_rptr;
}

/* expect one upstream primitive; return it (freed by the caller) */
static mblk_t *
expect(struct strm *s, ulong prim)
{
    mblk_t *mp = s_up(s);

    CHECK(mp != NULL);
    if (mp)
	CHECK(prim_of(mp) == prim);
    return mp;
}

static void
bind(struct strm *s, ulong sap)
{
    s_put(s, bind_req(sap));
    freemsg(expect(s, DL_BIND_ACK));
}

/* a frame from the wire: dst, PEER, type, payload of `len'-14 bytes */
static unsigned char frame[2048];

static int
inject(unsigned char *dst, int type, int len, int seq)
{
    int i;

    memcpy(frame, dst, 6);
    memcpy(frame + 6, PEER, 6);
    frame[12] = type >> 8;
    frame[13] = type & 0xff;
    for (i = 14; i < len; i++)
	frame[i] = (seq + i) & 0xff;
    return chip_receive(frame, len, XS_RSR_PRX, 0);
}

/* the indication carries `len'-14 bytes of payload from `seq' */
static int
ind_ok(mblk_t *mp, int len, int seq)
{
    dl_unitdata_ind_t *d;
    int i;

    if (mp == NULL || prim_of(mp) != DL_UNITDATA_IND || mp->b_cont == NULL)
	return 0;
    d = (dl_unitdata_ind_t *)mp->b_rptr;
    if (memcmp(mp->b_rptr + d->dl_src_addr_offset, PEER, 6))
	return 0;
    if (mp->b_cont->b_wptr - mp->b_cont->b_rptr != len - 14)
	return 0;
    for (i = 14; i < len; i++)
	if (mp->b_cont->b_rptr[i - 14] != ((seq + i) & 0xff))
	    return 0;
    return 1;
}

/* ---------------- set-up ---------------- */
static void
boot(char *params)
{
    int i;

    for (i = 0; i < 8; i++)
	memset(&S[i], 0, sizeof S[i]);
    host_console[0] = 0;
    lbolt = 1000;
    host_ipl = 0;
    host_alloc_fail = 0;
    host_attach_fail = 0;
    host_upstream_hook = NULL;
    chip_power_on(MAC);
    CHECK(xsurf_load(params) == 0);
}

static void
shutdown()
{
    int i;

    for (i = 0; i < 8; i++)
	s_close(&S[i]);
    CHECK(xsurf_unload() == 0);
    CHECK(!host_attached());
    CHECK(!host_tick_armed());
    CHECK(host_ifs_count == 0);
    CHECK(chip.gpoc_in_dma == 0);
    CHECK(chip.overread == 0);
    CHECK(chip.bad_addr == 0);
    CHECK(chip.odd_bout == 0);
    CHECK(host_live == 0);
}

static void
ticks(int n)
{
    while (n-- > 0)
	host_tick();
}

/* ---------------- the tests ---------------- */
static void
t_open()
{
    cur = "open";
    boot("intr=0");
    CHECK(s_open(&S[0], 0) == 0);
    CHECK(getminor(S[0].dev) == 0x10);
    CHECK(s_open(&S[1], 0) == 0);
    CHECK(getminor(S[1].dev) == 0x20);
    CHECK(s_open(&S[2], 0) == 0);
    CHECK(s_open(&S[3], 0) == 0);
    CHECK(s_open(&S[4], 0) == 0);
    CHECK(s_open(&S[5], 0) == ENOSPC);
    CHECK(s_open(&S[6], 1) == ENXIO);		/* no second board */
    CHECK(s_open_flag(&S[7], 0, CLONEOPEN) == EINVAL);
    CHECK(B->ifs.ifs_active == 1);
    shutdown();
    CHECK(B->ifs.ifs_active == 0);
}

static void
t_info_bind()
{
    mblk_t *mp;
    dl_info_ack_t *ia;
    dl_bind_ack_t *ba;

    cur = "dlpi-info-bind";
    boot("intr=0");
    s_open(&S[0], 0);
    s_put(&S[0], proto(4, DL_INFO_REQ));
    mp = expect(&S[0], DL_INFO_ACK);
    ia = (dl_info_ack_t *)mp->b_rptr;
    CHECK(ia->dl_provider_style == DL_STYLE1);
    CHECK(ia->dl_mac_type == DL_ETHER && ia->dl_max_sdu == 1500);
    CHECK(ia->dl_current_state == DL_UNBOUND && ia->dl_addr_offset == 0);
    freemsg(mp);

    s_put(&S[0], bind_req(0x800));
    mp = expect(&S[0], DL_BIND_ACK);
    ba = (dl_bind_ack_t *)mp->b_rptr;
    CHECK(ba->dl_sap == 0x800 && ba->dl_addr_length == 6);
    CHECK(memcmp(mp->b_rptr + ba->dl_addr_offset, MAC, 6) == 0);
    freemsg(mp);

    s_put(&S[0], proto(4, DL_INFO_REQ));
    mp = expect(&S[0], DL_INFO_ACK);
    ia = (dl_info_ack_t *)mp->b_rptr;
    CHECK(ia->dl_current_state == DL_IDLE && ia->dl_addr_offset != 0);
    CHECK(memcmp(mp->b_rptr + ia->dl_addr_offset, MAC, 6) == 0);
    freemsg(mp);

    s_put(&S[0], proto(4, DL_ATTACH_REQ));
    mp = expect(&S[0], DL_OK_ACK);
    CHECK(((dl_ok_ack_t *)mp->b_rptr)->dl_correct_primitive == DL_ATTACH_REQ);
    freemsg(mp);
    s_put(&S[0], proto(4, DL_DETACH_REQ));
    freemsg(expect(&S[0], DL_OK_ACK));
    s_put(&S[0], proto(4, DL_UNBIND_REQ));
    freemsg(expect(&S[0], DL_OK_ACK));
    s_put(&S[0], send_ok(PEER, 20, 0));		/* unbound now */
    CHECK(chip.wire_n == 0 && B->st.tx_unbound == 1);
    shutdown();
}

static void
t_bad_requests()
{
    mblk_t *mp;
    dl_error_ack_t *e;

    cur = "dlpi-bad-requests";
    boot("intr=0");
    s_open(&S[0], 0);
    s_put(&S[0], proto(8, DL_BIND_REQ));		/* short bind */
    mp = expect(&S[0], DL_ERROR_ACK);
    CHECK(((dl_error_ack_t *)mp->b_rptr)->dl_errno == DL_BADPRIM);
    freemsg(mp);
    s_put(&S[0], bind_req(0x12345));			/* SAP too large */
    mp = expect(&S[0], DL_ERROR_ACK);
    CHECK(((dl_error_ack_t *)mp->b_rptr)->dl_errno == DL_BADSAP);
    freemsg(mp);
    s_put(&S[0], proto(4, 0x55));			/* unknown */
    mp = expect(&S[0], DL_ERROR_ACK);
    e = (dl_error_ack_t *)mp->b_rptr;
    CHECK(e->dl_error_primitive == 0x55 && e->dl_errno == DL_BADPRIM);
    freemsg(mp);
    s_put(&S[0], proto(2, 0));				/* shorter than a primitive */
    CHECK(s_upcount(&S[0]) == 0);

    bind(&S[0], 0x800);
    s_put(&S[0], unitdata(PEER, 6, 200, 20, 0));	/* address outside the block */
    s_put(&S[0], unitdata(PEER, 6, -1, 20, 0));	/* offset wraps */
    s_put(&S[0], unitdata(PEER, 4, sizeof(dl_unitdata_req_t), 20, 0));
    s_put(&S[0], proto(8, DL_UNITDATA_REQ));		/* short request */
    CHECK(B->st.tx_bad_req == 4);
    CHECK(chip.wire_n == 0);
    shutdown();
}

static void
t_ack_nomem()
{
    mblk_t *mp;

    cur = "dlpi-ack-nomem";
    boot("intr=0");
    s_open(&S[0], 0);
    mp = bind_req(0x800);
    host_alloc_fail = 1;
    s_put(&S[0], mp);
    CHECK(s_upcount(&S[0]) == 0);
    CHECK(S[0].wq.q_first != NULL);			/* kept for a retry */
    CHECK(B->s[0].state == DL_UNBOUND);
    s_put(&S[0], proto(4, DL_INFO_REQ));		/* behind it, in order */
    CHECK(s_upcount(&S[0]) == 0);
    host_tick();
    mp = expect(&S[0], DL_BIND_ACK);
    freemsg(mp);
    freemsg(expect(&S[0], DL_INFO_ACK));
    CHECK(s_upcount(&S[0]) == 0);
    CHECK(B->s[0].state == DL_IDLE);
    mp = proto(4, 0x55);
    host_alloc_fail = 1;
    s_put(&S[0], mp);
    CHECK(s_upcount(&S[0]) == 0);
    host_tick();
    freemsg(expect(&S[0], DL_ERROR_ACK));
    shutdown();
}

static void
t_tx_frame()
{
    int i, ok;

    cur = "tx-frame-and-padding";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    s_put(&S[0], send_ok(PEER, 10, 3));
    host_tick();
    CHECK(chip.wire_n == 1 && chip.wire_len[0] == 60);
    CHECK(memcmp(chip.wire[0], PEER, 6) == 0);
    CHECK(memcmp(chip.wire[0] + 6, MAC, 6) == 0);
    CHECK(chip.wire[0][12] == 0x08 && chip.wire[0][13] == 0x00);
    for (ok = 1, i = 0; i < 10; i++)
	ok &= chip.wire[0][14 + i] == ((3 + i) & 0xff);
    for (i = 24; i < 60; i++)
	ok &= chip.wire[0][i] == 0;
    CHECK(ok);
    s_put(&S[0], send_ok(PEER, 1500, 0));
    host_tick();
    CHECK(chip.wire_n == 2 && chip.wire_len[1] == 1514);
    s_put(&S[0], send_ok(PEER, 2000, 0));		/* clipped to the MTU */
    host_tick();
    CHECK(chip.wire_n == 3 && chip.wire_len[2] == 1514);
    s_put(&S[0], send_ok(PEER, 47, 0));			/* odd length */
    host_tick();
    CHECK(chip.wire_n == 4 && chip.wire_len[3] == 61);
    s_put(&S[0], send_ok(PEER, 4, 0));			/* short after long */
    host_tick();
    CHECK(chip.wire_n == 5 && chip.wire_len[4] == 60);
    for (ok = 1, i = 18; i < 60; i++)
	ok &= chip.wire[4][i] == 0;
    CHECK(ok);					/* the padding is zeros */
    CHECK(B->st.tx_frames == 5);
    shutdown();
}

static void
t_rx_deliver()
{
    mblk_t *mp;

    cur = "rx-demux";
    boot("intr=0");
    s_open(&S[0], 0);
    s_open(&S[1], 0);
    s_open(&S[2], 0);
    bind(&S[0], 0x800);
    bind(&S[1], 0x800);
    bind(&S[2], 0x806);
    inject(BCAST, 0x800, 100, 1);
    host_tick();
    mp = s_up(&S[0]);
    CHECK(ind_ok(mp, 100, 1));
    freemsg(mp);
    mp = s_up(&S[1]);
    CHECK(ind_ok(mp, 100, 1));				/* every bound stream */
    freemsg(mp);
    CHECK(s_upcount(&S[2]) == 0);
    inject(MAC, 0x806, 60, 2);
    host_tick();
    mp = s_up(&S[2]);
    CHECK(ind_ok(mp, 60, 2));
    freemsg(mp);
    inject(OTHER, 0x800, 100, 3);			/* not for this station */
    host_tick();
    CHECK(s_upcount(&S[0]) == 0 && B->st.rx_not_for_us == 2);
    shutdown();
}

static void
t_rx_hostile()
{
    cur = "rx-trailer-runt-oversize";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    inject(MAC, 0x1001, 1500, 0);			/* trailer encapsulation */
    inject(MAC, 0x1010, 64, 0);
    host_tick();
    CHECK(s_upcount(&S[0]) == 0 && B->st.rx_no_sap == 2);
    inject(MAC, 0x800, 50, 0);				/* runt */
    host_tick();
    CHECK(B->st.rx_bad_size == 1);
    inject(MAC, 0x800, 1600, 0);			/* oversize */
    host_tick();
    CHECK(B->st.rx_bad_size == 2 && s_upcount(&S[0]) == 0);
    inject(MAC, 0x800, 1518, 9);			/* the longest taken */
    host_tick();
    CHECK(s_upcount(&S[0]) == 1);
    shutdown();
}

static void
t_rx_nomem()
{
    cur = "rx-nomem-and-full";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    inject(MAC, 0x800, 100, 0);
    host_alloc_fail = 1;
    host_tick();
    CHECK(B->st.rx_nomem == 1 && s_upcount(&S[0]) == 0);
    inject(MAC, 0x800, 100, 0);
    host_alloc_fail = 2;				/* the data block fails */
    host_tick();
    host_alloc_fail = 0;
    CHECK(B->st.rx_nomem >= 2 && s_upcount(&S[0]) == 0);
    S[0].head.full = 1;
    inject(MAC, 0x800, 100, 0);
    host_tick();
    CHECK(B->st.rx_couldnt_put == 1 && s_upcount(&S[0]) == 0);
    S[0].head.full = 0;
    inject(MAC, 0x800, 100, 0);
    host_tick();
    CHECK(s_upcount(&S[0]) == 1);
    shutdown();
}

static mblk_t *
ioctl_msg(int cmd, unsigned int count, int with_cont)
{
    mblk_t *mp = allocb(sizeof(struct copyreq), BPRI_MED);
    struct iocblk *io = (struct iocblk *)mp->b_wptr;

    mp->b_datap->db_type = M_IOCTL;
    memset(io, 0, sizeof(struct copyreq));
    io->ioc_cmd = cmd;
    io->ioc_count = count;
    mp->b_wptr += sizeof(struct iocblk);
    if (with_cont) {
	mp->b_cont = allocb(sizeof(caddr_t), BPRI_MED);
	*(caddr_t *)mp->b_cont->b_wptr = (caddr_t)0x1000;
	mp->b_cont->b_wptr += sizeof(caddr_t);
    }
    return mp;
}

static void
t_ioctl()
{
    mblk_t *mp;
    xsurf_status_t *st;

    cur = "ioctl";
    boot("intr=0");
    s_open(&S[0], 0);
    s_put(&S[0], ioctl_msg(XSURF_GET_STATUS, 0, 0));
    mp = s_up(&S[0]);
    CHECK(mp && mp->b_datap->db_type == M_IOCACK && mp->b_cont);
    if (mp && mp->b_cont) {
	st = (xsurf_status_t *)mp->b_cont->b_rptr;
	CHECK(st->version == XSURF_STATUS_VERSION && st->size == sizeof(xsurf_status_t));
	CHECK(st->link == XSURF_LINK_UNKNOWN && st->intr_mode == XSURF_MODE_POLLED);
    }
    freemsg(mp);
    s_put(&S[0], ioctl_msg(XSURF_GET_STATUS, TRANSPARENT, 0));	/* no address */
    mp = s_up(&S[0]);
    CHECK(mp && mp->b_datap->db_type == M_IOCNAK &&
	  ((struct iocblk *)mp->b_rptr)->ioc_error == EINVAL);
    freemsg(mp);
    s_put(&S[0], ioctl_msg(XSURF_NUMBER_OF_BOARDS, TRANSPARENT, 1));
    mp = s_up(&S[0]);
    CHECK(mp && mp->b_datap->db_type == M_COPYOUT && mp->b_cont &&
	  *(int *)mp->b_cont->b_rptr == 1);
    freemsg(mp);
    s_put(&S[0], ioctl_msg(XSURFIOC | 20, 0, 0));	/* no test ioctls */
    mp = s_up(&S[0]);
    CHECK(mp && mp->b_datap->db_type == M_IOCNAK);
    freemsg(mp);
    mp = ioctl_msg(0, 0, 0);
    mp->b_datap->db_type = M_IOCDATA;
    s_put(&S[0], mp);
    mp = s_up(&S[0]);
    CHECK(mp && mp->b_datap->db_type == M_IOCACK);
    freemsg(mp);
    shutdown();
}

static void
t_prom()
{
    cur = "prom-read";
    boot("intr=0");
    CHECK(memcmp(B->mac, MAC, 6) == 0);
    CHECK(chip.overread == 0);		/* the count matches the reads */
    CHECK(memcmp(chip.par, MAC, 6) == 0);
    shutdown();
}

static void
t_ring()
{
    mblk_t *mp;
    int i, good = 0;

    cur = "rx-ring-wrap-and-burst";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    for (i = 0; i < 60; i++) {			/* goes round the ring 4 times */
	inject(MAC, 0x800, 700 + i, i);
	host_tick();
	mp = s_up(&S[0]);
	good += ind_ok(mp, 700 + i, i);
	freemsg(mp);
    }
    CHECK(good == 60);
    for (i = 0; i < 10; i++)			/* ten waiting at once */
	CHECK(inject(MAC, 0x800, 1000, 100 + i));
    host_tick();
    for (good = 0, i = 0; i < 10; i++) {
	mp = s_up(&S[0]);
	good += ind_ok(mp, 1000, 100 + i);
	freemsg(mp);
    }
    CHECK(good == 10);
    shutdown();
}

static void
t_overrun()
{
    mblk_t *mp;
    int i, n = 0;

    cur = "rx-overrun";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    for (i = 0; i < 40 && inject(MAC, 0x800, 1500, i); i++)
	n++;
    CHECK(chip.ovw == 1 && n > 0 && n < 40);
    host_tick();
    CHECK(chip.ovw == 0 && chip.ovw_bad_ack == 0);
    CHECK(B->st.rx_overruns == 1);
    CHECK(s_upcount(&S[0]) == n);
    s_drain(&S[0]);
    CHECK(inject(MAC, 0x800, 300, 7));		/* the receiver runs again */
    host_tick();
    mp = s_up(&S[0]);
    CHECK(ind_ok(mp, 300, 7));
    freemsg(mp);
    CHECK(chip.loop_sends == 0);
    shutdown();
}

static void
t_overrun_resend()
{
    cur = "rx-overrun-resend";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    chip.tx_mode = TX_HANG;
    s_put(&S[0], send_ok(PEER, 100, 0));		/* on the wire, unfinished */
    while (inject(MAC, 0x800, 1500, 0))
	;
    chip.tx_mode = TX_OK;
    host_tick();
    CHECK(chip.ovw == 0 && B->st.tx_resends == 1);
    CHECK(chip.wire_n == 1 && chip.wire_len[0] == 114);
    shutdown();
}

static void
reply_hook(queue_t *q, mblk_t *mp)
{
    host_upstream_hook = NULL;			/* one reply */
    s_put(&S[0], send_ok(PEER, 30, 5));
}

static void
t_overrun_reply()
{
    cur = "rx-overrun-reply-not-looped";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    while (inject(MAC, 0x800, 1500, 0))
	;
    host_upstream_hook = reply_hook;		/* an ARP-style reply */
    host_tick();
    host_tick();
    CHECK(chip.loop_sends == 0);
    CHECK(chip.wire_n == 1 && chip.wire_len[0] == 60);
    shutdown();
}

static void
t_counters()
{
    cur = "rx-counters";
    boot("intr=0");
    chip.cntr[0] = 3;
    chip.cntr[1] = 0x80;
    chip.cntr[2] = 0x90;
    chip.isr |= XS_I_CNT;
    host_tick();
    CHECK((chip.isr & XS_I_CNT) == 0);
    CHECK(B->st.rx_frame_errors == 3 && B->st.rx_crc_errors == 0x80 &&
	  B->st.rx_missed == 0x90);
    shutdown();

    cur = "rx-counters-no-storm";
    boot("");					/* interrupts */
    CHECK(B->intr == XSURF_MODE_INTR);
    chip.cntr[1] = 0x81;
    chip.isr |= XS_I_CNT;
    CHECK(host_interrupt() == 1);
    CHECK(host_interrupt() == 0);			/* the line is down */
    CHECK(B->st.rx_crc_errors == 0x81);
    shutdown();
}

static void
t_tx_abort()
{
    cur = "tx-abort-no-stall";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    chip.tx_mode = TX_ABORT;
    chip.tx_abort_count = 1;
    s_put(&S[0], send_ok(PEER, 20, 1));		/* aborted */
    s_put(&S[0], send_ok(PEER, 21, 2));		/* staged behind it */
    host_tick();
    CHECK(B->st.tx_aborts == 1 && chip.wire_n == 1 && chip.wire_len[0] == 60);
    s_put(&S[0], send_ok(PEER, 50, 3));
    host_tick();
    CHECK(chip.wire_n == 2 && chip.wire_len[1] == 64);
    CHECK(S[0].wq.q_first == NULL);
    shutdown();
}

static void
t_tx_timeout()
{
    cur = "tx-timeout-watchdog";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    chip.tx_mode = TX_HANG;
    s_put(&S[0], send_ok(PEER, 20, 1));
    ticks(XS_TX_TIMEOUT + 2);
    CHECK(B->st.tx_timeouts == 1 && B->st.resets >= 1);
    chip.tx_mode = TX_OK;
    s_put(&S[0], send_ok(PEER, 20, 2));
    host_tick();
    CHECK(chip.wire_n == 1);
    shutdown();
}

static void
t_tx_slots()
{
    int i, ok;

    cur = "tx-two-slots-and-queue";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    chip.tx_mode = TX_HANG;
    s_put(&S[0], send_ok(PEER, 100, 1));		/* on the wire */
    s_put(&S[0], send_ok(PEER, 200, 2));		/* staged */
    s_put(&S[0], send_ok(PEER, 300, 3));		/* waits in the queue */
    CHECK(S[0].wq.q_first != NULL);
    chip_tx_complete();
    host_tick();
    host_tick();
    CHECK(chip.wire_n == 3);
    ok = chip.wire_len[0] == 114 && chip.wire_len[1] == 214 && chip.wire_len[2] == 314;
    CHECK(ok);
    for (ok = 1, i = 0; i < 3; i++)
	ok &= chip.wire[i][14] == i + 1;
    CHECK(ok);
    CHECK(S[0].wq.q_first == NULL);
    shutdown();
}

static void
t_dma_timeout()
{
    cur = "tx-dma-timeout";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    chip.rdc_never = 1;
    s_put(&S[0], send_ok(PEER, 20, 1));
    CHECK(B->st.tx_dma_timeouts == 1 && chip.wire_n == 0);
    chip.rdc_never = 0;
    host_tick();
    CHECK(B->st.resets == 1);
    s_put(&S[0], send_ok(PEER, 20, 2));
    host_tick();
    CHECK(chip.wire_n == 1);
    shutdown();
}

static void
t_resync()
{
    mblk_t *mp;

    cur = "rx-corrupt-header-resync";
    boot("intr=0");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    memcpy(frame, MAC, 6);
    chip_receive(frame, 100, XS_RSR_PRX, 0x41);	/* next page outside the ring */
    CHECK(inject(MAC, 0x800, 100, 1));
    host_tick();
    CHECK(B->st.rx_resyncs == 1 && s_upcount(&S[0]) == 0);
    CHECK(chip.bnry == (chip.curr == XS_RX_START ? XS_RX_STOP - 1 : chip.curr - 1));
    CHECK(inject(MAC, 0x800, 100, 2));
    host_tick();
    mp = s_up(&S[0]);
    CHECK(ind_ok(mp, 100, 2));
    freemsg(mp);
    shutdown();
}

static void
t_interrupts()
{
    mblk_t *mp;

    cur = "intr-selftest-pass";
    boot("");
    CHECK(B->intr == XSURF_MODE_INTR && host_attached());
    CHECK(strstr(host_console, "xsf0: Model, Zorro 2 at 0xe90000") != NULL);
    CHECK(strstr(host_console, "interrupt I/O") != NULL);
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    inject(MAC, 0x800, 100, 4);
    CHECK(host_interrupt() == 1);
    mp = s_up(&S[0]);
    CHECK(ind_ok(mp, 100, 4));
    freemsg(mp);
    s_put(&S[0], send_ok(PEER, 20, 1));
    CHECK(host_interrupt() == 1);			/* PTX */
    CHECK(B->st.tx_frames == 1 && B->st.irq_claims == 2);
    shutdown();

    cur = "intr-selftest-fail";
    host_boards = 1;
    chip_power_on(MAC);
    boot("");
    shutdown();
    host_console[0] = 0;
    {
	int i;
	for (i = 0; i < 8; i++)
	    memset(&S[i], 0, sizeof S[i]);
	chip_power_on(MAC);
	chip.irq_dead = 1;
	CHECK(xsurf_load("intr=2") == 0);
    }
    CHECK(B->intr == XSURF_MODE_POLLED && !host_attached());
    CHECK(strstr(host_console, "polled (interrupt self-test failed)") != NULL);
    shutdown();

    cur = "intr-zero";
    boot("intr=0");
    CHECK(B->intr == XSURF_MODE_POLLED && !host_attached());
    CHECK(strstr(host_console, ", polled\n") != NULL);
    shutdown();

    cur = "intr-attach-fails";
    host_console[0] = 0;
    chip_power_on(MAC);
    host_attach_fail = 1;
    CHECK(xsurf_load("") == 0);
    host_attach_fail = 0;
    CHECK(B->intr == XSURF_MODE_POLLED);
    shutdown();

    cur = "intr-bad-param";
    boot("intr=7");
    CHECK(strstr(host_console, "intr=7 is not 0 or 2") != NULL);
    CHECK(B->intr == XSURF_MODE_INTR);
    shutdown();
}

static void
t_intr_stops()
{
    mblk_t *mp;
    char *p;
    int n = 0;

    cur = "intr-stops-fallback";
    boot("");
    s_open(&S[0], 0);
    bind(&S[0], 0x800);
    chip.irq_dead = 1;				/* the interrupt stops coming */
    inject(MAC, 0x800, 100, 6);
    CHECK(host_interrupt() == 0);
    ticks(XS_STUCK_TICKS);
    CHECK(B->intr == XSURF_MODE_POLLED && B->st.irq_fallbacks == 1);
    mp = s_up(&S[0]);
    CHECK(ind_ok(mp, 100, 6));
    freemsg(mp);
    ticks(10);
    for (p = host_console; (p = strstr(p, "interrupts stopped; polled")); p++)
	n++;
    CHECK(n == 1);
    shutdown();
}

static void
t_load_unload()
{
    cur = "load-no-board";
    host_console[0] = 0;
    chip_power_on(MAC);
    host_boards = 0;
    CHECK(xsurf_load("") == ENXIO);
    host_boards = 1;
    CHECK(!host_attached() && !host_tick_armed() && host_ifs_count == 0);

    cur = "unload-busy-and-halt";
    boot("");
    s_open(&S[0], 0);
    CHECK(xsurf_unload() == EBUSY);
    xsurf_halt();
    CHECK(chip.started == 0 && chip.imr == 0 && !host_tick_armed());
    shutdown();
}

int
main()
{
    host_window = calloc(1, 16);
    t_open();
    t_info_bind();
    t_bad_requests();
    t_ack_nomem();
    t_tx_frame();
    t_rx_deliver();
    t_rx_hostile();
    t_rx_nomem();
    t_ioctl();
    t_prom();
    t_ring();
    t_overrun();
    t_overrun_resend();
    t_overrun_reply();
    t_counters();
    t_tx_abort();
    t_tx_timeout();
    t_tx_slots();
    t_dma_timeout();
    t_resync();
    t_interrupts();
    t_intr_stops();
    t_load_unload();
    printf("t_core: %d checks, %d failed\n", n_checks, n_fail);
    return n_fail != 0;
}
