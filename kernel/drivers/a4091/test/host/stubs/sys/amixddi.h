#ifndef _HOSTTEST_SYS_AMIXDDI_H
#define _HOSTTEST_SYS_AMIXDDI_H
/* The DDI names the module calls, as the kit's amixddi.h declares them (K&R);
 * mock.c implements them. */
extern int		sd_register();
extern int		root_defer();
#ifndef DMA_TO_DEVICE
#define	DMA_TO_DEVICE	0
#define	DMA_FROM_DEVICE	1
#endif
extern int		dma_prepare();
extern void		dma_complete();
extern unsigned long	dma_addr();
extern char		*dma_alloc();
extern void		dma_free();
#endif
