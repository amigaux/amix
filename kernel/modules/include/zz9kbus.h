/*
 * zz9kbus.h -- the interface between a ZZ9000-family board driver (the Z3660's
 * z3660rtg; a ZZ9000 driver) and the core-1 service channel zz9ksvc, through the
 * zz9kbus registry module.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see kernel/modules/LICENSE in the amix repository.
 *
 * A board driver that finds the SDK bootstrap block on its board fills a struct
 * zz9kbus_board and calls zz9kbus_register(); zz9kbus gives it a unit (0 or 1).
 * zz9ksvc, a demand-class module loaded at the first open of /dev/zz9ksvcN, takes
 * the board of unit N with zz9kbus_get() and gives it back with zz9kbus_put().
 * zz9kbus_unregister() answers EBUSY while zz9ksvc holds the board, so the board
 * driver keeps it (and refuses its own _unload) until then.  Board drivers and
 * zz9ksvc name zz9kbus in depend=; they never name each other.
 *
 * The board driver gives exactly this much of its board, nothing else: no register
 * pointer and no mapping of the whole board.
 *   zb_bread      a read of a 16-bit register of the SDK bootstrap block, at an even
 *                 offset below zb_bsize from the block's base (0x400 on the Z3660,
 *                 0x100 on the ZZ9000); the board driver refuses any other offset
 *                 with 0xffff
 *   zb_doorbell   the doorbell write
 *   zb_mbox       the mailbox (descriptor and rings, at the address the bootstrap
 *                 block publishes), mapped by the board driver into kernel space:
 *                 its address and length; 0 when the board has no runtime
 *   zb_heapphys   where a range of the firmware's host-visible heap lies in physical
 *                 memory: 0 and *physp when the whole range [armaddr, armaddr + len)
 *                 is inside the host-visible heap window, -1 otherwise; zz9ksvc
 *                 maps buffers into user processes from this answer only
 * None of the functions sleeps.  zb_doorbell may be called from a timeout() callout at the
 * clock's level; zb_bread and zb_heapphys only in process context.
 */
#ifndef _ZZ9KBUS_H
#define _ZZ9KBUS_H

#define ZZ9KBUS_VERSION	1
#define ZZ9KBUS_NUNIT	2		/* boards per machine: /dev/zz9ksvc0 and 1 */

/* board ids: AutoConfig manufacturer << 16 | product */
#define ZZ9KBUS_ID_Z3660	0x144b0001UL	/* the Z3660's RTG/ethernet/SCSI board */
#define ZZ9KBUS_ID_ZZ9000_Z2	0x6d6e0003UL
#define ZZ9KBUS_ID_ZZ9000_Z3	0x6d6e0004UL

struct zz9kbus_board {
	int		zb_version;	/* ZZ9KBUS_VERSION */
	int		zb_unit;	/* set by zz9kbus_register: 0 .. ZZ9KBUS_NUNIT - 1 */
	unsigned long	zb_id;		/* manufacturer << 16 | product */
	unsigned long	zb_boff;	/* the bootstrap block's board offset (0x400, 0x100) */
	int		zb_bsize;	/* bytes of the bootstrap block zb_bread may read */
	char		*zb_ctx;	/* the board driver's own, passed back to its functions */
	unsigned	(*zb_bread)();	/* (ctx, off): the 16-bit register, or 0xffff */
	void		(*zb_doorbell)();	/* (ctx) */
	char		*zb_mbox;	/* the mailbox, in kernel space, or 0 */
	unsigned long	zb_mboxlen;
	int		(*zb_heapphys)();	/* (ctx, armaddr, len, physp): 0 or -1 */
	int		zb_hold;	/* zz9kbus's count of zz9kbus_get without zz9kbus_put */
};

#ifdef _KERNEL
extern int zz9kbus_register();		/* (bp): 0, EINVAL, EBUSY (already in), ENOSPC */
extern int zz9kbus_unregister();	/* (bp): 0, EINVAL (not in), EBUSY (held) */
extern struct zz9kbus_board *zz9kbus_get();	/* (unit): the board, held, or 0 */
extern void zz9kbus_put();		/* (bp) */
#endif

#endif /* _ZZ9KBUS_H */
