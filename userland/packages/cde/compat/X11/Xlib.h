/*
 * X11/Xlib.h -- X11R6.3's <X11/Xlib.h> with XSetAuthorization declared,
 * as later X releases do; R6.3's libX11 has it (ConnDis.c).
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_X11_XLIB_H
#define AMIX_COMPAT_X11_XLIB_H
#include_next <X11/Xlib.h>
#ifdef __cplusplus
extern "C" {
#endif
extern void XSetAuthorization(char *, int, char *, int);
#ifdef __cplusplus
}
#endif
#endif
