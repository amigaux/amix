/*
 * amixddi.h -- DDI v1 (k30.1.0, k46.1.0; stage 4 adds minors 1 and 2): the names a module may use from the
 * kernel, and the declarations of those the module core provides.
 *
 * The list of record is the kit's ddi.list; the contract of each name
 * (arguments, context, errors) is docs/abi/ddi.md in amix-dlm
 * (docs/contracts/C3-2-symbols-and-ddi.md section 3 is its index).  The
 * stock names are declared by the stock headers that define them
 * (<sys/kmem.h>, <sys/stream.h>, <sys/systm.h> and the others); this
 * header declares only what the core adds, and fixes one stock
 * declaration that is wrong for these kernels (cputype).  It is not the
 * stock SVR4 <sys/ddi.h> (the DDI/DKI macros), which a module may include
 * as well.
 *
 * Context: "proc" may sleep; "any" includes interrupt level.  Level 6 is
 * never masked by an spl in these kernels: spl5, spl6 and spl7 raise to
 * level 4, as <sys/inline.h> does (FAST_INTERRUPTS).  A level-6 handler
 * calls no DDI function (docs/contracts/C3-6-driver-to-module.md 1.3).
 *
 * K&R declarations: the kernel is built with gcc 2.7.2.3 -traditional.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */

#ifndef _SYS_AMIXDDI_H
#define _SYS_AMIXDDI_H

/*
 * Board windows below VSECT1 (any): the kernel maps physical addresses
 * there one to one on both lines, so phystokv is the identity.  The k30
 * <sys/immu.h> defines both; the k46 kit's 4 KiB-page form does not, so
 * they are here, in the stock form.
 */
#ifndef VSECT1
#define VSECT1		0x40000000
#endif
#ifndef phystokv
#define phystokv(paddr) (paddr)
#endif

/*
 * Interrupt level as functions (any).  <sys/inline.h> gives the same as
 * inline code and #defines the names; a module may use either form.
 */
#ifndef spl5
extern int	spl0(), spl1(), spl2(), spl3(), spl4();
extern int	spl5(), spl6(), spl7();	/* level 4, not 5-7 */
extern int	splx();			/* (int s) */
#endif

/*
 * Interrupt chains (proc).  intr_attach(level, fn, arg, name): level 2 or
 * 6; fn(arg) is called every time its level fires and returns nonzero
 * only when its own board raised it.  0, EINVAL, EEXIST, ECONFIG (8 per
 * chain), ENXIO (level 2 before the core armed it).
 * intr_detach(level, fn, arg): 0, EINVAL, ENOENT.
 */
extern int	intr_attach();		/* (int, int (*)(), char *, char *) */
extern int	intr_detach();		/* (int, int (*)(), char *) */

/*
 * A disk controller (root, k30.1.1 / k46.1.1; contract C4-1).
 * sd_register(queuefn, c, base, name, rank) from the module's _load:
 * queuefn(c, cp) gets sd's requests for the board, rank is the class the
 * module's .moddata declares (1 z3660, 2 zorro, 3 mobo, 4 ide).  0,
 * EINVAL, ENOSPC (four), EBUSY (after sd's first open).
 */
extern int	sd_register();		/* (int (*)(), unsigned, char *, char *, unsigned) */

/*
 * The deferred call (root, k30.1.2 / k46.1.1; contract C4-2 section 3).
 * root_defer(fn, arg) from a root-class module's _load: fn(arg) runs once
 * at the first sysinit entry, at level 0, where the driver attaches its
 * interrupt and runs its self-test.  0, EINVAL (not in a root-class
 * _load), ENOSPC (8 already).
 */
extern int	root_defer();		/* (int (*)(), char *) */

/*
 * The RAM-disk image (any, k30.1.2 / k46.1.2; contract C4-3 section 4).
 * ramdisk_image(&paddr, &size): the physical address and size of the
 * image boot2 placed.  0, or ENOENT when there is none.
 */
extern int	ramdisk_image();	/* (unsigned long *, unsigned long *) */

/*
 * A filesystem (k30.1.2 / k46.1.2; contract C4-6 section 3).
 * vfs_register(name, init, ops, flag) from the module's _load, with name
 * its .moddata fs=: a vfssw row, init(row, index) run once now.  0,
 * EINVAL, EEXIST (that type is there), ENOSPC (4 spare rows).  A
 * filesystem module is pinned.
 */
extern int	vfs_register();		/* (char *, int (*)(), struct vfsops *, long) */

/*
 * DMA by a bus-master board (k30.1.2 / k46.1.2; contract C4-5).  The
 * record is the driver's, struct dma_rec of layout version 2 (0x60 bytes,
 * the 040/060 port's DMA040-SERVICE-RECORD.md).  Per transfer:
 * dma_prepare(r, pa, len, dir) after the driver built what the device
 * reads, then arm the device with dma_addr(r, pa) where it takes the data
 * address, then dma_complete(r, pa, len, dir) when it has stopped.  A
 * nonzero prepare is a miss the driver arms past.  dma_alloc(len, &pa):
 * len bytes (at most 64 KiB, 16-aligned) the board reaches, for SCRIPTS
 * and tables, 0 when none; never sleeps.  On k30 the provider is a
 * placeholder until S4-62: dma_alloc returns 0.
 */
#ifndef DMA_TO_DEVICE
#define	DMA_TO_DEVICE	0
#define	DMA_FROM_DEVICE	1
#endif
extern int		dma_prepare();	/* (struct dma_rec *, ulong pa, ulong len, int dir) */
extern void		dma_complete();	/* (struct dma_rec *, ulong pa, ulong len, int dir) */
extern unsigned long	dma_addr();	/* (struct dma_rec *, ulong pa) */
extern char		*dma_alloc();	/* (ulong len, ulong *pa) */
extern void		dma_free();	/* (char *va, ulong len) */

/*
 * Network attachment (proc): a driver's struct ifstats (<net/if.h>) on or
 * off the stock list netstat reads.  0, EEXIST / ENOENT.
 */
extern int	if_attach();		/* (struct ifstats *) */
extern int	if_detach();		/* (struct ifstats *) */

/*
 * The console hook (proc).  fn(cp, p, n) sees every console write before
 * the native screen code, in the writer's context (perhaps an
 * interrupt's; it must not sleep); nonzero = taken.  cp is the console,
 * a struct console * ("amiga/console/console.h" in the kit's stock/usr/sys),
 * and the hook takes only writes to the screen it shows:
 * cp->screen == displayedscreen, the kernel's `struct screen *` (DDI data,
 * read-only), which no stock header declares: declare it beside the hook.
 * One hook at a time: cons_hook_set gives EBUSY for a second.
 */
extern int	cons_hook_set();	/* (int (*)(struct console *, char *, int)) */
extern void	cons_hook_clear();

/*
 * The module interface (proc): mod_miscops and the other linkage ops are
 * declared by <sys/moddefs.h> and used through its wrapper macros.
 * mod_hold(wrapper) / mod_rele(wrapper) keep a module loaded across a
 * window where nothing else holds it.
 */

/*
 * cputype (data, read-only): 30 on k30; 40 or 60 on k46.  It is a long in
 * these kernels (the port's cputype060.s; amix-dlm core/plat/k30), while
 * <sys/systm.h> still declares the stock `short`, so read it with
 * DDI_CPUTYPE, which is right with or without <sys/systm.h>.
 */
#ifndef _SYS_SYSTM_H
extern long	cputype;
#endif
#define	DDI_CPUTYPE	(*(long *)&cputype)

/*
 * 64-bit helpers on k46 come from the core (libgcc's), on k30 from the
 * kernel: __udivdi3, __umoddi3, __lshrdi3.  The compiler calls them; a
 * module never names them.
 */

#endif	/* _SYS_AMIXDDI_H */
