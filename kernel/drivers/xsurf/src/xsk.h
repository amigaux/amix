#ifndef _XSK_H
#define _XSK_H
/*
 * xsk.h -- the kernel interfaces the driver uses, in one place.  The module
 * build takes them from the ABI kit; the host tests (module/host/) build
 * the same sources against their own model of these interfaces, selected
 * with -DXS_HOSTTEST.
 */
#ifdef XS_HOSTTEST
#include "hostk.h"
#else
#include "sys/types.h"
#include "sys/param.h"
#include "sys/signal.h"
#include "sys/errno.h"
#include "sys/psw.h"
#include "sys/pcb.h"
#include "sys/user.h"
#include "sys/sysmacros.h"
#include "sys/immu.h"
#include "sys/stream.h"
#include "sys/stropts.h"
#include "sys/systm.h"
#include "sys/cred.h"
#include "sys/dlpi.h"
#include "sys/ddi.h"
#include "sys/cmn_err.h"
#include "sys/socket.h"
#include "sys/sockio.h"
#include "net/if.h"
#include "sys/inline.h"
#include "sys/conf.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

/* lbolt, panicstr, timeout and untimeout come from sys/systm.h */
extern int	autocon(), bprobe();
extern caddr_t	sptalloc();
extern void	sptfree();
#ifdef XS_K46
extern char	*dev_kvmap();
extern void	dev_kvunmap();
#endif

/* IPL 4: every chip access and the driver's shared state (see xsurf.c) */
#define splxs()		spl6()
#endif /* XS_HOSTTEST */
#endif /* _XSK_H */
