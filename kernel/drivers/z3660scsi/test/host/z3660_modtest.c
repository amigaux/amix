/*
 * z3660_modtest.c -- host test of the root-class module form of src/z3660.c
 * (-DZ3660SCSI_MODULE; kernel/dlm contracts C4-1, C4-2).
 *
 * The same driver source as z3660_test.c, built with the module switch and
 * HOST_TEST, against the same mock piscsi mailbox.  sd_register() is mocked
 * here: it records what _load hands sd.  Checks z3660scsi_load():
 *   - ENXIO, silent, nothing registered, on ECS and on an AGA window with no
 *     mailbox (no console line: C4-2 section 2);
 *   - the fixed-base board: one sd_register(z3660queue, 0, 0x10000000,
 *     "Z3660 SCSI", 1), no spl at all (the root pass stays at level 7), and
 *     the registered queue function runs a command;
 *   - an AutoConfig board with a silent mailbox: registered, sweep deferred;
 *   - a mapping failure: ENOMEM, nothing registered;
 *   - sd_register's errno passed back (EBUSY);
 * and z3660scsi_halt(): no mailbox access, recorded.
 *
 * ZS-06, the cache arm: _load sets z3660_cache from cputype (DDI_CPUTYPE,
 * here the harness's own `cputype`) and the `cache=` parameter before
 * z3660map(), and records where it came from in z3660_cache_src.  The matrix
 * is cputype 30/40/60 x cache absent, -1, 0, 40, 60, 99, not a number; on the
 * 060 with no parameter the attach check runs (z3660_ci_ok 1) and a READ
 * pushes (z3660_push_n > 0), the on-box check after boot.
 *
 * C4-7, the limits (test_c47_limits()): _load declares them after a
 * successful sd_register (one segment of 64 KiB, align 16, length 512,
 * SDL_ALLRAM with reach 0x0FFFFFFF, no SDL_SEG, sl_queue z3660queuex), not with limits=0
 * and not when sd_register failed, and loads on ENOSYS; z3660queuex runs a
 * 64 KiB READ and WRITE as one mailbox request each with sx_resid 0, leaves
 * them out of the page-cross census, refuses an SDX_SEG command without a
 * doorbell (sx_resid nbyte), and gives a failed command sx_resid nbyte.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

#include "mock_piscsi.h"
#include "stubs/rico.h"
#include "stubs/sd.h"
#include "stubs/sys/sdseg.h"

extern bool		z3660queue();
extern bool		z3660queuex();
extern long		z3660_limits, z3660_lim_rc;
extern unsigned long	z3660_xseg, z3660_pagecross_n;
extern int		z3660scsi_load();
extern void		z3660scsi_halt();
extern void		z3660_test_unmap();
extern unsigned char	z3660_present;
extern unsigned long	z3660_sig_deferred, z3660_nest_depth, z3660_nest_hits;
extern unsigned long	z3660_halted, z3660_halt_busy;
extern unsigned long	z3660_sig_ok, z3660_sig_fails, z3660_fixed_berr, z3660_fixed_ram;
extern long		z3660_cache;
extern unsigned long	z3660_ci_ok, z3660_push_n;
/* weak until the arm exists, so the matrix runs red instead of not linking */
extern long		z3660_cache_src __attribute__((weak));

long	cputype = 30;		/* what the module reads through DDI_CPUTYPE */

#define ENXIO_	6
#define ENOMEM_	12
#define EBUSY_	16

static int g_pass, g_fail;
#define CHECK(cond, msg) do { \
	if (cond) { g_pass++; printf("  ok    %s\n", (msg)); } \
	else { g_fail++; printf("  FAIL: %s   [%s:%d]\n", (msg), __FILE__, __LINE__); } \
} while (0)

/* ---- the mock sd_register (C4-1 section 3) ---------------------------- */
static int	sr_calls, sr_ret;
static bool	(*sr_fn)();
static unsigned	sr_c, sr_rank;
static char	*sr_base, *sr_name;

int sd_register( fn, c, base, name, rank)
bool	(*fn)();
unsigned c, rank;
char	*base, *name;
{
	sr_calls++;
	sr_fn = fn; sr_c = c; sr_base = base; sr_name = name; sr_rank = rank;
	return sr_ret;
}

/* ---- the mock sd_limits (C4-7 section 3) ------------------------------ */
static int		sl_calls, sl_ret;
static bool		(*sl_fn)();
static unsigned		sl_c;
static struct sdlim	*sl_l;

int sd_limits( fn, c, l)
bool		(*fn)();
unsigned	c;
struct sdlim	*l;
{
	sl_calls++;
	sl_fn = fn; sl_c = c; sl_l = l;
	return sl_ret;
}

/* ---- console capture: what _load printed ------------------------------ */
static char	cap[4096];
static int	cap_fd, cap_saved;

static void cap_begin()
{
	char	tmpl[] = "/tmp/z3660modXXXXXX";

	fflush( stdout);
	cap_fd = mkstemp( tmpl);
	unlink( tmpl);
	cap_saved = dup( 1);
	dup2( cap_fd, 1);
}

static void cap_end()
{
	ssize_t	n;

	fflush( stdout);
	dup2( cap_saved, 1);
	close( cap_saved);
	lseek( cap_fd, 0, SEEK_SET);
	n = read( cap_fd, cap, sizeof cap - 1);
	cap[n > 0 ? n : 0] = 0;
	close( cap_fd);
}

static char	*g_params;	/* the parameter string load_cell2 hands _load */

/* load_cell2: also the fixed-window gate's inputs (a bus error at the probe,
 * one boot memory region lo..hi) */
static int load_cell2( autocon_base, vposr, bus, berr, lo, hi)
unsigned long	autocon_base;
unsigned short	vposr;
int		bus, berr;
unsigned long	lo, hi;
{
	int	r;

	mock_reset();
	mock_spl_reset();
	mock_add_drive( 0, 0x00, 512UL, 0x10000UL, 256UL * 512);
	z3660_test_unmap();
	z3660_cache = 0;
	mock_autocon_base = autocon_base;
	mock_vposr = vposr;
	mock_bus_mode = bus;
	mock_bprobe_fault = berr;
	mock_mem_lo[0] = lo;
	mock_mem_hi[0] = hi;
	sr_calls = 0; sr_fn = 0; sr_base = 0; sr_name = 0; sr_c = 99; sr_rank = 0;
	sl_calls = 0; sl_fn = 0; sl_c = 99; sl_l = 0;
	cap_begin();
	r = z3660scsi_load( g_params);
	cap_end();
	return r;
}

static int load_cell( autocon_base, vposr, bus)
unsigned long	autocon_base;
unsigned short	vposr;
int		bus;
{
	return load_cell2( autocon_base, vposr, bus, 0, 0UL, 0UL);
}

static volatile int	g_done;
static void tintr( cp) struct sdcom *cp; { g_done = 1; }

/* ---- ZS-06: the cache arm matrix ------------------------------------- */
static int count_lines( s, pat)
char	*s, *pat;
{
	int	n = 0;

	while ((s = strstr( s, pat)) != 0) {
		n++;
		s += strlen( pat);
	}
	return n;
}

static long	g_preset = -7;	/* z3660_cache before _load: the arm decides */

static void arm_cell( cpu, params, want, wsrc, wsaid)
long	cpu;
char	*params;
long	want, wsrc;
int	wsaid;
{
	char	msg[160];
	int	r, said;
	long	src;

	mock_reset();
	mock_spl_reset();
	mock_add_drive( 0, 0x00, 512UL, 0x10000UL, 256UL * 512);
	z3660_test_unmap();
	z3660_cache = g_preset;
	if (&z3660_cache_src)
		z3660_cache_src = -7;
	cputype = cpu;
	mock_autocon_base = 0;
	mock_vposr = (unsigned short)0x2300;
	mock_bus_mode = MOCK_BUS_BOARD;
	sr_calls = 0;
	cap_begin();
	r = z3660scsi_load( params);
	cap_end();
	said = count_lines( cap, "z3660: cache");
	src = &z3660_cache_src ? z3660_cache_src : -99;
	sprintf( msg, "cputype %ld, %s: z3660_cache %ld (want %ld), src %ld (want %ld), %d line(s) (want %d)",
		 cpu, params ? params : "no params", z3660_cache, want, src, wsrc, said, wsaid);
	CHECK( r == 0 && sr_calls == 1 && z3660_cache == want && src == wsrc && said == wsaid, msg);
}

static void test_zs06_arm()
{
	static char	*pv[] = { 0, "cache=-1", "cache=0", "cache=40", "cache=60",
				  "cache=99", "cache=x1" };
	/* want[cpu][param], src, lines: 30 is 0 always; -1/absent by cputype;
	 * 0/40/60 as given unless the CPU has no cache ops; else by cputype + a line */
	static long	want[3][7] = {
		{  0,  0, 0,  0,  0,  0,  0 },
		{ 40, 40, 0, 40, 60, 40, 40 },
		{ 60, 60, 0, 40, 60, 60, 60 } };
	static long	wsrc[3][7] = {
		{ 0, 0, 1, 0, 0, 0, 0 },
		{ 0, 0, 1, 1, 1, 0, 0 },
		{ 0, 0, 1, 1, 1, 0, 0 } };
	static int	wsaid[3][7] = {
		{ 0, 0, 0, 1, 1, 1, 1 },
		{ 0, 0, 0, 0, 0, 1, 1 },
		{ 0, 0, 0, 0, 0, 1, 1 } };
	static long	cpus[3] = { 30, 40, 60 };
	struct sdcom	sc;
	unsigned char	buf[512];
	int		c, i;

	printf("\n=== ZS-06: the cache arm (cputype x cache=) ===\n");
	for (c = 0; c < 3; c++)
		for (i = 0; i < 7; i++)
			arm_cell( cpus[c], pv[i], want[c][i], wsrc[c][i], wsaid[c][i]);

	/* the parser's shape: other records skipped, a near-miss name is not cache= */
	arm_cell( 60L, "x=3 cache=40", 40L, 1L, 0);
	arm_cell( 60L, "  cachex=0  ", 60L, 0L, 0);
	arm_cell( 60L, "cache=", 60L, 0L, 1);
	arm_cell( 60L, "cache=60x", 60L, 0L, 1);
	arm_cell( 30L, "cache=-5", 0L, 0L, 1);
	arm_cell( 20L, 0, 0L, 0L, 0);
	arm_cell( 20L, "cache=60", 0L, 0L, 1);

	/* the on-box check after boot on the 060: armed, checked, pushing --
	 * from the module's .data 0, so an arm set after z3660map() fails here */
	g_preset = 0;
	arm_cell( 60L, 0, 60L, 0L, 0);
	g_preset = -7;
	CHECK( z3660_ci_ok == 1, "060, no parameter: the attach cache-inhibit check ran and passed (z3660_ci_ok 1)");
	z3660_push_n = 0;
	memset( &sc, 0, sizeof sc);
	sc.unit = 0; sc.intr = (void (*)())tintr; g_done = 0;
	sc.reading = 1; sc.addr = (caddr_t)buf; sc.nbyte = sizeof buf;
	sc.cdb[0] = 0x28; sc.cdb[8] = 1;		/* READ(10), one block */
	(*sr_fn)( 0, &sc);
	CHECK( g_done && sc.okay && z3660_push_n > 0,
	       "060, no parameter: a READ through the registered queue pushes (z3660_push_n > 0)");
	cputype = 30;
}

/* ---- C4-7: the limits and the extended commands ---------------------- */
static int		gx_done;
static struct sdcomx	*gx_cp;
static void xintr( cp) struct sdcom *cp; { gx_done++; gx_cp = (struct sdcomx *)cp; }

static unsigned char	xbuf[65536 + 4096];

static void x_cmd( x, op, lba, nblk, buf)
struct sdcomx	*x;
int		op;
unsigned long	lba, nblk;
unsigned char	*buf;
{
	memset( x, 0, sizeof *x);
	x->sx_com.unit = 0;
	x->sx_com.cdb[0] = op;
	x->sx_com.cdb[2] = lba >> 24; x->sx_com.cdb[3] = lba >> 16;
	x->sx_com.cdb[4] = lba >> 8;  x->sx_com.cdb[5] = lba;
	x->sx_com.cdb[7] = nblk >> 8; x->sx_com.cdb[8] = nblk;
	x->sx_com.addr = (caddr_t)buf;
	x->sx_com.nbyte = nblk * 512;
	x->sx_com.reading = (op == 0x28);
	x->sx_com.intr = (void (*)())xintr;
	x->sx_resid = 0xDEAD;
}

static void test_c47_limits()
{
	struct sdcomx	x;
	unsigned char	*bk, *buf;
	unsigned long	db, pc;
	int		r, i, same;

	printf("\n=== C4-7: the limits and the extended commands ===\n");

	sr_ret = 0; sl_ret = 0; g_params = 0;
	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD);
	CHECK( r == 0 && sr_calls == 1 && sl_calls == 1 && sl_fn == z3660queue && sl_c == 0
	       && z3660_lim_rc == 0 && z3660_limits == 1,
	       "_load declares the limits once, after sd_register, for (z3660queue, 0); result 0 kept");
	CHECK( sl_l && sl_l->sl_ver == 1 && sl_l->sl_flags == SDL_ALLRAM && sl_l->sl_maxbytes == 65536
	       && sl_l->sl_maxseg == 1 && sl_l->sl_align == 16 && sl_l->sl_gran == 512
	       && sl_l->sl_pad == 0 && sl_l->sl_reach == 0x0FFFFFFFUL && sl_l->sl_queue == z3660queuex,
	       "limits: version 1, SDL_ALLRAM and no SDL_SEG, 64 KiB, 1 segment, align 16, length 512, reach 0x0FFFFFFF, queue z3660queuex");

	/* a 64 KiB READ through sl_queue, the buffer across pages (2 KiB NBPP) */
	bk = mock_backing( 0);
	buf = xbuf + 100 * 16;			/* 16-aligned, not page-aligned */
	memset( buf, 0x5A, 65536);
	db = mock_doorbells[0]; pc = z3660_pagecross_n; gx_done = 0;
	x_cmd( &x, 0x28, 0, 128, buf);
	(*sl_l->sl_queue)( 0, &x);
	CHECK( gx_done == 1 && gx_cp == &x && x.sx_com.okay && x.sx_com.status == 0
	       && x.sx_resid == 0 && mock_doorbells[0] == db + 1 && memcmp( buf, bk, 65536) == 0,
	       "64 KiB READ (sdcomx, no SDX_SEG): one mailbox request, the data, GOOD, sx_resid 0");
	CHECK( z3660_pagecross_n == pc,
	       "a C4-7 command is contiguous: not counted in the page-cross census");

	/* a 64 KiB WRITE */
	for (i = 0; i < 65536; i++)
		buf[i] = (unsigned char)(i * 7 + 3);
	db = mock_doorbells[0]; gx_done = 0;
	x_cmd( &x, 0x2A, 128, 128, buf);
	(*sl_l->sl_queue)( 0, &x);
	CHECK( gx_done == 1 && x.sx_com.okay && x.sx_resid == 0 && mock_doorbells[0] == db + 1
	       && memcmp( bk + 128 * 512, buf, 65536) == 0,
	       "64 KiB WRITE (sdcomx): one mailbox request, the data on the disk, sx_resid 0");

	/* a stock command after it is in the census again (z3660_xcur cleared) */
	{
		struct sdcom	sc;

		memset( &sc, 0, sizeof sc);
		sc.unit = 0; sc.cdb[0] = 0x28; sc.cdb[8] = 8;
		sc.addr = (caddr_t)(xbuf + 2048 - 512);	/* crosses a 2 KiB page */
		sc.nbyte = 4096; sc.reading = 1; sc.intr = (void (*)())tintr;
		pc = z3660_pagecross_n; g_done = 0;
		z3660queue( 0, &sc);
		CHECK( g_done && sc.okay && z3660_pagecross_n == pc + 1,
		       "a stock READ across a page after a C4-7 command: counted, as before");
	}

	/* SDX_SEG: refused, no doorbell */
	db = mock_doorbells[0]; gx_done = 0;
	x_cmd( &x, 0x28, 0, 8, buf);
	x.sx_flags = SDX_SEG; x.sx_nseg = 1;
	(*sl_l->sl_queue)( 0, &x);
	CHECK( gx_done == 1 && !x.sx_com.okay && x.sx_resid == 4096 && mock_doorbells[0] == db
	       && z3660_xseg == 1,
	       "an SDX_SEG command (none declared): refused, sx_resid nbyte, no doorbell, counted");

	/* a failing extended command: past the end */
	db = mock_doorbells[0]; gx_done = 0;
	x_cmd( &x, 0x28, 0x10000UL - 4, 8, buf);
	(*sl_l->sl_queue)( 0, &x);
	CHECK( gx_done == 1 && !x.sx_com.okay && x.sx_resid == 4096 && mock_doorbells[0] == db,
	       "a C4-7 READ past the end: failed, sx_resid nbyte, no doorbell");

	/* the stock entry never touches a residual it does not have */
	same = 1;
	{
		struct sdcomx	y;

		x_cmd( &y, 0x28, 0, 8, buf);
		g_done = 0;
		y.sx_com.intr = (void (*)())tintr;
		z3660queue( 0, &y.sx_com);
		same = (y.sx_resid == 0xDEAD);
		CHECK( g_done && y.sx_com.okay && same,
		       "a command through the stock entry: run, no residual written");
	}

	g_params = "limits=0";
	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD);
	CHECK( r == 0 && sr_calls == 1 && sl_calls == 0 && z3660_limits == 0,
	       "limits=0: registered, no limits declared");
	g_params = "cache=0 limits=1";
	z3660_lim_rc = -1;
	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD);
	CHECK( r == 0 && sl_calls == 1 && z3660_limits == 1 && z3660_lim_rc == 0,
	       "limits=1 beside another parameter: declared");

	g_params = 0; sl_ret = 89;		/* ENOSYS: a kernel before the segment minor */
	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD);
	CHECK( r == 0 && sr_calls == 1 && sl_calls == 1 && z3660_lim_rc == 89,
	       "ENOSYS (no segment minor): _load still 0, the result kept, today's commands");
	sl_ret = 0;

	sr_ret = EBUSY_;
	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD);
	CHECK( r == EBUSY_ && sl_calls == 0, "sd_register refused: no limits declared");
	sr_ret = 0;
}

int main()
{
	struct sdcom	sc;
	unsigned long	trips;
	int		r;

	printf("=== z3660scsi root-class module: _load / _halt ===\n");

	sr_ret = 0;
	r = load_cell( 0UL, (unsigned short)0x2000, MOCK_BUS_BOARD);	/* ECS */
	CHECK( r == ENXIO_ && sr_calls == 0 && cap[0] == 0 && mock_trips == 0,
	       "ECS, no ConfigDev: ENXIO, silent, nothing registered, no mailbox access");

	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_ZERO);	/* AGA, open bus */
	CHECK( r == ENXIO_ && sr_calls == 0 && cap[0] == 0 && z3660_present == 0,
	       "AGA, fixed window with no mailbox: ENXIO, silent (no console line), nothing registered");

	/* AGA, an empty window that reads 0xFF with no fault (the emulated 030):
	 * the probe read passes the gate, the signature refuses */
	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_ONES);
	CHECK( r == ENXIO_ && sr_calls == 0 && cap[0] == 0 && z3660_present == 0
	       && mock_bprobe_calls == 1 && z3660_fixed_berr == 0 && z3660_fixed_ram == 0
	       && z3660_sig_ok == 0 && z3660_sig_fails == 1 && mock_doorbells[0] == 0,
	       "AGA, fixed window reading all ones, no fault: gate passes, signature refuses, ENXIO, silent");

	r = load_cell2( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD, 1, 0UL, 0UL);
	CHECK( r == ENXIO_ && sr_calls == 0 && cap[0] == 0 && z3660_present == 0
	       && mock_trips == 0 && mock_bprobe_calls == 1,
	       "AGA, the fixed window's probe read faults: ENXIO, silent, no mailbox access");

	r = load_cell2( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD, 0,
	    0x08000000UL, 0x18000000UL);
	CHECK( r == ENXIO_ && sr_calls == 0 && cap[0] == 0 && z3660_present == 0
	       && mock_trips == 0 && mock_bprobe_calls == 0,
	       "AGA, boot memory over the fixed window: ENXIO, silent, zero accesses");

	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD);	/* AGA, the board */
	CHECK( r == 0 && sr_calls == 1, "fixed-base board: _load 0, one sd_register");
	CHECK( strcmp( cap, "z3660: units 1-7: no drive mapped\n") == 0,
	       "fixed-base board: the empty units 1-7 named on one console line, nothing else");
	CHECK( sr_fn == z3660queue && sr_c == 0 && sr_base == (char *)0x10000000UL
	       && sr_name && strcmp( sr_name, "Z3660 SCSI") == 0 && sr_rank == 1,
	       "sd_register(z3660queue, 0, 0x10000000, \"Z3660 SCSI\", 1 = rank z3660)");
	CHECK( mock_spl6_calls == 0 && mock_splx_calls == 0 && z3660_nest_depth == 0
	       && z3660_nest_hits == 0,
	       "_load takes no spl: the root pass stays at level 7; nest accounting balanced");

	memset( &sc, 0, sizeof sc);			/* TEST UNIT READY through sd's entry */
	sc.unit = 0; sc.intr = (void (*)())tintr; g_done = 0;
	(*sr_fn)( 0, &sc);
	CHECK( g_done && sc.okay && sc.status == 0,
	       "the registered queue function completes TEST UNIT READY GOOD");

	trips = mock_trips;
	z3660scsi_halt();
	CHECK( mock_trips == trips && z3660_halted == 1 && z3660_halt_busy == 0,
	       "_halt: no mailbox access, recorded, nothing in flight");

	r = load_cell( 0x40000000UL, (unsigned short)0x2300, MOCK_BUS_ZERO);	/* ConfigDev, silent */
	CHECK( r == 0 && sr_calls == 1 && sr_base == (char *)0x40000000UL && z3660_sig_deferred == 1,
	       "AutoConfig board, mailbox silent: registered at its base, unit sweep deferred");

	mock_sptalloc_fail = 1;
	r = load_cell( 0x40000000UL, (unsigned short)0x2300, MOCK_BUS_BOARD);
	CHECK( r == 0, "(control) the high board with sptalloc working: 0");
	mock_reset(); mock_spl_reset(); z3660_test_unmap();
	mock_autocon_base = 0x40000000UL; mock_sptalloc_fail = 1;
	sr_calls = 0;
	cap_begin(); r = z3660scsi_load( (char *)0); cap_end();
	CHECK( r == ENOMEM_ && sr_calls == 0 && strstr( cap, "cannot map") != 0,
	       "mapping failure: ENOMEM (printed by the core and named by z3660map), nothing registered");

	sr_ret = EBUSY_;
	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD);
	CHECK( r == EBUSY_ && sr_calls == 1 && strstr( cap, "sd_register failed") != 0,
	       "sd_register refuses (EBUSY): _load returns it, one console line");
	sr_ret = 0;

	test_zs06_arm();
	test_c47_limits();

	printf("\n=== MODULE GATING: %d passed, %d failed ===\n", g_pass, g_fail);
	return g_fail ? 1 : 0;
}
