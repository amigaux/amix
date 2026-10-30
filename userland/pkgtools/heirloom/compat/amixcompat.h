/*
 * amixcompat.h - C89/SVR4.0 compatibility shim for the Amix (Amiga Unix)
 * cross build of heirloom-pkgtools.  Force-included into every compile
 * via "-include amixcompat.h" (see mk.config.amix); NOT used by the
 * Linux host build.
 *
 * Copyright (c) 2026 Jussi Alanärä
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
 */

#ifndef AMIXCOMPAT_H
#define AMIXCOMPAT_H

#include <stddef.h>	/* size_t */
#include <stdarg.h>	/* va_list */

/*
 * ------------------------------------------------------------------
 * Configuration for the vendored C99-snprintf (compat/snprintf.c,
 * Patrick Powell / Holger Weiss lineage).  These HAVE_* macros are
 * consumed by compat/snprintf.c; they are harmless elsewhere.
 * SVR4.0 has neither snprintf nor vsnprintf in libc.
 * ------------------------------------------------------------------
 */
#define HAVE_SNPRINTF 0
#define HAVE_VSNPRINTF 0
#define HAVE_ASPRINTF 1		/* not needed; skip building rpl_asprintf */
#define HAVE_VASPRINTF 1	/* not needed; skip building rpl_vasprintf */
#define HAVE_STDARG_H 1
#define HAVE_STDDEF_H 1
#define HAVE_STDINT_H 0
#define HAVE_STDLIB_H 1
#define HAVE_FLOAT_H 1
#define HAVE_INTTYPES_H 0
#define HAVE_LOCALE_H 0
#define HAVE_LOCALECONV 0
#define HAVE_LCONV_DECIMAL_POINT 0
#define HAVE_LCONV_THOUSANDS_SEP 0
#define HAVE_LONG_DOUBLE 0	/* keep FP paths in plain double on m68k */
#define HAVE_LONG_LONG_INT 1	/* gcc 2.7.2.3 supports long long */
#define HAVE_UNSIGNED_LONG_LONG_INT 1
#define HAVE_INTMAX_T 0
#define HAVE_UINTMAX_T 0
#define HAVE_UINTPTR_T 0
#define HAVE_PTRDIFF_T 1
#define HAVE_VA_COPY 0
#define HAVE___VA_COPY 0

extern int rpl_snprintf(char *, size_t, const char *, ...);
extern int rpl_vsnprintf(char *, size_t, const char *, va_list);

#define snprintf rpl_snprintf
#define vsnprintf rpl_vsnprintf

/*
 * ------------------------------------------------------------------
 * LFS64 -> plain mapping.  SVR4.0 has no large-file API at all
 * (verified: no *64 symbols/types anywhere in the sysroot headers),
 * and Amix filesystems cannot exceed 2 GB anyway.
 * ------------------------------------------------------------------
 */
#define stat64		stat
#define fstat64		fstat
#define lstat64		lstat
#define statvfs64	statvfs
#define fstatvfs64	fstatvfs
#define readdir64	readdir
#define dirent64	dirent
#define fsblkcnt64_t	fsblkcnt_t
#define fsfilcnt64_t	fsfilcnt_t

#ifndef O_LARGEFILE
#define O_LARGEFILE	0
#endif

/*
 * ------------------------------------------------------------------
 * Types missing from the SVR4.0 headers (verified: no ssize_t or
 * blkcnt_t anywhere in the sysroot).  m68k is ILP32.
 * ------------------------------------------------------------------
 */
#ifndef AMIX_HAVE_SSIZE_T
#define AMIX_HAVE_SSIZE_T
typedef long ssize_t;
typedef long blkcnt_t;
typedef unsigned long fsblkcnt_t;
typedef unsigned long fsfilcnt_t;
#endif

/*
 * ------------------------------------------------------------------
 * <limits.h> values the SVR4.0 header hides behind
 * "#if __STDC__ - 0 == 0 || defined(_POSIX_SOURCE) || ..." (gcc
 * defines __STDC__=1, and defining _POSIX_SOURCE would restrict
 * other headers).  Values match the sysroot limits.h.
 * ------------------------------------------------------------------
 */
#ifndef PATH_MAX
#define PATH_MAX	1024
#endif
#ifndef MAX_INPUT
#define MAX_INPUT	512
#endif
#ifndef MAX_CANON
#define MAX_CANON	256
#endif
#ifndef NGROUPS_MAX
#define NGROUPS_MAX	16
#endif
#ifndef ARG_MAX
#define ARG_MAX		5120
#endif
#ifndef NAME_MAX
#define NAME_MAX	255
#endif
#ifndef LINE_MAX
#define LINE_MAX	2048
#endif

/*
 * ------------------------------------------------------------------
 * Functions missing from the SVR4.0 libc (verified against the
 * sysroot libc.so.1/libc.a with nm).  Implemented in compat/amixcompat.c.
 * ------------------------------------------------------------------
 */
extern char *strdup(const char *);	/* in libc; declared by string.h
					   only when __STDC__ == 0 */
extern int strcasecmp(const char *, const char *);
extern int strncasecmp(const char *, const char *, size_t);
extern int mkstemp(char *);
extern int isblank(int);	/* used by compat/charclass.h (fnmatch) */

/*
 * MAP_FAILED postdates SVR4.0's <sys/mman.h> (mmap itself is in libc).
 */
#ifndef MAP_FAILED
#define MAP_FAILED	((void *)-1)
#endif

/*
 * Signal constants <sys/signal.h> hides behind "__STDC__ == 0 &&
 * !defined(_POSIX_SOURCE)" (values match the sysroot header).
 */
#ifndef SA_RESTART
#define SA_RESTART	0x00000004
#endif
#ifndef NSIG
#define NSIG	32
#endif

/*
 * SVR4 signal-family declarations that <signal.h> only emits when
 * __STDC__ == 0 (the functions themselves are in libc - verified).
 */
extern void (*sigset(int, void (*)(int)))(int);
extern int sighold(int);
extern int sigrelse(int);
extern int sigignore(int);
extern int sigpause(int);

/*
 * environ: the Amix libc.so.1 exports only _environ (no plain
 * "environ" alias); putenv() maintains _environ, so mapping the name
 * keeps everything consistent.
 */
#define environ _environ

/*
 * vfork: not in SVR4.0 libc.  Every use in this tree is the classic
 * vfork-then-exec pattern, for which fork() is a drop-in.
 */
#define vfork fork

/*
 * BSD memory ops (bzero/bcopy/bcmp) -> C89 equivalents.
 */
extern void *memset(void *, int, size_t);
extern void *memmove(void *, const void *, size_t);
extern int memcmp(const void *, const void *, size_t);
#define bzero(b, len)		((void)memset((b), 0, (len)))
#define bcopy(src, dst, len)	((void)memmove((dst), (src), (len)))
#define bcmp(a, b, len)		memcmp((a), (b), (len))

/*
 * More functions missing from the SVR4.0 libc (all verified with nm);
 * implemented in compat/amixcompat.c.
 */
extern char *realpath(const char *, char *);
extern ssize_t pwrite(int, const void *, size_t, long);
extern int ftruncate(int, long);
extern int madvise(void *, size_t, int);
extern void *memalign(size_t, size_t);
extern int getpagesize(void);
extern long long atoll(const char *);
extern char *basename(char *);
extern char *strtok_r(char *, const char *, char **);
extern unsigned long long strtoull(const char *, char **, int);
extern int gethostname(char *, int);
extern void amix_raise_rlimits(void);	/* best-effort soft->hard */
struct tm;
extern struct tm *localtime_r();	/* old-style: struct tm is
					   incomplete until <time.h> */

/*
 * getopt globals: Solaris declares these in <stdlib.h> and the tree
 * relies on that; on Amix they may be hidden behind feature guards or
 * the file may not include <stdlib.h> at all.  (The implementation
 * linked is libadm/getopt.o.)
 */
extern char *optarg;
extern int optind, opterr, optopt;
extern int getopt(int, char *const *, const char *);

/*
 * dirfd(): SVR4.0 <dirent.h> exposes the descriptor as dd_fd.
 */
#define dirfd(d)	((d)->dd_fd)

#endif /* AMIXCOMPAT_H */
