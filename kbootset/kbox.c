/*
 * kbox.c -- kbootset on the running box (see kbox.h).
 *
 * Raw disks are named /dev/rdsk/c<X>d0s<S>: X = 8 × card + unit in hex
 * (c6 = card 0, unit 6; ce = card 1, unit 6), S the slice, s0 the whole
 * disk.  Slice S is the S-th PART block of the disk's RDB partition list
 * (sdpart.c; amix-installng/tools/lib/rdb.py).  A store is opened through
 * its own slice, never the whole disk at an offset: a raw read far into a
 * whole-disk node hangs on a stock kernel (grimoire quirks §62).
 *
 * KBOOTSET_DEVROOT (default /dev/rdsk) and KBOOTSET_KINFO (default
 * /dev/kinfo) move both, for the host tests.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "crc32.h"
#include "kbox.h"

#define BLK	512UL
#define RDBSCAN	64		/* the RDSK block is looked for in blocks 0..63 */
#define MAXPART	16

static ax_u32
get32(const ax_u8 *p)
{
	return ((ax_u32)p[0] << 24) | ((ax_u32)p[1] << 16) | ((ax_u32)p[2] << 8) | p[3];
}

static void
str(char *out, const ax_u8 *p, int n)
{
	int i;

	for (i = 0; i < n && p[i]; i++)
		out[i] = (char)p[i];
	out[i] = 0;
}

int
kb_kinfo_read(const char *path, struct kb_kinfo *ki)
{
	static ax_u8 r[2048];
	FILE *f = fopen(path, "rb");
	ax_u32 len, sum, i;
	size_t n;

	memset(ki, 0, sizeof(*ki));
	if (!f)
		return -1;
	n = fread(r, 1, sizeof(r), f);
	fclose(f);
	if (n < 540 || get32(r) != 0x4B494631UL || (get32(r + 4) >> 16) != 2)
		return -1;
	len = get32(r + 4) & 0xFFFF;
	if (len < 540 || len > n || len % 4)
		return -1;
	for (sum = 0, i = 0; i < len; i += 4)
		sum += get32(r + i);
	if (sum != 0)
		return -1;
	ki->cpu = get32(r + 12);
	ki->line = get32(r + 16);
	ki->attn = get32(r + 20);
	str(ki->kabi, r + 24, 24);
	str(ki->build, r + 48, 32);
	ki->flags = get32(r + 80);
	if ((ki->flags & 1) && get32(r + 84) == 0x41584C31UL) {	/* AXL1 */
		const ax_u8 *a = r + 84;

		ki->has_axl1 = 1;
		ki->boot1_choice = get32(a + 16);
		ki->gen_id = get32(a + 28);
		ki->gen_state = get32(a + 32);
		ki->dev_unit = get32(a + 44);
		ki->dev_start = get32(a + 48);
		ki->dev_base = get32(a + 52);
		ki->dev_id = get32(a + 56);
		ki->root_kind = get32(a + 60);
		ki->root_id = get32(a + 64);
		ki->root_base = get32(a + 68);
		ki->root_unit = get32(a + 72);
		ki->root_slice = get32(a + 76);
		str(ki->rootfs, a + 100, 16);
	}
	ki->nboards = (int)get32(r + 264);
	if (ki->nboards > KB_MAXBOARD)
		ki->nboards = KB_MAXBOARD;
	for (i = 0; i < (ax_u32)ki->nboards; i++) {
		const ax_u8 *b = r + 268 + 12 * i;

		ki->board[i].id = ((ax_u32)b[0] << 24) | ((ax_u32)b[1] << 16) | ((ax_u32)b[2] << 8);
		ki->board[i].base = get32(b + 4);
		ki->board[i].size = get32(b + 8);
	}
	ki->ncards = (int)get32(r + 460);
	if (ki->ncards > KB_MAXCARD)
		ki->ncards = KB_MAXCARD;
	for (i = 0; i < (ax_u32)ki->ncards; i++) {
		const ax_u8 *c = r + 464 + 16 * i;

		ki->card[i].k = get32(c);
		ki->card[i].id = get32(c + 4);
		ki->card[i].base = get32(c + 8);
		ki->card[i].flags = get32(c + 12);
	}
	ki->fast = get32(r + 528);
	ki->chip = get32(r + 532);
	ki->nmods = (int)get32(r + 536);
	if (ki->nmods > KB_MAXMODS || 540 + 32 * (ax_u32)ki->nmods > len)
		ki->nmods = 0;
	for (i = 0; i < (ax_u32)ki->nmods; i++)
		str(ki->mods[i], r + 540 + 32 * i, 24);
	return 0;
}

void
kb_matchkey(ax_u32 id, char out[48])
{
	static const char *const mobo[] = { "", "a3000-wd", "gayle", "a4000t-710", "z3660-window" };

	if (id >> 16)
		sprintf(out, "zorro:%04lx:%02lx", (unsigned long)(id >> 16), (unsigned long)((id >> 8) & 0xFF));
	else if (id >= 1 && id <= 4)
		sprintf(out, "mobo:%s", mobo[id]);
	else
		out[0] = 0;
}

/* the card table entry of a controller: by id and base on a Zorro board,
 * by the motherboard flag when the loader saw no board (base and id 0) */
static int
card_of(const struct kb_kinfo *ki, ax_u32 id, ax_u32 base)
{
	int i;

	for (i = 0; i < ki->ncards; i++)
		if (id ? (ki->card[i].id == id && ki->card[i].base == base) :
			 (ki->card[i].flags & 1) != 0)
			return i;
	return -1;
}

void
kb_kinfo_facts(const struct kb_kinfo *ki, struct kb_facts *f)
{
	int c;

	if (!f->line && (ki->line == 30 || ki->line == 46))
		f->line = (int)ki->line;
	if (!f->mem)
		f->mem = ki->fast;
	if (ki->has_axl1) {
		if (!f->bootdev[0] && (c = card_of(ki, ki->dev_id, ki->dev_base)) >= 0)
			kb_matchkey(ki->card[c].id, f->bootdev);
		if (!f->rootdev[0] && (ki->root_kind & 0xFF) == 1) {
			if ((ki->root_kind & 0x100) || !ki->root_id) {
				if ((c = card_of(ki, 0, 0)) >= 0)
					kb_matchkey(ki->card[c].id, f->rootdev);
			} else {
				kb_matchkey(ki->root_id, f->rootdev);
			}
		}
		if (!f->rootfs[0] && ki->rootfs[0])
			sprintf(f->rootfs, "%.15s", ki->rootfs);
	}
}

int
kb_bootset_get(const char *path, const char *key, char *out, int cap)
{
	FILE *f = fopen(path, "r");
	char line[512];
	size_t kl = strlen(key);
	int found = -1;

	out[0] = 0;
	if (!f)
		return -1;
	while (fgets(line, sizeof(line), f)) {
		char *p = line;

		line[strcspn(line, "\n")] = 0;
		while (*p == ' ' || *p == '\t')
			p++;
		if (!strncmp(p, key, kl) && p[kl] == '=') {
			sprintf(out, "%.*s", cap - 1, p + kl + 1);
			found = 0;
		}
	}
	fclose(f);
	return found;
}

void
kb_bootset_facts(const char *path, struct kb_facts *f)
{
	char v[128];

	if (!f->line && kb_bootset_get(path, "line", v, sizeof(v)) == 0)
		f->line = atoi(v);
	if (!f->bootdev[0])
		kb_bootset_get(path, "bootdev", f->bootdev, sizeof(f->bootdev));
	if (!f->rootdev[0])
		kb_bootset_get(path, "rootdev", f->rootdev, sizeof(f->rootdev));
	if (!f->rootfs[0])
		kb_bootset_get(path, "rootfs", f->rootfs, sizeof(f->rootfs));
	if (!f->mem && kb_bootset_get(path, "mem", v, sizeof(v)) == 0)
		f->mem = (ax_u32)strtoul(v, 0, 0);
}

/* rewrite store= and store-id=, keeping every other line */
static int
bootset_store(const char *path, const char *dev, ax_u32 set_id)
{
	char tmp[1100], line[512];
	FILE *in = fopen(path, "r"), *out;

	sprintf(tmp, "%.1000s.new", path);
	if ((out = fopen(tmp, "w")) == 0) {
		if (in)
			fclose(in);
		return -1;
	}
	if (!in)
		fputs("# /etc/default/bootset -- read by kbootset and apkg (40 §2.2, §5; C2-4 §6)\n", out);
	while (in && fgets(line, sizeof(line), in))
		if (strncmp(line, "store=", 6) && strncmp(line, "store-id=", 9))
			fputs(line, out);
	if (in)
		fclose(in);
	fprintf(out, "store=%s\nstore-id=%08lx\n", dev, (unsigned long)set_id);
	if (fclose(out) != 0 || rename(tmp, path) != 0) {
		remove(tmp);
		return -1;
	}
	return 0;
}

static const char *
devroot(void)
{
	const char *r = getenv("KBOOTSET_DEVROOT");

	return r && *r ? r : "/dev/rdsk";
}

/* the store header in a raw slice: its set id, or 0 when there is none */
static ax_u32
header_of(const ax_u32 *crctab, const char *dev)
{
	ax_u8 h[1024];
	struct ax_header hd;
	FILE *f = fopen(dev, "rb");
	size_t n;

	if (!f)
		return 0;
	n = fseek(f, (long)AX_HDR_A_OFF, SEEK_SET) == 0 ? fread(h, 1, sizeof(h), f) : 0;
	fclose(f);
	if (n != sizeof(h) || ax_hdr_pick(crctab, h, h + AX_HDR_SIZE, &hd) < 0)
		return 0;
	return hd.set_id ? hd.set_id : 0xFFFFFFFFUL;
}

struct part {
	int slice;
	ax_u32 start, dostype;
};

/* the RDB partition list of the disk cX (X = 8 × card + unit): the slice,
 * byte start and DosType of each; the number of partitions, -1 none */
static int
rdb_parts(ax_u32 x, struct part *p)
{
	static ax_u8 blk[RDBSCAN * BLK];
	char path[1100];
	FILE *f;
	ax_u32 next, b;
	int n = 0, i;
	size_t got;

	sprintf(path, "%.1000s/c%lxd0s0", devroot(), (unsigned long)x);
	if ((f = fopen(path, "rb")) == 0)
		return -1;
	got = fread(blk, 1, sizeof(blk), f);
	for (b = 0; b < RDBSCAN && (b + 1) * BLK <= got; b++)
		if (!memcmp(blk + b * BLK, "RDSK", 4))
			break;
	if (b == RDBSCAN || (b + 1) * BLK > got) {
		fclose(f);
		return -1;
	}
	next = get32(blk + b * BLK + 28);	/* rdb_PartitionList */
	while (next != 0xFFFFFFFFUL && n < MAXPART) {
		ax_u8 pb[BLK];
		const ax_u8 *de;

		if (fseek(f, (long)(next * BLK), SEEK_SET) != 0 || fread(pb, 1, BLK, f) != BLK ||
		    memcmp(pb, "PART", 4))
			break;
		de = pb + 128;
		p[n].slice = n + 1;
		p[n].start = get32(de + 36) * get32(de + 12) * get32(de + 20) * get32(de + 4) * 4;
		p[n].dostype = get32(de + 64);
		n++;
		for (i = 0; i < n - 1; i++)
			if (p[i].start == p[n - 1].start)
				n = MAXPART;	/* a loop: stop */
		next = get32(pb + 16);
	}
	fclose(f);
	return n;
}

#define UNI0	0x554E4900UL

/* on disk cX: the UNI\0 slice holding a store (at byte start want, when
 * want is not ~0); its device into dev; the number of UNI\0 partitions on
 * the disk into *nuni; 0 found, -1 not */
static int
store_on(const ax_u32 *crctab, ax_u32 x, ax_u32 want, char *dev, int *nuni, ax_u32 *set_id)
{
	struct part p[MAXPART];
	int n = rdb_parts(x, p), i, found = -1;
	char path[1100];

	*nuni = 0;
	for (i = 0; i < n; i++) {
		if (p[i].dostype != UNI0)
			continue;
		(*nuni)++;
		if (want != 0xFFFFFFFFUL && p[i].start != want)
			continue;
		sprintf(path, "%.1000s/c%lxd0s%d", devroot(), (unsigned long)x, p[i].slice);
		if (found < 0 && (*set_id = header_of(crctab, path)) != 0) {
			strcpy(dev, path);
			found = 0;
		}
	}
	return found;
}

int
kb_find_store(struct ks *k, const struct kb_kinfo *ki, int have_kinfo, const char *bootset,
	      char *dev, int *disk, int record)
{
	ax_u32 tab[256], id = 0, want, x, sid, fx = 0;
	char v[1024], cand[1100], first[1100];
	int c, nuni, hits = 0;

	ax_crc32_init(tab);
	k->gate = 0;
	*disk = -1;
	/* 1. the store bootset recorded, if its header still says so */
	if (kb_bootset_get(bootset, "store", v, sizeof(v)) == 0 && v[0]) {
		char sv[32];

		if (kb_bootset_get(bootset, "store-id", sv, sizeof(sv)) == 0 &&
		    (id = header_of(tab, v)) != 0 && id == (ax_u32)strtoul(sv, 0, 16)) {
			strcpy(dev, v);
			return KS_OK;
		}
	}
	want = have_kinfo && ki->has_axl1 ? ki->dev_start : 0xFFFFFFFFUL;
	/* 2. the loader record through the card table */
	if (have_kinfo && ki->has_axl1 && (c = card_of(ki, ki->dev_id, ki->dev_base)) >= 0 &&
	    ki->dev_unit < 8) {
		x = 8 * ki->card[c].k + ki->dev_unit;
		if (store_on(tab, x, want, cand, &nuni, &sid) == 0) {
			*disk = (int)x;
			if (nuni > 1) {
				sprintf(k->msg, "gate 9 (one boot slice): the boot disk c%lxd0 carries %d "
					"UNI\\0 partitions", (unsigned long)x, nuni);
				k->gate = 9;
				return KS_EREFUSE;
			}
			strcpy(dev, cand);
			goto found;
		}
	}
	/* 3. every disk: one UNI\0 slice with a store, at the recorded start */
	for (x = 0; x < 8 * KB_MAXCARD; x++) {
		if (store_on(tab, x, want, cand, &nuni, &sid) != 0)
			continue;
		if (++hits == 1) {
			strcpy(first, cand);
			id = sid;
			fx = x;
			if (nuni > 1) {
				sprintf(k->msg, "gate 9 (one boot slice): the disk c%lxd0 carries %d "
					"UNI\\0 partitions", (unsigned long)x, nuni);
				k->gate = 9;
				return KS_EREFUSE;
			}
		}
	}
	if (hits != 1) {
		if (hits)
			sprintf(k->msg, "gate 8 (boot disk): %d disks hold a boot store%s; name it with --dev",
				hits, want != 0xFFFFFFFFUL ? " at the loader record's partition start" : "");
		else
			sprintf(k->msg, "gate 8 (boot disk): no boot store found%s; name it with --dev",
				want != 0xFFFFFFFFUL ? " at the loader record's partition start" : "");
		k->gate = 8;
		return KS_EREFUSE;
	}
	strcpy(dev, first);
	sid = id;
	*disk = (int)fx;
found:
	if (record && bootset_store(bootset, dev, sid) != 0) {
		sprintf(k->msg, "the boot store is %.120s, but %.120s cannot be written", dev, bootset);
		return KS_EIO;
	}
	return KS_OK;
}
