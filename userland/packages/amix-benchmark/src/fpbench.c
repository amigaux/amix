/* fpbench.c -- the two floating-point rows: a throughput loop, and a
 * correctness gate.
 *
 * ---------------------------------------------------------------------------
 * WHY A SEPARATE FP BENCHMARK AT ALL, AND WHAT IT IS **NOT**
 *
 * `cpu.dhry` already runs Dhrystone 2.1.  Dhrystone's measured loop is INTEGER;
 * its only floating point is the rate arithmetic printed afterwards.  The metal
 * round of 2026-08-27 measured 70,093.5 d/s with the FP-built `dhry` binary and
 * called that row "the FP-dhrystone metal row" -- meaning *the Dhrystone binary
 * that contains FP*, not *a Dhrystone of FP*.  That number is a `cpu.dhry`
 * number and belongs beside our `cpu.dhry` numbers.
 *
 * THIS file is the other thing: a loop whose measured window is nothing but
 * double-precision arithmetic.  `fpu.dhry` and `cpu.dhry` are different
 * experiments and their numbers must never be put in the same column.
 *
 * ---------------------------------------------------------------------------
 * --test dhry: A DHRYSTONE-CLASS FP THROUGHPUT LOOP
 *
 * "Dhrystone-class" means only this: a fixed, published instruction mix, run a
 * self-calibrated number of times so the measured window is long compared with
 * one clock tick, with the rate derived from tick counts and never observed per
 * operation.  It is not Dhrystone and shares no code with it.
 *
 * The kernel is a 2x2 rotation with a small forcing term.  Chosen because it is
 *   * BOUNDED for any run length -- a decaying kernel would end up doing its
 *     arithmetic on zeros (fast, and on some parts a different code path
 *     entirely), and a growing one would reach infinity and then measure
 *     infinity arithmetic.  A rotation stays on its circle forever.
 *   * ten operations exactly, written ONE OPERATION PER STATEMENT so that every
 *     intermediate is stored back to a `double`.  On the 68881/68882 the
 *     registers are EXTENDED precision; without the round trip through memory
 *     the loop would be measuring extended arithmetic and calling it double.
 *   * free of any floating-point comparison (see below).
 *
 * ★ BUILT AT -O0, ON PURPOSE.  On 2026-08-27 an FP probe built with the cross
 * gcc at -O reported "no trap" from a divide by zero; the disassembly had no
 * `fdiv` in it at all, because the compiler had constant-folded the divide.  A
 * negative -- or instant -- FP result from an optimised binary is the
 * compiler's answer, not the machine's.  So this file is built -O0 AND
 * build-fieldkit.sh counts the FP instructions in the shipped binary and
 * refuses a build that does not contain enough of them.  Two independent
 * guards, because this is the one benchmark where "it ran suspiciously fast" is
 * the expected failure mode.
 *
 * The consequence for comparability: at -O0 every operand comes from memory, so
 * the number is a FLOOR -- the cost of a double-precision operation with its
 * operands in memory.  That is deliberately the quantity an FP-emulation lane
 * cares about, where the trap-and-emulate cost dwarfs addressing entirely.
 * Compare -O0 numbers only with -O0 numbers; BUILD-INFO records the flags.
 *
 * ---------------------------------------------------------------------------
 * ★ EVERY SECOND THIS PROGRAM SPENDS IS UNDER --max-seconds (2026-08-28).
 *
 * The 2026-08-28 metal round could not measure `fpu.dhry` AT ALL on the one
 * class of machine the row exists for -- a socketed 68LC060 with no FPU, where
 * every double-precision instruction traps into a software emulator.  Three
 * seconds of work on a hardware FPU was 365 s there, and none of it was inside
 * the deadline.  Two separate defects, both fixed here:
 *
 *   1. THE FINGERPRINT RAN OUTSIDE THE DEADLINE AND WAS 40x TOO BIG.
 *      run_dhry() called fp_reference() twice before arming the deadline, at
 *      FPB_REF_RUNS = 20,000 iterations a call.  Measured on that machine
 *      (5,584,216 FPE lane entries over a 1,700 s FP window = ~304 us per
 *      emulated FP instruction, and this kernel compiles to 30 F-line
 *      instructions per iteration at -O0):
 *          2 x 20,000 x 30 x 304 us = 365 s   -- 2.0x the row's whole 180 s
 *      budget, before one measured iteration.  All three transport attempts
 *      died inside the SECOND fp_reference() call, which is why the row came
 *      back empty rather than slow.  FPB_REF_RUNS is now 512 (9.3 s there), the
 *      pilot ladder asks for --no-ref and pays none of it, and --ref-max-seconds
 *      lets a caller say out loud what it can afford.
 *
 *   2. THE MEASURED WINDOW'S DEADLINE WAS ONLY CHECKED EVERY 65,536 ITERATIONS.
 *      FPB_CHUNK was a fixed 65,536, so on that machine the FIRST chunk was
 *      65,536 x 30 x 304 us = 598 s and --max-seconds could not interrupt it --
 *      and the pilot, at 20,000 runs, was one single un-interruptible chunk.  A
 *      cap consulted less often than it fires is not a cap.  The chunk now
 *      STARTS small (FPB_CHUNK_MIN) and grows x4 only while a chunk lands under
 *      FPB_CHUNK_MIN_TICKS, so the deadline is consulted every <= ~8 ticks on
 *      any machine and the clock-read overhead stays under a tick's worth on a
 *      fast one.
 *
 * The rule this file is now held to: NOTHING between entry and the result line
 * is unbounded, and anything skipped to stay bounded is named on the row.
 *
 * ---------------------------------------------------------------------------
 * --test paranoia: A CORRECTNESS GATE, NOT A TIMING
 *
 * This row answers "does this machine's floating point compute the right
 * answers", and it FAILS LOUDLY when it does not: a non-zero exit, a named
 * failing check, and the wrong value printed in hex beside the right one.
 *
 * It is a focused IEEE-754 battery rather than a build of Kahan's paranoia.c.
 * Three reasons, all specific to this suite:
 *   * paranoia.c is a page-and-a-half of prose per run and its verdict is a
 *     count of "flaws/defects/failures" that does not reduce to one row cleanly;
 *   * it compares floating-point values against floating-point tolerances
 *     everywhere, and on this family's cross toolchain a register-to-register
 *     `fcmp` assembles with its operands REVERSED (see below) -- a correctness
 *     gate whose comparisons answer backwards is worse than no gate;
 *   * the target of this campaign is a 68LC060 with a software FPU, where every
 *     one of paranoia.c's operations is a trap into an emulator.
 *
 * Every check here therefore compares BIT PATTERNS as integers, or printed
 * strings, and every expected value is constructed from exactly representable
 * operands (powers of two, small integer quotients) rather than from a decimal
 * literal -- so the check tests the MACHINE's arithmetic and not the
 * COMPILER's decimal-to-binary conversion.
 *
 * ---------------------------------------------------------------------------
 * ★ THERE IS NOT ONE FLOATING-POINT COMPARISON IN THIS FILE, ON PURPOSE
 *
 * Same rule as iobench.c, and here it matters more.  gcc 2.7.2.3 emits SGS
 * compare operand order; the cross wrapper's fix_asm swaps it back for
 * `cmp.b/w/l` and nothing else, so a register-to-register `fcmp.x %fp2,%fp0`
 * assembles with its operands REVERSED and every `a > b` between two doubles
 * answers `b > a`.  build-fieldkit.sh refuses a build of this file whose
 * disassembly contains an `fcmp` at all.
 *
 * The reversed-fcmp defect is a defect of the TOOLCHAIN, not of the machine, so
 * it is gated at build time.  This program's job is the machine.
 *
 * ---------------------------------------------------------------------------
 * C89 with K&R definitions, as in iobench.c: valid C89 and additionally
 * acceptable to the K&R-only vendor compilers on other 68030 UNIXes.  All
 * OS-dependent code is in bench-compat.h.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <setjmp.h>
#include "bench-compat.h"

/* ------------------------------------------------------------- bit access -- */

/* `unsigned int` and not `unsigned long`: long is 32 bits on the m68k target
 * and 64 on the build host, so a two-`long` union would be sixteen bytes here
 * and eight there.  int is 32 on both. */
typedef union {
    double d;
    unsigned int w[2];
} fpb_bits;

static int g_hi = 0;                    /* index of the high-order word */
static int g_lo = 1;

/* Establish which half of the union holds the exponent, and prove the format is
 * the IEEE-754 double this program's expectations are written for.  A machine
 * that answers neither way is refused rather than measured. */
static int bits_probe()
{
    fpb_bits t;

    if (sizeof(double) != 8) return 0;
    if (sizeof(unsigned int) != 4) return 0;

    t.d = 1.0;
    if (t.w[0] == 0x3FF00000U && t.w[1] == 0U) { g_hi = 0; g_lo = 1; return 1; }
    if (t.w[1] == 0x3FF00000U && t.w[0] == 0U) { g_hi = 1; g_lo = 0; return 1; }
    return 0;
}

static unsigned int hi_of(v)
double v;
{
    fpb_bits t;
    t.d = v;
    return t.w[g_hi];
}

static unsigned int lo_of(v)
double v;
{
    fpb_bits t;
    t.d = v;
    return t.w[g_lo];
}

static unsigned int exp_of(v)
double v;
{
    return (hi_of(v) >> 20) & 0x7FFU;
}

static int is_nan(v)
double v;
{
    if (exp_of(v) != 0x7FFU) return 0;
    if ((hi_of(v) & 0x000FFFFFU) != 0U) return 1;
    if (lo_of(v) != 0U) return 1;
    return 0;
}

static int is_subnormal(v)
double v;
{
    if (exp_of(v) != 0U) return 0;
    if ((hi_of(v) & 0x000FFFFFU) != 0U) return 1;
    if (lo_of(v) != 0U) return 1;
    return 0;
}

/* ------------------------------------------------------- the FP kernel ----- */

/* Ten double-precision operations per iteration.  The constants are globals and
 * NOT const, so no compiler on any optimisation level can fold the kernel into
 * its answer.  C and S are the 7-24-25 Pythagorean triple scaled to one, so the
 * map is a rotation to within rounding and the state never leaves its circle. */
static double K_C = 0.96;
static double K_S = 0.28;
static double K_D = 1.0;        /* set to 1 + 2^-52 at startup */
static double K_E = 1.0;        /* set to 2^-30 at startup */

#define FPB_OPS_PER_ITER 10

typedef struct {
    double x;
    double y;
    double acc;
} fp_state;

static void fp_state_init(st)
fp_state *st;
{
    st->x = 1.0;
    st->y = 0.0;
    st->acc = 0.0;
}

/* ★ ONE OPERATION PER STATEMENT.  Do not "tidy" these into expressions: at -O0
 * each statement stores its result back to a double, which is what rounds the
 * 68881's extended-precision registers down to the double precision this
 * benchmark claims to measure. */
static void fp_kernel(st, n)
fp_state *st;
long n;
{
    double x, y, acc;
    double t1, t2, t3, t4, nx, ny;
    long i;

    x = st->x;
    y = st->y;
    acc = st->acc;

    for (i = 0; i < n; i++) {
        t1 = x * K_C;           /* 1  mul */
        t2 = y * K_S;           /* 2  mul */
        nx = t1 - t2;           /* 3  sub */
        t3 = x * K_S;           /* 4  mul */
        t4 = y * K_C;           /* 5  mul */
        ny = t3 + t4;           /* 6  add */
        x = nx + K_E;           /* 7  add */
        y = ny / K_D;           /* 8  div */
        t1 = nx * ny;           /* 9  mul */
        acc = acc + t1;         /* 10 add */
    }

    st->x = x;
    st->y = y;
    st->acc = acc;
}

/* The reference reduction.  A FIXED iteration count, so its answer does not
 * depend on how fast the machine is -- which is what lets the soak script use
 * "the same bits as cycle 1" as an FP regression detector, and what lets this
 * program prove its own determinism by running it twice.
 *
 * NOTE what is deliberately NOT done: the answer is not compared against a
 * constant pinned on the build host.  The 68881/68882 rounds to EXTENDED and
 * then this kernel's stores round again to double, and double rounding differs
 * from single rounding in about one operation in two thousand -- so an m68k
 * answer and an x86 answer legitimately differ, and a pinned constant would
 * turn correct hardware into a failed row.  Determinism, finiteness and the
 * paranoia battery are the checks that DO carry across machines.
 *
 * ★ FPB_REF_RUNS MUST BE A COMPILE-TIME CONSTANT.  The obvious "fix" for the
 * 2026-08-28 defect -- size it from a quick probe so it costs the same
 * everywhere -- would destroy the only property it has.  The fingerprint is
 * useful because the SAME iteration count on the SAME machine must give the
 * same 64 bits every cycle; a probe-sized count moves with the machine's load
 * and would make amix-allsoak.sh's sharpest check fire on every cycle.  So the
 * count is fixed, and it was made SMALL instead: 512 rather than 20,000.
 *
 * What that trades: 512 iterations is 5,120 double-precision operations, every
 * intermediate stored back to memory, feeding one accumulator whose low bits
 * depend on every one of them.  That is ample to catch a systematic arithmetic
 * or context-save regression, which is what the soak uses it for; it is 40x
 * less likely to walk into a once-in-a-million rare path than 20,000 was.  On
 * the machine that could not run this row at all, the whole determinism check
 * went from 365 s to 9.3 s.  A fingerprint that is taken is worth more than a
 * denser one that is not.
 *
 * ★ AND ref= VALUES ARE NOT COMPARABLE ACROSS THIS CHANGE.  The answer depends
 * on the iteration count, so a 1.0 kit's ref= and a 1.1 kit's ref= are
 * different numbers about the same machine.  BENCH_VERSION was bumped for this,
 * --info publishes ref_runs=, and the row prints it: compare like with like. */
#define FPB_REF_RUNS 512L

/* The pre-flight probe.  Fixed, tiny, and its only job is to find out how
 * expensive one iteration is on THIS machine before anything long is started --
 * so the reference pair's cost can be predicted rather than discovered by
 * hanging.  64 iterations is under a clock tick on any machine with a hardware
 * FPU (probe_us_per_run then reads 0.0, which means "faster than 1/HZ", not
 * "free") and 0.6 s on the softest soft-FPU lane measured so far. */
#define FPB_PROBE_RUNS 64L

static double fp_reference()
{
    fp_state st;
    fp_state_init(&st);
    fp_kernel(&st, FPB_REF_RUNS);
    return st.acc + st.x + st.y;
}

/* Elapsed real ticks for FPB_PROBE_RUNS iterations.  The result is thrown away
 * -- only the time is wanted -- but it is accumulated into a static so no
 * compiler can decide the call had no effect. */
static double g_probe_sink = 0.0;

/* ★ FOR THE HOST SELFTEST ONLY, and it is here for the same reason
 * --inject-fail is: the over-budget path can only be reached on a machine slow
 * enough that 1,024 iterations cost real seconds, and the host this suite runs
 * on is four orders of magnitude too fast to ever reach it.  A guard nobody has
 * watched fire is a guard nobody has tested.  -1 = not injected. */
static long g_inject_probe_ticks = -1L;

static long fp_probe(hz)
long hz;
{
    fp_state st;
    long p0, p1;

    (void) hz;
    fp_state_init(&st);
    p0 = bench_clock((long *) 0, (long *) 0);
    fp_kernel(&st, FPB_PROBE_RUNS);
    p1 = bench_clock((long *) 0, (long *) 0);
    g_probe_sink = g_probe_sink + st.acc;
    if (g_inject_probe_ticks >= 0L) return g_inject_probe_ticks;
    if (p1 - p0 < 0L) return 0L;
    return p1 - p0;
}

/* ----------------------------------------------------------- trap guard ---- */

static jmp_buf g_jb;
static int g_trapped = 0;
static int g_guard_armed = 0;

static void on_sigfpe(sig)
int sig;
{
    g_trapped = 1;
    if (g_guard_armed) longjmp(g_jb, 1);
    /* Not inside a guarded check: nothing sensible to do but stop, loudly. */
    fprintf(stderr, "fpbench: SIGFPE (%d) outside a guarded check\n", sig);
    exit(4);
}

/* -------------------------------------------------------- the FP signal ---- */

static int g_alrm_fired = 0;
static double g_alrm_result = 0.0;

static void on_sigalrm(sig)
int sig;
{
    fp_state st;

    (void) sig;
    /* Deliberately does FLOATING POINT inside the handler: the thing under test
     * is whether the interrupted computation's FP state survives someone else's
     * FP running on top of it.  On an emulated-FPU lane this is the interesting
     * question, not an edge case. */
    fp_state_init(&st);
    fp_kernel(&st, 500L);
    g_alrm_result = st.acc;
    g_alrm_fired = 1;
}

/* ------------------------------------------------------------- the checks -- */

#define K_BITS      0       /* exact hi/lo bit pattern            */
#define K_NAN       1       /* must be a NaN                      */
#define K_SUBNORMAL 2       /* must be subnormal (exp 0, frac !=0) */
#define K_STR       3       /* printed form must match exactly    */
#define K_LONG      4       /* integer result must match exactly  */
#define K_ORDER     5       /* bit patterns must sort as the values do */

#define C_IEEE   "ieee"
#define C_LIBC   "libc"
#define C_SIGNAL "signal"

typedef struct {
    char *id;
    char *cls;
    int   kind;
    unsigned int want_hi;
    unsigned int want_lo;
    char *want_str;
    long  want_long;
    char *note;
} fp_check;

/* Every expected value below was produced from exactly representable operands
 * and verified independently; the construction is in compute() and the reason
 * each one is IEEE-mandated is in the note. */
static fp_check g_checks[] = {
 { "divzero.pos",  C_IEEE, K_BITS, 0x7FF00000U, 0x00000000U, 0, 0, "1/0 = +Inf, no trap by default" },
 { "divzero.neg",  C_IEEE, K_BITS, 0xFFF00000U, 0x00000000U, 0, 0, "-1/0 = -Inf" },
 { "nan.zerodiv",  C_IEEE, K_NAN,  0U, 0U, 0, 0, "0/0 = NaN" },
 { "nan.add",      C_IEEE, K_NAN,  0U, 0U, 0, 0, "NaN + 1 = NaN (propagation)" },
 { "nan.mul",      C_IEEE, K_NAN,  0U, 0U, 0, 0, "NaN * 2 = NaN (propagation)" },
 { "overflow.inf", C_IEEE, K_BITS, 0x7FF00000U, 0x00000000U, 0, 0, "2^1000 * 2^100 overflows to +Inf" },
 { "underflow.sub",C_IEEE, K_SUBNORMAL, 0U, 0U, 0, 0, "2^-1000 / 2^40 is subnormal (gradual underflow)" },
 { "underflow.bits",C_IEEE,K_BITS, 0x00000004U, 0x00000000U, 0, 0, "...and its bits are 2^-1040 exactly" },
 { "underflow.zero",C_IEEE,K_BITS, 0x00000000U, 0x00000000U, 0, 0, "2^-1040 / 2^40 underflows to +0" },
 { "zero.neg",     C_IEEE, K_BITS, 0x80000000U, 0x00000000U, 0, 0, "0 * -1 = -0, sign preserved" },
 { "round.tie.down",C_IEEE,K_BITS, 0x3FF00000U, 0x00000000U, 0, 0, "1 + 2^-53 ties to even -> 1" },
 { "round.up",     C_IEEE, K_BITS, 0x3FF00000U, 0x00000001U, 0, 0, "1 + 2^-52 is exact" },
 { "round.075ulp", C_IEEE, K_BITS, 0x3FF00000U, 0x00000001U, 0, 0, "1 + 0.75ulp rounds up" },
 { "round.bigtie", C_IEEE, K_BITS, 0x43400000U, 0x00000000U, 0, 0, "2^53 + 1 ties to even -> 2^53" },
 { "round.bigup",  C_IEEE, K_BITS, 0x43400000U, 0x00000001U, 0, 0, "2^53 + 2 is exact" },
 { "add.tenths",   C_IEEE, K_BITS, 0x3FD33333U, 0x33333334U, 0, 0, "1/10 + 2/10, the classic" },
 { "div.third",    C_IEEE, K_BITS, 0x3FD55555U, 0x55555555U, 0, 0, "1/3 correctly rounded" },
 { "mul.third3",   C_IEEE, K_BITS, 0x3FF00000U, 0x00000000U, 0, 0, "3 * (1/3) = 1 (a tie, resolved to even)" },
 { "cvt.int2dbl",  C_IEEE, K_BITS, 0x41DFFFFFU, 0xFFC00000U, 0, 0, "(double)2147483647 is exact" },
 { "cvt.dbl2int",  C_IEEE, K_LONG, 0U, 0U, 0, -1L, "(long)-1.5 truncates toward zero" },
 { "cvt.dbl2int2", C_IEEE, K_LONG, 0U, 0U, 0, 1000000000L, "(long)1e9 built by doubling" },
 { "order.bits",   C_IEEE, K_ORDER, 0U, 0U, 0, 0, "positive doubles sort as their bit patterns do" },
 { "printf.fefg",  C_LIBC, K_STR,  0U, 0U, "3.141593|1.234568e+04|0.000123", 0,
                   "the %f|%e|%g round trip, same string the 2026-08-27 metal round recorded" }
};

#define NCHECKS ((int)(sizeof(g_checks) / sizeof(g_checks[0])))

/* Non-const seeds.  Everything the battery needs is BUILT here from these at
 * run time, so no expected value depends on the compiler's strtod. */
static double S_ZERO = 0.0;
static double S_ONE  = 1.0;
static double S_TWO  = 2.0;
static double S_THREE = 3.0;
static double S_TEN  = 10.0;
static double S_NEG  = -1.0;

static double pow2(k)
long k;
{
    double v;
    long i;

    v = S_ONE;
    if (k >= 0L) {
        for (i = 0L; i < k; i++) v = v * S_TWO;
    } else {
        for (i = 0L; i < -k; i++) v = v / S_TWO;
    }
    return v;
}

static char g_strbuf[128];
static long g_longval = 0L;

/* Compute check `which`.  Returns the double under test; K_STR fills g_strbuf
 * and K_LONG fills g_longval. */
static double compute(which)
int which;
{
    double a, b, c;
    long k;

    a = S_ZERO;
    b = S_ZERO;
    c = S_ZERO;
    k = 0L;

    switch (which) {
    case 0:  return S_ONE / S_ZERO;
    case 1:  return S_NEG / S_ZERO;
    case 2:  return S_ZERO / S_ZERO;
    case 3:  a = S_ZERO / S_ZERO; return a + S_ONE;
    case 4:  a = S_ZERO / S_ZERO; return a * S_TWO;
    case 5:  a = pow2(1000L); b = pow2(100L); return a * b;
    case 6:  a = pow2(-1000L); b = pow2(40L); return a / b;
    case 7:  a = pow2(-1000L); b = pow2(40L); return a / b;
    case 8:  a = pow2(-1000L); b = pow2(40L); c = a / b; return c / b;
    case 9:  return S_ZERO * S_NEG;
    case 10: a = pow2(-53L); return S_ONE + a;
    case 11: a = pow2(-52L); return S_ONE + a;
    case 12: a = pow2(-52L); b = S_THREE / (S_TWO * S_TWO); return S_ONE + a * b;
    case 13: a = pow2(53L); return a + S_ONE;
    case 14: a = pow2(53L); return a + S_TWO;
    case 15: a = S_ONE / S_TEN; b = S_TWO / S_TEN; return a + b;
    case 16: return S_ONE / S_THREE;
    case 17: a = S_ONE / S_THREE; return S_THREE * a;
    case 18: return (double) 2147483647L;
    case 19: a = S_THREE / S_TWO; g_longval = (long)(-a); return S_ZERO;
    case 20:
        /* 1e9 without a decimal literal: repeated multiplication by ten is
         * exact all the way to 2^53, so this tests the conversion and not the
         * compiler's strtod. */
        a = S_ONE;
        for (k = 0L; k < 9L; k++) a = a * S_TEN;
        g_longval = (long) a;
        return S_ZERO;
    case 21: return S_ZERO;             /* the ordering check needs no value */
    case 22:
        /* pi and the two format probes come from literals because what is under
         * test is the FORMATTING, not the parsing; a 1-ulp difference in any of
         * these literals cannot change any of the three printed fields. */
        sprintf(g_strbuf, "%f|%e|%g", 3.14159265358979, 12345.6789, 0.000123);
        return S_ZERO;
    default:
        return S_ZERO;
    }
}

/* The ordering check: eight ascending positive doubles, built from powers of
 * two and small quotients, must have ascending (hi,lo) bit patterns.  That is
 * an IEEE-754 property of the format and it exercises the exponent and mantissa
 * fields end to end without one floating-point comparison. */
static int order_ok()
{
    double v[8];
    unsigned int phi, plo, hi, lo;
    int i;

    v[0] = pow2(-300L);
    v[1] = pow2(-10L);
    v[2] = S_ONE / S_TWO;
    v[3] = S_ONE;
    v[4] = S_THREE / S_TWO;
    v[5] = S_TWO;
    v[6] = pow2(10L);
    v[7] = pow2(300L);

    phi = hi_of(v[0]);
    plo = lo_of(v[0]);
    for (i = 1; i < 8; i++) {
        hi = hi_of(v[i]);
        lo = lo_of(v[i]);
        if (hi < phi) return 0;
        if (hi == phi && lo <= plo) return 0;
        phi = hi;
        plo = lo;
    }
    return 1;
}

/* ------------------------------------------------------------------ args --- */

static char *g_prog = "fpbench";

static void usage()
{
    fprintf(stderr,
"usage: fpbench --test dhry [--runs N] [--max-seconds N] [--label ID]\n"
"       fpbench --test paranoia [--max-seconds N] [--label ID]\n"
"       fpbench --info | --version\n"
"\n");
    fprintf(stderr,
"  --test dhry      a Dhrystone-CLASS double-precision throughput loop.  This\n"
"                   is NOT Dhrystone: Dhrystone's measured loop is integer.\n"
"  --test paranoia  an IEEE-754 correctness battery.  Pass/fail, not a timing;\n"
"                   a wrong answer exits non-zero and names the check.\n");
    fprintf(stderr,
"  --runs N         kernel iterations for --test dhry (the harness calibrates)\n"
"  --max-seconds N  hard wall-clock cap on the MEASURED window; the run stops\n"
"                   and says capped=time.  Checked between chunks, and the\n"
"                   chunk is sized so that is at most ~8 ticks late.\n"
"  --label ID       echoed back in the result line\n"
"  --inject-fail ID corrupt one expected value.  For the HOST SELFTEST only --\n"
"                   it exists so the suite can prove this gate is not vacuous.\n");
    fprintf(stderr,
"  --no-ref         --test dhry only: skip the determinism check and the ref=\n"
"                   fingerprint.  For a CALIBRATION pilot, which needs a rate\n"
"                   and not a fingerprint; the sized run must not use it.\n");
    fprintf(stderr,
"  --ref-max-seconds N   --test dhry only: if a pre-flight probe predicts the\n"
"                   determinism check would cost more than N seconds, skip it,\n"
"                   print ref=none ref_check=skipped-over-budget and warn, and\n"
"                   still report the throughput.  Default 0 = no limit.\n");
    fprintf(stderr,
"  --inject-probe-ticks N  force the pre-flight probe's answer.  For the HOST\n"
"                   SELFTEST only -- it exists so the suite can prove the\n"
"                   --ref-max-seconds guard fires on a machine no host is.\n");
    fprintf(stderr,
"  --no-fpsig       skip the FP-state-across-a-signal check.  That check costs a\n"
"                   few seconds because a signal cannot arrive faster than\n"
"                   alarm(2)'s one-second floor; the harness runs it, the host\n"
"                   selftest skips it where it is only checking the table.\n");
}

static long parse_num(s)
char *s;
{
    long v = 0L;
    int any = 0;

    if (s == 0) return -1L;
    while (*s >= '0' && *s <= '9') {
        v = v * 10L + (long)(*s - '0');
        s++;
        any = 1;
    }
    if (!any) return -1L;
    if (*s != '\0') return -1L;
    return v;
}

/* ------------------------------------------------------------- test: dhry -- */

/* ★ THE CHUNK IS THE DEADLINE'S RESOLUTION, so it is adaptive rather than
 * fixed.  The measured loop can only notice --max-seconds between chunks; a
 * fixed 65,536 was 598 s of trap-and-emulate on the 2026-08-28 metal box, so
 * the cap could not fire until ten minutes after it was due.  Starting at
 * FPB_CHUNK_MIN and growing x4 only while a chunk lands under
 * FPB_CHUNK_MIN_TICKS gives both machines what they need:
 *
 *   soft-FPU lane   chunk never grows; deadline checked every ~1 s;
 *   hardware FPU    chunk reaches FPB_CHUNK_MAX in 6 growths, so the whole
 *                   calibration costs 6 clock reads and the steady-state loop
 *                   reads the clock about twice a second.
 *
 * The overshoot past the deadline is therefore ONE chunk, and a chunk only
 * grows if the previous one finished under 2 ticks -- so after any growth a
 * chunk is under ~8 ticks (0.13 s at HZ=60).  The single exception is the very
 * first chunk on a machine slower than any measured: FPB_CHUNK_MIN iterations,
 * ~1.2 s at the 68LC060's emulated rate.  Both bounds are stated because the
 * transport timeout upstream is sized from them. */
#define FPB_CHUNK_MIN       128L
#define FPB_CHUNK_MAX     65536L
#define FPB_CHUNK_GROW        4L
#define FPB_CHUNK_MIN_TICKS   2L

static int run_dhry(runs, max_seconds, label, want_ref, ref_max_seconds)
long runs;
long max_seconds;
char *label;
int want_ref;
long ref_max_seconds;
{
    fp_state st;
    double r1, r2;
    long hz, t0, t1, u0, u1, s0, s1, ticks, uticks, sticks;
    long done, chunk, now, prev, probe_ticks, ref_predict, ref_t0, ref_ticks;
    char *capped = "runs";
    char *warn = "ok";
    char *ref_check;
    char *refstr;
    char refbuf[32];
    int  ref_over_budget;
    double secs, fpops, rate, us_run, runs_s, probe_us;

    hz = bench_hz();
    if (hz <= 0L) hz = 60L;

    /* ---- the probe.  Bounded, tiny, and it runs FIRST so that everything
     * after it is a decision made with a number rather than a hope. -------- */
    probe_ticks = fp_probe(hz);
    probe_us = ((double) probe_ticks * 1000000.0)
             / ((double) hz * (double) FPB_PROBE_RUNS);

    /* Predicted cost of the determinism check, in ticks: two references at
     * FPB_REF_RUNS each, scaled from the probe.  Written as
     * (2*REF/PROBE) * probe_ticks so the multiply cannot overflow a 32-bit
     * long -- the leading factor is a compile-time 16. */
    ref_predict = (2L * FPB_REF_RUNS / FPB_PROBE_RUNS) * probe_ticks;

    ref_ticks = 0L;
    r1 = 0.0;
    r2 = 0.0;
    refbuf[0] = '\0';
    refstr = "none";
    ref_over_budget = 0;

    if (!want_ref) {
        /* A deliberate caller choice, not a downgrade: the pilot ladder needs
         * a rate, not a fingerprint, and paying one per pilot invocation is
         * exactly what made this row unrunnable on a soft-FPU machine. */
        ref_check = "off";
    } else if (ref_max_seconds > 0L && ref_predict > ref_max_seconds * hz) {
        /* ★ SAID OUT LOUD, NEVER SILENTLY.  The caller told us what it could
         * afford; the probe says the fingerprint costs more than that.  The
         * throughput number is still worth taking, so the row is produced --
         * with ref=none, a named reason, and warn=ref-skipped on its face. */
        ref_check = "skipped-over-budget";
        ref_over_budget = 1;
    } else {
        /* Determinism, and BEFORE the timed window: the same fixed kernel run
         * twice must give bit-identical answers.  A machine whose FP state does
         * not survive its own scheduler has nothing worth timing. */
        ref_t0 = bench_clock((long *) 0, (long *) 0);
        r1 = fp_reference();
        r2 = fp_reference();
        ref_ticks = bench_clock((long *) 0, (long *) 0) - ref_t0;
        if (ref_ticks < 0L) ref_ticks = 0L;

        if (hi_of(r1) != hi_of(r2) || lo_of(r1) != lo_of(r2)) {
            printf("FPBENCH label=%s test=dhry status=failed reason=nondeterministic \
ref1=%08x%08x ref2=%08x%08x ref_runs=%ld\n", label,
                   hi_of(r1), lo_of(r1), hi_of(r2), lo_of(r2), FPB_REF_RUNS);
            return 1;
        }
        if (exp_of(r1) == 0x7FFU) {
            printf("FPBENCH label=%s test=dhry status=failed reason=reference-not-finite \
ref=%08x%08x ref_runs=%ld\n", label, hi_of(r1), lo_of(r1), FPB_REF_RUNS);
            return 1;
        }
        sprintf(refbuf, "%08x%08x", hi_of(r1), lo_of(r1));
        refstr = refbuf;
        ref_check = "ok";
    }

    fp_state_init(&st);
    done = 0L;
    chunk = FPB_CHUNK_MIN;

    /* ==================== the measured window starts here ================== */
    t0 = bench_clock(&u0, &s0);
    prev = t0;
    while (done < runs) {
        long want = runs - done;
        if (want > chunk) want = chunk;
        fp_kernel(&st, want);
        done += want;

        now = bench_clock((long *) 0, (long *) 0);
        if (max_seconds > 0L && (now - t0) >= max_seconds * hz) {
            capped = "time";
            break;
        }
        if ((now - prev) < FPB_CHUNK_MIN_TICKS && chunk < FPB_CHUNK_MAX) {
            chunk = chunk * FPB_CHUNK_GROW;
            if (chunk > FPB_CHUNK_MAX) chunk = FPB_CHUNK_MAX;
        }
        prev = now;
    }
    t1 = bench_clock(&u1, &s1);
    /* ===================== the measured window ends here =================== */

    ticks = t1 - t0;
    uticks = u1 - u0;
    sticks = s1 - s0;
    if (ticks < 0L) ticks = 0L;

    secs = (double) ticks / (double) hz;
    fpops = (double) done * (double) FPB_OPS_PER_ITER;

    /* ★ INTEGER GUARDS, as in iobench.c.  `secs > 0.0` compiles to a
     * register-to-register fcmp whose operands GNU as 2.8.1 reads backwards. */
    rate   = (ticks > 0L) ? fpops / secs : 0.0;
    runs_s = (ticks > 0L) ? ((double) done) / secs : 0.0;
    us_run = (done > 0L && ticks > 0L) ? (secs * 1000000.0) / (double) done : 0.0;

    /* warn carries the timing verdict and, joined with '+', the fact that the
     * fingerprint could not be afforded.  One token, no spaces: every consumer
     * of this line splits on whitespace. */
    if (ticks == 0L) warn = ref_over_budget ? "zero-elapsed+ref-skipped" : "zero-elapsed";
    else if (ticks < 30L) warn = ref_over_budget ? "short-run+ref-skipped" : "short-run";
    else if (ref_over_budget) warn = "ref-skipped";

    printf("FPBENCH label=%s test=dhry status=ok runs=%ld ops_per_run=%d hz=%ld \
ticks=%ld real=%.3f user=%.3f sys=%.3f fpops=%.0f fpops_per_sec=%.1f \
runs_per_sec=%.1f us_per_run=%.3f ref=%s ref_runs=%ld ref_ticks=%ld \
ref_check=%s ref_predict_ticks=%ld probe_us_per_run=%.1f chunk=%ld \
capped=%s warn=%s\n",
           label, done, FPB_OPS_PER_ITER, hz, ticks, secs,
           (double) uticks / (double) hz, (double) sticks / (double) hz,
           fpops, rate, runs_s, us_run, refstr, FPB_REF_RUNS, ref_ticks,
           ref_check, ref_predict, probe_us, chunk, capped, warn);
    return 0;
}

/* --------------------------------------------------------- test: paranoia -- */

/* The FP-state-across-a-signal check.  Not part of the table because it needs
 * its own sizing and can legitimately report "not exercised". */
static void run_fpsig(deadline_ticks, hz, t0, nfail, npass, nchk)
long deadline_ticks;
long hz;
long t0;
int *nfail;
int *npass;
int *nchk;
{
    fp_state a, b;
    double ra, rb;
    long pilot, n, e0, e1, per_sec, tries, attempt, left, secs_left;
    char *status;
    char *note;

    *nchk += 1;
    ra = 0.0;
    rb = 0.0;
    n = 0L;

    /* ★ THE PILOT ESCALATES.  A pilot that finishes inside one clock tick tells
     * you nothing except "faster than 1/HZ", and taking that as the rate sizes
     * the real run far too short -- which is how this check quietly reports
     * "not-exercised" on every fast machine and stops being a check at all.
     * So the pilot is multiplied until it spans at least two ticks, bounded so
     * a slow FP lane cannot spend the row's whole budget in calibration. */
    pilot = 20000L;
    per_sec = 0L;
    for (tries = 0L; tries < 8L; tries++) {
        e0 = bench_clock((long *) 0, (long *) 0);
        fp_state_init(&a);
        fp_kernel(&a, pilot);
        e1 = bench_clock((long *) 0, (long *) 0);
        if (e1 - e0 >= 2L) { per_sec = (pilot * hz) / (e1 - e0); break; }
        if (pilot > 200000000L) { per_sec = pilot * hz; break; }
        pilot = pilot * 8L;
    }
    if (per_sec <= 0L) per_sec = pilot * hz;
    if (per_sec < 1000L) per_sec = 1000L;

    /* ★ AND THE SIZING RETRIES UNTIL THE SIGNAL ACTUALLY LANDS.  alarm(2) fires
     * no earlier than the next whole second, so the loop it must land inside has
     * to be comfortably longer than that -- and a pilot-derived estimate on a
     * HZ-granularity clock is routinely out by a factor of two in the wrong
     * direction.  Rather than trusting the estimate, the check DOUBLES the run
     * and tries again until the handler reports that it ran, bounded by the
     * attempts and by the row's own deadline.  A check that silently downgrades
     * itself to "not exercised" is the failure mode this loop exists to stop. */
    for (attempt = 0L; attempt < 4L; attempt++) {
        left = (deadline_ticks > 0L)
             ? deadline_ticks - (bench_clock((long *) 0, (long *) 0) - t0)
             : 3600L * hz;
        secs_left = left / hz;
        if (secs_left < 6L) break;              /* two runs plus the alarm */
        if (secs_left > 120L) secs_left = 120L; /* bound the multiply below */

        if (attempt == 0L) n = per_sec * 2L;
        else n = n * 2L;
        if (n > per_sec * (secs_left / 2L)) n = per_sec * (secs_left / 2L);
        if (n < 1000L) n = 1000L;

        fp_state_init(&a);
        fp_kernel(&a, n);
        ra = a.acc;

        g_alrm_fired = 0;
        (void) signal(SIGALRM, on_sigalrm);
        (void) alarm(1);
        fp_state_init(&b);
        fp_kernel(&b, n);
        rb = b.acc;
        (void) alarm(0);
        (void) signal(SIGALRM, SIG_IGN);

        /* A clobbered result is decided immediately: doubling the run to make
         * the signal land again would only take longer to reach the same
         * verdict, and the verdict is already known. */
        if (hi_of(ra) != hi_of(rb) || lo_of(ra) != lo_of(rb)) break;
        if (g_alrm_fired) break;
    }

    if (n == 0L) {
        printf("FPCHK id=fp.signal class=%s status=skipped note=no-time-left\n", C_SIGNAL);
        *npass += 1;
        return;
    }

    if (hi_of(ra) != hi_of(rb) || lo_of(ra) != lo_of(rb)) {
        status = "FAIL";
        note = "FP-state-clobbered-by-signal";
        *nfail += 1;
    } else if (!g_alrm_fired) {
        status = "ok";
        note = "not-exercised-no-signal-arrived";
        *npass += 1;
    } else {
        status = "ok";
        note = "FP-state-survived-a-signal-handler-doing-FP";
        *npass += 1;
    }
    printf("FPCHK id=fp.signal class=%s status=%s runs=%ld fired=%d got=%08x%08x \
want=%08x%08x note=%s\n", C_SIGNAL, status, n, g_alrm_fired,
           hi_of(rb), lo_of(rb), hi_of(ra), lo_of(ra), note);
}

static int run_paranoia(max_seconds, label, inject, want_fpsig)
long max_seconds;
char *label;
char *inject;
int want_fpsig;
{
    /* ★ EVERY LOCAL TOUCHED ACROSS setjmp() IS static, NOT auto.  A non-volatile
     * automatic modified between setjmp and longjmp has an indeterminate value
     * after the jump -- and this loop's got=/want= reporting reads exactly those
     * variables on the trapped path.  Static is the C89-portable way to say
     * "survives the jump" without sprinkling volatile through the arithmetic. */
    static int i;
    static int nfail, npass, nchk, ntrap;
    static int good;
    static unsigned int ghi, glo;
    static char *first_fail;
    static char *status;
    static long hz, t0, t1, deadline;
    double v;

    hz = bench_hz();
    if (hz <= 0L) hz = 60L;
    deadline = (max_seconds > 0L) ? max_seconds * hz : 0L;

    nfail = 0; npass = 0; nchk = 0; ntrap = 0;
    first_fail = "-";

    if (inject != 0) {
        for (i = 0; i < NCHECKS; i++) {
            if (strcmp(g_checks[i].id, inject) == 0) {
                /* Corrupt the EXPECTATION, never the arithmetic: the point is to
                 * prove the comparison and the reporting really fire. */
                g_checks[i].want_lo = g_checks[i].want_lo ^ 1U;
                g_checks[i].want_long = g_checks[i].want_long + 1L;
                g_checks[i].want_str = "deliberately-wrong";
                fprintf(stderr, "fpbench: --inject-fail corrupted the expectation for %s\n",
                        g_checks[i].id);
            }
        }
    }

    (void) signal(SIGFPE, on_sigfpe);

    t0 = bench_clock((long *) 0, (long *) 0);

    for (i = 0; i < NCHECKS; i++) {
        nchk++;
        g_trapped = 0;
        g_strbuf[0] = '\0';
        g_longval = 0L;
        good = 0;
        ghi = 0U;
        glo = 0U;

        g_guard_armed = 1;
        if (setjmp(g_jb) == 0) {
            v = compute(i);
            ghi = hi_of(v);
            glo = lo_of(v);
            switch (g_checks[i].kind) {
            case K_BITS:
                good = (ghi == g_checks[i].want_hi && glo == g_checks[i].want_lo);
                break;
            case K_NAN:
                good = is_nan(v);
                break;
            case K_SUBNORMAL:
                good = is_subnormal(v);
                break;
            case K_STR:
                good = (strcmp(g_strbuf, g_checks[i].want_str) == 0);
                break;
            case K_LONG:
                good = (g_longval == g_checks[i].want_long);
                break;
            case K_ORDER:
                good = order_ok();
                break;
            default:
                good = 0;
                break;
            }
        } else {
            good = 0;
        }
        g_guard_armed = 0;

        if (g_trapped) ntrap++;

        if (good) {
            npass++;
            status = "ok";
        } else {
            nfail++;
            status = "FAIL";
            if (strcmp(first_fail, "-") == 0) first_fail = g_checks[i].id;
        }

        if (g_checks[i].kind == K_STR) {
            printf("FPCHK id=%s class=%s status=%s got='%s' want='%s' trapped=%d note=%s\n",
                   g_checks[i].id, g_checks[i].cls, status,
                   g_strbuf, g_checks[i].want_str, g_trapped, g_checks[i].note);
        } else if (g_checks[i].kind == K_LONG) {
            printf("FPCHK id=%s class=%s status=%s got=%ld want=%ld trapped=%d note=%s\n",
                   g_checks[i].id, g_checks[i].cls, status,
                   g_longval, g_checks[i].want_long, g_trapped, g_checks[i].note);
        } else if (g_checks[i].kind == K_BITS) {
            printf("FPCHK id=%s class=%s status=%s got=%08x%08x want=%08x%08x trapped=%d note=%s\n",
                   g_checks[i].id, g_checks[i].cls, status,
                   ghi, glo, g_checks[i].want_hi, g_checks[i].want_lo,
                   g_trapped, g_checks[i].note);
        } else {
            printf("FPCHK id=%s class=%s status=%s got=%08x%08x want=%s trapped=%d note=%s\n",
                   g_checks[i].id, g_checks[i].cls, status,
                   ghi, glo,
                   (g_checks[i].kind == K_NAN) ? "any-NaN" :
                   ((g_checks[i].kind == K_SUBNORMAL) ? "any-subnormal" : "ascending"),
                   g_trapped, g_checks[i].note);
        }
    }

    if (want_fpsig) {
        run_fpsig(deadline, hz, t0, &nfail, &npass, &nchk);
    } else {
        printf("FPCHK id=fp.signal class=%s status=skipped note=--no-fpsig\n", C_SIGNAL);
    }
    if (nfail > 0 && strcmp(first_fail, "-") == 0) first_fail = "fp.signal";

    t1 = bench_clock((long *) 0, (long *) 0);

    printf("FPBENCH label=%s test=paranoia status=%s checks=%d passed=%d failed=%d \
trapped=%d first_fail=%s hz=%ld ticks=%ld real=%.3f verdict=%s warn=%s\n",
           label, (nfail == 0) ? "ok" : "failed",
           nchk, npass, nfail, ntrap, first_fail, hz, t1 - t0,
           (double)(t1 - t0) / (double) hz,
           (nfail == 0) ? "PASS" : "FAIL",
           (ntrap > 0) ? "fp-traps-enabled" : "ok");

    /* ★ THE EXIT CODE IS THE VERDICT.  A correctness gate that a caller has to
     * remember to grep for is not a gate. */
    return (nfail == 0) ? 0 : 1;
}

/* ------------------------------------------------------------------ main --- */

int main(argc, argv)
int argc;
char **argv;
{
    char *test = 0;
    char *label = "-";
    char *inject = 0;
    int  want_fpsig = 1;
    int  want_ref = 1;
    long runs = 0L;
    long max_seconds = 0L;
    long ref_max_seconds = 0L;
    int i;

    if (argc > 0 && argv[0]) g_prog = argv[0];

    /* The kernel constants that cannot be written as a short literal. */
    K_D = 1.0 + pow2(-52L);
    K_E = pow2(-30L);

    for (i = 1; i < argc; i++) {
        char *a = argv[i];
        char *v;

#define NEXTARG(name) \
        v = (i + 1 < argc) ? argv[++i] : 0; \
        if (v == 0) { fprintf(stderr, "%s: %s needs a value\n", g_prog, name); return 2; }

        if (strcmp(a, "--test") == 0)             { NEXTARG("--test"); test = v; }
        else if (strcmp(a, "--label") == 0)       { NEXTARG("--label"); label = v; }
        else if (strcmp(a, "--inject-fail") == 0) { NEXTARG("--inject-fail"); inject = v; }
        else if (strcmp(a, "--no-fpsig") == 0)    want_fpsig = 0;
        else if (strcmp(a, "--no-ref") == 0)      want_ref = 0;
        else if (strcmp(a, "--runs") == 0)        { NEXTARG("--runs"); runs = parse_num(v); }
        else if (strcmp(a, "--max-seconds") == 0) { NEXTARG("--max-seconds"); max_seconds = parse_num(v); }
        else if (strcmp(a, "--ref-max-seconds") == 0) { NEXTARG("--ref-max-seconds"); ref_max_seconds = parse_num(v); }
        else if (strcmp(a, "--inject-probe-ticks") == 0) {
            NEXTARG("--inject-probe-ticks");
            g_inject_probe_ticks = parse_num(v);
            fprintf(stderr, "fpbench: --inject-probe-ticks: the pre-flight probe will "
                            "report %s ticks instead of measuring\n", v);
        }
        else if (strcmp(a, "--info") == 0) {
            if (!bits_probe()) {
                printf("FPINFO version=%s hz=%ld ieee754=no\n", BENCH_VERSION, bench_hz());
                return 3;
            }
            printf("FPINFO version=%s hz=%ld pagesize=%ld ieee754=yes hiword=%d \
sizeof_double=%d ops_per_run=%d ref_runs=%ld probe_runs=%ld chunk_min=%ld \
chunk_max=%ld checks=%d\n",
                   BENCH_VERSION, bench_hz(), bench_pagesize(), g_hi,
                   (int) sizeof(double), FPB_OPS_PER_ITER, FPB_REF_RUNS,
                   FPB_PROBE_RUNS, FPB_CHUNK_MIN, FPB_CHUNK_MAX, NCHECKS + 1);
            return 0;
        }
        else if (strcmp(a, "--version") == 0) { printf("fpbench %s\n", BENCH_VERSION); return 0; }
        else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) { usage(); return 0; }
        else { fprintf(stderr, "%s: unknown argument '%s'\n", g_prog, a); usage(); return 2; }
#undef NEXTARG
    }

    if (runs < 0L || max_seconds < 0L || ref_max_seconds < 0L) {
        fprintf(stderr, "%s: a numeric argument was not a number\n", g_prog);
        return 2;
    }

    /* Refusing is the right answer here: every expected value in the battery is
     * an IEEE-754 double bit pattern, so on a machine whose doubles are not
     * that, a "FAIL" would be a lie about the hardware. */
    if (!bits_probe()) {
        fprintf(stderr,
"%s: this machine's `double` is not the IEEE-754 binary64 this program's\n"
"    expectations are written for (or int is not 32 bits).  Refusing to\n"
"    report a verdict about arithmetic it cannot describe.\n", g_prog);
        return 3;
    }

    if (test == 0) { fprintf(stderr, "%s: --test is required\n", g_prog); usage(); return 2; }

    if (strcmp(test, "dhry") == 0) {
        if (runs <= 0L) { fprintf(stderr, "%s: --test dhry needs --runs N\n", g_prog); return 2; }
        return run_dhry(runs, max_seconds, label, want_ref, ref_max_seconds);
    }
    if (strcmp(test, "paranoia") == 0) {
        return run_paranoia(max_seconds, label, inject, want_fpsig);
    }

    fprintf(stderr, "%s: --test must be dhry or paranoia\n", g_prog);
    return 2;
}
