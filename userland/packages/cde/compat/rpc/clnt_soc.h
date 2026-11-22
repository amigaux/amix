/*
 * rpc/clnt_soc.h -- Amix's <rpc/clnt_soc.h> with prototypes (see rpc/xdr.h here).
 * The socket-era client calls.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_CLNT_SOC_H
#define AMIX_COMPAT_RPC_CLNT_SOC_H
#include <netinet/in.h>
#define callrpc	amix_kr_callrpc
#define clnttcp_create	amix_kr_clnttcp_create
#define clntudp_create	amix_kr_clntudp_create

#include_next <rpc/clnt_soc.h>

#undef callrpc
#undef clnttcp_create
#undef clntudp_create

#ifdef __cplusplus
extern "C" {
#endif
extern int callrpc(const char *, u_long, u_long, u_long, xdrproc_t, char *, xdrproc_t, char *);
extern CLIENT *clnttcp_create(struct sockaddr_in *, u_long, u_long, int *, u_int, u_int);
extern CLIENT *clntudp_create(struct sockaddr_in *, u_long, u_long, struct timeval, int *);
#ifdef __cplusplus
}
#endif

#endif
