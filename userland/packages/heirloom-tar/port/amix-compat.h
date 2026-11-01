/*
 * amix-compat.h -- what Heirloom tar expects of the platform and Amix
 * (SVR4.0) lacks.  Included ahead of every source (-include); the
 * functions are in amix-compat.c.  MIT, this repository.
 */
#ifndef AMIX_TAR_COMPAT_H
#define AMIX_TAR_COMPAT_H

#include <sys/types.h>
#include <stdio.h>

/* the largest read(2)/write(2) count: ssize_t is an int */
#ifndef SSIZE_MAX
#define SSIZE_MAX 2147483647
#endif

/* off_t is a long and there are no large files: fseeko is fseek */
#define fseeko(f, o, w) fseek((f), (long)(o), (w))

long long strtoll(const char *, char **, int);
long long atoll(const char *);
int mkstemp(char *);

#endif
