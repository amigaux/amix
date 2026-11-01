/*
 * kern.c -- the kernel side of libzz9k's host test: kernel/modules' zz9ksvc.c behind its own
 * host harness (zz9ksvc/test/td.h: the DDI stand-ins, a simulated clock, the stub boards)
 * with the stand-in runtimes of zz9ksvc/test/fw.c, one per unit.  The test's other units
 * reach it only through the kt_* calls below, in plain types.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see LICENSE.
 */
#include "td.h"

#define KT_NSLOT	64

static dev_t kt_dev[KT_NSLOT];
static int kt_used[KT_NSLOT];
static struct zz9kbus_board kt_b[FW_NINST];
static int kt_nb;

/* an open of /dev/zz9ksvc<unit>: a slot, or -errno */
int
kt_open(int unit)
{
	dev_t d;
	int e, s;

	d = op_open(unit, &e);
	if (e)
		return -e;
	for (s = 0; s < KT_NSLOT; s++)
		if (!kt_used[s]) {
			kt_used[s] = 1;
			kt_dev[s] = d;
			return s;
		}
	op_close(d);
	return -EMFILE;
}

/* d_close of a slot's clone, as specfs calls it: after the last close and the last unmap */
int
kt_close(int s)
{
	kt_used[s] = 0;
	return op_close(kt_dev[s]);
}

int
kt_ioctl(int s, int cmd, void *arg)
{
	return ioc(kt_dev[s], cmd, arg);
}

/* what a mapping of len bytes at off reaches, or 0 */
void *
kt_map(int s, long off, unsigned long len)
{
	return td_map(kt_dev[s], off, len);
}

void kt_drain(void) { drain(); }
void kt_run(int ticks) { td_run(ticks); }
int kt_kmem(void) { return td_kmem_live; }

/* opens the driver holds, closed ones waiting for releases included */
int
kt_opens(void)
{
	int u, s, n = 0;

	for (u = 0; u < ZZ9KBUS_NUNIT; u++)
		for (s = 0; s < ZZS_NOPEN; s++)
			if (zzs_unit[u].u_open[s])
				n++;
	return n;
}

/*
 * A fresh box: zz9ksvc unloaded, the boards of the last one gone; then n boards, board i
 * on unit i with runtime i, board 0 without a runtime when dead0, and zz9ksvc loaded.
 * Returns _load's answer (ENXIO when no board serves).
 */
int
kt_setup(int n, int dead0)
{
	int i, e;

	drain();
	if ((e = td_unload()) != 0)
		return e;
	for (i = 0; i < kt_nb; i++)
		zz9kbus_unregister(&kt_b[i]);
	kt_nb = 0;
	for (i = 0; i < n && i < FW_NINST; i++) {
		fw_cur = i;
		fw_init(8, 8, 0);
		board_setup(&kt_b[i], i);
		if (i == 0 && dead0)
			kt_b[i].zb_mbox = 0;
		zz9kbus_register(&kt_b[i]);
		kt_nb++;
	}
	fw_cur = 0;
	return td_load("");
}

/* the box torn down: 0 when zz9ksvc unloads and gave everything back */
int
kt_teardown(void)
{
	int i, e;

	drain();
	if ((e = td_unload()) != 0)
		return e;
	for (i = 0; i < kt_nb; i++)
		zz9kbus_unregister(&kt_b[i]);
	kt_nb = 0;
	return td_kmem_live == 0 && callouts() == 0 ? 0 : -1;
}
