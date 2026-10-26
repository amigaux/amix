/*
 * t_plat.c -- core/plat/amiga.c on the host: a bootinfo built by the
 * loader's own code (loader/common/bootinfo.c) with two boards and a
 * loader record, then plat_dmainit() and plat_match().
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <string.h>
#include "bootinfo.h"
#include "rel.h"

char bootinfo[AXB_SIZE];
static char buildid[] = "68060-261101-01";
char *plat_buildid(void) { return buildid; }
void plat_line_init(void) { }
int dlm_devload, dlm_safe;
unsigned long dlm_rd_addr, dlm_rd_size;
static ax_u32 rd_a, rd_s;	/* the image boot() puts in the loader record */
char *dlm_build;
int (*dlm_plat_match)(char *);

void plat_dmainit(void);
int plat_match(char *);

static int fails;

static void
check(int ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	fails += !ok;
}

/* a ConfigDev with the manufacturer at +20 and the product at +17 */
static void
board(unsigned char *cfg, unsigned mf, unsigned pr)
{
	memset(cfg, 0, AXB_CFGSIZE);
	cfg[17] = (unsigned char)pr;
	cfg[20] = (unsigned char)(mf >> 8);
	cfg[21] = (unsigned char)mf;
}

static void
boot(ax_u32 flags, int with_axl1)
{
	unsigned char cfg[2 * AXB_CFGSIZE];
	ax_u8 axl1[AX_AXL1_LEN];
	struct ax_loaderrec l;
	struct ax_bootdata bd;

	board(cfg, 0x144b, 0x01);
	board(cfg + AXB_CFGSIZE, 0x0202, 0x54);
	memset(&l, 0, sizeof l);
	memset(&bd, 0, sizeof bd);
	l.loader_version = 2;
	l.gen_id = 3;
	l.flags = flags;
	l.ramdisk_addr = rd_a;
	l.ramdisk_size = rd_s;
	ax_axl1_build(&l, axl1);
	ax_bootinfo_build((ax_u8 *)bootinfo, cfg, 2, 0, 0, 0, &bd, 0, with_axl1 ? axl1 : 0);
	dlm_devload = dlm_safe = 0;
	dlm_rd_addr = dlm_rd_size = 0;
	dlm_build = 0;
	dlm_plat_match = 0;
	plat_dmainit();
}

int
main(void)
{
	boot(AXLF_SAFE | AXLF_DEVLOAD, 1);
	check(dlm_safe == 1 && dlm_devload == 1, "plat: AXL1's safe and development-load flags reach the core");
	check(dlm_build && strcmp(dlm_build, "68060-261101-01") == 0, "plat: the build id is the line's");
	check(dlm_plat_match == plat_match, "plat: the board matcher is set");
	check(plat_match("zorro:144b:01") && plat_match("zorro:0202:54"), "plat: a zorro key of a board here matches");
	check(!plat_match("zorro:144b:02") && !plat_match("zorro:dead:01"), "plat: other boards do not");
	check(plat_match("mobo:gayle"), "plat: a mobo key always matches (the module's probe decides)");
	check(!plat_match("zorro:144B:01") && !plat_match("zorro:144b") && !plat_match("always1"),
	    "plat: a malformed key does not match");
	boot(0, 1);
	check(dlm_safe == 0 && dlm_devload == 0, "plat: no flags, neither mode");
	boot(AXLF_SAFE | AXLF_DEVLOAD, 0);
	check(dlm_safe == 0 && dlm_devload == 0, "plat: no loader record, neither mode");
	rd_a = 0x03f00000UL;
	rd_s = 0x000c0000UL;
	boot(0, 1);
	check(dlm_rd_addr == 0x03f00000UL && dlm_rd_size == 0x000c0000UL,
	    "plat: the RAM-disk image's address and size reach the core (C4-3)");
	boot(0, 0);
	check(dlm_rd_addr == 0 && dlm_rd_size == 0, "plat: no loader record, no image");
	printf("t_plat: %d failed\n", fails);
	return fails != 0;
}
