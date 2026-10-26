/* SPDX-License-Identifier: MIT */
/*
 * a4091_modtest.c -- host tests of the a4091 root-class module form
 * (src/a4091-wr.c built with -DA4091_MODULE; with -DA4091_KVA as the k46 arm).
 *
 * The real driver source runs against mock.c: AutoConfig boards, their pages,
 * sd_register and the C4-5 DMA names.  What is checked:
 *   - _load: the registrations (board index c, base, name, rank zorro), the
 *     A4092 and A4770 identities, the product order and the four-board cap,
 *     the failure paths (no board, no DMA area, a board that does not map, a
 *     refused registration), the D42 records;
 *   - two boards: which board a request reaches when sd's card order (rank,
 *     then base) differs from the module's registration order;
 *   - the queue path: the DSA table and SCRIPTS handed to the chip by their
 *     physical address in the dma_alloc area, prepare -> dma_addr -> complete
 *     with the one arm site taking dma_addr's answer, the driver's own bounce
 *     for a misaligned read, a zero-length command;
 *   - _halt: every mapped board stopped and re-initialised.
 * Each case runs in its own child process: the driver keeps per-board state
 * in statics, as it does in the kernel.  The chip itself is not emulated: the
 * mock board's read side says "command done" (DIP, SIR, DSPS 0xff00).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include "mock.h"

#define ulong unsigned long
#include "../../src/a4091_dmarec.h"
#undef ulong

/* the driver's struct sdcom (stubs/sd.h), host layout */
struct sdcom {
	volatile struct sdcom	*next;
	char		reading, okay;
	unsigned char	status, cdb[12];
	char		*addr;
	unsigned	nbyte, card, unit;
	void		(*intr)();
};

/* the DSA table as the driver declares it (siop_ds), host layout */
struct ds_mirror {
	unsigned long	scsi_addr;
	struct { unsigned long len; unsigned char *buf; } p[9];
};
#define DS_ID	0
#define DS_CMD	1
#define DS_DATA1 7

/* the driver's globals */
extern int		a4091_load();
extern void		a4091_halt();
extern long		a4091_busreset;
extern int		a4091_nboards;
extern unsigned long	a4091_halted;
extern void		*a4091_da;
extern unsigned long	a4091_dapa;
extern struct dma_rec	a4091_dmarec[];
extern int		mock_verbose;

#define R_DSA		0x10
#define R_DSP		0x2c
#define R_SCID		0x07
#define R_DMODE		0x3b

#define P_A4091	0x02020054L
#define P_A4092	0xc0de0001L
#define P_A4770	0xc0de0002L
#define RANK_ZORRO	2

static int fails, checks;

#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; \
	printf("    FAIL %s (%s:%d)\n", what, __FILE__, __LINE__); } } while (0)

static int intr_calls;
static void cb(struct sdcom *cp) { (void)cp; intr_calls++; }

static void
setup(void)
{
	mock_reset();
	a4091_busreset = 0;	/* the bus reset reads VHPOSR (0xDFF006): metal only */
	intr_calls = 0;
}

/* the area's kernel address for a physical one the chip was given */
static unsigned char *
area_va(unsigned long pa)
{
	if (pa < a4091_dapa || pa >= a4091_dapa + mock_dma_len)
		return NULL;
	return (unsigned char *)a4091_da + (pa - a4091_dapa);
}

static int
run_queue(int c, unsigned card, int reading, char *buf, unsigned n, unsigned char op)
{
	struct sdcom cp;

	memset(&cp, 0, sizeof cp);
	cp.reading = reading;
	cp.cdb[0] = op;
	cp.cdb[4] = (unsigned char)n;
	cp.addr = buf;
	cp.nbyte = n;
	cp.card = card;
	cp.unit = 6;
	cp.intr = (void (*)())cb;
	return mock_reg[c].fn(c, &cp) && cp.okay;
}

/* ---- the cases ---- */

static void
t_one_a4091(void)
{
	int e;
	unsigned long w0;

	setup();
	mock_add(P_A4091, 0x40000000);
	e = a4091_load(NULL);
	CHECK(e == 0, "load returns 0");
	CHECK(mock_nreg == 1 && a4091_nboards == 1, "one registration");
	CHECK(mock_reg[0].c == 0 && mock_reg[0].base == 0x40000000, "c 0, the autocon base");
	CHECK(mock_reg[0].name && !strcmp(mock_reg[0].name, "A4091 SCSI"), "name A4091 SCSI");
	CHECK(mock_reg[0].rank == RANK_ZORRO, "rank zorro (2)");
	CHECK(mock_reg[0].fn != NULL, "queue function given");
	CHECK(mock_dma_allocs == 1 && a4091_da == mock_dma_va && a4091_dapa == MOCK_DMA_PA,
	    "one dma_alloc area, its kernel and physical address kept");
	memcpy(&w0, (char *)a4091_da + 16, sizeof w0);	/* behind the status line */
	CHECK(w0 == 0x47000000UL, "SCRIPTS copied into the area (SELECT ATN first)");
	CHECK(a4091_dmarec[0].magic == DMA_REC_MAGIC && a4091_dmarec[0].version == 2
	    && a4091_dmarec[0].ctlid == 0x02020054UL && a4091_dmarec[0].unit == 0,
	    "D42 record: magic, version 2, ctlid, unit");
}

static void
identity(long prod, const char *name)
{
	setup();
	mock_add(prod, 0x40000000);
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(mock_nreg == 1 && mock_reg[0].name && !strcmp(mock_reg[0].name, name), name);
	CHECK(mock_reg[0].rank == RANK_ZORRO, "rank zorro (2)");
	CHECK(a4091_dmarec[0].ctlid == 0x02020054UL, "record ctlid is the driver family's");
}
static void t_a4092(void) { identity(P_A4092, "A4092 SCSI"); }
static void t_a4770(void) { identity(P_A4770, "A4770 SCSI"); }

/*
 * Two boards, an A4091 above an A4092.  The module registers in product order
 * (A4091 c 0, A4092 c 1); sd sorts by (rank, base), so the A4092 is card 0.
 * A request for card 0 arrives as queuefn(1, cp) and must reach the A4092's
 * chip, never the A4091's: the module's tables are indexed by c, not cp->card.
 */
static void
t_two_board_order(void)
{
	static char buf[512] __attribute__((aligned(16)));
	struct mock_board *a4091, *a4092;
	int sd0;
	unsigned char before[MOCK_PAGE];

	setup();
	a4092 = &mock_board[mock_add(P_A4092, 0x40000000)];
	a4091 = &mock_board[mock_add(P_A4091, 0x50000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(mock_nreg == 2, "two registrations");
	CHECK(mock_reg[0].c == 0 && mock_reg[0].base == 0x50000000
	    && !strcmp(mock_reg[0].name, "A4091 SCSI"), "c 0 = the A4091 (product order)");
	CHECK(mock_reg[1].c == 1 && mock_reg[1].base == 0x40000000
	    && !strcmp(mock_reg[1].name, "A4092 SCSI"), "c 1 = the A4092");
	/* sd's order: same rank, lower base first */
	sd0 = (mock_reg[0].base < mock_reg[1].base) ? 0 : 1;
	CHECK(sd0 == 1, "sd card 0 is the A4092 (c 1)");
	CHECK(a4091_dmarec[0].unit == 0 && a4091_dmarec[1].unit == 1, "one record per board");

	memcpy(before, a4091->regs, sizeof before);
	CHECK(run_queue(sd0, 0, 1, buf, sizeof buf, 0x28), "card 0 request completes");
	CHECK(mock_wr32(a4092, R_DSP) != 0, "the A4092's chip was armed");
	CHECK(!memcmp(before, a4091->regs, sizeof before), "the A4091's chip untouched");
	CHECK(intr_calls == 1, "callback once");
}

static void
t_four_cap(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	mock_add(P_A4091, 0x41000000);
	mock_add(P_A4092, 0x42000000);
	mock_add(P_A4092, 0x43000000);
	mock_add(P_A4770, 0x44000000);
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(mock_nreg == 4 && a4091_nboards == 4, "four boards registered, not five");
	CHECK(mock_reg[3].c == 3 && !strcmp(mock_reg[3].name, "A4092 SCSI"),
	    "the fifth (the A4770) is not registered");
}

static void
t_no_board(void)
{
	setup();
	CHECK(a4091_load(NULL) == 6, "ENXIO with no board");
	CHECK(mock_nreg == 0, "nothing registered");
	CHECK(mock_dma_frees == 1 && a4091_da == NULL, "the area given back");
}

static void
t_no_dma(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	mock_dma_alloc_fail = 1;
	CHECK(a4091_load(NULL) == 12, "ENOMEM without a dma_alloc area (k30 today)");
	CHECK(mock_nreg == 0 && mock_autocon_calls == 0, "no probe, nothing registered");
}

static void
t_dead_board(void)
{
	setup();
	mock_board[mock_add(P_A4091, 0x40000000)].dead = 1;
	mock_add(P_A4092, 0x48000000);
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(mock_nreg == 1 && mock_reg[0].c == 0 && mock_reg[0].base == 0x48000000,
	    "the dead board skipped, the next one is c 0");
}

static void
t_all_dead(void)
{
	setup();
	mock_board[mock_add(P_A4091, 0x40000000)].dead = 1;
	CHECK(a4091_load(NULL) == 6, "ENXIO when no board maps");
	CHECK(mock_nreg == 0 && mock_dma_frees == 1, "nothing registered, the area given back");
}

static void
t_register_refused(void)
{
	struct mock_board *b0;

	setup();
	b0 = &mock_board[mock_add(P_A4091, 0x40000000)];
	mock_add(P_A4091, 0x41000000);
	mock_reg_fail_at = 1;
	mock_reg_errno = 16;
	CHECK(a4091_load(NULL) == 16, "sd_register's errno returned (EBUSY)");
	CHECK(mock_dma_frees == 1 && a4091_da == NULL, "the area given back");
	CHECK(a4091_halted == 1 && mock_wr8(b0, R_DMODE) == 0xe0, "the mapped board stopped");
}

static void
t_halt(void)
{
	struct mock_board *b0, *b1;

	setup();
	b0 = &mock_board[mock_add(P_A4091, 0x40000000)];
	b1 = &mock_board[mock_add(P_A4092, 0x48000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	memset(b0->regs + MOCK_WRSHADOW, 0, 0x40);
	memset(b1->regs + MOCK_WRSHADOW, 0, 0x40);
	a4091_halt();
	CHECK(a4091_halted == 1, "halt counted");
	CHECK(mock_wr8(b0, R_DMODE) == 0xe0 && mock_wr8(b0, R_SCID) == 0x80,
	    "board 0 aborted, reset and re-initialised");
	CHECK(mock_wr8(b1, R_DMODE) == 0xe0 && mock_wr8(b1, R_SCID) == 0x80,
	    "board 1 aborted, reset and re-initialised");
}

/* one aligned READ: the chip gets physical addresses in the area, and the data
 * address is dma_addr's answer, taken after prepare, before complete */
static void
t_queue_read(void)
{
	static char buf[512] __attribute__((aligned(16)));
	struct mock_board *b;
	struct ds_mirror *ds;
	unsigned long dsa, dsp, w0, pa;
	unsigned char *idp, *cdbp;

	setup();
	b = &mock_board[mock_add(P_A4091, 0x40000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	mock_addr_offset = 0x1000;	/* a k30 bounce: dma_addr != pa */
	CHECK(run_queue(0, 0, 1, buf, sizeof buf, 0x28), "READ completes");
	pa = (unsigned long)buf;

	CHECK(mock_nlog == 3, "three DMA calls");
	CHECK(mock_log[0].op == OP_PREPARE && mock_log[0].pa == pa && mock_log[0].len == 512
	    && mock_log[0].dir == 1, "prepare(pa, 512, FROM_DEVICE) first");
	CHECK(mock_log[1].op == OP_ADDR && mock_log[1].pa == pa, "then dma_addr(r, pa)");
	CHECK(mock_log[2].op == OP_COMPLETE && mock_log[2].pa == pa && mock_log[2].len == 512
	    && mock_log[2].dir == 1, "then complete(pa, 512, FROM_DEVICE)");

	dsa = mock_wr32(b, R_DSA);
	dsp = mock_wr32(b, R_DSP);
	ds = (struct ds_mirror *)area_va(dsa);
	CHECK(ds != NULL, "DSA is a physical address in the dma_alloc area");
	CHECK(area_va(dsp) != NULL, "DSP is a physical address in the dma_alloc area");
	if (area_va(dsp)) {
		memcpy(&w0, area_va(dsp), sizeof w0);
		CHECK(w0 == 0x47000000UL, "DSP points at the SCRIPTS copy");
	}
	if (ds) {
		CHECK((unsigned long)ds->p[DS_DATA1].buf == pa + 0x1000,
		    "data1buf = dma_addr's answer (the one arm site)");
		CHECK(ds->p[DS_DATA1].len == 512, "data1len = nbyte");
		idp = area_va((unsigned long)ds->p[DS_ID].buf);
		cdbp = area_va((unsigned long)ds->p[DS_CMD].buf);
		CHECK(idp && *idp == 0x80, "IDENTIFY buffer: physical, in the area, 0x80");
		CHECK(cdbp && cdbp[0] == 0x28, "CDB buffer: physical, in the area, the CDB");
	}
	CHECK(a4091_dmarec[0].drv_prep == 1 && a4091_dmarec[0].drv_cmpl == 1, "record counts");
}

/* a misaligned 16-byte READ (dd's sense): the driver's own bounce in the area,
 * prepared by its physical address, copied out by its kernel address */
static void
t_queue_bounce(void)
{
	static char raw[64] __attribute__((aligned(16)));
	char *buf = raw + 1;
	int i, zero = 1;

	setup();
	mock_add(P_A4091, 0x40000000);
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	memset(raw, 0xaa, sizeof raw);
	CHECK(run_queue(0, 0, 1, buf, 16, 0x03), "REQUEST SENSE completes");
	CHECK(mock_nlog == 3 && mock_log[0].op == OP_PREPARE, "prepare called");
	CHECK(area_va(mock_log[0].pa) != NULL && (mock_log[0].pa & 15) == 0
	    && mock_log[0].len == 16, "prepared: the area's bounce, 16-aligned, 16 bytes");
	CHECK(mock_log[1].pa == mock_log[0].pa && mock_log[2].pa == mock_log[0].pa,
	    "dma_addr and complete on the bounce");
	for (i = 0; i < 16; i++)
		if (buf[i] != 0)
			zero = 0;
	CHECK(zero, "copied out to the caller (the cleared bounce)");
	CHECK(raw[0] == (char)0xaa && raw[17] == (char)0xaa, "no byte outside the 16");
}

/* the status-line sync (C4-5 v5 section 5.4): prepare + complete FROM_DEVICE
 * over a 16-byte line in the area holding the status byte the chip wrote */
static void
check_sline(int i)
{
	unsigned char *sl = area_va(mock_log[i].pa);

	CHECK(mock_log[i].op == OP_PREPARE && mock_log[i + 1].op == OP_COMPLETE,
	    "status line: prepare then complete");
	CHECK(sl != NULL && (mock_log[i].pa & 15) == 0 && mock_log[i].len == 16
	    && mock_log[i].dir == 1 && mock_log[i + 1].pa == mock_log[i].pa
	    && mock_log[i + 1].len == 16 && mock_log[i + 1].dir == 1,
	    "status line: 16 aligned bytes in the area, FROM_DEVICE");
	CHECK(sl && sl[0] == 0xff, "status line holds the status byte");
}

/* TEST UNIT READY: no data segment; only the status line is synced */
static void
t_queue_zero(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(run_queue(0, 0, 0, NULL, 0, 0x00), "TUR completes");
	CHECK(mock_nlog == 2, "no data DMA call, one status-line sync");
	if (mock_nlog == 2)
		check_sline(0);
	CHECK(a4091_dmarec[0].drv_zero == 1, "drv_zero counted");
}

/* a WRITE: TO_DEVICE, never bounced by the driver; its complete clears no
 * cache, so the status line is synced after it */
static void
t_queue_write(void)
{
	static char raw[600] __attribute__((aligned(16)));

	setup();
	mock_add(P_A4091, 0x40000000);
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(run_queue(0, 0, 0, raw + 2, 512, 0x2a), "WRITE completes");
	CHECK(mock_nlog == 5 && mock_log[0].dir == 0
	    && mock_log[0].pa == (unsigned long)(raw + 2), "prepare(caller pa, TO_DEVICE)");
	CHECK(mock_log[2].op == OP_COMPLETE && mock_log[2].dir == 0, "data complete first");
	if (mock_nlog == 5)
		check_sline(3);
}

/* C4-5 v5: dma_addr 0 (out of reach, no bounce) -- never arm, fail the
 * command, no complete for what the provider never took */
static void
t_queue_noreach(void)
{
	static char buf[512] __attribute__((aligned(16)));
	struct mock_board *b;
	struct sdcom cp;

	setup();
	b = &mock_board[mock_add(P_A4091, 0x40000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	mock_addr_zero = 1;
	memset(&cp, 0, sizeof cp);
	cp.reading = 1; cp.cdb[0] = 0x28; cp.addr = buf; cp.nbyte = sizeof buf;
	cp.unit = 6; cp.intr = (void (*)())cb;
	CHECK(mock_reg[0].fn(0, &cp), "queue returns TRUE");
	CHECK(!cp.okay && cp.status == 0xff && intr_calls == 1, "failed: status 0xff, callback once");
	/* DSP only: on the host an 8-byte read of the DSA shadow also takes the
	 * CTEST0 byte (0x17) that a4091init writes */
	CHECK(mock_wr32(b, R_DSP) == 0, "the chip was never armed (no DSP write)");
	CHECK(mock_nlog == 2 && mock_log[0].op == OP_PREPARE && mock_log[1].op == OP_ADDR,
	    "prepare, dma_addr, and no complete");
	CHECK(a4091_dmarec[0].drv_prep == a4091_dmarec[0].drv_cmpl + 1, "the gap is the count");
	mock_addr_zero = 0;
	CHECK(run_queue(0, 0, 1, buf, sizeof buf, 0x28), "the next command runs");
}

static const struct { const char *name; void (*fn)(void); } cases[] = {
	{ "one A4091", t_one_a4091 },
	{ "A4092 identity", t_a4092 },
	{ "A4770 identity", t_a4770 },
	{ "two boards: sd order vs registration order", t_two_board_order },
	{ "four-board cap", t_four_cap },
	{ "no board", t_no_board },
	{ "no dma_alloc area", t_no_dma },
	{ "a board that does not map", t_dead_board },
	{ "no board maps", t_all_dead },
	{ "sd_register refuses", t_register_refused },
	{ "halt", t_halt },
	{ "queue: aligned READ", t_queue_read },
	{ "queue: misaligned READ (bounce)", t_queue_bounce },
	{ "queue: zero length", t_queue_zero },
	{ "queue: WRITE", t_queue_write },
	{ "queue: out of reach (dma_addr 0)", t_queue_noreach },
};

int
main(int argc, char **argv)
{
	unsigned i, bad = 0;
	int st;

	mock_verbose = argc > 1 && !strcmp(argv[1], "-v");
	for (i = 0; i < sizeof cases / sizeof cases[0]; i++) {
		fflush(stdout);
		if (fork() == 0) {
			cases[i].fn();
			printf("  %-46s %s (%d checks)\n", cases[i].name,
			    fails ? "FAIL" : "ok", checks);
			exit(fails ? 1 : 0);
		}
		wait(&st);
		if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) {
			bad++;
			if (!WIFEXITED(st))
				printf("  %-46s CRASH (signal %d)\n", cases[i].name, WTERMSIG(st));
		}
	}
	printf("%s: %u/%u cases pass\n", LINE_NAME, (unsigned)(i - bad), i);
	return bad ? 1 : 0;
}
