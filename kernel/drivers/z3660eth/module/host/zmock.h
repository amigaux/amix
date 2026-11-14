/* zmock.h -- the z3660eth host tests' firmware model and kernel controls (zmock.c) */
#ifndef _ZMOCK_H
#define _ZMOCK_H

#define ZM_BASE		0x10000000UL	/* the board's base: below VSECT1, the direct map */
#define ZM_WIRE		64

struct zm {
    int present;
    unsigned long machi, maclo, config;
    int rd, wr, strobes;		/* the backlog's cursor and fill */
    unsigned short serial;
    unsigned long tx_rc;		/* the transmit result: 0 sent, 1 no link */
    int wire_n, wire_len[ZM_WIRE];
    unsigned char wire[ZM_WIRE][1600];
};
extern struct zm zm;

extern int	host_ipl, host_alloc_fail, host_live, host_ifs_count;
extern char	host_console[];
void	zm_power_on(), host_tick();
int	zm_receive(), host_tick_armed();
#endif
