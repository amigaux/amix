/* SPDX-License-Identifier: MIT */
/*
 * mock.h -- the host harness's view of the kernel the a4091 module calls:
 * AutoConfig boards (autocon), their two pages (sptalloc on k30, dev_kvmap +
 * bprobe on k46), sd_register, and the C4-5 DMA names.  Plain host code.
 */
#ifndef MOCK_H
#define MOCK_H

#include <stddef.h>

#define MOCK_SIOP_OFF	0x00800000UL	/* the 53C710 block in the board window */
#define MOCK_WRSHADOW	0x40		/* writes land at reg + 0x40 */
#define MOCK_PAGE	0x1000
#define MOCK_NBOARD	6
#define MOCK_NREG	8
#define MOCK_NLOG	32
#define MOCK_DMA_PA	0x00f00000UL	/* dma_alloc's physical address: never mapped */

struct mock_board {
	long		prod;		/* (manufacturer << 16) | product */
	unsigned long	base;		/* the physical base autocon reports */
	int		dead;		/* k46: bprobe faults; k30: sptalloc fails */
	unsigned char	acfg[MOCK_PAGE];
	unsigned char	regs[MOCK_PAGE];	/* reads at +0, writes at +0x40 */
};

struct mock_reg {			/* one sd_register call */
	int		(*fn)();
	unsigned	c;
	unsigned long	base;
	char		*name;
	unsigned	rank;
};

enum mock_op { OP_PREPARE = 1, OP_ADDR, OP_COMPLETE };
struct mock_log {			/* one DMA call */
	enum mock_op	op;
	unsigned long	pa, len;
	int		dir;
	unsigned long	ret;		/* dma_addr's answer */
};

extern struct mock_board	mock_board[MOCK_NBOARD];
extern int			mock_nboard;
extern struct mock_reg		mock_reg[MOCK_NREG];
extern int			mock_nreg;
extern int			mock_reg_fail_at;	/* -1, or the call that fails */
extern int			mock_reg_errno;
extern struct mock_log		mock_log[MOCK_NLOG];
extern int			mock_nlog;
extern int			mock_dma_alloc_fail;
extern unsigned long		mock_addr_offset;	/* dma_addr = pa + this */
extern int			mock_addr_zero;		/* dma_addr = 0: out of reach */
extern int			mock_forcebounce;	/* the k30 hook: a FROM complete
							 * copies a stale bounce (0x5a) back */
extern unsigned char		*mock_status_va;	/* the chip's status byte ... */
extern unsigned char		mock_status_val;	/* ... written before the first
							 * complete after a launch */
extern int			mock_status_done;
extern void			*mock_dma_va;
extern size_t			mock_dma_len;
extern int			mock_dma_allocs, mock_dma_frees;
extern int			mock_autocon_calls;

void	mock_reset(void);
int	mock_add(long prod, unsigned long base);
void	mock_chip_done(struct mock_board *b);	/* reads: DIP, SIR, DSPS 0xff00 */
unsigned long	mock_wr32(struct mock_board *b, int reg);	/* last write */
unsigned char	mock_wr8(struct mock_board *b, int reg);

#endif
