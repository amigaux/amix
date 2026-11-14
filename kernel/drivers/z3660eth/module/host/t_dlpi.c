/*
 * t_dlpi.c -- host tests of z3660eth.c's STREAMS/DLPI side, against the
 * module form of the shipped source built for the host (zmock.c is the
 * kernel and the firmware).  Each test loads the module, drives it through
 * its STREAMS entry points and the poll tick, and checks what reached the
 * wire, what went upstream and the status record.
 *
 * The driver handles the frame's type field as a native 16-bit word, which is
 * network order on the 68k; the host is little-endian, so the tests write and
 * read that field the same way (TYPE16), and every other byte as it is.
 */
#include <stddef.h>
#include "zhostk.h"
#include "../../src/z3660eth.h"
#include "zmock.h"

extern struct streamtab z3660ethinfo;
extern int	z3660eth_load(), z3660eth_unload();
extern void	z3660eth_halt();

static int	n_checks, n_fail;
static char	*cur;
#define CHECK(c) do { n_checks++; if (!(c)) { n_fail++; \
	printf("FAIL %s: %s (line %d)\n", cur, #c, __LINE__); } } while (0)

#define TYPE16(p)	(*(unsigned short *)(p))

static unsigned char MAC[6] = { 0x00, 0x80, 0x10, 0x00, 0x01, 0x00 };
static unsigned char PEER[6] = { 0x02, 0x00, 0x00, 0x00, 0x00, 0x99 };
static unsigned char BCAST[6] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };

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
    s->dev = makedevice(51, minor);
    e = (*z3660ethinfo.st_rdinit->qi_qopen)(&s->rq, &s->dev, 0, sflag, NULL);
    s->open = e == 0;
    return e;
}

static int s_open(struct strm *s, int minor) { return s_open_flag(s, minor, 0); }

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
s_close(struct strm *s)
{
    mblk_t *mp;

    if (!s->open)
	return;
    (*z3660ethinfo.st_rdinit->qi_qclose)(&s->rq);
    flushq(&s->wq, FLUSHALL);
    while ((mp = s_up(s)) != NULL)
	freemsg(mp);
    s->open = 0;
}

static void
s_put(struct strm *s, mblk_t *mp)
{
    (*z3660ethinfo.st_wrinit->qi_putp)(&s->wq, mp);
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

static ulong prim_of(mblk_t *mp) { return *(ulong *)mp->b_rptr; }

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

static z3660eth_status_t *
status()
{
    static z3660eth_status_t st;
    struct strm t;
    mblk_t *mp;
    struct iocblk *io;

    s_open(&t, 0);
    mp = allocb(sizeof(struct copyreq), BPRI_MED);
    mp->b_datap->db_type = M_IOCTL;
    io = (struct iocblk *)mp->b_wptr;
    memset(io, 0, sizeof(struct copyreq));
    io->ioc_cmd = Z3660ETH_GET_STATUS;
    mp->b_wptr += sizeof(struct iocblk);
    s_put(&t, mp);
    mp = s_up(&t);
    memset(&st, 0, sizeof st);
    if (mp && mp->b_datap->db_type == M_IOCACK && mp->b_cont)
	memcpy(&st, mp->b_cont->b_rptr, sizeof st);
    freemsg(mp);
    s_close(&t);
    return &st;
}

static void
boot()
{
    int i;

    for (i = 0; i < 8; i++)
	memset(&S[i], 0, sizeof S[i]);
    host_console[0] = 0;
    lbolt = 1000;
    host_ipl = 0;
    host_alloc_fail = 0;
    zm_power_on(MAC);
    CHECK(z3660eth_load(0) == 0);
}

static void
shutdown()
{
    int i;

    for (i = 0; i < 8; i++)
	s_close(&S[i]);
    CHECK(z3660eth_unload() == 0);
    CHECK(!host_tick_armed());
    CHECK(host_ifs_count == 0);
    CHECK(host_live == 0);
}

/* ---------------- the tests ---------------- */
static void
t_primitives()
{
    mblk_t *mp;
    dl_info_ack_t *ia;
    dl_bind_ack_t *ba;
    dl_error_ack_t *e;

    cur = "primitives";
    boot();
    CHECK(s_open(&S[0], 0) == 0 && getminor(S[0].dev) == 0x10);
    CHECK(s_open_flag(&S[1], 0, CLONEOPEN) == EINVAL);
    s_put(&S[0], proto(4, DL_INFO_REQ));
    mp = expect(&S[0], DL_INFO_ACK);
    ia = (dl_info_ack_t *)mp->b_rptr;
    CHECK(ia->dl_provider_style == DL_STYLE1 && ia->dl_addr_offset == 0);
    freemsg(mp);
    s_put(&S[0], proto(4, DL_ATTACH_REQ));
    mp = expect(&S[0], DL_OK_ACK);
    CHECK(((dl_ok_ack_t *)mp->b_rptr)->dl_correct_primitive == DL_ATTACH_REQ);
    freemsg(mp);
    s_put(&S[0], bind_req(0x800));
    mp = expect(&S[0], DL_BIND_ACK);
    ba = (dl_bind_ack_t *)mp->b_rptr;
    CHECK(ba->dl_sap == 0x800 && memcmp(mp->b_rptr + ba->dl_addr_offset, MAC, 6) == 0);
    freemsg(mp);
    s_put(&S[0], proto(4, DL_INFO_REQ));
    mp = expect(&S[0], DL_INFO_ACK);
    ia = (dl_info_ack_t *)mp->b_rptr;
    CHECK(ia->dl_current_state == DL_IDLE && memcmp(mp->b_rptr + ia->dl_addr_offset, MAC, 6) == 0);
    freemsg(mp);
    s_put(&S[0], proto(4, DL_UNBIND_REQ));
    freemsg(expect(&S[0], DL_OK_ACK));
    s_put(&S[0], proto(4, DL_DETACH_REQ));
    freemsg(expect(&S[0], DL_OK_ACK));

    s_put(&S[0], proto(4, 0x55));				/* unknown */
    mp = expect(&S[0], DL_ERROR_ACK);
    e = (dl_error_ack_t *)mp->b_rptr;
    CHECK(e->dl_error_primitive == 0x55 && e->dl_errno == DL_BADPRIM);
    freemsg(mp);
    s_put(&S[0], proto(2, 0));					/* shorter than a primitive */
    CHECK(s_upcount(&S[0]) == 0);
    s_put(&S[0], proto(8, DL_BIND_REQ));			/* short bind */
    mp = expect(&S[0], DL_ERROR_ACK);
    CHECK(((dl_error_ack_t *)mp->b_rptr)->dl_errno == DL_BADPRIM);
    freemsg(mp);
    s_put(&S[0], bind_req(0x12345));				/* SAP over 16 bits */
    mp = expect(&S[0], DL_ERROR_ACK);
    CHECK(((dl_error_ack_t *)mp->b_rptr)->dl_errno == DL_BADSAP);
    freemsg(mp);
    shutdown();
}

static void
t_ack_nomem()
{
    mblk_t *mp;

    cur = "ack-nomem-retried";
    boot();
    s_open(&S[0], 0);
    mp = bind_req(0x800);
    host_alloc_fail = 1;
    s_put(&S[0], mp);
    CHECK(s_upcount(&S[0]) == 0 && S[0].wq.q_first != NULL);
    s_put(&S[0], proto(4, DL_INFO_REQ));			/* behind it, in order */
    CHECK(s_upcount(&S[0]) == 0);
    host_tick();
    freemsg(expect(&S[0], DL_BIND_ACK));
    freemsg(expect(&S[0], DL_INFO_ACK));
    CHECK(s_upcount(&S[0]) == 0);
    mp = proto(4, 0x55);
    host_alloc_fail = 1;
    s_put(&S[0], mp);
    CHECK(s_upcount(&S[0]) == 0);
    host_tick();
    freemsg(expect(&S[0], DL_ERROR_ACK));
    mp = proto(4, DL_UNBIND_REQ);
    host_alloc_fail = 1;
    s_put(&S[0], mp);
    host_tick();
    freemsg(expect(&S[0], DL_OK_ACK));
    CHECK(s_upcount(&S[0]) == 0);
    shutdown();
}

static void
t_unitdata()
{
    z3660eth_status_t *st;
    int i, ok;

    cur = "unitdata-checks";
    boot();
    s_open(&S[0], 0);
    s_put(&S[0], send_ok(PEER, 20, 0));			/* not bound yet */
    CHECK(zm.wire_n == 0);
    bind(&S[0], 0x800);
    s_put(&S[0], unitdata(PEER, 6, 200, 20, 0));		/* address outside the block */
    s_put(&S[0], unitdata(PEER, 6, -1, 20, 0));		/* offset wraps */
    s_put(&S[0], unitdata(PEER, 4, sizeof(dl_unitdata_req_t), 20, 0));
    s_put(&S[0], proto(8, DL_UNITDATA_REQ));			/* short request */
    CHECK(zm.wire_n == 0);
    s_put(&S[0], send_ok(PEER, 10, 3));
    CHECK(zm.wire_n == 1 && zm.wire_len[0] == 60);
    CHECK(memcmp(zm.wire[0], PEER, 6) == 0 && memcmp(zm.wire[0] + 6, MAC, 6) == 0);
    CHECK(TYPE16(zm.wire[0] + 12) == 0x0800);
    for (ok = 1, i = 24; i < 60; i++)
	ok &= zm.wire[0][i] == 0;
    CHECK(ok);
    st = status();
    CHECK(st->tx_bad_req == 4 && st->tx_unbound == 1);
    CHECK(offsetof(z3660eth_status_t, tx_bad_req) == 27 * sizeof(unsigned int));
    CHECK(offsetof(z3660eth_status_t, tx_unbound) == 28 * sizeof(unsigned int));
    shutdown();
}

static void
t_receive()
{
    unsigned char f[200];
    mblk_t *mp;
    int i;

    cur = "receive-to-every-bound-stream";
    boot();
    s_open(&S[0], 0);
    s_open(&S[1], 0);
    bind(&S[0], 0x800);
    bind(&S[1], 0x800);
    memcpy(f, BCAST, 6);
    memcpy(f + 6, PEER, 6);
    TYPE16(f + 12) = 0x0800;
    for (i = 14; i < 100; i++)
	f[i] = i;
    CHECK(zm_receive(f, 100));
    host_tick();
    for (i = 0; i < 2; i++) {
	mp = s_up(&S[i]);
	CHECK(mp && prim_of(mp) == DL_UNITDATA_IND && mp->b_cont &&
	      mp->b_cont->b_wptr - mp->b_cont->b_rptr == 86 && mp->b_cont->b_rptr[0] == 14);
	freemsg(mp);
    }
    TYPE16(f + 12) = 0x1001;					/* trailer type */
    CHECK(zm_receive(f, 100));
    host_tick();
    CHECK(s_upcount(&S[0]) == 0 && s_upcount(&S[1]) == 0);
    shutdown();
}

int
main()
{
    t_primitives();
    t_ack_nomem();
    t_unitdata();
    t_receive();
    printf("t_dlpi: %d checks, %d failed\n", n_checks, n_fail);
    return n_fail != 0;
}
