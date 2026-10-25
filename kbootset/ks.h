/*
 * ks.h -- the core of kbootset (docs/spec/40-generations-and-composer.md
 * §3): a boot store's generations, and every change to them, on any
 * device that can read and write bytes at an offset -- a disk image on the
 * host, a raw slice on the box.  Portable C89, built on the host and for
 * the box from the same sources, sharing loader/common with the loader.
 *
 * Every write is read back and compared; every refusal leaves the store
 * as it was.  The control block is the only commit point: a change is
 * written into free extents and the inactive control-block copy, and the
 * store changes when that copy reads back valid (10 §4.2).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef KS_H
#define KS_H

#include "axtypes.h"
#include "store.h"
#include "manifest.h"

/* the device: byte offsets within the store (the boot slice); 0 = done */
struct ks_dev {
	int (*read)(void *ctx, ax_u32 off, ax_u8 *buf, ax_u32 len);
	int (*write)(void *ctx, ax_u32 off, const ax_u8 *buf, ax_u32 len);
	void *ctx;
};

/* the journal (/var/kbootset/journal on the box): one line of text */
struct ks_jrn {
	int (*put)(void *ctx, const char *text);
	int (*get)(void *ctx, char *buf, int cap);	/* 0: none */
	int (*clear)(void *ctx);
	void *ctx;
};

/* raw deflate of n bytes into a malloc'd buffer; 0 when it does not help */
typedef ax_u8 *(*ks_deflate)(const ax_u8 *in, ax_u32 n, ax_u32 *outn);

/* one member of a new generation */
struct ks_member {
	int kind;		/* AXK_KERNEL, AXK_MODULE (root class), AXK_RAMDISK */
	const char *name;
	const char *attrs;	/* the rest of the record (match=, …), or 0 */
	const ax_u8 *data;
	ax_u32 size;
	int deflate;		/* store it deflated when that is smaller */
};

/* a new generation: its records other than the members, and the members */
struct ks_newgen {
	const char *head;	/* records after "generation N", each ending in \n */
	const char *tail;	/* records after the members (boot/demand modules, param) */
	int n;
	const struct ks_member *m;
	ax_u32 created;		/* seconds since 1970 */
	ax_u32 id;		/* the id it was built as, or 0: the next id */
};

#define KS_MAXEXT	(AX_MAXGEN * (AXM_MAXMOD + 3) + 4)

struct ks_ext {
	ax_u32 off, len;
};

struct ks {
	struct ks_dev dev;
	struct ks_jrn jrn;	/* put == 0: no journal (host media builds) */
	ks_deflate deflate;	/* 0: members are stored raw */
	/* called before each commit step of 40 §3.2 (1 journal, 2 members,
	 * 4 manifest, 5 control block = the commit point, 7 journal cleared),
	 * for the power-cut rows (docs/plan/stage-2.md S2-08); or 0 */
	void (*step)(int n, const char *what);
	ax_u32 crctab[256];
	struct ax_header hdr;
	int hdrcopy;		/* 0 = header A holds hdr, 1 = B */
	struct ax_ctl ctl;
	int ctlcopy;		/* 0 = control block A holds ctl, 1 = B */
	int nused;
	struct ks_ext used[KS_MAXEXT];	/* every extent the control block references */
	int gate;		/* after KS_EREFUSE: the gate of 40 §3.1, 0 for a rule */
	char msg[320];		/* what happened, one line, for the caller */
};

#define KS_OK		0
#define KS_EIO		(-1)	/* a read, a write or a read-back failed */
#define KS_EREFUSE	(-2)	/* refused by a gate or a rule; nothing written */
#define KS_ESTORE	(-3)	/* the store is not valid or not readable */

/* read the store; recovers an interrupted commit from the journal */
int ks_open(struct ks *k);

/* lay a new, empty store: boot1 (1024 bytes, or 0 to leave the first
 * 1024 bytes as they are), boot2 as the primary loader, no generation */
int ks_create(struct ks *k, ax_u32 store_size, const ax_u8 *boot1,
	      const ax_u8 *boot2, ax_u32 boot2_len, ax_u32 loader_version);

/* write generation g as the trial (as pristine when the store holds no
 * generation yet); *id = its number */
int ks_commit(struct ks *k, const struct ks_newgen *g, ax_u32 *id);

/* the end of a full multi-user boot of generation booted: a trial becomes
 * good and the default; primary_used: boot1 ran the primary boot2 (clears
 * the loader trial) */
int ks_mark_good(struct ks *k, ax_u32 booted, int primary_used);

/* the default goes to the newest good (or pristine) generation older than
 * it; a pending trial is cancelled; *to = the new default */
int ks_rollback(struct ks *k, ax_u32 *to);

/* a one-shot request for the next boot (AXO_*), gen for AXO_GEN */
int ks_next(struct ks *k, int req, ax_u32 gen);

/* the administrator's verdict on a generation */
int ks_mark_bad(struct ks *k, ax_u32 id);

/* drop the generations outside the kept set */
int ks_collect(struct ks *k);

/* a new boot2 as the primary loader on trial; the current primary becomes
 * the secondary; boot1 (1024 bytes) only when given */
int ks_loader_install(struct ks *k, const ax_u8 *boot2, ax_u32 len, ax_u32 version,
		      const ax_u8 *boot1);

/* the id the next commit gives */
ax_u32 ks_next_id(const struct ks *k);

/* generation id's manifest, checked, in a malloc'd buffer that *m points
 * into (free it after use); 0 when it cannot be read */
char *ks_manifest(struct ks *k, ax_u32 id, struct ax_manifest *m);

/* the entry of generation id, or 0 */
const struct ax_gen *ks_find(const struct ks *k, ax_u32 id);

/* free bytes in the data area (before the next control-block write) */
ax_u32 ks_free(const struct ks *k);

#endif
