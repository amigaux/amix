/*
 * rpc/auth_des.h -- Amix's <rpc/auth_des.h> with prototypes (see rpc/xdr.h here).
 * authdes_getucred, which Amix declares nowhere.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_AUTH_DES_H
#define AMIX_COMPAT_RPC_AUTH_DES_H
#include <rpc/types.h>

#include_next <rpc/auth_des.h>


#ifdef __cplusplus
extern "C" {
#endif
extern int authdes_getucred(struct authdes_cred *, uid_t *, gid_t *, short *, gid_t *);
#ifdef __cplusplus
}
#endif

#endif
