/*
 * t_plat.c -- core/plat/amiga.c on the host: a bootinfo built by the
 * loader's own code (loader/common/bootinfo.c) with three boards and a
 * loader record, then plat_dmainit(), plat_match() and plat_board_window().
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <string.h>
#include "bootinfo.h"
#include "rel.h"

char bootinfo[AXB_SIZE];
static char k46id[] = " 68060-261101-01", k30id[] = "68030-261101-02", blank[] = " ";
static char *buildid = k46id;	/* the port's stamp writes a leading blank */
char *plat_buildid(void) { return buildid; }
void plat_line_init(void) { }
int dlm_devload, dlm_safe;
unsigned long dlm_rd_addr, dlm_rd_size;
static ax_u32 rd_a, rd_s;	/* the image boot() puts in the loader record */
char *dlm_build;
int (*dlm_plat_match)(char *);
char *inode;				/* s5's table pointer, the kernel's */
int ninode = 600;
static char zwin[8];			/* what the line's mapper gives */
static unsigned long zwin_asked;	/* the bytes it was asked for */
static int zwin_fail;
char *plat_line_zwin(unsigned long n) { zwin_asked = n; return zwin_fail ? 0 : zwin; }
extern char *plat_inowin;

void plat_dmainit(void);
int plat_match(char *);
int plat_board_window(unsigned long, unsigned long);

static int fails;

static void
check(int ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	fails += !ok;
}

static void
put32(unsigned char *p, ax_u32 v)
{
	p[0] = (unsigned char)(v >> 24);
	p[1] = (unsigned char)(v >> 16);
	p[2] = (unsigned char)(v >> 8);
	p[3] = (unsigned char)v;
}

/* a ConfigDev with er_Type at +16, the product at +17, the manufacturer at
 * +20, cd_BoardAddr at +32 and cd_BoardSize at +36 */
static void
board(unsigned char *cfg, unsigned mf, unsigned pr, unsigned type, ax_u32 base, ax_u32 size)
{
	memset(cfg, 0, AXB_CFGSIZE);
	cfg[16] = (unsigned char)type;
	cfg[17] = (unsigned char)pr;
	cfg[20] = (unsigned char)(mf >> 8);
	cfg[21] = (unsigned char)mf;
	put32(cfg + 32, base);
	put32(cfg + 36, size);
}

static void
boot(ax_u32 flags, int with_axl1)
{
	unsigned char cfg[3 * AXB_CFGSIZE];
	ax_u8 axl1[AX_AXL1_LEN];
	struct ax_loaderrec l;
	struct ax_bootdata bd;

	board(cfg, 0x144b, 0x01, 0x80, 0x40000000UL, 0x10000000UL);	/* Zorro III, 256 MiB */
	board(cfg + AXB_CFGSIZE, 0x0202, 0x54, 0xc1, 0x00e90000UL, 0x10000UL);	/* Zorro II, 64 KiB */
	board(cfg + 2 * AXB_CFGSIZE, 0x0a00, 0x02, 0xa0, 0x08000000UL, 0x08000000UL);	/* RAM, MEMLIST */
	memset(&l, 0, sizeof l);
	memset(&bd, 0, sizeof bd);
	l.loader_version = 2;
	l.gen_id = 3;
	l.flags = flags;
	l.ramdisk_addr = rd_a;
	l.ramdisk_size = rd_s;
	ax_axl1_build(&l, axl1);
	ax_bootinfo_build((ax_u8 *)bootinfo, cfg, 3, 0, 0, 0, &bd, 0, with_axl1 ? axl1 : 0);
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
	check(dlm_build && strcmp(dlm_build, "68060-261101-01") == 0, "plat: the build id is the line's, without the stamp's leading blank");
	check(dlm_plat_match == plat_match, "plat: the board matcher is set");
	buildid = k30id;
	boot(0, 1);
	check(dlm_build && strcmp(dlm_build, "68030-261101-02") == 0, "plat: a build id with no blank is taken as it is");
	buildid = blank;
	boot(0, 1);
	check(dlm_build == 0, "plat: a blank build id gives none (a core-tier module is refused)");
	buildid = k46id;
	check(plat_match("zorro:144b:01") && plat_match("zorro:0202:54"), "plat: a zorro key of a board here matches");
	check(!plat_match("zorro:144b:02") && !plat_match("zorro:dead:01"), "plat: other boards do not");
	check(plat_match("mobo:gayle"), "plat: a mobo key always matches (the module's probe decides)");
	check(!plat_match("zorro:144B:01") && !plat_match("zorro:144b") && !plat_match("always1"),
	    "plat: a malformed key does not match");
	/* fb_register's window rule (k46) */
	check(plat_board_window(0x40010000UL, 0x200000UL) && plat_board_window(0x40000000UL, 0x10000000UL),
	    "plat: a window inside a board's, or all of it, is a board window");
	check(plat_board_window(0x00e90000UL, 0x1000UL), "plat: on the second board too");
	check(!plat_board_window(0x4ff00000UL, 0x200000UL) && !plat_board_window(0x3fff0000UL, 0x20000UL),
	    "plat: a window that runs past a board's end or starts before it is not");
	check(!plat_board_window(0x08000000UL, 0x1000UL), "plat: a RAM board's (MEMLIST) is not");
	check(!plat_board_window(0x20000000UL, 0x1000UL), "plat: where no board is, is not");
	check(!plat_board_window(0x40000000UL, 0) && !plat_board_window(0xfffff000UL, 0x2000UL),
	    "plat: an empty or a wrapping range is not");
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
	/* the empty inode table: set only while inode is 0 */
	inode = 0;
	zwin_asked = 0;
	boot(0, 1);
	check(inode == zwin && plat_inowin == zwin && zwin_asked == 600UL * 200,
	    "plat: no s5 table: inode points at the line's window of ninode x 200 bytes");
	{
		char table[4];

		inode = table;
		zwin_asked = 0;
		boot(0, 1);
		check(inode == table && zwin_asked == 0, "plat: an s5 table already there is left alone, no window made");
	}
	inode = 0;
	zwin_fail = 1;
	boot(0, 1);
	check(inode == 0 && plat_inowin == 0, "plat: no window to be had: inode stays 0, said on the console");
	zwin_fail = 0;
	printf("t_plat: %d failed\n", fails);
	return fails != 0;
}
