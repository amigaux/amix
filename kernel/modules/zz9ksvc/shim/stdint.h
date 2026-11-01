/*
 * stdint.h -- the C99 integer types the ZZ9000 SDK headers use, for wire.c's ANSI
 * compile with gcc 2.7.2.3 (whose sysroot has no stdint.h).  m68k: int and long are
 * 32 bits, long long 64.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 */
#ifndef ZZ9KSVC_STDINT_H
#define ZZ9KSVC_STDINT_H
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
#define INT64_C(c)	c ## LL
#define UINT64_C(c)	c ## ULL
#define UINT8_MAX	0xff
#define UINT16_MAX	0xffff
#define UINT32_MAX	0xffffffffU
#define INT32_MAX	0x7fffffff
#define UINT64_MAX	0xffffffffffffffffULL
#endif
