/*
 * tiuser.h -- Amix's <tiuser.h> with the TLI calls declared.
 *
 * Amix (SVR4) declares the TLI structures but none of libnsl's t_*
 * functions, so C++ (ToolTalk) cannot call them and C sees implicit
 * declarations.  The prototypes are SVR4's.  libnsl has no t_strerror
 * (it came with XTI); it is defined here from libnsl's t_errlist.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_TIUSER_H
#define AMIX_COMPAT_TIUSER_H

#include_next <tiuser.h>

#ifdef __cplusplus
extern "C" {
#endif
extern int t_errno;
extern int t_nerr;
extern char *t_errlist[];
extern int t_accept(int, int, struct t_call *);
extern char *t_alloc(int, int, int);
extern int t_bind(int, struct t_bind *, struct t_bind *);
extern int t_close(int);
extern int t_connect(int, struct t_call *, struct t_call *);
extern void t_error(const char *);
extern int t_free(char *, int);
extern int t_getinfo(int, struct t_info *);
extern int t_getstate(int);
extern int t_listen(int, struct t_call *);
extern int t_look(int);
extern int t_open(const char *, int, struct t_info *);
extern int t_optmgmt(int, struct t_optmgmt *, struct t_optmgmt *);
extern int t_rcv(int, char *, unsigned, int *);
extern int t_rcvconnect(int, struct t_call *);
extern int t_rcvdis(int, struct t_discon *);
extern int t_rcvrel(int);
extern int t_rcvudata(int, struct t_unitdata *, int *);
extern int t_rcvuderr(int, struct t_uderr *);
extern int t_snd(int, char *, unsigned, int);
extern int t_snddis(int, struct t_call *);
extern int t_sndrel(int);
extern int t_sndudata(int, struct t_unitdata *);
extern int t_sync(int);
extern int t_unbind(int);
#ifdef __cplusplus
}
#endif

static inline char *
t_strerror(int e)
{
	return (e >= 0 && e < t_nerr) ? t_errlist[e] : (char *)"unknown TLI error";
}

#endif /* AMIX_COMPAT_TIUSER_H */
