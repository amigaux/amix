/*
 * sys/signal.h -- Amix's <sys/signal.h>, then <signal.h>: some CDE files
 * include only the former and call signal(), which Amix declares in the
 * latter (glibc's <sys/signal.h> is <signal.h>).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_SYS_SIGNAL_H
#define AMIX_COMPAT_SYS_SIGNAL_H
#include_next <sys/signal.h>
#include <signal.h>
#endif
