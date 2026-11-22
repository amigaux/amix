/*
 * netconfig.h -- Amix's <netconfig.h> with nc_sperror and nc_perror
 * declared (sys/netconfig.h declares the rest of libnsl's netconfig calls).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_NETCONFIG_H
#define AMIX_COMPAT_NETCONFIG_H
#include_next <netconfig.h>
#ifdef __cplusplus
extern "C" {
#endif
extern char *nc_sperror(void);
extern void nc_perror(const char *);
#ifdef __cplusplus
}
#endif
#endif
