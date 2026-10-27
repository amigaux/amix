/*
 * knode.c -- the sd disk nodes of a four-card kernel (C4-1 §2.4, C2-4 §14).
 *
 * When an installed kernel's sidecar says sdcards=4 (C2-3 §2), /dev/dsk
 * and /dev/rdsk hold c0..c1f d0 s0..s7 (block 18, character 40, the minor
 * of C4-1 §2.1) and none of core's c<N>d1s<S> names: their minors have
 * bit 7 set, which a four-card kernel reads as the card's high bit, so
 * c6d1s0 would open the disk c16d0s0 names.  The set covers all four
 * cards whatever the board set, so a board added or removed needs no node.
 *
 * The package database follows, as firstboot's step 4d did it: the d1
 * names out of core and the c10-c1f nodes into it, by APKG's removef and
 * installf (the stock ones take a bus error on the 68060), from /tmp, on
 * the running box only.  Under -R the nodes are made and the registration
 * is left to `kbootset nodes` on the booted box.  The host build writes
 * nothing: it prints what it would do, for tests/host/knode.sh.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#ifdef KS_SYNC
#include <unistd.h>
#include <sys/sysmacros.h>
#endif
#include "knode.h"

#define SD_BMAJ		18
#define SD_CMAJ		40
#define APKG		"/usr/apkg/bin/"
#define NODELIST	"/tmp/kbootset.nodes"

/* the minor of disk N (8 x card + unit), slice s (C4-1 §2.1) */
static unsigned
minor_of(unsigned n, unsigned s)
{
	unsigned card = n >> 3;

	return (card & 1) << 3 | (card >> 1) << 7 | s << 4 | (n & 7);
}

/* 4 when an installed kernel's sidecar says sdcards=4, else 2 */
static int
sdcards(const char *pre)
{
	static char path[1000], line[256];
	static const char *const lines[] = { "30", "46" };
	FILE *f;
	int i, n = 2;

	for (i = 0; i < 2; i++) {
		sprintf(path, "%.900s/stand/k%s/kabi", pre, lines[i]);
		if (!(f = fopen(path, "r")))
			continue;
		while (fgets(line, sizeof line, f))
			if (!strncmp(line, "sdcards=", 8) && atoi(line + 8) == 4)
				n = 4;
		fclose(f);
	}
	return n;
}

static int
node_ok(const char *path, int blk, unsigned mn)
{
	struct stat st;

	if (stat(path, &st) != 0)
		return 0;
#ifdef KS_SYNC
	return (st.st_mode & S_IFMT) == (blk ? S_IFBLK : S_IFCHR) &&
	    st.st_rdev == makedevice(blk ? SD_BMAJ : SD_CMAJ, mn);
#else
	(void)blk, (void)mn;
	return 1;	/* the host's trees are plain files: present is enough */
#endif
}

/* core's registration: *d1 = it still names d1 nodes; returns whether it
 * names the c10-c1f set (its last node, as firstboot checked); -1 when
 * there is no package database */
static int
registered(const char *pre, int *d1)
{
	static char path[1000], line[1024];
	FILE *f;
	int c1x = 0;
	char *p;

	*d1 = 0;
	sprintf(path, "%.900s/var/sadm/install/contents", pre);
	if (!(f = fopen(path, "r")))
		return -1;
	while (fgets(line, sizeof line, f)) {
		p = !strncmp(line, "/dev/dsk/c", 10) ? line + 10 :
		    !strncmp(line, "/dev/rdsk/c", 11) ? line + 11 : 0;
		if (p && *p && strchr("0123456789abcdef", *p) && !strncmp(p + 1, "d1s", 3))
			*d1 = 1;
		if (!strncmp(line, "/dev/rdsk/c1fd0s7 ", 18))
			c1x = 1;
	}
	fclose(f);
	return c1x;
}

#ifdef KS_SYNC
/* core's d1 names out, 16 paths a call (removef's stdin form keeps each
 * line's newline and matches nothing), then the c10-c1f nodes in */
static void
reg_core(int d1, int c1x)
{
	static char cmd[1200];
	FILE *f;
	unsigned n, s;
	int i;

	for (n = 0; d1 && n < 16; n++) {
		i = sprintf(cmd, "cd /tmp && " APKG "removef core");
		for (s = 0; s < 8; s++)
			i += sprintf(cmd + i, " /dev/dsk/c%xd1s%u /dev/rdsk/c%xd1s%u", n, s, n, s);
		strcpy(cmd + i, " >/dev/null 2>&1");
		system(cmd);
	}
	if (d1)
		system("cd /tmp && " APKG "removef -f core >/dev/null 2>&1");
	if (c1x || !(f = fopen(NODELIST, "w")))
		return;
	for (n = 16; n < 32; n++)
		for (s = 0; s < 8; s++)
			fprintf(f, "/dev/dsk/c%xd0s%u b %d %u 0600 root root\n"
				"/dev/rdsk/c%xd0s%u c %d %u 0600 root root\n",
				n, s, SD_BMAJ, minor_of(n, s), n, s, SD_CMAJ, minor_of(n, s));
	fclose(f);
	system("cd /tmp && " APKG "installf core - < " NODELIST " >/dev/null 2>&1 && "
	       APKG "installf -f core >/dev/null 2>&1");
	unlink(NODELIST);
}
#endif

int
kb_nodes(const char *root, int make, char *msg)
{
	static char path[1000];
	const char *pre = strcmp(root, "/") ? root : "";
	int box = !*pre, missing = 0, d1left = 0, reg, d1reg, bad = 0, blk;
	unsigned n, s;

	if (sdcards(pre) != 4) {
		sprintf(msg, "nodes: no four-card kernel installed (no sdcards=4 in /stand/k30/kabi or "
			"/stand/k46/kabi): core's nodes stand");
		return KB_ND_TWO;
	}
	reg = registered(pre, &d1reg);
	for (n = 0; n < 16; n++)
		for (s = 0; s < 8; s++)
			for (blk = 0; blk < 2; blk++) {
				struct stat st;

				sprintf(path, "%.900s/dev/%s/c%xd1s%u", pre, blk ? "dsk" : "rdsk", n, s);
				if (stat(path, &st) != 0)
					continue;
				d1left++;
				if (!make)
					continue;
#ifdef KS_SYNC
				if (unlink(path) != 0)
					bad++;
#else
				printf("would remove %s\n", path + strlen(pre));
#endif
			}
	for (n = 0; n < 32; n++)
		for (s = 0; s < 8; s++)
			for (blk = 1; blk >= 0; blk--) {
				sprintf(path, "%.900s/dev/%s/c%xd0s%u", pre, blk ? "dsk" : "rdsk", n, s);
				if (node_ok(path, blk, minor_of(n, s)))
					continue;
				missing++;
				if (!make)
					continue;
#ifdef KS_SYNC
				unlink(path);
				if (mknod(path, (blk ? S_IFBLK : S_IFCHR) | 0600,
					  makedevice(blk ? SD_BMAJ : SD_CMAJ, minor_of(n, s))) != 0 ||
				    chown(path, 0, 0) != 0)
					bad++;
#else
				printf("would make %s %c %d %u\n", path + strlen(pre), blk ? 'b' : 'c',
				       blk ? SD_BMAJ : SD_CMAJ, minor_of(n, s));
#endif
			}
	if (!missing && !d1left && reg != 0 && !d1reg) {
		sprintf(msg, "nodes: the four-card set is complete (c0-c1f d0 s0-s7, no d1 nodes)");
		return KB_ND_COMPLETE;
	}
	if (!make) {
		sprintf(msg, "nodes: %d of the four-card set missing or wrong, %d d1 nodes left%s: "
			"run kbootset nodes", missing, d1left,
			reg == 0 || d1reg ? ", core's registration not done" : "");
		return KB_ND_MISSING;
	}
#ifdef KS_SYNC
	if (box && reg >= 0 && (reg == 0 || d1reg)) {
		reg_core(d1reg, reg);
		reg = registered(pre, &d1reg);
	}
	if (bad) {
		sprintf(msg, "nodes: %d of %d nodes could not be made or removed", bad, missing + d1left);
		return KB_ND_FAIL;
	}
	if (box && reg >= 0 && (reg == 0 || d1reg)) {
		sprintf(msg, "nodes: made %d, removed %d d1 nodes; WARNING: core's registration failed "
			"(APKG's installf, removef)", missing, d1left);
		return KB_ND_FAIL;
	}
	sprintf(msg, "nodes: made %d, removed %d d1 nodes; %s", missing, d1left,
		reg < 0 ? "no package database" : box ? "registered to core" :
		reg == 0 || d1reg ? "the registration is the booted box's (kbootset nodes there)" :
		"registered to core");
#else
	(void)bad;
	if (box || reg < 0 || (reg != 0 && !d1reg))
		sprintf(msg, "nodes: the host build writes nothing: %d to make, %d d1 nodes to remove",
			missing, d1left);
	else
		sprintf(msg, "nodes: the host build writes nothing: %d to make, %d d1 nodes to remove, "
			"core's registration left to the booted box", missing, d1left);
#endif
	return KB_ND_MADE;
}
