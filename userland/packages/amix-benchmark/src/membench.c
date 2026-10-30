/* membench.c -- the memory-bandwidth row: memcpy and memset swept across block
 * sizes, on one machine, with the same clock discipline as iobench.
 *
 * ---------------------------------------------------------------------------
 * WHY A SWEEP AND NOT ONE NUMBER
 *
 * The same reason the disk rows are sixteen cells and not one: the SHAPE is the
 * signal.  A 68030 with a 256-byte on-chip data cache, a Z3660 with its own
 * cache hierarchy and an emulated 030 with a host cache underneath all report
 * roughly the same figure for a 1 KB block -- and completely different figures
 * once the block stops fitting.  The curve across block sizes is where the
 * cache boundary, the bus width and the write-allocate policy show up; a single
 * "MB/s" hides all three.
 *
 * Two directions, because they are different machines' worth of behaviour:
 *   memcpy  -- one read stream plus one write stream, the bus at its busiest;
 *   memset  -- one write stream, no read traffic at all.
 * A part whose memset is much faster than its memcpy is telling you its reads
 * are the expensive half.
 *
 * ---------------------------------------------------------------------------
 * IT CHECKS ITS OWN COPY
 *
 * After the copy phase the destination is checksummed and compared with the
 * source's checksum, which is computed before the timed window.  This costs one
 * pass and buys something a benchmark badly needs: a memcpy that does not
 * actually move the bytes -- because the libc is broken, because the DMA engine
 * under an emulator lied, because the block size overflowed a length argument
 * somewhere -- reports a magnificent bandwidth otherwise.  The checksum is a
 * 32-bit integer rolling sum, so it costs nothing to verify and cannot be
 * confused with a floating-point tolerance.
 *
 * ---------------------------------------------------------------------------
 * BOUNDED, BECAUSE THIS SUITE RUNS ON OTHER PEOPLE'S MACHINES
 *
 * The working set is two buffers of the LARGEST swept size, and the largest
 * size is refused above MEM_MAX_BS (1 MB), so the row can never be the reason a
 * 16 MB box starts swapping.  Every phase is additionally bounded by a
 * wall-clock deadline shared across the whole sweep, so a very slow part
 * shortens the sweep instead of overrunning the row's cap.
 *
 * C89 with K&R definitions; all OS-dependent code is in bench-compat.h.  There
 * is not one floating-point comparison in this file -- see iobench.c for why.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bench-compat.h"

#define MEM_MAX_BS      (1024L * 1024L)
#define MEM_MAX_SIZES   16
#define MEM_ALIGN       4096L

static char *g_prog = "membench";

static void usage()
{
    fprintf(stderr,
"usage: membench [--sizes N,N,...] [--bytes-per-size N] [--max-seconds N]\n"
"                [--label ID] [--no-verify]\n"
"       membench --info | --version\n"
"\n");
    fprintf(stderr,
"  --sizes LIST        comma-separated block sizes in bytes (default\n"
"                      1024,4096,16384,65536,262144).  Each is refused above\n"
"                      1 MB: the working set is two buffers of the largest.\n"
"  --bytes-per-size N  bytes to move per size per direction (suffix K/M)\n");
    fprintf(stderr,
"  --max-seconds N     wall-clock cap for the WHOLE sweep, shared out across\n"
"                      the phases; a slow part gets a shorter sweep, never a\n"
"                      longer row\n"
"  --no-verify         skip the post-copy checksum (do not: see the header)\n"
"  --label ID          echoed back in the result lines\n");
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

/* A 32-bit rolling checksum.  Integer on purpose: the verification must not be
 * a floating-point tolerance, and it must be cheap enough that leaving it on by
 * default is not a measurement decision. */
static unsigned int checksum(p, n)
char *p;
long n;
{
    unsigned int s = 0U;
    long i;

    for (i = 0L; i < n; i++) {
        s = (s << 1) | ((s >> 31) & 1U);
        s = s + (unsigned int)((unsigned char) p[i]);
    }
    return s;
}

/* Bandwidth as a long, for ordering only: kilobytes per thousand ticks.  The
 * printed figure stays a double; this is the quantity the peak/floor selection
 * compares, so that selection is an integer comparison the cross toolchain
 * assembles the right way round.  The intermediate is bounded by
 * (bytes/1024) * 1000, which for this program's byte budgets is well inside a
 * 32-bit long. */
static long rate_int(moved, ticks, hz)
long moved;
long ticks;
long hz;
{
    if (ticks <= 0L) return 0L;
    (void) hz;
    return ((moved / 1024L) * 1000L) / ticks;
}

int main(argc, argv)
int argc;
char **argv;
{
    long sizes[MEM_MAX_SIZES];
    int  nsizes = 0;
    long bytes_per_size = 4L * 1024L * 1024L;
    long max_seconds = 0L;
    char *label = "-";
    int  verify = 1;
    int  i, k;

    char *rawa = 0, *rawb = 0, *A = 0, *B = 0;
    long maxbs = 0L;
    long hz, t0, tdead, tstart, tend, ticks;
    long total_bytes = 0L;
    double peak_cpy = 0.0, peak_set = 0.0, min_cpy = 0.0;
    long peak_cpy_bs = 0L, peak_set_bs = 0L, min_cpy_bs = 0L;
    long peak_cpy_i = 0L, peak_set_i = 0L, min_cpy_i = 0L;
    int  have_min = 0;
    int  bad = 0;
    int  unresolved = 0;
    char *capped = "sweep";
    long done_sizes = 0L;

    if (argc > 0 && argv[0]) g_prog = argv[0];

    for (i = 1; i < argc; i++) {
        char *a = argv[i];
        char *v;

#define NEXTARG(name) \
        v = (i + 1 < argc) ? argv[++i] : 0; \
        if (v == 0) { fprintf(stderr, "%s: %s needs a value\n", g_prog, name); return 2; }

        if (strcmp(a, "--label") == 0)            { NEXTARG("--label"); label = v; }
        else if (strcmp(a, "--bytes-per-size") == 0) { NEXTARG("--bytes-per-size"); bytes_per_size = parse_size(v); }
        else if (strcmp(a, "--max-seconds") == 0) { NEXTARG("--max-seconds"); max_seconds = parse_size(v); }
        else if (strcmp(a, "--no-verify") == 0)   verify = 0;
        else if (strcmp(a, "--sizes") == 0) {
            char *p;
            char buf[32];
            int  n;
            NEXTARG("--sizes");
            p = v;
            while (*p != '\0') {
                n = 0;
                while (*p != '\0' && *p != ',' && n < 31) buf[n++] = *p++;
                buf[n] = '\0';
                if (*p == ',') p++;
                if (nsizes >= MEM_MAX_SIZES) {
                    fprintf(stderr, "%s: at most %d sizes\n", g_prog, MEM_MAX_SIZES); return 2;
                }
                sizes[nsizes] = parse_size(buf);
                if (sizes[nsizes] <= 0L) {
                    fprintf(stderr, "%s: bad size '%s'\n", g_prog, buf); return 2;
                }
                nsizes++;
            }
        }
        else if (strcmp(a, "--info") == 0) {
            printf("MEMINFO version=%s hz=%ld pagesize=%ld max_bs=%ld sizeof_long=%d\n",
                   BENCH_VERSION, bench_hz(), bench_pagesize(), MEM_MAX_BS, (int) sizeof(long));
            return 0;
        }
        else if (strcmp(a, "--version") == 0) { printf("membench %s\n", BENCH_VERSION); return 0; }
        else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) { usage(); return 0; }
        else { fprintf(stderr, "%s: unknown argument '%s'\n", g_prog, a); usage(); return 2; }
#undef NEXTARG
    }

    if (nsizes == 0) {
        sizes[0] = 1024L; sizes[1] = 4096L; sizes[2] = 16384L;
        sizes[3] = 65536L; sizes[4] = 262144L;
        nsizes = 5;
    }
    if (bytes_per_size <= 0L) {
        fprintf(stderr, "%s: --bytes-per-size must be > 0\n", g_prog); return 2;
    }
    for (i = 0; i < nsizes; i++) {
        if (sizes[i] > MEM_MAX_BS) {
            fprintf(stderr,
"%s: REFUSED -- block size %ld is above the %ld-byte ceiling.  The working set\n"
"    is TWO buffers of the largest size and this suite runs on 16 MB machines\n"
"    that belong to other people.\n", g_prog, sizes[i], MEM_MAX_BS);
            return 2;
        }
        if (sizes[i] > maxbs) maxbs = sizes[i];
    }

    hz = bench_hz();
    if (hz <= 0L) hz = 60L;

    rawa = (char *) malloc((size_t)(maxbs + MEM_ALIGN));
    rawb = (char *) malloc((size_t)(maxbs + MEM_ALIGN));
    if (rawa == 0 || rawb == 0) {
        /* Not a failure of the machine's memory system, a statement about how
         * much of it is free.  The harness records it as a skip. */
        printf("MEMBENCH label=%s status=skipped reason=no-memory want=%ld\n",
               label, 2L * (maxbs + MEM_ALIGN));
        if (rawa) free(rawa);
        if (rawb) free(rawb);
        return 0;
    }
    /* Page-align both buffers.  Unaligned source and destination change the
     * answer on every 68k part (the copy loop degrades to bytes), and an
     * accident of malloc's bookkeeping is not a property worth measuring. */
    A = rawa + (MEM_ALIGN - (long)(((unsigned long) rawa) & (unsigned long)(MEM_ALIGN - 1L)));
    B = rawb + (MEM_ALIGN - (long)(((unsigned long) rawb) & (unsigned long)(MEM_ALIGN - 1L)));

    for (i = 0; i < maxbs; i++) A[i] = (char)((i * 7 + 13) & 0xFF);
    memset(B, 0, (size_t) maxbs);

    t0 = bench_clock((long *) 0, (long *) 0);
    tdead = (max_seconds > 0L) ? (t0 + max_seconds * hz) : 0L;

    printf("MEMBENCH label=%s status=start sizes=%d bytes_per_size=%ld max_seconds=%ld \
hz=%ld pagesize=%ld align=%ld\n",
           label, nsizes, bytes_per_size, max_seconds, hz, bench_pagesize(), MEM_ALIGN);

    for (k = 0; k < nsizes; k++) {
        long bs = sizes[k];
        long reps, r;
        long cpy_moved = 0L, set_moved = 0L;
        unsigned int cs_src, cs_dst;
        double cpy_kb = 0.0, set_kb = 0.0;
        long cpy_ticks = 0L, set_ticks = 0L;
        char *vfy = "-";

        if (tdead > 0L && bench_clock((long *) 0, (long *) 0) >= tdead) {
            capped = "time";
            break;
        }

        reps = bytes_per_size / bs;
        if (reps < 1L) reps = 1L;

        cs_src = verify ? checksum(A, bs) : 0U;
        memset(B, 0, (size_t) bs);

        /* ---- memcpy ------------------------------------------------------ */
        tstart = bench_clock((long *) 0, (long *) 0);
        for (r = 0L; r < reps; r++) {
            memcpy(B, A, (size_t) bs);
            if ((r & 15L) == 15L && tdead > 0L) {
                if (bench_clock((long *) 0, (long *) 0) >= tdead) { r++; break; }
            }
        }
        tend = bench_clock((long *) 0, (long *) 0);
        cpy_ticks = tend - tstart;
        if (cpy_ticks < 0L) cpy_ticks = 0L;
        cpy_moved = r * bs;
        total_bytes += cpy_moved;
        cpy_kb = (cpy_ticks > 0L)
               ? ((double) cpy_moved / 1024.0) / ((double) cpy_ticks / (double) hz)
               : 0.0;

        if (verify) {
            cs_dst = checksum(B, bs);
            if (cs_dst == cs_src) {
                vfy = "ok";
            } else {
                vfy = "MISMATCH";
                bad++;
            }
        }

        /* ---- memset ------------------------------------------------------ */
        tstart = bench_clock((long *) 0, (long *) 0);
        for (r = 0L; r < reps; r++) {
            memset(B, (int)(r & 0xFF), (size_t) bs);
            if ((r & 15L) == 15L && tdead > 0L) {
                if (bench_clock((long *) 0, (long *) 0) >= tdead) { r++; break; }
            }
        }
        tend = bench_clock((long *) 0, (long *) 0);
        set_ticks = tend - tstart;
        if (set_ticks < 0L) set_ticks = 0L;
        set_moved = r * bs;
        total_bytes += set_moved;
        set_kb = (set_ticks > 0L)
               ? ((double) set_moved / 1024.0) / ((double) set_ticks / (double) hz)
               : 0.0;

        printf("MEMSWEEP label=%s bs=%ld reps=%ld memcpy_bytes=%ld memcpy_ticks=%ld \
memcpy_kb_s=%.1f memset_bytes=%ld memset_ticks=%ld memset_kb_s=%.1f verify=%s\n",
               label, bs, reps, cpy_moved, cpy_ticks, cpy_kb,
               set_moved, set_ticks, set_kb, vfy);

        /* ★ THE PEAK IS PICKED ON INTEGERS, NOT ON THE PRINTED DOUBLES.
         * `if (cpy_kb > peak_cpy)` would put a register-to-register fcmp in
         * this binary, and on the cross toolchain that test answers BACKWARDS
         * -- so the row's "peak" would silently be its floor, and nothing about
         * the output would look wrong.  rate_int() is KB per thousand ticks in
         * a long, which orders the same way and cannot be reversed. */
        /* Same honesty as vmbench's fault row: a size that finished inside one
         * tick has a rate of 0.0, which reads like a stall rather than like
         * "too fast to time at HZ granularity".  It is counted and named. */
        if (cpy_ticks == 0L || set_ticks == 0L) unresolved++;

        if (cpy_ticks > 0L) {
            long ri = rate_int(cpy_moved, cpy_ticks, hz);
            if (peak_cpy_bs == 0L || ri > peak_cpy_i) {
                peak_cpy = cpy_kb; peak_cpy_bs = bs; peak_cpy_i = ri;
            }
            if (!have_min || ri < min_cpy_i) {
                min_cpy = cpy_kb; min_cpy_bs = bs; min_cpy_i = ri; have_min = 1;
            }
        }
        if (set_ticks > 0L) {
            long ri = rate_int(set_moved, set_ticks, hz);
            if (peak_set_bs == 0L || ri > peak_set_i) {
                peak_set = set_kb; peak_set_bs = bs; peak_set_i = ri;
            }
        }
        done_sizes++;
    }

    ticks = bench_clock((long *) 0, (long *) 0) - t0;
    if (ticks < 0L) ticks = 0L;

    printf("MEMBENCH label=%s status=%s sizes=%ld bytes=%ld hz=%ld ticks=%ld real=%.3f \
cpy_peak_kb_s=%.1f cpy_peak_bs=%ld cpy_min_kb_s=%.1f cpy_min_bs=%ld \
set_peak_kb_s=%.1f set_peak_bs=%ld verify_bad=%d unresolved_sizes=%d capped=%s warn=%s\n",
           label, (bad == 0) ? "ok" : "failed",
           done_sizes, total_bytes, hz, ticks, (double) ticks / (double) hz,
           peak_cpy, peak_cpy_bs, min_cpy, min_cpy_bs,
           peak_set, peak_set_bs, bad, unresolved,
           capped,
           (bad != 0) ? "copy-verify-failed"
                      : ((unresolved > 0) ? "some-sizes-under-one-tick"
                                          : ((ticks < 30L) ? "short-run" : "ok")));

    free(rawa);
    free(rawb);
    return (bad == 0) ? 0 : 1;
}
