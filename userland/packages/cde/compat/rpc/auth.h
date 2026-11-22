/*
 * rpc/auth.h -- Amix's <rpc/auth.h> with prototypes (see rpc/xdr.h here).
 * Authentication: none, sys and DES.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_AUTH_H
#define AMIX_COMPAT_RPC_AUTH_H
#include <netinet/in.h>
#define authdes_create	amix_kr_authdes_create
#define authdes_seccreate	amix_kr_authdes_seccreate
#define authsys_create_default	amix_kr_authsys_create_default
#define authnone_create	amix_kr_authnone_create

#include_next <rpc/auth.h>

#undef authdes_create
#undef authdes_seccreate
#undef authsys_create_default
#undef authnone_create

#ifdef __cplusplus
extern "C" {
#endif
extern AUTH *authdes_create(char *, u_int, struct sockaddr_in *, des_block *);
extern AUTH *authdes_seccreate(const char *, u_int, const char *, des_block *);
extern AUTH *authsys_create_default(void);
extern AUTH *authnone_create(void);
#ifdef __cplusplus
}
#endif

#endif
