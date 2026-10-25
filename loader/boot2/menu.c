/*
 * menu.c -- the menu window and the boot menu (docs/spec/10-boot-loader.md
 * §7.1, §7.4).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "b2.h"
#include "input.h"
#include "store.h"
#include "menu.h"

/* returning to the strap stays off until M-LD3 shows Kickstart handles it */
#define STRAP_RETURN 0

static const char *const statename[] = { "free", "pristine", "good", "trial", "bad" };

/*
 * The window: menu_ds tenths of a second (5 frames each) in which a key,
 * a serial byte or the left mouse button opens the menu and 'p' boots the
 * previous good generation.  The keyboard matrix is kept for bootinfo.
 */
int
menu_window(ax_u32 ds, ax_u8 keys[16])
{
	ax_u32 f;
	int c, k;

	in_matrix(keys);
	for (f = 0; f < ds * 5; f++) {
		in_frame();
		k = in_key();
		c = k >= 0 ? in_char(k) : in_serial();
		if (c == 'p' || c == 'P')
			return MENU_PREVIOUS;
		if (k >= 0 || c >= 0 || in_lmb())
			return MENU_OPEN;
	}
	return MENU_NONE;
}

static int
listed(const struct ax_ctl *c, int i)
{
	return i < c->ngen && c->gen[i].state != AXG_FREE;
}

static void
draw(const struct ax_ctl *c, int sel, int safe, int devload, ax_u32 cpu)
{
	int i, n = 0;

	con_printf("\namix-boot %u (680%u)\n", LOADER_VERSION, cpu);
	for (i = 0; i < c->ngen; i++) {
		if (!listed(c, i))
			continue;
		n++;
		con_printf(" %c%u  generation %u  %s%s\n", i == sel ? '>' : ' ', (ax_u32)n,
			   c->gen[i].id, statename[c->gen[i].state],
			   c->gen[i].id == c->default_gen ? "  (default)" : "");
	}
	con_printf("  s  safe mode: %s   d  development load: %s   p  previous good\n",
		   safe ? "on" : "off", devload ? "on" : "off");
	con_puts("  digit: choose   Return: boot   left mouse: next, hold 2 s: boot\n");
}

/* the newest good generation other than the default, or 0 (the same rule
 * as the one-shot request, select.c) */
ax_u32
menu_previous(const struct ax_ctl *c)
{
	ax_u32 best = 0;
	int i;

	for (i = 0; i < c->ngen; i++)
		if (c->gen[i].state == AXG_GOOD && c->gen[i].id != c->default_gen &&
		    c->gen[i].id > best)
			best = c->gen[i].id;
	return best;
}

/* the generation chosen in the menu (0: nothing chosen) */
ax_u32
menu_run(const struct ax_ctl *c, ax_u32 first, ax_u32 cpu, int *safe, int *devload)
{
	int sel = -1, i, n, k, ch, released = 0;
	ax_u32 held = 0;

	for (i = 0; i < c->ngen; i++)
		if (listed(c, i) && (sel < 0 || c->gen[i].id == first))
			sel = i;
	if (sel < 0) {
		con_puts("amix-boot: no generation to choose from\n");
		return 0;
	}
	draw(c, sel, *safe, *devload, cpu);
	for (;;) {
		in_frame();
		k = in_key();
		ch = k >= 0 ? in_char(k) : in_serial();
		if (ch >= '1' && ch <= '9') {
			for (i = 0, n = 0; i < c->ngen; i++)
				if (listed(c, i) && ++n == ch - '0') {
					sel = i;
					draw(c, sel, *safe, *devload, cpu);
				}
		} else if (ch == 'p' || ch == 'P') {
			ax_u32 prev = menu_previous(c);
			if (prev)
				return prev;
			con_puts("amix-boot: no previous good generation\n");
		} else if (ch == 's' || ch == 'S') {
			*safe = !*safe;
			draw(c, sel, *safe, *devload, cpu);
		} else if (ch == 'd' || ch == 'D') {
			*devload = !*devload;
			draw(c, sel, *safe, *devload, cpu);
		} else if (ch == 'r' || ch == 'R') {
			if (STRAP_RETURN)
				return 0;
			con_puts("amix-boot: returning to Kickstart is not enabled in this loader\n");
		} else if (ch == '\r' || ch == '\n') {
			return c->gen[sel].id;
		}
		/* mouse: actions count only after the first release */
		if (!in_lmb()) {
			if (released && held > 0 && held < 100) {
				for (i = (sel + 1) % c->ngen; i != sel; i = (i + 1) % c->ngen)
					if (listed(c, i))
						break;
				sel = i;
				draw(c, sel, *safe, *devload, cpu);
			}
			released = 1;
			held = 0;
		} else if (released && ++held == 100) {
			return c->gen[sel].id;
		}
	}
}
