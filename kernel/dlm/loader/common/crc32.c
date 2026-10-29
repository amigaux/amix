/*
 * crc32.c -- see crc32.h.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "crc32.h"

void
ax_crc32_init(ax_u32 table[256])
{
	ax_u32 i, j, c;

	for (i = 0; i < 256; i++) {
		c = i;
		for (j = 0; j < 8; j++)
			c = (c & 1) ? (c >> 1) ^ 0xEDB88320UL : c >> 1;
		table[i] = c;
	}
}

ax_u32
ax_crc32_update(const ax_u32 table[256], ax_u32 crc, const ax_u8 *buf,
		ax_u32 len)
{
	crc = ~crc;
	while (len--)
		crc = table[(crc ^ *buf++) & 0xFF] ^ (crc >> 8);
	return ~crc;
}

ax_u32
ax_crc32(const ax_u32 table[256], const ax_u8 *buf, ax_u32 len)
{
	return ax_crc32_update(table, 0, buf, len);
}
