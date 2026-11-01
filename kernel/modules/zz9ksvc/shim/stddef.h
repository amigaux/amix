/*
 * stddef.h -- what the ZZ9000 SDK headers need of <stddef.h>, for wire.c's ANSI
 * compile, which includes no kernel header.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 */
#ifndef ZZ9KSVC_STDDEF_H
#define ZZ9KSVC_STDDEF_H
typedef unsigned int	size_t;
typedef int		ptrdiff_t;
#ifndef NULL
#define NULL	0
#endif
#define offsetof(t, m)	((size_t)&((t *)0)->m)
#endif
