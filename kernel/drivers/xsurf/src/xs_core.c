/*
 * xs_core.c -- the DP8390 core shared by the X-Surf and the X-Surf-100.
 *
 * Written from the chip's documented behaviour (docs/facts.md, "The 8390
 * behaviour both cards share").  Every chip access goes through the card's
 * operations (xs_boards.c), so this file knows registers, not addresses.
 *
 * Context: every entry point runs at IPL 4 (splxs(), xsurf.c), which masks
 * the level-2 interrupt and the clock, so the interrupt handler, the tick
 * and the write side never interleave on the chip or on the state here.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "xsk.h"
#include "xsurf.h"

#define XRD(b, r)	((*(b)->ops->rd)((b), (r)))
#define XWR(b, r, v)	((*(b)->ops->wr)((b), (r), (v)))

static void	xs_rx(), xs_overrun(), xs_tx_kick(), xs_tx_done(), xs_restart();

/* the receive buffer; one at a time at IPL 4, whatever the board */
static unsigned char xs_rxbuf[XS_ETHERMAX + 2];

#ifndef XS_HOSTTEST
/*
 * A delay in microseconds that does not scale with the CPU: every access to
 * a CIA waits for the E clock (709-716 kHz, at least 1.4 us), on a 68000 as
 * on a 68060.  One read of CIA-A's port A per microsecond therefore waits at
 * least `us' microseconds, and at most about twice that.  Port A has no read
 * side effects.
 */
#define XS_CIA_PRA	((volatile unsigned char *)phystokv(0xBFE001))
static volatile unsigned char xs_cia_sink;

void
xs_udelay(us)
long us;
{
    volatile unsigned char *p = XS_CIA_PRA;

    while (us-- > 0)
	xs_cia_sink = *p;
}
#endif

/* page 0, the chip's run state unchanged, no remote DMA */
void
xs_page0(b)
xs_board_t *b;
{
    XWR(b, XS_CR, XS_CR_NODMA | (b->running ? XS_CR_STA : XS_CR_STP));
}

static int
xs_wrap(page)
int page;
{
    if (page < XS_RX_START)
	return page + XS_RX_PAGES;
    if (page >= XS_RX_STOP)
	return page - XS_RX_PAGES;
    return page;
}

/* the boundary is one page behind the next frame to read */
static void
xs_set_next(b, page)
xs_board_t *b;
int page;
{
    b->next = page;
    XWR(b, XS_BNRY, xs_wrap(page - 1));
}

/*
 * Reset the chip: read the reset register and write the value back, then
 * wait for ISR.RST.  0 when nothing answers like an 8390 (open bus reads
 * 0xFF, or RST never comes).
 */
int
xs_chip_reset(b)
xs_board_t *b;
{
    int v, t, isr;

    b->running = 0;
    if (XRD(b, XS_CR) == 0xff)
	return 0;
    v = XRD(b, XS_RESET);
    XWR(b, XS_RESET, v);
    for (t = 0; t < XS_RESET_US; t += 10) {
	if (XRD(b, XS_ISR) & XS_I_RST)
	    break;
	xs_udelay(10L);
    }
    isr = XRD(b, XS_ISR);
    XWR(b, XS_ISR, 0xff);
    return (isr & XS_I_RST) != 0;
}

/*
 * The station address: the chip's PROM image, 32 bytes read in byte mode
 * with the remote count programmed to the bytes read; the address is every
 * second byte.  The chip is stopped and receives nothing meanwhile (monitor
 * mode, internal loopback).  1 when the address is a usable unicast one.
 */
int
xs_read_prom(b, mac)
xs_board_t *b;
unsigned char *mac;
{
    unsigned char prom[XS_PROM_BYTES];
    int i, t, zero, ones;

    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STP);
    XWR(b, XS_DCR, XS_DCR_BYTE);
    XWR(b, XS_RBCR0, 0);
    XWR(b, XS_RBCR1, 0);
    XWR(b, XS_IMR, 0);
    XWR(b, XS_ISR, 0xff);
    XWR(b, XS_RCR, XS_RCR_MON);
    XWR(b, XS_TCR, XS_TCR_LOOP);
    XWR(b, XS_RBCR0, XS_PROM_BYTES);
    XWR(b, XS_RBCR1, 0);
    XWR(b, XS_RSAR0, 0);
    XWR(b, XS_RSAR1, 0);
    XWR(b, XS_CR, XS_CR_RREAD | XS_CR_STA);
    for (i = 0; i < XS_PROM_BYTES; i++)
	prom[i] = XRD(b, XS_DATA);
    for (t = 0; t < XS_RDC_US && !(XRD(b, XS_ISR) & XS_I_RDC); t += 10)
	xs_udelay(10L);
    XWR(b, XS_ISR, XS_I_RDC);
    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STP);

    zero = ones = 0;
    for (i = 0; i < XS_ETHERADDRL; i++) {
	mac[i] = prom[2 * i];
	if (mac[i] == 0x00)
	    zero++;
	if (mac[i] == 0xff)
	    ones++;
    }
    return zero != XS_ETHERADDRL && ones != XS_ETHERADDRL && !(mac[0] & 1);
}

/*
 * Set the chip up in the documented order, stopped; with `start' also start
 * it, transmitter and receiver on.  The interrupt mask follows the board's
 * mode: everything the driver handles in interrupt mode, nothing polled.
 */
void
xs_chip_init(b, start)
xs_board_t *b;
int start;
{
    int i;

    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STP);
    b->running = 0;
    XWR(b, XS_DCR, XS_DCR_WORD);
    XWR(b, XS_RBCR0, 0);
    XWR(b, XS_RBCR1, 0);
    if (b->ops->phy)			/* no remote DMA can be running now */
	(*b->ops->phy)(b, 1);
    XWR(b, XS_RCR, XS_RCR_MON);
    XWR(b, XS_TCR, XS_TCR_LOOP);
    XWR(b, XS_TPSR, XS_TX_START);
    XWR(b, XS_PSTART, XS_RX_START);
    XWR(b, XS_BNRY, XS_RX_STOP - 1);
    XWR(b, XS_PSTOP, XS_RX_STOP);
    XWR(b, XS_ISR, 0xff);
    XWR(b, XS_IMR, 0);

    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_PAGE1 | XS_CR_STP);
    for (i = 0; i < XS_ETHERADDRL; i++)
	XWR(b, XS_PAR0 + i, b->mac[i]);
    for (i = 0; i < 8; i++)
	XWR(b, XS_MAR0 + i, 0);
    XWR(b, XS_CURR, XS_RX_START);
    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STP);

    b->next = XS_RX_START;
    b->tx_len[0] = b->tx_len[1] = 0;
    b->tx_cur = -1;
    b->tx_hold = 0;
    b->need_reset = 0;

    if (start) {
	XWR(b, XS_ISR, 0xff);
	XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STA);
	b->running = 1;
	XWR(b, XS_TCR, XS_TCR_NORMAL);
	XWR(b, XS_RCR, b->ops->rcr | XS_RCR_AB);
	XWR(b, XS_IMR, b->intr == XSURF_MODE_INTR ? XS_IMR_RUN : 0);
    }
}

/* stop the chip and mask it: nothing received, nothing interrupts */
void
xs_chip_stop(b)
xs_board_t *b;
{
    XWR(b, XS_IMR, 0);
    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STP);
    b->running = 0;
}

/* the interrupt mask for the board's mode, the chip running */
void
xs_chip_mask(b, on)
xs_board_t *b;
int on;
{
    xs_page0(b);
    XWR(b, XS_IMR, on ? XS_IMR_RUN : 0);
}

/* events the interrupt would have handled are waiting */
int
xs_pending(b)
xs_board_t *b;
{
    if (!b->running)
	return 0;
    xs_page0(b);
    return (XRD(b, XS_ISR) & XS_IMR_RUN) != 0;
}

/*
 * Remote DMA.  A read moves `len' bytes from packet memory at `offset'
 * through the data port; a write moves an even `len' to `page' and waits
 * for RDC, which says the chip has taken the last word.  0 from a write that
 * never completed: the frame is lost and the chip is reset at the next tick.
 */
void
xs_rdma_read(b, buf, offset, len)
xs_board_t *b;
unsigned char *buf;
int offset, len;
{
    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STA);
    XWR(b, XS_RBCR0, len & 0xff);
    XWR(b, XS_RBCR1, (len >> 8) & 0xff);
    XWR(b, XS_RSAR0, offset & 0xff);
    XWR(b, XS_RSAR1, (offset >> 8) & 0xff);
    XWR(b, XS_CR, XS_CR_RREAD | XS_CR_STA);
    (*b->ops->bin)(b, buf, len);
    XWR(b, XS_ISR, XS_I_RDC);
}

int
xs_rdma_write(b, buf, page, len)
xs_board_t *b;
unsigned char *buf;
int page, len;
{
    int t;

    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STA);
    XWR(b, XS_ISR, XS_I_RDC);
    XWR(b, XS_RBCR0, len & 0xff);
    XWR(b, XS_RBCR1, (len >> 8) & 0xff);
    XWR(b, XS_RSAR0, 0);
    XWR(b, XS_RSAR1, page);
    XWR(b, XS_CR, XS_CR_RWRITE | XS_CR_STA);
    (*b->ops->bout)(b, buf, len);
    for (t = 0; !(XRD(b, XS_ISR) & XS_I_RDC); t += 10) {
	if (t >= XS_RDC_US) {
	    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STA);
	    b->st.tx_dma_timeouts++;
	    b->need_reset = 1;
	    return 0;
	}
	xs_udelay(10L);
    }
    XWR(b, XS_ISR, XS_I_RDC);
    return 1;
}

/*
 * Drain the receive ring: from b->next up to the chip's CURR.  A header
 * whose next-page pointer does not follow from its own length, or points
 * outside the ring, means the ring is corrupt: everything up to CURR is
 * dropped (resync) rather than read as frames.  The ring pointers move
 * before a frame goes upstream, so a transmit the delivery starts (an ARP
 * reply) finds the chip between frames.
 */
static void
xs_rx(b)
xs_board_t *b;
{
    unsigned char hdr[4];
    int n, curr, status, nxt, count, len, exp, offset, first;

    for (n = 0; n < XS_RX_FRAMES; n++) {
	XWR(b, XS_CR, XS_CR_NODMA | XS_CR_PAGE1 | XS_CR_STA);
	curr = XRD(b, XS_CURR);
	XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STA);
	if (curr < XS_RX_START || curr >= XS_RX_STOP) {
	    b->st.rx_resyncs++;
	    b->ifs.ifs_ierrors++;
	    b->need_reset = 1;
	    return;
	}
	if (b->next == curr)
	    return;

	xs_rdma_read(b, hdr, b->next << 8, 4);
	status = hdr[0];
	nxt = hdr[1];
	count = hdr[2] | (hdr[3] << 8);
	len = count - 4;
	exp = xs_wrap(b->next + 1 + (count >> 8));
	if (nxt < XS_RX_START || nxt >= XS_RX_STOP ||
	    (nxt != exp && nxt != xs_wrap(exp + 1))) {
	    b->st.rx_resyncs++;
	    b->ifs.ifs_ierrors++;
	    xs_set_next(b, curr);
	    return;
	}

	if (!(status & XS_RSR_PRX)) {
	    b->st.rx_errors++;
	    b->ifs.ifs_ierrors++;
	    xs_set_next(b, nxt);
	    continue;
	}
	if (len < XS_ETHERMIN || len > XS_ETHERMAX) {
	    b->st.rx_bad_size++;
	    b->ifs.ifs_ierrors++;
	    xs_set_next(b, nxt);
	    continue;
	}
	offset = (b->next << 8) + 4;
	if (offset + len > (XS_RX_STOP << 8)) {
	    first = (XS_RX_STOP << 8) - offset;
	    xs_rdma_read(b, xs_rxbuf, offset, first);
	    xs_rdma_read(b, xs_rxbuf + first, XS_RX_START << 8, len - first);
	} else
	    xs_rdma_read(b, xs_rxbuf, offset, len);
	xs_set_next(b, nxt);
	b->st.rx_frames++;
	b->ifs.ifs_ipackets++;
	xs_deliver(b, xs_rxbuf, len);
    }
}

/*
 * Receive overrun, the documented recovery: note a transmit in progress,
 * stop, wait at least 1.6 ms, clear the remote count, transmitter to
 * loopback, start, drain the ring, acknowledge, transmitter back, and resend
 * a frame that neither completed nor failed.  A transmit a delivery starts
 * meanwhile is only staged (tx_hold): in loopback it would never reach the
 * wire.
 */
static void
xs_overrun(b)
xs_board_t *b;
{
    int was_tx, resend;

    was_tx = XRD(b, XS_CR) & XS_CR_TXP;
    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STP);
    xs_udelay((long)XS_OVW_US);
    XWR(b, XS_RBCR0, 0);
    XWR(b, XS_RBCR1, 0);
    resend = was_tx && !(XRD(b, XS_ISR) & (XS_I_PTX | XS_I_TXE));
    XWR(b, XS_TCR, XS_TCR_LOOP);
    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STA);
    b->tx_hold = 1;
    XWR(b, XS_ISR, XS_I_PRX | XS_I_RXE);
    xs_rx(b);
    XWR(b, XS_ISR, XS_I_OVW);
    XWR(b, XS_TCR, XS_TCR_NORMAL);
    b->tx_hold = 0;
    b->st.rx_overruns++;
    b->ifs.ifs_ierrors++;
    if (resend) {
	XWR(b, XS_CR, XS_CR_NODMA | XS_CR_TXP | XS_CR_STA);
	b->tx_since = lbolt;
	b->st.tx_resends++;
    } else if (b->tx_cur < 0 && (b->tx_len[0] || b->tx_len[1]))
	xs_tx_kick(b, b->tx_len[0] ? 0 : 1);
}

/* a free transmit slot, or -1 */
int
xs_tx_free(b)
xs_board_t *b;
{
    if (b->tx_len[0] == 0)
	return 0;
    if (b->tx_len[1] == 0)
	return 1;
    return -1;
}

static void
xs_tx_kick(b, slot)
xs_board_t *b;
int slot;
{
    int len = b->tx_len[slot];

    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STA);
    XWR(b, XS_TPSR, XS_TX_START + slot * XS_TX_SLOT);
    XWR(b, XS_TBCR0, len & 0xff);
    XWR(b, XS_TBCR1, (len >> 8) & 0xff);
    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_TXP | XS_CR_STA);
    b->tx_cur = slot;
    b->tx_since = lbolt;
}

/*
 * Send a frame of `len' bytes (60..1514; buf holds one byte more, zero, for
 * the even remote-DMA count).  1 when it is sent, staged, or lost to a
 * remote-DMA timeout (counted); 0 when both slots are busy.
 */
int
xs_tx_send(b, buf, len)
xs_board_t *b;
unsigned char *buf;
int len;
{
    int slot = xs_tx_free(b);

    if (slot < 0)
	return 0;
    if (!xs_rdma_write(b, buf, XS_TX_START + slot * XS_TX_SLOT, (len + 1) & ~1)) {
	b->ifs.ifs_oerrors++;
	return 1;
    }
    b->tx_len[slot] = len;
    if (b->tx_cur < 0 && !b->tx_hold)
	xs_tx_kick(b, slot);
    return 1;
}

/* the frame on the wire is finished, sent or not: start the staged one */
static void
xs_tx_done(b)
xs_board_t *b;
{
    int other;

    if (b->tx_cur >= 0) {
	b->tx_len[b->tx_cur] = 0;
	other = 1 - b->tx_cur;
	b->tx_cur = -1;
	if (b->tx_len[other])
	    xs_tx_kick(b, other);
    }
    xs_tx_restart(b);
}

/* restart the chip from nothing: the frames in its slots are lost */
static void
xs_restart(b)
xs_board_t *b;
{
    b->st.resets++;
    if (b->tx_len[0])
	b->ifs.ifs_oerrors++;
    if (b->tx_len[1])
	b->ifs.ifs_oerrors++;
    (void)xs_chip_reset(b);
    xs_chip_init(b, 1);
    xs_tx_restart(b);
}

/*
 * Everything the chip has to say: up to XS_ISR_LOOPS passes over ISR.  The
 * interrupt handler and the tick call it the same way.  ISR bits are
 * acknowledged before the work they announce, so an event during the work
 * shows on the next pass.
 */
void
xs_service(b)
xs_board_t *b;
{
    int n, isr, tsr;

    if (!b->running)
	return;
    for (n = 0; n < XS_ISR_LOOPS; n++) {
	xs_page0(b);
	isr = XRD(b, XS_ISR) & ~XS_I_RST;
	if (isr == 0)
	    break;

	if (isr & XS_I_OVW)
	    xs_overrun(b);
	else if (isr & (XS_I_PRX | XS_I_RXE)) {
	    XWR(b, XS_ISR, isr & (XS_I_PRX | XS_I_RXE));
	    if (isr & XS_I_RXE) {
		b->st.rx_errors++;
		b->ifs.ifs_ierrors++;
	    }
	    xs_rx(b);
	}

	if (isr & XS_I_PTX) {
	    XWR(b, XS_ISR, isr & (XS_I_PTX | XS_I_TXE));
	    tsr = XRD(b, XS_TSR);
	    if (tsr & XS_TSR_COL)
		b->st.tx_collisions++;
	    if (isr & XS_I_TXE) {
		b->st.tx_errors++;
		b->ifs.ifs_oerrors++;
	    } else {
		b->st.tx_frames++;
		b->ifs.ifs_opackets++;
	    }
	    xs_tx_done(b);
	} else if (isr & XS_I_TXE) {
	    /* no PTX: the frame was aborted; it ends here, the next goes */
	    XWR(b, XS_ISR, XS_I_TXE);
	    tsr = XRD(b, XS_TSR);
	    b->st.tx_errors++;
	    b->ifs.ifs_oerrors++;
	    if (tsr & (XS_TSR_ABT | XS_TSR_FU))
		b->st.tx_aborts++;
	    if (tsr & XS_TSR_ABT)
		b->st.tx_collisions += 16;
	    xs_tx_done(b);
	}

	if (isr & XS_I_CNT) {
	    /* all three: an unread counter keeps CNT set */
	    b->st.rx_frame_errors += XRD(b, XS_CNTR0);
	    b->st.rx_crc_errors += XRD(b, XS_CNTR1);
	    b->st.rx_missed += XRD(b, XS_CNTR2);
	    XWR(b, XS_ISR, XS_I_CNT);
	}
	if (isr & XS_I_RDC)
	    XWR(b, XS_ISR, XS_I_RDC);
	if (b->need_reset)
	    break;
    }
    xs_page0(b);
}

/*
 * The tick's watchdog: a chip a remote-DMA timeout or a corrupt CURR marked,
 * or a transmit older than XS_TX_TIMEOUT, is restarted.
 */
void
xs_watch(b)
xs_board_t *b;
{
    if (!b->running)
	return;
    if (b->tx_cur >= 0 && lbolt - b->tx_since > XS_TX_TIMEOUT) {
	b->st.tx_timeouts++;
	b->need_reset = 1;
    }
    if (b->need_reset)
	xs_restart(b);
}

/*
 * The interrupt self-test, in two halves around a wait at IPL 0: a remote
 * read of one word sets RDC, and with only RDC unmasked the board raises
 * its interrupt.  xs_selftest_ack is the handler's half.
 */
void
xs_selftest_kick(b)
xs_board_t *b;
{
    unsigned char w[2];

    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STA);
    XWR(b, XS_IMR, 0);
    XWR(b, XS_ISR, XS_I_RDC);
    XWR(b, XS_RBCR0, 2);
    XWR(b, XS_RBCR1, 0);
    XWR(b, XS_RSAR0, 0);
    XWR(b, XS_RSAR1, XS_RX_START);
    XWR(b, XS_CR, XS_CR_RREAD | XS_CR_STA);
    (*b->ops->bin)(b, w, 2);
    XWR(b, XS_CR, XS_CR_NODMA | XS_CR_STA);
    XWR(b, XS_IMR, XS_I_RDC);
}

int
xs_selftest_ack(b)
xs_board_t *b;
{
    xs_page0(b);
    if (!(XRD(b, XS_ISR) & XS_I_RDC))
	return 0;
    XWR(b, XS_IMR, 0);
    XWR(b, XS_ISR, XS_I_RDC);
    return 1;
}
