/*
 * unistd.h -- Amix's <unistd.h> and getdomainname, which SVR4 lacks
 * (defined in this directory's lib/amix-compat.c with sysinfo); and
 * <crypt.h>, where Amix declares crypt, setkey and encrypt, which X/Open
 * puts in <unistd.h>.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_UNISTD_H
#define AMIX_COMPAT_UNISTD_H
#include_next <unistd.h>
#include <crypt.h>
#ifdef __cplusplus
extern "C" {
#endif
extern int getdomainname(char *, int);
#ifdef __cplusplus
}
#endif
#endif
