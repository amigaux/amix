/*
 * lsstore.c -- read a boot store back and verify it: header, control block,
 * every manifest and every member the loader would load.
 *
 * usage: lsstore IMAGE [OFFSET] [VOLUME2 ...]   (further volumes at offset 0)
 *        lsstore -C DIR                         a CD tree from mkstore -C:
 *                                               DIR/BOOT/K30 and DIR/BOOT/K46
 *
 * Exit status 0 when everything verifies, 1 otherwise.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "crc32.h"
#include "store.h"
#include "manifest.h"
#include "inflate.h"

static ax_u32 tab[256];
static FILE *img, *volimg[8];
static unsigned long base;
static int bad, nvolimg = 1;
static ax_u32 storesize;	/* from the header: where a volume ends */
static char cddir[1024];	/* -C: the line directory being listed */

static void rdv(int vol, ax_u32 off, void *buf, ax_u32 len);

/* -C: read exactly len bytes of the file cddir/name; 0 or -1 */
static int
rdfile(const char *name, void *buf, ax_u32 len)
{
	char path[1100];
	FILE *f;
	int rc;

	sprintf(path, "%s/%s", cddir, name);
	memset(buf, 0, len);
	if (!(f = fopen(path, "rb"))) {
		printf("    %s: missing\n", path);
		return -1;
	}
	rc = fread(buf, 1, len, f) == len && getc(f) == EOF ? 0 : -1;
	fclose(f);
	if (rc)
		printf("    %s: not %lu bytes\n", path, (unsigned long)len);
	return rc;
}

/* a member's stored bytes, from its extent or (CD) its file; 0 or -1 */
static int
stored(const struct ax_member *mb, void *buf)
{
	ax_u32 vol = mb->vol, off = mb->at, left = mb->stored, n;
	unsigned char *b = buf;

	if (mb->file)
		return rdfile(mb->file, buf, mb->stored);
	for (;;) {	/* past the end of a volume: on at AX_VOLN_DATA of the next */
		if (off >= storesize)
			return -1;
		n = storesize - off < left ? storesize - off : left;
		rdv(vol, off, b, n);
		b += n;
		left -= n;
		if (!left)
			return 0;
		vol++;
		off = AX_VOLN_DATA;
	}
}

static void
rdv(int vol, ax_u32 off, void *buf, ax_u32 len)
{
	FILE *f = vol <= 1 ? img : vol <= nvolimg ? volimg[vol - 1] : 0;
	unsigned long b = vol <= 1 ? base : 0;

	memset(buf, 0, len);
	if (!f) {
		fprintf(stderr, "lsstore: volume %d not given\n", vol);
		exit(1);
	}
	if (fseek(f, (long)(b + off), SEEK_SET) != 0 || fread(buf, 1, len, f) != len) {
		fprintf(stderr, "lsstore: short read at %d:0x%lx\n", vol, (unsigned long)off);
		exit(1);
	}
}

#define rd(off, buf, len) rdv(1, off, buf, len)

static const char *
statename(int s)
{
	static const char *n[] = { "free", "pristine", "good", "trial", "bad" };
	return s >= 0 && s <= 4 ? n[s] : "?";
}

static void
member(const char *what, const struct ax_member *mb)
{
	unsigned char *p;
	ax_u32 crc;

	if (!mb->has_at && !mb->file) {
		printf("    %-7s %-12s %8lu  path %s\n", what, mb->name, (unsigned long)mb->size,
		       mb->path ? mb->path : "-");
		return;
	}
	p = malloc(mb->size ? mb->size : 1);
	if (mb->z == AXZ_DEFLATE) {
		static struct ax_inflate st;
		unsigned char *zp = malloc(mb->stored ? mb->stored : 1);
		ax_u32 got = 0;

		if (stored(mb, zp) != 0 ||
		    ax_inflate(&st, p, mb->size, &got, zp, mb->stored) != AXI_OK || got != mb->size) {
			printf("    %-7s %-12s inflate FAILED\n", what, mb->name);
			bad = 1;
			free(zp);
			free(p);
			return;
		}
		free(zp);
	} else if (stored(mb, p) != 0) {
		printf("    %-7s %-12s unreadable\n", what, mb->name);
		bad = 1;
		free(p);
		return;
	}
	crc = ax_crc32(tab, p, mb->size);
	free(p);
	if (mb->file)
		printf("    %-7s %-12s %8lu  file %s%s  crc %08lx %s\n", what, mb->name,
		       (unsigned long)mb->size, mb->file,
		       mb->z == AXZ_DEFLATE ? " (deflate)" : "", (unsigned long)crc,
		       crc == mb->crc ? "ok" : "BAD");
	else
		printf("    %-7s %-12s %8lu  at %u:0x%lx%s%s  crc %08lx %s\n", what, mb->name,
		       (unsigned long)mb->size, mb->vol, (unsigned long)mb->at,
		       mb->z == AXZ_DEFLATE ? " (deflate)" : "",
		       mb->at + mb->stored > storesize ? " (on to the next volume)" : "",
		       (unsigned long)crc, crc == mb->crc ? "ok" : "BAD");
	if (crc != mb->crc)
		bad = 1;
}

static void
control(int which, const struct ax_ctl *c)
{
	printf("control %c: seq %lu, default %lu, trial %lu, one-shot %u, %u generation(s), "
	       "console%s%s, menu %u ds\n",
	       "AB"[which], (unsigned long)c->seq, (unsigned long)c->default_gen,
	       (unsigned long)c->trial_gen, c->oneshot, c->ngen,
	       (c->console & AXC_SERIAL) ? " serial" : "", (c->console & AXC_SCREEN) ? " screen" : "",
	       c->menu_ds);
}

/* every generation of c: manifest from the store, or (cd) G<id>.GMF */
static void
generations(const struct ax_ctl *c, int cd)
{
	static struct ax_manifest m;
	char *man, name[24];
	int i, j, rc, errline;

	for (i = 0; i < c->ngen; i++) {
		const struct ax_gen *g = &c->gen[i];

		man = malloc(g->man_len ? g->man_len : 1);
		if (cd) {
			sprintf(name, "G%lu.GMF", (unsigned long)g->id);
			printf("  generation %lu (%s), manifest %lu bytes, %s\n", (unsigned long)g->id,
			       statename(g->state), (unsigned long)g->man_len, name);
			if (rdfile(name, man, g->man_len) != 0) {
				bad = 1;
				free(man);
				continue;
			}
		} else {
			printf("  generation %lu (%s), manifest %lu bytes at 0x%lx\n", (unsigned long)g->id,
			       statename(g->state), (unsigned long)g->man_len, (unsigned long)g->man_off);
			rdv(g->volume ? g->volume : 1, g->man_off, man, g->man_len);
		}
		if (ax_crc32(tab, (ax_u8 *)man, g->man_len) != g->man_crc) {
			printf("    manifest CRC BAD\n");
			bad = 1;
			free(man);
			continue;
		}
		rc = ax_manifest_parse(tab, man, g->man_len, &m, &errline);
		if (rc != AXM_OK) {
			printf("    manifest refused (%d) at line %d\n", rc, errline);
			bad = 1;
			free(man);
			continue;
		}
		if (m.generation != g->id) {
			printf("    manifest says generation %lu\n", (unsigned long)m.generation);
			bad = 1;
		}
		printf("    line %s%s%s\n", m.line, m.rootfs ? ", rootfs " : "", m.rootfs ? m.rootfs : "");
		member("kernel", &m.kernel);
		for (j = 0; j < m.nmod; j++)
			member("module", &m.mod[j]);
		if (m.has_ramdisk)
			member("ramdisk", &m.ramdisk);
		if (cd && m.line && strcmp(m.line, strstr(cddir, "/K30") ? "k30" : "k46")) {
			printf("    line %s in the wrong directory\n", m.line);
			bad = 1;
		}
		free(man);
	}
}

/* lsstore -C DIR */
static int
cdtree(const char *dir)
{
	static const char *const sub[2] = { "K30", "K46" };
	static struct ax_ctl c;
	unsigned char blk[2048];
	char path[1100];
	FILE *f;
	int k, found = 0;

	ax_crc32_init(tab);
	for (k = 0; k < 2; k++) {
		sprintf(cddir, "%s/BOOT/%s", dir, sub[k]);
		sprintf(path, "%s/CONTROL", cddir);
		if (!(f = fopen(path, "rb")))
			continue;
		fclose(f);
		found = 1;
		printf("%s:\n", cddir);
		if (rdfile("CONTROL", blk, sizeof(blk)) != 0 || ax_ctl_parse(tab, blk, &c) != AX_OK) {
			printf("control: not a valid control block\n");
			bad = 1;
			continue;
		}
		control(0, &c);
		generations(&c, 1);
	}
	if (!found) {
		printf("lsstore: %s/BOOT has no K30 or K46 control file\n", dir);
		bad = 1;
	}
	printf(bad ? "lsstore: FAILED\n" : "lsstore: ok\n");
	return bad;
}

int
main(int argc, char **argv)
{
	unsigned char hb[2][512], cb[2][2048], *b2;
	struct ax_header h;
	static struct ax_ctl c;
	int which, i, rc;

	if (argc == 3 && !strcmp(argv[1], "-C"))
		return cdtree(argv[2]);
	if (argc < 2 || argc > 9) {
		fprintf(stderr, "usage: lsstore IMAGE [OFFSET] [VOLUME2 ...] | lsstore -C DIR\n");
		return 2;
	}
	base = argc >= 3 ? strtoul(argv[2], 0, 0) : 0;
	if (!(img = fopen(argv[1], "rb"))) {
		perror(argv[1]);
		return 1;
	}
	volimg[0] = img;
	for (i = 3; i < argc; i++)
		if (!(volimg[nvolimg++] = fopen(argv[i], "rb"))) {
			perror(argv[i]);
			return 1;
		}
	ax_crc32_init(tab);

	rd(AX_HDR_A_OFF, hb[0], 512);
	rd(AX_HDR_B_OFF, hb[1], 512);
	which = ax_hdr_pick(tab, hb[0], hb[1], &h);
	if (which < 0) {
		printf("header: no valid copy\n");
		return 1;
	}
	storesize = h.store_size;
	printf("header %c: seq %lu, store %lu bytes, flags 0x%lx, volume %u/%u\n", "AB"[which],
	       (unsigned long)h.seq, (unsigned long)h.store_size, (unsigned long)h.flags,
	       h.volume, h.nvolumes);
	for (i = 0; i < 2; i++) {
		if (!h.boot2[i].len) {
			printf("  boot2[%d]: none\n", i);
			continue;
		}
		b2 = malloc(h.boot2[i].len);
		rd(h.boot2[i].off, b2, h.boot2[i].len);
		rc = ax_crc32(tab, b2, h.boot2[i].len) == h.boot2[i].crc;
		free(b2);
		printf("  boot2[%d]: %lu bytes at 0x%lx, version %lu, crc %s\n", i,
		       (unsigned long)h.boot2[i].len, (unsigned long)h.boot2[i].off,
		       (unsigned long)h.boot2[i].ver, rc ? "ok" : "BAD");
		if (!rc)
			bad = 1;
	}
	rd(h.ctl_off[0], cb[0], 2048);
	rd(h.ctl_off[1], cb[1], 2048);
	which = ax_ctl_pick(tab, cb[0], cb[1], &c);
	if (which < 0) {
		printf("control block: no valid copy\n");
		return 1;
	}
	control(which, &c);
	generations(&c, 0);
	fclose(img);
	printf(bad ? "lsstore: FAILED\n" : "lsstore: ok\n");
	return bad;
}
