/*
 * t_crc32.c -- CRC-32 against the standard check value.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "t.h"
#include "crc32.h"

void
test_crc32(void)
{
	ax_u32 tab[256];
	const ax_u8 *s = (const ax_u8 *)"123456789";

	ax_crc32_init(tab);
	T_EQ(ax_crc32(tab, s, 9), 0xCBF43926UL);
	T_EQ(ax_crc32(tab, s, 0), 0);
	/* incremental equals one-shot */
	T_EQ(ax_crc32_update(tab, ax_crc32(tab, s, 4), s + 4, 5), 0xCBF43926UL);
}
