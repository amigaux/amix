#ifndef _XSURF_H
#define _XSURF_H
/*
 * xsurf.h -- the driver's own definitions: the per-board state, the
 * back-end operations a card provides, and the core's entry points.
 *
 * Three parts:
 *   xsurf.c      STREAMS/DLPI, the module's load/unload/halt, interrupts,
 *                the tick (polling and the watchdog)
 *   xs_core.c    the DP8390 core both cards share: chip set-up, the receive
 *                ring, transmit, overrun and error recovery
 *   xs_boards.c  one back end per card: register and data-port access,
 *                the interrupt-status bit, probing and mapping the board
 */

#include "xs8390.h"
#include "xsurfuser.h"

#define XS_MAXBOARDS	2	/* one X-Surf-100 and one X-Surf at most */
#define XS_MAXDEV	5	/* streams per board */

/* ethernet framing */
#define XS_ETHERADDRL	6
#define XS_ETHERHDR	14
#define XS_ETHERMTU	1500
#define XS_ETHERMIN	60	/* shortest frame without CRC */
#define XS_ETHERMAX	1518	/* the longest the ring accepts, as Linux */
#define XS_ETHERTYPE_IP	0x0800
#define XS_ETHERTYPE_ARP 0x0806

#define XS_HIWAT	(1024 * 5)
#define XS_LOWAT	(2 * XS_HIWAT / 3)

/* the chip's limits in time, as clock ticks or microseconds */
#define XS_TX_TIMEOUT	(HZ / 5)	/* a transmit that takes longer: restart */
#define XS_STUCK_TICKS	3		/* ticks of unserviced interrupts: poll */
#define XS_RESET_US	20000		/* the longest the chip may take to reset */
#define XS_RDC_US	20000		/* the longest a remote-DMA write may take */
#define XS_OVW_US	2000		/* after a stop on overrun: at least 1.6 ms */
#define XS_SELFTEST_US	20000		/* the interrupt self-test's wait */

#define XS_ISR_LOOPS	8		/* passes over ISR per service call */
#define XS_RX_FRAMES	64		/* frames per drain: more than the ring holds */

/* how a board window was mapped (xs_boards.c) */
#define XS_MAP_NONE	0
#define XS_MAP_IDENT	1	/* below VSECT1 on k30: the identity */
#define XS_MAP_SPT	2	/* above VSECT1 on k30: sptalloc */
#define XS_MAP_KV	3	/* k46: dev_kvmap, non-cacheable serialised */

typedef struct xs_board xs_board_t;

/*
 * A card's operations.  rd/wr take a DP8390 register number (xs8390.h) in
 * the page the core selected; bin/bout move bytes through the data port
 * after the core set up a remote DMA; irq says whether the card's own
 * network interrupt bit is set; phy powers the PHY (0 when the card has no
 * such control).  None of them sleeps or allocates.
 */
struct xs_ops
{
    char	*name;		/* "X-Surf-100", "X-Surf" */
    int		kind;		/* XSURF_KIND_* */
    int		rcr;		/* RCR bits the card adds to accept-broadcast */
    int		(*rd)();	/* (b, reg) */
    void	(*wr)();	/* (b, reg, val) */
    void	(*bin)();	/* (b, buf, len): any length */
    void	(*bout)();	/* (b, buf, len): even length */
    int		(*irq)();	/* (b) */
    void	(*phy)();	/* (b, on), or 0 */
};

/* one open stream */
typedef struct
{
    queue_t		*q;		/* read queue; 0 = slot free */
    int			state;		/* DL_UNBOUND or DL_IDLE */
    int			board;
    unsigned short	sap;		/* the bound ethertype */
} xs_stream_t;

struct xs_board
{
    struct xs_ops	*ops;
    int			unit;		/* xsfN */
    unsigned long	phys;		/* the board's physical base */
    volatile unsigned char *va;	/* the mapped base */
    int			map_how;	/* XS_MAP_* */
    unsigned long	map_bytes;
    int			present;	/* found, mapped and set up */
    int			running;	/* the chip is started */
    unsigned char	mac[XS_ETHERADDRL];

    /* receive */
    int			next;		/* the ring page read next */

    /* transmit: two slots; len 0 = free */
    int			tx_len[2];
    int			tx_cur;		/* the slot on the wire, -1 = none */
    long		tx_since;	/* lbolt when it started */
    int			tx_hold;	/* stage, do not start (overrun recovery) */
    int			need_reset;	/* the tick restarts the chip */

    /* interrupts */
    int			intr;		/* XSURF_MODE_* */
    int			attached;	/* on the level-2 chain */
    int			stuck;		/* ticks with unserviced interrupts */
    unsigned int	last_claims;	/* irq_claims at the previous tick */
    int			ifs_on;		/* on the interface list */
    volatile int	selftest;	/* the self-test is waiting */
    volatile int	selftest_seen;

    xs_stream_t		s[XS_MAXDEV];
    xsurf_status_t	st;
    struct ifstats	ifs;
};

extern xs_board_t	xs_board[];
extern int		xs_nboards;

/* xs_core.c */
extern void	xs_udelay();		/* (us) */
extern int	xs_chip_reset();	/* (b) -> 1 = the chip answered */
extern int	xs_read_prom();		/* (b, mac) -> 1 = a usable address */
extern void	xs_chip_init();		/* (b, start) */
extern void	xs_chip_stop();		/* (b) */
extern void	xs_chip_mask();		/* (b, on) */
extern int	xs_pending();		/* (b) -> events the interrupt handles wait */
extern void	xs_selftest_kick();	/* (b) */
extern int	xs_selftest_ack();	/* (b) -> 1 = the self-test's RDC */
extern void	xs_service();		/* (b) */
extern void	xs_watch();		/* (b): the tick's watchdog */
extern int	xs_tx_free();		/* (b) -> a free slot, or -1 */
extern int	xs_tx_send();		/* (b, buf, len) -> 1 sent or queued, 0 no slot */
extern void	xs_rdma_read();		/* (b, buf, offset, len) */
extern int	xs_rdma_write();	/* (b, buf, page, len) */
extern void	xs_page0();		/* (b) */

/* xsurf.c: what the core calls back */
extern void	xs_deliver();		/* (b, frame, len) */
extern void	xs_tx_restart();	/* (b): a transmit slot came free */

/* xs_boards.c */
extern int	xs_find_boards();	/* () -> number found and set up */
extern void	xs_unmap();		/* (b) */

#endif /* _XSURF_H */
