#ifndef _XS8390_H
#define _XS8390_H
/*
 * xs8390.h -- the DP8390 register model shared by the X-Surf (Realtek) and
 * the X-Surf-100 (ASIX AX88796B).  Register numbers are the chip's; each
 * board's back end turns a number into an address (xs_boards.c).
 */

/* page 0 (R = read, W = write where the two differ) */
#define XS_CR		0x00	/* command, every page */
#define XS_PSTART	0x01	/* W: first ring page */
#define XS_PSTOP	0x02	/* W: ring end page + 1 */
#define XS_BNRY		0x03	/* boundary: one page behind the next frame */
#define XS_TPSR		0x04	/* W: transmit page */
#define XS_TSR		0x04	/* R: transmit status */
#define XS_TBCR0	0x05	/* W: transmit byte count */
#define XS_TBCR1	0x06
#define XS_ISR		0x07	/* interrupt status, write 1 to clear */
#define XS_RSAR0	0x08	/* W: remote start address */
#define XS_RSAR1	0x09
#define XS_RBCR0	0x0a	/* W: remote byte count */
#define XS_RBCR1	0x0b
#define XS_RCR		0x0c	/* W: receive configuration */
#define XS_TCR		0x0d	/* W: transmit configuration */
#define XS_CNTR0	0x0d	/* R: frame alignment errors */
#define XS_DCR		0x0e	/* W: data configuration */
#define XS_CNTR1	0x0e	/* R: CRC errors */
#define XS_IMR		0x0f	/* W: interrupt mask */
#define XS_CNTR2	0x0f	/* R: missed frames */
/* page 1 */
#define XS_PAR0		0x01	/* station address, 6 registers */
#define XS_CURR		0x07	/* the page the chip writes next */
#define XS_MAR0		0x08	/* multicast filter, 8 registers */
/* past the register file */
#define XS_DATA		0x10	/* remote-DMA data port */
#define XS_DSR		0x17	/* AX88796B only, read: device status (link) */
#define XS_RESET	0x1f	/* read, then write the value back: reset */

/* CR */
#define XS_CR_STP	0x01
#define XS_CR_STA	0x02
#define XS_CR_TXP	0x04
#define XS_CR_RREAD	0x08
#define XS_CR_RWRITE	0x10
#define XS_CR_NODMA	0x20
#define XS_CR_PAGE1	0x40
#define XS_CR_PAGE3	0xc0	/* RTL8019AS: its configuration registers */

/* ISR and IMR */
#define XS_I_PRX	0x01	/* frame received */
#define XS_I_PTX	0x02	/* frame sent */
#define XS_I_RXE	0x04	/* receive error */
#define XS_I_TXE	0x08	/* transmit error */
#define XS_I_OVW	0x10	/* receive ring overrun */
#define XS_I_CNT	0x20	/* a tally counter is half full */
#define XS_I_RDC	0x40	/* remote DMA complete */
#define XS_I_RST	0x80	/* the chip is stopped (read only) */
#define XS_IMR_RUN	(XS_I_PRX | XS_I_PTX | XS_I_RXE | XS_I_TXE | XS_I_OVW | XS_I_CNT)

/* TSR */
#define XS_TSR_PTX	0x01
#define XS_TSR_COL	0x04
#define XS_TSR_ABT	0x08	/* aborted: excessive collisions */
#define XS_TSR_FU	0x20	/* aborted: FIFO underrun */

/* the receive ring header's status byte */
#define XS_RSR_PRX	0x01

/* TCR, RCR, DCR values */
#define XS_TCR_NORMAL	0x00
#define XS_TCR_LOOP	0x02	/* internal loopback: the chip sends nothing */
#define XS_RCR_AB	0x04	/* accept broadcast */
#define XS_RCR_MON	0x20	/* monitor: receive nothing into the ring */
#define XS_DCR_BYTE	0x48	/* FIFO threshold 8, normal, byte transfers */
#define XS_DCR_WORD	0x49	/* the same with word transfers (WTS) */

/*
 * The AX88796B's Device Status Register (datasheet V1.6 sec. 5.1.68).  A
 * write to 0x17 is its back-pressure jam limit, not a GPOC: the driver
 * never writes it.  The PHY is on from reset (MII register 0 = 0x3100).
 */
#define XS_DSR_LINK	0x01	/* link up */
#define XS_DSR_DUPLEX	0x02	/* full duplex */
#define XS_DSR_SPEED	0x04	/* 100 Mb/s */
#define XS_DSR_RDY	0x10	/* D_RDY: the chip is ready (not reset, asleep, loading) */

/*
 * The RTL8019AS (datasheet LS003.8 sec. 5.1): page 0's ID bytes, and page
 * 3's CONFIG0 (what it sends on) and CONFIG2 (the medium setting).
 */
#define XS_RTL_ID0	0x0a	/* page 0, read: 0x50 'P' */
#define XS_RTL_ID1	0x0b	/* page 0, read: 0x70 'p' */
#define XS_RTL_CONFIG0	0x03	/* page 3 */
#define XS_RTL_CONFIG2	0x05	/* page 3 */
#define XS_RTL_CONFIG3	0x06	/* page 3 */
#define XS_CONFIG0_BNC	0x04	/* sending on coax (auto-detect: link test failed) */
#define XS_CONFIG0_AUI	0x20	/* sending on AUI */
#define XS_CONFIG2_PL(v) (((v) >> 6) & 3) /* 0 auto, 1 10BASE-T no test, 2 10BASE5, 3 10BASE2 */
#define XS_CONFIG3_FUDUP 0x40	/* full duplex */

/* the probe's write check: page 1's MAR2 and MAR3, read back */
#define XS_CHECK_REG	0x0a
#define XS_CHECK_A	0x55
#define XS_CHECK_B	0xaa

/*
 * Packet memory, the same on both cards: 16 KB from page 0x40.  Two transmit
 * slots of 6 pages (1536 bytes) each, then the receive ring.
 */
#define XS_TX_START	0x40
#define XS_TX_SLOT	6
#define XS_RX_START	(XS_TX_START + 2 * XS_TX_SLOT)	/* 0x4c */
#define XS_RX_STOP	0x80
#define XS_RX_PAGES	(XS_RX_STOP - XS_RX_START)
#define XS_PROM_BYTES	32	/* the station-address PROM image, byte-doubled */

#endif /* _XS8390_H */
