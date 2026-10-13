/*
 * compat/alloca.h - SVR4.0 has no <alloca.h>; map to the gcc builtin
 * (gcc 2.7 supports __builtin_alloca on m68k).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license (see amixcompat.h).
 */

#ifndef AMIX_COMPAT_ALLOCA_H
#define AMIX_COMPAT_ALLOCA_H

#ifndef alloca
#define alloca(size)	__builtin_alloca(size)
#endif

#endif /* AMIX_COMPAT_ALLOCA_H */
