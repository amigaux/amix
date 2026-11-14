#ifndef _XSURFUSER_H
#define _XSURFUSER_H
/*
 * xsurfuser.h -- what a user program may use: the ioctls of /dev/xsfN and
 * the status record.  No kernel types.
 */

#define XSURFIOC		('X' << 8)
#define XSURF_GET_STATUS	(XSURFIOC | 2)	/* -> xsurf_status_t */
#define XSURF_NUMBER_OF_BOARDS	(XSURFIOC | 5)	/* -> int */

#define XSURF_STATUS_VERSION	1

/* board_kind */
#define XSURF_KIND_XSURF	1	/* X-Surf, 0x1212:0x17 */
#define XSURF_KIND_XSURF100	100	/* X-Surf-100, 0x1212:0x64 */

/* intr_mode */
#define XSURF_MODE_POLLED	0
#define XSURF_MODE_INTR		2	/* the level-2 interrupt */

/* link: the driver does not read the PHY */
#define XSURF_LINK_UNKNOWN	2

/*
 * The status record.  `version' and `size' come first and stay first: a
 * reader checks both before trusting the rest.  Counters only grow.
 */
typedef struct
{
    unsigned int	version;	/* XSURF_STATUS_VERSION */
    unsigned int	size;		/* sizeof(xsurf_status_t) */
    unsigned int	board_kind;
    unsigned int	zorro;		/* 2 or 3 */
    unsigned int	board_phys;	/* the board's physical base */
    unsigned int	intr_mode;
    unsigned int	link;
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
} xsurf_status_t;

#endif /* _XSURFUSER_H */
