/*
 * rpc/rpc.h -- Amix's <rpc/rpc.h>, with the socket-era RPC headers as
 * other systems' rpc.h includes them (portmapper calls, svc_register,
 * clnttcp_create and the like), and registerrpc, which libnsl has and no
 * Amix header declares.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_RPC_H
#define AMIX_COMPAT_RPC_RPC_H
#include_next <rpc/rpc.h>
#include <rpc/pmap_clnt.h>
#include <rpc/svc_soc.h>
#include <rpc/clnt_soc.h>
#ifdef __cplusplus
extern "C" {
#endif
extern int registerrpc(u_long, u_long, u_long, char *(*)(char *), xdrproc_t, xdrproc_t);
#ifdef __cplusplus
}
#endif
#endif
