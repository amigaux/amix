/*
 * rpc/svc.h -- Amix's <rpc/svc.h> with prototypes (see rpc/xdr.h here).
 * The server side.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_SVC_H
#define AMIX_COMPAT_RPC_SVC_H
struct netconfig;
struct t_bind;
#define svc_reg	amix_kr_svc_reg
#define svc_unreg	amix_kr_svc_unreg
#define xprt_register	amix_kr_xprt_register
#define xprt_unregister	amix_kr_xprt_unregister
#define svc_sendreply	amix_kr_svc_sendreply
#define svcerr_decode	amix_kr_svcerr_decode
#define svcerr_weakauth	amix_kr_svcerr_weakauth
#define svcerr_noproc	amix_kr_svcerr_noproc
#define svcerr_progvers	amix_kr_svcerr_progvers
#define svcerr_auth	amix_kr_svcerr_auth
#define svcerr_noprog	amix_kr_svcerr_noprog
#define svcerr_systemerr	amix_kr_svcerr_systemerr
#define svc_getreq	amix_kr_svc_getreq
#define svc_getreqset	amix_kr_svc_getreqset
#define svc_run	amix_kr_svc_run
#define svc_tli_create	amix_kr_svc_tli_create
#define svc_fd_create	amix_kr_svc_fd_create

#include_next <rpc/svc.h>

#undef svc_reg
#undef svc_unreg
#undef xprt_register
#undef xprt_unregister
#undef svc_sendreply
#undef svcerr_decode
#undef svcerr_weakauth
#undef svcerr_noproc
#undef svcerr_progvers
#undef svcerr_auth
#undef svcerr_noprog
#undef svcerr_systemerr
#undef svc_getreq
#undef svc_getreqset
#undef svc_run
#undef svc_tli_create
#undef svc_fd_create

#ifdef __cplusplus
extern "C" {
#endif
extern bool_t svc_reg(SVCXPRT *, u_long, u_long, void (*)(struct svc_req *, SVCXPRT *), struct netconfig *);
extern void svc_unreg(u_long, u_long);
extern void xprt_register(SVCXPRT *);
extern void xprt_unregister(SVCXPRT *);
extern bool_t svc_sendreply(SVCXPRT *, xdrproc_t, caddr_t);
extern void svcerr_decode(SVCXPRT *);
extern void svcerr_weakauth(SVCXPRT *);
extern void svcerr_noproc(SVCXPRT *);
extern void svcerr_progvers(SVCXPRT *, u_long, u_long);
extern void svcerr_auth(SVCXPRT *, enum auth_stat);
extern void svcerr_noprog(SVCXPRT *);
extern void svcerr_systemerr(SVCXPRT *);
extern void svc_getreq(int);
extern void svc_getreqset(fd_set *);
extern void svc_run(void);
extern SVCXPRT *svc_tli_create(int, struct netconfig *, struct t_bind *, u_int, u_int);
extern SVCXPRT *svc_fd_create(int, u_int, u_int);
#ifdef __cplusplus
}
#endif

#endif
