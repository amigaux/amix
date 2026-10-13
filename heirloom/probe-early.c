/*
 * probe-early.c - on-box probe for the pkgremove early-crash
 * (SIGSEGV right after lockinst), exercising in sequence, with a
 * flushed stderr marker BETWEEN every step so a crash pinpoints the
 * phase:
 *
 *   STEP A: iterate /etc/mnttab with a compiled-in COPY of the Amix
 *           text _getmntent parser (validates the gcc 2.7 codegen of
 *           the same logic), printing every entry;
 *   STEP B: call the REAL libinst get_mntinfo(0, NULL) (runs the real
 *           _getmntent object code + construct_mt + fs_tab build);
 *   STEP C: call the REAL libinst ocfile() against the live
 *           /var/sadm/install/contents - read-only source, the
 *           temporary contents image is MEMORY-ONLY (nothing written
 *           to disk); exercises the CONTENTS_DELTA allocation ladder
 *           (32MB rung fails on Amix -> fallback rungs run).  The
 *           database lock is taken and released like the real tools.
 *   STEP D: sanity-write into the temp image (the exact operation
 *           that crashed pkgremove when vfpSetSize corruption left a
 *           NULL buffer), close everything, release the lock, exit 0.
 *
 * Run:  DS_DEBUG=1 probe-early 2>&1   (DS_DEBUG adds the in-library
 *       traces: per-mnttab-entry, get_mntinfo progress, ocfile rungs)
 *
 * Exit: 0 = all steps passed; 10+N = step N failed cleanly.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license (see compat/amixcompat.h).
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/mnttab.h>
#include <pkgstrct.h>
#include <pkginfo.h>
#include <pkglocs.h>
#include <pkglib.h>
#include <install.h>
#include <libinst.h>
#include <libadm.h>

#define	MARK(s)	{ (void) fprintf(stderr, "PROBE: %s\n", (s)); \
		  (void) fflush(stderr); }

/*
 * libinst expects the embedding tool to provide quit() (pkgadd,
 * pkgremove & co all do); for the probe any call to it is itself a
 * finding, so report and exit with a distinctive code.
 */
void
quit(int retcode)
{
	(void) fprintf(stderr, "PROBE: quit(%d) called from libinst!\n",
	    retcode);
	(void) fflush(stderr);
	exit(90 + (retcode & 7));
}

/* ------------------------------------------------------------------ */
/* STEP A: standalone copy of the Amix text-mnttab parser             */
/* (source-identical to libinst/mntinfo.c _getmntent)                 */
/* ------------------------------------------------------------------ */

#define	A_MNT_LINE_MAX	1024

static int
probe_getmntent(FILE *fp, struct mnttab *tp)
{
	static char line[A_MNT_LINE_MAX];
	char	*p, *lasts;

	for (;;) {
		if (fgets(line, sizeof (line), fp) == NULL)
			return (-1);
		if ((p = strchr(line, '\n')) != NULL)
			*p = '\0';
		if (line[0] == '\0' || line[0] == '#')
			continue;
		if ((tp->mnt_special =
		    strtok_r(line, " \t", &lasts)) == NULL)
			continue;
		if ((tp->mnt_mountp =
		    strtok_r((char *)NULL, " \t", &lasts)) == NULL)
			continue;	/* malformed: no mount point */
		tp->mnt_fstype = strtok_r((char *)NULL, " \t", &lasts);
		if (tp->mnt_fstype == NULL)
			tp->mnt_fstype = "ufs";
		tp->mnt_mntopts = strtok_r((char *)NULL, " \t", &lasts);
		if (tp->mnt_mntopts == NULL)
			tp->mnt_mntopts = "rw";
		tp->mnt_time = strtok_r((char *)NULL, " \t", &lasts);
		if (tp->mnt_time == NULL)
			tp->mnt_time = "0";
		return (0);
	}
}

static int
step_a(const char *table)
{
	FILE	*fp;
	struct mnttab	mt;
	int	n = 0;

	MARK("STEP A: local text parser over the mount table");
	(void) fprintf(stderr, "PROBE: A: table=<%s>\n", table);
	if ((fp = fopen(table, "r")) == NULL) {
		(void) fprintf(stderr, "PROBE: A: fopen errno=%d\n", errno);
		return (1);
	}
	while (probe_getmntent(fp, &mt) == 0) {
		n++;
		(void) fprintf(stderr,
		    "PROBE: A: [%d] special=<%s> mountp=<%s> fstype=<%s> "
		    "opts=<%s> time=<%s>\n", n, mt.mnt_special,
		    mt.mnt_mountp, mt.mnt_fstype, mt.mnt_mntopts,
		    mt.mnt_time);
		(void) fflush(stderr);
	}
	(void) fclose(fp);
	(void) fprintf(stderr, "PROBE: A: done, %d entries\n", n);
	return (n == 0);
}

/* ------------------------------------------------------------------ */

int
main(int argc, char **argv)
{
	VFP_T	*mapvfp = (VFP_T *)NULL;
	VFP_T	*tmpvfp = (VFP_T *)NULL;
	const char	*table;
	int	n;

	table = (argc > 1) ? argv[1] : "/etc/mnttab";

	MARK("start (run with DS_DEBUG=1 for in-library traces)");

	/* ---------------- STEP A ---------------- */
	if (step_a(table) != 0) {
		MARK("STEP A FAILED (clean)");
		return (11);
	}

	/* ---------------- STEP B ---------------- */
	MARK("STEP B: real libinst get_mntinfo(0, NULL)");
	n = get_mntinfo(0, (char *)NULL);
	(void) fprintf(stderr, "PROBE: B: get_mntinfo -> %d\n", n);
	(void) fflush(stderr);
	if (n != 0) {
		MARK("STEP B FAILED (clean)");
		return (12);
	}

	/* ---------------- STEP C ---------------- */
	MARK("STEP C: real libinst ocfile() on the live contents DB");
	n = ocfile(&mapvfp, &tmpvfp, 10UL);
	(void) fprintf(stderr, "PROBE: C: ocfile -> %d (1=ok)\n", n);
	(void) fflush(stderr);
	if (n != 1) {
		MARK("STEP C FAILED (clean)");
		return (13);
	}
	(void) fprintf(stderr,
	    "PROBE: C: tmpvfp start=%s size=%lu curr=%s\n",
	    tmpvfp->_vfpStart ? "non-NULL" : "NULL!!",
	    (unsigned long)tmpvfp->_vfpSize,
	    tmpvfp->_vfpCurr ? "non-NULL" : "NULL!!");
	(void) fflush(stderr);

	/* ---------------- STEP D ---------------- */
	MARK("STEP D: sanity-write into the temp contents image");
	vfpPuts(tmpvfp, "# probe-early sanity line\n");
	(void) fprintf(stderr, "PROBE: D: write ok, overflow=%d\n",
	    tmpvfp->_vfpOverflow);
	(void) fflush(stderr);

	(void) vfpClose(&tmpvfp);
	(void) vfpClose(&mapvfp);
	(void) relslock();

	MARK("ALL STEPS PASSED, exit 0");
	return (0);
}
