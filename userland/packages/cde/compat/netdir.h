/*
 * netdir.h -- Amix's <netdir.h> with prototypes (see rpc/xdr.h here).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_NETDIR_H
#define AMIX_COMPAT_NETDIR_H
#define netdir_sperror	amix_kr_netdir_sperror
#define netdir_options	amix_kr_netdir_options
#define netdir_getbyname amix_kr_netdir_getbyname
#define netdir_getbyaddr amix_kr_netdir_getbyaddr
#define netdir_mergeaddr amix_kr_netdir_mergeaddr
#define netdir_free	amix_kr_netdir_free
#define uaddr2taddr	amix_kr_uaddr2taddr
#define netdir_perror	amix_kr_netdir_perror
#define taddr2uaddr	amix_kr_taddr2uaddr
#include_next <netdir.h>
#undef netdir_sperror
#undef netdir_options
#undef netdir_getbyname
#undef netdir_getbyaddr
#undef netdir_mergeaddr
#undef netdir_free
#undef uaddr2taddr
#undef netdir_perror
#undef taddr2uaddr
#ifdef __cplusplus
extern "C" {
#endif
extern int netdir_getbyname(struct netconfig *, struct nd_hostserv *, struct nd_addrlist **);
extern int netdir_getbyaddr(struct netconfig *, struct nd_hostservlist **, struct netbuf *);
extern int netdir_options(struct netconfig *, int, int, char *);
extern int netdir_mergeaddr(struct netconfig *, char **, char *, char *);
extern void netdir_free(void *, int);
extern struct netbuf *uaddr2taddr(struct netconfig *, char *);
extern char *taddr2uaddr(struct netconfig *, struct netbuf *);
extern void netdir_perror(const char *);
extern char *netdir_sperror(void);
#ifdef __cplusplus
}
#endif
#endif
