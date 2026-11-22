/*
 * X11/ImUtil.h -- the declaration later X releases install for Xlib's
 * image helper.  X11R6.3's libX11 has _XInitImageFuncPtrs (ImUtil.c) but
 * installs no header for it.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_X11_IMUTIL_H
#define AMIX_COMPAT_X11_IMUTIL_H
#include <X11/Xlib.h>
#ifdef __cplusplus
extern "C" {
#endif
extern void _XInitImageFuncPtrs(XImage *);
#ifdef __cplusplus
}
#endif
#endif
