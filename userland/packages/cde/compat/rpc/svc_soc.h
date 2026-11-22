/*
 * rpc/svc_soc.h -- Amix's <rpc/svc_soc.h> with prototypes (see rpc/xdr.h here).
 * The socket-era server calls.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_SVC_SOC_H
#define AMIX_COMPAT_RPC_SVC_SOC_H
#define svc_register	amix_kr_svc_register
#define svc_unregister	amix_kr_svc_unregister
#define svcudp_create	amix_kr_svcudp_create
#define svctcp_create	amix_kr_svctcp_create
#define svcfd_create	amix_kr_svcfd_create

#include_next <rpc/svc_soc.h>

#undef svc_register
#undef svc_unregister
#undef svcudp_create
#undef svctcp_create
#undef svcfd_create

#ifdef __cplusplus
extern "C" {
#endif
extern bool_t svc_register(SVCXPRT *, u_long, u_long, void (*)(struct svc_req *, SVCXPRT *), int);
extern void svc_unregister(u_long, u_long);
extern SVCXPRT *svcudp_create(int);
extern SVCXPRT *svctcp_create(int, u_int, u_int);
extern SVCXPRT *svcfd_create(int, u_int, u_int);
#ifdef __cplusplus
}
#endif

#endif
