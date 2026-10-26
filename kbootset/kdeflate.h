/*
 * kdeflate.h -- a raw deflate for the box's kbootset, which has no zlib
 * (kdeflate.c).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef KDEFLATE_H
#define KDEFLATE_H

#include "axtypes.h"

/* raw deflate of n bytes into a malloc'd buffer (*outn bytes); 0 when the
 * result would not be smaller than the input (as ks_deflate) */
ax_u8 *kb_deflate(const ax_u8 *in, ax_u32 n, ax_u32 *outn);

#endif
