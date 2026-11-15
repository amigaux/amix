#ifndef _XSURFUSER_H
#define _XSURFUSER_H
/*
 * xsurfuser.h -- what a user program may use: the ioctls of /dev/xsfN and
 * /dev/xsfctl, and the status record.  No kernel types.
 *
 * /dev/xsfN (c 56 N) is board N's interface.  /dev/xsfctl (c 56 15) is
 * status only: it opens whenever the module is loaded, also when every
 * board it found was refused at load, and answers XSURF_FOUND_STATUS(i)
 * for each board AutoConfig gave it, in the order it probed them.
 */

#define XSURFIOC		('X' << 8)
#define XSURF_GET_STATUS	(XSURFIOC | 2)	/* /dev/xsfN -> xsurf_status_t */
#define XSURF_NUMBER_OF_BOARDS	(XSURFIOC | 5)	/* -> int: boards in use */
/* /dev/xsfctl: the i-th board found (0..XSURF_MAXFOUND-1); EINVAL past the last */
#define XSURF_FOUND_STATUS(i)	(XSURFIOC | 0x10 | (i))
#define XSURF_MAXFOUND		4

#define XSURF_CTL_MINOR		15	/* /dev/xsfctl */

#define XSURF_STATUS_VERSION	2

/* board_kind */
#define XSURF_KIND_XSURF	1	/* X-Surf, 0x1212:0x17 */
#define XSURF_KIND_XSURF100	100	/* X-Surf-100, 0x1212:0x64 */

/* intr_mode */
#define XSURF_MODE_POLLED	0
#define XSURF_MODE_INTR		2	/* the level-2 interrupt */

/* link */
#define XSURF_LINK_DOWN		0
#define XSURF_LINK_UP		1
#define XSURF_LINK_UNKNOWN	2	/* the card cannot say (link_medium says why) */

/* link_duplex */
#define XSURF_DUPLEX_HALF	0
#define XSURF_DUPLEX_FULL	1
#define XSURF_DUPLEX_UNKNOWN	2

/*
 * link_medium: what the chip sends on.  X-Surf-100: always TP.  X-Surf
 * (RTL8019AS): from its CONFIG0 and CONFIG2 registers; in auto-detect it
 * falls back to coax (or AUI) when the 10BASE-T link test fails.
 */
#define XSURF_MEDIUM_UNKNOWN	0
#define XSURF_MEDIUM_TP		1	/* 10BASE-T or 100BASE-TX */
#define XSURF_MEDIUM_TP_NOTEST	2	/* 10BASE-T, link test switched off */
#define XSURF_MEDIUM_COAX	3	/* 10BASE2 */
#define XSURF_MEDIUM_AUI	4	/* 10BASE5, an external transceiver */
#define XSURF_MEDIUM_NOTREADY	5	/* X-Surf-100: the chip says it is not ready */
#define XSURF_MEDIUM_NOTKNOWN	6	/* the chip does not identify as the expected one */

/* refused: why a board found by AutoConfig was not taken at load */
#define XSURF_REFUSED_NONE	0	/* taken: it is xsf<unit> */
#define XSURF_REFUSED_NOANSWER	1	/* a bus error at its registers */
#define XSURF_REFUSED_NORESET	2	/* the chip does not reset */
#define XSURF_REFUSED_NOWRITES	3	/* its registers do not take writes */
#define XSURF_REFUSED_NOMAC	4	/* no usable station address */
#define XSURF_REFUSED_HIGH	5	/* placed at or above 0x80000000 */
#define XSURF_REFUSED_SMALL	6	/* AutoConfig size too small */
#define XSURF_REFUSED_NOMAP	7	/* no kernel address space to map it */

/* notes: transmit failures said once on the console (then only counted) */
#define XSURF_NOTE_TXTIMEOUT	0x01	/* a transmit did not complete; chip restarted */
#define XSURF_NOTE_DMA		0x02	/* a remote-DMA write did not complete */
#define XSURF_NOTE_ABORT	0x04	/* a transmit aborted: excessive collisions */
#define XSURF_NOTE_TXERR	0x08	/* another transmit error */

typedef struct
{
    unsigned int	version;	/* XSURF_STATUS_VERSION */
    unsigned int	size;		/* sizeof(xsurf_status_t) */
    unsigned int	board_kind;
    unsigned int	zorro;		/* 2 or 3 */
    unsigned int	board_phys;	/* the board's physical base */
    unsigned int	intr_mode;
    unsigned int	link;		/* XSURF_LINK_*; version 1 said UNKNOWN */
    unsigned int	running;	/* the chip is started */
    unsigned int	pnp;		/* X-Surf: set up through plug-and-play */

    /* receive */
    unsigned int	rx_frames;	/* frames taken from the ring */
    unsigned int	rx_delivered;	/* indications sent upstream */
    unsigned int	rx_no_sap;	/* no stream bound to the frame's type */
    unsigned int	rx_not_for_us;
    unsigned int	rx_couldnt_put;	/* a bound stream was full */
    unsigned int	rx_nomem;	/* allocb failed */
    unsigned int	rx_errors;	/* RXE */
    unsigned int	rx_bad_size;	/* length outside 60..1518 */
    unsigned int	rx_resyncs;	/* a corrupt ring header: ring dropped */
    unsigned int	rx_overruns;	/* OVW recoveries */
    unsigned int	rx_frame_errors; /* CNTR0 */
    unsigned int	rx_crc_errors;	/* CNTR1 */
    unsigned int	rx_missed;	/* CNTR2 */

    /* transmit */
    unsigned int	tx_frames;	/* frames completed */
    unsigned int	tx_errors;	/* TXE */
    unsigned int	tx_aborts;	/* aborted (excessive collisions, underrun) */
    unsigned int	tx_collisions;
    unsigned int	tx_timeouts;	/* the watchdog restarted the chip */
    unsigned int	tx_dma_timeouts; /* a remote-DMA write never completed */
    unsigned int	tx_bad_req;	/* a malformed DL_UNITDATA_REQ, dropped */
    unsigned int	tx_unbound;	/* DL_UNITDATA_REQ on an unbound stream */
    unsigned int	tx_resends;	/* frames resent after an overrun */

    /* the driver */
    unsigned int	irq_claims;	/* level-2 interrupts taken */
    unsigned int	irq_fallbacks;	/* interrupts stopped: polling since */
    unsigned int	resets;		/* chip restarts of any cause */
    unsigned int	ack_retries;	/* a DLPI ack waited for memory */

    unsigned int	if_ipackets;
    unsigned int	if_opackets;
    unsigned int	if_ierrors;
    unsigned int	if_oerrors;

    /* version 2 */
    unsigned int	unit;		/* xsf<unit>; 0xffffffff when refused */
    unsigned int	refused;	/* XSURF_REFUSED_* */
    unsigned int	refused_detail;	/* NOWRITES: the byte read back for 0x55 */
    unsigned int	intr_param;	/* the module parameter intr (0 or 2) */
    unsigned int	selftest_failed; /* intr=2 and the interrupt self-test failed */
    unsigned char	mac[8];		/* the station address, 6 bytes used */
    unsigned int	link_speed;	/* 10 or 100; 0 = unknown */
    unsigned int	link_duplex;	/* XSURF_DUPLEX_* */
    unsigned int	link_medium;	/* XSURF_MEDIUM_* */
    unsigned int	link_raw;	/* -100: DSR; X-Surf: CONFIG0 << 8 | CONFIG2 */
    unsigned int	link_changes;	/* changes said on the console */
    unsigned int	notes;		/* XSURF_NOTE_* said on the console */
    unsigned int	if_collisions;	/* the interface's count (netstat Collis) */
} xsurf_status_t;

#endif /* _XSURFUSER_H */
