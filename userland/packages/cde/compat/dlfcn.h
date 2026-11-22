/*
 * dlfcn.h -- Amix's <dlfcn.h> with RTLD_GLOBAL and RTLD_LOCAL, which
 * SVR4.0 predates (its dlopen takes RTLD_LAZY or RTLD_NOW only).  Both are
 * 0 here, so they add nothing to the mode dlopen is given.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_DLFCN_H
#define AMIX_COMPAT_DLFCN_H
#include_next <dlfcn.h>
#ifndef RTLD_GLOBAL
#define RTLD_GLOBAL	0
#endif
#ifndef RTLD_LOCAL
#define RTLD_LOCAL	0
#endif
#endif
