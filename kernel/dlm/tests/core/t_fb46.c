/*
 * t_fb46.c -- fb_register of core/plat/k46/line.c on the host, included
 * whole so the slot holders can be reset between cases.  The stand-ins:
 * hat_cm_fb and hat_cm_fb_add as the port's hat040.s has them (two {lo, hi}
 * slots, an identical interval accepted again, a full table refused, LO
 * stored before HI); dlm_curname as the core gives it during a _load;
 * plat_board_window with one device board, 256 MiB at 0x40000000.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <string.h>

/* what the rest of line.c links against; not called here */
char kvseg[16];
char buildid[] = " 68060-261115-01";
char *kmem_alloc(unsigned long n, int f) { (void)n, (void)f; return 0; }
void kmem_free(char *p, unsigned long n) { (void)p, (void)n; }
unsigned long vtop(char *va, char *p) { (void)va, (void)p; return 0; }
int dma_prepare(char *r, unsigned long pa, unsigned long l, int d) { (void)r, (void)pa, (void)l, (void)d; return 0; }
void dma_complete(char *r, unsigned long pa, unsigned long l, int d) { (void)r, (void)pa, (void)l, (void)d; }
char *sptalloc(int n, int m, int b, int f) { (void)n, (void)m, (void)b, (void)f; return 0; }
void sptfree(char *va, int n, int f) { (void)va, (void)n, (void)f; }
unsigned long *vatosde(char *va) { (void)va; return 0; }
unsigned long *vatopte(char *va, unsigned long *s) { (void)va, (void)s; return 0; }
void segkmem_setprot(char *s, char *va, unsigned long l, unsigned long p) { (void)s, (void)va, (void)l, (void)p; }

/* the port's table and its writer (hat040.s hat_cm_fb_add) */
unsigned long hat_cm_fb[4];
static int adds, add_refuse;

int
hat_cm_fb_add(unsigned long lo, unsigned long hi)
{
	int i;

	adds++;
	if (add_refuse || hi <= lo)
		return 0;
	for (i = 0; i < 2; i++) {
		if (hat_cm_fb[2 * i] == 0 && hat_cm_fb[2 * i + 1] == 0) {
			hat_cm_fb[2 * i] = lo;
			hat_cm_fb[2 * i + 1] = hi;
			return 1;
		}
		if (hat_cm_fb[2 * i] == lo && hat_cm_fb[2 * i + 1] == hi)
			return 1;
	}
	return 0;
}

static char *loading;			/* the module in _load, or 0 */
char *dlm_curname(void) { return loading; }

#define BOARD	0x40000000UL
#define BSIZE	0x10000000UL
int
plat_board_window(unsigned long pa, unsigned long len)
{
	return len != 0 && pa >= BOARD && len <= BSIZE && pa - BOARD <= BSIZE - len;
}

#include "../../core/plat/k46/line.c"

static int fails;

static void
check(int ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	fails += !ok;
}

static void
reset(void)
{
	memset(hat_cm_fb, 0, sizeof hat_cm_fb);
	memset(fbheld, 0, sizeof fbheld);
	adds = add_refuse = 0;
}

static int
as(char *mod, unsigned long pa, unsigned long len)
{
	int e;

	loading = mod;
	e = fb_register(pa, len);
	loading = 0;
	return e;
}

#define A	(BOARD + 0x10000UL)	/* a VA2000's framebuffer, 4 MiB */
#define AL	0x400000UL
#define B	(BOARD + 0x01000000UL)	/* another board's, 8 MiB */
#define BL	0x800000UL

int
main(void)
{
	reset();
	check(fb_register(A, AL) == EINVAL && adds == 0, "fb: outside a module's _load -> EINVAL");
	check(as("va2000", A + 0x800, AL) == EINVAL && as("va2000", A, AL - 0x800) == EINVAL,
	    "fb: an address or a length off a 4 KiB page -> EINVAL");
	check(as("va2000", A, 0) == EINVAL && as("va2000", 0xfffff000UL, 0x2000UL) == EINVAL,
	    "fb: an empty or a wrapping range -> EINVAL");
	check(as("va2000", 0x20000000UL, AL) == EINVAL && as("va2000", BOARD + BSIZE - 0x1000, 0x2000UL) == EINVAL,
	    "fb: outside a device board, or past its end -> EINVAL");
	check(adds == 0 && hat_cm_fb[1] == 0 && hat_cm_fb[3] == 0, "fb: no refusal touched the port's table");
	check(as("va2000", A, AL) == 0 && hat_cm_fb[0] == A >> 12 && hat_cm_fb[1] == (A + AL) >> 12,
	    "fb: a window inside a board -> 0, in slot 0 as page frames [lo, hi)");
	check(as("va2000", A, AL) == 0 && adds == 1 && hat_cm_fb[2] == 0,
	    "fb: the same module and window again -> 0, no second slot (a reload)");
	check(as("z3660rtg", A, AL) == EBUSY, "fb: another module, the same window -> EBUSY");
	check(as("z3660rtg", A + AL - 0x1000, 0x2000UL) == EBUSY && as("z3660rtg", BOARD, 0x11000UL) == EBUSY,
	    "fb: a window overlapping either end of a held one -> EBUSY");
	check(as("va2000", A, AL / 2) == EBUSY, "fb: the holder itself, a different window over its own -> EBUSY");
	check(as("z3660rtg", B, BL) == 0 && hat_cm_fb[2] == B >> 12 && hat_cm_fb[3] == (B + BL) >> 12,
	    "fb: a second window elsewhere -> 0, in slot 1");
	check(as("xother", BOARD + 0x02000000UL, 0x1000UL) == ENOSPC && adds == 2,
	    "fb: both slots held -> ENOSPC, the port's table not asked");
	check(as("z3660rtg", B, BL) == 0 && as("va2000", A, AL) == 0,
	    "fb: each holder may ask for its own window again after the table filled");
	check(as("va2000", A + AL, 0x1000UL) == ENOSPC, "fb: a holder's new window when both are held -> ENOSPC");

	reset();
	hat_cm_fb[0] = A >> 12;			/* a static driver's, at boot */
	hat_cm_fb[1] = (A + AL) >> 12;
	check(as("va2000", A, AL) == EBUSY && adds == 0, "fb: the kernel's own window -> EBUSY, not taken over");
	check(as("va2000", B, BL) == 0 && hat_cm_fb[2] == B >> 12, "fb: the other slot is still given out");

	reset();
	add_refuse = 1;
	check(as("va2000", A, AL) == ENOSPC && fbheld[0].name[0] == 0,
	    "fb: the port's writer refusing -> ENOSPC, no holder recorded");

	reset();
	check(as("abcdefghijklmn", A, AL) == 0 && strcmp(fbheld[0].name, "abcdefghijklmn") == 0 &&
	    as("abcdefghijklmn", A, AL) == 0, "fb: a 14-byte name is held and recognised");
	check(as("abcdefghijklmo", A, AL) == EBUSY, "fb: a name differing in its last byte is another holder");
	printf("t_fb46: %d failed\n", fails);
	return fails != 0;
}
