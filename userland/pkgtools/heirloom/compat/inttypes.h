/*
 * compat/inttypes.h - minimal C99 fixed-width integer types for the
 * Amix (SVR4.0 m68k, ILP32, big-endian) cross build.  Only what
 * hdrs/sys/dklabel.h and hdrs/sys/vtoc.h consume.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license (see amixcompat.h).
 */

#ifndef AMIX_COMPAT_INTTYPES_H
#define AMIX_COMPAT_INTTYPES_H

typedef signed char		int8_t;
typedef unsigned char		uint8_t;
typedef short			int16_t;
typedef unsigned short		uint16_t;
typedef int			int32_t;
typedef unsigned int		uint32_t;
typedef long long		int64_t;
typedef unsigned long long	uint64_t;

typedef long			intptr_t;
typedef unsigned long		uintptr_t;

#endif /* AMIX_COMPAT_INTTYPES_H */
