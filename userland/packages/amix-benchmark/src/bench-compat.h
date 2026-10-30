/* bench-compat.h -- the entire OS-dependent surface of the amix-bench binaries,
 * in one header.
 *
 * WHY THIS FILE EXISTS.  The suite is meant to travel: it runs on our Z3660 box,
 * on other people's REAL A3000s under Amix, and (a stated future intent) on
 * AmigaOS.  Everything below the line "PORT ME" is System V Release 4; everything
 * above it is strict C89 and portable.  A port therefore has a bounded job -- the
 * clock, the file primitives and the two constants -- rather than a hunt through
 * four benchmark sources.
 *
 * ALWAYS REQUIRED:
 *
 *   bench_hz()                      ticks per second, > 0
 *   bench_clock(&user, &sys)        -> elapsed REAL ticks (any fixed origin);
 *                                      *user / *sys = this process's CPU ticks
 *   bench_pagesize()                VM page size in bytes, > 0
 *
 * REQUIRED ONLY FOR FILE I/O (iobench.c defines BENCH_WANT_FILE):
 *
 *   bench_open(path, wr, sync)      -> fd, or -1
 *   bench_close(fd)
 *   bench_read(fd, buf, n)          -> bytes, 0 = EOF, -1 = error
 *   bench_write(fd, buf, n)         -> bytes, -1 = error
 *   bench_seek(fd, off)             -> absolute offset, or -1  (SEEK_SET)
 *   bench_size(fd)                  -> extent in bytes, or 0 when unknowable
 *   BENCH_HAVE_SYNC                 1 if `sync` in bench_open() is honoured
 *   BENCH_OFF_T                     the seek-offset type
 *
 * REQUIRED ONLY FOR PROCESSES (vmbench.c defines BENCH_WANT_PROC):
 *
 *   BENCH_HAVE_FORK                 1 if fork/exec/pipe/wait exist
 *   bench_wait(&status)             -> reaped pid, or -1
 *
 * The two facility blocks are guarded rather than unconditional for a practical
 * reason as well as a documentary one: an unused static in a shared header is a
 * warning in every translation unit that does not need it, and a portability
 * header nobody can compile with -Werror stops being enforced.
 *
 * BENCH_HAVE_FORK 0 is a perfectly good answer: vmbench then prints
 * status=skipped for its fork and ctx rows and the harness records that.  The
 * fault row needs no processes and runs anywhere.  (AmigaOS is the target this
 * escape hatch exists for -- it has no fork.)
 *
 * The rest of the programs never call the OS.  In particular the RANDOM OFFSET
 * GENERATOR is deliberately implemented in portable 32-bit arithmetic (see
 * iobench.c) so that the SAME seed yields the SAME offsets on a 32-bit m68k and
 * on a 64-bit host -- which is what lets the host-side selftest prove the box's
 * access pattern without a box.
 *
 * C89, on purpose: no //-comments, no declarations after statements, no `long
 * long`, no variadic macros.  The cross compiler is gcc 2.7.2.3 and the field
 * target may be an even older vendor cc.
 */

#ifndef BENCH_COMPAT_H
#define BENCH_COMPAT_H

/* 1.1 (2026-08-28): fpbench's FP reference reduction shrank from 20,000 to 512
 * iterations, so `ref=` fingerprints from a 1.0 kit and a 1.1 kit are DIFFERENT
 * NUMBERS ABOUT THE SAME MACHINE and must never be compared.  The version is
 * bumped rather than left alone precisely so that comparison is detectable:
 * every results header echoes it, fpbench --info publishes ref_runs=, and the
 * fpu.dhry row prints both. */
#define BENCH_VERSION "1.1"

/* --------------------------------------------------------------- PORT ME ---
 * Everything from here to the end of the SVR4 block is the OS-dependent half.
 * ------------------------------------------------------------------------- */

#if defined(AMIGA) || defined(__amigaos__)
# error "AmigaOS port not written yet -- implement the bench_* primitives above."
#endif

/* ---- System V Release 4 (Amix 2.1, and any other SVR4 68030 UNIX) --------- */

#include <sys/types.h>
#include <sys/times.h>
#include <sys/param.h>
#include <fcntl.h>
#include <unistd.h>

typedef long BENCH_OFF_T;

/* O_SYNC is SVR4's "write does not return until the data is on the medium".
 * It is present in Amix 2.1's <sys/fcntl.h> (0x10).  A target that lacks it
 * gets BENCH_HAVE_SYNC 0 and iobench REFUSES --sync rather than silently
 * reporting buffered numbers as synchronous ones. */
#ifdef O_SYNC
# define BENCH_HAVE_SYNC 1
# define BENCH_O_SYNC    O_SYNC
#else
# define BENCH_HAVE_SYNC 0
# define BENCH_O_SYNC    0
#endif

/* HZ.  sysconf(_SC_CLK_TCK) is the runtime truth (Amix answers 60).  The
 * <sys/param.h> HZ and the final 60 are fallbacks for a libc without sysconf.
 * NOTE the asymmetry with dhry: Dhrystone's HZ is compiled IN (-DHZ=...), so
 * runbench.sh cross-checks the built-in value against this runtime one. */
static long bench_hz()
{
    long t = 0;
#ifdef _SC_CLK_TCK
    t = sysconf(_SC_CLK_TCK);
#endif
#ifdef HZ
    if (t <= 0) t = HZ;
#endif
    if (t <= 0) t = 60;
    return t;
}

/* times() on SVR4 RETURNS elapsed real time in ticks since an arbitrary origin
 * -- that return value, not tms_utime, is the wall clock an I/O benchmark
 * needs.  The CPU halves come back through the out-parameters so a caller can
 * separate "waiting for the disk" from "the kernel copying bytes". */
static long bench_clock(user, sys)
long *user;
long *sys;
{
    struct tms tb;
    clock_t r;

    r = times(&tb);
    if (user) *user = (long) tb.tms_utime;
    if (sys)  *sys  = (long) tb.tms_stime;
    return (long) r;
}

/* ---- OPTIONAL: file I/O.  Only iobench.c asks for this block -------------- */
#ifdef BENCH_WANT_FILE

static int bench_open(path, wr, sync)
char *path;
int wr;
int sync;
{
    int flags;

    if (wr) {
        flags = O_WRONLY;
        if (sync) flags |= BENCH_O_SYNC;
    } else {
        flags = O_RDONLY;
    }
    return open(path, flags);
}

static int bench_close(fd)
int fd;
{
    return close(fd);
}

static long bench_read(fd, buf, n)
int fd;
char *buf;
unsigned long n;
{
    return (long) read(fd, buf, (unsigned) n);
}

static long bench_write(fd, buf, n)
int fd;
char *buf;
unsigned long n;
{
    return (long) write(fd, buf, (unsigned) n);
}

static BENCH_OFF_T bench_seek(fd, off)
int fd;
BENCH_OFF_T off;
{
    return (BENCH_OFF_T) lseek(fd, (off_t) off, 0);   /* 0 = SEEK_SET */
}

/* Extent of the target, or 0 when it cannot be established.  A regular file
 * answers through lseek-to-end.  A RAW character device usually does not (SVR4
 * raw devices have no size), which is why iobench requires an explicit --span
 * for random patterns on such a target instead of guessing. */
static BENCH_OFF_T bench_size(fd)
int fd;
{
    BENCH_OFF_T here, end;

    here = (BENCH_OFF_T) lseek(fd, (off_t) 0, 1);      /* 1 = SEEK_CUR */
    if (here < 0) return 0;
    end = (BENCH_OFF_T) lseek(fd, (off_t) 0, 2);       /* 2 = SEEK_END */
    (void) lseek(fd, (off_t) here, 0);
    if (end < 0) return 0;
    return end;
}

#endif /* BENCH_WANT_FILE */

/* The VM page size.  membench reports it (a bandwidth curve is meaningless
 * without knowing where the page boundary is) and vmbench's fault row strides
 * by it.  sysconf is the SVR4 answer; the two fallbacks matter because Amix's
 * page size is a live question in this family (see docs/nbpp-4k-feasibility.md)
 * and a hard-coded 4096 would quietly turn a wrong page size into a wrong
 * fault rate rather than a visible one -- so the value is always PRINTED. */
static long bench_pagesize()
{
    long p = 0;
#ifdef _SC_PAGESIZE
    p = sysconf(_SC_PAGESIZE);
#endif
#ifdef _SC_PAGE_SIZE
    if (p <= 0) p = sysconf(_SC_PAGE_SIZE);
#endif
#ifdef NBPP
    if (p <= 0) p = NBPP;
#endif
    if (p <= 0) p = 4096;
    return p;
}

/* ---- OPTIONAL: processes.  Only vmbench.c asks for this block ------------- */
#ifdef BENCH_WANT_PROC

#include <sys/wait.h>

#define BENCH_HAVE_FORK 1

/* wait(2) with the status by pointer.  Wrapped for exactly one reason: the
 * AmigaOS port has no answer for it, so the whole dependency is one name that a
 * port can leave undefined together with BENCH_HAVE_FORK. */
static long bench_wait(status)
int *status;
{
    return (long) wait(status);
}

#endif /* BENCH_WANT_PROC */

#ifndef BENCH_HAVE_FORK
# define BENCH_HAVE_FORK 0
#endif

#endif /* BENCH_COMPAT_H */
