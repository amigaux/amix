/*
 * amixddi.h -- DDI v1 (k30.1.0, k46.1.0): the names a module may use from the
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
