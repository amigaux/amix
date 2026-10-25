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
 *              filled in order, each member on one volume
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
 * Each SPEC file describes one generation.  Lines are copied into the
 * manifest as written, except:
 *   state pristine|good|trial|bad      (control block only; required)
 *   kernel NAME FILE [attr ...]        the file is placed in the store
 *   module NAME root FILE [attr ...]   likewise; boot- and demand-class
 *                                      module lines are copied as written
 *   ramdisk NAME FILE [attr ...]       likewise
 * mkstore adds the size, at=, crc32= and the end line.  A member with the
 * attribute z=deflate is stored raw-deflate compressed (zlib, level 9) and
 * gets stored=; crc32 is always of the uncompressed bytes.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <zlib.h>
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

/* where volumes after the first start their data: after the headers */
#define VOLN_DATA (AX_HDR_B_OFF + AX_HDR_SIZE)

/* place len bytes in the data area; returns the extent offset and sets
 * *vol (1-based); a member that does not fit moves to the next volume */
static ax_u32
place(const unsigned char *p, ax_u32 len, ax_u16 *vol)
{
	ax_u32 off = next_free;

	if (len > store_size - off) {
		if (curvol + 1 >= nvol)
			die("store full", 0);
		curvol++;
		off = next_free = VOLN_DATA;
		if (len > store_size - off)
			die("member larger than a volume", 0);
	}
	memcpy(vols[curvol] + off, p, len);
	next_free = (off + len + AX_BLK - 1) / AX_BLK * AX_BLK;
	*vol = (ax_u16)(curvol + 1);
	return off;
}

/* raw deflate at level 9; returns a malloc'd buffer */
static unsigned char *
deflate_raw(const unsigned char *in, ax_u32 n, ax_u32 *outn)
{
	z_stream z;
	ax_u32 cap = n + n / 8 + 1024;
	unsigned char *out = malloc(cap);

	memset(&z, 0, sizeof(z));
	if (!out || deflateInit2(&z, 9, Z_DEFLATED, -15, 9, Z_DEFAULT_STRATEGY) != Z_OK)
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
	ax_u32 mlen = 0, flen, crc, off;
	ax_u16 vol;
	int n, state = -1, i, have_gen = 0;
	unsigned char *data;
	struct ax_manifest chk;
	int errline;
	char *p;

	if (!f)
		die("cannot open", spec);
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
			data = slurp(tok[fi], &flen);
			crc = ax_crc32(tab, data, flen);
			if (zip) {
				zdata = deflate_raw(data, flen, &zlen);
				off = place(zdata, zlen, &vol);
				free(zdata);
			} else {
				zlen = flen;
				off = place(data, flen, &vol);
			}
			free(data);
			out[0] = 0;
			for (i = 0; i < fi; i++)
				sprintf(out + strlen(out), "%s ", tok[i]);
			if (vol > 1)
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
	g->man_off = place((unsigned char *)man, mlen, &vol);
	g->volume = vol;
	g->created = (ax_u32)time(0);
}

int
main(int argc, char **argv)
{
	const char *image[MAXVOL], *b1 = 0, *b2 = 0, *b2b = 0;
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
		else die("unknown option", argv[i]);
	}
	if (i + 1 < argc && (!strcmp(argv[argc - 1], "-r") || !strcmp(argv[argc - 1], "-f")))
		die("options go before the spec files", 0);
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
	h.set_id = (ax_u32)time(0);
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
