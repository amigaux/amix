/* SPDX-License-Identifier: MIT */
/*
 * mock.c -- the kernel names the a4091 module calls, as host code.  The board
 * windows are host buffers; dma_alloc's physical address is a value the host
 * never maps, so a driver that handed its own kernel address to the chip, or
 * dereferenced the physical one, fails a check or faults here.
 */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "mock.h"

struct mock_board	mock_board[MOCK_NBOARD];
int			mock_nboard;
struct mock_reg		mock_reg[MOCK_NREG];
int			mock_nreg;
int			mock_reg_fail_at = -1;
int			mock_reg_errno;
struct mock_log		mock_log[MOCK_NLOG];
int			mock_nlog;
int			mock_dma_alloc_fail;
unsigned long		mock_addr_offset;
int			mock_addr_zero;
void			*mock_dma_va;
size_t			mock_dma_len;
int			mock_dma_allocs, mock_dma_frees;
int			mock_autocon_calls;

void
mock_reset(void)
{
	memset(mock_board, 0, sizeof mock_board);
	mock_nboard = 0;
	memset(mock_reg, 0, sizeof mock_reg);
	mock_nreg = 0;
	mock_reg_fail_at = -1;
	mock_reg_errno = 0;
	memset(mock_log, 0, sizeof mock_log);
	mock_nlog = 0;
	mock_dma_alloc_fail = 0;
	mock_addr_offset = 0;
	mock_addr_zero = 0;
	mock_dma_allocs = mock_dma_frees = 0;
	mock_autocon_calls = 0;
}

int
mock_add(long prod, unsigned long base)
{
	struct mock_board *b = &mock_board[mock_nboard];

	b->prod = prod;
	b->base = base;
	mock_chip_done(b);
	return mock_nboard++;
}

/* the read side of a chip that has finished a command: ISTAT DIP, DSTAT SIR,
 * DSPS 0xff00 (the SCRIPTS' INT ok) */
void
mock_chip_done(struct mock_board *b)
{
	unsigned long dsps = 0xff00;

	b->regs[0x22] = 0x01;
	b->regs[0x0f] = 0x04;
	memcpy(&b->regs[0x30], &dsps, sizeof dsps);
}

unsigned long
mock_wr32(struct mock_board *b, int reg)
{
	unsigned long v;

	memcpy(&v, &b->regs[reg + MOCK_WRSHADOW], sizeof v);
	return v;
}

unsigned char
mock_wr8(struct mock_board *b, int reg)
{
	return b->regs[reg + MOCK_WRSHADOW];
}

static struct mock_board *
page(unsigned long phys, unsigned char **p)
{
	int i;

	for (i = 0; i < mock_nboard; i++) {
		if (phys == mock_board[i].base) {
			*p = mock_board[i].acfg;
			return &mock_board[i];
		}
		if (phys == mock_board[i].base + MOCK_SIOP_OFF) {
			*p = mock_board[i].regs;
			return &mock_board[i];
		}
	}
	return NULL;
}

/* autocon(prod, index, &base, &size): the index-th board of that product */
int
autocon(long prod, int n, long *base, long *size)
{
	int i, seen = 0;

	mock_autocon_calls++;
	for (i = 0; i < mock_nboard; i++)
		if (mock_board[i].prod == prod && seen++ == n) {
			*base = (long)mock_board[i].base;
			*size = 0x01000000;
			return 1;
		}
	return 0;
}

/* k30: sptalloc(npages, mode, pfn, flag), pfn the physical address here */
char *
sptalloc(int npages, int mode, unsigned long pfn, int flag)
{
	unsigned char *p;
	struct mock_board *b = page(pfn, &p);

	(void)npages; (void)mode; (void)flag;
	return (b && !b->dead) ? (char *)p : NULL;
}

/* k46: dev_kvmap(phys, nbytes, cm, flags) / dev_kvunmap(kva, nbytes) */
char *
dev_kvmap(long phys, unsigned long nbytes, int cm, int flags)
{
	unsigned char *p;

	(void)nbytes; (void)cm; (void)flags;
	return page((unsigned long)phys, &p) ? (char *)p : NULL;
}

void
dev_kvunmap(char *kva, unsigned long nbytes)
{
	(void)kva; (void)nbytes;
}

/* k46: one byte through u_nofault; a dead board's window faults */
int
bprobe(char *addr, int v)
{
	int i;

	(void)v;
	for (i = 0; i < mock_nboard; i++)
		if ((unsigned char *)addr >= mock_board[i].regs
		    && (unsigned char *)addr < mock_board[i].regs + MOCK_PAGE)
			return mock_board[i].dead;
	return 1;
}

int _spl7(void) { return 7; }
int splx(int s) { return s; }

int
sd_register(int (*fn)(), unsigned c, char *base, char *name, unsigned rank)
{
	int i = mock_nreg;

	if (i == mock_reg_fail_at)
		return mock_reg_errno;
	mock_reg[i].fn = fn;
	mock_reg[i].c = c;
	mock_reg[i].base = (unsigned long)base;
	mock_reg[i].name = name;
	mock_reg[i].rank = rank;
	mock_nreg++;
	return 0;
}

char *
dma_alloc(unsigned long len, unsigned long *pa)
{
	mock_dma_allocs++;
	if (mock_dma_alloc_fail)
		return NULL;
	free(mock_dma_va);
	mock_dma_va = aligned_alloc(16, (len + 15) & ~15UL);
	memset(mock_dma_va, 0x5a, len);
	mock_dma_len = len;
	*pa = MOCK_DMA_PA;
	return mock_dma_va;
}

void
dma_free(char *va, unsigned long len)
{
	if (va == mock_dma_va && len == mock_dma_len)
		mock_dma_frees++;
}

static void
logop(enum mock_op op, unsigned long pa, unsigned long len, int dir, unsigned long ret)
{
	if (mock_nlog < MOCK_NLOG) {
		mock_log[mock_nlog].op = op;
		mock_log[mock_nlog].pa = pa;
		mock_log[mock_nlog].len = len;
		mock_log[mock_nlog].dir = dir;
		mock_log[mock_nlog].ret = ret;
	}
	mock_nlog++;
}

int
dma_prepare(void *r, unsigned long pa, unsigned long len, int dir)
{
	(void)r;
	logop(OP_PREPARE, pa, len, dir, 0);
	return 0;
}

void
dma_complete(void *r, unsigned long pa, unsigned long len, int dir)
{
	(void)r;
	logop(OP_COMPLETE, pa, len, dir, 0);
}

unsigned long
dma_addr(void *r, unsigned long pa)
{
	unsigned long a = mock_addr_zero ? 0 : pa + mock_addr_offset;

	(void)r;
	logop(OP_ADDR, pa, 0, 0, a);
	return a;
}

void
mock_bcopy(const void *from, void *to, size_t n)
{
	memmove(to, from, n);
}

int mock_verbose;

int
mock_printf(const char *fmt, ...)
{
	va_list ap;
	int n = 0;

	if (mock_verbose) {
		va_start(ap, fmt);
		n = vfprintf(stderr, fmt, ap);
		va_end(ap);
	}
	return n;
}
