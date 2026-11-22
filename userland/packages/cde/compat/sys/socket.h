/*
 * sys/socket.h -- Amix's <sys/socket.h> with socklen_t, which predates it
 * (Amix's socket calls take an int * length).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_SYS_SOCKET_H
#define AMIX_COMPAT_SYS_SOCKET_H
#include_next <sys/socket.h>
#ifndef AMIX_HAVE_SOCKLEN_T
#define AMIX_HAVE_SOCKLEN_T
typedef int socklen_t;
#endif
#endif
