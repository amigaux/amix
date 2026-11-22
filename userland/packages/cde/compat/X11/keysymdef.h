/*
 * X11/keysymdef.h -- X11R6.3's <X11/keysymdef.h>, included directly.
 * R6.3 defines each group of keysyms only when its XK_<group> macro is set,
 * which <X11/keysym.h> does; a file that includes <X11/keysymdef.h> alone
 * (as CDE's do) got none.  The groups <X11/keysym.h> sets are set here too.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef XK_MISCELLANY
#define XK_MISCELLANY
#define XK_XKB_KEYS
#define XK_LATIN1
#define XK_LATIN2
#define XK_LATIN3
#define XK_LATIN4
#define XK_GREEK
#endif
#include_next <X11/keysymdef.h>
