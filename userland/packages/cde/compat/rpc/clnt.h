/*
 * rpc/clnt.h -- Amix's <rpc/clnt.h> with prototypes (see rpc/xdr.h here).
 * The client side.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_CLNT_H
#define AMIX_COMPAT_RPC_CLNT_H
struct netconfig;
struct netbuf;
#define clnt_create	amix_kr_clnt_create
#define clnt_tli_create	amix_kr_clnt_tli_create
#define clnt_pcreateerror	amix_kr_clnt_pcreateerror
#define clnt_spcreateerror	amix_kr_clnt_spcreateerror
#define clnt_perrno	amix_kr_clnt_perrno
#define clnt_perror	amix_kr_clnt_perror
#define clnt_sperror	amix_kr_clnt_sperror
#define clnt_sperrno	amix_kr_clnt_sperrno

#include_next <rpc/clnt.h>

#undef clnt_create
#undef clnt_tli_create
#undef clnt_pcreateerror
#undef clnt_spcreateerror
#undef clnt_perrno
#undef clnt_perror
#undef clnt_sperror
#undef clnt_sperrno

#ifdef __cplusplus
extern "C" {
#endif
extern CLIENT *clnt_create(const char *, u_long, u_long, const char *);
extern CLIENT *clnt_tli_create(int, struct netconfig *, struct netbuf *, u_long, u_long, u_int, u_int);
extern void clnt_pcreateerror(const char *);
extern char *clnt_spcreateerror(const char *);
extern void clnt_perrno(enum clnt_stat);
extern void clnt_perror(CLIENT *, const char *);
extern char *clnt_sperror(CLIENT *, const char *);
extern char *clnt_sperrno(enum clnt_stat);
#ifdef __cplusplus
}
#endif

#endif
