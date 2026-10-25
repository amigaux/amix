/*
 * crc32.h -- CRC-32 (IEEE 802.3, reflected, polynomial 0xEDB88320, initial
 * and final XOR 0xFFFFFFFF; the zlib/PNG CRC).  The table is built at run
 * time into caller storage so the loader carries no 1 KiB constant.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef CRC32_H
#define CRC32_H

#include "axtypes.h"

void ax_crc32_init(ax_u32 table[256]);
ax_u32 ax_crc32_update(const ax_u32 table[256], ax_u32 crc,
		       const ax_u8 *buf, ax_u32 len);
/* one-shot: crc32 of buf[0..len) */
ax_u32 ax_crc32(const ax_u32 table[256], const ax_u8 *buf, ax_u32 len);

#endif
