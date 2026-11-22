/*
 * X11/Xutil.h -- X11R6.3's <X11/Xutil.h>, after <X11/Xlib.h> (whose types
 * it uses) and with <X11/keysym.h>, as later X releases have it: Xutil.h's
 * own IsModifierKey and similar macros use XK_ names, and CDE relies on
 * getting them, and Xlib's types, from here.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_X11_XUTIL_H
#define AMIX_COMPAT_X11_XUTIL_H
#include <X11/Xlib.h>
#include_next <X11/Xutil.h>
#include <X11/keysym.h>
#endif
