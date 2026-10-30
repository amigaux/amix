/* vmbench.c -- the three kernel-path rows: process creation, context switching,
 * and page faulting.
 *
 * These are the rows that measure the KERNEL rather than the part.  A 68030 and
 * an emulated 68030 can report the same Dhrystone and the same disk curve and
 * still differ by an order of magnitude in fork() -- because fork is address
 * space work, and address space work is exactly where a PMMU emulator, a
 * different page size or a copy-on-write that is not really copy-on-write show
 * up.  A driver campaign that never measures them is guessing.
 *
 *   --test fork   fork+_exit and fork+exec cycles per second
 *   --test ctx    pipe ping-pong; two context switches per round trip
 *   --test fault  first-touch page-fault rate, and the resident re-touch rate
 *
 * ---------------------------------------------------------------------------
 * ★ WHY THE FAULT ROW REFUSES TO OVERCOMMIT
 *
 * The obvious way to measure paging is to allocate more than there is and watch
 * the pageout path.  This suite runs on OTHER PEOPLE'S MACHINES -- 16 MB
 * A3000s, possibly with a small swap partition, possibly with the owner's work
 * on them -- and on such a machine an overcommit row is not a measurement, it
 * is a wedge, and the owner cannot tell it apart from a kernel bug.  So:
 *
 *   * the working set is capped at VM_WS_MAX (16 MB) and a larger --ws is
 *     REFUSED, not clamped, so nobody gets a number they did not ask for;
 *   * the default is 4 MB, which fits in the smallest machine we target with
 *     room for the rest of the system;
 *   * malloc failing is a SKIP, not a failure and not a retry;
 *   * every phase is bounded by a wall-clock deadline, checked between pages,
 *     so a machine that starts swapping shortens the row instead of hanging;
 *   * nothing is ever locked into memory and no child is left behind.
 *
 * The row therefore measures the FAULT PATH -- zero-fill on first touch, and
 * the cost of a resident touch afterwards -- and deliberately does not measure
 * pageout.  A pageout row belongs on a machine whose owner is in the room.
 *
 * ---------------------------------------------------------------------------
 * DEGRADING GRACEFULLY
 *
 * fork/exec/pipe are POSIX, not portable to every target this suite is aimed at
 * (AmigaOS has no fork at all).  bench-compat.h answers BENCH_HAVE_FORK, and a
 * build without it still compiles: the rows print status=skipped with the
 * reason, and the harness records that rather than failing the run.
 *
 * C89 with K&R definitions.  There is not one floating-point comparison in this
 * file -- see iobench.c for the reason.
 */

#define BENCH_WANT_PROC 1

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bench-compat.h"

#define VM_WS_MAX      (16L * 1024L * 1024L)
#define VM_WS_DEFAULT  (4L * 1024L * 1024L)
#define VM_FORK_MAX    20000L
#define VM_CTX_MAX     200000L
#define VM_CHILD_RC    7

static char *g_prog = "vmbench";

static void usage()
{
    fprintf(stderr,
"usage: vmbench --test fork [--ops N] [--exec-target PATH] [--max-seconds N]\n"
"       vmbench --test ctx  [--ops N] [--max-seconds N]\n"
"       vmbench --test fault [--ws BYTES] [--max-seconds N]\n"
"       vmbench --exec-child | --info | --version\n"
"\n");
    fprintf(stderr,
"  --test fork        fork+_exit cycles, then fork+exec cycles.  --exec-target\n"
"                     is the program to exec; it should be THIS binary, which\n"
"                     answers --exec-child by exiting immediately with a known\n"
"                     status, so the parent can prove the exec really happened.\n");
    fprintf(stderr,
"  --test ctx         pipe ping-pong between a parent and one child.  Each\n"
"                     round trip is two context switches.\n"
"  --test fault       touch one byte per page of a fresh buffer (first-touch\n"
"                     faults), then touch it again (resident), then in a large\n"
"                     stride.  The working set is capped at 16 MB and a bigger\n"
"                     --ws is refused -- read the header before raising it.\n");
    fprintf(stderr,
"  --ops N            iterations (fork: %ld max, ctx: %ld max)\n"
"  --ws BYTES         fault working set, default 4M, ceiling 16M\n"
"  --max-seconds N    wall-clock cap for the row; a slow machine gets fewer\n"
"                     iterations, never a longer row\n"
"  --label ID         echoed back in the result line\n", VM_FORK_MAX, VM_CTX_MAX);
}

static long parse_size(s)
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
    if (*s == 'k' || *s == 'K') { v *= 1024L; s++; }
    else if (*s == 'm' || *s == 'M') { v *= 1024L * 1024L; s++; }
    if (*s != '\0') return -1L;
    if (v < 0L) return -1L;
    return v;
}

/* Rate as a double, guarded on INTEGERS.  `secs > 0.0` compiles to a
 * register-to-register fcmp whose operands GNU as 2.8.1 reads backwards. */
static double rate_of(count, ticks, hz)
long count;
long ticks;
long hz;
{
    if (ticks <= 0L || count <= 0L) return 0.0;
    return (double) count / ((double) ticks / (double) hz);
}

static double us_of(count, ticks, hz)
long count;
long ticks;
long hz;
{
    if (ticks <= 0L || count <= 0L) return 0.0;
    return (((double) ticks / (double) hz) * 1000000.0) / (double) count;
}

#if BENCH_HAVE_FORK

/* ------------------------------------------------------------ test: fork --- */

static int run_fork(ops, max_seconds, exec_target, label)
long ops;
long max_seconds;
char *exec_target;
char *label;
{
    long hz, t0, tdead, ts, te;
    long i, did_fork = 0L, did_exec = 0L, bad_status = 0L;
    long fork_ticks = 0L, exec_ticks = 0L;
    long exec_ops;
    char *warn = "ok";
    char *capped = "ops";
    int  st;
    long pid;

    hz = bench_hz();
    if (hz <= 0L) hz = 60L;
    t0 = bench_clock((long *) 0, (long *) 0);
    tdead = (max_seconds > 0L) ? (t0 + max_seconds * hz) : 0L;

    /* ---- phase 1: fork + _exit ------------------------------------------- */
    ts = bench_clock((long *) 0, (long *) 0);
    for (i = 0L; i < ops; i++) {
        pid = (long) fork();
        if (pid == 0L) {
            _exit(0);
        }
        if (pid < 0L) {
            /* Out of process slots or out of memory.  Stop; never spin retrying
             * -- on a small box that is how a benchmark becomes a fork bomb. */
            warn = "fork-failed";
            break;
        }
        (void) bench_wait(&st);
        did_fork++;
        if (tdead > 0L && (i & 7L) == 7L) {
            if (bench_clock((long *) 0, (long *) 0) >= tdead) { capped = "time"; break; }
        }
    }
    te = bench_clock((long *) 0, (long *) 0);
    fork_ticks = te - ts;
    if (fork_ticks < 0L) fork_ticks = 0L;

    /* ---- phase 2: fork + exec -------------------------------------------- */
    /* Quarter the count: an exec is much more expensive than a bare fork, and
     * the row's job is a rate, not a long run. */
    exec_ops = ops / 4L;
    if (exec_ops < 1L) exec_ops = 1L;
    if (exec_target == 0) {
        warn = (strcmp(warn, "ok") == 0) ? "no-exec-target" : warn;
        exec_ops = 0L;
    }
    if (strcmp(capped, "time") == 0) exec_ops = 0L;

    ts = bench_clock((long *) 0, (long *) 0);
    for (i = 0L; i < exec_ops; i++) {
        pid = (long) fork();
        if (pid == 0L) {
            char *av[3];
            av[0] = exec_target;
            av[1] = "--exec-child";
            av[2] = (char *) 0;
            (void) execv(exec_target, av);
            /* execv only returns on failure, and a child that falls through
             * here must NOT become a second copy of the benchmark. */
            _exit(126);
        }
        if (pid < 0L) { warn = "fork-failed"; break; }
        st = 0;
        (void) bench_wait(&st);
        /* The exit status is the proof that the exec really happened: a child
         * that never got as far as exec exits 126, and a fork that quietly did
         * not exec at all would exit 0. */
        if (((st >> 8) & 0xFF) != VM_CHILD_RC) bad_status++;
        did_exec++;
        if (tdead > 0L && (i & 3L) == 3L) {
            if (bench_clock((long *) 0, (long *) 0) >= tdead) { capped = "time"; break; }
        }
    }
    te = bench_clock((long *) 0, (long *) 0);
    exec_ticks = te - ts;
    if (exec_ticks < 0L) exec_ticks = 0L;

    if (bad_status > 0L) warn = "exec-status-wrong";

    printf("VMBENCH label=%s test=fork status=%s hz=%ld forks=%ld fork_ticks=%ld \
fork_per_sec=%.1f us_per_fork=%.1f execs=%ld exec_ticks=%ld forkexec_per_sec=%.1f \
us_per_forkexec=%.1f bad_status=%ld real=%.3f capped=%s warn=%s\n",
           label, (bad_status > 0L) ? "failed" : "ok", hz,
           did_fork, fork_ticks, rate_of(did_fork, fork_ticks, hz), us_of(did_fork, fork_ticks, hz),
           did_exec, exec_ticks, rate_of(did_exec, exec_ticks, hz), us_of(did_exec, exec_ticks, hz),
           bad_status,
           (double)(bench_clock((long *) 0, (long *) 0) - t0) / (double) hz,
           capped, warn);
    return (bad_status > 0L) ? 1 : 0;
}

/* ------------------------------------------------------------- test: ctx --- */

static int run_ctx(ops, max_seconds, label)
long ops;
long max_seconds;
char *label;
{
    int  up[2], down[2];
    long hz, t0, tdead, ts, te, ticks;
    long i, done = 0L;
    long pid;
    char tok;
    int  st;
    char *warn = "ok";
    char *capped = "ops";
    int  rc = 0;

    hz = bench_hz();
    if (hz <= 0L) hz = 60L;

    if (pipe(up) < 0) {
        printf("VMBENCH label=%s test=ctx status=failed reason=pipe-failed\n", label);
        return 1;
    }
    if (pipe(down) < 0) {
        (void) close(up[0]); (void) close(up[1]);
        printf("VMBENCH label=%s test=ctx status=failed reason=pipe-failed\n", label);
        return 1;
    }

    pid = (long) fork();
    if (pid < 0L) {
        (void) close(up[0]); (void) close(up[1]);
        (void) close(down[0]); (void) close(down[1]);
        printf("VMBENCH label=%s test=ctx status=skipped reason=fork-failed\n", label);
        return 0;
    }
    if (pid == 0L) {
        /* The echo child.  It exits when the parent closes its end, which is
         * how the parent's wall-clock cap terminates it -- there is no signal
         * and no timeout to get wrong. */
        (void) close(up[1]);
        (void) close(down[0]);
        for (;;) {
            if (read(up[0], &tok, 1) != 1) break;
            if (write(down[1], &tok, 1) != 1) break;
        }
        _exit(0);
    }

    (void) close(up[0]);
    (void) close(down[1]);

    t0 = bench_clock((long *) 0, (long *) 0);
    tdead = (max_seconds > 0L) ? (t0 + max_seconds * hz) : 0L;
    tok = 'x';

    ts = bench_clock((long *) 0, (long *) 0);
    for (i = 0L; i < ops; i++) {
        if (write(up[1], &tok, 1) != 1) { warn = "write-failed"; rc = 1; break; }
        if (read(down[0], &tok, 1) != 1) { warn = "read-failed"; rc = 1; break; }
        done++;
        if (tdead > 0L && (i & 63L) == 63L) {
            if (bench_clock((long *) 0, (long *) 0) >= tdead) { capped = "time"; break; }
        }
    }
    te = bench_clock((long *) 0, (long *) 0);
    ticks = te - ts;
    if (ticks < 0L) ticks = 0L;

    (void) close(up[1]);
    (void) close(down[0]);
    (void) bench_wait(&st);

    printf("VMBENCH label=%s test=ctx status=%s hz=%ld roundtrips=%ld ticks=%ld \
real=%.3f rt_per_sec=%.1f us_per_rt=%.1f switches_per_sec=%.1f capped=%s warn=%s\n",
           label, (rc == 0) ? "ok" : "failed", hz, done, ticks,
           (double) ticks / (double) hz,
           rate_of(done, ticks, hz), us_of(done, ticks, hz),
           rate_of(done * 2L, ticks, hz), capped, warn);
    return rc;
}

#endif /* BENCH_HAVE_FORK */

/* ----------------------------------------------------------- test: fault --- */

/* Touching ONE BYTE PER PAGE is the whole method: it is the smallest amount of
 * work that provokes the fault, so the number is the fault path's cost and not
 * a memory-bandwidth figure wearing its clothes.  membench measures bandwidth. */
static int run_fault(ws, max_seconds, label)
long ws;
long max_seconds;
char *label;
{
    char *buf;
    long hz, t0, tdead, ts, te;
    long pagesz, npages, i, idx, stride;
    long cold_pages = 0L, warm_pages = 0L, stride_pages = 0L;
    long cold_ticks = 0L, warm_ticks = 0L, stride_ticks = 0L;
    char *capped = "pages";
    char *warn = "ok";
    long sink = 0L;

    hz = bench_hz();
    if (hz <= 0L) hz = 60L;
    pagesz = bench_pagesize();
    if (pagesz <= 0L) pagesz = 4096L;

    if (ws > VM_WS_MAX) {
        fprintf(stderr,
"%s: REFUSED -- a %ld-byte working set is above the %ld-byte ceiling.\n"
"    This row runs on other people's 16 MB machines; an overcommitted working\n"
"    set there is a wedge, not a measurement.  Read the header in vmbench.c\n"
"    before raising the ceiling, and raise it in the source, deliberately.\n",
                g_prog, ws, VM_WS_MAX);
        return 2;
    }
    if (ws < pagesz * 8L) ws = pagesz * 8L;

    buf = (char *) malloc((size_t) ws);
    if (buf == 0) {
        printf("VMBENCH label=%s test=fault status=skipped reason=no-memory ws=%ld pagesize=%ld\n",
               label, ws, pagesz);
        return 0;
    }
    npages = ws / pagesz;

    t0 = bench_clock((long *) 0, (long *) 0);
    tdead = (max_seconds > 0L) ? (t0 + max_seconds * hz) : 0L;

    /* ---- phase 1: first touch (zero-fill faults) ------------------------- */
    ts = bench_clock((long *) 0, (long *) 0);
    for (i = 0L; i < npages; i++) {
        buf[i * pagesz] = (char)(i & 0x7F);
        cold_pages++;
        if (tdead > 0L && (i & 255L) == 255L) {
            if (bench_clock((long *) 0, (long *) 0) >= tdead) { capped = "time"; break; }
        }
    }
    te = bench_clock((long *) 0, (long *) 0);
    cold_ticks = te - ts;
    if (cold_ticks < 0L) cold_ticks = 0L;

    /* ---- phase 2: touch again (resident, no faults expected) ------------- */
    ts = bench_clock((long *) 0, (long *) 0);
    for (i = 0L; i < cold_pages; i++) {
        sink += (long) buf[i * pagesz];
        warm_pages++;
        if (tdead > 0L && (i & 255L) == 255L) {
            if (bench_clock((long *) 0, (long *) 0) >= tdead) { capped = "time"; break; }
        }
    }
    te = bench_clock((long *) 0, (long *) 0);
    warm_ticks = te - ts;
    if (warm_ticks < 0L) warm_ticks = 0L;

    /* ---- phase 3: large stride, to defeat any read-ahead ------------------ */
    /* A stride coprime with the page count visits every page exactly once in a
     * scattered order, which is what tells a translation-cache miss apart from
     * a sequential prefetch. */
    stride = 7L;
    if (cold_pages > 0L) {
        ts = bench_clock((long *) 0, (long *) 0);
        idx = 0L;
        for (i = 0L; i < cold_pages; i++) {
            sink += (long) buf[idx * pagesz];
            idx += stride;
            while (idx >= cold_pages) idx -= cold_pages;
            stride_pages++;
            if (tdead > 0L && (i & 255L) == 255L) {
                if (bench_clock((long *) 0, (long *) 0) >= tdead) { capped = "time"; break; }
            }
        }
        te = bench_clock((long *) 0, (long *) 0);
        stride_ticks = te - ts;
        if (stride_ticks < 0L) stride_ticks = 0L;
    }

    /* ★ A PHASE THAT FINISHED INSIDE ONE TICK REPORTS A RATE OF 0.0, AND THAT
     * READS LIKE A MACHINE THAT HAS STOPPED.  It is the opposite: the resident
     * re-touch is SUPPOSED to be far faster than the cold one, and on a
     * 2 MB-page Amix box 2048 resident touches really do finish under 1/60 s.
     * So the row says which phases it could not resolve rather than presenting
     * an unmeasured zero beside two measured numbers. */
    if (cold_ticks < 6L) warn = "short-run";
    else if (warm_ticks == 0L || stride_ticks == 0L) warn = "warm-and-stride-under-one-tick";

    printf("VMBENCH label=%s test=fault status=ok hz=%ld pagesize=%ld ws=%ld pages=%ld \
cold_pages=%ld cold_ticks=%ld cold_per_sec=%.1f us_per_fault=%.1f \
warm_pages=%ld warm_ticks=%ld warm_per_sec=%.1f \
stride_pages=%ld stride_ticks=%ld stride_per_sec=%.1f sink=%ld real=%.3f capped=%s warn=%s\n",
           label, hz, pagesz, ws, npages,
           cold_pages, cold_ticks, rate_of(cold_pages, cold_ticks, hz), us_of(cold_pages, cold_ticks, hz),
           warm_pages, warm_ticks, rate_of(warm_pages, warm_ticks, hz),
           stride_pages, stride_ticks, rate_of(stride_pages, stride_ticks, hz),
           sink,
           (double)(bench_clock((long *) 0, (long *) 0) - t0) / (double) hz,
           capped, warn);

    free(buf);
    return 0;
}

/* ------------------------------------------------------------------ main --- */

int main(argc, argv)
int argc;
char **argv;
{
    char *test = 0;
    char *label = "-";
    char *exec_target = 0;
    long ops = 0L;
    long ws = VM_WS_DEFAULT;
    long max_seconds = 0L;
    int i;

    if (argc > 0 && argv[0]) g_prog = argv[0];

    /* Checked FIRST and with no other work done: this process is the exec
     * target of the fork row and its whole job is to exit with a known status
     * as fast as an exec can get here. */
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--exec-child") == 0) _exit(VM_CHILD_RC);
    }

    for (i = 1; i < argc; i++) {
        char *a = argv[i];
        char *v;

#define NEXTARG(name) \
        v = (i + 1 < argc) ? argv[++i] : 0; \
        if (v == 0) { fprintf(stderr, "%s: %s needs a value\n", g_prog, name); return 2; }

        if (strcmp(a, "--test") == 0)             { NEXTARG("--test"); test = v; }
        else if (strcmp(a, "--label") == 0)       { NEXTARG("--label"); label = v; }
        else if (strcmp(a, "--exec-target") == 0) { NEXTARG("--exec-target"); exec_target = v; }
        else if (strcmp(a, "--ops") == 0)         { NEXTARG("--ops"); ops = parse_size(v); }
        else if (strcmp(a, "--ws") == 0)          { NEXTARG("--ws"); ws = parse_size(v); }
        else if (strcmp(a, "--max-seconds") == 0) { NEXTARG("--max-seconds"); max_seconds = parse_size(v); }
        else if (strcmp(a, "--info") == 0) {
            printf("VMINFO version=%s hz=%ld pagesize=%ld fork=%d ws_max=%ld ws_default=%ld\n",
                   BENCH_VERSION, bench_hz(), bench_pagesize(), BENCH_HAVE_FORK,
                   VM_WS_MAX, VM_WS_DEFAULT);
            return 0;
        }
        else if (strcmp(a, "--version") == 0) { printf("vmbench %s\n", BENCH_VERSION); return 0; }
        else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) { usage(); return 0; }
        else { fprintf(stderr, "%s: unknown argument '%s'\n", g_prog, a); usage(); return 2; }
#undef NEXTARG
    }

    if (ops < 0L || ws < 0L || max_seconds < 0L) {
        fprintf(stderr, "%s: a numeric argument was not a number\n", g_prog);
        return 2;
    }
    if (test == 0) { fprintf(stderr, "%s: --test is required\n", g_prog); usage(); return 2; }

    if (strcmp(test, "fault") == 0) {
        if (ws <= 0L) ws = VM_WS_DEFAULT;
        return run_fault(ws, max_seconds, label);
    }

#if BENCH_HAVE_FORK
    if (strcmp(test, "fork") == 0) {
        if (ops <= 0L) ops = 200L;
        if (ops > VM_FORK_MAX) {
            fprintf(stderr, "%s: --ops above %ld is refused for the fork row\n", g_prog, VM_FORK_MAX);
            return 2;
        }
        return run_fork(ops, max_seconds, exec_target, label);
    }
    if (strcmp(test, "ctx") == 0) {
        if (ops <= 0L) ops = 2000L;
        if (ops > VM_CTX_MAX) {
            fprintf(stderr, "%s: --ops above %ld is refused for the ctx row\n", g_prog, VM_CTX_MAX);
            return 2;
        }
        return run_ctx(ops, max_seconds, label);
    }
#else
    if (strcmp(test, "fork") == 0 || strcmp(test, "ctx") == 0) {
        printf("VMBENCH label=%s test=%s status=skipped reason=no-fork-on-this-target\n",
               label, test);
        return 0;
    }
#endif

    fprintf(stderr, "%s: --test must be fork, ctx or fault\n", g_prog);
    return 2;
}
