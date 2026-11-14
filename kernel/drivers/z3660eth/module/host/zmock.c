/*
 * zmock.c -- the z3660eth host tests' kernel and firmware.
 *
 * The kernel: STREAMS queues and messages (allocb failures on demand),
 * timeouts run by hand, the interrupt level, the interface list, the
 * console.  The firmware: the Z3660's ethernet register file and its frame
 * windows, as z3660eth.c reads them (z3660eth.h): the station address in
 * MAC_HI/MAC_LO, the RX backlog (slots of [len][serial] + frame, the cursor
 * in RX_ADDR, advanced by the ETH_RX strobe; when the driver has caught up
 * the backlog restarts at slot 0 carrying the released serial), and a
 * synchronous transmit from the TX frame window.
 */
#include <stdarg.h>
#include "zhostk.h"
#include "../../src/z3660eth.h"
#include "zmock.h"

long	lbolt;
char	*panicstr;
unsigned char	*host_window;
unsigned long	host_window_phys = ZM_BASE;
int	host_ipl, host_alloc_fail, host_live, host_ifs_count;
char	host_console[8192];

void
cmn_err(int level, char *fmt, ...)
{
    char line[512];
    va_list ap;

    va_start(ap, fmt);
    vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    if (strlen(host_console) + strlen(line) + 2 < sizeof host_console) {
	strcat(host_console, line);
	if (level != CE_CONT)
	    strcat(host_console, "\n");
    }
}

mblk_t *
allocb(int size, int pri)
{
    mblk_t *mp;

    if (host_alloc_fail > 0) {
	host_alloc_fail--;
	return NULL;
    }
    mp = calloc(1, sizeof(mblk_t));
    mp->b_datap = calloc(1, sizeof(struct datab));
    mp->b_datap->db_base = calloc(1, size + 64);
    mp->b_datap->db_lim = mp->b_datap->db_base + size + 64;
    mp->b_rptr = mp->b_wptr = mp->b_datap->db_base;
    host_live++;
    return mp;
}

void
freemsg(mblk_t *mp)
{
    mblk_t *n;

    for (; mp; mp = n) {
	n = mp->b_cont;
	free(mp->b_datap->db_base);
	free(mp->b_datap);
	free(mp);
	host_live--;
    }
}

mblk_t *
unlinkb(mblk_t *mp)
{
    mblk_t *c = mp->b_cont;

    mp->b_cont = NULL;
    return c;
}

void
putnext(queue_t *q, mblk_t *mp)
{
    queue_t *h = q->q_next;

    mp->b_next = NULL;
    if (h->up_last)
	h->up_last->b_next = mp;
    else
	h->up_first = mp;
    h->up_last = mp;
}

void
qreply(queue_t *q, mblk_t *mp)
{
    putnext(OTHERQ(q), mp);
}

int
putq(queue_t *q, mblk_t *mp)
{
    mp->b_next = NULL;
    if (q->q_last)
	q->q_last->b_next = mp;
    else
	q->q_first = mp;
    q->q_last = mp;
    return 1;
}

int
putbq(queue_t *q, mblk_t *mp)
{
    mp->b_next = q->q_first;
    q->q_first = mp;
    if (q->q_last == NULL)
	q->q_last = mp;
    return 1;
}

mblk_t *
getq(queue_t *q)
{
    mblk_t *mp = q->q_first;

    if (mp) {
	q->q_first = mp->b_next;
	if (q->q_first == NULL)
	    q->q_last = NULL;
	mp->b_next = NULL;
    }
    return mp;
}

void
flushq(queue_t *q, int flag)
{
    mblk_t *mp;

    while ((mp = getq(q)) != NULL)
	freemsg(mp);
}

int
canput(queue_t *q)
{
    return !q->full;
}

static void (*to_fn)();
static caddr_t to_arg;

int
timeout(void (*fn)(), caddr_t arg, long ticks)
{
    to_fn = fn;
    to_arg = arg;
    return 7;
}

void
untimeout(int id)
{
    to_fn = NULL;
}

/* one clock tick: lbolt, then the callout at IPL 4 */
void
host_tick()
{
    void (*fn)() = to_fn;
    int s;

    lbolt++;
    if (fn) {
	to_fn = NULL;
	s = spl6();
	(*fn)(to_arg);
	splx(s);
    }
}

int
host_tick_armed()
{
    return to_fn != NULL;
}

int
spl6()
{
    int s = host_ipl;

    host_ipl = 4;
    return s;
}

int
splx(int s)
{
    int o = host_ipl;

    host_ipl = s;
    return o;
}

void wakeup(caddr_t c) { }
int sleep(caddr_t c, int p) { return 0; }
int intr_attach(int l, int (*f)(), char *a, char *n) { return ENXIO; }	/* intr=0 only */
int intr_detach(int l, int (*f)(), char *a) { return 0; }
int if_attach(struct ifstats *ifs) { host_ifs_count++; return 0; }
int if_detach(struct ifstats *ifs) { host_ifs_count--; return 0; }
int bprobe(caddr_t a, int v) { return 0; }
caddr_t sptalloc(int n, int m, unsigned long pfn, int f) { return NULL; }
void sptfree(caddr_t va, int n, int f) { }

int
autocon(unsigned long id, int index, long *addr, long *size)
{
    if (id != Z3660_PROD || index != 0 || !zm.present)
	return 0;
    *addr = ZM_BASE;
    *size = 0x08000000;
    return 1;
}

/* ---------------- the firmware ---------------- */
struct zm zm;

static unsigned char *
slot(int k)
{
    return host_window + ZZ_RXBACKLOG_OFF + k * ZZ_FRAME_SIZE;
}

void
zm_power_on(unsigned char *mac)
{
    if (host_window == NULL)
	host_window = calloc(1, 0x08000000);		/* touched pages only */
    memset(slot(0), 0, ZZ_RX_MAX_SLOTS * ZZ_FRAME_SIZE);
    memset(&zm, 0, sizeof zm);
    zm.present = 1;
    zm.machi = (mac[0] << 8) | mac[1];
    zm.maclo = ((unsigned long)mac[2] << 24) | (mac[3] << 16) | (mac[4] << 8) | mac[5];
}

unsigned long
zz_host_rd(unsigned long off)
{
    switch (off) {
    case ZZ_ETH_MAC_HI: return zm.machi;
    case ZZ_ETH_MAC_LO: return zm.maclo;
    case ZZ_ETH_RX_ADDR: return ZZ_RXBACKLOG_OFF + zm.rd * ZZ_FRAME_SIZE;
    case ZZ_INT_STATUS: return 0;
    case ZZ_ETH_TX: return zm.tx_rc;
    }
    return 0;
}

void
zz_host_wr(unsigned long off, unsigned long v)
{
    unsigned char *f = host_window + ZZ_TXFRAME_OFF;
    int i;

    switch (off) {
    case ZZ_CONFIG:
	zm.config = v;
	break;
    case ZZ_ETH_RX:			/* free the cursor's slot */
	zm.strobes++;
	if (zm.rd + 1 < zm.wr)
	    zm.rd++;
	else {				/* caught up: the backlog restarts */
	    slot(0)[2] = slot(zm.rd)[2];
	    slot(0)[3] = slot(zm.rd)[3];
	    zm.rd = zm.wr = 0;
	}
	break;
    case ZZ_ETH_TX:			/* synchronous: the frame leaves now */
	if (zm.tx_rc == 0 && zm.wire_n < ZM_WIRE) {
	    for (i = 0; i < (int)v && i < 1600; i++)
		zm.wire[zm.wire_n][i] = f[i];
	    zm.wire_len[zm.wire_n] = v;
	}
	if (zm.tx_rc == 0)
	    zm.wire_n++;
	break;
    }
}

void zz_host_raise(int bits) { }

/* a frame arrives: into the next backlog slot, the serial written last */
int
zm_receive(unsigned char *frame, int len)
{
    unsigned char *p;

    if (zm.wr >= ZZ_RX_RING_SLOTS)
	return 0;
    p = slot(zm.wr);
    memcpy(p + ZZ_RX_FRAME_PAD, frame, len);
    p[0] = len >> 8;
    p[1] = len & 0xff;
    zm.serial++;
    p[2] = zm.serial >> 8;
    p[3] = zm.serial & 0xff;
    zm.wr++;
    return 1;
}
