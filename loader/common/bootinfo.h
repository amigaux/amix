/*
 * bootinfo.h -- what boot2 hands the kernel (docs/spec/10-boot-loader.md
 * §2.2, §6): struct bootinfo in the loader's layout, the RTH1 root-hint
 * record (and the RTO1 root record inside it), and the AXL1 loader record.
 *
 * bootinfo, 0x778 bytes, loader's view:
 *   0x000 autocon[16]   ConfigDev copies, 0x44 bytes each
 *   0x440 memory[16]    MemHeader copies, 0x20 bytes each
 *   0x640 keystates[16]
 *   0x650 bootdata      entry, then text/rodata/data vaddr, offset, size
 *   0x678 reserved[256] RTH1 at +0, AXL1 at +0x38; only reserved[0..243]
 *                       reach the kernel, which copies 0x76c bytes
 * RTH1 and RTO1 follow amix-040-060-port/docs/contracts/RTH1-ROOT-HINT.md.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef BOOTINFO_H
#define BOOTINFO_H

#include "axtypes.h"
#include "rel.h"

#define AXB_SIZE	0x778
#define AXB_AUTOCON	0x000
#define AXB_CFGSIZE	0x44
#define AXB_MEMORY	0x440
#define AXB_MEMSIZE	0x20
#define AXB_KEYS	0x640
#define AXB_BOOTDATA	0x650
#define AXB_RESERVED	0x678
#define AXB_RESVISIBLE	244	/* reserved bytes that reach the kernel */
#define AXB_MAXBOARDS	16
#define AXB_MAXMEM	16

#define AX_RTH1_MAGIC	0x52544831UL	/* "RTH1" */
#define AX_RTO1_MAGIC	0x52544F31UL	/* "RTO1" */
#define AX_AXL1_MAGIC	0x41584C31UL	/* "AXL1" */
#define AX_RTH1_LEN	0x38
#define AX_RTO1_LEN	0x1c
#define AX_AXL1_LEN	124
#define AX_AXL1_OFF	AX_RTH1_LEN	/* within reserved[] */

/* RTH1 flags */
#define RTH_BOOT	0x01
#define RTH_BCDEV	0x02
#define RTH_BMOBO	0x04
#define RTH_ROOT	0x08
#define RTH_AMBIG	0x10
#define RTO_MOBO	0x01

/* a disk named by controller identity (the manifest's root/swap lines) */
#define AXS_NONE	0
#define AXS_SD		1
#define AXS_RAMDISK	2
struct ax_disksel {
	int kind;
	ax_u32 id;		/* er_Manufacturer << 16 | er_Product << 8 */
	ax_u32 base;		/* cd_BoardAddr, or 0 to match by id */
	ax_u32 unit;		/* SCSI target 0..7 */
	ax_u32 slice;
	int mobo;		/* the motherboard controller */
};

/* AXL1 state and flags */
#define AXL_GOOD	1
#define AXL_TRIAL	2
#define AXL_PRISTINE	3
#define AXL_MENU	4
#define AXL_ONESHOT	5
#define AXLF_SAFE	0x01
#define AXLF_MENU	0x02
#define AXLF_FALLBACK	0x04
#define AXLF_READONLY	0x08
#define AXLF_DEVLOAD	0x10

struct ax_loaderrec {
	ax_u32 loader_version;
	ax_u32 boot1_choice;	/* d1 from boot1 */
	ax_u32 cpu;		/* 30, 40 or 60 from the probe */
	ax_u32 attnflags;
	ax_u32 gen_id;
	ax_u32 gen_state;
	ax_u32 flags;
	ax_u32 dev_namecrc;	/* CRC-32 of the boot device's name */
	ax_u32 dev_unit, dev_start, dev_base, dev_id;
	struct ax_disksel root, swap;
	char rootfs[16];
	ax_u32 ramdisk_addr, ramdisk_size;
};

/* parse "sd id=... base=... unit=... slice=... [mobo]", "ramdisk", "none" */
int ax_disksel_parse(const char *s, struct ax_disksel *d);

/* the 0x1c-byte RTO1 record for an sd disk selector; 0, or -1 if invalid */
int ax_rto1_build(const struct ax_disksel *d, ax_u8 out[AX_RTO1_LEN]);

/* a memory region as exec lists it: MemHeader attributes, lower, upper */
struct ax_memr {
	ax_u32 attr, lower, upper;
};

/* where the kernel is bound: the largest region without MEMF_CHIP (attr
 * 0x2), counting only its part below AX_IDMAP_TOP, its base rounded down
 * to 256 bytes; *size its bytes from there.  Returns 0 with *size 0 when
 * there is no such region: the kernel needs fast memory and is never bound
 * in chip memory (address 0 is the vector table).  The Amix kernels map
 * the first 1 GiB one to one and keep their own segment maps at 0x40040000
 * (syssegs): a kernel bound in Zorro III expansion memory, from
 * 0x40000000, is not mapped once translation is on and never starts
 * (S3-43-7, 2026-10-26; docs/spec/10-boot-loader.md §5) */
#define AX_IDMAP_TOP	0x40000000UL
ax_u32 ax_bind_region(const struct ax_memr *r, int n, ax_u32 *size);

/* the 0x38-byte RTH1 record; root may be 0 */
void ax_rth1_build(ax_u32 flags, ax_u32 boot_unit, ax_u32 boot_base, ax_u32 boot_id,
		   const ax_u8 *root, ax_u8 out[AX_RTH1_LEN]);

void ax_axl1_build(const struct ax_loaderrec *l, ax_u8 out[AX_AXL1_LEN]);

/* assemble bootinfo; 0, or -1 when more than 16 boards or memory regions */
int ax_bootinfo_build(ax_u8 out[AXB_SIZE], const ax_u8 *cfgdevs, int ncfg,
		      const ax_u8 *memhdrs, int nmem, const ax_u8 keys[16],
		      const struct ax_bootdata *bd, const ax_u8 rth1[AX_RTH1_LEN],
		      const ax_u8 axl1[AX_AXL1_LEN]);

#endif
