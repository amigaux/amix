/*
 * amix-rpcgen.h -- what rpcgen's output needs from the AMIX headers, for
 * TOOLCHAIN=gcc14 builds of the files the build container's rpcgen writes
 * (toolchain/rpcgen.distfile, rpcsvc-proto).
 *
 *     $CC $AMIX_CFLAGS -Wno-unused-variable \
 *         -include "$AMIX_GCC14_DECLS" -include "$AMIX_GCC14_RPCGEN" -c foo_xdr.c
 *
 * MIT licence, see LICENSE at the top of the repository.
 *
 * rpcgen writes for glibc and libtirpc.  Against the AMIX headers, with GCC
 * 14's implicit-declaration error, its output needs:
 *   - int32_t, for the XDR routines' inline buffer (`int32_t *buf'): from
 *     stdint.h, where it is `long', the type rpc/xdr.h's XDR_INLINE returns;
 *   - the socket-style calls of the default (-b) server and client:
 *     svcudp_create, svctcp_create, svc_register, clntudp_create, ...: AMIX
 *     declares them in rpc/svc_soc.h and rpc/clnt_soc.h, which rpc/rpc.h
 *     does not include;
 *   - for a -5 (TI-RPC, SVR4) server: FMNAMESZ (sys/conf.h), I_LOOK, I_POP
 *     and I_PUSH (stropts.h), and t_getinfo and t_getstate, which no AMIX
 *     header declares (sys/tiuser.h has only the types).
 * -Wno-unused-variable: rpcgen declares the inline buffer `buf' in every XDR
 * routine, used or not (on every system, not only here).
 * syslog and getrlimit, which a -5 server also calls, are in amix-decls.h.
 * Link with -lnsl (libnsl.so has both the TI-RPC and the socket-style
 * calls); a -b server or client also needs -lsocket first.
 *
 * Not supported: `hyper' and `unsigned hyper' (rpcgen's quad_t, u_quad_t
 * and xdr_quad_t): AMIX's libnsl has no 64-bit XDR routine.
 */
#ifndef AMIX_RPCGEN_H
#define AMIX_RPCGEN_H
#include <stdint.h>
#include <rpc/rpc.h>
#include <rpc/svc_soc.h>
#include <rpc/clnt_soc.h>
#include <sys/conf.h>
#include <stropts.h>
#include <sys/tiuser.h>
int t_getinfo(int, struct t_info *);
int t_getstate(int);
#endif
