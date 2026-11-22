/*
 * netinet/in.h -- Amix's <netinet/in.h> with INADDR_NONE, which it lacks.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_NETINET_IN_H
#define AMIX_COMPAT_NETINET_IN_H
#include_next <netinet/in.h>
#ifndef INADDR_NONE
#define INADDR_NONE	0xffffffff	/* inet_addr's error return */
#endif
#endif
