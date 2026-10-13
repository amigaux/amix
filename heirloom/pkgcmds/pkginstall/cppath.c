/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at src/OPENSOLARIS.LICENSE
 * or http://www.opensolaris.org/os/licensing.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at src/OPENSOLARIS.LICENSE.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 *
 * Portions Copyright 2026 Jussi Alanärä.  Amix port changes are marked
 * "AMIX PORT" at each site and listed in heirloom/AMIX-PORT.md.
 */

/*
 * Copyright 2005 Sun Microsystems, Inc.  All rights reserved.
 * Use is subject to license terms.
 */

/* Copyright (c) 1984, 1986, 1987, 1988, 1989 AT&T */
/* All Rights Reserved */

/*	from OpenSolaris "cppath.c	1.20	06/02/27 SMI"	*/

/*
 * Portions Copyright (c) 2007 Gunnar Ritter, Freiburg i. Br., Germany
 *
 * Sccsid @(#)cppath.c	1.2 (gritter) 2/24/07
 */

/*
 * System includes
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <utime.h>
#include <locale.h>
#include <libintl.h>
#include <pkglocs.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>

/*
 * consolidation pkg command library includes
 */

#include <pkglib.h>

/*
 * local pkg command library includes
 */

#include "libadm.h"
#include "libinst.h"
#include "install.h"
#include "messages.h"
#include "pkginstall.h"

/*
 * forward declarations
 */

static int	write_file(char **r_linknam, int a_ctrl, mode_t a_mode,
			char *a_file);
static int	create_path(int a_ctrl, char *a_file);
static int	temp_template(char *a_buf, size_t a_bufsize, char *a_file,
			int a_relative);

/*
 * AMIX PORT: the mkstemp template must survive a 14-character filesystem.
 *
 * Upstream builds write_file()'s template as <target-path> + "XXXXXX".  Amix's
 * root filesystem is System V s5, where a directory entry name is truncated to
 * 14 characters on create AND on lookup.  For a target whose basename is 14
 * characters or longer, EVERY candidate name mkstemp can generate truncates
 * back to the dirent being replaced: each O_CREAT|O_EXCL create returns EEXIST,
 * mkstemp exhausts its tries and fails, and pkgadd dies with ERR_MKTEMP
 * ("unable to create unique temporary file <>" -- mkstemp having emptied the
 * template is the fingerprint).  The overwrite branch is entered only when the
 * target already exists, so fresh installs never see it: what it breaks is
 * re-install and upgrade, for 572 objects of our `full` set and for shipped
 * files as ordinary as /usr/apkg/doc/OPENSOLARIS.LICENSE and
 * /etc/inet/network-config.  Measured and enumerated in
 * ../../../docs/s5-14char-collisions.md section 2.1.
 *
 * The fix shortens the stem, nothing else:
 *
 *   - The temporary stays in the TARGET'S OWN DIRECTORY.  That is load-bearing
 *     and not negotiable: cppath() finishes with rename(temp, target), which is
 *     atomic only within one filesystem, and is what makes replacing a file
 *     that is currently executing safe.  A /tmp (or TMPDIR) template would
 *     cross a mount point on any real Amix layout.
 *   - At most AMIX_TMPL_STEM bytes of the target basename are used, so the
 *     template basename is at most AMIX_S5_NAME_MAX (8 + 6 = 14) bytes: the six
 *     X's survive truncation intact, and every generated name differs from the
 *     target's own dirent.  A basename of 8 characters or less is unaffected --
 *     the template is byte-for-byte upstream's.
 *
 * Collision safety.  Shortening the stem lowers the distinctness of the
 * template, not of the generated name: the 6 X's are exactly the entropy
 * mkstemp had before, and they are now the part that SURVIVES on s5 (they were
 * the part being eaten).  A candidate that happens to be taken is not a
 * failure in either version -- mkstemp retries; compat/amixcompat.c's
 * SVR4-mktemp-based mkstemp() restores the pristine template and retries up to
 * ten times on EEXIST, and that is the mkstemp that runs on the box.  Two
 * pkgadds racing in one directory were arbitrated by the same O_EXCL before
 * this change and are arbitrated by it after; only files whose first 8
 * basename characters agree can now aim at the same candidate, and mktemp's
 * per-process pid component keeps separate processes apart.
 *
 * The cap is deliberately UNCONDITIONAL rather than conditioned on
 * pathconf(_PC_NAME_MAX): a 14-byte temporary name is valid on every
 * filesystem, the name is cosmetic (it lives for the duration of one copy, and
 * only a rename(2) failure ever exposes it -- see the $PKGADM/textbusy log
 * above), and asking a 1991 libc for its opinion would make the fix silently
 * inoperative if that libc answered wrongly.  AMIX_S5_NAME_MAX is the knob if a
 * longer-named filesystem (ufs) ever becomes the target.
 *
 * Compiling with -DAMIX_NO_S5_TEMPLATE_CAP restores the upstream template.
 * DIAGNOSIS ONLY -- it is how heirloom/tests/s5-14char/ demonstrates the defect
 * before demonstrating the fix, in the same spirit as -DAMIX_NO_ATTR_GUARD.
 * Never ship a binary built that way.
 */

#define	TMP_SUFFIX	"XXXXXX"
#define	TMP_SUFFIX_LEN	(sizeof (TMP_SUFFIX) - 1)

#ifndef	AMIX_S5_NAME_MAX
#define	AMIX_S5_NAME_MAX	14		/* s5 dirent name limit */
#endif

#define	AMIX_TMPL_STEM		(AMIX_S5_NAME_MAX - TMP_SUFFIX_LEN)

/*
 * Name:	cppath
 * Description:	copy a path object (install new file on system)
 * Arguments:
 *    - a_cntrl - determine how the destination file mode is set:
 *	|= MODE_0666 - force mode to 0666
 *      |= MODE_SET - mode is a_mode (no mask SET?ID bits)
 *      |= MODE_SRC - mode from source file (mask SET?ID bits)
 *      |= DIR_DISPLAY - display "%s <implied directory>" if directory created
 *    - a_srcPath - path to source to copy
 *    - a_dstPath - path to copy source to
 *    - a_mode - mode to set a_dstpath to (mode controlled by a_ctrl)
 * Returns:	int
 *	== 0 - success
 *	!= 0 - failure
 */

int
cppath(int a_ctrl, char *a_srcPath, char *a_dstPath, mode_t a_mode)
{
	char		*linknam = (char *)NULL;
	int		dstFd;
	int		len;
	int		srcFd;
	long		status;
	struct stat	srcStatbuf;
	struct utimbuf	times;

	/* entry debugging info */

	echoDebug(DBG_CPPATH_ENTRY, a_ctrl, a_mode, a_srcPath, a_dstPath);

	/* open source file for reading */

	srcFd = open(a_srcPath, O_RDONLY);
	if (srcFd < 0) {
		progerr(ERR_OPEN_READ, a_srcPath,
				errno, strerror(errno));
		return (1);
	}

	/* obtain file status of source file */

	if (fstat(srcFd, &srcStatbuf) != 0) {
		progerr(ERR_FSTAT, srcFd, a_srcPath, errno, strerror(errno));
		(void) close(srcFd);
		return (1);
	}

	/*
	 * Determine the permissions mode for the destination:
	 * - if MODE_SET is specified:
	 * --> use a_mode (do not mask off any portion)
	 * --> If a_mode is unknown (? in the pkgmap), then the file gets
	 * --> installed with the default 0644 mode
	 * - if MODE_SRC is specified:
	 * --> use the mode of the source (srcStatbuf.st_mode) but mask off all
	 * --> non-access mode bits (remove SET?UID bits)
	 * - otherwise:
	 * --> use 0666
	 */

	if (a_ctrl & MODE_SET) {
		mode_t	usemode;

		usemode = (a_mode ^ BADMODE) ? a_mode : 0644;
		if (a_mode != usemode && usemode == 0644) {
			logerr(WRN_DEF_MODE, a_dstPath);
			a_mode = usemode;
		}
	} else if (a_ctrl & MODE_SRC) {
		a_mode = (srcStatbuf.st_mode & S_IAMB);
	} else {
		a_mode = 0666;
	}

	/*
	 * Get fd of newly created destination file or, if this
	 * is an overwrite,  a temporary file (linknam).
	 */

	dstFd = write_file(&linknam, a_ctrl, a_mode, a_dstPath);
	if (dstFd < 0) {
		(void) close(srcFd);
		return (1);
	}

	/*
	 * source and target files are open: copy data
	 */

	status = copyFile(srcFd, dstFd, a_srcPath, a_dstPath, &srcStatbuf, 0);

	(void) close(srcFd);
	(void) close(dstFd);

	if (status != 0) {
		progerr(ERR_INPUT, a_srcPath, errno, strerror(errno));
		if (linknam) {
			(void) remove(linknam);
		}
		return (1);
	}

	/*
	 * If this is an overwrite, rename temp over original
	 */

	if ((linknam != (char *)NULL) && (rename(linknam, a_dstPath) != 0)) {
		FILE	*logfp = (FILE *)NULL;
		char	busylog[PATH_MAX];

		/* output log message if busy else program error */

		if (errno == ETXTBSY) {
			logerr(MSG_PROCMV, linknam);
		} else {
			progerr(ERR_OUTPUT_WRITING, a_dstPath, errno,
				strerror(errno));
		}

		(void) remove(linknam);

		/* open the log file and append log entry */

		len = snprintf(busylog, sizeof (busylog),
				"%s/textbusy", get_PKGADM());
		if (len > sizeof (busylog)) {
			progerr(ERR_CREATE_PATH_2, get_PKGADM(),
				"textbusy");
		} else {
			logfp = fopen(busylog, "a");
			if (logfp == NULL) {
				progerr(ERR_LOG, busylog, errno,
					strerror(errno));
			} else {
				(void) fprintf(logfp, "%s\n", linknam);
				(void) fclose(logfp);
			}
		}
	}

	/* set access/modification times for target */

	times.actime = srcStatbuf.st_atime;
	times.modtime = srcStatbuf.st_mtime;

	if (utime(a_dstPath, &times) != 0) {
		progerr(ERR_MODTIM, a_dstPath, errno, strerror(errno));
		return (1);
	}

	/* success! */

	return (0);
}

/*
 * This function creates all of the directory components of the specified path.
 */
static int
create_path(int a_ctrl, char *a_file)
{
	char	*pt;
	int	found = 0;

	for (pt = a_file; *pt; pt++) {
		/* continue if not at path separator or at start of path */

		if ((*pt != '/') || (pt == a_file)) {
			continue;
		}

		/* at '/' - terminate path at current entry */

		*pt = '\0';

		/* continue if path element exists */

		if (access(a_file, F_OK) == 0) {
			*pt = '/';
			continue;
		}

		/* create directory in path */

		if (mkdir(a_file, 0755)) {
			progerr(ERR_MAKE_DIR, a_file, errno, strerror(errno));
			*pt = '/';
			return (1);
		}

		/* display 'implied directory created' message */

		if (a_ctrl & DIR_DISPLAY) {
			echo(MSG_IMPDIR, a_file);
		}

		found++;

		*pt = '/';
	}

	return (!found);
}

/*
 * Name:	write_file
 * Description:	creates a new destination file if the file does not already
 *		exist; otherwise, creates a temporary file and places a
 *		pointer to the temporary file name in 'r_linknam'.
 * Arguments:	r_linknam - pointer to (char*) where name of temporary file
 *			created is returned
 *		a_ctrl - determine if the destination file name is displayed:
 *		     |= DIR_DISPLAY - display "%s <implied directory>"
 *			if directory created
 *		a_mode - permissions mode to set a_file to
 *		a_file - name of destination file to open
 * Returns:	int
 *			success - file descriptor of the file it opened.
 *			failure - returns -1
 */

static int
write_file(char **r_linknam, int a_ctrl, mode_t a_mode, char *a_file)
{
	int		fd = -1;
	int		relative;
	static char	loc_link[PATH_MAX];

	/* entry debugging */

	echoDebug(DBG_WRITEFILE_ENTRY, a_ctrl, a_mode, a_file);

	/* reset pointer to returned 'temporary file name' */

	*r_linknam = (char *)NULL;

	/*
	 * If we are overwriting an existing file, arrange to replace
	 * it transparently.
	 */

	if (access(a_file, F_OK) == 0) {
		/*
		 * link the file to be copied to a temporary name in case
		 * it is executing or it is being written/used (e.g., a shell
		 * script currently being executed
		 */

		relative = RELATIVE(a_file);

		if (relative) {
			logerr(WRN_RELATIVE, a_file);
		}

		/*
		 * AMIX PORT: template built by temp_template() (see above) so
		 * that it fits a 14-character s5 dirent.  A template that does
		 * not fit loc_link is now FATAL: upstream reported it and then
		 * ran mkstemp() on the truncated remains, which can only
		 * create -- or clobber -- the wrong path.
		 */

		if (temp_template(loc_link, sizeof (loc_link), a_file,
				relative) < 0) {
			if (relative) {
				progerr(ERR_CREATE_PATH_3, "./", a_file,
					TMP_SUFFIX);
			} else {
				progerr(ERR_CREATE_PATH_2, a_file, TMP_SUFFIX);
			}
			return (-1);
		}

		/* create and open temporary file */

		fd = mkstemp(loc_link);
		if (fd == -1) {
			progerr(ERR_MKTEMP, loc_link, errno, strerror(errno));
			return (-1);
		}

		/* remember name of temporary file */

		*r_linknam = loc_link;

		/* make sure temporary file has correct mode */

		if (fchmod(fd, a_mode) < 0) {
			progerr(ERR_FCHMOD, loc_link, a_mode, errno,
				strerror(errno));
		}

		return (fd);
	}

	/*
	 * We are not overwriting an existing file, create a new one directly.
	 */

	fd = open(a_file, O_WRONLY | O_CREAT | O_TRUNC, a_mode);
	if (fd == -1) {
		if (create_path(a_ctrl, a_file) == 0) {
			fd = open(a_file, O_WRONLY | O_CREAT | O_TRUNC, a_mode);
		}
	}

	if (fd == -1) {
		progerr(ERR_OPEN_WRITE, a_file, errno, strerror(errno));
	}

	return (fd);
}

/*
 * Name:	temp_template
 * Description:	AMIX PORT.  Compose the mkstemp(3) template used to replace
 *		a_file transparently, bounded so that its basename fits an s5
 *		directory entry (AMIX_S5_NAME_MAX bytes).  The rationale, and
 *		the collision-safety argument, are in the block comment at the
 *		top of this file.
 * Arguments:	a_buf	  - buffer to compose the template into
 *		a_bufsize - size of a_buf
 *		a_file	  - the destination path being replaced
 *		a_relative - non-zero if a_file is relative (template is then
 *			    prefixed "./", as upstream does)
 * Returns:	int
 *		>= 0 - length of the composed template
 *		  -1 - it does not fit a_bufsize (nothing written)
 *
 * The directory part of a_file is copied verbatim -- the temporary MUST be
 * created in the destination's own directory for the rename(2) in cppath() to
 * be an atomic, same-filesystem replacement.  Only the basename stem is
 * shortened.
 */

static int
temp_template(char *a_buf, size_t a_bufsize, char *a_file, int a_relative)
{
	char	*slash;
	char	*stem;
	size_t	dirlen;
	size_t	need;
	size_t	stemlen;
	size_t	stemmax;

	/* split a_file into "directory part" + "basename stem" */

	slash = strrchr(a_file, '/');
	stem = (slash == (char *)NULL) ? a_file : slash + 1;
	dirlen = (size_t)(stem - a_file);	/* includes the '/', if any */
	stemlen = strlen(stem);

#ifdef	AMIX_NO_S5_TEMPLATE_CAP
	/* DIAGNOSIS ONLY: upstream's unbounded template (defect reproducer) */
	stemmax = stemlen;
#else
	stemmax = (size_t)AMIX_TMPL_STEM;
#endif

	if (stemlen > stemmax) {
		stemlen = stemmax;
	}

	/* "./" (relative only) + directory + stem + XXXXXX + NUL */

	need = (a_relative ? 2 : 0) + dirlen + stemlen + TMP_SUFFIX_LEN + 1;
	if (need > a_bufsize) {
		return (-1);
	}

	a_buf[0] = '\0';
	if (a_relative) {
		(void) strcat(a_buf, "./");
	}
	(void) strncat(a_buf, a_file, dirlen);
	(void) strncat(a_buf, stem, stemlen);
	(void) strcat(a_buf, TMP_SUFFIX);

	return ((int)(need - 1));
}
