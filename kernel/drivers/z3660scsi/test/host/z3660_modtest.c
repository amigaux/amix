/*
 * z3660_modtest.c -- host test of the root-class module form of src/z3660.c
 * (-DZ3660SCSI_MODULE; amix-dlm contracts C4-1, C4-2).
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
 * pushes (z3660_push_n > 0), the Bench's check after boot.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

#include "mock_piscsi.h"
#include "stubs/rico.h"
#include "stubs/sd.h"

extern bool		z3660queue();
extern int		z3660scsi_load();
extern void		z3660scsi_halt();
extern void		z3660_test_unmap();
extern unsigned char	z3660_present;
extern unsigned long	z3660_sig_deferred, z3660_nest_depth, z3660_nest_hits;
extern unsigned long	z3660_halted, z3660_halt_busy;
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

static int load_cell( autocon_base, vposr, bus)
unsigned long	autocon_base;
unsigned short	vposr;
int		bus;
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
	sr_calls = 0; sr_fn = 0; sr_base = 0; sr_name = 0; sr_c = 99; sr_rank = 0;
	cap_begin();
	r = z3660scsi_load( (char *)0);
	cap_end();
	return r;
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

	/* the Bench's check after boot on the 060: armed, checked, pushing --
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

	r = load_cell( 0UL, (unsigned short)0x2300, MOCK_BUS_BOARD);	/* AGA, the board */
	CHECK( r == 0 && sr_calls == 1, "fixed-base board: _load 0, one sd_register");
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

	printf("\n=== MODULE GATING: %d passed, %d failed ===\n", g_pass, g_fail);
	return g_fail ? 1 : 0;
}
