/*
 * netdb.h -- Amix's <netdb.h> with prototypes (see rpc/xdr.h here), and
 * libsocket's rresvport and rcmd, which no Amix header declares (glibc
 * declares them here).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_NETDB_H
#define AMIX_COMPAT_NETDB_H
#define gethostbyname	amix_kr_gethostbyname
#define gethostbyaddr	amix_kr_gethostbyaddr
#define gethostent	amix_kr_gethostent
#define getnetbyname	amix_kr_getnetbyname
#define getnetbyaddr	amix_kr_getnetbyaddr
#define getnetent	amix_kr_getnetent
#define getservbyname	amix_kr_getservbyname
#define getservbyport	amix_kr_getservbyport
#define getservent	amix_kr_getservent
#define getprotobyname	amix_kr_getprotobyname
#define getprotobynumber amix_kr_getprotobynumber
#define getprotoent	amix_kr_getprotoent
#include_next <netdb.h>
#undef gethostbyname
#undef gethostbyaddr
#undef gethostent
#undef getnetbyname
#undef getnetbyaddr
#undef getnetent
#undef getservbyname
#undef getservbyport
#undef getservent
#undef getprotobyname
#undef getprotobynumber
#undef getprotoent
#ifdef __cplusplus
extern "C" {
#endif
extern struct hostent *gethostbyname(const char *);
extern struct hostent *gethostbyaddr(const char *, int, int);
extern struct hostent *gethostent(void);
extern struct netent *getnetbyname(const char *);
extern struct netent *getnetbyaddr(long, int);
extern struct netent *getnetent(void);
extern struct servent *getservbyname(const char *, const char *);
extern struct servent *getservbyport(int, const char *);
extern struct servent *getservent(void);
extern struct protoent *getprotobyname(const char *);
extern struct protoent *getprotobynumber(int);
extern struct protoent *getprotoent(void);
extern int rresvport(int *);
extern int rcmd(char **, unsigned short, const char *, const char *,
    const char *, int *);
#ifdef __cplusplus
}
#endif
#endif
