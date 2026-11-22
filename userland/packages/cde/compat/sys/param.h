/*
 * sys/param.h -- Amix's <sys/param.h> with MAXHOSTNAMELEN, which it lacks
 * (<netdb.h> has it, 64).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_SYS_PARAM_H
#define AMIX_COMPAT_SYS_PARAM_H
#include_next <sys/param.h>
#ifndef MAXHOSTNAMELEN
#define MAXHOSTNAMELEN	64	/* as Amix's <netdb.h> */
#endif
#endif
