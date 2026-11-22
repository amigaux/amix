/*
 * rpc/pmap_clnt.h -- Amix's <rpc/pmap_clnt.h> with prototypes (see rpc/xdr.h here).
 * The portmapper calls.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_PMAP_CLNT_H
#define AMIX_COMPAT_RPC_PMAP_CLNT_H
#include <netinet/in.h>
#include <rpc/types.h>
#define pmap_set	amix_kr_pmap_set
#define pmap_unset	amix_kr_pmap_unset
#define pmap_getport	amix_kr_pmap_getport

#include_next <rpc/pmap_clnt.h>

#undef pmap_set
#undef pmap_unset
#undef pmap_getport

#ifdef __cplusplus
extern "C" {
#endif
extern bool_t pmap_set(u_long, u_long, int, u_short);
extern bool_t pmap_unset(u_long, u_long);
extern u_short pmap_getport(struct sockaddr_in *, u_long, u_long, u_int);
#ifdef __cplusplus
}
#endif

#endif
