/* sys/sdseg.h as the kit ships it (amix-dlm docs/contracts/C4-7): struct
 * sdcomx, struct sdlim and DDI_SD_LIMITS; mock.c implements sd_limits.
 * After rico.h and sd.h. */

#ifndef _SYS_SDSEG_H
#define _SYS_SDSEG_H

/* one segment: a physical address, as sdcom.addr, and its length */
struct sdseg {
	unsigned long	ss_pa;
	unsigned long	ss_len;		/* > 0 */
};

/*
 * The extended command.  With SDX_SEG the data is sx_seg[0 .. sx_nseg-1]
 * in that order, sx_com.nbyte their sum and sx_com.addr sx_seg[0].ss_pa;
 * without it, sx_com.addr/nbyte as today.  sx_resid is the number of
 * bytes not transferred (the landed bytes are the first ones), set by the
 * driver before it calls sx_com.intr: 0 or nbyte for a driver that knows
 * only all or nothing.
 */
struct sdcomx {
	struct sdcom	sx_com;		/* the stock command, at offset 0 */
	unsigned short	sx_flags;	/* 40: SDX_SEG */
	unsigned short	sx_nseg;	/* 42: 1 .. sl_maxseg, with SDX_SEG */
	struct sdseg	*sx_seg;	/* 44: the issuer's, until intr returns */
	unsigned int	sx_resid;	/* 48: bytes not transferred */
};					/* 52 */

#define	SDX_SEG		0x0001

/*
 * A controller's limits, given to sd_limits after sd_register: the
 * module's storage for the kernel's life.  sl_queue's result is ignored,
 * as sd ignores queuefn's: a controller that cannot run a command
 * completes it, sx_com.okay 0 and sx_resid nbyte.
 */
struct sdlim {
	unsigned short	sl_ver;		/*  0: SDLIM_VER */
	unsigned short	sl_flags;	/*  2: SDL_SEG, SDL_ALLRAM */
	unsigned long	sl_maxbytes;	/*  4: per command, a multiple of 512 */
	unsigned short	sl_maxseg;	/*  8: 1 without SDL_SEG */
	unsigned short	sl_align;	/* 10: segment start, a power of two, 1..4096 */
	unsigned short	sl_gran;	/* 12: segment length, a power of two, 1..512 */
	unsigned short	sl_pad;		/* 14: 0 */
	unsigned long	sl_reach;	/* 16: the last physical address the engine reaches */
	bool		(*sl_queue)();	/* 20: sl_queue(c, struct sdcomx *), result ignored */
};					/* 24 */

#define	SDLIM_VER	1
#define	SDL_SEG		0x0001		/* takes SDX_SEG commands */
#define	SDL_ALLRAM	0x0002		/* reaches all RAM the CPU does (C4-7 3.2) */

/*
 * sd_limits(queuefn, c, l): root pass, level 7, no sleep, after
 * sd_register(queuefn, c, ...) returned 0 in the same _load.  0, EBUSY
 * (registration closed), ENOENT (no such registration of this module),
 * EINVAL (a field out of range); a refusal leaves today's commands.
 *
 * DDI_SD_LIMITS_DECL; once at file scope, then DDI_SD_LIMITS(queuefn, c,
 * l), with <sys/errno.h>.  The reference is weak, so the module keeps the
 * minor its other names give it and loads on a kernel before the segment
 * minor, where the call gives ENOSYS and the controller gets today's
 * commands.
 */
extern int	sd_limits();		/* (bool (*queuefn)(), uint c, struct sdlim *) */
#define	DDI_SD_LIMITS_DECL \
	asm(".weak sd_limits"); \
	static int (*volatile ddi_sdlim)() = sd_limits
#define	DDI_SD_LIMITS(queuefn, c, l) \
	(ddi_sdlim ? (*ddi_sdlim)((queuefn), (unsigned int)(c), (l)) : ENOSYS)

#endif /* _SYS_SDSEG_H */
