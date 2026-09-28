/* SPDX-License-Identifier: MIT */
/*
 * a4091_dma040.h -- the D42 DMA-coherence seam as the A4091 calls it (040/060
 * driver line only; included by a4091-wr.c under -DA4091_KVA).
 *
 * D42 as amended by the collaborator (2026-09-27): ONE protocol and state
 * machine, in the port's src/dma_cache040.s; the per-controller RECORD lives in
 * each controller's own object.  This header is our side of that cut: the record
 * layout the service reads and writes, and the two entry points we call.  The
 * service does not exist yet, so the names below are the PROPOSAL in
 * docs/D42-CALL-SHAPE.md, not an interface anyone has agreed to.  Until it is
 * agreed and linked, a4091-wr.c builds local stubs (no cache maintenance at all)
 * unless -DA4091_D42 is given.
 *
 * Every field is a longword so the service can reach it with movel and a fixed
 * displacement; the offsets are part of the contract and are asserted in the
 * doc.  Ownership per field:
 *   D = the driver writes it (the service only reads it)
 *   S = the service writes it (the driver only reads it, for diagnostics)
 */
#ifndef	A4091_DMA040_H
#define	A4091_DMA040_H

#define	DMA040_MAGIC		0x44343252	/* "D42R": static, proves the address   */
#define	DMA040_VERSION		1		/* this layout                          */

#define	DMA040_TO_DEVICE	0		/* device reads RAM  (SCSI write)       */
#define	DMA040_FROM_DEVICE	1		/* device writes RAM (SCSI read)        */

#define	DMA040_EMPTY		0		/* state values (service-owned)         */
#define	DMA040_PREPARING	1
#define	DMA040_PREPARED		2

struct dma040_rec {
	ulong	magic;		/* 0x00 D  DMA040_MAGIC                                */
	ulong	version;	/* 0x04 D  DMA040_VERSION                              */
	ulong	ctlid;		/* 0x08 D  controller identity: AutoConfig product id   */
	ulong	unit;		/* 0x0c D  controller instance (sd card number)         */
	ulong	off;		/* 0x10 D  nonzero: seam OFF (service counts, no op)    */
	ulong	state;		/* 0x14 S  EMPTY / PREPARING / PREPARED                 */
	ulong	dir;		/* 0x18 S  direction of the owned segment               */
	ulong	pa;		/* 0x1c S  owned segment: physical base                 */
	ulong	len;		/* 0x20 S  owned segment: length in bytes               */
	ulong	seq;		/* 0x24 S  prepares that took ownership                 */
	ulong	prep_to;	/* 0x28 S  prepares, TO_DEVICE                          */
	ulong	prep_from;	/* 0x2c S  prepares, FROM_DEVICE                        */
	ulong	cmpl_to;	/* 0x30 S  completes consumed, TO_DEVICE                */
	ulong	cmpl_from;	/* 0x34 S  completes consumed, FROM_DEVICE              */
	ulong	prep_owned;	/* 0x38 S  prepare while a segment is still owned       */
	ulong	cmpl_noprep;	/* 0x3c S  complete with no PREPARED record             */
	ulong	cmpl_mismatch;	/* 0x40 S  complete (pa,len,dir) != the owned segment   */
	ulong	range_ovf;	/* 0x44 S  pa + len wrapped: refused                    */
	ulong	off_n;		/* 0x48 S  calls seen while off != 0                    */
	ulong	drv_prep;	/* 0x4c D  prepare calls made by the driver             */
	ulong	drv_cmpl;	/* 0x50 D  complete calls made by the driver            */
	ulong	drv_zero;	/* 0x54 D  zero-length transfers: no call made          */
	ulong	drv_quiesce;	/* 0x58 D  completes that followed a forced quiesce     */
};				/* 0x5c bytes */

/*
 * prepare  -- before the driver arms the device (the DSP write that starts
 *             SCRIPTS).  Takes ownership of [pa, pa+len) and pushes the CPU's
 *             dirty lines over it.  Returns 0 when the segment is PREPARED,
 *             nonzero when it is not (off, still owned, bad range); the driver
 *             arms either way -- nothing on this path may panic.
 * complete -- after the device has stopped touching the segment (its
 *             completion interrupt, or a forced quiesce), before the sd
 *             callback.  FROM_DEVICE: invalidate the owned lines; TO_DEVICE: no
 *             cache op.  Consumes the record (state -> EMPTY).
 * pa is PHYSICAL (sdcom.addr is physical by contract on this line); the service
 * works by physical line, so one op covers every virtual alias of the page.
 */
#ifdef	A4091_D42
extern int	dma040_prepare();	/* (struct dma040_rec *, ulong pa, ulong len, int dir) */
extern void	dma040_complete();	/* (struct dma040_rec *, ulong pa, ulong len, int dir) */
#endif

#endif	/* A4091_DMA040_H */
