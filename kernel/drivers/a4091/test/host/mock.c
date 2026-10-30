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
int			mock_forcebounce;
unsigned char		*mock_status_va;
unsigned char		mock_status_val;
int			mock_status_done;
void			*mock_dma_va;
size_t			mock_dma_len;
int			mock_dma_allocs, mock_dma_frees;
int			mock_autocon_calls;
int			mock_dd_touch;
int			mock_sptfrees, mock_unmaps;
unsigned char		*mock_rom;
int			mock_rom_maps;
unsigned short		mock_vposr_val = 0x2300;
static struct mock_board	rom_board;

unsigned short
mock_vposr(void)
{
	return mock_vposr_val;
}

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
	mock_forcebounce = 0;
	mock_status_va = NULL;
	mock_status_done = 0;
	mock_dma_allocs = mock_dma_frees = 0;
	mock_autocon_calls = 0;
	mock_dd_touch = 0;
	mock_sptfrees = mock_unmaps = 0;
	mock_rom = NULL;
	mock_rom_maps = 0;
	mock_vposr_val = 0x2300;
}

int
mock_add(long prod, unsigned long base)
{
	struct mock_board *b = &mock_board[mock_nboard];

	b->prod = prod;
	b->base = base;
	b->siop_off = MOCK_SIOP_OFF;
	b->shadow = MOCK_WRSHADOW;
	b->regs = b->rpage;
	mock_chip_done(b);
	return mock_nboard++;
}

/* the A4000T onboard 53C710 at $DD0000: registers at +0x40 written directly,
 * the DIP bank at +0x3000 (all switches off: host ID 7), an idle chip as the
 * ROM driver leaves it (SIEN 0xAF, DIEN 0x3D enabled; DSTAT DFE; revision 2) */
int
mock_add_a4kt(void)
{
	struct mock_board *b = &mock_board[mock_nboard];

	b->prod = 0;
	b->base = 0xDD0000;
	b->acfg_off = 0x3000;
	b->siop_off = 0x40;
	b->shadow = 0;
	b->regs = b->rpage + 0x40;
	memset(b->acfg, 0xff, sizeof b->acfg);
	b->regs[0x00] = 0xaf;		/* SIEN */
	b->regs[0x3a] = 0x3d;		/* DIEN */
	b->regs[0x0f] = 0x80;		/* DSTAT DFE */
	b->regs[0x21] = 0x20;		/* CTEST8 revision 2 */
	b->regs[0x22] = 0x00;		/* ISTAT idle */
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

/* an absent id: the SELECT timed out (ISTAT SIP, SSTAT0 STO) */
void
mock_chip_seltimeout(struct mock_board *b)
{
	b->regs[0x22] = 0x02;
	b->regs[0x0e] = 0x20;
	b->regs[0x0f] = 0x00;
}

/* an unexpected phase: the SCRIPTS' INT err5 (DSPS 0xff05) */
void
mock_chip_phase(struct mock_board *b)
{
	unsigned long dsps = 0xff05;

	b->regs[0x22] = 0x01;
	b->regs[0x0f] = 0x04;
	memcpy(&b->regs[0x30], &dsps, sizeof dsps);
}

unsigned long
mock_wr32(struct mock_board *b, int reg)
{
	unsigned long v;

	memcpy(&v, &b->regs[reg + b->shadow], sizeof v);
	return v;
}

unsigned char
mock_wr8(struct mock_board *b, int reg)
{
	return b->regs[reg + b->shadow];
}

/* the page answering phys: frame = 1 maps by frame (sptalloc: the page's
 * start), 0 keeps the in-page offset (dev_kvmap) */
static struct mock_board *
page(unsigned long phys, unsigned char **p, int frame)
{
	int i;
	struct mock_board *b;
	unsigned long rp;

	if (phys >= 0xDD0000 && phys < 0xDE0000)
		mock_dd_touch++;
	if (phys == 0xF80000) {
		mock_rom_maps++;
		*p = mock_rom;
		return mock_rom ? &rom_board : NULL;
	}
	for (i = 0; i < mock_nboard; i++) {
		b = &mock_board[i];
		rp = b->base + b->siop_off;
		if (phys == b->base + b->acfg_off) {
			*p = b->acfg;
			return b;
		}
		if (frame ? (phys & ~0x7ffUL) == (rp & ~0x7ffUL) : phys == rp) {
			*p = frame ? b->rpage : b->regs;
			return b;
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
	struct mock_board *b = page(pfn, &p, 1);

	(void)npages; (void)mode; (void)flag;
	return (b && !b->dead) ? (char *)p : NULL;
}

void
sptfree(char *va, int npages, int flag)
{
	(void)va; (void)npages; (void)flag;
	mock_sptfrees++;
}

/* k46: dev_kvmap(phys, nbytes, cm, flags) / dev_kvunmap(kva, nbytes) */
char *
dev_kvmap(long phys, unsigned long nbytes, int cm, int flags)
{
	unsigned char *p;

	(void)nbytes; (void)cm; (void)flags;
	return page((unsigned long)phys, &p, 0) ? (char *)p : NULL;
}

void
dev_kvunmap(char *kva, unsigned long nbytes)
{
	(void)kva; (void)nbytes;
	mock_unmaps++;
}

/* k46: one byte through u_nofault; a dead board's window faults */
int
bprobe(char *addr, int v)
{
	int i;

	(void)v;
	for (i = 0; i < mock_nboard; i++)
		if (mock_board[i].prod == 0 && (unsigned char *)addr >= mock_board[i].rpage
		    && (unsigned char *)addr < mock_board[i].rpage + sizeof mock_board[i].rpage)
			mock_dd_touch++;	/* the onboard chip's window */
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
	unsigned char *p;

	(void)r;
	logop(OP_COMPLETE, pa, len, dir, 0);
	/* the chip finished before the driver completes anything: its status */
	if (mock_status_va && !mock_status_done) {
		*mock_status_va = mock_status_val;
		mock_status_done = 1;
	}
	/* the k30 hook (amix-dlm core/plat/k30/line.c): every segment bounced, a
	 * FROM complete copies the bounce back over [pa, pa + len); a bounce
	 * the chip never wrote holds stale bytes */
	if (mock_forcebounce && dir == 1) {
		if (pa >= MOCK_DMA_PA && pa < MOCK_DMA_PA + mock_dma_len)
			p = (unsigned char *)mock_dma_va + (pa - MOCK_DMA_PA);
		else
			p = (unsigned char *)pa;
		memset(p, 0x5a, len);
	}
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
int mock_trace_lines;

int
mock_printf(const char *fmt, ...)
{
	va_list ap;
	int n = 0;

	if (!strncmp(fmt, "A4091 slow", 10))
		mock_trace_lines++;
	if (mock_verbose) {
		va_start(ap, fmt);
		n = vfprintf(stderr, fmt, ap);
		va_end(ap);
	}
	return n;
}
