/*
 * sys/mman.h -- Amix's <sys/mman.h> with POSIX prototypes (see rpc/xdr.h
 * here): mmap is declared K&R, the others not at all.  madvise is not in Amix's
 * libc; this directory's lib/amix-compat.c gives it through memcntl's
 * MC_ADVISE, which is how SVR4 offers that call.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_SYS_MMAN_H
#define AMIX_COMPAT_SYS_MMAN_H
#include <sys/types.h>
#define mmap	amix_kr_mmap
#include_next <sys/mman.h>
#undef mmap
#ifndef MAP_FAILED
#define MAP_FAILED	((void *)-1)
#endif
#ifdef __cplusplus
extern "C" {
#endif
extern void *mmap(void *, size_t, int, int, int, off_t);
extern int munmap(void *, size_t);
extern int mprotect(void *, size_t, int);
extern int msync(void *, size_t, int);
extern int mlock(void *, size_t);
extern int munlock(void *, size_t);
extern int memcntl(caddr_t, size_t, int, caddr_t, int, int);
extern int madvise(void *, size_t, int);
#ifdef __cplusplus
}
#endif
#endif
