/*
 * test-mntinfo.c - host regression test for get_mntinfo()'s sparse-mnttab
 * robustness (AMIX PORT, libinst/mntinfo.c).
 *
 * Calls the REAL libinst get_mntinfo(0, NULL) against the mount table named
 * by $PKG_MNTTAB (the AMIX PORT test/diagnostic override), and exits 0 iff
 * get_mntinfo returned 0 (success).  run.sh drives it with four fixtures:
 *
 *   - a "sparse" table (a /cdrom line but NO "/"): this is the install
 *     miniroot shape.  Pre-fix, get_mntinfo mis-identified /cdrom as the
 *     root and returned 1 (ERR_MNT_NOROOT), aborting the whole datastream
 *     install; the fix synthesizes the always-mounted "/" -> returns 0.
 *   - a "normal" table (contains "/"): returns 0, behaviour unchanged (the
 *     synthesize branch is never entered).
 *   - a MISSING file (open -> ENOENT): the fresh-install-media case (the Amix
 *     miniroot ships no /etc/mnttab).  METAL-FIX.1 treats it as an empty
 *     table and synthesizes "/" -> returns 0.
 *   - an UNREADABLE file (open -> EACCES): a genuine fault -> get_mntinfo
 *     still fails CLOSED -> returns 1.  Only ENOENT is widened; every other
 *     open error stays fatal.
 *
 * The standalone form matters: pkgadd reaches get_mntinfo only inside the
 * pkginstall child, which sets environ = NULL partway through, so PKG_MNTTAB
 * is only reliably visible to a caller that invokes get_mntinfo directly.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license (see compat/amixcompat.h).
 */

#include <stdio.h>
#include <stdlib.h>
#include <sys/mnttab.h>
#include <pkgstrct.h>
#include <pkginfo.h>
#include <pkglocs.h>
#include <pkglib.h>
#include <install.h>
#include <libinst.h>
#include <libadm.h>

/*
 * libinst expects the embedding tool to provide quit() (pkgadd, pkginstall
 * & co all do).  For this test any call to it is itself a finding.
 */
void
quit(int retcode)
{
	(void) fprintf(stderr, "test-mntinfo: quit(%d) called from libinst\n",
	    retcode);
	(void) fflush(stderr);
	exit(90 + (retcode & 7));
}

int
main(void)
{
	int	n;
	char	*tab;

	tab = getenv("PKG_MNTTAB");
	(void) fprintf(stderr, "test-mntinfo: PKG_MNTTAB=<%s>\n",
	    tab ? tab : "(unset)");

	n = get_mntinfo(0, (char *)NULL);
	(void) fprintf(stderr, "test-mntinfo: get_mntinfo -> %d\n", n);
	(void) fflush(stderr);

	return (n == 0 ? 0 : 1);
}
