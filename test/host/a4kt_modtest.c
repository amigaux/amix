/* SPDX-License-Identifier: MIT */
/*
 * a4kt_modtest.c -- host tests of the a4kt710 module (S5-06): src/a4091-wr.c
 * built as its second target (-DA4091_MODULE -DA4091_A4KT; -DA4091_KVA as the
 * k46 arm) against mock.c, with a synthetic Kickstart image at 0xF80000.
 *
 * What is checked (amix-dlm C4-2 v6 section 8.1, docs/A4000T-ONBOARD-710.md
 * section 10):
 *   - the gate: without the Kickstart's "NCR scsi.device" cold-start tag, with
 *     a near-miss tag, with declared=0, on a non-AGA chipset: ENXIO and ZERO
 *     accesses under $DD0000 (no map, no probe, no DMA area);
 *   - declared=1 passes without the tag (the owner's override);
 *   - a passing gate: one registration (c 0, $DD0000, rank mobo), the attach
 *     quiesce, the host ID from the DIP bank, the D42 record's ctlid 3;
 *   - no chip, or a chip that fails the fingerprint: ENXIO, the area given back;
 *   - _halt: direct writes, DCNTL EA (0x20), SCID from the DIP host ID.
 * The queue path is the A4091's (modtest-k30/-k46).  It is not repeated here:
 * this chip's direct writes land where the mock's reads are, so a launch's
 * longword writes would overwrite the mock's "command done" state.
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

extern int		a4kt710_load();
extern void		a4091_halt();
extern long		a4091_busreset;
extern int		a4091_nboards;
extern void		*a4091_da;
extern struct dma_rec	a4091_dmarec[];
extern int		a4kt_hostid;
extern unsigned long	a4kt_gate, a4kt_tagoff;
extern int		mock_verbose;

#define ROMBASE		0xF80000UL
#define ROMLEN		0x80000UL
#define TAGOFF		0x1234UL	/* even */
#define NAMEOFF		0x5000UL

static int fails, checks;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; \
	printf("    FAIL %s (%s:%d)\n", what, __FILE__, __LINE__); } } while (0)

static unsigned char rom[ROMLEN];

static void
be32(unsigned char *p, unsigned long v)
{
	p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v;
}

/* a struct Resident at TAGOFF; how = 0 valid, 1 no RTF_COLDSTART, 2 a wrong
 * name, 3 rt_MatchTag not its own address, 4 rt_Name outside the image */
static void
mkrom(int tag, int how)
{
	unsigned char *t = rom + TAGOFF;

	memset(rom, 0, sizeof rom);
	strcpy((char *)rom + 0x100, "exec.library");	/* something else in it */
	if (!tag)
		return;
	t[0] = 0x4a; t[1] = 0xfc;
	be32(t + 2, how == 3 ? ROMBASE + TAGOFF + 2 : ROMBASE + TAGOFF);
	be32(t + 6, ROMBASE + TAGOFF + 26);
	t[10] = how == 1 ? 0x00 : 0x01;
	t[11] = 47; t[12] = 3; t[13] = 0;
	be32(t + 14, how == 4 ? 0x00200000UL : ROMBASE + NAMEOFF);
	be32(t + 18, ROMBASE + NAMEOFF + 0x20);
	strcpy((char *)rom + NAMEOFF, how == 2 ? "NCR scsi.devic" : "NCR scsi.device");
	strcpy((char *)rom + NAMEOFF + 0x20, "A4000T_scsidisk 47.4");
}

static void
setup(int tag, int how)
{
	mock_reset();
	a4091_busreset = 0;
	mkrom(tag, how);
	mock_rom = rom;
}

static void
nothing_touched(void)
{
	CHECK(mock_dd_touch == 0, "zero accesses under $DD0000");
	CHECK(mock_dma_allocs == 0 && mock_nreg == 0, "no DMA area, nothing registered");
}

static void
t_no_tag(void)
{
	setup(0, 0);
	mock_add_a4kt();
	CHECK(a4kt710_load(NULL) == 6, "ENXIO without the NCR tag");
	nothing_touched();
	CHECK(mock_rom_maps == 1 && mock_sptfrees + mock_unmaps == 1, "the Kickstart mapped once, unmapped");
	CHECK(a4kt_gate == 1, "a4kt_gate 1 (the declaration)");
}

static void
near_miss(int how)
{
	setup(1, how);
	mock_add_a4kt();
	CHECK(a4kt710_load(NULL) == 6, "ENXIO for a near-miss tag");
	nothing_touched();
}
static void t_tag_no_coldstart(void) { near_miss(1); }
static void t_tag_wrong_name(void) { near_miss(2); }
static void t_tag_bad_matchtag(void) { near_miss(3); }
static void t_tag_name_outside(void) { near_miss(4); }

static void
t_declared_0(void)
{
	setup(1, 0);
	mock_add_a4kt();
	CHECK(a4kt710_load("declared=0") == 6, "declared=0: ENXIO with the tag present");
	nothing_touched();
	CHECK(mock_rom_maps == 0, "declared=0: the Kickstart not even read");
}

static void
t_not_aga(void)
{
	setup(1, 0);
	mock_add_a4kt();
	mock_vposr_val = 0x0000;	/* OCS/ECS */
	CHECK(a4kt710_load(NULL) == 6, "ENXIO on a non-AGA chipset");
	nothing_touched();
	CHECK(a4kt_gate == 2, "a4kt_gate 2 (G0)");
}

static void
t_found(void)
{
	struct mock_board *b;

	setup(1, 0);
	b = &mock_board[mock_add_a4kt()];
	CHECK(a4kt710_load("other=3 declared=-1") == 0, "the tag found: load returns 0");
	CHECK(a4kt_tagoff == TAGOFF, "the tag's offset recorded");
	CHECK(mock_nreg == 1 && a4091_nboards == 1, "one registration");
	CHECK(mock_reg[0].c == 0 && mock_reg[0].base == 0xDD0000, "c 0 at $DD0000");
	CHECK(mock_reg[0].name && !strcmp(mock_reg[0].name, "A4000T onboard SCSI"), "the name");
	CHECK(mock_reg[0].rank == 3, "rank mobo (3)");
	CHECK(b->regs[0x00] == 0 && b->regs[0x3a] == 0, "attach quiesce: SIEN and DIEN 0, written directly");
	CHECK(a4kt_hostid == 7, "host ID 7 from an all-off DIP bank");
	CHECK(a4091_dmarec[0].magic == DMA_REC_MAGIC && a4091_dmarec[0].ctlid == 3,
	    "the D42 record, ctlid 3 (C2-1 a4000t-710)");
	CHECK(a4kt_gate == 0, "a4kt_gate 0");
}

static void
t_declared_1(void)
{
	setup(0, 0);
	mock_add_a4kt();
	CHECK(a4kt710_load("declared=1") == 0, "declared=1: load returns 0 without the tag");
	CHECK(mock_rom_maps == 0 && mock_nreg == 1, "the Kickstart not read, one registration");
}

static void
t_no_chip(void)
{
	setup(1, 0);
	CHECK(a4kt710_load(NULL) == 6, "no chip mapped: ENXIO");
	CHECK(mock_nreg == 0 && mock_dma_allocs == 1 && mock_dma_frees == 1 && a4091_da == NULL,
	    "nothing registered, the area given back");
}

static void
t_fingerprint_fails(void)
{
	struct mock_board *b;

	setup(1, 0);
	b = &mock_board[mock_add_a4kt()];
	b->regs[0x22] = 0xff;		/* ISTAT reads all-ones: no 710 */
	CHECK(a4kt710_load(NULL) == 6, "fingerprint fails: ENXIO");
	CHECK(mock_nreg == 0 && mock_dma_frees == 1, "nothing registered, the area given back");
	CHECK(a4kt_gate == 4, "a4kt_gate 4 (G2)");
	CHECK(mock_sptfrees + mock_unmaps >= 3, "the Kickstart and both chip pages unmapped");
}

static void
t_hostid_halt(void)
{
	struct mock_board *b;

	setup(1, 0);
	b = &mock_board[mock_add_a4kt()];
	b->acfg[0] = 0xfd; b->acfg[3] = 0xfd;	/* DIP: host ID 5 (either byte order) */
	CHECK(a4kt710_load(NULL) == 0, "load returns 0");
	CHECK(a4kt_hostid == 5, "host ID 5 from the DIP bank");
	a4091_halt();
	CHECK(b->regs[0x38] == 0x20, "halt: DCNTL 0x20 (EA), written directly");
	CHECK(b->regs[0x07] == (1 << 5), "halt: SCID one-hot host ID 5");
	CHECK(b->regs[0x3b] == 0xe0 && b->regs[0x00] == 0 && b->regs[0x3a] == 0,
	    "halt: DMODE 0xe0, SIEN and DIEN 0");
}

static const struct { const char *name; void (*fn)(void); } cases[] = {
	{ "no NCR tag in the Kickstart", t_no_tag },
	{ "tag without RTF_COLDSTART", t_tag_no_coldstart },
	{ "tag with a wrong name", t_tag_wrong_name },
	{ "tag whose rt_MatchTag is wrong", t_tag_bad_matchtag },
	{ "tag whose rt_Name is outside", t_tag_name_outside },
	{ "declared=0", t_declared_0 },
	{ "not AGA", t_not_aga },
	{ "tag found: attach and register", t_found },
	{ "declared=1 without the tag", t_declared_1 },
	{ "tag found, no chip", t_no_chip },
	{ "tag found, fingerprint fails", t_fingerprint_fails },
	{ "host ID and halt", t_hostid_halt },
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
