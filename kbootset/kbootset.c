/*
 * kbootset.c -- the generation composer's command line
 * (docs/spec/40-generations-and-composer.md §3): the commands over the
 * core in ks.c, on a disk image (host media builds) or a raw boot slice
 * (the box).  The same source builds on the host and, statically, for the
 * box (docs/plan/stage-2.md S2-07).
 *
 * usage: kbootset (--image FILE | --dev PATH) [--offset N] [--journal PATH] COMMAND
 *   create SIZE BOOT2 [--boot1 FILE] [--version N]   lay an empty store
 *   status                                           generations and states
 *   commit --spec SPEC     a generation from a spec (mkstore's format): the
 *                          host form until `build` composes from packages
 *   mark-good --booted ID [--secondary]   end of a full multi-user boot
 *   rollback               the default to the previous good generation
 *   next previous|safe|devload|none|ID   for the next boot only
 *   mark-bad ID
 *   collect
 *   loader-install BOOT2 [--version N] [--boot1 FILE]
 *
 * Power-cut rows (docs/plan/stage-2.md S2-08): commit prints
 * "kbootset: step N <what>" to stderr before each step of 40 §3.2, and with
 * KBOOTSET_HOLD=N set it flushes, syncs and waits for ever before step N,
 * so the row can cut the power exactly there.
 *
 * Exit status: 0 done; 1 I/O error or damaged store; 2 usage; 3 refused
 * by a rule; 4 refused by a gate of 40 §3.1 (its number is printed).
 * Nothing is written when the status is 2, 3 or 4.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "ks.h"
#ifdef KS_ZLIB
#include <zlib.h>
#endif
#ifdef KS_SYNC			/* the box build: sync() before a hold */
#include <unistd.h>
#endif

#define SECTOR	512UL

struct file {
	FILE *f;
	unsigned long base;
};

/* raw devices take whole sectors: every access is widened to sectors
 * through a bounce buffer (the core's offsets are all sector-aligned) */
static int
fio(struct file *d, int wr, ax_u32 off, ax_u8 *buf, ax_u32 len)
{
	ax_u32 n = (len + SECTOR - 1) / SECTOR * SECTOR;
	ax_u8 *b = malloc(n ? n : 1);
	int rc = -1;

	if (!b || off % SECTOR)
		goto out;
	memset(b, 0, n);
	if (wr) {
		memcpy(b, buf, len);
		if (n > len) {		/* keep the bytes after len in the last sector */
			ax_u8 t[SECTOR];
			if (fseek(d->f, (long)(d->base + off + n - SECTOR), SEEK_SET) == 0 &&
			    fread(t, 1, SECTOR, d->f) == SECTOR)
				memcpy(b + len, t + (len - (n - SECTOR)), n - len);
		}
		rc = fseek(d->f, (long)(d->base + off), SEEK_SET) != 0 ||
		     fwrite(b, 1, n, d->f) != n || fflush(d->f) != 0 ? -1 : 0;
	} else {
		rc = fseek(d->f, (long)(d->base + off), SEEK_SET) != 0 ||
		     fread(b, 1, n, d->f) != n ? -1 : 0;
		if (rc == 0)
			memcpy(buf, b, len);
	}
out:
	free(b);
	return rc;
}

static int fread_(void *c, ax_u32 o, ax_u8 *b, ax_u32 l) { return fio(c, 0, o, b, l); }
static int fwrite_(void *c, ax_u32 o, const ax_u8 *b, ax_u32 l) { return fio(c, 1, o, (ax_u8 *)b, l); }

static const char *jpath;

static int
jput(void *c, const char *t)
{
	FILE *f = fopen(jpath, "w");

	(void)c;
	return !f || fprintf(f, "%s\n", t) < 0 || fclose(f) != 0 ? -1 : 0;
}

static int
jget(void *c, char *buf, int cap)
{
	FILE *f = fopen(jpath, "r");

	(void)c;
	buf[0] = 0;
	if (!f)
		return 0;
	if (!fgets(buf, cap, f))
		buf[0] = 0;
	fclose(f);
	buf[strcspn(buf, "\n")] = 0;
	return (int)strlen(buf);
}

static int
jclear(void *c)
{
	(void)c;
	return remove(jpath) == 0 || !fopen(jpath, "r") ? 0 : -1;
}

#ifdef KS_ZLIB
static ax_u8 *
zdeflate(const ax_u8 *in, ax_u32 n, ax_u32 *outn)
{
	z_stream z;
	ax_u32 cap = n + n / 8 + 1024;
	ax_u8 *out = malloc(cap);

	memset(&z, 0, sizeof(z));
	if (!out || deflateInit2(&z, 9, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
		free(out);
		return 0;
	}
	z.next_in = (ax_u8 *)in;
	z.avail_in = n;
	z.next_out = out;
	z.avail_out = cap;
	if (deflate(&z, Z_FINISH) != Z_STREAM_END) {
		deflateEnd(&z);
		free(out);
		return 0;
	}
	*outn = cap - z.avail_out;
	deflateEnd(&z);
	return out;
}
#endif

static void
step(int n, const char *what)
{
	const char *hold = getenv("KBOOTSET_HOLD");

	fprintf(stderr, "kbootset: step %d %s\n", n, what);
	if (hold && atoi(hold) == n) {
		fprintf(stderr, "kbootset: holding before step %d; cut the power now\n", n);
		fflush(0);
#ifdef KS_SYNC
		sync();
#endif
		for (;;)
			;	/* waits for the power cut */
	}
}

static void
usage(void)
{
	fprintf(stderr,
		"usage: kbootset (--image FILE | --dev PATH) [--offset N] [--journal PATH] COMMAND\n"
		"  create SIZE BOOT2 [--boot1 FILE] [--version N]\n"
		"  status | rollback | collect | mark-bad ID\n"
		"  commit --spec SPEC\n"
		"  mark-good --booted ID [--secondary]\n"
		"  next previous|safe|devload|none|ID\n"
		"  loader-install BOOT2 [--version N] [--boot1 FILE]\n");
	exit(2);
}

static ax_u8 *
slurp(const char *path, ax_u32 *len)
{
	FILE *f = fopen(path, "rb");
	ax_u8 *p;
	long n;

	if (!f) {
		perror(path);
		exit(1);
	}
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	p = malloc(n ? n : 1);
	if (!p || fread(p, 1, n, f) != (size_t)n) {
		perror(path);
		exit(1);
	}
	fclose(f);
	*len = (ax_u32)n;
	return p;
}

static const char *
state(int s)
{
	static const char *const n[] = { "free", "pristine", "good", "trial", "bad" };
	return s >= 0 && s <= 4 ? n[s] : "?";
}

static void
status(const struct ks *k)
{
	int i;

	printf("store: %lu bytes, %lu free; header seq %lu%s%s\n",
	       (unsigned long)k->hdr.store_size, (unsigned long)ks_free(k), (unsigned long)k->hdr.seq,
	       (k->hdr.flags & AXF_READONLY) ? ", read-only" : "",
	       (k->hdr.flags & AXF_LDRTRIAL) ? ", new loader on trial" : "");
	for (i = 0; i < 2; i++)
		if (k->hdr.boot2[i].len)
			printf("loader %s: version %lu, %lu bytes\n", i ? "secondary" : "primary",
			       (unsigned long)k->hdr.boot2[i].ver, (unsigned long)k->hdr.boot2[i].len);
	printf("control seq %lu: default %lu, trial %lu, next boot %u", (unsigned long)k->ctl.seq,
	       (unsigned long)k->ctl.default_gen, (unsigned long)k->ctl.trial_gen, k->ctl.oneshot);
	if (k->ctl.oneshot == AXO_GEN)
		printf(" (generation %lu)", (unsigned long)k->ctl.oneshot_gen);
	printf(", last id %lu\n", (unsigned long)k->ctl.last_id);
	for (i = 0; i < k->ctl.ngen; i++) {
		const struct ax_gen *g = &k->ctl.gen[i];

		printf("  generation %lu  %-8s attempts %u  created %lu  manifest %lu bytes%s\n",
		       (unsigned long)g->id, state(g->state), g->attempts, (unsigned long)g->created,
		       (unsigned long)g->man_len, g->id == k->ctl.default_gen ? "  (default)" : "");
	}
}

/* commit --spec: members from kernel/module root/ramdisk lines (FILE in
 * place of the size, attributes kept, z=deflate honoured); the other
 * lines are copied, except generation and state, which kbootset sets */
static int
commit_spec(struct ks *k, const char *spec)
{
	static struct ks_member m[AXM_MAXMOD + 2];
	static char head[16384], attrs[AXM_MAXMOD + 2][256];
	char line[512], *tok[16], *p;
	struct ks_newgen g;
	FILE *f = fopen(spec, "r");
	ax_u32 id;
	int n, i, fi, nm = 0, rc;
	size_t hl = 0;

	if (!f) {
		perror(spec);
		return 1;
	}
	head[0] = 0;
	while (fgets(line, sizeof(line), f)) {
		char orig[512];

		line[strcspn(line, "\n")] = 0;
		strcpy(orig, line);
		for (n = 0, p = strtok(line, " "); p && n < 16; p = strtok(0, " "))
			tok[n++] = p;
		if (!n || !strcmp(tok[0], "generation") || !strcmp(tok[0], "state"))
			continue;
		fi = (!strcmp(tok[0], "kernel") || !strcmp(tok[0], "ramdisk")) && n >= 3 ? 2 :
		     !strcmp(tok[0], "module") && n >= 4 && !strcmp(tok[2], "root") ? 3 : 0;
		if (!fi) {
			if (hl + strlen(orig) + 2 > sizeof(head))
				return fprintf(stderr, "kbootset: spec too long\n"), 2;
			hl += (size_t)sprintf(head + hl, "%s\n", orig);
			continue;
		}
		if (nm == AXM_MAXMOD + 2)
			return fprintf(stderr, "kbootset: too many members\n"), 2;
		memset(&m[nm], 0, sizeof(m[nm]));
		m[nm].kind = tok[0][0] == 'k' ? AXK_KERNEL : tok[0][0] == 'r' ? AXK_RAMDISK : AXK_MODULE;
		m[nm].name = strcpy(malloc(strlen(tok[1]) + 1), tok[1]);
		m[nm].data = slurp(tok[fi], &m[nm].size);
		attrs[nm][0] = 0;
		for (i = fi + 1; i < n; i++)
			if (!strcmp(tok[i], "z=deflate"))
				m[nm].deflate = 1;
			else if (strlen(attrs[nm]) + strlen(tok[i]) + 2 < sizeof(attrs[nm]))
				sprintf(attrs[nm] + strlen(attrs[nm]), "%s%s", attrs[nm][0] ? " " : "", tok[i]);
		m[nm].attrs = attrs[nm];
		nm++;
	}
	fclose(f);
	for (i = 0; i < nm && m[i].kind != AXK_KERNEL; i++)
		;
	if (i == nm || i != 0)
		return fprintf(stderr, "kbootset: the spec's first member must be its kernel\n"), 2;
	memset(&g, 0, sizeof(g));
	g.head = head;
	g.n = nm;
	g.m = m;
	g.created = getenv("SOURCE_DATE_EPOCH") ? (ax_u32)strtoul(getenv("SOURCE_DATE_EPOCH"), 0, 10) :
		    (ax_u32)time(0);
	rc = ks_commit(k, &g, &id);
	for (i = 0; i < nm; i++)
		free((void *)m[i].data), free((void *)m[i].name);
	return rc;
}

int
main(int argc, char **argv)
{
	static struct ks k;
	struct file d;
	const char *image = 0, *boot1 = 0;
	unsigned long off = 0, version = 1;
	ax_u8 *b1 = 0, *b2;
	ax_u32 len, l1, id = 0;
	int i, rc, secondary = 0, create;
	char **cmd;

	for (i = 1; i < argc && argv[i][0] == '-'; i++) {
		if (i + 1 >= argc)
			usage();
		if (!strcmp(argv[i], "--image") || !strcmp(argv[i], "--dev"))
			image = argv[++i];
		else if (!strcmp(argv[i], "--offset"))
			off = strtoul(argv[++i], 0, 0);
		else if (!strcmp(argv[i], "--journal"))
			jpath = argv[++i];
		else
			usage();
	}
	if (!image || i >= argc)
		usage();
	cmd = argv + i;
	argc -= i;
	create = !strcmp(cmd[0], "create");
	d.base = off;
	if (!(d.f = fopen(image, "r+b")) && !(create && (d.f = fopen(image, "w+b")))) {
		perror(image);
		return 1;
	}
	k.dev.read = fread_;
	k.dev.write = fwrite_;
	k.dev.ctx = &d;
	if (jpath) {
		k.jrn.put = jput;
		k.jrn.get = jget;
		k.jrn.clear = jclear;
	}
#ifdef KS_ZLIB
	k.deflate = zdeflate;
#endif
	k.step = step;
	for (i = 1; i < argc; i++) {		/* the options after the command */
		if (!strcmp(cmd[i], "--boot1") && i + 1 < argc)
			boot1 = cmd[++i];
		else if (!strcmp(cmd[i], "--version") && i + 1 < argc)
			version = strtoul(cmd[++i], 0, 0);
		else if (!strcmp(cmd[i], "--secondary"))
			secondary = 1;
	}
	if (boot1) {
		b1 = slurp(boot1, &l1);
		if (l1 != AX_BOOT1_MAX)
			return fprintf(stderr, "kbootset: boot1 must be 1024 bytes\n"), 2;
	}
	if (create) {
		if (argc < 3)
			usage();
		b2 = slurp(cmd[2], &len);
		rc = ks_create(&k, (ax_u32)strtoul(cmd[1], 0, 0), b1, b2, len, (ax_u32)version);
	} else if ((rc = ks_open(&k)) != KS_OK) {
		;
	} else {
		if (k.msg[0])
			printf("kbootset: %s\n", k.msg);	/* journal recovery */
		k.msg[0] = 0;
		if (!strcmp(cmd[0], "status")) {
			status(&k);
		} else if (!strcmp(cmd[0], "commit") && argc == 3 && !strcmp(cmd[1], "--spec")) {
			rc = commit_spec(&k, cmd[2]);
			if (rc == 2)
				return 2;
		} else if (!strcmp(cmd[0], "mark-good") && argc >= 3 && !strcmp(cmd[1], "--booted")) {
			rc = ks_mark_good(&k, (ax_u32)strtoul(cmd[2], 0, 0), !secondary);
		} else if (!strcmp(cmd[0], "rollback") && argc == 1) {
			rc = ks_rollback(&k, &id);
		} else if (!strcmp(cmd[0], "next") && argc == 2) {
			const char *r = cmd[1];
			rc = !strcmp(r, "previous") ? ks_next(&k, AXO_PREVIOUS, 0) :
			     !strcmp(r, "safe") ? ks_next(&k, AXO_SAFE, 0) :
			     !strcmp(r, "devload") ? ks_next(&k, AXO_DEVLOAD, 0) :
			     !strcmp(r, "none") ? ks_next(&k, AXO_NONE, 0) :
			     ks_next(&k, AXO_GEN, (ax_u32)strtoul(r, 0, 0));
		} else if (!strcmp(cmd[0], "mark-bad") && argc == 2) {
			rc = ks_mark_bad(&k, (ax_u32)strtoul(cmd[1], 0, 0));
		} else if (!strcmp(cmd[0], "collect") && argc == 1) {
			rc = ks_collect(&k);
		} else if (!strcmp(cmd[0], "loader-install") && argc >= 2) {
			b2 = slurp(cmd[1], &len);
			rc = ks_loader_install(&k, b2, len, (ax_u32)version, b1);
		} else {
			usage();
		}
	}
	if (k.msg[0])
		printf("kbootset: %s\n", k.msg);
	fclose(d.f);
	if (rc == KS_EREFUSE)
		return k.gate ? 4 : 3;
	return rc == KS_OK ? 0 : 1;
}
