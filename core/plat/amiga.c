/*
 * amiga.c -- the module core's platform hook on the Amix kernels, both
 * lines (docs/spec/30-module-core.md section 1: line-specific code lives in
 * core/plat/, not in patches).  dmainit() calls plat_dmainit() after
 * dlm_init():
 *
 *   - the loader record (AXL1, docs/spec/10-boot-loader.md section 6) in
 *     bootinfo's reserved area gives development load and safe mode;
 *   - the kernel's build id (plat_buildid(), the line's file: buildid on
 *     the 68040/68060 line, kinfo_buildid on the 030 line), for core-tier
 *     modules (C3-1);
 *   - match= keys are matched against the boards in bootinfo: a
 *     zorro:MMMM:PP key against each board's manufacturer and product; a
 *     mobo: key always, because the module's gated probe decides, as for
 *     the loader (10 section 5.3).
 *
 * Built with the loader's flags (C89), like loader/common, whose
 * bootinfo.h it uses.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "bootinfo.h"

extern char bootinfo[];			/* the kernel's copy, AXB_SIZE bytes */
extern int dlm_devload, dlm_safe;
extern char *dlm_build;
extern int (*dlm_plat_match)(char *);
extern int printf(const char *, ...);

extern char *plat_buildid(void);	/* core/plat/<line>/line.c */

static ax_u32
get32(const char *p)
{
	const unsigned char *u = (const unsigned char *)p;

	return (ax_u32)u[0] << 24 | (ax_u32)u[1] << 16 | (ax_u32)u[2] << 8 | u[3];
}

static int
hex(const char *s, int n, ax_u32 *v)
{
	int i, c;

	for (*v = 0, i = 0; i < n; i++) {
		c = s[i];
		if (c >= '0' && c <= '9')
			c -= '0';
		else if (c >= 'a' && c <= 'f')
			c -= 'a' - 10;
		else
			return -1;
		*v = *v << 4 | (ax_u32)c;
	}
	return 0;
}

/* 1 if the key names a board in this box */
int
plat_match(char *key)
{
	const char *cfg;
	ax_u32 mf, pr;
	int i;

	if (key[0] == 'm' && key[1] == 'o' && key[2] == 'b' && key[3] == 'o' && key[4] == ':')
		return 1;
	if (key[0] != 'z' || key[5] != ':' || key[10] != ':' || key[13] != 0 ||
	    hex(key + 6, 4, &mf) || hex(key + 11, 2, &pr))
		return 0;
	for (i = 0; i < AXB_MAXBOARDS; i++) {
		cfg = bootinfo + AXB_AUTOCON + i * AXB_CFGSIZE;
		if (get32(cfg + 20) >> 16 == 0)
			break;			/* the boards end at a zero manufacturer */
		if (get32(cfg + 20) >> 16 == mf && ((const unsigned char *)cfg)[17] == pr)
			return 1;
	}
	return 0;
}

void
plat_dmainit(void)
{
	const char *l = bootinfo + AXB_RESERVED + AX_AXL1_OFF;
	char *bid = plat_buildid();
	ax_u32 sum = 0, flags;
	int i;

	for (i = 0; i < AX_AXL1_LEN / 4; i++)
		sum += get32(l + 4 * i);
	if (get32(l) == AX_AXL1_MAGIC && get32(l + 4) == (0x00010000UL | AX_AXL1_LEN) &&
	    (sum & 0xffffffffUL) == 0) {
		flags = get32(l + 36);
		dlm_safe = (flags & AXLF_SAFE) != 0;
		dlm_devload = (flags & AXLF_DEVLOAD) != 0;
		if (dlm_devload)
			printf("dlm: DEVELOPMENT LOAD: modules outside the manifest allowed this boot\n");
	}
	if (bid[0] != 0)
		dlm_build = bid;
	dlm_plat_match = plat_match;
}
