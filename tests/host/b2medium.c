/*
 * b2medium.c -- test helper: boot2's store medium (loader/boot2/main.c,
 * compiled in whole) reading a floppy pair on the host.  The drive and the
 * person at it are simulated: on every L11 prompt the drive is first empty,
 * then holds a blank disk, then OTHER (a disk of another boot set), then
 * the wrong volume of this set, and only then the volume asked for -- so
 * want_volume's change detection, its refusals and the read of an extent
 * that continues on the next volume all run as on the target.  Every
 * member of every generation is read through st_read_stored, inflated and
 * checked against its CRC-32.
 *
 * usage: b2medium VOL1 VOL2 OTHER
 * Prints the number of volume changes; exit status 0 when every member
 * verifies and every change went through the whole script.
 *
 * Built -no-pie with an arena in the program image, so the 32-bit buffer
 * addresses main.c writes into the IOStdReq stay valid pointers here.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include "main.c"
#include "inflate.h"

/* -- the simulated machine ------------------------------------------ */

static ax_u8 arena[8UL << 20];
static ax_u32 arena_used;
static ax_u32 crctab[256];
static ax_u8 *disk[2], *other, blank[2048];
static ax_u8 *drive;		/* the disk in the drive, 0 = empty */
static ax_u32 disksize;
static int wanted;		/* the volume the last L11 prompt asked for */
static int step;		/* where the person is in the swap script; 0 = idle */
static int changes, refused_set, refused_vol, motor_offs;

ax_u32 *ax_crctab = crctab;
ax_u32 core_cpu = 30;
void *ax_execbase;

void *
x_allocmem(ax_u32 size, ax_u32 flags)
{
	ax_u8 *p = arena + arena_used;

	(void)flags;
	size = (size + 15) & ~15UL;
	if (size > sizeof(arena) - arena_used)
		return 0;
	arena_used += size;
	memset(p, 0, size);
	return p;
}

void x_freemem(void *p, ax_u32 size) { (void)p, (void)size; }
void x_memcpy(void *d, const void *s, ax_u32 n) { memcpy(d, s, n); }
void x_memset(void *d, int c, ax_u32 n) { memset(d, c, n); }

/* the person: each read during a change finds the next disk of the script */
static void
next_disk(void)
{
	switch (step) {
	case 1: drive = 0; break;
	case 2: drive = blank; break;
	case 3: drive = other; break;
	case 4: drive = disk[wanted == 1 ? 1 : 0]; break;
	default: drive = disk[wanted - 1]; step = -1; changes++; break;
	}
	step++;
}

int
x_doio(void *iobp)
{
	ax_u8 *r = iobp;
	ax_u16 cmd = *(ax_u16 *)(r + IO_COMMAND);
	ax_u32 len = *(ax_u32 *)(r + IO_LENGTH), off = *(ax_u32 *)(r + IO_OFFSET);
	ax_u8 *buf = (ax_u8 *)(unsigned long)*(ax_u32 *)(r + IO_DATA);

	if (cmd == TD_MOTOR) {
		motor_offs++;
		return 0;
	}
	if (cmd != CMD_READ)
		return -1;
	if (step > 0)
		next_disk();
	if (!drive || off % 2048 || len % 2048 || off + len > disksize)
		return -1;
	memcpy(buf, drive + off, len);
	return 0;
}

void
con_printf(const char *fmt, ...)
{
	char line[256];
	unsigned v;
	va_list ap;

	va_start(ap, fmt);
	vsprintf(line, fmt, ap);
	va_end(ap);
	fputs(line, stdout);
	if (sscanf(line, "amix-boot: L11 insert boot volume %u", &v) == 1) {
		wanted = (int)v;
		step = 1;
	} else if (strstr(line, "that is volume")) {
		refused_vol++;
	}
}

void
con_puts(const char *s)
{
	fputs(s, stdout);
	if (strstr(s, "not part of this boot set"))
		refused_set++;
}

void in_frame(void) { }
int in_key(void) { return -1; }
int in_serial(void) { return -1; }
int in_lmb(void) { return 0; }

/* referenced by main.c's boot path and RTH1 walk, never reached here */
static void never(void) { fputs("b2medium: unexpected call\n", stderr); exit(2); }
void con_init(ax_u32 baud) { (void)baud; never(); }
int core_init(void) { never(); return -1; }
long core_boot(const struct medium *m, const struct ax_ctl *c, void *p) { (void)m, (void)c, (void)p; never(); return -1; }
void *x_openlib(const char *n, ax_u32 v) { (void)n, (void)v; return 0; }
void x_forbid(void) { never(); }
void x_permit(void) { never(); }
ax_u32 x_typeofmem(const void *p) { (void)p; never(); return 0; }
int x_opendevice(const char *n, ax_u32 u, void *r, ax_u32 f) { (void)n, (void)u, (void)r, (void)f; never(); return -1; }
void x_closedevice(void *r) { (void)r; never(); }
void *x_findconfigdev(void *e, void *o, long m, long p) { (void)e, (void)o, (void)m, (void)p; never(); return 0; }

/* -- the test --------------------------------------------------------- */

static ax_u8 *
load(const char *path)
{
	FILE *f = fopen(path, "rb");
	ax_u8 *p;
	long n;

	if (!f) {
		perror(path);
		exit(2);
	}
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (disksize && (ax_u32)n != disksize) {
		fprintf(stderr, "b2medium: %s is not the size of the others\n", path);
		exit(2);
	}
	disksize = (ax_u32)n;
	p = malloc(n);
	if (!p || fread(p, 1, n, f) != (size_t)n)
		exit(2);
	fclose(f);
	return p;
}

static int
check(const char *what, const struct ax_member *mb)
{
	static struct ax_inflate st;
	ax_u8 *z, *p;
	ax_u32 got = 0;
	int rc;

	if (!mb->has_at)
		return 0;	/* boot/demand class: not the loader's */
	z = x_allocmem(mb->stored, MEMF_PUBLIC);
	p = mb->z == AXZ_DEFLATE ? x_allocmem(mb->size, MEMF_PUBLIC) : z;
	if (!z || !p) {
		fprintf(stderr, "b2medium: arena full\n");
		return 1;
	}
	if ((rc = st_read_stored(mb, z)) != 0) {
		printf("b2medium: %s %s: read failed (%d)\n", what, mb->name, rc);
		return 1;
	}
	if (mb->z == AXZ_DEFLATE &&
	    (ax_inflate(&st, p, mb->size, &got, z, mb->stored) != AXI_OK || got != mb->size)) {
		printf("b2medium: %s %s: inflate failed\n", what, mb->name);
		return 1;
	}
	if (ax_crc32(crctab, p, mb->size) != mb->crc) {
		printf("b2medium: %s %s: CRC BAD\n", what, mb->name);
		return 1;
	}
	printf("b2medium: %s %s %lu bytes from %u:0x%lx ok\n", what, mb->name,
	       (unsigned long)mb->size, mb->vol, (unsigned long)mb->at);
	return 0;
}

int
main(int argc, char **argv)
{
	static ax_u32 iobuf[IOSTD_SIZE / 4];
	static struct ax_ctl ctl;
	static struct ax_manifest m;
	ax_u8 cb[2048], *man;
	int i, j, errline, failed = 0;

	if (argc != 4)
		return 2;
	if ((unsigned long)(arena + sizeof(arena)) > 0xFFFFFFFFUL) {
		fprintf(stderr, "b2medium: arena above 4 GiB (build with -no-pie)\n");
		return 2;
	}
	disk[0] = load(argv[1]);
	disk[1] = load(argv[2]);
	other = load(argv[3]);
	ax_crc32_init(crctab);

	/* as boot2_main: volume 1 in the drive, header and control block read */
	drive = disk[0];
	iob = (ax_u8 *)iobuf;
	part = 0;
	bounce = x_allocmem(BOUNCE, MEMF_CHIP);
	if (ax_hdr_pick(crctab, disk[0] + AX_HDR_A_OFF, disk[0] + AX_HDR_B_OFF, &hdr) < 0 ||
	    hdr.nvolumes != 2) {
		fprintf(stderr, "b2medium: %s is not volume 1 of a pair\n", argv[1]);
		return 1;
	}
	curvol = hdr.volume;
	if (io(CMD_READ, hdr.ctl_off[0], cb, 2048) != 0 ||
	    (ctlcopy = ax_ctl_pick(crctab, cb, cb, &ctl)) < 0) {
		fprintf(stderr, "b2medium: no control block\n");
		return 1;
	}
	for (i = 0; i < ctl.ngen; i++) {
		const struct ax_gen *g = &ctl.gen[i];

		man = st_read_manifest(g);
		if (!man || ax_crc32(crctab, man, g->man_len) != g->man_crc ||
		    ax_manifest_parse(crctab, (char *)man, g->man_len, &m, &errline) != AXM_OK) {
			printf("b2medium: generation %lu: manifest unreadable\n", (unsigned long)g->id);
			failed = 1;
			continue;
		}
		failed |= check("kernel", &m.kernel);
		for (j = 0; j < m.nmod; j++)
			failed |= check("module", &m.mod[j]);
		if (m.has_ramdisk)
			failed |= check("ramdisk", &m.ramdisk);
	}
	/* every change refused the blank and the foreign disk, then the wrong volume */
	if (step != 0 || refused_set != 2 * changes || refused_vol != changes || motor_offs != changes)
		failed = 1;
	printf("b2medium: %d volume change(s), %d foreign/blank and %d wrong-volume disks refused: %s\n",
	       changes, refused_set, refused_vol, failed ? "FAILED" : "ok");
	return failed;
}
