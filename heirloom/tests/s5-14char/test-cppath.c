/*
 * test-cppath.c - drive pkginstall's cppath() directly.
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
 *
 * cppath() is what pkgadd uses to lay a regular file down on the target
 * system, and write_file() -- the function this harness exists for -- is its
 * private helper.  Linking the real cppath.c against the real host libinst/
 * libpkg means the code under test is the shipping code, not a transcription
 * of it.
 *
 * usage: test-cppath <source-file> <destination-path>
 * exit:  0 = cppath() returned success, 1 = cppath() failed, 2 = usage
 */

#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>

/* the prerequisite chain pkginstall.h needs, in cppath.c's own order */
#include <pkglib.h>
#include "libadm.h"
#include "libinst.h"
#include "install.h"
#include "pkginstall.h"			/* MODE_SET */

extern int cppath(int a_ctrl, char *a_srcPath, char *a_dstPath, mode_t a_mode);

int
main(int argc, char **argv)
{
	int rc;

	if (argc != 3) {
		(void) fprintf(stderr,
			"usage: test-cppath <source> <destination>\n");
		return (2);
	}

	(void) set_prog_name("test-cppath");

	rc = cppath(MODE_SET, argv[1], argv[2], 0644);
	(void) printf("cppath(%s -> %s) rc=%d\n", argv[1], argv[2], rc);

	return (rc == 0 ? 0 : 1);
}
