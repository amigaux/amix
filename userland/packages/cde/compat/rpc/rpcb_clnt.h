/*
 * rpc/rpcb_clnt.h -- Amix's <rpc/rpcb_clnt.h> with prototypes (see rpc/xdr.h here).
 * The rpcbind calls.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_RPCB_CLNT_H
#define AMIX_COMPAT_RPC_RPCB_CLNT_H
#include <rpc/types.h>
struct netconfig;
struct netbuf;
#define rpcb_set	amix_kr_rpcb_set
#define rpcb_unset	amix_kr_rpcb_unset

#include_next <rpc/rpcb_clnt.h>

#undef rpcb_set
#undef rpcb_unset

#ifdef __cplusplus
extern "C" {
#endif
extern bool_t rpcb_set(u_long, u_long, struct netconfig *, struct netbuf *);
extern bool_t rpcb_unset(u_long, u_long, struct netconfig *);
#ifdef __cplusplus
}
#endif

#endif
