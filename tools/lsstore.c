/*
 * lsstore.c -- read a boot store back and verify it: header, control block,
 * every manifest and every member the loader would load.
 *
 * usage: lsstore IMAGE [OFFSET]
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

static ax_u32 tab[256];
static FILE *img;
static unsigned long base;
static int bad;

static void
rd(ax_u32 off, void *buf, ax_u32 len)
{
	memset(buf, 0, len);
	if (fseek(img, (long)(base + off), SEEK_SET) != 0 || fread(buf, 1, len, img) != len) {
		fprintf(stderr, "lsstore: short read at 0x%lx\n", (unsigned long)off);
		exit(1);
	}
}

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

	if (!mb->has_at) {
		printf("    %-7s %-12s %8lu  path %s\n", what, mb->name, (unsigned long)mb->size,
		       mb->path ? mb->path : "-");
		return;
	}
	if (mb->z != AXZ_NONE) {
		printf("    %-7s %-12s %8lu  at 0x%lx  (compressed; CRC not checked here)\n", what,
		       mb->name, (unsigned long)mb->size, (unsigned long)mb->at);
		return;
	}
	p = malloc(mb->size ? mb->size : 1);
	rd(mb->at, p, mb->size);
	crc = ax_crc32(tab, p, mb->size);
	free(p);
	printf("    %-7s %-12s %8lu  at 0x%lx  crc %08lx %s\n", what, mb->name,
	       (unsigned long)mb->size, (unsigned long)mb->at, (unsigned long)crc,
	       crc == mb->crc ? "ok" : "BAD");
	if (crc != mb->crc)
		bad = 1;
}

int
main(int argc, char **argv)
{
	unsigned char hb[2][512], cb[2][2048], *b2;
	struct ax_header h;
	static struct ax_ctl c;
	static struct ax_manifest m;
	int which, i, j, errline, rc;
	char *man;

	if (argc < 2 || argc > 3) {
		fprintf(stderr, "usage: lsstore IMAGE [OFFSET]\n");
		return 2;
	}
	base = argc == 3 ? strtoul(argv[2], 0, 0) : 0;
	if (!(img = fopen(argv[1], "rb"))) {
		perror(argv[1]);
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
	printf("control %c: seq %lu, default %lu, trial %lu, one-shot %u, %u generation(s)\n",
	       "AB"[which], (unsigned long)c.seq, (unsigned long)c.default_gen,
	       (unsigned long)c.trial_gen, c.oneshot, c.ngen);
	for (i = 0; i < c.ngen; i++) {
		struct ax_gen *g = &c.gen[i];

		printf("  generation %lu (%s), manifest %lu bytes at 0x%lx\n", (unsigned long)g->id,
		       statename(g->state), (unsigned long)g->man_len, (unsigned long)g->man_off);
		man = malloc(g->man_len);
		rd(g->man_off, man, g->man_len);
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
		free(man);
	}
	fclose(img);
	printf(bad ? "lsstore: FAILED\n" : "lsstore: ok\n");
	return bad;
}
