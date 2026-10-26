/*
 * kbuild.c -- `kbootset build`, `commit` from a build, and the gates (see
 * kbuild.h).  A generation is a kernel, a static one or a module kernel
 * (sidecar version 5, C3-3), whose manifest gets its arena and identity
 * records for loader version 2, and the boot- and demand-class modules
 * installed under /etc/conf/mod.d (C3-5): copied to /stand/gen/<id>/mod/,
 * each with its manifest record and parameters.  Root-class modules are
 * stage 4's and are refused here until then.
 *
 * Gates 5 (store space) is ks_commit's.  Gates 8 and 9 (the boot disk) are
 * met when the store is named explicitly (--image, --dev); finding it on
 * the box is S2-06.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#define _POSIX_C_SOURCE 200112L	/* mkdir, opendir */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <errno.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include "crc32.h"
#include "sha256.h"
#include "kbuild.h"
#include "kbox.h"
#include "kmod.h"
#include "knl.h"

#define MAXFILE	(64UL << 20)

static int
refuse(struct ks *k, int gate, const char *msg)
{
	static const char *const name[] = { "", "hash", "kabi", "closure", "arena",
		"store space", "memory", "loader", "boot disk", "one boot slice", "line" };

	k->gate = gate;
	if (gate)
		sprintf(k->msg, "gate %d (%s): %.260s", gate, name[gate], msg);
	else
		sprintf(k->msg, "%.300s", msg);
	return KS_EREFUSE;
}

static const char *
under(const char *root, const char *path)
{
	static char buf[2][1024];
	static int which;

	which ^= 1;
	sprintf(buf[which], "%.500s%s%.500s", root, path[0] == '/' ? "" : "/", path);
	return buf[which];
}

static ax_u8 *
slurp(const char *path, ax_u32 *len)
{
	FILE *f = fopen(path, "rb");
	ax_u8 *p;
	long n;

	if (!f)
		return 0;
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (n < 0 || (unsigned long)n > MAXFILE || (p = malloc(n ? n : 1)) == 0) {
		fclose(f);
		return 0;
	}
	if (fread(p, 1, n, f) != (size_t)n) {
		free(p);
		fclose(f);
		return 0;
	}
	fclose(f);
	*len = (ax_u32)n;
	return p;
}

static void
hex(const ax_u8 *p, ax_u32 len, char out[65])
{
	ax_u8 d[32];
	int i;

	ax_sha256(p, len, d);
	for (i = 0; i < 32; i++)
		sprintf(out + 2 * i, "%02x", d[i]);
}

/* "key=value" (sidecar, facts): the value of key into out, or 0 */
static int
value(const char *text, const char *key, char *out, size_t cap)
{
	size_t kl = strlen(key), n;
	const char *p = text, *e;

	while (*p) {
		e = strchr(p, '\n');
		n = e ? (size_t)(e - p) : strlen(p);
		if (n > kl && !strncmp(p, key, kl) && p[kl] == '=') {
			n -= kl + 1;
			if (n >= cap)
				n = cap - 1;
			memcpy(out, p + kl + 1, n);
			out[n] = 0;
			return 1;
		}
		p += n + (e != 0);
	}
	out[0] = 0;
	return 0;
}

static int
sidecar(struct ks *k, const char *root, int line, struct kb_kernel *kk)
{
	char path[32], buf[64];
	ax_u8 *t;
	ax_u32 len;
	char *text;

	sprintf(path, "/stand/k%d/kabi", line);
	if ((t = slurp(under(root, path), &len)) == 0) {
		char m[120];
		FILE *other;

		sprintf(path, "/stand/k%d/kabi", line == 30 ? 46 : 30);
		if ((other = fopen(under(root, path), "r")) != 0) {
			fclose(other);
			sprintf(m, "the installed kernel is for line k%d, the box is k%d",
				line == 30 ? 46 : 30, line);
			return refuse(k, 10, m);
		}
		sprintf(m, "no kernel package for line k%d is installed (/stand/k%d/kabi)", line, line);
		return refuse(k, 1, m);
	}
	text = malloc(len + 1);
	memcpy(text, t, len);
	text[len] = 0;
	free(t);
	memset(kk, 0, sizeof(*kk));
	value(text, "kabi", kk->kabi, sizeof(kk->kabi));
	value(text, "family", kk->family, sizeof(kk->family));
	value(text, "line", kk->line, sizeof(kk->line));
	value(text, "pin", kk->pin, sizeof(kk->pin));
	value(text, "build", kk->build, sizeof(kk->build));
	value(text, "sha256", kk->sha256, sizeof(kk->sha256));
	value(text, "abi", kk->abi, sizeof(kk->abi));
	value(text, "root", kk->root, sizeof(kk->root));
	value(text, "rootfs", kk->rootfs, sizeof(kk->rootfs));
	kk->size = value(text, "size", buf, sizeof(buf)) ? (ax_u32)strtoul(buf, 0, 10) : 0;
	kk->loader_min = value(text, "loader-min", buf, sizeof(buf)) ? (ax_u32)strtoul(buf, 0, 10) : 1;
	kk->bss = value(text, "bss", buf, sizeof(buf)) ? (ax_u32)strtoul(buf, 0, 0) : 0;
	if (value(text, "arena", buf, sizeof(buf))) {
		char *e;
		kk->arena_off = (ax_u32)strtoul(buf, &e, 0);
		kk->arena_cap = (ax_u32)strtoul(e, 0, 0);
		kk->has_arena = 1;
	}
	if (value(text, "ident", buf, sizeof(buf))) {
		kk->ident_off = (ax_u32)strtoul(buf, 0, 0);
		kk->has_ident = 1;
	}
	free(text);
	return KS_OK;
}

/* the apkg record (C2-2) naming path: its file line, and the record's
 * kabi, pin and verified fields; 0 found, -1 not, -2 named by more than
 * one record (r->name and r->other hold two of them).  apkg writes a
 * record as <name>.new and renames it, so a .new left by an interrupted
 * write is not a record */
struct kb_rec {
	ax_u32 size;
	char sha256[65], kabi[24], pin[48], verified[8], name[64], other[64];
};

static int
record(const char *root, const char *path, struct kb_rec *r)
{
	DIR *d = opendir(under(root, "/var/apkg/kpkg"));
	struct dirent *e;
	char line[1200], rp[1100];
	int found = -1;

	if (!d)
		return -1;
	while ((e = readdir(d)) != 0) {
		FILE *f;
		struct kb_rec t;
		size_t nl = strlen(e->d_name);
		int here = 0;

		if (e->d_name[0] == '.' || (nl > 4 && !strcmp(e->d_name + nl - 4, ".new")))
			continue;
		sprintf(rp, "/var/apkg/kpkg/%.60s", e->d_name);
		if ((f = fopen(under(root, rp), "r")) == 0)
			continue;
		memset(&t, 0, sizeof(t));
		sprintf(t.name, "%.60s", e->d_name);
		while (fgets(line, sizeof(line), f)) {
			char *fp, *fs, *fh;

			line[strcspn(line, "\n")] = 0;
			if (!strncmp(line, "kabi ", 5))
				sprintf(t.kabi, "%.23s", line + 5);
			else if (!strncmp(line, "pin ", 4))
				sprintf(t.pin, "%.47s", line + 4);
			else if (!strncmp(line, "verified ", 9))
				sprintf(t.verified, "%.7s", line + 9);
			else if (!strncmp(line, "file ", 5) &&
				 (fp = strtok(line + 5, " ")) != 0 && (fs = strtok(0, " ")) != 0 &&
				 (fh = strtok(0, " ")) != 0 && !strcmp(fp, path)) {
				/* no sscanf: its number scanner brings libc's floating point */
				t.size = (ax_u32)strtoul(fs, 0, 10);
				sprintf(t.sha256, "%.64s", fh);
				here = 1;
			}
		}
		fclose(f);
		if (here && found == 0) {
			sprintf(r->other, "%.60s", t.name);
			found = -2;
		} else if (here && found < 0 && found != -2) {
			*r = t;
			found = 0;
		}
	}
	closedir(d);
	return found;
}

/* comma-separated list membership, case-insensitive */
static int
listed(const char *list, const char *key)
{
	size_t n = strlen(key), i;
	const char *p = list;

	if (!n)
		return 0;
	while (*p) {
		const char *e = strchr(p, ',');
		size_t len = e ? (size_t)(e - p) : strlen(p);

		if (len == n) {
			for (i = 0; i < n; i++) {
				char a = p[i], b = key[i];
				if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
				if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
				if (a != b)
					break;
			}
			if (i == n)
				return 1;
		}
		p += len + (e != 0);
	}
	return 0;
}

/* one gate-1 check: the file under root against its record */
static int
hashed(struct ks *k, const char *root, const char *path, const ax_u8 *data, ax_u32 len,
       struct kb_rec *r, char sha[65])
{
	char m[400];

	hex(data, len, sha);
	switch (record(root, path, r)) {
	case -1:
		sprintf(m, "%s has no apkg record: placed by hand or by a bare pkgadd", path);
		return refuse(k, 1, m);
	case -2:
		sprintf(m, "%s is named by two apkg records (%s, %s)", path, r->name, r->other);
		return refuse(k, 1, m);
	}
	if (r->size != len || strcmp(r->sha256, sha)) {
		sprintf(m, "%s differs from what package %s installed", path, r->name);
		return refuse(k, 1, m);
	}
	/* the signature hook (60 §4): require-signature does not exist in 1.1,
	 * so verified=no passes */
	return KS_OK;
}

/*
 * An ET_REL kernel's bss: its allocated NOBITS sections and its COMMON
 * symbols, each aligned, which the loader places past the image (as
 * loader/common/rel.c lays them out).  0 for anything else.
 */
static ax_u32
etrel_bss(const ax_u8 *k, ax_u32 len)
{
	ax_u32 shoff, shnum, i, j, n = 0;

#define KG16(p)	((ax_u32)(p)[0] << 8 | (ax_u32)(p)[1])
#define KG32(p)	(KG16(p) << 16 | KG16((p) + 2))
	if (len < 52 || memcmp(k, "\177ELF", 4) || KG16(k + 16) != 1)
		return 0;
	shoff = KG32(k + 32);
	shnum = KG16(k + 48);
	if (KG16(k + 46) != 40 || shoff > len || shnum * 40 > len - shoff)
		return 0;
	for (i = 0; i < shnum; i++) {
		const ax_u8 *s = k + shoff + 40 * i;
		ax_u32 al = KG32(s + 32) ? KG32(s + 32) : 1;

		if (KG32(s + 4) == 8 && (KG32(s + 8) & 2))		/* NOBITS, ALLOC */
			n = (n + al - 1) / al * al + KG32(s + 20);
		if (KG32(s + 4) == 2 && KG32(s + 16) <= len && KG32(s + 20) <= len - KG32(s + 16))
			for (j = 0; j < KG32(s + 20) / 16; j++) {	/* SYMTAB: COMMONs */
				const ax_u8 *y = k + KG32(s + 16) + 16 * j;

				if (KG16(y + 14) == 0xfff2) {
					ax_u32 ca = KG32(y + 4) ? KG32(y + 4) : 1;

					n = (n + ca - 1) / ca * ca + KG32(y + 8);
				}
			}
	}
#undef KG16
#undef KG32
	return n;
}

/* every gate this module owns, for the kernel of line f->line; on success
 * *kernel holds the kernel's bytes (malloc'd) */
static int
gates(struct ks *k, const char *root, const struct kb_facts *f, const char *rootfs,
      struct kb_kernel *kk, ax_u8 **kernel, ax_u32 *klen)
{
	char kpath[32], spath[32], sha[65], m[400];
	struct kb_rec rk, rs;
	ax_u8 *side;
	ax_u32 slen, need, ver;
	int rc;

	*kernel = 0;
	if (f->line != 30 && f->line != 46)
		return refuse(k, 10, "the box's line is unknown (no kinfo): name --line on a host build");
	if ((rc = sidecar(k, root, f->line, kk)) != KS_OK)
		return rc;
	sprintf(m, "k%d", f->line);
	if (strcmp(kk->line, m)) {
		sprintf(m, "the kernel is for line %s, the box is k%d", kk->line, f->line);
		return refuse(k, 10, m);
	}
	/* 1: hash -- the kernel and its sidecar against the apkg records */
	sprintf(kpath, "/stand/k%d/unix", f->line);
	sprintf(spath, "/stand/k%d/kabi", f->line);
	if ((*kernel = slurp(under(root, kpath), klen)) == 0)
		return refuse(k, 1, "the kernel /stand/kNN/unix cannot be read");
	if ((side = slurp(under(root, spath), &slen)) == 0)
		return refuse(k, 1, "the sidecar cannot be read");
	rc = hashed(k, root, spath, side, slen, &rs, sha);
	free(side);
	if (rc == KS_OK)
		rc = hashed(k, root, kpath, *kernel, *klen, &rk, sha);
	if (rc == KS_OK && (strcmp(kk->sha256, sha) || kk->size != *klen))
		rc = refuse(k, 1, "the kernel does not match its own sidecar (size, sha256)");
	/* 2: kabi -- the sidecar against the record it was installed with; a
	 * brel kernel records no bss, so its sidecar must give it */
	if (rc == KS_OK && (!kk->kabi[0] || !kk->pin[0]))
		rc = refuse(k, 2, "the sidecar names no kabi or no compiler pin");
	kk->brel = *klen > 18 && (*kernel)[16] == 0xFF && (*kernel)[17] == 0x00;
	if (rc == KS_OK && kk->brel && !kk->bss)
		rc = refuse(k, 2, "the kernel is a brel, whose bss is not recorded, and its sidecar "
			    "gives no bss=");
	/* a module kernel: arena=, ident= and loader-min=2 together (C3-3 §3) */
	if (rc == KS_OK && (kk->has_arena != kk->has_ident ||
			    (kk->has_arena && (!kk->arena_cap || kk->loader_min < 2))))
		rc = refuse(k, 2, "a module kernel's sidecar gives arena=, ident= and loader-min=2 "
			    "together, a static kernel's none of them");
	if (rc == KS_OK && kk->has_arena && !kk->abi[0])
		rc = refuse(k, 2, "a module kernel's sidecar gives no abi= (the fingerprint, C3-3 "
			    "section 4)");
	if (rc == KS_OK && kk->abi[0] && (strlen(kk->abi) != 64 ||
					  strspn(kk->abi, "0123456789abcdef") != 64))
		rc = refuse(k, 2, "the sidecar's abi= is not a fingerprint (64 lowercase hex digits)");
	if (rc == KS_OK && (strcmp(rk.kabi, kk->kabi) || strcmp(rk.pin, kk->pin))) {
		sprintf(m, "the kernel's sidecar says kabi %s pin %s, its package record %s %s",
			kk->kabi, kk->pin, rk.kabi, rk.pin);
		rc = refuse(k, 2, m);
	}
	/* 3: closure -- the kernel's built-in root controllers and filesystems
	 * (root=, rootfs=); root-class modules come with stage 4 */
	if (rc == KS_OK && (!f->bootdev[0] || !f->rootdev[0]))
		rc = refuse(k, 3, "the boot or root disk's controller is unknown (no kinfo): "
			    "name --bootdev and --rootdev on a host build");
	if (rc == KS_OK && !listed(kk->root, f->bootdev)) {
		sprintf(m, "the kernel has no driver for the boot disk's controller %s (it has %s)",
			f->bootdev, kk->root[0] ? kk->root : "none");
		rc = refuse(k, 3, m);
	}
	if (rc == KS_OK && !listed(kk->root, f->rootdev)) {
		sprintf(m, "the kernel has no driver for the root disk's controller %s (it has %s)",
			f->rootdev, kk->root[0] ? kk->root : "none");
		rc = refuse(k, 3, m);
	}
	if (rc == KS_OK && !listed(kk->rootfs, rootfs)) {
		sprintf(m, "the kernel cannot mount a %s root (it has %s)", rootfs[0] ? rootfs : "(unknown)",
			kk->rootfs[0] ? kk->rootfs : "none");
		rc = refuse(k, 3, m);
	}
	/* 4: arena -- no root-class module to place before stage 4; that the
	 * manifest copy fits is ks_commit's (C3-4 §4) */
	/* 6: memory -- about twice the kernel, its bss, arena and RAM disk; an
	 * ET_REL kernel's bss is in its section headers, a brel's only in the
	 * sidecar's bss= */
	need = 2 * (*klen + (kk->brel ? kk->bss : etrel_bss(*kernel, *klen)) +
		    (kk->has_arena ? kk->arena_cap : 0));
	if (rc == KS_OK && !f->mem)
		rc = refuse(k, 6, "the box's fast memory is unknown (no kinfo): name --mem on a host build");
	if (rc == KS_OK && f->mem < need) {
		sprintf(m, "%lu bytes of fast memory, %lu needed", (unsigned long)f->mem, (unsigned long)need);
		rc = refuse(k, 6, m);
	}
	/* 7: loader -- the oldest loader that may boot it: the secondary as
	 * well while a new primary is on trial */
	ver = k->hdr.boot2[0].ver;
	if ((k->hdr.flags & AXF_LDRTRIAL) && k->hdr.boot2[1].len && k->hdr.boot2[1].ver < ver)
		ver = k->hdr.boot2[1].ver;
	if (rc == KS_OK && ver < kk->loader_min) {
		sprintf(m, "the installed loader is version %lu, the kernel needs %lu: "
			"run kbootset loader-install first", (unsigned long)ver, (unsigned long)kk->loader_min);
		rc = refuse(k, 7, m);
	}
	if (rc != KS_OK) {
		free(*kernel);
		*kernel = 0;
	}
	return rc;
}

/*
 * Module members (docs/contracts/C3-5-module-member.md section 2): every
 * module object under /etc/conf/mod.d, unless its modreg file says
 * disable, through gates 1 to 3; the records in manifest order.
 */
struct kb_mod {
	struct km_info i;
	ax_u8 *data;
	ax_u32 size;
	char sha[65];
	int np;
	char pv[KM_MAXPARAM][64];	/* each declared parameter's value */
	int placed;
};
static struct kb_mod mods[AXM_MAXMOD];
static int nmods;

static void
mods_free(void)
{
	int i;

	for (i = 0; i < nmods; i++)
		free(mods[i].data);
	nmods = 0;
}

/* gate 2 for one module against the kernel (C3-1 section 3) */
static int
mod_gate2(struct ks *k, const struct kb_kernel *kk, const struct km_info *mi)
{
	char m[300];
	const char *a = mi->kabi, *b = kk->kabi;
	size_t fa = strcspn(a, "."), fb = strcspn(b, ".");
	long ma, mb, na, nb;
	char *e;

	ma = strtol(a + fa + (a[fa] != 0), &e, 10);
	na = *e == '.' ? strtol(e + 1, &e, 10) : -1;
	mb = strtol(b + fb + (b[fb] != 0), &e, 10);
	nb = *e == '.' ? strtol(e + 1, &e, 10) : -1;
	if (fa != fb || strncmp(a, b, fa) || ma != mb || na < 0 || nb < 0 || na > nb) {
		sprintf(m, "module %.15s is built for kabi %s, the kernel is %s", mi->name, a, b);
		return refuse(k, 2, m);
	}
	if (strcmp(mi->cc, kk->pin)) {
		sprintf(m, "module %.15s is built with %s, the kernel with %s", mi->name, mi->cc, kk->pin);
		return refuse(k, 2, m);
	}
	if (!strcmp(mi->tier, "core") && strcmp(mi->build, kk->build)) {
		sprintf(m, "core-tier module %.15s is built for kernel %s, this one is %s", mi->name,
			mi->build, kk->build);
		return refuse(k, 2, m);
	}
	return KS_OK;
}

/* modreg.d, then modreg.local.d (C3-5 section 1): disable, and the
 * parameter values, a later line winning */
static int
modreg(struct ks *k, const char *root, struct kb_mod *md, int *disabled)
{
	static const char *const dir[] = { "/etc/conf/modreg.d/", "/etc/conf/modreg.local.d/" };
	char p[96], line[300], m[400], v[64];
	int d, j;
	FILE *f;

	for (d = 0; d < 2; d++) {
		sprintf(p, "%s%.15s", dir[d], md->i.name);
		if ((f = fopen(under(root, p), "r")) == 0)
			continue;
		while (fgets(line, sizeof(line), f)) {
			char *s = line, *eq;

			line[strcspn(line, "#\n")] = 0;
			while (*s == ' ' || *s == '\t')
				s++;
			if (!*s)
				continue;
			if (!strncmp(s, "disable", 7) && !s[7 + strspn(s + 7, " \t")]) {
				*disabled = 1;
				continue;
			}
			if (strncmp(s, "param ", 6) || !(eq = strchr(s + 6, '='))) {
				fclose(f);
				sprintf(m, "%s: %.60s: neither param <name>=<value> nor disable", p, s);
				return refuse(k, 2, m);
			}
			*eq = 0;
			for (s += 6; *s == ' '; s++)
				;
			eq[1 + strcspn(eq + 1, " \t\r")] = 0;
			for (j = 0; j < md->i.nparam && strcmp(md->i.param[j].name, s); j++)
				;
			if (j == md->i.nparam) {
				fclose(f);
				sprintf(m, "%s: module %s declares no parameter %.31s", p, md->i.name, s);
				return refuse(k, 2, m);
			}
			if (km_value(&md->i.param[j], eq + 1, v)) {
				fclose(f);
				sprintf(m, "%s: %.40s=%.60s is not a valid %s value for module %s", p, s,
					eq + 1, md->i.param[j].type, md->i.name);
				return refuse(k, 2, m);
			}
			strcpy(md->pv[j], v);
		}
		fclose(f);
	}
	return KS_OK;
}

static int
by_name(const void *a, const void *b)
{
	return strcmp(((const struct kb_mod *)a)->i.name, ((const struct kb_mod *)b)->i.name);
}

/* the name is in the comma-separated list */
static int
named(const char *list, const char *name)
{
	size_t n = strlen(name);

	while (*list) {
		size_t len = strcspn(list, ",");

		if (len == n && !strncmp(list, name, n))
			return 1;
		list += len + (list[len] == ',');
	}
	return 0;
}

/*
 * The modules for kernel kk, gates 1-3 (C3-5 section 2); their records,
 * paths under /stand/gen/<id>/mod/, into tail (cap bytes): boot class in
 * depend order, then demand class, then the param records.  mods[] keeps
 * the objects for mods_copy.
 */
static int
modules(struct ks *k, const char *root, const struct kb_kernel *kk, ax_u32 id, char *tail,
	size_t cap)
{
	DIR *dd;
	struct dirent *e;
	struct kb_rec r;
	char path[80], m[400], rec[600], sha[65], why[128];
	int i, j, n, rc = KS_OK, cls, order[AXM_MAXMOD], nparam = 0;
	size_t tl = 0;

	mods_free();
	tail[0] = 0;
	if ((dd = opendir(under(root, "/etc/conf/mod.d"))) == 0)
		return KS_OK;			/* no module package installed */
	while (rc == KS_OK && (e = readdir(dd)) != 0) {
		struct kb_mod *md = &mods[nmods];
		int disabled = 0;

		if (e->d_name[0] == '.')
			continue;
		if (nmods == AXM_MAXMOD) {
			rc = refuse(k, 0, "more than 32 module packages: over the manifest's limit");
			break;
		}
		memset(md, 0, sizeof(*md));
		sprintf(path, "/etc/conf/mod.d/%.40s", e->d_name);
		if ((md->data = slurp(under(root, path), &md->size)) == 0) {
			sprintf(m, "%s cannot be read", path);
			rc = refuse(k, 1, m);
			break;
		}
		nmods++;
		if ((rc = hashed(k, root, path, md->data, md->size, &r, sha)) != KS_OK)
			break;
		strcpy(md->sha, sha);
		if (km_read(md->data, md->size, &md->i, why)) {
			sprintf(m, "%s: %.120s", path, why);
			rc = refuse(k, 2, m);
			break;
		}
		if (strcmp(md->i.name, e->d_name)) {
			sprintf(m, "%s names itself %.15s: the file name is the module's name", path,
				md->i.name);
			rc = refuse(k, 2, m);
			break;
		}
		if ((rc = mod_gate2(k, kk, &md->i)) != KS_OK)
			break;
		for (j = 0; j < md->i.nparam; j++)
			if (km_value(&md->i.param[j], md->i.param[j].def, md->pv[j])) {
				sprintf(m, "module %.15s: its own default %s=%s is not a valid %s value",
					md->i.name, md->i.param[j].name, md->i.param[j].def,
					md->i.param[j].type);
				rc = refuse(k, 2, m);
				break;
			}
		if (rc == KS_OK)
			rc = modreg(k, root, md, &disabled);
		if (rc == KS_OK && disabled) {
			free(md->data);
			nmods--;
		}
	}
	closedir(dd);
	if (rc != KS_OK) {
		mods_free();
		return rc;
	}
	qsort(mods, (size_t)nmods, sizeof(mods[0]), by_name);

	/* gate 3: class, match, majors, depend */
	for (i = 0; i < nmods && rc == KS_OK; i++) {
		struct km_info *mi = &mods[i].i;
		const char *p = mi->majors;

		if (!strcmp(mi->cls, "root"))
			sprintf(m, "module %.15s is root class: root-class modules are composed from stage 4",
				mi->name), rc = refuse(k, 3, m);
		else if (strcmp(mi->cls, "boot") && strcmp(mi->cls, "demand"))
			sprintf(m, "module %.15s has class %s", mi->name, mi->cls), rc = refuse(k, 3, m);
		else if (!strcmp(mi->cls, "boot") && !mi->match[0])
			sprintf(m, "boot-class module %.15s has no match= (one that needs no board says "
				"match=always)", mi->name), rc = refuse(k, 3, m);
		else if (!strcmp(mi->cls, "demand") && !mi->majors[0])
			sprintf(m, "demand-class module %.15s has no majors=", mi->name), rc = refuse(k, 3, m);
		while (rc == KS_OK && *p) {
			char *q;
			long maj = (p[0] == 'c' || p[0] == 'b') && p[1] == ':' ? strtol(p + 2, &q, 10) : -1;
			const char *own;

			if (maj < 0 || (*q && *q != ',')) {
				sprintf(m, "module %.15s: majors=%s is malformed", mi->name, mi->majors);
				rc = refuse(k, 3, m);
			} else if (p[0] == 'b') {
				sprintf(m, "module %.15s: block majors come with stage 4", mi->name);
				rc = refuse(k, 3, m);
			} else if ((own = km_owner('c', (int)maj)) == 0 || strcmp(own, mi->name)) {
				sprintf(m, "module %.15s: major c:%ld is %s", mi->name, maj,
					own ? "registered to another module" : "not in the registry");
				rc = refuse(k, 3, m);
			} else
				p = *q ? q + 1 : q;
		}
		for (p = mi->depend; rc == KS_OK && *p; ) {
			size_t len = strcspn(p, ",");

			for (j = 0; j < nmods && (strlen(mods[j].i.name) != len ||
						 strncmp(mods[j].i.name, p, len)); j++)
				;
			if (j == nmods) {
				sprintf(m, "module %.15s depends on %.*s, which is not in the generation",
					mi->name, (int)(len > 15 ? 15 : len), p);
				rc = refuse(k, 3, m);
			}
			p += len + (p[len] == ',');
		}
	}

	/* the order: each module after its dependencies, boot class before
	 * demand class, names breaking ties */
	for (n = 0, cls = 0; cls < 2 && rc == KS_OK; cls++) {
		int progress = 1;

		while (progress) {
			progress = 0;
			for (i = 0; i < nmods; i++) {
				int ready = 1;

				if (mods[i].placed || strcmp(mods[i].i.cls, cls ? "demand" : "boot"))
					continue;
				for (j = 0; j < nmods; j++)
					if (!mods[j].placed && j != i && named(mods[i].i.depend, mods[j].i.name))
						ready = 0;
				if (ready) {
					mods[i].placed = 1;
					order[n++] = i;
					progress = 1;
					break;
				}
			}
		}
	}
	if (rc == KS_OK && n != nmods) {
		for (i = 0; i < nmods && mods[i].placed; i++)
			;
		sprintf(m, "module %.15s: its depend= closure has a cycle%s", mods[i].i.name,
			!strcmp(mods[i].i.cls, "boot") ? " or a demand-class dependency" : "");
		rc = refuse(k, 3, m);
	}

	for (i = 0; i < n && rc == KS_OK; i++) {
		struct kb_mod *md = &mods[order[i]];
		int boot = !strcmp(md->i.cls, "boot");

		sprintf(rec, "module %.15s %s %lu path=/stand/gen/%lu/mod/%s sha256=%s", md->i.name,
			md->i.cls, (unsigned long)md->size, (unsigned long)id, md->i.name, md->sha);
		if (boot)
			sprintf(rec + strlen(rec), " match=%s", md->i.match);
		else
			sprintf(rec + strlen(rec), " majors=%s", md->i.majors);
		if (md->i.depend[0])
			sprintf(rec + strlen(rec), " depend=%s", md->i.depend);
		if (!strcmp(md->i.tier, "core"))
			sprintf(rec + strlen(rec), " tier=core build=%s", md->i.build);
		if (strlen(rec) > AXM_MAXLINE || tl + strlen(rec) + 2 > cap) {
			sprintf(m, "module %.15s: its record is longer than the manifest's 255 bytes",
				md->i.name);
			rc = refuse(k, 0, m);
			break;
		}
		tl += (size_t)sprintf(tail + tl, "%s\n", rec);
	}
	for (i = 0; i < n && rc == KS_OK; i++) {
		struct kb_mod *md = &mods[order[i]];

		for (j = 0; j < md->i.nparam && rc == KS_OK; j++) {
			sprintf(rec, "param %s.%s=%s", md->i.name, md->i.param[j].name, md->pv[j]);
			if (++nparam > AXM_MAXPARAM || strlen(rec) > AXM_MAXLINE || tl + strlen(rec) + 2 > cap)
				rc = refuse(k, 0, "the modules' parameters are over the manifest's limits "
					    "(32 param records of 255 bytes)");
			else
				tl += (size_t)sprintf(tail + tl, "%s\n", rec);
		}
	}
	if (rc != KS_OK)
		mods_free();
	return rc;
}

/* the composed objects into /stand/gen/<id>/mod/ (mkdirs made the parent) */
static int
mods_copy(struct ks *k, const char *root, ax_u32 id)
{
	char p[96];
	FILE *f;
	int i;

	if (!nmods)
		return KS_OK;
	sprintf(p, "/stand/gen/%lu/mod", (unsigned long)id);
	if (mkdir(under(root, p), 0755) != 0 && errno != EEXIST)
		return refuse(k, 0, "cannot create /stand/gen/<id>/mod");
	for (i = 0; i < nmods; i++) {
		sprintf(p, "/stand/gen/%lu/mod/%.15s", (unsigned long)id, mods[i].i.name);
		if ((f = fopen(under(root, p), "wb")) == 0 ||
		    fwrite(mods[i].data, 1, mods[i].size, f) != mods[i].size || fclose(f) != 0)
			return refuse(k, 0, "cannot write /stand/gen/<id>/mod/<name>");
	}
	return KS_OK;
}

static int
mkdirs(struct ks *k, const char *root, ax_u32 id)
{
	char p[64];

	if (mkdir(under(root, "/stand"), 0755) != 0 && errno != EEXIST)
		return refuse(k, 0, "cannot create /stand");
	if (mkdir(under(root, "/stand/gen"), 0755) != 0 && errno != EEXIST)
		return refuse(k, 0, "cannot create /stand/gen");
	sprintf(p, "/stand/gen/%lu", (unsigned long)id);
	if (mkdir(under(root, p), 0755) != 0 && errno != EEXIST)
		return refuse(k, 0, "cannot create /stand/gen/<id>");
	return KS_OK;
}

static int
put_text(struct ks *k, const char *root, ax_u32 id, const char *name, const char *text)
{
	char p[80];
	FILE *f;

	sprintf(p, "/stand/gen/%lu/%s", (unsigned long)id, name);
	if ((f = fopen(under(root, p), "w")) == 0 || fputs(text, f) < 0 || fclose(f) != 0)
		return refuse(k, 0, "cannot write /stand/gen/<id>");
	return KS_OK;
}

int
kb_check(struct ks *k, const char *root, void (*say)(const char *line))
{
	static struct ax_manifest m;
	struct kb_rec r;
	char line[600], sha[65], kpath[32], *buf;
	ax_u8 *data;
	ax_u32 len;
	DIR *d;
	int i, j, bad = 0;

	if ((d = opendir(under(root, "/var/apkg/kpkg"))) == 0) {
		sprintf(line, "no apkg records under %.400s: the root-side checks are skipped", root);
		say(line);
		return 0;
	}
	closedir(d);
	for (i = 0; i < k->ctl.ngen; i++) {
		const struct ax_gen *g = &k->ctl.gen[i];

		if ((buf = ks_manifest(k, g->id, &m)) == 0)
			continue;		/* ks_check reports it */
		for (j = 0; j < m.nmod; j++) {
			const struct ax_member *mb = &m.mod[j];

			if (mb->has_at || !mb->path)
				continue;
			if ((data = slurp(under(root, mb->path), &len)) == 0) {
				sprintf(line, "generation %lu module %s: %.300s missing", (unsigned long)g->id,
					mb->name, mb->path);
				bad++;
			} else {
				hex(data, len, sha);
				free(data);
				if (mb->sha256 && strncmp(sha, mb->sha256, 64)) {
					sprintf(line, "generation %lu module %s: %.300s SHA-256 BAD",
						(unsigned long)g->id, mb->name, mb->path);
					bad++;
				} else {
					sprintf(line, "generation %lu module %s: %.300s ok", (unsigned long)g->id,
						mb->name, mb->path);
				}
			}
			say(line);
		}
		/* the default generation against what is installed now */
		if (g->id == k->ctl.default_gen && m.line && m.kernel.sha256) {
			sprintf(kpath, "/stand/%.3s/unix", m.line);
			if ((data = slurp(under(root, kpath), &len)) == 0) {
				sprintf(line, "%s: not installed", kpath);
				say(line);
			} else {
				hex(data, len, sha);
				free(data);
				if (record(root, kpath, &r) != 0 || strcmp(r.sha256, sha)) {
					sprintf(line, "%s differs from its apkg record (or has none)", kpath);
					say(line);
					bad++;
				} else if (strncmp(sha, m.kernel.sha256, 64)) {
					sprintf(line, "%s (package %s) differs from the default generation %lu: "
						"kbootset build and commit compose it", kpath, r.name,
						(unsigned long)g->id);
					say(line);
				} else {
					sprintf(line, "%s is the default generation %lu's kernel", kpath,
						(unsigned long)g->id);
					say(line);
				}
			}
		}
		free(buf);
	}
	return bad;
}

/* the generation's records before its members (10 §5.1) */
static void
head(char *text, const struct kb_facts *f, const struct kb_kernel *kk, const char *rootfs,
     const char *rootrec, const char *swaprec, const char *boards, ax_u32 created)
{
	time_t t = (time_t)created;
	struct tm *tm = gmtime(&t);	/* by hand: strftime brings libc's locale tables */

	sprintf(text, "line k%d\nkabi %s\ncpu %s\nloader-min %lu\n"
		"created %04d-%02d-%02dT%02d:%02d:%02dZ\n", f->line, kk->kabi,
		f->line == 30 ? "68030" : "68040 68060", (unsigned long)kk->loader_min,
		tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday, tm->tm_hour, tm->tm_min, tm->tm_sec);
	if (kk->family[0])
		sprintf(text + strlen(text), "family %s\n", kk->family);
	if (kk->build[0])
		sprintf(text + strlen(text), "kernel-build %s\n", kk->build);
	sprintf(text + strlen(text), "rootfs %s\n", rootfs);
	if (kk->has_arena)
		sprintf(text + strlen(text), "arena 0x%08lx 0x%08lx\nident 0x%08lx\n",
			(unsigned long)kk->arena_off, (unsigned long)kk->arena_cap,
			(unsigned long)kk->ident_off);
	if (rootrec && rootrec[0])
		sprintf(text + strlen(text), "root %.120s\n", rootrec);
	if (swaprec && swaprec[0])
		sprintf(text + strlen(text), "swap %.120s\n", swaprec);
	if (boards)
		sprintf(text + strlen(text), "boards %.200s\n", boards);
}

int
kb_spec(const char *root, const struct kb_facts *f, ax_u32 loader_version, ax_u32 created,
	int deflate, const char *ramdisk, char *out, char *msg)
{
	static struct ks k;
	static char mtail[16384];
	struct kb_kernel kk;
	ax_u8 *kernel;
	ax_u32 klen;
	int rc;

	memset(&k, 0, sizeof(k));
	k.hdr.boot2[0].ver = loader_version;	/* gate 7: the loader the medium carries */
	if ((rc = gates(&k, root, f, f->rootfs, &kk, &kernel, &klen)) != KS_OK) {
		strcpy(msg, k.msg);
		return k.gate ? 4 : 3;
	}
	free(kernel);
	/* the modules of the pristine generation: records as build writes them,
	 * the copies under root's /stand/gen/1/mod/, for the medium's root */
	if ((rc = modules(&k, root, &kk, 1, mtail, sizeof(mtail))) != KS_OK ||
	    (nmods && ((rc = mkdirs(&k, root, 1)) != KS_OK || (rc = mods_copy(&k, root, 1)) != KS_OK))) {
		mods_free();
		strcpy(msg, k.msg);
		return k.gate ? 4 : 3;
	}
	mods_free();
	sprintf(out, "generation 1\nstate pristine\n");
	head(out + strlen(out), f, &kk, f->rootfs, f->root, f->swap, 0, created);
	sprintf(out + strlen(out), "kernel unix %.500s%s", under(root, f->line == 30 ?
		"/stand/k30/unix" : "/stand/k46/unix"), deflate ? " z=deflate" : "");
	if (kk.brel)
		sprintf(out + strlen(out), " bss=%lu", (unsigned long)kk.bss);
	strcat(out, "\n");
	if (ramdisk)
		sprintf(out + strlen(out), "ramdisk miniroot %.500s%s\n", ramdisk, deflate ? " z=deflate" : "");
	strcat(out, mtail);
	msg[0] = 0;
	return 0;
}

static int
same(const char *a, const char *b)
{
	return a == b || (a && b && !strcmp(a, b));
}

/*
 * Does the default generation already hold what head and this kernel
 * describe?  Both sides go through the loader's parser, so the comparison
 * is of what the manifests say (line, kabi, CPUs, loader-min, root,
 * swap, filesystem, boards, arena, identity record, every member by size
 * and SHA-256, the parameters), not of their layout; the generation id
 * and created time are not compared.  Sets *dflt to the default's id.
 */
static int
same_as_default(struct ks *k, const char *head, const ax_u8 *kernel, ax_u32 klen, ax_u32 bss,
		const char *tail, ax_u32 *dflt)
{
	static char cand[8192 + 512 + 16384];
	static struct ax_manifest d, n;
	char *dman, hx[65];
	int i, errline, eq;
	size_t l;

	if (!k->ctl.default_gen || (dman = ks_manifest(k, k->ctl.default_gen, &d)) == 0)
		return 0;
	hex(kernel, klen, hx);		/* the kernel's SHA-256 */
	l = (size_t)sprintf(cand, "GMF1\ngeneration %lu\n%.8192s", (unsigned long)d.generation, head);
	l += (size_t)sprintf(cand + l, "kernel unix %lu at=0x10000 crc32=00000000 sha256=%s",
			     (unsigned long)klen, hx);
	if (bss)
		l += (size_t)sprintf(cand + l, " bss=%lu", (unsigned long)bss);
	cand[l++] = '\n';
	l += (size_t)sprintf(cand + l, "%.16384s", tail);
	l += (size_t)sprintf(cand + l, "end crc32=%08lx\n",
			     (unsigned long)ax_crc32(k->crctab, (ax_u8 *)cand, (ax_u32)l));
	eq = ax_manifest_parse(k->crctab, cand, (ax_u32)l, &n, &errline) == AXM_OK &&
	     same(d.line, n.line) && same(d.kabi, n.kabi) && same(d.cpu, n.cpu) &&
	     d.loader_min == n.loader_min && same(d.rootfs, n.rootfs) && same(d.root, n.root) &&
	     same(d.swap, n.swap) && same(d.boards, n.boards) &&
	     d.has_arena == n.has_arena && d.arena_off == n.arena_off && d.arena_cap == n.arena_cap &&
	     d.has_ident == n.has_ident && d.ident_off == n.ident_off &&
	     d.has_kernel && d.kernel.size == n.kernel.size && same(d.kernel.sha256, n.kernel.sha256) &&
	     d.kernel.bss == n.kernel.bss && d.nmod == n.nmod && d.has_ramdisk == n.has_ramdisk &&
	     d.nparam == n.nparam;
	for (i = 0; eq && i < d.nmod; i++)
		eq = same(d.mod[i].name, n.mod[i].name) && same(d.mod[i].sha256, n.mod[i].sha256);
	for (i = 0; eq && i < d.nparam; i++)
		eq = same(d.param[i], n.param[i]);
	*dflt = d.generation;
	free(dman);
	return eq;
}

int
kb_build(struct ks *k, const char *root, const struct kb_facts *f, ax_u32 created, ax_u32 *idp)
{
	static char text[8192 + 16384], facts[2048], mtail[16384];
	static struct ax_manifest m;
	struct kb_kernel kk;
	char rootfs[16], *dman = 0;
	const char *rootrec = f->root, *swaprec = f->swap, *boards = 0;
	ax_u8 *kernel;
	ax_u32 klen, id = ks_next_id(k), dflt = 0;
	int rc, same_default = 0;

	k->gate = 0;
	k->msg[0] = 0;
	/* what the new generation does not say for itself comes from the
	 * default generation: the same root, swap, filesystem and boards */
	if (k->ctl.default_gen && (dman = ks_manifest(k, k->ctl.default_gen, &m)) != 0) {
		if (!rootrec[0] && m.root)
			rootrec = m.root;
		if (!swaprec[0] && m.swap)
			swaprec = m.swap;
		boards = m.boards;
	}
	sprintf(rootfs, "%.15s", f->rootfs[0] ? f->rootfs : dman && m.rootfs ? m.rootfs : "");
	rc = gates(k, root, f, rootfs, &kk, &kernel, &klen);
	if (rc != KS_OK)
		goto out;
	if ((rc = modules(k, root, &kk, id, mtail, sizeof(mtail))) != KS_OK) {
		free(kernel);
		goto out;
	}
	head(text, f, &kk, rootfs, rootrec, swaprec, boards, created);
	same_default = same_as_default(k, text, kernel, klen, kk.brel ? kk.bss : 0, mtail, &dflt);
	free(kernel);
	sprintf(text + strlen(text), "kernel unix /stand/k%d/unix\n%s", f->line, mtail);
	sprintf(facts, "line=%d\nbootdev=%s\nrootdev=%s\nrootfs=%s\nmem=%lu\ncreated=%lu\n",
		f->line, f->bootdev, f->rootdev, rootfs, (unsigned long)f->mem, (unsigned long)created);
	if ((rc = mkdirs(k, root, id)) == KS_OK && (rc = mods_copy(k, root, id)) == KS_OK &&
	    (rc = put_text(k, root, id, "build", text)) == KS_OK &&
	    (rc = put_text(k, root, id, "facts", facts)) == KS_OK) {
		*idp = id;
		sprintf(k->msg, "generation %lu built in /stand/gen/%lu; kbootset commit writes it",
			(unsigned long)id, (unsigned long)id);
		if (same_default)	/* a loader-only transaction, say (C2-4 §3) */
			sprintf(k->msg + strlen(k->msg), "; it equals the default generation %lu: "
				"kbootset commit will write nothing (commit --again writes it)",
				(unsigned long)dflt);
	}
out:
	mods_free();
	free(dman);
	return rc;
}


/* commit: a built module record's copy under /stand/gen as it is now: its
 * size and SHA-256 as recorded, and gate 2 against the kernel again */
static int
mod_verify(struct ks *k, const char *root, const struct kb_kernel *kk, const char *line)
{
	char buf[600], *tok[16], *p, m[400], sha[65], why[128];
	const char *path = 0, *want = 0;
	struct km_info mi;
	ax_u8 *data;
	ax_u32 len;
	int n = 0, i, rc;

	sprintf(buf, "%.590s", line);
	for (p = strtok(buf, " "); p && n < 16; p = strtok(0, " "))
		tok[n++] = p;
	for (i = 4; i < n; i++)
		if (!strncmp(tok[i], "path=", 5))
			path = tok[i] + 5;
		else if (!strncmp(tok[i], "sha256=", 7))
			want = tok[i] + 7;
	if (n < 4 || !path || !want)
		return refuse(k, 0, "a module record of the build lacks path= or sha256=");
	if ((data = slurp(under(root, path), &len)) == 0) {
		sprintf(m, "%.200s, built for this generation, is missing", path);
		return refuse(k, 1, m);
	}
	hex(data, len, sha);
	if (len != (ax_u32)strtoul(tok[3], 0, 10) || strcmp(sha, want)) {
		free(data);
		sprintf(m, "%.200s changed since kbootset build", path);
		return refuse(k, 1, m);
	}
	rc = km_read(data, len, &mi, why) ? refuse(k, 2, why) : mod_gate2(k, kk, &mi);
	free(data);
	return rc;
}

int
kb_commit(struct ks *k, const char *root, ax_u32 *idp, int again)
{
	static char head[8192], tail[16384];
	static struct ks_member mb;
	struct kb_facts f;
	struct kb_kernel kk;
	struct ks_newgen g;
	char p[80], buf[64], *text, *line, *next;
	ax_u8 *t, *kernel;
	ax_u32 len, klen, id = ks_next_id(k), created, dflt;
	size_t hl = 0, tl = 0;
	int rc;

	k->gate = 0;
	k->msg[0] = 0;
	sprintf(p, "/stand/gen/%lu/facts", (unsigned long)id);
	if ((t = slurp(under(root, p), &len)) == 0) {
		sprintf(p, "nothing built for generation %lu: run kbootset build", (unsigned long)id);
		return refuse(k, 0, p);
	}
	text = malloc(len + 1);
	memcpy(text, t, len);
	text[len] = 0;
	free(t);
	memset(&f, 0, sizeof(f));
	f.line = value(text, "line", buf, sizeof(buf)) ? atoi(buf) : 0;
	value(text, "bootdev", f.bootdev, sizeof(f.bootdev));
	value(text, "rootdev", f.rootdev, sizeof(f.rootdev));
	value(text, "rootfs", f.rootfs, sizeof(f.rootfs));
	f.mem = value(text, "mem", buf, sizeof(buf)) ? (ax_u32)strtoul(buf, 0, 10) : 0;
	created = value(text, "created", buf, sizeof(buf)) ? (ax_u32)strtoul(buf, 0, 10) : 0;
	free(text);
	/* the gates again, on the files as they are now */
	if ((rc = gates(k, root, &f, f.rootfs, &kk, &kernel, &klen)) != KS_OK)
		return rc;
	sprintf(p, "/stand/gen/%lu/build", (unsigned long)id);
	if ((t = slurp(under(root, p), &len)) == 0) {
		free(kernel);
		return refuse(k, 0, "the build record is missing");
	}
	text = malloc(len + 1);
	memcpy(text, t, len);
	text[len] = 0;
	free(t);
	head[0] = tail[0] = 0;
	for (line = text; *line; line = next) {
		next = strchr(line, '\n');
		if (next)
			*next++ = 0;
		else
			next = line + strlen(line);
		if (!strncmp(line, "kernel ", 7))
			continue;		/* the kernel is the member checked above */
		if (!strncmp(line, "module ", 7) || !strncmp(line, "param ", 6)) {
			if ((line[0] == 'm' && (rc = mod_verify(k, root, &kk, line)) != KS_OK) ||
			    (tl + strlen(line) + 2 > sizeof(tail) &&
			     (rc = refuse(k, 0, "the build's module records are too long")) != KS_OK)) {
				free(text);
				free(kernel);
				return rc;
			}
			tl += (size_t)sprintf(tail + tl, "%s\n", line);
			continue;
		}
		if (!strncmp(line, "ramdisk ", 8)) {
			free(text);
			free(kernel);
			return refuse(k, 0, "RAM disks are composed from stage 4 on");
		}
		if (hl + strlen(line) + 2 > sizeof(head))
			break;
		hl += (size_t)sprintf(head + hl, "%s\n", line);
	}
	free(text);
	memset(&mb, 0, sizeof(mb));
	mb.kind = AXK_KERNEL;
	mb.name = "unix";
	mb.data = kernel;
	mb.size = klen;
	mb.deflate = 0;			/* raw in a disk store (10 §5.5) */
	if (kk.brel) {			/* the loader adds it to the brel's end */
		static char battr[32];

		sprintf(battr, "bss=%lu", (unsigned long)kk.bss);
		mb.attrs = battr;
	}
	if (!again && same_as_default(k, head, kernel, klen, kk.brel ? kk.bss : 0, tail, &dflt)) {
		/* nothing new: write nothing, and drop the build so the next one
		 * starts clean (C2-4 §3) */
		free(kernel);
		sprintf(p, "/stand/gen/%lu/build", (unsigned long)id);
		remove(under(root, p));
		sprintf(p, "/stand/gen/%lu/facts", (unsigned long)id);
		remove(under(root, p));
		sprintf(p, "/stand/gen/%lu", (unsigned long)id);
		rmdir(under(root, p));
		*idp = dflt;
		sprintf(k->msg, "the default generation %lu already has these members; nothing to commit",
			(unsigned long)dflt);
		return KS_OK;
	}
	memset(&g, 0, sizeof(g));
	g.head = head;
	g.tail = tail;
	g.n = 1;
	g.m = &mb;
	g.created = created;
	g.id = id;
	rc = ks_commit(k, &g, idp);
	free(kernel);
	return rc;
}

int
kb_namelist_run(struct ks *k, const char *root, const struct kb_kinfo *ki, int write,
		char line[300])
{
	struct ax_manifest m;
	struct kb_layout lay;
	ax_u8 *kern = 0, *sym = 0, *nl = 0, *old = 0;
	ax_u32 klen, slen = 0, nlen, olen = 0;
	char *buf, why[120], path[96], text[4096], v[200], sha[65], ksha[65], lname[16], np[1100];
	int rc = KB_NL_NONE;
	FILE *f;

	if (!ki || !ki->has_axl1) {
		strcpy(line, "no namelist: which generation booted is unknown (no kinfo loader record)");
		return KB_NL_NONE;
	}
	if (ki->version < 3 || !ki->has_bootdata) {
		sprintf(line, "no namelist: kinfo version %lu gives no bind address", (unsigned long)ki->version);
		return KB_NL_NONE;
	}
	if (ki->flags & 8) {
		strcpy(line, "no namelist: kinfo flags a loader fault (0x8)");
		return KB_NL_NONE;
	}
	/*
	 * The booted kernel: the generation's, from the store; or, on a boot
	 * from a read-only medium (a CD, a floppy pair: AXL1 flag 0x08), whose
	 * generation is not this box's, the line's installed kernel when its
	 * build id is kinfo's (C2-4 section 13)
	 */
	buf = 0;
	if (KB_MEDIUM(ki)) {
		sprintf(lname, "k%lu", (unsigned long)ki->line);
		sprintf(path, "/stand/%s/kabi", lname);
		if ((f = fopen(under(root, path), "r")) == 0) {
			sprintf(line, "no namelist: booted from a read-only medium, and %s cannot be read", path);
			return KB_NL_NONE;
		}
		text[fread(text, 1, sizeof(text) - 1, f)] = 0;
		fclose(f);
		if (!value(text, "build", v, sizeof(v)) || strcmp(v, ki->build)) {
			sprintf(line, "no namelist: booted from a read-only medium whose kernel (%.32s) is not "
				"the one installed here (%.32s)", ki->build, value(text, "build", v, sizeof(v)) ? v : "none");
			return KB_NL_NONE;
		}
		sprintf(path, "/stand/%s/unix", lname);
		if ((kern = slurp(under(root, path), &klen)) == 0) {
			sprintf(line, "no namelist: %s cannot be read", path);
			return KB_NL_NONE;
		}
		hex(kern, klen, ksha);
	} else {
		if ((buf = ks_manifest(k, ki->gen_id, &m)) == 0 || !m.has_kernel ||
		    (kern = ks_member(k, &m.kernel, &klen)) == 0) {
			sprintf(line, "no namelist: generation %lu's kernel cannot be read from the store",
				(unsigned long)ki->gen_id);
			free(buf);
			free(kern);
			return KB_NL_NONE;
		}
		sprintf(lname, "%.3s", m.line ? m.line : "k??");
		sprintf(ksha, "%.64s", m.kernel.sha256 ? m.kernel.sha256 : "");
	}
	if (klen >= 18 && kern[16] == 0xff && kern[17] == 0) {	/* a brel: the line's unix.sym */
		const char *p;

		sprintf(path, "/stand/%s/kabi", lname);
		if ((f = fopen(under(root, path), "r")) == 0) {
			sprintf(line, "no namelist: %s cannot be read", path);
			goto out;
		}
		text[fread(text, 1, sizeof(text) - 1, f)] = 0;
		fclose(f);
		if (!value(text, "sym", v, sizeof(v)) || strncmp(v, "unix.sym ", 9)) {
			strcpy(line, "no namelist: the kernel has no symbols (no unix.sym)");
			goto out;
		}
		if (!value(text, "sha256", sha, sizeof(sha)) || strncmp(sha, ksha, 64)) {
			sprintf(line, "no namelist: generation %lu's kernel is not the installed one, whose "
				"unix.sym this is", (unsigned long)ki->gen_id);
			goto out;
		}
		sprintf(path, "/stand/%s/unix.sym", lname);
		p = strchr(v + 9, ' ');
		if ((sym = slurp(under(root, path), &slen)) == 0 || !p ||
		    strtoul(v + 9, 0, 10) != slen) {
			sprintf(line, "no namelist: %s is missing or not the size its sidecar says", path);
			goto out;
		}
		hex(sym, slen, sha);
		if (strncmp(sha, p + 1, 64)) {
			sprintf(line, "no namelist: %s differs from its sidecar's sym=", path);
			goto out;
		}
	}
	if (kb_namelist(sym ? 0 : kern, sym ? 0 : klen, sym, slen, ki->bd_tvaddr, &lay, &nl, &nlen, why)) {
		sprintf(line, "no namelist: %s", why);
		goto out;
	}
	/* the layout against where the loader says it bound the kernel */
	if (lay.vaddr[0] != ki->bd_tvaddr ||
	    (ki->bd_rsize && (lay.vaddr[1] != ki->bd_rvaddr || lay.size[1] != ki->bd_rsize)) ||
	    (ki->bd_dsize && (lay.vaddr[2] != ki->bd_dvaddr || lay.size[2] != ki->bd_dsize)) ||
	    (!sym && lay.size[0] != ki->bd_tsize)) {
		strcpy(line, "no namelist: the layout does not match kinfo");
		goto out;
	}
	old = slurp(under(root, "/stand/unix"), &olen);
	if (old && olen == nlen && !memcmp(old, nl, nlen)) {
		if (KB_MEDIUM(ki))
			sprintf(line, "namelist for the medium's kernel (%.32s) is current", ki->build);
		else
			sprintf(line, "namelist for generation %lu is current", (unsigned long)ki->gen_id);
		rc = KB_NL_CURRENT;
		goto out;
	}
	if (!write) {
		strcpy(line, old ? "namelist: /stand/unix is not the booted kernel's: run kbootset namelist"
				 : "namelist: /stand/unix is missing: run kbootset namelist");
		rc = KB_NL_STALE;
		goto out;
	}
	/* a new file renamed over the name: a link to /stand/2.1_unix keeps its file */
	sprintf(np, "%.1000s", under(root, "/stand/unix.new"));
	if ((f = fopen(np, "wb")) != 0) {
		int bad = fwrite(nl, 1, nlen, f) != nlen || fflush(f) != 0;

#ifdef KS_SYNC
		bad = bad || fsync(fileno(f)) != 0;
#endif
		bad = fclose(f) != 0 || bad;
		if (bad)
			remove(np);
		else if (rename(np, under(root, "/stand/unix")) == 0)
			f = (FILE *)1;		/* written */
		else
			f = 0;
	}
	if (f != (FILE *)1) {
		strcpy(line, "no namelist: /stand/unix cannot be written");
		rc = -1;
		goto out;
	}
	if (KB_MEDIUM(ki))
		sprintf(line, "namelist /stand/unix written for the medium's kernel (%.32s), bound at 0x%08lx",
			ki->build, (unsigned long)ki->bd_tvaddr);
	else
		sprintf(line, "namelist /stand/unix written for generation %lu, bound at 0x%08lx",
			(unsigned long)ki->gen_id, (unsigned long)ki->bd_tvaddr);
	rc = KB_NL_WRITTEN;
out:
	free(buf);
	free(kern);
	free(sym);
	free(nl);
	free(old);
	return rc;
}

