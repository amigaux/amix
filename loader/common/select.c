/*
 * select.c -- see select.h.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "select.h"

static const struct ax_gen *
find(const struct ax_ctl *c, ax_u32 id)
{
	int i;

	for (i = 0; i < c->ngen; i++)
		if (c->gen[i].id == id && c->gen[i].state != AXG_FREE)
			return &c->gen[i];
	return 0;
}

static void
add(struct ax_sel *s, ax_u32 id)
{
	int i;

	for (i = 0; i < s->n; i++)
		if (s->order[i] == id)
			return;
	s->order[s->n++] = id;
}

/* good generations other than skip, newest (highest id) first */
static void
add_good(const struct ax_ctl *c, struct ax_sel *s, ax_u32 skip)
{
	ax_u32 last = 0xFFFFFFFFUL, best;
	int i, found;

	for (;;) {
		found = 0;
		best = 0;
		for (i = 0; i < c->ngen; i++)
			if (c->gen[i].state == AXG_GOOD && c->gen[i].id != skip &&
			    c->gen[i].id < last && c->gen[i].id >= best) {
				best = c->gen[i].id;
				found = 1;
			}
		if (!found)
			return;
		add(s, best);
		last = best;
	}
}

void
ax_select(const struct ax_ctl *c, int readonly, struct ax_sel *s)
{
	const struct ax_gen *g, *d;
	int i;

	s->n = 0;
	s->safe = s->devload = s->trial_first = s->oneshot_used = s->write = 0;
	s->failed_trial = 0;

	/* a trial already started once and never marked good failed (L8) */
	g = c->trial_gen ? find(c, c->trial_gen) : 0;
	if (!readonly && g && g->state == AXG_TRIAL && g->attempts >= 1) {
		s->failed_trial = g->id;
		s->write = 1;
		g = 0;
	}

	/* a one-shot request takes this boot; a pending trial waits */
	if (!readonly && c->oneshot != AXO_NONE) {
		s->oneshot_used = 1;
		s->write = 1;
		if (c->oneshot == AXO_PREVIOUS)
			add_good(c, s, c->default_gen);
		else if (c->oneshot == AXO_GEN && (d = find(c, c->oneshot_gen)) &&
			 d->state != AXG_BAD)
			add(s, d->id);
		else if (c->oneshot == AXO_SAFE)
			s->safe = 1;
		else if (c->oneshot == AXO_DEVLOAD)
			s->devload = 1;
		g = 0;
	}

	/* an unstarted trial goes first and is recorded before it boots */
	if (!readonly && g && g->state == AXG_TRIAL && g->attempts == 0) {
		add(s, g->id);
		s->trial_first = 1;
		s->write = 1;
	}

	/* then the default, the other good generations newest first, the
	 * pristine generation(s) */
	d = find(c, c->default_gen);
	if (d && (d->state == AXG_GOOD || d->state == AXG_PRISTINE))
		add(s, d->id);
	add_good(c, s, 0);
	for (i = 0; i < c->ngen; i++)
		if (c->gen[i].state == AXG_PRISTINE)
			add(s, c->gen[i].id);
}

void
ax_select_apply(const struct ax_ctl *c, const struct ax_sel *s, struct ax_ctl *out)
{
	int i;

	*out = *c;
	out->seq = c->seq + 1;
	for (i = 0; i < out->ngen; i++) {
		if (s->failed_trial && out->gen[i].id == s->failed_trial) {
			out->gen[i].state = AXG_BAD;
			if (out->trial_gen == s->failed_trial)
				out->trial_gen = 0;
		}
		if (s->trial_first && s->n && out->gen[i].id == s->order[0] &&
		    out->gen[i].attempts < 255)
			out->gen[i].attempts++;
	}
	if (s->oneshot_used) {
		out->oneshot = AXO_NONE;
		out->oneshot_gen = 0;
	}
}

void
ax_select_writefail(struct ax_sel *s)
{
	int i;

	if (s->trial_first) {
		for (i = 1; i < s->n; i++)
			s->order[i - 1] = s->order[i];
		s->n--;
		s->trial_first = 0;
	}
	s->write = 0;
}
