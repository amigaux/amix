/*
 * axtypes.h -- fixed-width types and big-endian access for code that is
 * built both by the host compiler (tools, unit tests) and by gcc-cross-amix
 * (GCC 2.7.2.3, m68k-cbm-sysv4) for the loader.  C89 only: no <stdint.h>,
 * no inline, no // comments.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef AXTYPES_H
#define AXTYPES_H

typedef unsigned char ax_u8;
typedef unsigned short ax_u16;
typedef unsigned int ax_u32;	/* 32 bits on both the host and m68k */
typedef int ax_s32;

#if defined(__m68k__) || defined(m68k)
/* the loader targets the 68020 and up: big-endian, and misaligned data
 * accesses are legal, so a field is read and written in place */
#define AX_GET16(p) (*(const ax_u16 *)(const void *)(p))
#define AX_GET32(p) (*(const ax_u32 *)(const void *)(p))
#define AX_PUT16(p, v) (*(ax_u16 *)(void *)(p) = (ax_u16)(v))
#define AX_PUT32(p, v) (*(ax_u32 *)(void *)(p) = (ax_u32)(v))
#else
#define AX_GET16(p) ((ax_u16)(((ax_u16)(p)[0] << 8) | (ax_u16)(p)[1]))
#define AX_GET32(p) (((ax_u32)(p)[0] << 24) | ((ax_u32)(p)[1] << 16) | \
		     ((ax_u32)(p)[2] << 8) | (ax_u32)(p)[3])
#define AX_PUT16(p, v) ((p)[0] = (ax_u8)((v) >> 8), (p)[1] = (ax_u8)(v))
#define AX_PUT32(p, v) ((p)[0] = (ax_u8)((v) >> 24), (p)[1] = (ax_u8)((v) >> 16), \
			(p)[2] = (ax_u8)((v) >> 8), (p)[3] = (ax_u8)(v))
#endif

#endif
