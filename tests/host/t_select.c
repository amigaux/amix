/*
 * t_select.c -- generation choice: every rule of docs/spec/10-boot-loader.md
 * §7 and the L8/L10 rows of §9.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <string.h>
#include "t.h"
#include "select.h"

static struct ax_ctl c, o;
static struct ax_sel s;

static void
gen(int i, ax_u32 id, int state, int attempts)
{
	c.gen[i].id = id;
	c.gen[i].state = (ax_u8)state;
	c.gen[i].attempts = (ax_u8)attempts;
	if (i >= c.ngen)
		c.ngen = (ax_u16)(i + 1);
}

/* pristine 12, good 40, good 41 (default) */
static void
base(void)
{
	memset(&c, 0, sizeof(c));
	c.seq = 100;
	gen(0, 12, AXG_PRISTINE, 0);
	gen(1, 40, AXG_GOOD, 0);
	gen(2, 41, AXG_GOOD, 0);
	c.default_gen = 41;
}

#define ORDER3(a, b, d) (s.n == 3 && s.order[0] == (a) && s.order[1] == (b) && s.order[2] == (d))

void
test_select(void)
{
	/* default path: no write; fallback order default, other good, pristine */
	base();
	ax_select(&c, 0, &s);
	T_CHECK(ORDER3(41, 40, 12));
	T_EQ(s.write, 0);

	/* rollback made an older generation the default: it goes first */
	base();
	c.default_gen = 40;
	ax_select(&c, 0, &s);
	T_CHECK(ORDER3(40, 41, 12));

	/* an unstarted trial boots first, its attempt recorded beforehand */
	base();
	gen(3, 42, AXG_TRIAL, 0);
	c.trial_gen = 42;
	ax_select(&c, 0, &s);
	T_EQ(s.n, 4);
	T_EQ(s.order[0], 42);
	T_EQ(s.order[1], 41);
	T_EQ(s.trial_first, 1);
	T_EQ(s.write, 1);
	ax_select_apply(&c, &s, &o);
	T_EQ(o.seq, 101);
	T_EQ(o.gen[3].attempts, 1);
	T_EQ(o.gen[3].state, AXG_TRIAL);
	T_EQ(o.default_gen, 41);		/* booting a trial never moves the default */

	/* the trial booted once and was never marked good: L8 */
	c = o;
	ax_select(&c, 0, &s);
	T_CHECK(ORDER3(41, 40, 12));
	T_EQ(s.failed_trial, 42);
	T_EQ(s.write, 1);
	ax_select_apply(&c, &s, &o);
	T_EQ(o.gen[3].state, AXG_BAD);
	T_EQ(o.trial_gen, 0);

	/* L10: the attempt cannot be written, so the trial is not booted */
	base();
	gen(3, 42, AXG_TRIAL, 0);
	c.trial_gen = 42;
	ax_select(&c, 0, &s);
	ax_select_writefail(&s);
	T_CHECK(ORDER3(41, 40, 12));
	T_EQ(s.trial_first, 0);

	/* read-only medium: trials and one-shots do not exist there */
	base();
	gen(3, 42, AXG_TRIAL, 0);
	c.trial_gen = 42;
	c.oneshot = AXO_SAFE;
	ax_select(&c, 1, &s);
	T_CHECK(ORDER3(41, 40, 12));
	T_EQ(s.write, 0);
	T_EQ(s.safe, 0);

	/* one-shot previous: the newest good generation older than the default */
	base();
	c.oneshot = AXO_PREVIOUS;
	ax_select(&c, 0, &s);
	T_CHECK(ORDER3(40, 41, 12));
	T_EQ(s.oneshot_used, 1);
	ax_select_apply(&c, &s, &o);
	T_EQ(o.oneshot, AXO_NONE);

	/* L10 on a one-shot: booted, but not consumed (it repeats) */
	ax_select_writefail(&s);
	T_CHECK(ORDER3(40, 41, 12));

	/* one-shot named generation, and a bad one is ignored */
	base();
	c.oneshot = AXO_GEN;
	c.oneshot_gen = 12;
	ax_select(&c, 0, &s);
	T_CHECK(ORDER3(12, 41, 40));
	base();
	gen(3, 39, AXG_BAD, 0);
	c.oneshot = AXO_GEN;
	c.oneshot_gen = 39;
	ax_select(&c, 0, &s);
	T_CHECK(ORDER3(41, 40, 12));

	/* one-shot safe mode and development load */
	base();
	c.oneshot = AXO_SAFE;
	ax_select(&c, 0, &s);
	T_EQ(s.safe, 1);
	T_EQ(s.order[0], 41);
	base();
	c.oneshot = AXO_DEVLOAD;
	ax_select(&c, 0, &s);
	T_EQ(s.devload, 1);

	/* a one-shot takes this boot; the pending trial waits, unrecorded */
	base();
	gen(3, 42, AXG_TRIAL, 0);
	c.trial_gen = 42;
	c.oneshot = AXO_PREVIOUS;
	ax_select(&c, 0, &s);
	T_CHECK(ORDER3(40, 41, 12));
	ax_select_apply(&c, &s, &o);
	T_EQ(o.gen[3].attempts, 0);

	/* a freshly installed box: pristine only */
	memset(&c, 0, sizeof(c));
	gen(0, 1, AXG_PRISTINE, 0);
	c.default_gen = 1;
	ax_select(&c, 0, &s);
	T_EQ(s.n, 1);
	T_EQ(s.order[0], 1);

	/* nothing bootable: an empty list (boot2 opens the menu) */
	memset(&c, 0, sizeof(c));
	gen(0, 5, AXG_BAD, 0);
	ax_select(&c, 0, &s);
	T_EQ(s.n, 0);
}
