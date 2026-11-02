/*
 * amix-compat.h -- what Dropbear expects of the platform and Amix (SVR4.0)
 * spells differently or lacks.  Included ahead of every Dropbear source
 * (-include); the definitions are in amix-compat.c.  MIT, this repository.
 */
#ifndef AMIX_DROPBEAR_COMPAT_H
#define AMIX_DROPBEAR_COMPAT_H

#include <sys/types.h>
#include <sys/time.h>
#include <stdarg.h>
#include <netinet/in.h>

/* SVR4's struct timestruc has the POSIX members, tv_sec and tv_nsec */
#define timespec timestruc
/* struct timeval's tv_usec is a long */
typedef long suseconds_t;

/* shutdown(2)'s how: SVR4 takes the BSD values and names none of them */
#define SHUT_RD 0
#define SHUT_WR 1
#define SHUT_RDWR 2

/* the most iovecs writev(2) takes in one call (SVR4.0: 16) */
#define IOV_MAX 16

/*
 * No O_NOFOLLOW.  Dropbear passes it only beside O_CREAT|O_EXCL, which
 * fails on any existing name, a symbolic link included (tests/smoke.sh).
 */
#define O_NOFOLLOW 0

/* read(2) as atomicio() takes it (patches/01-atomicio-read.patch) */
#define amix_read ((ssize_t (*)(int, void *, size_t))read)

int inet_aton(const char *, struct in_addr *);
int utimes(const char *, const struct timeval *);
int nanosleep(const struct timespec *, struct timespec *);
int vasprintf(char **, const char *, va_list);

/* the SVR4 pty calls (libc has them; no header declares them) */
int grantpt(int);
int unlockpt(int);
char *ptsname(int);

#endif
