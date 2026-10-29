/*
 * input.h -- see input.c.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef INPUT_H
#define INPUT_H

#include "axtypes.h"

void in_init(void *replyport);
void in_matrix(ax_u8 m[16]);
int in_key(void);
int in_lmb(void);
int in_serial(void);
int in_char(int k);
void in_frame(void);

#endif
