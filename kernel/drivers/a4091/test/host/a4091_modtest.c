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
extern unsigned long	a4091_busreset_n, a4091_busreset_to, a4091_busreset_chg;
extern int		a4091_nboards;
extern unsigned long	a4091_halted;
extern void		*a4091_da;
extern unsigned long	a4091_dapa;
extern struct dma_rec	a4091_dmarec[];
extern int		mock_verbose;
extern unsigned long	a4091_kstat[];	/* 23 longs, magic first */
/* the static arm's diagnostics, absent from the module: weak, so a missing
 * name links as a null address */
extern long		a4091_bytewrite_probe __attribute__((weak));
extern long		a4091_dma_off __attribute__((weak));
extern unsigned long	a4091_dsps __attribute__((weak));
extern unsigned long	a4091_resid __attribute__((weak));
extern unsigned char	a4091_rc __attribute__((weak));
extern unsigned char	a4091_stat __attribute__((weak));
static int
no_static_diag(void)
{
	return &a4091_bytewrite_probe == NULL && &a4091_dma_off == NULL
	    && &a4091_dsps == NULL && &a4091_resid == NULL
	    && &a4091_rc == NULL && &a4091_stat == NULL;
}

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
	a4091_busreset = 0;	/* the bus reset cases turn it on, with the mock beam */
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
	memcpy(&w0, (char *)a4091_da + 32, sizeof w0);	/* behind the status and clear lines */
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

static unsigned char *status_va(struct mock_board *b);

/* the cache-clearing sync (C4-5 v5 section 5.4): prepare + complete FROM_DEVICE
 * over a 16-byte clear line in the area -- never over the status and message
 * bytes the chip wrote, which a bounced complete would overwrite */
static void
check_sline(int i, struct mock_board *b)
{
	unsigned char *sl = area_va(mock_log[i].pa), *st = status_va(b);

	CHECK(mock_log[i].op == OP_PREPARE && mock_log[i + 1].op == OP_COMPLETE,
	    "clear line: prepare then complete");
	CHECK(sl != NULL && (mock_log[i].pa & 15) == 0 && mock_log[i].len == 16
	    && mock_log[i].dir == 1 && mock_log[i + 1].pa == mock_log[i].pa
	    && mock_log[i + 1].len == 16 && mock_log[i + 1].dir == 1,
	    "clear line: 16 aligned bytes in the area, FROM_DEVICE");
	CHECK(sl && st && (st + 12 <= sl || st >= sl + 16),
	    "clear line overlaps neither the status nor the message bytes");
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
		check_sline(0, &mock_board[0]);
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
		check_sline(3, &mock_board[0]);
}

/* C4-5 v5: dma_addr 0 (out of reach, no bounce) -- never arm, fail the
 * command; the complete still runs (the provider counts cmpl_noprep) */
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
	CHECK(mock_nlog == 3 && mock_log[0].op == OP_PREPARE && mock_log[1].op == OP_ADDR
	    && mock_log[2].op == OP_COMPLETE && mock_log[2].pa == (unsigned long)buf
	    && mock_log[2].len == 512 && mock_log[2].dir == 1,
	    "prepare, dma_addr, then complete(pa, 512, FROM_DEVICE)");
	CHECK(a4091_dmarec[0].drv_prep == a4091_dmarec[0].drv_cmpl, "drv_prep == drv_cmpl");
	mock_addr_zero = 0;
	CHECK(run_queue(0, 0, 1, buf, sizeof buf, 0x28), "the next command runs");
}

/*
 * k30 with dma_forcebounce on: the status after a WRITE or a TUR must
 * be the byte the chip wrote, even when the provider bounces the cache-clearing
 * sync and copies a stale bounce back.  The chip's status lands before any
 * complete; the copy-back follows.  cp->status must read the chip's 0x00.
 */
static unsigned char *
status_va(struct mock_board *b)
{
	struct ds_mirror *ds = (struct ds_mirror *)area_va(mock_wr32(b, R_DSA));
	unsigned long sp;

	if (!ds)
		return NULL;
	memcpy(&sp, (char *)ds + sizeof (unsigned long) + 2 * 16 + 8, sizeof sp);
	return area_va(sp);	/* p[2].buf: stsbuf */
}

static int
run_status(int c, int reading, char *buf, unsigned n, unsigned char op)
{
	struct sdcom cp;

	memset(&cp, 0, sizeof cp);
	cp.reading = reading; cp.cdb[0] = op; cp.addr = buf; cp.nbyte = n;
	cp.unit = 6; cp.intr = (void (*)())cb;
	mock_status_done = 0;
	mock_reg[c].fn(c, &cp);
	return cp.okay ? cp.status : -1;
}

static void
t_forcebounce_status(void)
{
	static char raw[600] __attribute__((aligned(16)));
	struct mock_board *b;
	unsigned char *sva;

	setup();
	b = &mock_board[mock_add(P_A4091, 0x40000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(run_queue(0, 0, 1, raw, 512, 0x28), "a first READ (finds the status line)");
	sva = status_va(b);
	CHECK(sva != NULL, "the DSA table's status buffer is in the area");
	mock_status_va = sva;
	mock_status_val = 0x00;		/* GOOD */
	mock_forcebounce = 1;
	CHECK(run_status(0, 0, raw, 512, 0x2a) == 0x00, "WRITE: status is the chip's 0x00");
	CHECK(run_status(0, 0, NULL, 0, 0x00) == 0x00, "TUR: status is the chip's 0x00");
	CHECK(run_status(0, 1, raw, 512, 0x28) == 0x00, "READ: status is the chip's 0x00");
}

/* an absent id answers a scan with a selection timeout: the command fails,
 * silently; a phase error still prints the trace */
static void
t_seltimeout_silent(void)
{
	struct mock_board *b;

	setup();
	b = &mock_board[mock_add(P_A4091, 0x40000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	mock_chip_seltimeout(b);
	mock_trace_lines = 0;
	CHECK(run_status(0, 1, NULL, 0, 0x12) == -1, "absent id: the command fails");
	CHECK(mock_trace_lines == 0, "absent id: no trace line");
	mock_chip_phase(b);
	CHECK(run_status(0, 1, NULL, 0, 0x12) == -1, "phase error: the command fails");
	CHECK(mock_trace_lines == 1, "phase error: one trace line");
}

/*
 * The bus reset before a card's first command: RST held 2 lines, then 4000
 * lines of settle, timed by the lines that passed (the beam), not by the
 * number of changes seen.  RESET_LINES is the least real time it may take.
 */
#define RESET_LINES	4002UL

static void
reset_run(int mode, unsigned long frame, unsigned long rpl, unsigned long start)
{
	struct mock_board *b;

	setup();
	b = &mock_board[mock_add(P_A4091, 0x40000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	a4091_busreset = 1;
	mock_beam_mode = mode;
	mock_beam_frame = frame;
	mock_beam_rpl = rpl;
	mock_beam_start = start;
	mock_beam_reads = 0;
	mock_chip_seltimeout(b);
	CHECK(run_status(0, 1, NULL, 0, 0x12) == -1, "the first command (an absent id) fails");
	CHECK(a4091_busreset_n == 1, "one bus reset before it");
	if (mock_verbose)
		printf("    beam: %lu lines, %lu changes, %lu reads, %lu timeouts\n",
		    mock_beam_line, a4091_busreset_chg, mock_beam_reads, a4091_busreset_to);
}

/* the second command runs without a second reset or a beam read */
static void
reset_once(void)
{
	unsigned long reads = mock_beam_reads;

	CHECK(run_status(0, 1, NULL, 0, 0x12) == -1, "the second command fails the same");
	CHECK(a4091_busreset_n == 1 && mock_beam_reads == reads, "no second reset");
}

static void
dense(unsigned long frame, unsigned long start)
{
	reset_run(MOCK_BEAM_DENSE, frame, 4, start);
	CHECK(a4091_busreset_to == 0, "metal: no line wait times out");
	CHECK(mock_beam_line == RESET_LINES, "metal: exactly 2 + 4000 lines");
	CHECK(a4091_busreset_chg == RESET_LINES, "metal: one change per line");
	reset_once();
}

static void t_reset_pal(void) { dense(313, 0); }
static void t_reset_pal_256(void) { dense(313, 250); }
static void t_reset_pal_end(void) { dense(313, 311); }
static void t_reset_ntsc(void) { dense(263, 200); }

/* an emulator that shows the CPU two beam values a frame: the reset still
 * lasts at least 4002 lines and at most three times that, in a few dozen
 * changes (counting changes took 4002 of them: half a minute and more) */
static void
burst(unsigned long frame, unsigned long start)
{
	reset_run(MOCK_BEAM_BURST, frame, 1000, start);
	CHECK(a4091_busreset_to == 0, "burst: no line wait times out");
	CHECK(mock_beam_line >= RESET_LINES, "burst: never shorter than 4002 lines");
	CHECK(mock_beam_line <= 3 * RESET_LINES, "burst: at most three times 4002 lines");
	CHECK(a4091_busreset_chg < 100, "burst: a few dozen changes, not 4002");
	reset_once();
}

static void t_reset_burst_pal(void) { burst(313, 0); }
static void t_reset_burst_pal_mid(void) { burst(313, 200); }
static void t_reset_burst_ntsc(void) { burst(263, 100); }

/* a counter that never moves: each of the two waits gives up at its read
 * bound, the reset ends and the command still runs */
static void
t_reset_stuck(void)
{
	reset_run(MOCK_BEAM_STUCK, 313, 4, 0);
	CHECK(a4091_busreset_to == 2, "stuck: both waits time out");
	CHECK(mock_beam_reads == 2 * 200001UL, "stuck: 200000 reads per wait, plus the first");
	CHECK(a4091_busreset_chg == 0, "stuck: no change seen");
	reset_once();
}

/*
 * The module has no U77 probe, no dma_off knob and no last-command globals;
 * the kstat keeps its 23 longs (magic "A4K2"; bw_* at 8-17 stay 0), the
 * record's off is 0, and the attach line names the board and its base.
 */
#define KS_BW_RUNS	8
#define KS_BW_MASK	14
#define KS_BOUNCE_N	18
#define KS_SELTIMEOUT	22

static void
t_module_lean(void)
{
	static char raw[600] __attribute__((aligned(16)));
	struct mock_board *b;
	int i, bw;

	setup();
	b = &mock_board[mock_add(P_A4091, 0x40000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(no_static_diag(), "no U77 knob, no dma_off, no last-command globals");
	CHECK(a4091_dmarec[0].off == 0, "the record's off is 0 at attach");
	CHECK(run_queue(0, 0, 1, raw + 2, 16, 0x03), "a misaligned 16-byte read (bounce)");
	CHECK(a4091_dmarec[0].off == 0, "and stays 0");
	mock_chip_seltimeout(b);
	CHECK(run_status(0, 1, NULL, 0, 0x12) == -1, "an absent id");
	CHECK(a4091_kstat[0] == 0x41344b32UL, "kstat magic A4K2");
	CHECK(a4091_kstat[KS_BOUNCE_N] == 1 && a4091_kstat[KS_SELTIMEOUT] == 1,
	    "bounce_n at 18, seltimeout at 22: the layout has not moved");
	bw = 0;
	for (i = KS_BW_RUNS; i < KS_BW_MASK + 4; i++)
		bw |= a4091_kstat[i] != 0;
	CHECK(!bw, "bw_runs..bw_mask[3] stay 0");
#ifdef MODTEST_KVA
	CHECK(!strcmp(mock_attach_line, "a4091: board 0 at 0x40000000\n"),
	    "attach line: a4091: board 0 at 0x40000000");
#endif
}


/* ---- the interrupt path ---- */

extern unsigned long	a4091_iq[];	/* 12 longs, magic first */
#define IQ_MODE		1
#define IQ_PARAM	2
#define IQ_SELFTEST	3
#define IQ_CLAIMED	5
#define IQ_SPURIOUS	6
#define IQ_LOST		7
#define IQ_HUNG		8
#define IQ_QUEUED	9
#define IQ_QMAX		10
#define IQ_FALLBACK	11
#define R_SIEN		0x00
#define R_DIEN		0x3a

/* one A4091 loaded and its deferred self-test run, the boards answering */
static struct mock_board *
intr_up(void)
{
	struct mock_board *b;

	setup();
	b = &mock_board[mock_add(P_A4091, 0x40000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(mock_defer_fn != 0, "load asked for the deferred call");
	CHECK(a4091_iq[0] == 0x4134494eUL && a4091_iq[IQ_MODE] == 0,
	    "iq magic A4IN, polled until the self-test");
	mock_selftest_irq = 1;
	CHECK(mock_defer_fn((char *)0) == 0, "the deferred call returns 0");
	return b;
}

static struct sdcom	qcp[4];
static char		qbuf[4][512] __attribute__((aligned(16)));

static int
qcmd(int i, unsigned unit, int reading, unsigned char op)
{
	memset(&qcp[i], 0, sizeof qcp[i]);
	qcp[i].reading = reading;
	qcp[i].cdb[0] = op;
	qcp[i].addr = qbuf[i];
	qcp[i].nbyte = 512;
	qcp[i].card = 1;
	qcp[i].unit = unit;
	qcp[i].intr = (void (*)())cb;
	return mock_reg[0].fn(0, &qcp[i]);
}

static unsigned long
ds_target(struct mock_board *b)
{
	struct ds_mirror *d = (struct ds_mirror *)area_va(mock_wr32(b, R_DSA));

	return d ? d->scsi_addr : 0;
}

static void
t_intr_selftest(void)
{
	struct mock_board *b = intr_up();

	CHECK(a4091_iq[IQ_MODE] == 1 && a4091_iq[IQ_SELFTEST] == 1, "self-test passed: mode 1");
	CHECK(mock_isr != 0 && mock_isr_level == 2, "the handler on level 2");
	CHECK(mock_to_fn != 0 && mock_to_ticks > 0, "the watchdog armed");
	CHECK(!strcmp(mock_last_line, "a4091: completion on the interrupt (level 2)\n"),
	    "console: completion on the interrupt (level 2)");
	CHECK(mock_wr8(b, R_DIEN) == 0 && mock_wr8(b, R_SIEN) == 0,
	    "the enables off again after the test");
	CHECK(mock_sleeps == 1, "one tick waited");
}

static void
t_intr_selftest_fails(void)
{
	struct mock_board *b;

	setup();
	b = &mock_board[mock_add(P_A4091, 0x40000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(mock_defer_fn((char *)0) == 0, "the deferred call returns 0");
	CHECK(a4091_iq[IQ_MODE] == 0 && a4091_iq[IQ_SELFTEST] == 0, "no interrupt: polled");
	CHECK(mock_isr == 0 && mock_isr_detached == 1, "the handler detached");
	CHECK(mock_sleeps == 10, "ten ticks waited");
	CHECK(strstr(mock_last_line, "board 0: no interrupt from the self-test: polled") != NULL,
	    "console: no interrupt from the self-test: polled");
	mock_chip_done(b);
	CHECK(mock_isr_last((char *)0) == 0, "polled: the handler leaves a pending ISTAT alone");
	CHECK(run_queue(0, 0, 1, qbuf[0], 512, 0x28) && intr_calls == 1,
	    "a polled READ completes inside the queue call");
}

static void
t_intr_param0(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	CHECK(a4091_load("intr=0") == 0, "load returns 0");
	CHECK(mock_defer_fn == 0 && a4091_iq[IQ_PARAM] == 0, "intr=0: no deferred call");
	CHECK(a4091_iq[IQ_MODE] == 0, "polled");
}

static void
t_intr_complete(void)
{
	struct mock_board *b = intr_up();

	mock_chip_idle(b);
	intr_calls = 0;
	CHECK(qcmd(0, 6, 1, 0x28), "queue accepts a READ");
	CHECK(intr_calls == 0, "not completed inside the queue call");
	CHECK(mock_wr8(b, R_DIEN) == 0x35 && mock_wr8(b, R_SIEN) == 0xaf,
	    "DIEN 0x35, SIEN 0xaf for the command");
	CHECK(ds_target(b) == (0x10000UL << 6), "the chip armed for id 6");
	CHECK(mock_isr((char *)0) == 0, "chip still running: not claimed");
	mock_chip_done(b);
	CHECK(mock_isr((char *)0) == 1, "the chip's interrupt claimed");
	CHECK(intr_calls == 1 && qcp[0].okay, "completed from the handler, okay");
	CHECK(a4091_iq[IQ_CLAIMED] == 2 && a4091_iq[IQ_SPURIOUS] == 0,
	    "claimed 2 (the self-test and the command), spurious 0");
}

static void
t_intr_fifo(void)
{
	struct mock_board *b = intr_up();

	mock_chip_idle(b);
	intr_calls = 0;
	CHECK(qcmd(0, 6, 1, 0x28) && qcmd(1, 5, 0, 0x2a), "two commands queued");
	CHECK(a4091_iq[IQ_QUEUED] == 1 && a4091_iq[IQ_QMAX] == 1, "one waited, high-water 1");
	CHECK(ds_target(b) == (0x10000UL << 6), "the first one runs");
	mock_chip_done(b);
	CHECK(mock_isr((char *)0) == 1, "first interrupt claimed");
	CHECK(intr_calls == 1 && qcp[0].okay, "the first completed");
	CHECK(ds_target(b) == (0x10000UL << 5), "the second armed from the handler");
	mock_chip_done(b);
	CHECK(mock_isr((char *)0) == 1 && intr_calls == 2 && qcp[1].okay, "the second completed");
	mock_chip_idle(b);
	CHECK(mock_isr((char *)0) == 0, "then nothing pending");
}

static void
t_intr_spurious(void)
{
	struct mock_board *b = intr_up();

	mock_chip_done(b);
	intr_calls = 0;
	CHECK(mock_isr((char *)0) == 1, "a pending ISTAT with nothing in flight: claimed");
	CHECK(a4091_iq[IQ_SPURIOUS] == 1 && intr_calls == 0, "counted spurious, no completion");
}

static void
t_intr_lost(void)
{
	struct mock_board *b = intr_up();
	int i;

	intr_calls = 0;
	for (i = 0; i < 3; i++) {
		mock_chip_idle(b);
		CHECK(qcmd(i, 6, 1, 0x28) && intr_calls == i, "queued, not completed");
		mock_chip_done(b);		/* done, but no interrupt comes */
		lbolt += 31;
		mock_to_fn(mock_to_arg);
		CHECK(intr_calls == i + 1 && qcp[i].okay, "the watchdog completed it");
		CHECK(a4091_iq[IQ_LOST] == (unsigned long)i + 1, "counted lost");
	}
	CHECK(a4091_iq[IQ_MODE] == 0 && a4091_iq[IQ_FALLBACK] == 1, "three lost: polled for good");
	CHECK(!strcmp(mock_last_line, "a4091: 3 interrupts lost: polled from now on\n"),
	    "console: 3 interrupts lost: polled from now on");
	CHECK(mock_wr8(b, R_DIEN) == 0 && mock_wr8(b, R_SIEN) == 0, "the enables off");
	mock_chip_done(b);
	CHECK(qcmd(3, 6, 1, 0x28) && intr_calls == 4, "the next command runs polled");
}

static void
t_intr_hung(void)
{
	struct mock_board *b = intr_up();

	mock_chip_idle(b);
	intr_calls = 0;
	CHECK(qcmd(0, 6, 1, 0x28), "queued");
	lbolt += 31;
	mock_to_fn(mock_to_arg);
	CHECK(intr_calls == 0, "still running at the first watchdog: left alone");
	lbolt += 600;
	mock_to_fn(mock_to_arg);
	CHECK(intr_calls == 1 && !qcp[0].okay, "past the bound: failed");
	CHECK(a4091_iq[IQ_HUNG] == 1 && a4091_iq[IQ_MODE] == 1, "counted hung, still interrupt mode");
	CHECK(mock_trace_lines == 1, "traced once");
}

static void
t_intr_halt(void)
{
	struct mock_board *b = intr_up();

	a4091_halt();
	CHECK(a4091_iq[IQ_MODE] == 0, "halt: the interrupt path stands down");
	CHECK(mock_wr8(b, R_DIEN) == 0 && mock_wr8(b, R_SIEN) == 0, "halt: enables off");
}

/* C4-7, host layout: the extended command, the limits, the counters */
struct sdcomx_m {
	struct sdcom	sx_com;
	unsigned short	sx_flags, sx_nseg;
	void		*sx_seg;
	unsigned	sx_resid;
};
struct sdlim_m {
	unsigned short	sl_ver, sl_flags;
	unsigned long	sl_maxbytes;
	unsigned short	sl_maxseg, sl_align, sl_gran, sl_pad;
	unsigned long	sl_reach;
	int		(*sl_queue)();
};
extern long		a4091_xs[];	/* magic, param, rc[4], cmds, refused */
#define XS_PARAM	1
#define XS_RC		2
#define XS_CMDS		6
#define XS_REFUSED	7

static char		xbuf[65536] __attribute__((aligned(16)));
static struct sdcomx_m	xcp;

static int
xcmd(int reading, unsigned short flags, unsigned short nseg)
{
	struct sdlim_m *l = (struct sdlim_m *)mock_lim;

	memset(&xcp, 0, sizeof xcp);
	xcp.sx_com.reading = reading;
	xcp.sx_com.cdb[0] = reading ? 0x28 : 0x2a;
	xcp.sx_com.addr = xbuf;
	xcp.sx_com.nbyte = sizeof xbuf;
	xcp.sx_com.card = 1;
	xcp.sx_com.unit = 6;
	xcp.sx_com.intr = (void (*)())cb;
	xcp.sx_flags = flags;
	xcp.sx_nseg = nseg;
	xcp.sx_resid = 12345;
	return l->sl_queue(0, &xcp);
}

static void
t_lim_declared(void)
{
	struct sdlim_m *l;

	setup();
	mock_add(P_A4091, 0x40000000);
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(mock_nlim == 1 && mock_lim_fn == mock_reg[0].fn && mock_lim_c == 0,
	    "sd_limits for the registration: its queuefn, c 0");
	l = (struct sdlim_m *)mock_lim;
	CHECK(l && l->sl_ver == 1 && l->sl_flags == 0 && l->sl_maxbytes == 65536
	    && l->sl_maxseg == 1, "version 1, no lists, 64 KiB, one segment");
	CHECK(l && l->sl_align == 16 && l->sl_gran == 16 && l->sl_pad == 0
	    && l->sl_reach == 0xffffffffUL, "align 16, gran 16, reach 0xFFFFFFFF");
	CHECK(l && l->sl_queue != 0 && l->sl_queue != mock_reg[0].fn, "a queuex of its own");
	CHECK(a4091_xs[0] == 0x41345853L && a4091_xs[XS_PARAM] == 1 && a4091_xs[XS_RC] == 0,
	    "xs magic A4XS, limits=1, rc 0");
}

static void
t_lim_param0(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	CHECK(a4091_load("intr=0 limits=0") == 0, "load returns 0");
	CHECK(mock_nlim == 0 && a4091_xs[XS_PARAM] == 0 && a4091_xs[XS_RC] == -1,
	    "limits=0: nothing declared, rc -1");
	CHECK(mock_defer_fn == 0, "intr=0 read from the same string");
}

static void
t_lim_refused(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	mock_lim_errno = 89;		/* ENOSYS: a kernel before the segment minor */
	CHECK(a4091_load(NULL) == 0, "load returns 0 all the same");
	CHECK(a4091_xs[XS_RC] == 89, "the result kept");
}

static void
t_lim_queuex(void)
{
	struct mock_board *b;
	struct ds_mirror *d;

	setup();
	b = &mock_board[mock_add(P_A4091, 0x40000000)];
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK(xcmd(1, 0, 0) && intr_calls == 1, "a 64 KiB READ completes (polled)");
	CHECK(xcp.sx_com.okay && xcp.sx_resid == 0, "okay, sx_resid 0");
	d = (struct ds_mirror *)area_va(mock_wr32(b, R_DSA));
	CHECK(d && d->p[DS_DATA1].len == 65536, "one block move of 65536");
	CHECK(mock_nlog == 3 && mock_log[0].len == 65536, "one segment through prepare/addr/complete");
	mock_addr_zero = 1;
	CHECK(xcmd(0, 0, 0) && intr_calls == 2, "a WRITE out of reach completes");
	CHECK(!xcp.sx_com.okay && xcp.sx_resid == 65536, "failed, sx_resid nbyte");
	mock_addr_zero = 0;
	CHECK(xcmd(1, 1, 2) && intr_calls == 3, "a list of two completes at once");
	CHECK(!xcp.sx_com.okay && xcp.sx_resid == 65536, "refused, sx_resid nbyte");
	CHECK(xcmd(1, 1, 1) && intr_calls == 4 && xcp.sx_com.okay && xcp.sx_resid == 0,
	    "a list of one runs");
	CHECK(a4091_xs[XS_CMDS] == 3 && a4091_xs[XS_REFUSED] == 1, "cmds 3, refused 1");
	CHECK(run_queue(0, 0, 1, qbuf[0], 512, 0x28) && intr_calls == 5,
	    "a stock READ through queuefn still completes");
}

static void
t_lim_queuex_intr(void)
{
	struct mock_board *b = intr_up();

	mock_chip_idle(b);
	intr_calls = 0;
	CHECK(xcmd(1, 0, 0) && intr_calls == 0, "queued, not completed in the call");
	CHECK(xcp.sx_resid == 65536, "sx_resid nbyte until the end");
	CHECK(qcmd(0, 5, 1, 0x28), "a stock command behind it");
	mock_chip_done(b);
	CHECK(mock_isr((char *)0) == 1 && intr_calls == 1, "the sdcomx completed from the handler");
	CHECK(xcp.sx_com.okay && xcp.sx_resid == 0, "okay, sx_resid 0");
	mock_chip_done(b);
	CHECK(mock_isr((char *)0) == 1 && intr_calls == 2 && qcp[0].okay, "then the stock one");
}

static void
t_auto_nolimits(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	mock_lim_errno = 89;		/* ENOSYS: a kernel before the segment minor */
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK((long)a4091_iq[IQ_PARAM] == -1 && mock_defer_fn == 0 && a4091_iq[IQ_MODE] == 0,
	    "intr auto without limits: no deferred call, polled");
	CHECK(run_queue(0, 0, 1, qbuf[0], 512, 0x28) && intr_calls == 1,
	    "a READ completes inside the queue call");
}

static void
t_auto_limits0(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	CHECK(a4091_load("limits=0") == 0, "load returns 0");
	CHECK(mock_defer_fn == 0 && a4091_iq[IQ_MODE] == 0, "intr auto with limits=0: polled");
}

static void
t_auto_limits(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	CHECK(a4091_load(NULL) == 0, "load returns 0");
	CHECK((long)a4091_iq[IQ_PARAM] == -1 && mock_defer_fn != 0,
	    "intr auto with the limits accepted: the deferred call asked");
}

static void
t_intr1_nolimits(void)
{
	setup();
	mock_add(P_A4091, 0x40000000);
	mock_lim_errno = 89;
	CHECK(a4091_load("intr=1") == 0, "load returns 0");
	CHECK(a4091_iq[IQ_PARAM] == 1 && mock_defer_fn != 0, "intr=1 without limits: the deferred call asked");
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
	{ "status under force-bounce", t_forcebounce_status },
	{ "selection timeout is silent", t_seltimeout_silent },
	{ "bus reset: metal, PAL", t_reset_pal },
	{ "bus reset: metal, PAL, from line 250", t_reset_pal_256 },
	{ "bus reset: metal, PAL, from line 311", t_reset_pal_end },
	{ "bus reset: metal, NTSC", t_reset_ntsc },
	{ "bus reset: burst beam, PAL", t_reset_burst_pal },
	{ "bus reset: burst beam, PAL, mid-frame start", t_reset_burst_pal_mid },
	{ "bus reset: burst beam, NTSC", t_reset_burst_ntsc },
	{ "bus reset: stuck beam", t_reset_stuck },
	{ "module: no U77, no dma_off, no last-command globals", t_module_lean },
	{ "interrupt: self-test passes", t_intr_selftest },
	{ "interrupt: self-test fails, polled", t_intr_selftest_fails },
	{ "interrupt: intr=0", t_intr_param0 },
	{ "interrupt: a command completes", t_intr_complete },
	{ "interrupt: two commands, one FIFO", t_intr_fifo },
	{ "interrupt: spurious", t_intr_spurious },
	{ "interrupt: lost interrupts, fallback", t_intr_lost },
	{ "interrupt: a command that never ends", t_intr_hung },
	{ "interrupt: halt", t_intr_halt },
	{ "limits: declared after sd_register", t_lim_declared },
	{ "limits: limits=0", t_lim_param0 },
	{ "limits: sd_limits refuses", t_lim_refused },
	{ "limits: sdcomx commands, polled", t_lim_queuex },
	{ "limits: sdcomx command on the interrupt", t_lim_queuex_intr },
	{ "intr auto: no limits, polled", t_auto_nolimits },
	{ "intr auto: limits=0, polled", t_auto_limits0 },
	{ "intr auto: limits accepted, interrupt", t_auto_limits },
	{ "intr=1: interrupt without limits", t_intr1_nolimits },
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
