/*
 * sys/systeminfo.h -- Amix's <sys/systeminfo.h>, which needs SYS_NMLN from
 * <sys/utsname.h> without including it.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_SYS_SYSTEMINFO_H
#define AMIX_COMPAT_SYS_SYSTEMINFO_H
#include <sys/utsname.h>
#include_next <sys/systeminfo.h>
#endif
