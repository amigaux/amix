/*
 * dsepoch.c - a datastream that depends only on its inputs and
 * SOURCE_DATE_EPOCH (T-56 D1: the reproducible roll).
 *
 * pkg_epoch() reads SOURCE_DATE_EPOCH.  ds_epoch_fd() rewrites, in place,
 * the newc (070701) header of every member of every cpio archive of a
 * datastream pkgtrans has written: ino renumbered from 1 in archive order
 * (members that share a (dev, ino) share the new number, so hard links stay
 * pairs), uid, gid and dev 0, mtime the epoch, and a directory's nlink 2
 * plus the directories directly under it in the archive.  Names, sizes,
 * modes, data and padding keep their values, but every field of every
 * header, the TRAILER!!!'s too, is written again as "%08lX": the host's
 * cpio writes upper-case hex and the Amix one lower-case (rig E1,
 * 2026-10-31), so a roll on the box is the host's bytes.  On the host that
 * is byte for byte what build/pkg's dsnorm.py makes of the same stream.
 *
 * The file is read and written a header at a time (lseek, read, write),
 * never whole: a datastream may be larger than an Amix process may hold.
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Jussi Alanärä.  A new Amix-port file, not derived from
 * the CDDL heirloom sources -- see heirloom/AMIX-PORT.md, "Licensing".
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "pkglib.h"

#define	DS_HDR_END	"# end of header\n"
#define	NC_HDR		110		/* newc header: magic + 13 fields */
#define	NC_FIELDS	13
#define	F_INO		0		/* the newc fields, in order */
#define	F_MODE		1
#define	F_UID		2
#define	F_GID		3
#define	F_NLINK		4
#define	F_MTIME		5
#define	F_FILESIZE	6
#define	F_DEVMAJOR	7
#define	F_DEVMINOR	8
#define	F_NAMESIZE	11
#define	F_CHECK		12

/*
 * SOURCE_DATE_EPOCH: 0 when unset or empty, 1 when set (*ep is it), -1
 * when it is not a number of seconds.
 */
int
pkg_epoch(long *ep)
{
	char	*s;
	char	*p;
	long	v;

	s = getenv("SOURCE_DATE_EPOCH");
	if (s == NULL || *s == '\0')
		return (0);
	v = 0;
	for (p = s; *p != '\0'; p++) {
		if (*p < '0' || *p > '9' || v > (0x7fffffffL - 9) / 10)
			return (-1);
		v = v * 10 + (*p - '0');
	}
	*ep = v;
	return (1);
}

static int
rd(int fd, long off, char *buf, unsigned n)
{
	if (lseek(fd, (off_t)off, SEEK_SET) == (off_t)-1)
		return (-1);
	return (read(fd, buf, n) == (ssize_t)n ? 0 : -1);
}

static int
wr(int fd, long off, char *buf, unsigned n)
{
	if (lseek(fd, (off_t)off, SEEK_SET) == (off_t)-1)
		return (-1);
	return (write(fd, buf, n) == (ssize_t)n ? 0 : -1);
}

static unsigned long
field(char *hdr, int i)
{
	char	f[9];

	(void) memcpy(f, hdr + 6 + 8 * i, 8);
	f[8] = '\0';
	return (strtoul(f, NULL, 16));
}

static void
put(char *hdr, int i, unsigned long v)
{
	char	f[9];

	(void) sprintf(f, "%08lX", v);
	(void) memcpy(hdr + 6 + 8 * i, f, 8);
}

/* xrealloc that also starts an array (SVR4.0's realloc(NULL) is not to
 * be relied on) */
static void *
grow(void *p, size_t n)
{
	return (p == NULL ? xmalloc(n) : xrealloc(p, n));
}

/* one member: its header, name, and where its header and next one are */
struct ncm {
	long		off;
	long		next;
	char		hdr[NC_HDR];
	char		name[1024];
};

/* read the member at off; 0 = read, -1 = not a newc 070701 member */
static int
member(int fd, long off, struct ncm *m)
{
	unsigned long	ns;
	unsigned long	fs;
	long		data;

	if (rd(fd, off, m->hdr, NC_HDR) != 0 ||
	    memcmp(m->hdr, "070701", 6) != 0)
		return (-1);
	ns = field(m->hdr, F_NAMESIZE);
	fs = field(m->hdr, F_FILESIZE);
	if (ns < 1 || ns > sizeof (m->name) ||
	    rd(fd, off + NC_HDR, m->name, (unsigned)ns) != 0)
		return (-1);
	m->name[ns - 1] = '\0';
	m->off = off;
	data = (off + NC_HDR + (long)ns + 3) / 4 * 4;
	m->next = (data + (long)fs + 3) / 4 * 4;
	return (0);
}

/* the inode map of one archive: (devmajor, devminor, ino) -> new ino */
struct inok {
	unsigned long	maj, min, ino;
	unsigned long	nino;
};

/* the directories of one archive and the directories directly in each */
struct dirk {
	char		*name;
	unsigned long	subdirs;
};

/*
 * Normalise the archive at off; *endp is where its TRAILER!!! member ends.
 * 0 = done, -1 = not newc 070701 or unreadable (why), -2 = I/O error.
 */
static int
archive(int fd, long off, long epoch, long *endp, char *why, unsigned cap)
{
	struct ncm	m;
	struct inok	*ik = NULL;
	struct dirk	*dk = NULL;
	unsigned	ni = 0, nd = 0, i;
	unsigned long	maj, min, ino, mode, nino;
	char		*slash;
	long		o;
	int		rc = 0;

	/* pass 1: the directories, and how many directories sit in each */
	for (o = off; ; o = m.next) {
		if (member(fd, o, &m) != 0) {
			(void) snprintf(why, cap, "the member at %ld is not "
			    "newc 070701", o);
			rc = -1;
			goto out;
		}
		if (strcmp(m.name, "TRAILER!!!") == 0)
			break;
		if (field(m.hdr, F_CHECK) != 0) {
			(void) snprintf(why, cap, "%s has a checksum field; "
			    "not 070701", m.name);
			rc = -1;
			goto out;
		}
		if (S_ISDIR(field(m.hdr, F_MODE))) {
			dk = (struct dirk *)grow(dk,
			    (nd + 1) * sizeof (struct dirk));
			dk[nd].name = xstrdup(m.name);
			dk[nd].subdirs = 0;
			nd++;
		}
	}
	*endp = m.next;
	for (i = 0; i < nd; i++) {
		unsigned	j;

		if ((slash = strrchr(dk[i].name, '/')) == NULL)
			continue;
		*slash = '\0';
		for (j = 0; j < nd; j++)
			if (j != i && strcmp(dk[j].name, dk[i].name) == 0)
				dk[j].subdirs++;
		*slash = '/';
	}

	/* pass 2: rewrite each header */
	for (o = off; ; o = m.next) {
		if (member(fd, o, &m) != 0) {
			rc = -2;
			goto out;
		}
		for (i = 0; i < NC_FIELDS; i++)
			put(m.hdr, (int)i, field(m.hdr, (int)i));
		if (strcmp(m.name, "TRAILER!!!") == 0) {
			if (wr(fd, m.off, m.hdr, NC_HDR) != 0)
				rc = -2;
			break;
		}
		maj = field(m.hdr, F_DEVMAJOR);
		min = field(m.hdr, F_DEVMINOR);
		ino = field(m.hdr, F_INO);
		mode = field(m.hdr, F_MODE);
		for (i = 0; i < ni; i++)
			if (ik[i].maj == maj && ik[i].min == min &&
			    ik[i].ino == ino)
				break;
		if (i == ni) {
			ik = (struct inok *)grow(ik,
			    (ni + 1) * sizeof (struct inok));
			ik[ni].maj = maj;
			ik[ni].min = min;
			ik[ni].ino = ino;
			ik[ni].nino = ni + 1;
			ni++;
		}
		nino = ik[i].nino;
		put(m.hdr, F_INO, nino);
		put(m.hdr, F_UID, 0);
		put(m.hdr, F_GID, 0);
		put(m.hdr, F_DEVMAJOR, 0);
		put(m.hdr, F_DEVMINOR, 0);
		put(m.hdr, F_MTIME, (unsigned long)epoch);
		if (S_ISDIR(mode)) {
			for (i = 0; i < nd; i++)
				if (strcmp(dk[i].name, m.name) == 0)
					break;
			put(m.hdr, F_NLINK, 2 + (i < nd ? dk[i].subdirs : 0));
		}
		if (wr(fd, m.off, m.hdr, NC_HDR) != 0) {
			rc = -2;
			goto out;
		}
	}
out:
	for (i = 0; i < nd; i++)
		free(dk[i].name);
	free(dk);
	free(ik);
	return (rc);
}

/*
 * Normalise every archive of the datastream open (read and write) on fd.
 * 0 = done, -1 = refused (why: not a datastream, not newc), -2 = I/O error.
 */
int
ds_epoch_fd(int fd, long epoch, char *why, unsigned cap)
{
	char	head[8192 + 1];
	char	magic[6];
	char	*end;
	ssize_t	n;
	long	off;
	long	aend;
	int	archives;
	int	rc;

	why[0] = '\0';
	if (lseek(fd, (off_t)0, SEEK_SET) == (off_t)-1 ||
	    (n = read(fd, head, sizeof (head) - 1)) <= 0) {
		(void) snprintf(why, cap, "cannot read the datastream");
		return (-2);
	}
	head[n] = '\0';
	if (strncmp(head, "# PaCkAgE DaTaStReAm\n", 21) != 0 ||
	    (end = strstr(head, DS_HDR_END)) == NULL) {
		(void) snprintf(why, cap, "not a package datastream");
		return (-1);
	}
	off = ((long)(end - head) + (long)strlen(DS_HDR_END) + 511) / 512 * 512;
	archives = 0;
	while (rd(fd, off, magic, 6) == 0 && memcmp(magic, "070701", 6) == 0) {
		if ((rc = archive(fd, off, epoch, &aend, why, cap)) != 0)
			return (rc);
		archives++;
		off = (aend + 511) / 512 * 512;
	}
	if (archives == 0) {
		(void) snprintf(why, cap, "no newc archive after the header");
		return (-1);
	}
	return (0);
}
