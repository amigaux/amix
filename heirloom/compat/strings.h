/*
 * compat/strings.h - SVR4.0 has no <strings.h>; the tree uses it only
 * for the str* routines (which live in <string.h>) plus
 * strcasecmp/strncasecmp (declared in amixcompat.h, implemented in
 * compat/amixcompat.c).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license (see amixcompat.h).
 */

#ifndef AMIX_COMPAT_STRINGS_H
#define AMIX_COMPAT_STRINGS_H

#include <string.h>

#endif /* AMIX_COMPAT_STRINGS_H */
