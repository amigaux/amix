/*
 * sys/poll.h -- Amix's <sys/poll.h> with INFTIM, poll's "no timeout" (-1), which SVR4
 * predates.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_SYS_POLL_H
#define AMIX_COMPAT_SYS_POLL_H
#include_next <sys/poll.h>
#ifndef INFTIM
#define INFTIM	(-1)
#endif
#endif
