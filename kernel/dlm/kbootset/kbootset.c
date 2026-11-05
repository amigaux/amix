/*
 * kbootset.c -- the generation composer's command line
 * (docs/spec/40-generations-and-composer.md §3): the commands over the
 * core in ks.c, on a disk image (host media builds) or a raw boot slice
 * (the box).  The same source builds on the host and, statically, for the
 * box.
 *
 * usage: kbootset [-R ROOT] [--image FILE | --dev PATH] [--offset N] [--journal PATH] COMMAND
 *
 * Without --image or --dev, kbootset works on the running box (kbox.c): it
 * reads /dev/kinfo (C2-1), finds the boot store (40 §5, gates 8 and 9)
 * and records it in ROOT/etc/default/bootset (C2-4 §6); the box facts come
 * from the options, then kinfo, then bootset; the journal is
 * ROOT/var/kbootset/journal unless --journal names one; mark-good's
 * --booted and --secondary default to what kinfo's loader record says.
 *   create SIZE BOOT2 [--boot1 FILE] [--version N] [--force]
 *                          lay an empty store (the first 64 KiB zeroed);
 *                          a slice holding a store or a bootblock needs --force
 *   status                                           generations and states
 *   build [--line 30|46] [--bootdev KEY] [--rootdev KEY] [--rootfs TYPE]
 *         [--mem BYTES] [--root REC] [--swap REC]
 *                          compose the next generation from the packages
 *                          installed under ROOT (default /) into
 *                          ROOT/stand/gen/<id>/; every gate; the options
 *                          name the box's facts on a host build (kinfo on
 *                          the box)
 *   commit                 commit the built generation (the gates again);
 *                          nothing when it equals the default generation
 *   commit --again         commit it even then (a repair; the bench rows)
 *   commit --spec SPEC     a generation from a spec (mkstore's format), for
 *                          tests and media built without packages
 *   check                  SHA-256 and CRC-32 of every member in the store,
 *                          the files the manifests name under ROOT, the
 *                          default generation against the installed kernel;
 *                          never writes; status 1 when a problem is found
 *   mark-good [--booted ID] [--secondary]   end of a full multi-user boot
 *   namelist                            /stand/unix for the booted kernel (C2-4 §12)
 *   major NAME             the majors the registry gives module NAME, one
 *                          `c N` or `b N` line each (C2-4 §15); needs no
 *                          store and no kinfo; status 1 for a name the
 *                          registry does not know
 *   major -l               every row of the registry, `NAME c|b N` in its
 *                          order (C2-4 §15, version 18)
 *   cards [DEV]            the running kernel's sd cards from kinfo's card
 *                          table, `card K: cN-cM KEY [base 0xB]` each, KEY the
 *                          controller's match key; with a disk node (cNdMsK)
 *                          only that disk's KEY, as --bootdev and --rootdev
 *                          take it (C2-4 §17); reads kinfo only; status 1
 *                          without kinfo or when the disk's card is not there
 *   nodes                  the sd disk nodes of a four-card kernel under ROOT
 *                          (C4-1 §2.4, C2-4 §14); needs no store; commit
 *                          runs it on the running box, check reports it
 *   retry [--booted ID]    from the base system's fsck-repair reboot path:
 *                          the trial's attempt does not count (40 §3.3);
 *                          writes the boot slice only, nothing on the root
 *   rollback               the default to the previous good generation
 *   default ID             a good or pristine generation becomes the default
 *   next previous|safe|devload|none|ID   for the next boot only
 *   mark-bad ID
 *   collect
 *   loader-install BOOT2 [--version N] [--boot1 FILE]
 *
 * Media (host build only): the pristine generation of a new medium
 * from the packages installed under ROOT, every gate run against the
 * medium's facts and the loader it carries:
 *   media --disk IMG --offset N --size S --boot1 F --boot2 F [--version N] [--force] FACTS
 *   media --disk IMG --offset N --size S --boot1 F --boot2 F [--version N] --ramdisk F FACTS
 *   media --floppy OUT1 OUT2 --boot1 F --boot2 F [--version N] [--ramdisk F] FACTS
 *   media --cd DIR [--cdboot F] [--version N] [--ramdisk F] FACTS
 * A disk store is written by kbootset's own core, members raw; the floppy
 * pair (members deflated) and the CD tree (raw) by mkstore's engine
 * (kmedia.c).  FACTS are the build options above.
 *
 * --version N is the version of the BOOT2 given, as the store header
 * records it for gate 7; it defaults to this kbootset's own loader's
 * (AX_LOADER_VERSION).
 *
 * Power-cut rows (M-GEN3): commit prints
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
#include <sys/types.h>
#include <sys/stat.h>
#include "bootinfo.h"
#include "ks.h"
#include "kbuild.h"
#include "kbox.h"
#include "kmod.h"
#include "kdeflate.h"
#include "knode.h"
#ifdef KS_ZLIB
#include <zlib.h>
#endif
#ifdef KS_SYNC			/* the box build: sync() before a hold; mknod; /dev/scsi */
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/sysmacros.h>
#endif

#define SECTOR	512UL
/* boot1's choice: bit 0 the copy that ran, 0x100 the other was damaged, 0x200
 * the trial's start was spent; 0x300 is the primary, after a damaged secondary */
#define SECONDARY_RAN(ki)	((ki)->boot1_choice & 1)

static void usage(void);

/* /stand/loader holds what the store does not (kb_loader_new); never installed
 * unasked: loader-install is a trial with the old loader kept as the secondary */
#define LOADER_NEW	"; the loader in /stand/loader is not on the boot store yet: " \
			"kbootset loader-install /stand/loader/boot2"
static ax_u8 *slurp(const char *path, ax_u32 *len);

struct file {
	FILE *f;
	unsigned long base;
	long ctl;		/* a disk whose cache is flushed: its cN, or -1 */
};

static int store_sync(struct file *d);

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
		     fwrite(b, 1, n, d->f) != n || fflush(d->f) != 0 || store_sync(d) != 0 ? -1 : 0;
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

/* make each missing directory above path, as mkdir -p would */
static void
mkparents(const char *path)
{
	char d[1024];
	char *s;

	if (strlen(path) >= sizeof d)
		return;
	strcpy(d, path);
	for (s = d + 1; (s = strchr(s, '/')) != 0; s++) {
		*s = 0;
		mkdir(d, 0755);
		*s = '/';
	}
}

static int
jput(void *c, const char *t)
{
	FILE *f;

	(void)c;
	mkparents(jpath);		/* given or default, it may not exist yet */
	f = fopen(jpath, "w");
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

/* the build options naming the box's (or the medium's) facts */
static void
facts_of(char **cmd, int argc, struct kb_facts *f)
{
	int i;

	memset(f, 0, sizeof(*f));
	for (i = 1; i < argc; i++)
		if (!strcmp(cmd[i], "--line") && i + 1 < argc)
			f->line = atoi(cmd[++i]);
		else if (!strcmp(cmd[i], "--bootdev") && i + 1 < argc)
			sprintf(f->bootdev, "%.47s", cmd[++i]);
		else if (!strcmp(cmd[i], "--rootdev") && i + 1 < argc)
			sprintf(f->rootdev, "%.47s", cmd[++i]);
		else if (!strcmp(cmd[i], "--rootfs") && i + 1 < argc)
			sprintf(f->rootfs, "%.15s", cmd[++i]);
		else if (!strcmp(cmd[i], "--mem") && i + 1 < argc)
			f->mem = (ax_u32)strtoul(cmd[++i], 0, 0);
		else if (!strcmp(cmd[i], "--root") && i + 1 < argc)
			sprintf(f->root, "%.127s", cmd[++i]);
		else if (!strcmp(cmd[i], "--swap") && i + 1 < argc)
			sprintf(f->swap, "%.127s", cmd[++i]);
}

static ax_u32
now(void)
{
	return getenv("SOURCE_DATE_EPOCH") ? (ax_u32)strtoul(getenv("SOURCE_DATE_EPOCH"), 0, 10) :
	       (ax_u32)time(0);
}

#ifdef KS_MEDIA
int mkstore_main(int argc, char **argv);

static int
media(const char *root, char **cmd, int argc)
{
	static char spec[32768], msg[400], specpath[1100], vstr[12], ostr[12], sstr[12];
	static struct ks k;
	struct kb_facts f;
	struct file d;
	const char *disk = 0, *fl1 = 0, *fl2 = 0, *cd = 0, *cdboot = 0, *b1p = 0, *b2p = 0, *rd = 0;
	unsigned long off = 0, size = 0, version = AX_LOADER_VERSION;
	int force = 0;
	char *av[24];
	ax_u8 *b1 = 0, *b2;
	ax_u32 l1, l2, id;
	int i, n = 0, rc;
	FILE *sf;

	facts_of(cmd, argc, &f);
	kb_canonkey(f.bootdev);
	kb_canonkey(f.rootdev);
	for (i = 1; i < argc; i++)
		if (!strcmp(cmd[i], "--disk") && i + 1 < argc) disk = cmd[++i];
		else if (!strcmp(cmd[i], "--offset") && i + 1 < argc) off = strtoul(cmd[++i], 0, 0);
		else if (!strcmp(cmd[i], "--size") && i + 1 < argc) size = strtoul(cmd[++i], 0, 0);
		else if (!strcmp(cmd[i], "--floppy") && i + 2 < argc) fl1 = cmd[++i], fl2 = cmd[++i];
		else if (!strcmp(cmd[i], "--cd") && i + 1 < argc) cd = cmd[++i];
		else if (!strcmp(cmd[i], "--cdboot") && i + 1 < argc) cdboot = cmd[++i];
		else if (!strcmp(cmd[i], "--boot1") && i + 1 < argc) b1p = cmd[++i];
		else if (!strcmp(cmd[i], "--boot2") && i + 1 < argc) b2p = cmd[++i];
		else if (!strcmp(cmd[i], "--version") && i + 1 < argc) version = strtoul(cmd[++i], 0, 0);
		else if (!strcmp(cmd[i], "--ramdisk") && i + 1 < argc) rd = cmd[++i];
		else if (!strcmp(cmd[i], "--force")) force = 1;
	if ((!!disk + !!fl1 + !!cd) != 1 || (!cd && (!b1p || !b2p)) || (disk && !size))
		usage();
	if (disk && !rd) {		/* kbootset's own core: create, build, commit */
		b1 = slurp(b1p, &l1);
		b2 = slurp(b2p, &l2);
		if (l1 != AX_BOOT1_MAX)
			return fprintf(stderr, "kbootset: boot1 must be 1024 bytes\n"), 2;
		d.base = off;
		d.ctl = -1;
		if (!(d.f = fopen(disk, "r+b")) && !(d.f = fopen(disk, "w+b"))) {
			perror(disk);
			return 1;
		}
		k.dev.read = fread_;
		k.dev.write = fwrite_;
		k.dev.ctx = &d;
		rc = ks_create(&k, (ax_u32)size, b1, b2, l2, (ax_u32)version, force);
		if (rc == KS_OK)
			rc = kb_build(&k, root, &f, now(), &id);
		if (rc == KS_OK)
			rc = kb_commit(&k, root, &id, 0);
		if (k.msg[0])
			printf("kbootset: %s\n", k.msg);
		fclose(d.f);
		return rc == KS_OK ? 0 : rc == KS_EREFUSE ? (k.gate ? 4 : 3) : 1;
	}
	/* the floppy pair, the CD tree and a disk store that roots on a RAM disk
	 * (the netinstall raw image, C4-3 §1): gated here, written by mkstore's
	 * engine; their loader reads the medium, the kernel never drives it
	 * (C2-4 §13); the disk store is read-only and its members raw, as the CD's */
	if (f.bootdev[0])
		fprintf(stderr, "kbootset: --bootdev is not used for a read-only medium: "
			"its loader reads it, the kernel never drives it\n");
	if (rd && !f.root[0])		/* a RAM-disk medium roots on it (C4-3 section 1) */
		strcpy(f.root, "ramdisk");
	if (rd && !f.swap[0])
		strcpy(f.swap, "none");
	if ((rc = kb_spec(root, &f, (ax_u32)version, now(), fl1 != 0, rd, spec, msg)) != 0) {
		printf("kbootset: %s\n", msg);
		return rc;
	}
	sprintf(specpath, "%.1000s.spec", fl1 ? fl1 : disk ? disk : cd);
	if (!(sf = fopen(specpath, "w")) || fputs(spec, sf) < 0 || fclose(sf) != 0) {
		perror(specpath);
		return 1;
	}
	sprintf(vstr, "%lu", version);
	av[n++] = "kbootset-media";
	if (fl1) {
		av[n++] = "-f";
		av[n++] = "-o"; av[n++] = (char *)fl1;
		av[n++] = "-o"; av[n++] = (char *)fl2;
		av[n++] = "-1"; av[n++] = (char *)b1p;
		av[n++] = "-2"; av[n++] = (char *)b2p;
		av[n++] = "-v"; av[n++] = vstr;
	} else if (disk) {
		sprintf(ostr, "%lu", off);
		sprintf(sstr, "%lu", size);
		av[n++] = "-o"; av[n++] = (char *)disk;
		av[n++] = "-p"; av[n++] = ostr;
		av[n++] = "-s"; av[n++] = sstr;
		av[n++] = "-1"; av[n++] = (char *)b1p;
		av[n++] = "-2"; av[n++] = (char *)b2p;
		av[n++] = "-v"; av[n++] = vstr;
		av[n++] = "-r";
	} else {
		av[n++] = "-C"; av[n++] = (char *)cd;
		if (cdboot) {
			av[n++] = "-x";
			av[n++] = (char *)cdboot;
		}
	}
	av[n++] = specpath;
	av[n] = 0;
	return mkstore_main(n, av);
}
#endif

static void
say(const char *line)
{
	printf("  %s\n", line);
}

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

#ifdef KS_SYNC
/* the node kinfo is read through (C2-3 §1, C2-4 §2): the installer makes
 * it; on a box without it kbootset makes it, character 53, 0, mode 0444 */
static void
kinfo_node(void)
{
	struct stat st;

	if (stat("/dev/kinfo", &st) == 0)
		return;
	if (mknod("/dev/kinfo", S_IFCHR | 0444, makedevice(53, 0)) == 0)
		printf("kbootset: made /dev/kinfo (character device 53, 0), which was missing\n");
	else
		printf("kbootset: /dev/kinfo is missing and cannot be made: the box facts come from "
		       "/etc/default/bootset and the options\n");
}
#endif

static void
usage(void)
{
	fprintf(stderr,
		"usage: kbootset [-R ROOT] [--image FILE | --dev PATH] [--offset N] [--journal PATH] COMMAND\n"
		"  create SIZE BOOT2 [--boot1 FILE] [--version N] [--force]\n"
		"  status | check | rollback | default ID | collect | mark-bad ID\n");
	fprintf(stderr,
		"  build [--line 30|46] [--bootdev KEY] [--rootdev KEY] [--rootfs TYPE] [--mem N]\n"
		"        [--root REC] [--swap REC]\n"
		"  commit [--again | --spec SPEC]\n"
		"  mark-good [--booted ID] [--secondary] | retry [--booted ID] | namelist | nodes\n"
		"  major NAME | major -l | cards [DEV | --probe] | inquiry CARD UNIT | flush CARD UNIT\n"
		"  next previous|safe|devload|none|ID\n"
		"  loader-install BOOT2 [--version N] [--boot1 FILE]\n");
	exit(2);
}

/*
 * The controller number of a disk node's name cNdMsK, or -1.  N is hex, as
 * the stock /dev/dsk names and kbootset nodes write it (C4-1 §2.4): c10d0s0
 * is card 2's unit 0, ced0s1 card 1's unit 6.  'd' is a hex digit too, so
 * the name is read from the right: s and the slice, d and the unit, and
 * what is left after the c is N, one or two lowercase hex digits.
 */
static long
disknode(const char *b)
{
	const char *s, *d;
	long c = 0;

	if (b[0] != 'c' || (s = strrchr(b, 's')) == 0 || !s[1] || strspn(s + 1, "0123456789") != strlen(s + 1))
		return -1;
	for (d = s; d > b + 1 && d[-1] >= '0' && d[-1] <= '9'; d--)
		;
	if (d == s || d[-1] != 'd' || --d - (b + 1) < 1 || d - (b + 1) > 2)
		return -1;
	for (b++; b < d; b++)
		c = 16 * c + (*b >= '0' && *b <= '9' ? *b - '0' : *b >= 'a' && *b <= 'f' ? *b - 'a' + 10 : -1000);
	return c < 0 ? -1 : c;
}

/*
 * `cards [DEV]` (C2-4 §17): the sd cards of the running kernel, from the
 * card table of the kinfo record at path (C2-1 §2), each with the match key
 * of its controller; or, given a disk node, the key of that disk's card,
 * c<8k + unit> (hex) on card k.  It reads nothing else and writes nothing; kp is
 * main's kinfo buffer.
 */
static int inq_line(int card, int unit, char *line, char *why);

static int
cards(const char *path, int n, char **a, struct kb_kinfo *kp)
{
	char key[48], line[80], why[200];
	const char *b = 0, *p;
	long c = -1;
	int i, u, probe = 0;

	if (n == 1 && !strcmp(a[0], "--probe"))	/* each card's units by INQUIRY (C2-4 §18) */
		probe = 1, n = 0;
	if (n > 1)
		usage();
	if (n == 1) {			/* /dev/dsk/cNdMsK, /dev/rdsk/..., or the name alone */
		b = (p = strrchr(a[0], '/')) != 0 ? p + 1 : a[0];
		c = disknode(b);
		if (c < 0) {
			fprintf(stderr, "kbootset: %s is not a disk node (cNdMsK)\n", a[0]);
			return 2;
		}
	}
	if (kb_kinfo_read(path, kp) != 0) {
		fprintf(stderr, "kbootset: no kinfo record at %s: the kernel's sd cards are unknown\n", path);
		return 1;
	}
	for (i = 0; i < kp->ncards; i++) {
		unsigned long k = (unsigned long)kp->card[i].k;

		kb_matchkey(kp->card[i].id, key);
		if (n == 0) {
			if (key[0])
				printf("card %lu: c%lx-c%lx %s", k, 8 * k, 8 * k + 7, key);
			else
				printf("card %lu: c%lx-c%lx unknown controller id 0x%08lx", k, 8 * k, 8 * k + 7,
				    (unsigned long)kp->card[i].id);
			if (kp->card[i].base)
				printf(" base 0x%08lx", (unsigned long)kp->card[i].base);
			printf("\n");
			fflush(stdout);
			for (u = 0; probe && u < 8; u++)
				if (inq_line((int)k, u, line, why) == 0) {
					printf("  unit %d: %s\n", u, line);
					fflush(stdout);
				}
		} else if (k == (unsigned long)c / 8) {
			if (!key[0]) {
				fprintf(stderr, "kbootset: %s: card %lu has the unknown controller id 0x%08lx\n",
				    a[0], k, (unsigned long)kp->card[i].id);
				return 1;
			}
			printf("%s\n", key);
			return 0;
		}
	}
	if (n == 1) {
		fprintf(stderr, "kbootset: %s: the running kernel has no card %ld\n", a[0], c / 8);
		return 1;
	}
	if (kp->ncards == 0)
		fprintf(stderr, "kbootset: the running kernel registered no sd cards\n");
	return 0;
}

/*
 * `inquiry CARD UNIT` and `cards --probe` (C2-4 §18): one SCSI INQUIRY
 * (6-byte CDB, 36 bytes back) through the stock raw passthrough /dev/scsi
 * (char major 11, scsi.c gsioctl: ioctl 'GSIO' with a struct sdcom).  It
 * reads; no other command is sent and no disk is opened, so a unit is
 * known before anything reads it through sd.  The struct is the kernel's
 * gcc 2.7.2.3 layout, written byte by byte: next 0, reading 4, okay 5,
 * status 6, cdb 7, addr 20, nbyte 24, card 28, unit 32, intr 36; 40 bytes.
 * The kernel bounces the data through its static iobuf, which it never
 * clears, so only the bytes the unit says it sent (5 + byte 4) are read.
 * KBOOTSET_SCSIDIR (the host test) takes the answer from the file
 * <dir>/<card>.<unit> instead: its bytes, or no file for no unit.
 */
#define GSIO		0x4753494FUL	/* 'GSIO' */
#define SD_SIZE		40
#define INQ_LEN		36

#ifdef KS_SYNC
static void
put32(ax_u8 *p, unsigned long v)
{
	p[0] = (ax_u8)(v >> 24), p[1] = (ax_u8)(v >> 16), p[2] = (ax_u8)(v >> 8), p[3] = (ax_u8)v;
}
#endif

/* the 36 bytes of an INQUIRY into r; 0, or an errno-like code with why */
static int
inquire(int card, int unit, ax_u8 *r, char *why)
{
	const char *dir = getenv("KBOOTSET_SCSIDIR");

	memset(r, 0, INQ_LEN);
	if (dir && *dir) {
		char p[1100];
		FILE *f;
		size_t n;

		sprintf(p, "%.1000s/%d.%d", dir, card, unit);
		if ((f = fopen(p, "rb")) == 0) {
			sprintf(why, "no answer (selection failed)");
			return 1;
		}
		n = fread(r, 1, INQ_LEN, f);
		fclose(f);
		if (n == 0) {
			sprintf(why, "the command failed");
			return 1;
		}
		return 0;
	}
#ifdef KS_SYNC
	{
		ax_u8 sd[SD_SIZE];
		int fd, e;

		if ((fd = open("/dev/scsi", O_RDONLY)) < 0) {
			sprintf(why, "/dev/scsi: %s (mknod /dev/scsi c 11 0)", strerror(errno));
			return 1;
		}
		memset(sd, 0, sizeof sd);
		sd[4] = 1;				/* reading */
		sd[7] = 0x12;				/* INQUIRY, LUN 0 */
		sd[7 + 4] = INQ_LEN;			/* allocation length */
		put32(sd + 20, (unsigned long)r);	/* addr: the kernel copies out here */
		put32(sd + 24, INQ_LEN);
		put32(sd + 28, (unsigned long)card);
		put32(sd + 32, (unsigned long)unit);
		e = ioctl(fd, (int)GSIO, sd) < 0 ? errno : 0;
		close(fd);
		if (e == ENXIO || e == ENODEV) {
			sprintf(why, "the running kernel has no card %d", card);
			return 1;
		}
		if (e) {
			sprintf(why, "/dev/scsi: %s", strerror(e));
			return 1;
		}
		if (!sd[5]) {
			sprintf(why, "no answer (status 0x%02x)", sd[6]);
			return 1;
		}
		return 0;
	}
#else
	(void)card, (void)unit;
	sprintf(why, "inquiry needs the box's /dev/scsi");
	return 1;
#endif
}

/* ask a unit to put what it holds in a write cache on the medium: one
 * SYNCHRONIZE CACHE (10), no data; 0 when it took it, or a code with why */
static int
scsi_flush(int card, int unit, char *why)
{
#ifdef KS_SYNC
	ax_u8 sd[SD_SIZE];
	int fd, e;

	if ((fd = open("/dev/scsi", O_RDONLY)) < 0) {
		sprintf(why, "/dev/scsi: %s (mknod /dev/scsi c 11 0)", strerror(errno));
		return 1;
	}
	memset(sd, 0, sizeof sd);
	sd[7] = 0x35;
	put32(sd + 28, (unsigned long)card);
	put32(sd + 32, (unsigned long)unit);
	e = ioctl(fd, (int)GSIO, sd) < 0 ? errno : 0;
	close(fd);
	if (e) {
		sprintf(why, "/dev/scsi: %s", strerror(e));
		return 1;
	}
	if (!sd[5] || sd[6]) {
		sprintf(why, "not taken (status 0x%02x)", sd[6]);
		return 1;
	}
	return 0;
#else
	(void)card, (void)unit;
	sprintf(why, "flush needs the box's /dev/scsi");
	return 1;
#endif
}

/*
 * After each store write, before the next: what keeps a box bootable is the
 * order of its writes (C2-4 section 20).  fsync for a file or a block node; a
 * raw node's write has already been completed by the disk.  On gayle the
 * drive's own cache is flushed too; a drive without it is no failure.
 */
static int
store_sync(struct file *d)
{
	char why[200];

#ifdef KS_SYNC
	if (fsync(fileno(d->f)) != 0 && errno == EIO)
		return -1;
#else
	const char *log = getenv("KBOOTSET_SYNCLOG");	/* the host test */
	FILE *f;

	if (log && *log && (f = fopen(log, "a")) != 0) {
		fprintf(f, "flush %ld\n", d->ctl);
		fclose(f);
	}
#endif
	if (d->ctl >= 0)
		(void)scsi_flush((int)(d->ctl >> 3), (int)(d->ctl & 7), why);
	return 0;
}

/* bytes [a, b) of the answer as one word: blanks and NULs trimmed at the
 * end, inner blanks '_', anything not printable '?', all blank "-" */
static void
inq_word(const ax_u8 *r, int a, int b, int got, char *out)
{
	int i, n = 0, end = b < got ? b : got;

	for (i = a; i < end; i++)
		out[n++] = r[i] == 0 || r[i] == ' ' ? ' ' : r[i] < 0x20 || r[i] > 0x7e ? '?' : (char)r[i];
	while (n > 0 && out[n - 1] == ' ')
		n--;
	for (i = 0; i < n; i++)
		if (out[i] == ' ')
			out[i] = '_';
	if (n == 0)
		out[n++] = '-';
	out[n] = 0;
}

/* one unit: its line "type N VENDOR PRODUCT REVISION" into line, or 1 with why */
static int
inq_line(int card, int unit, char *line, char *why)
{
	ax_u8 r[INQ_LEN];
	char v[20], p[20], rev[8];
	int got;

	if (inquire(card, unit, r, why))
		return 1;
	if (r[0] >> 5) {
		sprintf(why, "no unit (qualifier %d)", r[0] >> 5);
		return 1;
	}
	if ((r[0] & 0x1f) == 0x1f) {
		sprintf(why, "no unit (device type 0x1f)");
		return 1;
	}
	got = 5 + r[4];
	inq_word(r, 8, 16, got, v);
	inq_word(r, 16, 32, got, p);
	inq_word(r, 32, 36, got, rev);
	sprintf(line, "type %d %s %s %s", r[0] & 0x1f, v, p, rev);
	return 0;
}

static int
inquiry(int n, char **a)
{
	char line[80], why[200], *e1, *e2;
	long c, u;

	if (n != 2)
		usage();
	c = strtol(a[0], &e1, 10);
	u = strtol(a[1], &e2, 10);
	if (!*a[0] || *e1 || !*a[1] || *e2 || c < 0 || c > 3 || u < 0 || u > 7) {
		fprintf(stderr, "kbootset: inquiry takes a card 0-3 and a unit 0-7\n");
		return 2;
	}
	if (inq_line((int)c, (int)u, line, why)) {
		fprintf(stderr, "kbootset: card %ld unit %ld: %s\n", c, u, why);
		return 1;
	}
	printf("%s\n", line);
	return 0;
}

/* kbootset flush CARD UNIT: does this unit take the store's cache flush */
static int
flushcmd(int n, char **a)
{
	char why[200], *e1, *e2;
	long c, u;

	if (n != 2)
		usage();
	c = strtol(a[0], &e1, 10);
	u = strtol(a[1], &e2, 10);
	if (!*a[0] || *e1 || !*a[1] || *e2 || c < 0 || c > 3 || u < 0 || u > 7) {
		fprintf(stderr, "kbootset: flush takes a card 0-3 and a unit 0-7\n");
		return 2;
	}
	if (scsi_flush((int)c, (int)u, why)) {
		fprintf(stderr, "kbootset: card %ld unit %ld: %s\n", c, u, why);
		return 1;
	}
	printf("card %ld unit %ld: flushed\n", c, u);
	return 0;
}

/* a store on a disk node of a gayle card, cN of its name; anything else, -1 */
static long
store_ctl(const char *path, const struct kb_kinfo *ki)
{
	const char *b = strrchr(path, '/');
	long c = disknode(b ? b + 1 : path);
	char key[48];
	int i;

	if (c < 0 || !ki)
		return -1;
	for (i = 0; i < ki->ncards; i++)
		if ((long)ki->card[i].k == c >> 3) {
			kb_matchkey(ki->card[i].id, key);
			return !strcmp(key, "mobo:gayle") ? c : -1;
		}
	return -1;
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

/* the booted generation's module members, each marked from kinfo's list
 * of the modules actually loaded (C3-5 section 5); why one did not load is
 * on the console */
static void
status_modules(struct ks *k, const struct kb_kinfo *ki)
{
	static struct ax_manifest m;
	char *buf;
	int i, j, n, safe = (ki->flags & 4) != 0;	/* kinfo flag 0x4: a safe boot */

	if ((buf = ks_manifest(k, ki->gen_id, &m)) == 0)
		return;
	if (m.nmod && safe) {	/* the safe set: the records marked safe=1 (C3-5 §3, C2-4 §11) */
		for (i = n = 0; i < m.nmod; i++)
			if (m.mod[i].safe)
				printf("%s%s", n++ ? ", " : "modules: safe mode: only the safe set loads this boot (",
				       m.mod[i].name);
		printf(n ? ")\n" : "modules: safe mode: the safe set is empty; no module loads this boot\n");
	}
	for (i = 0; i < m.nmod; i++) {
		for (j = 0; j < ki->nmods && strcmp(ki->mods[j], m.mod[i].name); j++)
			;
		printf("module %s (%s): %s\n", m.mod[i].name,
		       m.mod[i].cls == AXC_BOOT ? "boot" : m.mod[i].cls == AXC_DEMAND ? "demand" : "root",
		       j < ki->nmods ? "loaded" : safe && !m.mod[i].safe ? "not loaded (safe mode)" :
		       m.mod[i].cls == AXC_DEMAND ? "not loaded (loads at first use: an open of its device or a "
		       "mount of its filesystem type)" :
		       "not loaded (the console says why)");
	}
	free(buf);
}

static void
status(struct ks *k)
{
	static const char *const req[] = { "none", "the previous good generation",
		"generation", "safe mode", "development load" };
	static struct ax_manifest m;
	char *buf;
	int i;

	printf("store: %lu bytes, %lu free; header seq %lu%s%s\n",
	       (unsigned long)k->hdr.store_size, (unsigned long)ks_free(k), (unsigned long)k->hdr.seq,
	       (k->hdr.flags & AXF_READONLY) ? ", read-only" : "",
	       (k->hdr.flags & AXF_LDRTRIAL) ? ", new loader on trial" : "");
	printf("store-id: %08lx\n", (unsigned long)k->hdr.set_id);	/* bootset's store-id= */
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
	if (k->ctl.trial_gen)
		printf("note: generation %lu is on trial: power-cycle to boot it; it becomes good with "
		       "kbootset mark-good at the end of a full boot\n", (unsigned long)k->ctl.trial_gen);
	if (k->ctl.oneshot && k->ctl.oneshot <= AXO_DEVLOAD)
		printf("note: the next boot only: %s%s\n", req[k->ctl.oneshot],
		       k->ctl.oneshot == AXO_GEN ? " (above)" : "");
	if (k->ctl.default_gen && (buf = ks_manifest(k, k->ctl.default_gen, &m)) != 0) {
		if (ks_free(k) < m.kernel.stored)
			printf("warning: a generation the size of the default does not fit "
			       "(%lu bytes free): kbootset collect\n", (unsigned long)ks_free(k));
		free(buf);
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
	const char *image = 0, *boot1 = 0, *root = "/", *booted = 0;
	struct kb_facts facts;
	static struct kb_kinfo ki;
	static char dev[1100], bootset[1100], jdefault[1100];
	const char *kpath = getenv("KBOOTSET_KINFO");
	int have_kinfo = 0, disk = -1, root_given = 0, noroot = 0, force = 0, isfile = 0;
	unsigned long off = 0, version = AX_LOADER_VERSION;
	ax_u8 *b1 = 0, *b2;
	ax_u32 len, l1, id = 0;
	int i, rc, secondary = 0, create;
	char **cmd;

	for (i = 1; i < argc && argv[i][0] == '-'; i++) {
		if (i + 1 >= argc)
			usage();
		if (!strcmp(argv[i], "--image") || !strcmp(argv[i], "--dev")) {
			isfile = argv[i][2] == 'i';
			image = argv[++i];
		}
		else if (!strcmp(argv[i], "--offset"))
			off = strtoul(argv[++i], 0, 0);
		else if (!strcmp(argv[i], "--journal"))
			jpath = argv[++i];
		else if (!strcmp(argv[i], "-R"))
			root = argv[++i], root_given = 1;
		else
			usage();
	}
	if (i < argc && !strcmp(argv[i], "media")) {
#ifdef KS_MEDIA
		return media(root, argv + i, argc - i);
#else
		fprintf(stderr, "kbootset: media builds are the host build's\n");
		return 2;
#endif
	}
	if (i >= argc)
		usage();
	if (!strcmp(argv[i], "nodes") && i + 1 == argc) {	/* no store (C2-4 §14) */
		char nm[300];
		int r = kb_nodes(root, 1, nm);

		printf("kbootset: %s\n", nm);
		return r == KB_ND_FAIL ? 1 : 0;
	}
	if (!strcmp(argv[i], "major")) {	/* the registry only (C2-4 §15) */
		int j, n, t, found = 0;
		const char *own;

		if (i + 2 != argc)
			usage();
		if (!strcmp(argv[i + 1], "-l")) {	/* the whole registry (version 18) */
			for (j = 0; (own = km_entry(j, &t, &n)) != 0; j++)
				printf("%s %c %d\n", own, t, n);
			return 0;
		}
		for (j = 0; (own = km_entry(j, &t, &n)) != 0; j++)
			if (!strcmp(own, argv[i + 1]))
				printf("%c %d\n", t, n), found = 1;
		if (!found)
			fprintf(stderr, "kbootset: no major is registered to %s\n", argv[i + 1]);
		return found ? 0 : 1;
	}
	if (!strcmp(argv[i], "cards"))		/* kinfo only, no store (C2-4 §17) */
		return cards(kpath && *kpath ? kpath : "/dev/kinfo", argc - i - 1, argv + i + 1, &ki);
	if (!strcmp(argv[i], "inquiry"))	/* /dev/scsi only, no store (C2-4 §18) */
		return inquiry(argc - i - 1, argv + i + 1);
	if (!strcmp(argv[i], "flush"))		/* /dev/scsi only, no store (C2-4 section 20) */
		return flushcmd(argc - i - 1, argv + i + 1);
	cmd = argv + i;
	argc -= i;
	create = !strcmp(cmd[0], "create");
	noroot = !strcmp(cmd[0], "retry");	/* the root may be unrepaired: write nothing there */
	sprintf(bootset, "%.1000s/etc/default/bootset", root);
#ifdef KS_SYNC
	if (!image && !(kpath && *kpath) && !noroot)
		kinfo_node();
#endif
	have_kinfo = kb_kinfo_read(kpath && *kpath ? kpath : "/dev/kinfo", &ki) == 0;
	if (!image) {			/* the running box: find the store */
		if (create)
			return fprintf(stderr, "kbootset: create needs --dev or --image\n"), 2;
		rc = kb_find_store(&k, &ki, have_kinfo, bootset, dev, &disk, !noroot);
		if (rc != KS_OK) {
			printf("kbootset: %s\n", k.msg);
			return rc == KS_EREFUSE ? 4 : 1;
		}
		image = dev;
		off = 0;
		if (!jpath && !noroot) {
			sprintf(jdefault, "%.1000s/var/kbootset/journal", root);
			jpath = jdefault;
		}
	}
	d.base = off;
	d.ctl = isfile ? -1 : store_ctl(image, have_kinfo ? &ki : 0);
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
#else
	k.deflate = kb_deflate;		/* the box: no zlib */
#endif
	k.step = step;
	facts_of(cmd, argc, &facts);
	if (have_kinfo)
		kb_kinfo_facts(&ki, &facts);
	if (root_given || image == dev)		/* not the host's own /etc */
		kb_bootset_facts(bootset, &facts);
	if (!facts.bootdev[0] && disk >= 0 && have_kinfo)	/* the disk the store is on */
		for (i = 0; i < ki.ncards; i++)
			if (ki.card[i].k == (ax_u32)disk / 8)
				kb_matchkey(ki.card[i].id, facts.bootdev);
	kb_canonkey(facts.bootdev);		/* the options' and bootset's too */
	kb_canonkey(facts.rootdev);
	for (i = 1; i < argc; i++) {		/* the options after the command */
		if (!strcmp(cmd[i], "--booted") && i + 1 < argc)
			booted = cmd[++i];
		else if (!strcmp(cmd[i], "--boot1") && i + 1 < argc)
			boot1 = cmd[++i];
		else if (!strcmp(cmd[i], "--version") && i + 1 < argc)
			version = strtoul(cmd[++i], 0, 0);
		else if (!strcmp(cmd[i], "--secondary"))
			secondary = 1;
		else if (!strcmp(cmd[i], "--force"))
			force = 1;
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
		rc = ks_create(&k, (ax_u32)strtoul(cmd[1], 0, 0), b1, b2, len, (ax_u32)version, force);
	} else if ((rc = ks_open(&k)) != KS_OK) {
		;
	} else {
		if (k.msg[0])
			printf("kbootset: %s\n", k.msg);	/* journal recovery */
		k.msg[0] = 0;
		if (!strcmp(cmd[0], "status")) {
			status(&k);
			if (kb_loader_new(&k, root))
				printf("note:%s\n", LOADER_NEW + 1);
			if (have_kinfo && KB_MEDIUM(&ki)) {	/* C2-4 section 13 */
				printf("booted: generation %lu of a read-only medium (%s), not of this box's store; "
				       "kernel %s, 680%lu, %lu bytes of fast memory\n", (unsigned long)ki.gen_id,
				       ki.dev_unit == 0xFFFFFFFFUL ? "a CD" : "a floppy pair", ki.build,
				       (unsigned long)ki.cpu, (unsigned long)ki.fast);
				printf("loaded modules (kinfo): %d\n", ki.nmods);
			} else if (have_kinfo && ki.has_axl1) {
				printf("booted: generation %lu, by the %s loader; kernel %s, 680%lu, %lu bytes "
				       "of fast memory\n", (unsigned long)ki.gen_id,
				       SECONDARY_RAN(&ki) ? "secondary" : "primary", ki.build,
				       (unsigned long)ki.cpu, (unsigned long)ki.fast);
				status_modules(&k, &ki);
			} else if (have_kinfo)
				printf("booted: by the stock loader (no loader record); kernel %s\n", ki.build);
			if (have_kinfo) {	/* compare only: status writes nothing */
				char nl[300];
				int r = kb_namelist_run(&k, root, &ki, 0, nl);

				if (r == KB_NL_CURRENT && KB_MEDIUM(&ki))
					printf("namelist: /stand/unix is the medium's kernel's (%s), bound at 0x%08lx\n",
					       ki.build, (unsigned long)ki.bd_tvaddr);
				else if (r == KB_NL_CURRENT)
					printf("namelist: /stand/unix is generation %lu's, bound at 0x%08lx\n",
					       (unsigned long)ki.gen_id, (unsigned long)ki.bd_tvaddr);
				else if (r == KB_NL_STALE)
					printf("%s\n", nl);
				else
					printf("namelist: none (%s)\n", strncmp(nl, "no namelist: ", 13) ? nl : nl + 13);
			}
			printf("facts: line %s, boot %s, root %s, rootfs %s, fast memory %lu\n",
			       facts.line == 30 ? "k30" : facts.line == 46 ? "k46" : "(unknown)",
			       facts.bootdev[0] ? facts.bootdev : "(unknown)",
			       facts.rootdev[0] ? facts.rootdev : "(unknown)",
			       facts.rootfs[0] ? facts.rootfs : "(unknown)", (unsigned long)facts.mem);
		} else if (!strcmp(cmd[0], "check") && argc == 1) {
			int bad = ks_check(&k, say) + kb_check(&k, root, say);

			if (kb_loader_new(&k, root))
				say(LOADER_NEW + 2);

			if (image == dev) {	/* the running box's nodes (C2-4 §14) */
				char nm[300];
				int r = kb_nodes(root, 0, nm);

				if (r != KB_ND_TWO)
					say(nm);
				bad += r == KB_ND_MISSING;
			}

			printf("kbootset: check: %d problem(s)\n", bad);
			fclose(d.f);
			return bad ? 1 : 0;
		} else if (!strcmp(cmd[0], "commit") && argc == 3 && !strcmp(cmd[1], "--spec")) {
			rc = commit_spec(&k, cmd[2]);
			if (rc == 2)
				return 2;
		} else if (!strcmp(cmd[0], "commit") && (argc == 1 || (argc == 2 && !strcmp(cmd[1], "--again")))) {
			rc = kb_commit(&k, root, &id, argc == 2);
			if (rc == KS_OK && kb_loader_new(&k, root))	/* on the line apkg repeats (C2-4 §3) */
				strcat(k.msg, LOADER_NEW);
			if (rc == KS_OK && image == dev && !root_given) {
				char nm[300];	/* before the commit's line, which apkg repeats (C2-4 §3, §14) */
				int r = kb_nodes(root, 1, nm);

				if (r == KB_ND_MADE || r == KB_ND_FAIL)
					printf("kbootset: %s\n", nm);
			}
		} else if (!strcmp(cmd[0], "build")) {
			rc = kb_build(&k, root, &facts, now(), &id);
		} else if (!strcmp(cmd[0], "mark-good") && !booted && have_kinfo && KB_MEDIUM(&ki)) {
			char nl[300];	/* C2-4 section 13: the store did not boot; the namelist still */

			printf("kbootset: booted from a read-only medium (generation %lu of %s): nothing to mark\n",
			       (unsigned long)ki.gen_id, ki.dev_unit == 0xFFFFFFFFUL ? "a CD" : "a floppy pair");
			if (kb_namelist_run(&k, root, &ki, 1, nl) != KB_NL_CURRENT)
				printf("kbootset: %s\n", nl);
		} else if (!strcmp(cmd[0], "retry") && !booted && have_kinfo && KB_MEDIUM(&ki)) {
			fclose(d.f);	/* no trial of this store booted: nothing to give back */
			return 0;
		} else if (!strcmp(cmd[0], "mark-good") && (booted || (have_kinfo && ki.has_axl1))) {
			/* the booted generation, and whether boot1 ran the primary boot2
			 * (choice bit 0 set: the secondary) -- from kinfo by default */
			rc = ks_mark_good(&k, booted ? (ax_u32)strtoul(booted, 0, 0) : ki.gen_id,
					  !secondary && !(have_kinfo && ki.has_axl1 && SECONDARY_RAN(&ki)));
			/* the loader fell back from the default on its own, not by a
			 * menu choice or a one-shot request: verify the default */
			if (rc == KS_OK && have_kinfo && !booted && (ki.axl1_flags & AXLF_FALLBACK) &&
			    !(ki.axl1_flags & AXLF_MENU) && ki.gen_state != AXL_ONESHOT &&
			    ki.gen_state != AXL_MENU)
				rc = ks_refused(&k, ki.gen_id);
			if (rc == KS_OK && have_kinfo && !booted) {	/* every boot (C2-4 §9) */
				char nl[300];

				if (k.msg[0])
					printf("kbootset: %s\n", k.msg);
				k.msg[0] = 0;
				if (kb_namelist_run(&k, root, &ki, 1, nl) != KB_NL_CURRENT)
					printf("kbootset: %s\n", nl);
			}
		} else if (!strcmp(cmd[0], "namelist") && argc == 1) {
			char nl[300];
			int r = kb_namelist_run(&k, root, have_kinfo ? &ki : 0, 1, nl);

			printf("kbootset: %s\n", nl);
			fclose(d.f);
			return r == KB_NL_WRITTEN || r == KB_NL_CURRENT ? 0 : r == KB_NL_NONE ? 3 : 1;
		} else if (!strcmp(cmd[0], "retry") && (booted || (have_kinfo && ki.has_axl1))) {
			rc = ks_retry(&k, booted ? (ax_u32)strtoul(booted, 0, 0) : ki.gen_id);
		} else if (!strcmp(cmd[0], "retry")) {	/* no booted generation known: nothing to give back (C2-4 §7) */
			return 0;
		} else if (!strcmp(cmd[0], "mark-good")) {
			printf("kbootset: which generation booted is unknown (no kinfo loader record); "
			       "name it with --booted\n");
			return 3;
		} else if (!strcmp(cmd[0], "rollback") && argc == 1) {
			rc = ks_rollback(&k, &id);
		} else if (!strcmp(cmd[0], "default") && argc == 2) {
			rc = ks_default(&k, (ax_u32)strtoul(cmd[1], 0, 0));
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
	/* what left the store leaves the root too; only for the store of this root,
	 * and with the running generation known */
	if (rc == KS_OK && (root_given || image == dev) && have_kinfo && ki.has_axl1 && !KB_MEDIUM(&ki) &&
	    (!strcmp(cmd[0], "commit") || !strcmp(cmd[0], "mark-good") || !strcmp(cmd[0], "collect") ||
	     !strcmp(cmd[0], "rollback") || !strcmp(cmd[0], "default") || !strcmp(cmd[0], "mark-bad")))
		kb_gen_sweep(&k, root, ki.gen_id);
	if (k.msg[0])
		printf("kbootset: %s\n", k.msg);
	fclose(d.f);
	if (rc == KS_EREFUSE)
		return k.gate ? 4 : 3;
	return rc == KS_OK ? 0 : 1;
}
