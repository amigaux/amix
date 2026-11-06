/* SPDX-License-Identifier: MIT
 * amix-net.c -- inet_pton and inet_ntop, which socketmodule.c needs and Amix's
 * libraries lack: IPv4 only, as this build is (--disable-ipv6).
 * MIT, see LICENSE.amix in the package. */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>

/* four decimal numbers of at most 255, nothing else: 1 good, 0 not an address */
int inet_pton(int af, const char *src, void *dst)
{
    unsigned char b[4];
    int i;

    if (af != AF_INET) {
        errno = EAFNOSUPPORT;
        return -1;
    }
    for (i = 0; i < 4; i++) {
        int n = 0, digits = 0;

        while (*src >= '0' && *src <= '9') {
            n = n * 10 + (*src++ - '0');
            if (n > 255 || ++digits > 3)
                return 0;
        }
        if (digits == 0 || *src != (i < 3 ? '.' : '\0'))
            return 0;
        b[i] = (unsigned char)n;
        src++;
    }
    memcpy(dst, b, 4);
    return 1;
}

const char *inet_ntop(int af, const void *src, char *dst, int size)
{
    const unsigned char *b = src;
    char t[16];

    if (af != AF_INET) {
        errno = EAFNOSUPPORT;
        return NULL;
    }
    sprintf(t, "%d.%d.%d.%d", b[0], b[1], b[2], b[3]);
    if ((int)strlen(t) >= size) {
        errno = ENOSPC;
        return NULL;
    }
    return strcpy(dst, t);
}
