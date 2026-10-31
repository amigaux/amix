/* amix-uio.h -- readv/writev: in AMIX's libc.so.1, declared by no AMIX header.
 * Force-included by build.sh (MAKE_CFLAGS).  SVR4.0 signatures. */
struct iovec;
extern int readv(int, struct iovec *, int);
extern int writev(int, const struct iovec *, int);
