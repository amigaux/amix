/*
 * amix-decls.h -- prototypes the AMIX headers never declare, for
 * TOOLCHAIN=gcc14 builds (build/pkg/common/gcc14-env.sh).
 *
 *     CFLAGS="$AMIX_CFLAGS -include $AMIX_GCC14_DECLS"
 *
 * GCC 14 (gnu17) makes an implicit function declaration an ERROR.  The AMIX
 * headers declare none of the BSD socket calls, select, the syslog family or
 * gethostname (sys/socket.h, sys/select.h and syslog.h define only types and
 * constants), nor fchmod (unistd.h declares fchown, sys/stat.h no fchmod),
 * nor getrlimit/setrlimit (sys/resource.h has struct rlimit, no prototypes),
 * nor seteuid/setegid (unistd.h declares only setuid/setgid), nor socketpair,
 * the netdb set/end*ent calls, munmap or isnan, so ordinary network and file code stops compiling.  The fix is a
 * prototype, never -Wno-error: an undeclared call that compiles is the
 * PORTING.md 3.1 trap.  Opt-in per recipe -- a source that declares one of
 * these itself, with a different spelling of the same type, would collide.
 *
 * Signatures are the SVR4.0 ABI (int lengths, not socklen_t/size_t; ILP32,
 * so the widths agree with POSIX anyway).  Where they come from at link time
 * (gcc14 evaluation sec 2): socket/connect/... libsocket.so, gethostname
 * libnsl.so -- link -lsocket -lnsl in that order; select and the syslog
 * family are static members of usr/ccs/lib/libc.so, which the specs already
 * reach; fchmod and getrlimit/setrlimit are exported by libc.so.1
 * (SYS_fchmod 93; bzip2 1.0.8 and coreutils 5.2.1 sort, 2026-10-29);
 * seteuid/setegid are the static member seteguid.o of usr/ccs/lib/libc.so
 * (trap #0, SYS 141/136; rsync 3.1.3's daemon, 2026-10-30); socketpair and
 * set/end*ent are libsocket's, munmap and isnan libc.so.1's (perl 5.8.9);
 * readv/writev are libc.so.1's (weak, over _readv/_writev; GNU Pth 2.0.7);
 * cbrt and copysign are libm.a's (cbrt, and copysign weak over _copysign;
 * FFmpeg 4.4.8), and gcc14 expands copysign inline anyway.  isinf is in no
 * AMIX library: it is gcc's builtin, as a macro, which C99 makes it, so a
 * float or long double argument is classified as itself (FFmpeg, vim).
 * MIT, this repository.
 */
#ifndef AMIX_PACKAGES_GCC14_DECLS_H
#define AMIX_PACKAGES_GCC14_DECLS_H

#include <sys/types.h>
#include <sys/select.h>

#ifdef __cplusplus
extern "C" {
#endif

struct sockaddr;
struct timeval;
struct rlimit;
struct iovec;

int socket(int, int, int);
int connect(int, const struct sockaddr *, int);
int bind(int, const struct sockaddr *, int);
int listen(int, int);
int accept(int, struct sockaddr *, int *);
int getsockname(int, struct sockaddr *, int *);
int getpeername(int, struct sockaddr *, int *);
int getsockopt(int, int, int, void *, int *);
int setsockopt(int, int, int, const void *, int);
int send(int, const void *, int, int);
int recv(int, void *, int, int);
int sendto(int, const void *, int, int, const struct sockaddr *, int);
int recvfrom(int, void *, int, int, struct sockaddr *, int *);
int shutdown(int, int);

int select(int, fd_set *, fd_set *, fd_set *, struct timeval *);

void openlog(const char *, int, int);
void syslog(int, const char *, ...);
void closelog(void);
int setlogmask(int);

int gethostname(char *, int);

int fchmod(int, mode_t);

int getrlimit(int, struct rlimit *);
int setrlimit(int, const struct rlimit *);

int seteuid(uid_t);
int setegid(gid_t);

int socketpair(int, int, int, int *);
void sethostent(int);
void endhostent(void);
void setnetent(int);
void endnetent(void);
void setprotoent(int);
void endprotoent(void);
void setservent(int);
void endservent(void);

int munmap(void *, size_t);
int isnan(double);

int readv(int, const struct iovec *, int);
int writev(int, const struct iovec *, int);

double cbrt(double);
double copysign(double, double);
#ifndef isinf
#define isinf(x) __builtin_isinf(x)
#endif
long _sysconf(int);	/* <limits.h>'s CLK_TCK is _sysconf(3) */

#ifdef __cplusplus
}
#endif

#endif /* AMIX_PACKAGES_GCC14_DECLS_H */
