/*
 * t_bootinfo.c -- RTO1 and RTH1 against the reference encoder
 * (amix-040-060-port/tools/rth1-record.py; expected bytes produced with it),
 * the root-selector parser, AXL1 and the bootinfo layout.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <string.h>
#include "t.h"
#include "bootinfo.h"

static int
hexeq(const ax_u8 *b, unsigned n, const char *hex)
{
	unsigned i, v;
	char two[3];

	if (strlen(hex) != 2 * n)
		return 0;
	two[2] = 0;
	for (i = 0; i < n; i++) {
		two[0] = hex[2 * i];
		two[1] = hex[2 * i + 1];
		v = (unsigned)((two[0] <= '9' ? two[0] - '0' : two[0] - 'a' + 10) << 4 |
			       (two[1] <= '9' ? two[1] - '0' : two[1] - 'a' + 10));
		if (b[i] != v)
			return 0;
	}
	return 1;
}

static int
sel_rto1(const char *line, const char *want)
{
	struct ax_disksel d;
	ax_u8 r[AX_RTO1_LEN];

	return ax_disksel_parse(line, &d) == 0 && ax_rto1_build(&d, r) == 0 &&
	       hexeq(r, AX_RTO1_LEN, want);
}

void
test_bootinfo(void)
{
	struct ax_disksel d, rootsel;
	ax_u8 rto[AX_RTO1_LEN], rth[AX_RTH1_LEN], axl[AX_AXL1_LEN], bi[AXB_SIZE];
	ax_u8 cfg[2 * AXB_CFGSIZE], mem[AXB_MEMSIZE], keys[16];
	struct ax_loaderrec l;
	struct ax_bootdata bd;
	ax_u32 sum;
	int i;

	/* rth1-record.py rootrec --unit 6 --id 0x144b0100 */
	T_CHECK(sel_rto1("sd id=144b0100 base=00000000 unit=6 slice=1",
			 "52544f310001001c0000000600000000144b010000000000995fafad"));
	/* --unit 1 --id 0xc0de0100 */
	T_CHECK(sel_rto1("sd id=c0de0100 unit=1", "52544f310001001c0000000100000000c0de010000000000ecccafb2"));
	/* --unit 6 --mobo */
	T_CHECK(sel_rto1("sd mobo unit=6", "52544f310001001c00000006000000000000000000000001adaab0ac"));
	/* --unit 3 --base 0x40000000 --id 0x02025400 */
	T_CHECK(sel_rto1("sd base=40000000 id=02025400 unit=3 slice=1",
			 "52544f310001001c000000034000000002025400000000006ba85cb0"));

	/* RTH1 with a root record; decoded by rth1-record.py as
	 * "flags BOOT|BCDEV|ROOT, boot unit 6, board 00e90000, id 144b01; root unit 1, id c0de01" */
	ax_disksel_parse("sd id=c0de0100 unit=1", &d);
	ax_rto1_build(&d, rto);
	ax_rth1_build(RTH_BOOT | RTH_BCDEV, 6, 0x00e90000UL, 0x144b0100UL, rto, rth);
	T_CHECK(hexeq(rth, AX_RTH1_LEN,
		"52544831000100380000000b0000000600e90000144b01009876b686"
		"52544f310001001c0000000100000000c0de010000000000ecccafb2"));

	/* selector refusals */
	T_EQ(ax_disksel_parse("sd unit=6", &d), -1);			/* no controller */
	T_EQ(ax_disksel_parse("sd mobo id=144b0100 unit=6", &d), -1);	/* both */
	T_EQ(ax_disksel_parse("sd id=144b0100 unit=8", &d), -1);
	T_EQ(ax_disksel_parse("sd id=144b0100 unit=6 bogus=1", &d), -1);
	T_EQ(ax_disksel_parse("nfs host:/x", &d), -1);
	T_EQ(ax_disksel_parse("ramdisk", &d), 0);
	T_EQ(d.kind, AXS_RAMDISK);
	T_EQ(ax_rto1_build(&d, rto), -1);				/* no RTO1 for a RAM disk */
	T_EQ(ax_disksel_parse("none", &d), 0);
	T_EQ(d.kind, AXS_NONE);

	/* AXL1: longs sum to zero, fields in place, fits the visible reserved area */
	memset(&l, 0, sizeof(l));
	l.loader_version = 1;
	l.cpu = 60;
	l.gen_id = 41;
	l.gen_state = AXL_TRIAL;
	l.flags = AXLF_SAFE | AXLF_DEVLOAD;
	ax_disksel_parse("sd id=144b0100 unit=6 slice=1", &rootsel);
	l.root = rootsel;
	strcpy(l.rootfs, "ufs");
	ax_axl1_build(&l, axl);
	for (sum = 0, i = 0; i < AX_AXL1_LEN; i += 4)
		sum += AX_GET32(axl + i);
	T_EQ(sum, 0);
	T_EQ(AX_GET32(axl), AX_AXL1_MAGIC);
	T_EQ(AX_GET32(axl + 28), 41);
	T_EQ(AX_GET32(axl + 60), AXS_SD);
	T_EQ(AX_GET32(axl + 64), 0x144b0100UL);
	T_EQ(AX_GET32(axl + 76), 1);			/* root slice */
	T_CHECK(memcmp(axl + 100, "ufs\0", 4) == 0);
	T_CHECK(AX_AXL1_OFF + AX_AXL1_LEN <= AXB_RESVISIBLE);

	/* bootinfo layout */
	memset(cfg, 0xC1, sizeof(cfg));
	memset(mem, 0x3E, sizeof(mem));
	memset(keys, 0x7, sizeof(keys));
	memset(&bd, 0, sizeof(bd));
	bd.entry = 0x07800000UL;
	bd.dsize = 0x1234;
	T_EQ(ax_bootinfo_build(bi, cfg, 2, mem, 1, keys, &bd, rth, axl), 0);
	T_EQ(bi[0x000], 0xC1);
	T_EQ(bi[2 * AXB_CFGSIZE - 1], 0xC1);
	T_EQ(bi[2 * AXB_CFGSIZE], 0);			/* unused boards stay zero */
	T_EQ(bi[0x440], 0x3E);
	T_EQ(bi[0x640], 7);
	T_EQ(AX_GET32(bi + 0x650), 0x07800000UL);
	T_EQ(AX_GET32(bi + 0x650 + 36), 0x1234);	/* bd_dsize */
	T_EQ(AX_GET32(bi + 0x678), AX_RTH1_MAGIC);	/* kernel reads RTH1 at +0x678 */
	T_EQ(AX_GET32(bi + 0x678 + 0x38), AX_AXL1_MAGIC);
	/* more than 16 boards refused (the kernel's copy loop has no bound) */
	T_EQ(ax_bootinfo_build(bi, cfg, 17, mem, 1, keys, &bd, rth, axl), -1);

	/* where the kernel is bound: never in chip memory */
	{
		/* a chip-only machine: no fast region, size 0 (the loader refuses, L4) */
		struct ax_memr chiponly[1] = { { 0x3, 0x400, 0x200000 } };
		/* chip, a small and a large fast region; the base rounds down to 256 */
		struct ax_memr mixed[3] = {
			{ 0x3, 0x400, 0x200000 },
			{ 0x5, 0x07000020, 0x07100000 },
			{ 0x5, 0x08000040, 0x09000000 } };
		ax_u32 size, base;

		base = ax_bind_region(chiponly, 1, &size);
		T_EQ(size, 0);
		T_EQ(base, 0);
		base = ax_bind_region(mixed, 3, &size);
		T_EQ(base, 0x08000000UL);
		T_EQ(size, 0x01000000UL);
		base = ax_bind_region(mixed, 0, &size);
		T_EQ(size, 0);
		{
			/* a larger Zorro III board (+z3=128 at 0x40000000) is never
			 * chosen: the kernel runs only below the identity map's top */
			struct ax_memr z3[3] = {
				{ 0x3, 0x400, 0x200000 },
				{ 0x5, 0x08000000, 0x09000000 },
				{ 0x5, 0x40000000, 0x48000000 } };
			/* a region across the top counts only below it */
			struct ax_memr across[2] = {
				{ 0x5, 0x08000000, 0x08800000 },
				{ 0x5, 0x3f000000, 0x41000000 } };
			/* Zorro III memory alone: nothing to bind in (L4) */
			struct ax_memr z3only[2] = {
				{ 0x3, 0x400, 0x200000 },
				{ 0x5, 0x40000000, 0x48000000 } };

			base = ax_bind_region(z3, 3, &size);
			T_EQ(base, 0x08000000UL);
			T_EQ(size, 0x01000000UL);
			base = ax_bind_region(across, 2, &size);
			T_EQ(base, 0x3f000000UL);
			T_EQ(size, 0x01000000UL);
			base = ax_bind_region(z3only, 2, &size);
			T_EQ(size, 0);
			T_EQ(base, 0);
		}
		{
			/* k30's 64 MiB cap (ax_memcap) on MemHeader copies: chip, a
			 * 16 MB bank touching a 128 MB one from below, Zorro III */
			static ax_u8 m[4 * AXB_MEMSIZE];
			static const ax_u32 r[4][3] = {
				{ 0x3, 0x400, 0x200000 },
				{ 0x5, 0x07000020, 0x08000000 },
				{ 0x5, 0x08000020, 0x10000000 },
				{ 0x5, 0x40000020, 0x48000000 } };
			int i;

			for (i = 0; i < 4; i++) {
				AX_PUT16(m + i * AXB_MEMSIZE + 14, r[i][0]);
				AX_PUT32(m + i * AXB_MEMSIZE + 20, r[i][1]);
				AX_PUT32(m + i * AXB_MEMSIZE + 24, r[i][2]);
				AX_PUT32(m + i * AXB_MEMSIZE + 28, r[i][2] - r[i][1]);
			}
			T_EQ(ax_memcap(m, 4, 0x08000000UL, AX_K30_MEMCAP), 1);
			T_EQ(AX_GET32(m + 2 * AXB_MEMSIZE + 24), 0x0C000000UL);	/* capped */
			T_EQ(AX_GET32(m + 1 * AXB_MEMSIZE + 24), 0x07FFF800UL);	/* a page short */
			T_EQ(AX_GET32(m + 3 * AXB_MEMSIZE + 24), 0x48000000UL);	/* Z3 untouched */
			T_EQ(AX_GET32(m + 0 * AXB_MEMSIZE + 24), 0x200000UL);	/* chip untouched */
			/* a 64 MB bank: nothing to cut */
			AX_PUT32(m + 2 * AXB_MEMSIZE + 24, 0x0C000000UL);
			AX_PUT32(m + 1 * AXB_MEMSIZE + 24, 0x07000020UL);
			T_EQ(ax_memcap(m, 4, 0x08000000UL, AX_K30_MEMCAP), 0);
		}
	}
}
