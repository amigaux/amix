/*
 * kbuild.c -- `kbootset build`, `commit` from a build, and the gates (see
 * kbuild.h).  A generation is a kernel: a static one, or a module kernel
 * (sidecar version 5, C3-3), whose manifest gets its arena and identity
 * records for loader version 2.  Root-class modules are stage 4's and are
 * refused here until then.
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
	/* 6: memory -- about twice the kernel, arena and RAM disk */
	need = 2 * (*klen + (kk->brel ? kk->bss : 0) + (kk->has_arena ? kk->arena_cap : 0));
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
	sprintf(out, "generation 1\nstate pristine\n");
	head(out + strlen(out), f, &kk, f->rootfs, f->root, f->swap, 0, created);
	sprintf(out + strlen(out), "kernel unix %.500s%s", under(root, f->line == 30 ?
		"/stand/k30/unix" : "/stand/k46/unix"), deflate ? " z=deflate" : "");
	if (kk.brel)
		sprintf(out + strlen(out), " bss=%lu", (unsigned long)kk.bss);
	strcat(out, "\n");
	if (ramdisk)
		sprintf(out + strlen(out), "ramdisk miniroot %.500s%s\n", ramdisk, deflate ? " z=deflate" : "");
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
		ax_u32 *dflt)
{
	static char cand[8192 + 512];
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
	static char text[8192], facts[2048];
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
	head(text, f, &kk, rootfs, rootrec, swaprec, boards, created);
	same_default = same_as_default(k, text, kernel, klen, kk.brel ? kk.bss : 0, &dflt);
	free(kernel);
	sprintf(text + strlen(text), "kernel unix /stand/k%d/unix\n", f->line);
	sprintf(facts, "line=%d\nbootdev=%s\nrootdev=%s\nrootfs=%s\nmem=%lu\ncreated=%lu\n",
		f->line, f->bootdev, f->rootdev, rootfs, (unsigned long)f->mem, (unsigned long)created);
	if ((rc = mkdirs(k, root, id)) == KS_OK && (rc = put_text(k, root, id, "build", text)) == KS_OK &&
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
	free(dman);
	return rc;
}

int
kb_commit(struct ks *k, const char *root, ax_u32 *idp, int again)
{
	static char head[8192];
	static struct ks_member mb;
	struct kb_facts f;
	struct kb_kernel kk;
	struct ks_newgen g;
	char p[80], buf[64], *text, *line, *next;
	ax_u8 *t, *kernel;
	ax_u32 len, klen, id = ks_next_id(k), created, dflt;
	size_t hl = 0;
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
	head[0] = 0;
	for (line = text; *line; line = next) {
		next = strchr(line, '\n');
		if (next)
			*next++ = 0;
		else
			next = line + strlen(line);
		if (!strncmp(line, "kernel ", 7))
			continue;		/* the kernel is the member checked above */
		if (!strncmp(line, "module ", 7) || !strncmp(line, "ramdisk ", 8)) {
			free(text);
			free(kernel);
			return refuse(k, 0, "modules and RAM disks are composed from stage 3 on");
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
	if (!again && same_as_default(k, head, kernel, klen, kk.brel ? kk.bss : 0, &dflt)) {
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
	g.n = 1;
	g.m = &mb;
	g.created = created;
	g.id = id;
	rc = ks_commit(k, &g, idp);
	free(kernel);
	return rc;
}
