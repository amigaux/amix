/*
 * menu.h -- see menu.c.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef MENU_H
#define MENU_H

#include "store.h"

#define MENU_NONE	0
#define MENU_OPEN	1
#define MENU_PREVIOUS	2

int menu_window(ax_u32 ds, ax_u8 keys[16]);
ax_u32 menu_previous(const struct ax_ctl *c);
ax_u32 menu_run(const struct ax_ctl *c, ax_u32 first, ax_u32 cpu, int *safe, int *devload);

#endif
