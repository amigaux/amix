/* iobench.c -- the four disk patterns a plain `dd` cannot measure.
 *
 * dd gives you one number: sequential throughput at one block size, through the
 * buffer cache, timed by a shell.  What we actually need to know about an Amix
 * box is how the SAME device behaves under SEQUENTIAL vs RANDOM access, at
 * block sizes from one sector to 64 KB, in both directions -- because that is
 * the shape that tells a slow *device* apart from a slow *request path*.  On the
 * Z3660 the firmware reports its own side of every request ([PSTAT]: seek, io,
 * cache, and the inter-request gap); this program reports the guest side of the
 * same requests, and the two laid side by side say where the time went.
 *
 * ---------------------------------------------------------------------------
 * TIMING, AND WHY IT IS DONE THIS WAY
 *
 * The clock is times(), whose granularity is HZ -- 60/s on Amix.  One tick is
 * 16.7 ms, which is LARGER than a whole fast request, so a per-operation clock
 * read would measure nothing but quantisation noise.  Therefore:
 *
 *   * the measured window is bracketed by EXACTLY TWO times() calls, one before
 *     the first operation and one after the last;
 *   * per-operation latency is DERIVED -- elapsed / op count -- never observed;
 *   * a run shorter than 30 ticks (0.5 s) is reported with warn=short-run,
 *     because at that length the +-1 tick quantisation is already >3%.
 *
 * The one exception is the wall-clock cap (--max-seconds), which needs to look
 * at the clock during the run.  It looks every 16 operations, so the cap costs
 * ops/16 extra times() syscalls inside the window -- a few hundred over a
 * multi-second run, well under a millisecond in total.  The cap exists because
 * this suite is handed to people with unknown hardware: a 512-byte random read
 * pattern on a slow SCSI disk can take an hour, and an unbounded benchmark on
 * someone else's machine is a bug.
 *
 * ---------------------------------------------------------------------------
 * SAFETY: THIS PROGRAM CANNOT CREATE A FILE
 *
 * Write patterns require --allow-write AND an existing target: the open is
 * O_WRONLY with no O_CREAT.  A mistyped path therefore fails with ENOENT
 * instead of quietly creating a file (or, worse, matching some other real path
 * than the one you meant).  Creating the scratch file is the harness's job, and
 * the harness only does it for a path the operator named after --write-target.
 * Writing to a RAW DISK DEVICE destroys whatever is on it; that is on purpose
 * and it is why three separate layers all demand an explicit target.
 *
 * ---------------------------------------------------------------------------
 * DETERMINISM
 *
 * Random offsets come from a 32-bit LCG whose state is masked to 32 bits after
 * every step, so the sequence is identical on a 32-bit m68k and on a 64-bit
 * host.  That is what makes `--plan` meaningful: the host-side selftest can
 * print the exact offset sequence the box will use, and prove it is stable,
 * in-range and block-aligned, without a box.
 *
 * ---------------------------------------------------------------------------
 * THE ARITHMETIC SELF-CHECK
 *
 * The random offset generator divides by a VARIABLE divisor.  On this family's
 * cross toolchain that operation was silently wrong until 2026-07-20 (GNU as
 * 2.8.1 assembled the SGS `tdivs.l` mnemonic as the 64-bit-dividend DIVS.L, so
 * every variable-divisor / and % returned garbage).  A benchmark whose offsets
 * are garbage still prints a plausible number, so this program refuses to run
 * unless two known divisions come out right -- it is a live witness that the
 * binary in front of you was built with a fixed toolchain.
 *
 * ---------------------------------------------------------------------------
 * ★ THERE IS NOT ONE FLOATING-POINT COMPARISON IN THIS FILE, ON PURPOSE
 *
 * Same defect CLASS, second instance.  gcc 2.7.2.3 emits SGS compare operand
 * order, and the cross wrapper's fix_asm swaps it back into GNU order for
 * `cmp.b/w/l` -- but not for `fcmp`.  A register-to-register `fcmp.x %fp2,%fp0`
 * therefore assembles with its operands REVERSED, so every `a > b` between two
 * doubles answers `b > a`.  (The register/memory form fails loudly with
 * "operands mismatch"; the register/register form does not.)  It cost this file
 * one metal run -- see the guard comment at the derived-field computation.
 *
 * So: guard on integers (ticks, ops), never on `secs`.  build-fieldkit.sh
 * refuses a cross build whose disassembly contains an `fcmp` at all, and the
 * selftest proves that gate is non-vacuous.
 *
 * C89 with K&R definitions on purpose: valid C89, and additionally acceptable
 * to the K&R-only vendor compilers still found on other 68030 UNIXes.  All
 * OS-dependent code is in bench-compat.h.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* iobench is the one benchmark that touches files, so it is the one that asks
 * bench-compat.h for the file primitives. */
#define BENCH_WANT_FILE 1
#include "bench-compat.h"

#define PAT_SEQ   0
#define PAT_RAND  1
#define DIR_READ  0
#define DIR_WRITE 1

#define MAX_BS      (1024L * 1024L)
#define TIME_CHECK_OPS 16
#define SHORT_RUN_TICKS 30

/* Non-const on purpose: the arithmetic self-check must divide by a value the
 * compiler cannot constant-fold, or it would prove nothing about the machine. */
static unsigned long g_div151 = 151UL;
static long          g_sdiv151 = 151L;

static char *g_prog = "iobench";

/* Split across several fprintf calls on purpose: C89 only guarantees string
 * literals up to 509 characters, and this text is checked with -pedantic. */
static void usage()
{
    fprintf(stderr,
"usage: iobench --path P --pattern seq|rand --dir read|write --bs N\n"
"               [--bytes N] [--ops N] [--max-seconds N] [--span N]\n"
"               [--seed N] [--sync] [--allow-write] [--label ID]\n"
"       iobench --plan --pattern rand --bs N --span N --ops N [--seed N]\n"
"       iobench --info | --version\n"
"\n");
    fprintf(stderr,
"  --path P         file or RAW device to exercise.  Never created: a write to\n"
"                   a nonexistent path fails instead of making one.\n"
"  --pattern seq    sequential from offset 0, wrapping at the extent\n"
"  --pattern rand   deterministic seeded random block offsets\n"
"  --dir read       read-only; safe on any target\n"
"  --dir write      DESTROYS the target's contents; needs --allow-write\n");
    fprintf(stderr,
"  --bs N           transfer size in bytes (suffix K/M allowed)\n"
"  --bytes N        stop after N bytes moved\n"
"  --ops N          stop after N operations\n"
"  --max-seconds N  stop after N seconds (checked every 16 ops)\n"
"  --span N         extent to address; required for rand on a raw device\n");
    fprintf(stderr,
"  --seed N         LCG seed (default 1); same seed = same offsets everywhere\n"
"  --sync           open writes O_SYNC (refused if the libc lacks it)\n"
"  --label ID       echoed back in the result line\n"
"  --plan           print the offset sequence and exit; no I/O is performed\n"
"  --info           print HZ and build facts and exit\n");
}

/* ------------------------------------------------------------ arithmetic --- */

static int arith_ok()
{
    unsigned long u;
    long s;

    u = 3141592653UL;
    if ((u % g_div151) != 54UL) return 0;
    if ((u / g_div151) != 20805249UL) return 0;
    s = 351L;
    if ((s % g_sdiv151) != 49L) return 0;
    if ((s / g_sdiv151) != 2L) return 0;
    return 1;
}

/* ------------------------------------------------------------- arg parse --- */

/* Accepts a decimal count with an optional K/M suffix.  Returns -1 on garbage
 * rather than silently yielding 0 -- a benchmark that ran "0 bytes" because of
 * a typo is worse than one that refused. */
static long parse_size(s)
char *s;
{
    long v = 0;
    int any = 0;

    if (s == 0) return -1;
    while (*s >= '0' && *s <= '9') {
        v = v * 10 + (long)(*s - '0');
        s++;
        any = 1;
    }
    if (!any) return -1;
    if (*s == 'k' || *s == 'K') { v *= 1024L; s++; }
    else if (*s == 'm' || *s == 'M') { v *= 1024L * 1024L; s++; }
    if (*s != '\0') return -1;
    if (v < 0) return -1;
    return v;
}

/* ------------------------------------------------------- offset generator --- */

/* 32-bit LCG, masked every step so the sequence does not depend on the width of
 * `unsigned long`.  The high bits are the good ones in an LCG, so the block
 * index is taken from state>>8. */
static unsigned long g_lcg = 1UL;

static void lcg_seed(seed)
unsigned long seed;
{
    g_lcg = seed & 0xFFFFFFFFUL;
    if (g_lcg == 0UL) g_lcg = 1UL;
}

static unsigned long lcg_next()
{
    g_lcg = (g_lcg * 1103515245UL + 12345UL) & 0xFFFFFFFFUL;
    return g_lcg;
}

/* Block index in [0, nblocks).  nblocks is a RUNTIME value: this is the
 * variable-divisor modulo the arithmetic self-check guards. */
static unsigned long next_block(nblocks)
unsigned long nblocks;
{
    if (nblocks <= 1UL) return 0UL;
    return (lcg_next() >> 8) % nblocks;
}

/* ------------------------------------------------------------------ main --- */

int main(argc, argv)
int argc;
char **argv;
{
    char *path = 0;
    char *label = "-";
    int   pattern = PAT_SEQ;
    int   dir = DIR_READ;
    long  bs = 0;
    long  want_bytes = 0;
    long  want_ops = 0;
    long  max_seconds = 0;
    long  span = 0;
    unsigned long seed = 1UL;
    int   want_sync = 0;
    int   allow_write = 0;
    int   do_plan = 0;
    int   have_pattern = 0, have_dir = 0;

    int   fd = -1;
    char *rawbuf = 0;
    char *buf = 0;
    long  hz;
    long  t0, t1, u0, u1, s0, s1;
    long  ticks, uticks, sticks;
    unsigned long ops = 0, shortio = 0, errs = 0, nblocks = 0, wraps = 0;
    unsigned long bytes = 0;
    BENCH_OFF_T off = 0;
    char *capped = "none";
    char *warn = "ok";
    double secs, kb_s, ops_s, us_op;
    long i;
    int rc = 0;

    if (argc > 0 && argv[0]) g_prog = argv[0];

    for (i = 1; i < (long) argc; i++) {
        char *a = argv[i];
        char *v;

#define NEXTARG(name) \
        v = (i + 1 < (long) argc) ? argv[++i] : 0; \
        if (v == 0) { fprintf(stderr, "%s: %s needs a value\n", g_prog, name); return 2; }

        if (strcmp(a, "--path") == 0)              { NEXTARG("--path"); path = v; }
        else if (strcmp(a, "--label") == 0)        { NEXTARG("--label"); label = v; }
        else if (strcmp(a, "--pattern") == 0) {
            NEXTARG("--pattern");
            if (strcmp(v, "seq") == 0) pattern = PAT_SEQ;
            else if (strcmp(v, "rand") == 0) pattern = PAT_RAND;
            else { fprintf(stderr, "%s: --pattern must be seq or rand\n", g_prog); return 2; }
            have_pattern = 1;
        }
        else if (strcmp(a, "--dir") == 0) {
            NEXTARG("--dir");
            if (strcmp(v, "read") == 0) dir = DIR_READ;
            else if (strcmp(v, "write") == 0) dir = DIR_WRITE;
            else { fprintf(stderr, "%s: --dir must be read or write\n", g_prog); return 2; }
            have_dir = 1;
        }
        else if (strcmp(a, "--bs") == 0)           { NEXTARG("--bs");    bs = parse_size(v); }
        else if (strcmp(a, "--bytes") == 0)        { NEXTARG("--bytes"); want_bytes = parse_size(v); }
        else if (strcmp(a, "--ops") == 0)          { NEXTARG("--ops");   want_ops = parse_size(v); }
        else if (strcmp(a, "--max-seconds") == 0)  { NEXTARG("--max-seconds"); max_seconds = parse_size(v); }
        else if (strcmp(a, "--span") == 0)         { NEXTARG("--span");  span = parse_size(v); }
        else if (strcmp(a, "--seed") == 0) {
            long sv;
            NEXTARG("--seed");
            sv = parse_size(v);
            if (sv < 0) { fprintf(stderr, "%s: --seed must be a number\n", g_prog); return 2; }
            seed = (unsigned long) sv;
        }
        else if (strcmp(a, "--sync") == 0)         want_sync = 1;
        else if (strcmp(a, "--allow-write") == 0)  allow_write = 1;
        else if (strcmp(a, "--plan") == 0)         do_plan = 1;
        else if (strcmp(a, "--info") == 0) {
            /* pagesize is reported because a RAW transfer goes through
             * physio(), which locks and DMAs whole pages of the user buffer --
             * so where the block size sits relative to the page is part of
             * reading this row's curve, not trivia. */
            printf("IOINFO version=%s hz=%ld osync=%d sizeof_long=%d pagesize=%ld\n",
                   BENCH_VERSION, bench_hz(), BENCH_HAVE_SYNC, (int) sizeof(long),
                   bench_pagesize());
            return 0;
        }
        else if (strcmp(a, "--version") == 0) {
            printf("iobench %s\n", BENCH_VERSION);
            return 0;
        }
        else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) { usage(); return 0; }
        else { fprintf(stderr, "%s: unknown argument '%s'\n", g_prog, a); usage(); return 2; }
#undef NEXTARG
    }

    if (!arith_ok()) {
        fprintf(stderr,
"%s: ARITHMETIC SELF-CHECK FAILED -- this binary's variable-divisor divide and\n"
"    modulo return wrong answers, so every random offset it computes would be\n"
"    garbage.  This is the GNU as 2.8.1 tdivs.l miscompile (fixed in the cross\n"
"    toolchain 2026-07-20).  Rebuild with a fixed toolchain; do not trust any\n"
"    number this binary would have printed.\n", g_prog);
        return 3;
    }

    if (bs < 0 || want_bytes < 0 || want_ops < 0 || max_seconds < 0 || span < 0) {
        fprintf(stderr, "%s: a size argument was not a number (suffix K/M allowed)\n", g_prog);
        return 2;
    }
    if (bs <= 0) { fprintf(stderr, "%s: --bs is required and must be > 0\n", g_prog); usage(); return 2; }
    if (bs > MAX_BS) { fprintf(stderr, "%s: --bs above %ld is refused\n", g_prog, MAX_BS); return 2; }
    if (!have_pattern || !have_dir) {
        if (!do_plan) { fprintf(stderr, "%s: --pattern and --dir are required\n", g_prog); usage(); return 2; }
    }

    /* ---- plan mode: no target is touched, so it is safe anywhere ---------- */
    if (do_plan) {
        unsigned long n;
        if (span <= 0 && path != 0) {
            fd = bench_open(path, 0, 0);
            if (fd < 0) { fprintf(stderr, "%s: cannot open %s for sizing\n", g_prog, path); return 1; }
            span = (long) bench_size(fd);
            bench_close(fd);
        }
        if (span <= 0) { fprintf(stderr, "%s: --plan needs --span (or a sizeable --path)\n", g_prog); return 2; }
        nblocks = (unsigned long)(span / bs);
        if (nblocks == 0UL) { fprintf(stderr, "%s: --span is smaller than --bs\n", g_prog); return 2; }
        n = (want_ops > 0) ? (unsigned long) want_ops : 16UL;
        lcg_seed(seed);
        printf("IOPLAN pattern=%s bs=%ld span=%ld nblocks=%lu ops=%lu seed=%lu\n",
               (pattern == PAT_RAND) ? "rand" : "seq", bs, span, nblocks, n, seed);
        for (ops = 0UL; ops < n; ops++) {
            unsigned long blk;
            if (pattern == PAT_RAND) blk = next_block(nblocks);
            else blk = ops % nblocks;
            printf("%lu %ld\n", ops, (long)(blk * (unsigned long) bs));
        }
        return 0;
    }

    /* ---- the three write gates ------------------------------------------- */
    if (dir == DIR_WRITE && !allow_write) {
        fprintf(stderr,
"%s: REFUSED -- --dir write DESTROYS the contents of %s.\n"
"    Add --allow-write only for a scratch file or a scratch disk you are\n"
"    willing to lose.  There is no default write target, on purpose.\n",
                g_prog, path ? path : "(no --path)");
        return 2;
    }
    if (path == 0) { fprintf(stderr, "%s: --path is required\n", g_prog); usage(); return 2; }
    if (want_sync && dir == DIR_WRITE && !BENCH_HAVE_SYNC) {
        fprintf(stderr,
"%s: REFUSED -- --sync was asked for but this build's libc has no O_SYNC, so\n"
"    the writes would be buffered and the numbers would be a lie.\n", g_prog);
        return 2;
    }

    hz = bench_hz();
    if (hz <= 0) hz = 60;

    fd = bench_open(path, (dir == DIR_WRITE) ? 1 : 0, want_sync);
    if (fd < 0) {
        fprintf(stderr, "%s: cannot open %s for %s (this program never creates files)\n",
                g_prog, path, (dir == DIR_WRITE) ? "writing" : "reading");
        return 1;
    }

    if (span <= 0) span = (long) bench_size(fd);
    if (span <= 0) {
        if (pattern == PAT_RAND) {
            fprintf(stderr,
"%s: cannot determine the extent of %s -- SVR4 raw devices have no size.\n"
"    Pass --span with the number of bytes you want addressed.\n", g_prog, path);
            bench_close(fd);
            return 2;
        }
        span = 0;                       /* sequential: just run until a cap */
    }
    if (span > 0) {
        nblocks = (unsigned long)(span / bs);
        if (nblocks == 0UL) {
            fprintf(stderr, "%s: the target extent (%ld) is smaller than --bs (%ld)\n",
                    g_prog, span, bs);
            bench_close(fd);
            return 2;
        }
    }

    /* Page-align the transfer buffer.  On SVR4 a raw-device read/write goes
     * through physio(), which LOCKS AND DMAs THE USER BUFFER ITSELF -- so the
     * buffer's alignment is the DMA target's alignment.  This family has
     * already paid for that lesson once on the kernel side (the cdfs
     * page-crossing DMA that zeroed innocent pages); aligning here costs one
     * page of address space and removes the variable entirely. */
    rawbuf = (char *) malloc((size_t)(bs + 4096L));
    if (rawbuf == 0) { fprintf(stderr, "%s: out of memory for a %ld-byte buffer\n", g_prog, bs); bench_close(fd); return 1; }
    buf = rawbuf + (4096 - (int)(((unsigned long) rawbuf) & 4095UL));
    for (i = 0; i < bs; i++) buf[i] = (char)((i + (long) seed) & 0xFF);

    if (want_ops <= 0 && want_bytes > 0) want_ops = want_bytes / bs;
    if (want_ops <= 0 && want_bytes <= 0 && max_seconds <= 0) {
        fprintf(stderr, "%s: give at least one of --bytes, --ops or --max-seconds\n", g_prog);
        free(rawbuf); bench_close(fd); return 2;
    }

    lcg_seed(seed);

    /* ==================== the measured window starts here ================== */
    t0 = bench_clock(&u0, &s0);
    for (;;) {
        long n;

        if (want_ops > 0 && (long) ops >= want_ops) { capped = "ops"; break; }
        if (want_bytes > 0 && (long) bytes >= want_bytes) { capped = "bytes"; break; }
        if (max_seconds > 0 && ops > 0UL && (ops % TIME_CHECK_OPS) == 0UL) {
            long now = bench_clock((long *) 0, (long *) 0);
            if ((now - t0) >= max_seconds * hz) { capped = "time"; break; }
        }

        if (pattern == PAT_RAND) {
            off = (BENCH_OFF_T)(next_block(nblocks) * (unsigned long) bs);
            if (bench_seek(fd, off) < 0) { errs++; break; }
        } else if (nblocks > 0UL) {
            /* Same formula --plan prints, so the plan predicts the real run.
             * A seek happens only on the wrap (and at the start): in between,
             * the file pointer advances by itself, which is what "sequential"
             * is supposed to measure. */
            unsigned long blk = ops % nblocks;
            off = (BENCH_OFF_T)(blk * (unsigned long) bs);
            if (blk == 0UL) {
                if (ops > 0UL) wraps++;
                if (bench_seek(fd, off) < 0) { errs++; break; }
            }
        } else {
            /* Extent unknown (a raw device): run forward until EOF or a cap. */
            if (ops == 0UL) {
                if (bench_seek(fd, (BENCH_OFF_T) 0) < 0) { errs++; break; }
                off = 0;
            } else {
                off += bs;
            }
        }

        if (dir == DIR_WRITE) n = bench_write(fd, buf, (unsigned long) bs);
        else                  n = bench_read(fd, buf, (unsigned long) bs);

        if (n < 0) { errs++; break; }
        if (n == 0) { capped = "eof"; break; }
        if (n != bs) shortio++;
        bytes += (unsigned long) n;
        ops++;
    }
    t1 = bench_clock(&u1, &s1);
    /* ===================== the measured window ends here =================== */

    ticks  = t1 - t0;
    uticks = u1 - u0;
    sticks = s1 - s0;
    if (ticks < 0) ticks = 0;

    secs = (double) ticks / (double) hz;
    if (ticks == 0) { warn = "zero-elapsed"; }
    else if (ticks < SHORT_RUN_TICKS) { warn = "short-run"; }
    if (errs) { warn = "io-error"; rc = 1; }

    /* ★ THE GUARDS ARE INTEGER ON PURPOSE.  DO NOT TIDY THEM BACK TO `secs > 0.0`.
     *
     * This is the 2026-08-17 metal defect.  The box printed
     *
     *   ... hz=60 ticks=712 real=11.867 user=0.267 sys=11.533
     *       kb_s=0.0 ops_s=0.0 us_per_op=0.0 ... capped=ops warn=ok
     *
     * -- every measured quantity right, every DERIVED one zero.  Cause: the
     * guard, not the arithmetic.  `secs > 0.0` compiles to a reg-reg `fcmp.x`,
     * whose SGS operand order GNU as 2.8.1 reads backwards (the cross wrapper
     * swaps cmp.b/w/l and nothing else), so the test evaluated `0.0 > secs` and
     * was false for every possible run.
     *
     * ticks and hz are longs and hz > 0, so `ticks > 0` is EXACTLY `secs > 0.0`
     * -- and it compiles to the integer compare the wrapper does fix.  Keep it
     * that way until gcc-cross-amix's fix_asm learns to swap fcmp too.
     */
    kb_s  = (ticks > 0) ? ((double) bytes / 1024.0) / secs : 0.0;
    ops_s = (ticks > 0) ? ((double) ops) / secs : 0.0;
    us_op = (ops > 0UL && ticks > 0) ? (secs * 1000000.0) / (double) ops : 0.0;

    printf("IOBENCH label=%s path=%s pattern=%s dir=%s bs=%ld ops=%lu bytes=%lu \
span=%ld seed=%lu sync=%d hz=%ld ticks=%ld real=%.3f user=%.3f sys=%.3f \
kb_s=%.1f ops_s=%.1f us_per_op=%.1f wraps=%lu short=%lu err=%lu capped=%s warn=%s\n",
           label, path,
           (pattern == PAT_RAND) ? "rand" : "seq",
           (dir == DIR_WRITE) ? "write" : "read",
           /* sync= reports what was APPLIED, not what was asked for: O_SYNC is
            * meaningless on a read, and a run labelled sync=1 that was in fact
            * buffered would be a lie in the results table. */
           bs, ops, bytes, span, seed, (want_sync && dir == DIR_WRITE) ? 1 : 0, hz, ticks,
           secs, (double) uticks / (double) hz, (double) sticks / (double) hz,
           kb_s, ops_s, us_op, wraps, shortio, errs, capped, warn);

    free(rawbuf);
    bench_close(fd);
    return rc;
}
