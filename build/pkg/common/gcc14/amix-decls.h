/*
 * amix-decls.h -- prototypes the AMIX headers never declare, for
 * TOOLCHAIN=gcc14 builds (recipes/common/gcc14-env.sh).
 *
 *     CFLAGS="$AMIX_CFLAGS -include $AMIX_GCC14_DECLS"
 *
 * GCC 14 (gnu17) makes an implicit function declaration an ERROR.  The AMIX
 * headers declare none of the BSD socket calls, select, the syslog family or
 * gethostname (sys/socket.h, sys/select.h and syslog.h define only types and
 * constants), so ordinary network code stops compiling.  The fix is a
 * prototype, never -Wno-error: an undeclared call that compiles is the
 * PORTING.md 3.1 trap.  Opt-in per recipe -- a source that declares one of
 * these itself, with a different spelling of the same type, would collide.
 *
 * Signatures are the SVR4.0 ABI (int lengths, not socklen_t/size_t; ILP32,
 * so the widths agree with POSIX anyway).  Where they come from at link time
 * (gcc14 evaluation sec 2): socket/connect/... libsocket.so, gethostname
 * libnsl.so -- link -lsocket -lnsl in that order; select and the syslog
 * family are static members of usr/ccs/lib/libc.so, which the specs already
 * reach.  MIT, this repository.
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

#ifdef __cplusplus
}
#endif

#endif /* AMIX_PACKAGES_GCC14_DECLS_H */
