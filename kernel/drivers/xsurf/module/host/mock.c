/*
 * mock.c -- the host tests' kernel and chip.
 *
 * The kernel: STREAMS queues and messages (with allocb failures on demand),
 * timeouts run by hand, the interrupt level, interrupt chains, the
 * interface list and the console.
 *
 * The chip: a DP8390 model behind the driver's back-end operations, with
 * what the emulator cannot do: receive overrun (and a check that the
 * documented recovery was followed before the receiver runs again), tally
 * counters that keep CNT set until read, transmit aborts, a transmit that
 * never completes, a remote DMA that never completes, a corrupt ring header,
 * a dead interrupt line, and a record of remote reads past the count.
 */
#include <stdarg.h>
#include "hostk.h"
#include "xsurf.h"
#include "mock.h"

static int	chip_irq_line();

/* ---------------- the kernel ---------------- */
long	lbolt;
char	*panicstr;
unsigned char	*host_window;
unsigned long	host_window_phys;
int	host_ipl;
int	host_alloc_fail;		/* allocb fails this many times */
int	host_live;			/* messages allocated, not freed */
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

/* to the stream head above a read queue */
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
    if (host_upstream_hook)
	(*host_upstream_hook)(q, mp);
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

static void (*host_to_fn)();
static caddr_t host_to_arg;

int
timeout(void (*fn)(), caddr_t arg, long ticks)
{
    host_to_fn = fn;
    host_to_arg = arg;
    return 7;
}

void
untimeout(int id)
{
    host_to_fn = NULL;
}

/* one clock tick: lbolt, then the callout, at IPL 4 */
void
host_tick()
{
    void (*fn)() = host_to_fn;
    int s;

    lbolt++;
    if (fn) {
	host_to_fn = NULL;
	s = spl6();
	(*fn)(host_to_arg);
	splx(s);
    }
}

int
host_tick_armed()
{
    return host_to_fn != NULL;
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

static int (*host_l2_fn)();
static char *host_l2_arg;
int	host_attach_fail;

int
intr_attach(int level, int (*fn)(), char *arg, char *name)
{
    if (level != 2)
	return EINVAL;
    if (host_attach_fail)
	return ENXIO;
    host_l2_fn = fn;
    host_l2_arg = arg;
    return 0;
}

int
intr_detach(int level, int (*fn)(), char *arg)
{
    host_l2_fn = NULL;
    return 0;
}

/* a level-2 interrupt, taken only below IPL 2: 1 when it was claimed */
int
host_interrupt()
{
    int s, r;

    if (host_l2_fn == NULL || host_ipl >= 2)
	return 0;
    s = host_ipl;
    host_ipl = 2;
    r = (*host_l2_fn)(host_l2_arg);
    host_ipl = s;
    return r;
}

int
host_attached()
{
    return host_l2_fn != NULL;
}

int	host_ifs_count;

int
if_attach(struct ifstats *ifs)
{
    host_ifs_count++;
    return 0;
}

int
if_detach(struct ifstats *ifs)
{
    host_ifs_count--;
    return 0;
}

/* a delay: a pending level-2 interrupt is taken during it, as on a box */
void
xs_udelay(long us)
{
    if (host_ipl < 2 && host_l2_fn && chip_irq_line())
	(void)host_interrupt();
}

/* ---------------- the chip ---------------- */
struct chip	chip;

static int
chip_irq_line()
{
    return !chip.irq_dead && (chip.isr & chip.imr) != 0;
}

void
chip_power_on(unsigned char *mac)
{
    int i;

    memset(&chip, 0, sizeof chip);
    for (i = 0; i < 6; i++)
	chip.mem[2 * i] = chip.mem[2 * i + 1] = mac[i];
    chip.mem[28] = chip.mem[29] = 0x57;
    chip.cr = 0x21;
    chip.isr = 0x80;
}

static void
chip_rdc_check()
{
    if (chip.rbcr == 0 && chip.dma && !chip.rdc_never)
	chip.isr |= XS_I_RDC;
}

static void
chip_transmit()
{
    int i, a = chip.tpsr << 8;

    if (chip.tcr & XS_TCR_LOOP) {
	chip.loop_sends++;
	chip.isr |= XS_I_PTX;
	chip.tsr = XS_TSR_PTX;
	return;
    }
    if (chip.tx_mode == TX_HANG) {
	chip.txing = 1;
	return;
    }
    if (chip.wire_n < WIRE_MAX) {
	for (i = 0; i < chip.tbcr && i < 1600; i++)
	    chip.wire[chip.wire_n][i] = chip.mem[(a + i) & 0x7fff];
	chip.wire_len[chip.wire_n] = chip.tbcr;
    }
    chip.wire_n++;
    if (chip.tx_mode == TX_ABORT) {
	chip.wire_n--;			/* aborted: it never made it */
	chip.isr |= XS_I_TXE;
	chip.tsr = XS_TSR_ABT;
	if (chip.tx_abort_count > 0 && --chip.tx_abort_count == 0)
	    chip.tx_mode = TX_OK;
    } else {
	chip.isr |= XS_I_PTX;
	chip.tsr = XS_TSR_PTX;
    }
}

static void
chip_cmd(int v)
{
    int was_stopped = !chip.started;

    if (v & XS_CR_STP) {
	chip.started = 0;
	chip.txing = 0;			/* a stop ends a transmit, unsent */
	chip.isr |= XS_I_RST;
	if (chip.ovw)
	    chip.rec_stp = 1;
    }
    if (v & XS_CR_STA) {
	if (was_stopped && chip.ovw && chip.rec_stp && chip.rec_rbcr &&
	    (chip.tcr & XS_TCR_LOOP))
	    chip.rec_loop = 1;
	chip.started = 1;
	chip.isr &= ~XS_I_RST;
    }
    chip.cr = (v & ~XS_CR_TXP) | (chip.txing ? XS_CR_TXP : 0);
    if (v & (XS_CR_RREAD | XS_CR_RWRITE)) {
	chip.dma = (v & XS_CR_RREAD) ? 1 : 2;
	chip_rdc_check();
    } else if (v & XS_CR_NODMA)
	chip.dma = 0;
    if (v & XS_CR_TXP) {
	chip.txp_count++;
	chip_transmit();
	chip.cr = (chip.cr & ~XS_CR_TXP) | (chip.txing ? XS_CR_TXP : 0);
    }
}

static int
chip_data_read()
{
    int v;

    if (chip.dma != 1 || chip.rbcr <= 0) {
	chip.overread++;
	return 0xff;
    }
    if (chip.rsar >= 0x8000) {
	chip.bad_addr++;
	return 0xee;
    }
    v = chip.mem[chip.rsar];
    chip.rsar++;
    chip.rbcr--;
    chip_rdc_check();
    return v;
}

static void
chip_data_write(int v)
{
    if (chip.dma != 2 || chip.rbcr <= 0) {
	chip.overwrite++;
	return;
    }
    if (chip.rsar < 0x4000 || chip.rsar >= 0x8000)
	chip.bad_addr++;
    else
	chip.mem[chip.rsar] = v;
    chip.rsar++;
    chip.rbcr--;
    chip_rdc_check();
}

int
chip_rd(int r)
{
    int page = (chip.cr >> 6) & 3, v;

    if (r == XS_CR)
	return chip.cr;
    if (r == XS_DATA)
	return chip_data_read();
    if (r == XS_RESET) {
	chip.started = 0;
	chip.txing = 0;
	chip.isr |= XS_I_RST;
	chip.cr = 0x21;
	chip.resets++;
	return 0;
    }
    if (r > 0x0f)
	return 0;
    if (page == 1) {
	if (r >= 1 && r <= 6)
	    return chip.par[r - 1];
	if (r == XS_CURR)
	    return chip.curr;
	return chip.mar[r - 8];
    }
    switch (r) {
    case XS_BNRY: return chip.bnry;
    case XS_TSR: return chip.tsr;
    case XS_ISR: return chip.isr;
    case XS_CNTR0: case XS_CNTR1: case XS_CNTR2:
	v = chip.cntr[r - XS_CNTR0];
	chip.cntr[r - XS_CNTR0] = 0;
	return v;
    }
    return 0;
}

void
chip_wr(int r, int v)
{
    int page = (chip.cr >> 6) & 3, i;

    v &= 0xff;
    if (r == XS_CR) {
	chip_cmd(v);
	return;
    }
    if (r == XS_DATA) {
	chip_data_write(v);
	return;
    }
    if (r == XS_GPOC) {
	if (chip.rbcr != 0)
	    chip.gpoc_in_dma++;		/* the emulator would move data */
	chip.gpoc = v;
	return;
    }
    if (r > 0x0f)
	return;
    if (page == 1) {
	if (r >= 1 && r <= 6)
	    chip.par[r - 1] = v;
	else if (r == XS_CURR)
	    chip.curr = v;
	else
	    chip.mar[r - 8] = v;
	return;
    }
    switch (r) {
    case XS_PSTART: chip.pstart = v; break;
    case XS_PSTOP: chip.pstop = v; break;
    case XS_BNRY: chip.bnry = v; break;
    case XS_TPSR: chip.tpsr = v; break;
    case XS_TBCR0: chip.tbcr = (chip.tbcr & 0xff00) | v; break;
    case XS_TBCR1: chip.tbcr = (chip.tbcr & 0xff) | (v << 8); break;
    case XS_ISR:
	chip.isr &= ~(v & 0x7f);
	for (i = 0; i < 3; i++)
	    if (chip.cntr[i] & 0x80)
		chip.isr |= XS_I_CNT;	/* not read: CNT comes back */
	if ((v & XS_I_OVW) && chip.ovw) {
	    if (chip.rec_stp && chip.rec_rbcr && chip.rec_loop)
		chip.ovw = 0;		/* the receiver runs again */
	    else
		chip.ovw_bad_ack++;	/* the receiver stays stopped */
	}
	break;
    case XS_RSAR0: chip.rsar = (chip.rsar & 0xff00) | v; break;
    case XS_RSAR1: chip.rsar = (chip.rsar & 0xff) | (v << 8); break;
    case XS_RBCR0: chip.rbcr = (chip.rbcr & 0xff00) | v; goto rb;
    case XS_RBCR1: chip.rbcr = (chip.rbcr & 0xff) | (v << 8);
    rb:
	if (chip.ovw && chip.rec_stp && chip.rbcr == 0)
	    chip.rec_rbcr = 1;
	break;
    case XS_RCR: chip.rcr = v; break;
    case XS_TCR: chip.tcr = v; break;
    case XS_DCR: chip.dcr = v; break;
    case XS_IMR: chip.imr = v; break;
    }
}

/*
 * A frame arrives from the wire: into the ring at CURR, as the chip writes
 * it (header: status, next page, count = frame + 4, low byte first), or an
 * overrun when it does not fit before BNRY.  0 = not taken.
 */
int
chip_receive(unsigned char *frame, int len, int status, int force_next)
{
    int ring = chip.pstop - chip.pstart, total = len + 4;
    int pages = (total + 4 + 255) >> 8, avail, next, a, i;

    if (!chip.started || chip.ovw || (chip.rcr & XS_RCR_MON)) {
	chip.rx_dropped++;
	return 0;
    }
    avail = (chip.bnry - chip.curr + ring) % ring;	/* free pages */
    if (pages > avail) {
	chip.ovw = 1;
	chip.rec_stp = chip.rec_rbcr = chip.rec_loop = 0;
	chip.isr |= XS_I_OVW;
	chip.rx_dropped++;
	return 0;
    }
    next = chip.curr + pages;
    if (next >= chip.pstop)
	next -= ring;
    a = chip.curr << 8;
    chip.mem[a] = status;
    chip.mem[a + 1] = force_next ? force_next : next;
    chip.mem[a + 2] = total & 0xff;
    chip.mem[a + 3] = total >> 8;
    a += 4;
    for (i = 0; i < len; i++) {
	if (a >= chip.pstop << 8)
	    a = chip.pstart << 8;
	chip.mem[a++] = frame[i];
    }
    chip.curr = next;
    chip.isr |= XS_I_PRX;
    return 1;
}

/* a transmit that was hanging completes now */
void
chip_tx_complete()
{
    if (chip.txing) {
	chip.txing = 0;
	chip.cr &= ~XS_CR_TXP;
	chip.tx_mode = TX_OK;
	chip_transmit();
    }
}

/* ---------------- the board ---------------- */
static int
m_rd(xs_board_t *b, int r)
{
    return chip_rd(r);
}

static void
m_wr(xs_board_t *b, int r, int v)
{
    chip_wr(r, v);
}

static void
m_bin(xs_board_t *b, unsigned char *buf, int len)
{
    while (len-- > 0)
	*buf++ = chip_data_read();
}

static void
m_bout(xs_board_t *b, unsigned char *buf, int len)
{
    if (len & 1)
	chip.odd_bout++;
    while (len-- > 0)
	chip_data_write(*buf++);
}

static int
m_irq(xs_board_t *b)
{
    return chip_irq_line();
}

static void
m_phy(xs_board_t *b, int on)
{
    chip_wr(XS_GPOC, on ? 0 : XS_GPOC_PPDSET);
}

struct xs_ops host_ops = {
    "Model", XSURF_KIND_XSURF100, 0x40, m_rd, m_wr, m_bin, m_bout, m_irq, m_phy,
};
int	host_boards = 1;

/* the core tests' board finder: one board on the model chip */
int
xs_find_boards()
{
    xs_board_t *b;
    int i;

    xs_nboards = 0;
    for (i = 0; i < host_boards && i < 1; i++) {
	b = &xs_board[i];
	memset(b, 0, sizeof *b);
	b->ops = &host_ops;
	b->unit = i;
	b->tx_cur = -1;
	if (!xs_chip_reset(b) || !xs_read_prom(b, b->mac))
	    return 0;
	xs_chip_init(b, 0);
	b->present = 1;
	b->st.zorro = 2;
	b->phys = 0xe90000;
	xs_nboards++;
    }
    return xs_nboards;
}

void
xs_unmap(xs_board_t *b)
{
}
