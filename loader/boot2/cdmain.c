/*
 * cdmain.c -- amix-cdboot, boot2 as an AmigaDOS program started from a CD's
 * startup-sequence (docs/spec/10-boot-loader.md §4.4, D-3 §10): the CD as
 * the medium -- the control file, manifests and members read as plain
 * files through dos.library from <base>/K30 or <base>/K46 -- and core.c for
 * everything else.  Read-only: no trial, no one-shot, no writes.
 *
 * usage (in S/Startup-Sequence):  amix-cdboot [BASE]     BASE = SYS:BOOT
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "b2.h"
#include "crc32.h"
#include "core.h"

#define MODE_OLDFILE	1005
#define RETURN_FAIL	20

static void *dosbase;
static char dir[160];		/* <base>/K30 or <base>/K46 */

static long
dos(long lvo, ax_u32 d1, ax_u32 d2, ax_u32 d3)
{
	struct ax_regs r;

	REGS0(r);
	r.d1 = d1, r.d2 = d2, r.d3 = d3;
	return ax_call(dosbase, lvo, &r);
}

static void
cat(char *d, const char *s, int cap)
{
	int n = 0;

	while (d[n])
		n++;
	while (*s && n < cap - 1)
		d[n++] = *s++;
	d[n] = 0;
}

static void
catu(char *d, ax_u32 v, int cap)
{
	char buf[12];
	int n = 11;

	buf[11] = 0;
	do {
		buf[--n] = (char)('0' + v % 10);
		v /= 10;
	} while (v && n);
	cat(d, buf + n, cap);
}

/* read exactly len bytes of file <dir>/name; 0, 12 (cannot open) or 13 */
static int
read_file(const char *name, ax_u8 *dst, ax_u32 len)
{
	char path[200];
	long fh, got;

	path[0] = 0;
	cat(path, dir, sizeof(path));
	cat(path, "/", sizeof(path));
	cat(path, name, sizeof(path));
	fh = dos(-30, (ax_u32)path, MODE_OLDFILE, 0);		/* Open */
	if (!fh) {
		con_printf("amix-boot: L12 cannot open %s\n", path);
		return 12;
	}
	got = dos(-42, (ax_u32)fh, (ax_u32)dst, len);		/* Read */
	dos(-36, (ax_u32)fh, 0, 0);				/* Close */
	return got == (long)len ? 0 : 13;
}

static int
cd_read_stored(const struct ax_member *mb, ax_u8 *dst)
{
	if (!mb->file)
		return 12;		/* a store extent (at=) on a CD */
	return read_file(mb->file, dst, mb->stored);
}

static ax_u8 *
cd_read_manifest(const struct ax_gen *g)
{
	char name[24];
	ax_u8 *buf = x_allocmem(g->man_len, MEMF_PUBLIC);

	if (!buf)
		return 0;
	name[0] = 0;
	cat(name, "G", sizeof(name));
	catu(name, g->id, sizeof(name));
	cat(name, ".GMF", sizeof(name));
	if (read_file(name, buf, g->man_len) != 0) {
		x_freemem(buf, g->man_len);
		return 0;
	}
	return buf;
}

/* no boot node to report: the loader was started by AmigaDOS */
static void
cd_identify(ax_u32 *flags, ax_u32 *unit, ax_u32 *base, ax_u32 *id, struct ax_loaderrec *lr)
{
	*flags = *unit = *base = *id = 0;
	lr->dev_unit = 0xFFFFFFFFUL;
}

static const struct medium cd = {
	1, cd_read_stored, cd_read_manifest, 0, 0, cd_identify, 0
};

/* from adstart.s; returns only on failure */
long
ados_main(void *execbase, const char *args, long arglen)
{
	static ax_u8 blk[2048];
	struct ax_ctl ctl;
	struct ax_regs r;
	void *port;
	int i;

	ax_execbase = execbase;
	con_init(9600);
	if (core_init() != 0)
		return RETURN_FAIL;
	dosbase = x_openlib("dos.library", 36);
	if (!dosbase) {
		con_puts("amix-cdboot: needs dos.library 36 (Kickstart 2.0)\n");
		return RETURN_FAIL;
	}
	/* BASE: the first word of the arguments, else SYS:BOOT */
	for (i = 0; i < arglen && (args[i] == ' ' || args[i] == '\t'); i++)
		;
	dir[0] = 0;
	if (i < arglen && args[i] != '\n') {
		int n = 0;
		while (i < arglen && args[i] != ' ' && args[i] != '\n' && n < 100)
			dir[n++] = args[i++];
		dir[n] = 0;
	} else {
		cat(dir, "SYS:BOOT", sizeof(dir));
	}
	cat(dir, core_cpu == 30 ? "/K30" : "/K46", sizeof(dir));
	con_printf("\namix-cdboot %u: 680%u, generations from %s\n", LOADER_VERSION, core_cpu, dir);
	if (read_file("CONTROL", blk, 2048) != 0 || ax_ctl_parse(ax_crctab, blk, &ctl) != AX_OK) {
		con_puts("amix-cdboot: no valid control file\n");
		return RETURN_FAIL;
	}
	REGS0(r);
	port = (void *)ax_call(ax_execbase, -666, &r);		/* CreateMsgPort */
	if (!port) {
		con_puts("amix-cdboot: L4 no message port\n");
		return RETURN_FAIL;
	}
	core_boot(&cd, &ctl, port);
	return RETURN_FAIL;
}
