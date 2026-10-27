/*
 * kbuild.h -- `kbootset build` and the gates (docs/spec/40-generations-and-
 * composer.md §3, §3.1): compose the next generation from what the package
 * system installed under a root, refuse it at the first gate it fails, and
 * hand it to commit.  The inputs are the agreed contracts:
 * docs/contracts/C2-2-kpkg.md (apkg's install records),
 * C2-3-packages.md (the kernel and its kabi sidecar), C3-3 (a module
 * kernel's sidecar) and C3-5 (the module packages and their records).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef KBUILD_H
#define KBUILD_H

#include "ks.h"

/* the box the generation is for: from kinfo (C2-1) on the box, from the
 * command line on a host build; an unknown fact fails its gate */
struct kb_facts {
	int line;		/* 30 or 46; 0 unknown */
	char bootdev[48];	/* match key of the boot disk's controller ("zorro:0202:54") */
	char rootdev[48];	/* match key of the root disk's controller */
	char rootfs[16];	/* root filesystem type */
	ax_u32 mem;		/* fast memory in bytes; 0 unknown */
	char root[128];		/* the manifest's root record, or "": the default generation's */
	char swap[128];		/* the swap record, or "": the default generation's */
};

/* the Z3660 as one controller (C4-1 §5.1, S5-15): a match key of its
 * window, mobo:z3660-window, becomes zorro:144b:01, in place; an sd root
 * or swap record on a Z3660 card (id 144b0100 at any base, id 4, or id 0
 * at the window 0x10000000) becomes id=144b0100 base=00000000, the rest
 * kept, into out (128 bytes) */
void kb_canonkey(char *key);
void kb_canonrec(const char *rec, char *out);

/* the kernel's sidecar (C2-3 §2; a module kernel's, version 5: C3-3 §3) */
struct kb_kernel {
	char kabi[24], family[32], line[8], pin[48], build[48], sha256[65];
	char abi[66];		/* the fingerprint, C3-3 section 4: 64 hex or "" */
	char sym[100];		/* sym= (a brel's unix.sym: name, size, sha256), or "" */
	char root[256], rootfs[64];
	ax_u32 size, loader_min, arena_off, arena_cap, ident_off;
	ax_u32 ksym_off, ksym_len;	/* the kernel's symbol block (C3-2), image offset and size */
	int has_ksym;
	ax_u32 bss;		/* bytes past the image to the kernel's end: a brel
				 * kernel does not record them (C2-3 §2) */
	int has_arena, has_ident;
	int brel;		/* the kernel file is a brel (ELF type 0xff00) */
};

/* compose the next generation under root (the box: "/") into
 * root/stand/gen/<id>/: `build` (the generation's records and members) and
 * `facts` (what the gates were run against); every gate is run; nothing is
 * written to the store */
int kb_build(struct ks *k, const char *root, const struct kb_facts *f, ax_u32 created,
	     ax_u32 *id);

/* commit the generation built for the store's next id: the gates run again
 * against its files as they are now, then ks_commit.  When it equals the
 * default generation (members by size and SHA-256, the facts, the
 * parameters) nothing is written and KS_OK returned, unless again is set
 * (C2-4 §3: a repair, or a row that needs the generation) */
int kb_commit(struct ks *k, const char *root, ax_u32 *id, int again);

/* a new medium's pristine generation (host media builds, S2-04): every
 * gate, against the loader version the medium carries, then the
 * generation as a mkstore spec in out (paths under root; members deflated
 * when deflate is set; ramdisk, if given, as its RAM disk; the installed
 * modules' records, with their copies written to root's /stand/gen/1/mod/
 * for the medium's root, C3-5); msg the refusal;
 * returns kbootset's exit status (0, 3 or 4) */
int kb_spec(const char *root, const struct kb_facts *f, ax_u32 loader_version, ax_u32 created,
	    int deflate, const char *ramdisk, char *out, char *msg);

/* the root-side half of `kbootset check` (C2-5), never writing: the
 * boot- and demand-class files the manifests name under root, and the
 * default generation's kernel against the installed kernel package;
 * skipped when root holds no apkg records; returns the number of problems */
int kb_check(struct ks *k, const char *root, void (*say)(const char *line));

/* the booted kernel's namelist, root/stand/unix (40 §4.2, C2-4 §12):
 * made from the booted generation's kernel (or the line's unix.sym for a
 * brel) at kinfo's bind address, its layout checked against kinfo's
 * bootdata block.  write: write it when it differs (stand/unix.new, then
 * renamed); else only compare.  line gets the message (C2-4 §12).
 * Returns KB_NL_WRITTEN, KB_NL_CURRENT, KB_NL_STALE (not written),
 * KB_NL_NONE (it cannot be made: line says why) or -1 (I/O error) */
struct kb_kinfo;
#define KB_NL_WRITTEN	0
#define KB_NL_CURRENT	1
#define KB_NL_STALE	2
#define KB_NL_NONE	3
int kb_namelist_run(struct ks *k, const char *root, const struct kb_kinfo *ki, int write,
		    char line[300]);

#endif
