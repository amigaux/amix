/*
 * mkstore.c -- build a boot store (docs/spec/10-boot-loader.md §4.2) into an
 * image file: the seed of `kbootset --image` (docs/plan/stage-1.md S1-06).
 *
 * usage: mkstore -o IMAGE [-o IMAGE2 ...] [-p OFFSET] [-s SIZE] [-f]
 *                -1 BOOT1.IMG -2 BOOT2.BIN [-b BOOT2B.BIN] [-v LOADERVER]
 *                [-r] [-d DEFAULT] SPEC...
 *
 *   -o IMAGE   image file; created if missing, otherwise written in place.
 *              Give -o once per volume for a multi-volume store (with -f)
 *   -f         floppy profile: read-only, one boot2 and one control block,
 *              packed after boot2; volumes of SIZE bytes (default 901120)
 *              filled in order; a member that runs past the end of a volume
 *              continues on the next (§4.3), a manifest never does
 *   -p OFFSET  byte offset of the boot partition in the image (default 0)
 *   -s SIZE    store (partition) size in bytes (default 64 MiB)
 *   -1 FILE    boot1 bootblock (1024 bytes, from bbframe)
 *   -2 FILE    primary boot2;  -b FILE  secondary boot2 (optional)
 *   -v N       loader version recorded for the boot2 copies (default 1)
 *   -r         read-only medium (no loader trial, no loader writes)
 *   -d ID      default generation (default: the first good or pristine one)
 *   -c WHAT    console: serial, screen or both (default both)
 *   -m DS      menu window in tenths of a second (default 20; 0 = none)
 *
 * or:    mkstore -C DIR [-x AMIX-CDBOOT] [-d DEFAULT] [-c ...] [-m DS] SPEC...
 *
 *   -C DIR     a CD-ROM tree instead of a store (§4.4): each generation goes
 *              to DIR/BOOT/K30 or DIR/BOOT/K46 by its `line` record, with a
 *              read-only control file CONTROL per line, the manifest as
 *              G<id>.GMF and its members as G<id>K.BIN (kernel), G<id>R.BIN
 *              (ramdisk) and G<id>M<nn>.BIN (root modules), named with
 *              file= -- ISO9660 8.3 names, so any mastering keeps them
 *   -x FILE    also copy amix-cdboot to DIR/BOOT/amix-cdboot and write
 *              DIR/S/Startup-Sequence to run it
 *
 * Each SPEC file describes one generation.  Lines are copied into the
 * manifest as written, except:
 *   state pristine|good|trial|bad      (control block only; required)
 *   kernel NAME FILE [attr ...]        the file is placed in the store
 *   module NAME root FILE [attr ...]   likewise; boot- and demand-class
 *                                      module lines are copied as written
 *   ramdisk NAME FILE [attr ...]       likewise
 * mkstore adds the size, at=, crc32= and the end line.  A member with the
 * attribute z=deflate is stored raw-deflate compressed (zlib level 9, the
 * smaller of memory levels 8 and 9) and
 * gets stored=; crc32 is always of the uncompressed bytes.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#define _POSIX_C_SOURCE 200112L	/* mkdir */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <zlib.h>
#include <errno.h>
#include <sys/stat.h>
#include "crc32.h"
#include "store.h"
#include "manifest.h"

#define MAXVOL 8

static ax_u32 tab[256];
static unsigned char *vols[MAXVOL];	/* each volume, built in memory */
static int nvol = 1, curvol;		/* curvol: 0-based volume being filled */
static ax_u32 store_size = 64UL << 20;
static ax_u32 next_free = AX_DATA_OFF;
#define store (vols[0])
static const char *cdroot;		/* -C: the CD tree, else 0 */
static char cddir[1024];		/* -C: the line directory being filled */

static void
die(const char *msg, const char *arg)
{
	fprintf(stderr, "mkstore: %s%s%s\n", msg, arg ? ": " : "", arg ? arg : "");
	exit(1);
}

static unsigned char *
slurp(const char *path, ax_u32 *len)
{
	FILE *f = fopen(path, "rb");
	unsigned char *p;
	long n;

	if (!f)
		die("cannot open", path);
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	p = malloc(n ? n : 1);
	if (!p || fread(p, 1, n, f) != (size_t)n)
		die("cannot read", path);
	fclose(f);
	*len = (ax_u32)n;
	return p;
}

/* place len bytes in the data area; returns the extent offset and sets
 * *vol (1-based).  With span, bytes past the end of a volume continue at
 * AX_VOLN_DATA on the next; without, data that does not fit moves whole to
 * the next volume */
static ax_u32
place(const unsigned char *p, ax_u32 len, ax_u16 *vol, int span)
{
	ax_u32 off, n;

	if (next_free >= store_size || (!span && len > store_size - next_free)) {
		if (curvol + 1 >= nvol)
			die("store full", 0);
		curvol++;
		next_free = AX_VOLN_DATA;
		if (!span && len > store_size - next_free)
			die("manifest larger than a volume", 0);
	}
	off = next_free;
	*vol = (ax_u16)(curvol + 1);
	for (;;) {
		n = store_size - next_free < len ? store_size - next_free : len;
		memcpy(vols[curvol] + next_free, p, n);
		next_free = (next_free + n + AX_BLK - 1) / AX_BLK * AX_BLK;
		p += n;
		len -= n;
		if (!len)
			return off;
		if (curvol + 1 >= nvol)
			die("store full", 0);
		curvol++;
		next_free = AX_VOLN_DATA;
	}
}

static void
makedir(const char *path)
{
	if (mkdir(path, 0777) != 0 && errno != EEXIST)
		die("cannot create directory", path);
}

/* -C: write len bytes as the file DIR/sub/name (sub may be 0 = cddir) */
static void
put_file(const char *sub, const char *name, const unsigned char *p, ax_u32 len)
{
	char path[1200];
	FILE *f;

	if (sub)
		sprintf(path, "%s/%s/%s", cdroot, sub, name);
	else
		sprintf(path, "%s/%s", cddir, name);
	if (!(f = fopen(path, "wb")) || fwrite(p, 1, len, f) != len || fclose(f) != 0)
		die("cannot write", path);
}

/* -C: the line directory of a spec, from its `line` record; 0 = k30 */
static int
spec_line(const char *spec)
{
	char line[1024];
	FILE *f = fopen(spec, "r");
	int k = -1;

	if (!f)
		die("cannot open", spec);
	while (k < 0 && fgets(line, sizeof(line), f)) {
		if (!strncmp(line, "line k30", 8) && (line[8] == '\n' || line[8] == ' ' || !line[8]))
			k = 0;
		else if (!strncmp(line, "line k46", 8) && (line[8] == '\n' || line[8] == ' ' || !line[8]))
			k = 1;
		else if (!strncmp(line, "line ", 5))
			die("line must be k30 or k46", spec);
	}
	fclose(f);
	if (k < 0)
		die("a CD generation needs a 'line' record", spec);
	sprintf(cddir, "%s/BOOT/%s", cdroot, k ? "K46" : "K30");
	makedir(cddir);
	return k;
}

/* raw deflate at level 9 and zlib memory level ml; a malloc'd buffer */
static unsigned char *
deflate_ml(const unsigned char *in, ax_u32 n, int ml, ax_u32 *outn)
{
	z_stream z;
	ax_u32 cap = n + n / 8 + 1024;
	unsigned char *out = malloc(cap);

	memset(&z, 0, sizeof(z));
	if (!out || deflateInit2(&z, 9, Z_DEFLATED, -15, ml, Z_DEFAULT_STRATEGY) != Z_OK)
		die("deflate init failed", 0);
	z.next_in = (unsigned char *)in;
	z.avail_in = n;
	z.next_out = out;
	z.avail_out = cap;
	if (deflate(&z, Z_FINISH) != Z_STREAM_END)
		die("deflate failed", 0);
	*outn = cap - z.avail_out;
	deflateEnd(&z);
	return out;
}

/* the smaller of memory levels 8 and 9: neither wins on every input */
static unsigned char *
deflate_raw(const unsigned char *in, ax_u32 n, ax_u32 *outn)
{
	ax_u32 n8, n9;
	unsigned char *z8 = deflate_ml(in, n, 8, &n8), *z9 = deflate_ml(in, n, 9, &n9);

	if (n8 <= n9) {
		free(z9);
		*outn = n8;
		return z8;
	}
	free(z8);
	*outn = n9;
	return z9;
}

static int
state_of(const char *s)
{
	if (!strcmp(s, "pristine")) return AXG_PRISTINE;
	if (!strcmp(s, "good")) return AXG_GOOD;
	if (!strcmp(s, "trial")) return AXG_TRIAL;
	if (!strcmp(s, "bad")) return AXG_BAD;
	die("unknown state", s);
	return 0;
}

/* build one generation's manifest from SPEC; fills the control entry */
static void
generation(const char *spec, struct ax_gen *g)
{
	static char man[65536];
	char line[1024], out[1024];
	char *tok[16];
	FILE *f = fopen(spec, "r");
	ax_u32 mlen = 0, flen, crc, off = 0;
	ax_u16 vol = 1;
	int n, state = -1, i, have_gen = 0, nmod = 0;
	char fname[16];
	ax_u32 res_off = 0, res_len = 0;
	ax_u16 res_vol = 0;
	unsigned char *data;
	struct ax_manifest chk;
	int errline;
	char *p;

	if (!f)
		die("cannot open", spec);
	if (nvol > 1) {
		/* a multi-volume set: reserve the manifest's room ahead of its
		 * members, so the loader reads the manifest from the volume its
		 * members start on (one change per pair, not three); every line
		 * is at most 256 bytes, plus the GMF1 and end lines */
		static unsigned char zero[65536];

		for (n = 2; fgets(line, sizeof(line), f); n++)
			;
		rewind(f);
		res_len = ((ax_u32)n * 256 + AX_BLK - 1) / AX_BLK * AX_BLK;
		if (res_len > sizeof(zero))
			die("spec too long", spec);
		res_off = place(zero, res_len, &res_vol, 0);
	}
	strcpy(man, "GMF1\n");
	mlen = 5;
	while (fgets(line, sizeof(line), f)) {
		line[strcspn(line, "\n")] = 0;
		if (!line[0])
			continue;
		strcpy(out, line);
		for (n = 0, p = strtok(line, " "); p && n < 16; p = strtok(0, " "))
			tok[n++] = p;
		if (!strcmp(tok[0], "state") && n == 2) {
			state = state_of(tok[1]);
			continue;
		}
		if (!strcmp(tok[0], "generation") && n == 2) {
			g->id = (ax_u32)strtoul(tok[1], 0, 0);
			have_gen = 1;
		}
		/* kernel, ramdisk and root-class modules are placed in the store;
		 * boot- and demand-class module lines are copied as written */
		if ((!strcmp(tok[0], "kernel") && n >= 3) || (!strcmp(tok[0], "ramdisk") && n >= 3) ||
		    (!strcmp(tok[0], "module") && n >= 4 && !strcmp(tok[2], "root"))) {
			int fi = !strcmp(tok[0], "module") ? 3 : 2, zip = 0;
			ax_u32 zlen;
			unsigned char *zdata;

			for (i = fi + 1; i < n; i++) {
				if (!strcmp(tok[i], "z=deflate"))
					zip = 1;
				else if (!strncmp(tok[i], "z=", 2) && strcmp(tok[i], "z=none"))
					die("unknown compression", tok[i]);
			}
			if (cdroot) {
				if (!have_gen || g->id > 9999)
					die("a CD generation needs its id (0..9999) before the members", spec);
				if (tok[0][0] == 'm' && ++nmod > 99)
					die("too many modules", spec);
				if (tok[0][0] == 'm')
					sprintf(fname, "G%luM%02d.BIN", (unsigned long)g->id, nmod);
				else
					sprintf(fname, "G%lu%c.BIN", (unsigned long)g->id,
						tok[0][0] == 'k' ? 'K' : 'R');
			}
			data = slurp(tok[fi], &flen);
			crc = ax_crc32(tab, data, flen);
			zdata = zip ? deflate_raw(data, flen, &zlen) : data;
			if (!zip)
				zlen = flen;
			if (cdroot)
				put_file(0, fname, zdata, zlen);
			else
				off = place(zdata, zlen, &vol, 1);
			if (zip)
				free(zdata);
			free(data);
			out[0] = 0;
			for (i = 0; i < fi; i++)
				sprintf(out + strlen(out), "%s ", tok[i]);
			if (cdroot)
				sprintf(out + strlen(out), "%lu file=%s", (unsigned long)flen, fname);
			else if (vol > 1)
				sprintf(out + strlen(out), "%lu at=%u:0x%lx", (unsigned long)flen, vol,
					(unsigned long)off);
			else
				sprintf(out + strlen(out), "%lu at=0x%lx", (unsigned long)flen,
					(unsigned long)off);
			if (zip)
				sprintf(out + strlen(out), " stored=%lu z=deflate", (unsigned long)zlen);
			sprintf(out + strlen(out), " crc32=%08lx", (unsigned long)crc);
			for (i = fi + 1; i < n; i++)
				if (strncmp(tok[i], "z=", 2))
					sprintf(out + strlen(out), " %s", tok[i]);
		}
		if (strlen(out) > AXM_MAXLINE)
			die("manifest line too long", out);
		n = sprintf(man + mlen, "%s\n", out);
		mlen += n;
	}
	fclose(f);
	if (state < 0 || !have_gen)
		die("spec needs 'generation' and 'state' lines", spec);
	crc = ax_crc32(tab, (ax_u8 *)man, mlen);
	mlen += sprintf(man + mlen, "end crc32=%08lx\n", (unsigned long)crc);

	/* the result must parse; the parser works in place, so on a copy */
	{
		static char copy[65536];
		memcpy(copy, man, mlen);
		if (ax_manifest_parse(tab, copy, mlen, &chk, &errline) != AXM_OK) {
			fprintf(stderr, "mkstore: %s: generated manifest refused at line %d\n", spec, errline);
			exit(1);
		}
	}
	g->state = (ax_u8)state;
	g->man_len = mlen;
	g->man_crc = ax_crc32(tab, (ax_u8 *)man, mlen);
	if (cdroot) {
		sprintf(fname, "G%lu.GMF", (unsigned long)g->id);
		put_file(0, fname, (unsigned char *)man, mlen);
		g->man_off = 0;
		g->volume = 0;
	} else if (res_len) {
		if (mlen > res_len)
			die("manifest larger than its reservation", spec);
		memcpy(vols[res_vol - 1] + res_off, man, mlen);
		g->man_off = res_off;
		g->volume = res_vol;
	} else {
		g->man_off = place((unsigned char *)man, mlen, &vol, 0);
		g->volume = vol;
	}
	g->created = (ax_u32)time(0);
}

/* -C: the CD tree; one read-only control file per line directory */
static int
cdtree(char **spec, int nspec, const char *cdboot, ax_u32 deflt, ax_u16 console, ax_u16 menu_ds)
{
	static const char *const sub[2] = { "BOOT/K30", "BOOT/K46" };
	static struct ax_ctl c[2];
	static unsigned char blk[AX_BLK];
	char path[1100];
	unsigned char *p;
	ax_u32 len, d;
	int i, k, n = 0;

	ax_crc32_init(tab);
	makedir(cdroot);
	sprintf(path, "%s/BOOT", cdroot);
	makedir(path);
	for (k = 0; k < 2; k++) {
		memset(&c[k], 0, sizeof(c[k]));
		c[k].seq = 1;
		c[k].menu_ds = menu_ds;
		c[k].console = console;
		c[k].serial_baud = 9600;
	}
	for (i = 0; i < nspec; i++) {
		struct ax_gen *g;

		k = spec_line(spec[i]);
		if (c[k].ngen == AX_MAXGEN)
			die("too many generations for one line", spec[i]);
		g = &c[k].gen[c[k].ngen++];
		generation(spec[i], g);
		if (g->state == AXG_TRIAL)
			die("a CD is read-only: no trial generation", spec[i]);
	}
	for (k = 0; k < 2; k++) {
		if (!c[k].ngen)
			continue;
		for (d = 0, i = 0; i < c[k].ngen; i++)
			if (c[k].gen[i].id == deflt)
				d = deflt;
		for (i = 0; !d && i < c[k].ngen; i++)
			if (c[k].gen[i].state == AXG_GOOD || c[k].gen[i].state == AXG_PRISTINE)
				d = c[k].gen[i].id;
		c[k].default_gen = d;
		ax_ctl_write(tab, &c[k], blk);
		put_file(sub[k], "CONTROL", blk, AX_BLK);
		n += c[k].ngen;
	}
	if (cdboot) {
		static const char ss[] =
			"; Amix CD boot: amix-cdboot loads the Amix kernel for this CPU\n"
			"; from BOOT/K30 or BOOT/K46 and does not return when it boots.\n"
			"SYS:BOOT/amix-cdboot\n";

		p = slurp(cdboot, &len);
		if (len < 32 || p[0] || p[1] || p[2] != 0x03 || p[3] != 0xF3)
			die("not an AmigaDOS load file", cdboot);
		put_file("BOOT", "amix-cdboot", p, len);
		free(p);
		sprintf(path, "%s/S", cdroot);
		makedir(path);
		put_file("S", "Startup-Sequence", (const unsigned char *)ss, sizeof(ss) - 1);
	}
	printf("mkstore: %s: CD tree, %d generation(s)%s%s%s\n", cdroot, n,
	       c[0].ngen ? ", K30" : "", c[1].ngen ? ", K46" : "", cdboot ? ", amix-cdboot" : "");
	return 0;
}

int
main(int argc, char **argv)
{
	const char *image[MAXVOL], *b1 = 0, *b2 = 0, *b2b = 0, *cdboot = 0;
	unsigned long poff = 0;
	ax_u32 ver = 1, deflt = 0, len, ctloff;
	int readonly = 0, floppy = 0, nimg = 0, sizeset = 0, i, v;
	ax_u16 console = AXC_SERIAL | AXC_SCREEN, menu_ds = 20;
	unsigned char *p;
	struct ax_header h;
	static struct ax_ctl c;
	FILE *f;

	for (i = 1; i < argc && argv[i][0] == '-'; i++) {
		if (i + 1 >= argc && strcmp(argv[i], "-r"))
			die("missing argument for", argv[i]);
		if (!strcmp(argv[i], "-o")) {
			if (nimg == MAXVOL)
				die("too many volumes", 0);
			image[nimg++] = argv[++i];
		} else if (!strcmp(argv[i], "-p")) poff = strtoul(argv[++i], 0, 0);
		else if (!strcmp(argv[i], "-s")) {
			store_size = (ax_u32)strtoul(argv[++i], 0, 0);
			sizeset = 1;
		}
		else if (!strcmp(argv[i], "-f")) floppy = readonly = 1;
		else if (!strcmp(argv[i], "-1")) b1 = argv[++i];
		else if (!strcmp(argv[i], "-2")) b2 = argv[++i];
		else if (!strcmp(argv[i], "-b")) b2b = argv[++i];
		else if (!strcmp(argv[i], "-v")) ver = (ax_u32)strtoul(argv[++i], 0, 0);
		else if (!strcmp(argv[i], "-d")) deflt = (ax_u32)strtoul(argv[++i], 0, 0);
		else if (!strcmp(argv[i], "-r")) readonly = 1;
		else if (!strcmp(argv[i], "-c")) {
			i++;
			if (!strcmp(argv[i], "serial")) console = AXC_SERIAL;
			else if (!strcmp(argv[i], "screen")) console = AXC_SCREEN;
			else if (!strcmp(argv[i], "both")) console = AXC_SERIAL | AXC_SCREEN;
			else die("-c takes serial, screen or both", argv[i]);
		}
		else if (!strcmp(argv[i], "-m")) menu_ds = (ax_u16)strtoul(argv[++i], 0, 0);
		else if (!strcmp(argv[i], "-C")) cdroot = argv[++i];
		else if (!strcmp(argv[i], "-x")) cdboot = argv[++i];
		else die("unknown option", argv[i]);
	}
	if (i + 1 < argc && (!strcmp(argv[argc - 1], "-r") || !strcmp(argv[argc - 1], "-f")))
		die("options go before the spec files", 0);
	if (cdroot) {
		if (nimg || b1 || b2 || b2b || floppy || i >= argc)
			die("usage: mkstore -C DIR [-x AMIX-CDBOOT] [-d ID] [-c serial|screen|both] [-m DS] SPEC...", 0);
		return cdtree(argv + i, argc - i, cdboot, deflt, console, menu_ds);
	}
	if (cdboot)
		die("-x goes with -C", 0);
	if (floppy && !sizeset)
		store_size = 901120;
	if (nimg > 1 && !floppy)
		die("several volumes need the floppy profile (-f)", 0);
	nvol = nimg ? nimg : 1;
	if (!nimg || !b1 || !b2 || i >= argc)
		die("usage: mkstore -o IMAGE [-p OFF] [-s SIZE] -1 BOOT1 -2 BOOT2 [-b BOOT2B] [-v N] [-r] [-d ID] [-c serial|screen|both] [-m DS] SPEC...", 0);
	if (store_size % AX_BLK || store_size < AX_DATA_OFF + AX_BLK)
		die("store size must be a multiple of 2048 and larger than 64 KiB", 0);
	if (argc - i > AX_MAXGEN)
		die("too many generations", 0);

	ax_crc32_init(tab);
	for (v = 0; v < nvol; v++)
		if (!(vols[v] = calloc(1, store_size)))
			die("out of memory", 0);

	p = slurp(b1, &len);
	if (len != AX_BOOT1_MAX)
		die("boot1 image must be exactly 1024 bytes", b1);
	memcpy(store, p, len);
	free(p);

	memset(&h, 0, sizeof(h));
	h.seq = 1;
	h.store_size = store_size;
	h.flags = readonly ? AXF_READONLY : AXF_WRITABLE;
	h.volume = h.nvolumes = 1;
	h.ctl_off[0] = AX_CTL_A_OFF;
	h.ctl_off[1] = AX_CTL_B_OFF;
	h.tally_off = AX_TALLY_OFF;
	h.medium = floppy ? AXM_FLOPPY : AXM_DISK;
	h.nvolumes = (ax_u16)nvol;
	if (nvol > 1)
		h.flags |= AXF_MULTIVOL;
	p = slurp(b2, &len);
	if (len == 0 || len > AX_BOOT2_MAX)
		die("boot2 must be 1..28672 bytes", b2);
	if (floppy) {
		/* packed: one control block right after boot2, data after it */
		if (b2b)
			die("the floppy profile carries one boot2", 0);
		ctloff = (AX_BOOT2_A_OFF + len + AX_BLK - 1) / AX_BLK * AX_BLK;
		h.ctl_off[0] = h.ctl_off[1] = ctloff;
		h.tally_off = 0;
		next_free = ctloff + AX_BLK;
	}
	memcpy(store + AX_BOOT2_A_OFF, p, len);
	h.boot2[0].off = AX_BOOT2_A_OFF;
	h.boot2[0].len = len;
	h.boot2[0].crc = ax_crc32(tab, p, len);
	h.boot2[0].ver = ver;
	free(p);
	if (b2b) {
		p = slurp(b2b, &len);
		if (len == 0 || len > AX_BOOT2_MAX)
			die("boot2 must be 1..28672 bytes", b2b);
		memcpy(store + AX_BOOT2_B_OFF, p, len);
		h.boot2[1].off = AX_BOOT2_B_OFF;
		h.boot2[1].len = len;
		h.boot2[1].crc = ax_crc32(tab, p, len);
		h.boot2[1].ver = ver;
		free(p);
	}

	memset(&c, 0, sizeof(c));
	c.seq = 1;
	c.menu_ds = menu_ds;
	c.console = console;
	c.serial_baud = 9600;
	for (c.ngen = 0; i < argc; i++, c.ngen++) {
		generation(argv[i], &c.gen[c.ngen]);
		if (c.gen[c.ngen].state == AXG_TRIAL)
			c.trial_gen = c.gen[c.ngen].id;
		if (!deflt && (c.gen[c.ngen].state == AXG_GOOD || c.gen[c.ngen].state == AXG_PRISTINE))
			deflt = c.gen[c.ngen].id;
	}
	c.default_gen = deflt;
	ax_ctl_write(tab, &c, store + h.ctl_off[0]);
	/* the set id tells the volumes of this set from any other: the time
	 * and the control block, which holds every manifest's CRC */
	h.set_id = (ax_u32)time(0) ^ ax_crc32(tab, store + h.ctl_off[0], AX_BLK);
	for (v = 0; v < nvol; v++) {
		h.volume = (ax_u16)(v + 1);
		ax_hdr_write(tab, &h, vols[v] + AX_HDR_A_OFF);
		ax_hdr_write(tab, &h, vols[v] + AX_HDR_B_OFF);
		f = fopen(image[v], "r+b");
		if (!f)
			f = fopen(image[v], "w+b");
		if (!f || fseek(f, v ? 0L : (long)poff, SEEK_SET) != 0 ||
		    fwrite(vols[v], 1, store_size, f) != store_size || fclose(f) != 0)
			die("cannot write", image[v]);
	}
	printf("mkstore: %s: store of %lu bytes at offset %lu, %d volume(s), %d generation(s), "
	       "%lu bytes used on the last volume\n", image[0], (unsigned long)store_size, poff,
	       nvol, c.ngen, (unsigned long)next_free);
	return 0;
}
