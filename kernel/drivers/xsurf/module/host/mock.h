/* mock.h -- the host tests' model chip and kernel controls (mock.c) */
#ifndef _MOCK_H
#define _MOCK_H

#define TX_OK		0
#define TX_ABORT	1	/* TXE with TSR.ABT, no PTX */
#define TX_HANG		2	/* the transmit never completes */
#define WIRE_MAX	256

struct chip {
    unsigned char mem[0x8000];	/* 0..31 PROM, 0x4000..0x7fff packet memory */
    int cr, isr, imr, rcr, tcr, dcr, pstart, pstop, bnry, curr, tpsr, tbcr;
    int rsar, rbcr, tsr, gpoc, dma, started, txing, resets;
    unsigned char par[6], mar[8];
    int cntr[3];
    int ovw, rec_stp, rec_rbcr, rec_loop, ovw_bad_ack;	/* overrun recovery */
    int tx_mode, tx_abort_count, txp_count, loop_sends;
    int wire_n, wire_len[WIRE_MAX];
    unsigned char wire[WIRE_MAX][1600];
    int rdc_never, irq_dead;
    int overread, overwrite, bad_addr, odd_bout, gpoc_in_dma, rx_dropped;
};
extern struct chip chip;

extern int	host_ipl, host_alloc_fail, host_live, host_boards, host_attach_fail;
extern int	host_ifs_count;
extern char	host_console[];
extern void	(*host_upstream_hook)();
extern struct xs_ops host_ops;

void	chip_power_on(), chip_tx_complete();
int	chip_receive(), chip_rd();
void	chip_wr();
void	host_tick();
int	host_tick_armed(), host_interrupt(), host_attached();
#endif
