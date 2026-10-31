/*
 * testdouble.c -- open/ioctl/close stand-ins for the monswctl host selftest.
 *
 * Every call is appended as one line to $MONSW_TD_LOG (open <path>, ioctl <req> <arg>,
 * close).  MONSW_TD_OPEN_ERRNO / MONSW_TD_IOCTL_ERRNO make the call fail with that errno;
 * MONSW_TD_INFO="config,source,state,holder,ncards" is what GETCFG copies out.
 * Compiled only with -DMONSW_TESTDOUBLE (monsw/test/tooltest.sh); never part of the box binary.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see kernel/modules/LICENSE in the amix repository.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/monsw.h>

static void
td_log(const char *line)
{
	const char *p = getenv("MONSW_TD_LOG");
	FILE *f;

	if (p == NULL)
		return;
	f = fopen(p, "a");
	if (f == NULL)
		return;
	fputs(line, f);
	fputc('\n', f);
	fclose(f);
}

static int
td_errno(const char *var)
{
	const char *p = getenv(var);
	return p ? atoi(p) : 0;
}

int
td_open(const char *path, int flags)
{
	char line[512];
	int e = td_errno("MONSW_TD_OPEN_ERRNO");

	(void)flags;
	sprintf(line, "open %s", path);
	td_log(line);
	if (e) {
		errno = e;
		return -1;
	}
	return 7;
}

int
td_ioctl(int fd, int req, long arg)
{
	char line[128];
	int e = td_errno("MONSW_TD_IOCTL_ERRNO");
	const char *name;

	(void)fd;
	switch (req) {
	case MONSWIOC_RTG:    name = "RTG"; break;
	case MONSWIOC_NATIVE: name = "NATIVE"; break;
	case MONSWIOC_GETCFG: name = "GETCFG"; break;
	case MONSWIOC_SETCFG: name = "SETCFG"; break;
	default:              name = "?"; break;
	}
	if (req == MONSWIOC_GETCFG)
		sprintf(line, "ioctl %s", name);
	else
		sprintf(line, "ioctl %s %ld", name, arg);
	td_log(line);
	if (e) {
		errno = e;
		return -1;
	}
	if (req == MONSWIOC_GETCFG) {
		struct monsw_info *mi = (struct monsw_info *)arg;
		const char *p = getenv("MONSW_TD_INFO");
		int c = 0, s = 0, st = -1, h = 0, n = 0;

		if (p)
			sscanf(p, "%d,%d,%d,%d,%d", &c, &s, &st, &h, &n);
		mi->mi_config = c;
		mi->mi_source = s;
		mi->mi_state = st;
		mi->mi_holder = h;
		mi->mi_ncards = n;
	}
	return 0;
}

int
td_close(int fd)
{
	(void)fd;
	td_log("close");
	return 0;
}
