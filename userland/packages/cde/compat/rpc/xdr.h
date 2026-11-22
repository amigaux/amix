/*
 * rpc/xdr.h -- Amix's <rpc/xdr.h> with prototypes.
 *
 * Amix (SVR4) declares the XDR routines K&R style, "bool_t xdr_int();".
 * C++ reads that as "takes no arguments", so CDE's C++ (ToolTalk) cannot
 * call them.  This header renames those declarations while the system
 * header is read, then declares the routines with their TI-RPC prototypes.
 * The same in C, where the prototypes add type checking.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_RPC_XDR_H
#define AMIX_COMPAT_RPC_XDR_H

#include <stdio.h>

#define xdr_void		amix_kr_xdr_void
#define xdr_int			amix_kr_xdr_int
#define xdr_u_int		amix_kr_xdr_u_int
#define xdr_long		amix_kr_xdr_long
#define xdr_u_long		amix_kr_xdr_u_long
#define xdr_short		amix_kr_xdr_short
#define xdr_u_short		amix_kr_xdr_u_short
#define xdr_bool		amix_kr_xdr_bool
#define xdr_enum		amix_kr_xdr_enum
#define xdr_array		amix_kr_xdr_array
#define xdr_bytes		amix_kr_xdr_bytes
#define xdr_opaque		amix_kr_xdr_opaque
#define xdr_string		amix_kr_xdr_string
#define xdr_union		amix_kr_xdr_union
#define xdr_char		amix_kr_xdr_char
#define xdr_u_char		amix_kr_xdr_u_char
#define xdr_vector		amix_kr_xdr_vector
#define xdr_float		amix_kr_xdr_float
#define xdr_double		amix_kr_xdr_double
#define xdr_reference		amix_kr_xdr_reference
#define xdr_pointer		amix_kr_xdr_pointer
#define xdr_wrapstring		amix_kr_xdr_wrapstring
#define xdr_netobj		amix_kr_xdr_netobj
#define xdrmem_create		amix_kr_xdrmem_create
#define xdrstdio_create		amix_kr_xdrstdio_create
#define xdrrec_create		amix_kr_xdrrec_create
#define xdrrec_endofrecord	amix_kr_xdrrec_endofrecord
#define xdrrec_skiprecord	amix_kr_xdrrec_skiprecord
#define xdrrec_eof		amix_kr_xdrrec_eof

#include_next <rpc/xdr.h>

#undef xdr_void
#undef xdr_int
#undef xdr_u_int
#undef xdr_long
#undef xdr_u_long
#undef xdr_short
#undef xdr_u_short
#undef xdr_bool
#undef xdr_enum
#undef xdr_array
#undef xdr_bytes
#undef xdr_opaque
#undef xdr_string
#undef xdr_union
#undef xdr_char
#undef xdr_u_char
#undef xdr_vector
#undef xdr_float
#undef xdr_double
#undef xdr_reference
#undef xdr_pointer
#undef xdr_wrapstring
#undef xdr_netobj
#undef xdrmem_create
#undef xdrstdio_create
#undef xdrrec_create
#undef xdrrec_endofrecord
#undef xdrrec_skiprecord
#undef xdrrec_eof

#ifdef __cplusplus
extern "C" {
#endif
extern bool_t xdr_void(void);
extern bool_t xdr_int(XDR *, int *);
extern bool_t xdr_u_int(XDR *, u_int *);
extern bool_t xdr_long(XDR *, long *);
extern bool_t xdr_u_long(XDR *, u_long *);
extern bool_t xdr_short(XDR *, short *);
extern bool_t xdr_u_short(XDR *, u_short *);
extern bool_t xdr_bool(XDR *, bool_t *);
extern bool_t xdr_enum(XDR *, enum_t *);
extern bool_t xdr_array(XDR *, caddr_t *, u_int *, u_int, u_int, xdrproc_t);
extern bool_t xdr_bytes(XDR *, char **, u_int *, u_int);
extern bool_t xdr_opaque(XDR *, caddr_t, u_int);
extern bool_t xdr_string(XDR *, char **, u_int);
extern bool_t xdr_union(XDR *, enum_t *, char *, struct xdr_discrim *, xdrproc_t);
extern bool_t xdr_char(XDR *, char *);
extern bool_t xdr_u_char(XDR *, u_char *);
extern bool_t xdr_vector(XDR *, char *, u_int, u_int, xdrproc_t);
extern bool_t xdr_float(XDR *, float *);
extern bool_t xdr_double(XDR *, double *);
extern bool_t xdr_reference(XDR *, caddr_t *, u_int, xdrproc_t);
extern bool_t xdr_pointer(XDR *, char **, u_int, xdrproc_t);
extern bool_t xdr_wrapstring(XDR *, char **);
extern bool_t xdr_netobj(XDR *, struct netobj *);
extern void xdr_free(xdrproc_t, char *);
extern void xdrmem_create(XDR *, caddr_t, u_int, enum xdr_op);
extern void xdrstdio_create(XDR *, FILE *, enum xdr_op);
extern void xdrrec_create(XDR *, u_int, u_int, caddr_t,
			  int (*)(void *, void *, u_int), int (*)(void *, void *, u_int));
extern bool_t xdrrec_endofrecord(XDR *, bool_t);
extern bool_t xdrrec_skiprecord(XDR *);
extern bool_t xdrrec_eof(XDR *);
#ifdef __cplusplus
}
#endif

#endif /* AMIX_COMPAT_RPC_XDR_H */
