/*
 * arpa/inet.h -- Amix's <arpa/inet.h> with prototypes (see rpc/xdr.h here).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_ARPA_INET_H
#define AMIX_COMPAT_ARPA_INET_H
#include <netinet/in.h>
#define inet_addr	amix_kr_inet_addr
#define inet_ntoa	amix_kr_inet_ntoa
#define inet_makeaddr	amix_kr_inet_makeaddr
#define inet_network	amix_kr_inet_network
#include_next <arpa/inet.h>
#undef inet_addr
#undef inet_ntoa
#undef inet_makeaddr
#undef inet_network
#ifdef __cplusplus
extern "C" {
#endif
extern unsigned long inet_addr(const char *);
extern char *inet_ntoa(struct in_addr);
extern struct in_addr inet_makeaddr(int, int);
extern unsigned long inet_network(const char *);
#ifdef __cplusplus
}
#endif
#endif
