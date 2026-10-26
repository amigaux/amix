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

	printf("\n=== MODULE GATING: %d passed, %d failed ===\n", g_pass, g_fail);
	return g_fail ? 1 : 0;
}
