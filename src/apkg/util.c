/*
 * util.c - small helpers for apkg: memory, strings, paths, messages.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * Everything here is strict C89 and avoids snprintf/strdup/strcasecmp,
 * none of which exist in the Amix (SVR4.0) libc.  Allocating string
 * builders (cat2/cat3) pre-compute lengths, so any sprintf call made
 * on their results elsewhere is bounded by construction.
 */

/*
 * _POSIX_SOURCE, and why it is HERE rather than in the Makefile.
 *
 * unblock_alarm() below needs sigset_t and sigprocmask(), and Amix's
 * <sys/signal.h> hides both behind
 *
 *     #if (__STDC__ - 0 == 0) || defined(_POSIX_SOURCE)
 *
 * -- i.e. behind a non-ANSI compile or this macro.  gcc is ANSI here, so
 * the macro is the only way in.  It is declared in this file, before any
 * header, because it must precede the first include to mean anything and
 * because it must NOT reach the rest of apkg: http.c and dns.c want the
 * decidedly non-POSIX socket and STREAMS declarations that _POSIX_SOURCE
 * takes away.  util.c itself is pure POSIX and compiles clean under it
 * on both toolchains (verified against the Amix sysroot and glibc), so
 * scoping it to this translation unit costs nothing.
 */
#ifndef _POSIX_SOURCE
#define _POSIX_SOURCE
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "apkg.h"

/*
 * Unblock SIGALRM after a longjmp out of its own handler.
 *
 * THE DEFECT THIS FIXES (found and reproduced host-side 2026-09-16, in a
 * 30-line program, while building the stub resolver).  A signal handler
 * runs with its own signal BLOCKED, and the block is lifted by the
 * normal RETURN from the handler -- which a longjmp never performs.
 * Whether the mask comes back is then up to which flavour of setjmp the
 * libc linked: sigsetjmp(env,1)/siglongjmp restore it, _setjmp/_longjmp
 * do not, and plain setjmp/longjmp are documented both ways on different
 * systems.  Measured here: after the FIRST timeout longjmp SIGALRM stays
 * blocked, so the next alarm() is armed and never delivered and the
 * following blocking call hangs FOREVER.
 *
 * That is not only the resolver's problem.  http.c has used
 * alarm()+longjmp for its inactivity timeout since it was written, and
 * its retry loop re-arms the same timer -- so with the shipped default
 * retries=2, the first stall timed out correctly and a SECOND stall hung
 * the client with no timeout at all.  The existing stall test never
 * caught it because it runs with retries=0, i.e. it only ever takes the
 * first timeout.  "The failure presents as the healthy state."
 *
 * The fix is to stop depending on the libc's flavour and say it outright.
 * sigsetjmp/siglongjmp were the other candidate, but the Amix libc
 * exports sigsetjmp and NOT siglongjmp; sigprocmask, sigemptyset and
 * sigaddset are all there, and are POSIX everywhere else.
 *
 * Call this on every path that longjmps out of a SIGALRM handler, right
 * beside the alarm(0).
 */
void unblock_alarm(void)
{
    sigset_t mask;

    sigemptyset(&mask);
    sigaddset(&mask, SIGALRM);
    sigprocmask(SIG_UNBLOCK, &mask, (sigset_t *)0);
}

char *xmalloc(unsigned n)
{
    char *p;

    if (n == 0)
        n = 1;
    p = (char *)malloc(n);
    if (p == NULL) {
        fprintf(stderr, "apkg: out of memory (%u bytes)\n", n);
        exit(EX_USAGE);
    }
    return p;
}

char *xrealloc(char *p, unsigned n)
{
    char *q;

    if (n == 0)
        n = 1;
    if (p == NULL)
        return xmalloc(n);
    q = (char *)realloc(p, n);
    if (q == NULL) {
        fprintf(stderr, "apkg: out of memory (%u bytes)\n", n);
        exit(EX_USAGE);
    }
    return q;
}

char *xstrdup(const char *s)
{
    char *p;

    p = xmalloc((unsigned)strlen(s) + 1);
    strcpy(p, s);
    return p;
}

/* allocating concat of two strings */
char *cat2(const char *a, const char *b)
{
    char *p;

    p = xmalloc((unsigned)(strlen(a) + strlen(b) + 1));
    strcpy(p, a);
    strcat(p, b);
    return p;
}

/* allocating concat of three strings */
char *cat3(const char *a, const char *b, const char *c)
{
    char *p;

    p = xmalloc((unsigned)(strlen(a) + strlen(b) + strlen(c) + 1));
    strcpy(p, a);
    strcat(p, b);
    strcat(p, c);
    return p;
}

/* case-insensitive string equality (Amix libc has no strcasecmp) */
int ci_streq(const char *a, const char *b)
{
    while (*a != '\0' && *b != '\0') {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b))
            return 0;
        a++;
        b++;
    }
    return *a == '\0' && *b == '\0';
}

/* case-insensitive substring search; returns 1 when found */
int ci_strfind(const char *hay, const char *needle)
{
    const char *h;
    const char *n;
    unsigned i;

    if (*needle == '\0')
        return 1;
    for (i = 0; hay[i] != '\0'; i++) {
        h = hay + i;
        n = needle;
        while (*h != '\0' && *n != '\0' &&
               tolower((unsigned char)*h) == tolower((unsigned char)*n)) {
            h++;
            n++;
        }
        if (*n == '\0')
            return 1;
    }
    return 0;
}

/* mkdir -p; returns 0 ok, -1 error */
int mkpath(const char *dir)
{
    char *copy;
    char *p;
    struct stat st;

    if (dir[0] == '\0')
        return 0;
    if (stat(dir, &st) == 0)
        return 0;
    copy = xstrdup(dir);
    p = copy + 1;
    for (;;) {
        while (*p != '\0' && *p != '/')
            p++;
        if (*p == '/') {
            *p = '\0';
            if (stat(copy, &st) != 0) {
                if (mkdir(copy, 0755) != 0 && errno != EEXIST) {
                    free(copy);
                    return -1;
                }
            }
            *p = '/';
            p++;
        } else {
            if (stat(copy, &st) != 0) {
                if (mkdir(copy, 0755) != 0 && errno != EEXIST) {
                    free(copy);
                    return -1;
                }
            }
            break;
        }
    }
    free(copy);
    return 0;
}

int file_exists(const char *path)
{
    struct stat st;

    return stat(path, &st) == 0;
}

long file_size(const char *path)
{
    struct stat st;

    if (stat(path, &st) != 0)
        return -1;
    return (long)st.st_size;
}

/* dirname without modifying input; always returns an allocated string */
char *dirname_of(const char *path)
{
    const char *slash;
    char *out;
    unsigned len;

    slash = strrchr(path, '/');
    if (slash == NULL)
        return xstrdup(".");
    if (slash == path)
        return xstrdup("/");
    len = (unsigned)(slash - path);
    out = xmalloc(len + 1);
    memcpy(out, path, len);
    out[len] = '\0';
    return out;
}

/* verbose-only note */
void note(const char *fmt, ...)
{
    va_list ap;

    if (!opt_verbose)
        return;
    va_start(ap, fmt);
    fprintf(stderr, "apkg: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

/* unconditional warning to stderr */
void warnx2(const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    fprintf(stderr, "apkg: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}
