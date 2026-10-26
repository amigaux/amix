/*
 * kbox.h -- kbootset on the running box (docs/plan/stage-2.md S2-06): the
 * kinfo record (docs/contracts/C2-1-kinfo.md), the box facts it gives,
 * finding the boot store (docs/spec/40-generations-and-composer.md §5,
 * gates 8 and 9), and /etc/default/bootset (C2-4 §6).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef KBOX_H
#define KBOX_H

#include "kbuild.h"

#define KB_MAXBOARD	16
#define KB_MAXCARD	4
#define KB_MAXMODS	32	/* C2-1: the module list holds at most 32 */

/* one read of /dev/kinfo, decoded (C2-1 version 2) */
struct kb_kinfo {
	ax_u32 cpu, line, attn, flags;
	char kabi[25], build[33];
	int has_axl1;			/* booted by our loader */
	ax_u32 boot1_choice, gen_id, gen_state;
	ax_u32 dev_unit, dev_start, dev_base, dev_id;
	ax_u32 root_kind, root_id, root_base, root_unit, root_slice;
	char rootfs[17];
	int nboards;
	struct { ax_u32 id, base, size; } board[KB_MAXBOARD];
	int ncards;
	struct { ax_u32 k, id, base, flags; } card[KB_MAXCARD];
	ax_u32 fast, chip;
	ax_u32 version;			/* 2 or 3 */
	int has_bootdata;		/* version 3: where the loader bound the kernel */
	ax_u32 bd_entry, bd_tvaddr, bd_tsize, bd_rvaddr, bd_rsize, bd_dvaddr, bd_dsize;
	int nmods;			/* the modules loaded, from the core's list */
	char mods[KB_MAXMODS][25];
};

/* read and check the record at path (/dev/kinfo on the box); 0, or -1
 * when there is none or it is not a valid version-2 or version-3 record */
int kb_kinfo_read(const char *path, struct kb_kinfo *ki);

/* a controller id (C2-1 §2.1) as a gate match key: "zorro:0202:54",
 * "mobo:gayle"; "" for an unknown motherboard code */
void kb_matchkey(ax_u32 id, char out[48]);

/* fill the facts f does not name yet from kinfo */
void kb_kinfo_facts(const struct kb_kinfo *ki, struct kb_facts *f);

/* /etc/default/bootset (C2-4 §6): the value of key into out (cap bytes);
 * 0, or -1 when the file or the key is absent */
int kb_bootset_get(const char *path, const char *key, char *out, int cap);

/* fill the facts f does not name yet from bootset's interim facts */
void kb_bootset_facts(const char *path, struct kb_facts *f);

/* find the boot store (40 §5): bootset's store= when its header still
 * carries store-id=; else the loader record through kinfo's card table;
 * else a scan of every disk's RDB for one UNI\0 slice holding a store
 * (starting at the loader record's partition start, when there is one).
 * On success dev holds the raw slice (1100 bytes), *disk the disk number
 * X of c<X>d0 when it was found by the record or the scan (else -1), and
 * bootset's store=/store-id= are written.  Returns 0, or KS_EREFUSE with
 * k->gate 8 or 9 and k->msg */
int kb_find_store(struct ks *k, const struct kb_kinfo *ki, int have_kinfo,
		  const char *bootset, char *dev, int *disk, int record);
/* (record 0: bootset is not written -- a root that may not be writable) */

#endif
