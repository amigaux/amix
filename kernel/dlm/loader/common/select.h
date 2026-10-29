/*
 * select.h -- which generation to boot (docs/spec/10-boot-loader.md §7):
 * try-once trials, one-shot requests, the default, and the fallback order
 * used when a generation cannot be loaded.  A pure function over the
 * control block; boot2 does the I/O.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef SELECT_H
#define SELECT_H

#include "store.h"

struct ax_sel {
	ax_u32 order[AX_MAXGEN + 1];	/* generation ids to try, in order */
	int n;
	int safe;		/* boot in safe mode */
	int devload;		/* development load for this boot */
	int trial_first;	/* order[0] is the trial: record its attempt first */
	int oneshot_used;	/* a one-shot request is consumed by this boot */
	ax_u32 failed_trial;	/* a trial that did not reach multi-user (L8), or 0 */
	int write;		/* the control block must be written before booting */
};

/* readonly: the medium has no writable control block (no trial, no one-shot) */
void ax_select(const struct ax_ctl *c, int readonly, struct ax_sel *s);

/* the control block to write for s (attempt recorded, failed trial marked
 * bad, one-shot cleared, sequence + 1) */
void ax_select_apply(const struct ax_ctl *c, const struct ax_sel *s, struct ax_ctl *out);

/* the write failed (L10): a trial is not booted, a one-shot request is
 * booted without being consumed */
void ax_select_writefail(struct ax_sel *s);

#endif
