/*
 * axsim.c -- test helper: the loader's decisions and writes on a boot store,
 * boot after boot, on the host.  For each boot it applies boot1's
 * loader-trial rule (records the start in the tally block, or takes the
 * secondary boot2: B4) and boot2's selection (try-once, one-shot, the L8
 * fallback), writes the control block as boot2 does -- the inactive copy,
 * sequence + 1 -- and prints the serial lines the loader prints for it.
 * The rules are loader/common's own (store.c, select.c); the menu is not
 * simulated (no input), and the kernel is assumed to start but never to
 * mark anything good, as a static 1.0 kernel does.  Used to state the
 * expected outcome of the M-LD4 lifecycle rows (docs/plan/stage-1.md S1-22).
 *
 * usage: axsim IMAGE OFFSET BOOTS     the image is written in place
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include "crc32.h"
#include "store.h"
#include "select.h"

static ax_u32 tab[256];
static FILE *img;
static unsigned long base;

static void
io(int wr, ax_u32 off, ax_u8 *buf, ax_u32 len)
{
	if (fseek(img, (long)(base + off), SEEK_SET) != 0 ||
	    (wr ? fwrite(buf, 1, len, img) : fread(buf, 1, len, img)) != len) {
		fprintf(stderr, "axsim: I/O error at 0x%lx\n", (unsigned long)off);
		exit(1);
	}
}

int
main(int argc, char **argv)
{
	static ax_u8 hb[2][512], cb[2][2048], tb[2048];
	static struct ax_ctl c, nc;
	struct ax_header h;
	struct ax_tally t;
	struct ax_sel s;
	int boots, k, which, wt, sec, tv;

	if (argc != 4)
		return 2;
	base = strtoul(argv[2], 0, 0);
	boots = atoi(argv[3]);
	if (!(img = fopen(argv[1], "r+b"))) {
		perror(argv[1]);
		return 1;
	}
	ax_crc32_init(tab);
	io(0, AX_HDR_A_OFF, hb[0], 512);
	io(0, AX_HDR_B_OFF, hb[1], 512);
	if (ax_hdr_pick(tab, hb[0], hb[1], &h) < 0) {
		fprintf(stderr, "axsim: no valid store header\n");
		return 1;
	}
	for (k = 1; k <= boots; k++) {
		printf("boot %d:\n", k);
		/* boot1 */
		tv = 0;
		if (h.tally_off) {
			io(0, h.tally_off, tb, 2048);
			tv = ax_tally_parse(tab, tb, &t) == AX_OK;
		}
		sec = ax_ldrtrial_choice(&h, tv, &t, &wt);
		if (wt) {
			t.magic = AX_MAGIC_TALLY;
			t.hdr_seq = h.seq;
			t.attempts = 1;
			ax_tally_write(tab, &t, tb);
			io(1, h.tally_off, tb, 2048);
		}
		printf("  amix-boot 1: ... boot1 choice %x\n", sec ? 0x201 : 0);
		if (sec)
			printf("  amix-boot: B4 new loader already started once, previous loader used\n");
		/* boot2 */
		io(0, h.ctl_off[0], cb[0], 2048);
		io(0, h.ctl_off[1], cb[1], 2048);
		if ((which = ax_ctl_pick(tab, cb[0], cb[1], &c)) < 0) {
			printf("  amix-boot: no valid control block\n");
			return 1;
		}
		ax_select(&c, (h.flags & AXF_READONLY) != 0, &s);
		if (s.failed_trial)
			printf("  amix-boot: L8 trial generation did not reach multi-user (generation %lu)\n",
			       (unsigned long)s.failed_trial);
		if (s.write) {
			ax_select_apply(&c, &s, &nc);
			ax_ctl_write(tab, &nc, cb[0]);
			io(1, h.ctl_off[which ^ 1], cb[0], 2048);
			printf("  (control block copy %c written, seq %lu)\n", "AB"[which ^ 1],
			       (unsigned long)nc.seq);
		}
		if (!s.n) {
			printf("  amix-boot: nothing loaded (the menu would open)\n");
			continue;
		}
		printf("  amix-boot: generation %lu, kernel ...\n", (unsigned long)s.order[0]);
		if (s.devload)
			printf("  amix-boot: DEVELOPMENT LOAD: modules outside the manifest allowed this boot\n");
		if (s.safe)
			printf("  amix-boot: safe mode\n");
	}
	fclose(img);
	return 0;
}
