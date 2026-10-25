/*
 * t_kbootset.c -- kbootset's core on a store in memory: the lifecycle
 * (commit, mark-good, rollback, next, mark-bad, collect, loader-install),
 * the store-space gate, and a power cut after every single write of each
 * operation -- whole or torn in half -- after which the store must still
 * boot, judged by the loader's own rules (docs/plan/stage-2.md S2-02, the
 * host half of M-GEN3).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdlib.h>
#include <string.h>
#include "t.h"
#include "crc32.h"
#include "select.h"
#include "ks.h"

#define SIZE	(2UL << 20)

static ax_u8 *img;
static long writes, cut = -1;	/* writes done; the write that loses power */
static int torn;		/* the cut write lands half */
static char jrn[200];

static int
mread(void *ctx, ax_u32 off, ax_u8 *buf, ax_u32 len)
{
	(void)ctx;
	if (off + len > SIZE)
		return -1;
	memcpy(buf, img + off, len);
	return 0;
}

static int
mwrite(void *ctx, ax_u32 off, const ax_u8 *buf, ax_u32 len)
{
	(void)ctx;
	if (off + len > SIZE)
		return -1;
	if (cut >= 0 && writes >= cut) {
		if (torn && writes == cut)
			memcpy(img + off, buf, len / 2);
		writes++;
		return -1;	/* the power is gone: nothing after this lands */
	}
	writes++;
	memcpy(img + off, buf, len);
	return 0;
}

static int jput(void *c, const char *t) { (void)c; if (cut >= 0 && writes >= cut) return -1; strcpy(jrn, t); return 0; }
static int jget(void *c, char *b, int n) { (void)c; strncpy(b, jrn, n); return (int)strlen(jrn); }
static int jclear(void *c) { (void)c; if (cut >= 0 && writes >= cut) return -1; jrn[0] = 0; return 0; }

static void
setup(struct ks *k)
{
	memset(k, 0, sizeof(*k));
	k->dev.read = mread;
	k->dev.write = mwrite;
	k->jrn.put = jput;
	k->jrn.get = jget;
	k->jrn.clear = jclear;
}

static ax_u8 kern[300000], boot2a[20000], boot2b[21000];

static void
fill(ax_u8 *p, ax_u32 n, ax_u32 seed)
{
	while (n--)
		*p++ = (ax_u8)((seed = seed * 1103515245UL + 12345UL) >> 16);
}

static int
commit(struct ks *k, ax_u32 seed, ax_u32 *id)
{
	struct ks_member m;
	struct ks_newgen g;

	fill(kern, sizeof(kern), seed);
	memset(&m, 0, sizeof(m));
	m.kind = AXK_KERNEL;
	m.name = "unix";
	m.data = kern;
	m.size = sizeof(kern);
	memset(&g, 0, sizeof(g));
	g.head = "line k46\nrootfs ufs\n";
	g.n = 1;
	g.m = &m;
	g.created = 1761400000UL + seed;
	return ks_commit(k, &g, id);
}

/* what the loader would do with the store as it lies: boot1's choice of
 * boot2 (primary, else secondary, by CRC), boot2's selection, and every
 * member of the chosen generation intact.  1 = it boots */
static int
boots(void)
{
	static struct ax_manifest m;
	static char man[65536];
	ax_u32 tab[256];
	struct ax_header h;
	struct ax_ctl c;
	struct ax_sel s;
	const struct ax_gen *g = 0;
	int i, e, b2 = 0;

	ax_crc32_init(tab);
	if (ax_hdr_pick(tab, img + AX_HDR_A_OFF, img + AX_HDR_B_OFF, &h) < 0)
		return 0;
	for (i = 0; i < 2 && !b2; i++)
		b2 = h.boot2[i].len && ax_crc32(tab, img + h.boot2[i].off, h.boot2[i].len) == h.boot2[i].crc;
	if (!b2 || ax_ctl_pick(tab, img + h.ctl_off[0], img + h.ctl_off[1], &c) < 0)
		return 0;
	ax_select(&c, 0, &s);
	if (s.n == 0)
		return 0;
	for (i = 0; i < c.ngen; i++)
		if (c.gen[i].id == s.order[0])
			g = &c.gen[i];
	if (!g || ax_crc32(tab, img + g->man_off, g->man_len) != g->man_crc)
		return 0;
	memcpy(man, img + g->man_off, g->man_len);
	if (ax_manifest_parse(tab, man, g->man_len, &m, &e) != AXM_OK)
		return 0;
	return ax_crc32(tab, img + m.kernel.at, m.kernel.size) == m.kernel.crc;
}

/* a base store: pristine 1, good 2 (the default), trial 3 */
static void
base(struct ks *k)
{
	ax_u32 id;

	writes = 0;
	cut = -1;
	jrn[0] = 0;
	memset(img, 0, SIZE);
	setup(k);
	fill(boot2a, sizeof(boot2a), 7);
	ks_create(k, SIZE, 0, boot2a, sizeof(boot2a), 1);
	commit(k, 1, &id);
	commit(k, 2, &id);
	ks_mark_good(k, 2, 1);
	commit(k, 3, &id);
}

/* op 0 commit, 1 mark-good of the trial, 2 rollback, 3 loader-install */
static int
op(struct ks *k, int which)
{
	ax_u32 id;

	switch (which) {
	case 0: return commit(k, 4, &id);
	case 1: return ks_mark_good(k, 3, 1);
	case 2: return ks_rollback(k, &id);
	default: return ks_loader_install(k, boot2b, sizeof(boot2b), 2, 0);
	}
}

/* the loader's attempt write, as boot2 does it before booting a trial */
static void
loader_boot(struct ks *k, ax_u32 *booted)
{
	struct ax_sel sel;
	struct ax_ctl nc;
	ax_u8 blk[AX_BLK];

	ax_select(&k->ctl, 0, &sel);
	*booted = sel.order[0];
	if (sel.write) {
		ax_select_apply(&k->ctl, &sel, &nc);
		ax_ctl_write(k->crctab, &nc, blk);
		memcpy(img + k->hdr.ctl_off[k->ctlcopy ^ 1], blk, AX_BLK);
	}
	setup(k);
	ks_open(k);
}

/* retry: an fsck-repair reboot gives the trial's attempt back, twice at
 * most; then the loader's try-once rule marks it bad */
static void
retries(void)
{
	struct ks k;
	ax_u32 booted, id;
	const struct ax_gen *g;
	int i;

	base(&k);			/* pristine 1, good 2 (default), trial 3 */
	for (i = 0; i < KS_RETRIES; i++) {
		loader_boot(&k, &booted);
		T_EQ(booted, 3);
		T_CHECK((g = ks_find(&k, 3)) != 0 && g->attempts == 1);
		T_EQ(ks_retry(&k, 3), KS_OK);	/* the fsck reboot */
		T_CHECK((g = ks_find(&k, 3)) != 0 && g->attempts == 0);
		T_EQ(g->flags & 3, i + 1);
	}
	loader_boot(&k, &booted);
	T_EQ(booted, 3);
	writes = 0;
	T_EQ(ks_retry(&k, 3), KS_OK);		/* given back twice: it stands */
	T_EQ(writes, 0);
	T_CHECK(strstr(k.msg, "stands") != 0);
	loader_boot(&k, &booted);		/* never marked good: L8, back to 2 */
	T_EQ(booted, 2);
	T_CHECK((g = ks_find(&k, 3)) == 0 || g->state == AXG_BAD);
	/* a boot that was not the trial gets nothing back */
	writes = 0;
	T_EQ(ks_retry(&k, 2), KS_OK);
	T_EQ(writes, 0);
	(void)id;
}

static void
powercuts(void)
{
	static ax_u8 before[SIZE];
	struct ks k;
	long total, i;
	int which, t, bad, rc;
	ax_u32 seq0, id;

	for (which = 0; which < 4; which++) {
		base(&k);
		memcpy(before, img, SIZE);
		seq0 = k.ctl.seq;
		writes = 0;
		T_EQ(op(&k, which), KS_OK);
		total = writes;
		/* commit: kernel, manifest, control block; mark-good, rollback:
		 * the control block; loader-install: secondary, header,
		 * primary, header */
		T_EQ(total, which == 0 ? 3 : which == 3 ? 4 : 1);
		for (t = 0; t < 2; t++)
			for (i = 0, bad = 0; i < total; i++) {
				memcpy(img, before, SIZE);
				setup(&k);
				cut = -1;
				jrn[0] = 0;
				T_EQ(ks_open(&k), KS_OK);
				writes = 0;
				cut = i;
				torn = t;
				rc = op(&k, which);
				if (rc == KS_OK)
					bad++;		/* it cannot finish without its writes */
				cut = -1;
				if (!boots())
					bad++;
				setup(&k);
				if (ks_open(&k) != KS_OK || (k.ctl.seq != seq0 && k.ctl.seq != seq0 + 1 &&
							     which != 3))
					bad++;
				/* after an interrupted commit the next one succeeds */
				if (which == 0 && commit(&k, 9, &id) != KS_OK)
					bad++;
				T_EQ(bad, 0);
				if (bad)
					fprintf(stderr, "  op %d, cut at write %ld of %ld, torn %d\n",
						which, i, total, t);
			}
	}
}

void
test_kbootset(void)
{
	static ax_u8 copy[SIZE];
	struct ks k;
	ax_u32 id, to;
	const struct ax_gen *g;
	struct ks_member m;
	struct ks_newgen ng;

	img = calloc(1, SIZE);
	setup(&k);
	fill(boot2a, sizeof(boot2a), 7);
	fill(boot2b, sizeof(boot2b), 8);
	T_EQ(ks_create(&k, SIZE, 0, boot2a, sizeof(boot2a), 1), KS_OK);
	T_EQ(k.ctl.ngen, 0);
	/* the first generation is pristine and the default */
	T_EQ(commit(&k, 1, &id), KS_OK);
	T_EQ(id, 1);
	T_CHECK((g = ks_find(&k, 1)) != 0 && g->state == AXG_PRISTINE);
	T_EQ(k.ctl.default_gen, 1);
	T_CHECK(boots());
	/* commit: a trial that does not change the default */
	T_EQ(commit(&k, 2, &id), KS_OK);
	T_EQ(id, 2);
	T_EQ(k.ctl.trial_gen, 2);
	T_EQ(k.ctl.default_gen, 1);
	/* a newer trial replaces an unbooted one */
	T_EQ(commit(&k, 3, &id), KS_OK);
	T_EQ(id, 3);
	T_CHECK(ks_find(&k, 2) == 0);
	T_EQ(k.ctl.trial_gen, 3);
	/* mark-good: the trial becomes good and the default */
	T_EQ(ks_mark_good(&k, 3, 1), KS_OK);
	T_EQ(k.ctl.default_gen, 3);
	T_EQ(k.ctl.trial_gen, 0);
	T_EQ(ks_mark_good(&k, 3, 1), KS_OK);	/* again: nothing to mark */
	T_EQ(commit(&k, 4, &id), KS_OK);
	T_EQ(ks_mark_good(&k, 4, 1), KS_OK);
	T_EQ(commit(&k, 5, &id), KS_OK);
	T_EQ(ks_mark_good(&k, 5, 1), KS_OK);
	/* kept: pristine 1, the two newest good 5 and 4; 3 collected */
	T_EQ(k.ctl.ngen, 3);
	T_CHECK(ks_find(&k, 1) && ks_find(&k, 4) && ks_find(&k, 5) && !ks_find(&k, 3));
	/* rollback with a pending trial: the default goes to 4, the trial is
	 * cancelled, 5 stays good */
	T_EQ(commit(&k, 6, &id), KS_OK);
	T_EQ(id, 6);
	T_EQ(ks_rollback(&k, &to), KS_OK);
	T_EQ(to, 4);
	T_EQ(k.ctl.default_gen, 4);
	T_EQ(k.ctl.trial_gen, 0);
	T_CHECK(!ks_find(&k, 6) && ks_find(&k, 5) && ks_find(&k, 5)->state == AXG_GOOD);
	T_CHECK(boots());
	/* ids are never reused, even after 6 was collected */
	T_EQ(commit(&k, 7, &id), KS_OK);
	T_EQ(id, 7);
	/* rollback all the way to the pristine generation */
	T_EQ(ks_rollback(&k, &to), KS_OK);
	T_EQ(to, 1);
	T_EQ(ks_rollback(&k, &to), KS_EREFUSE);
	/* refusals */
	T_EQ(ks_mark_bad(&k, 1), KS_EREFUSE);		/* pristine */
	T_EQ(ks_mark_good(&k, 99, 1), KS_EREFUSE);
	T_EQ(ks_next(&k, AXO_GEN, 99), KS_EREFUSE);
	T_EQ(ks_next(&k, AXO_GEN, 5), KS_OK);
	T_EQ(k.ctl.oneshot, AXO_GEN);
	T_EQ(ks_mark_bad(&k, 5), KS_OK);		/* also drops the request */
	T_CHECK(!ks_find(&k, 5));
	T_EQ(k.ctl.oneshot, AXO_NONE);
	/* gate 5: a generation that does not fit writes nothing */
	memcpy(copy, img, SIZE);
	memset(&m, 0, sizeof(m));
	m.kind = AXK_KERNEL;
	m.name = "unix";
	m.data = img;			/* any bytes */
	m.size = SIZE - 100000;
	memset(&ng, 0, sizeof(ng));
	ng.head = "line k46\n";
	ng.n = 1;
	ng.m = &m;
	writes = 0;
	T_EQ(ks_commit(&k, &ng, &id), KS_EREFUSE);
	T_EQ(k.gate, 5);
	T_EQ(writes, 0);
	T_CHECK(memcmp(copy, img, SIZE) == 0);
	/* loader-install: the new primary on trial, the old one secondary;
	 * mark-good after a boot through it accepts it */
	T_EQ(ks_loader_install(&k, boot2b, sizeof(boot2b), 2, 0), KS_OK);
	T_CHECK(k.hdr.flags & AXF_LDRTRIAL);
	T_EQ(k.hdr.boot2[0].len, sizeof(boot2b));
	T_EQ(k.hdr.boot2[1].len, sizeof(boot2a));
	T_CHECK(memcmp(img + AX_BOOT2_B_OFF, boot2a, sizeof(boot2a)) == 0);
	T_EQ(ks_mark_good(&k, k.ctl.default_gen, 0), KS_OK);	/* secondary ran */
	T_CHECK(k.hdr.flags & AXF_LDRTRIAL);
	T_EQ(ks_mark_good(&k, k.ctl.default_gen, 1), KS_OK);
	T_CHECK(!(k.hdr.flags & AXF_LDRTRIAL));
	/* the journal: an interrupted commit is reported and cleared */
	strcpy(jrn, "commit 42");
	T_EQ(ks_open(&k), KS_OK);
	T_CHECK(strstr(k.msg, "generation 42 was interrupted") != 0);
	T_EQ(jrn[0], 0);
	retries();
	powercuts();
	free(img);
}
