/*
 * monswtest.c -- the on-box instrument for /dev/monsw (the monsw module or the 68040/68060
 * port's static monsw), one step per run.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see kernel/modules/LICENSE in the amix repository.
 *
 * WHY ONE STEP PER RUN.  The screen is the instrument for the switching steps: a person (or
 * a camera) looks at it between runs.  Each run prints one MONSW-RESULT line a script can
 * read; errors also go to perror.
 *
 *   monswtest get            MONSWIOC_GETCFG: the value in effect, its source, the state,
 *                            the holder flag, the cards registered
 *   monswtest rtg [secs]     MONSWIOC_RTG, then hold /dev/monsw open for secs (default 10):
 *                            expect the RTG picture, then the native one when the device
 *                            closes (the last close of a holder that asked for RTG)
 *   monswtest native         MONSWIOC_NATIVE: expect the native picture
 *   monswtest set <value>    MONSWIOC_SETCFG (root): -1 unsets; expect EBUSY when the value
 *                            is forced (the module's config parameter), EPERM for a user
 *   monswtest bad            MONSWIOC_SETCFG 4 (not a 1/2/16/32 bit sum): expect EINVAL, or
 *                            EBUSY when forced, and no change on screen
 *
 * The device is /dev/monsw (c 52 0).  K&R C for the guest's cc:
 *   cc -I<amix>/kernel/modules/include -o monswtest monswtest.c
 */
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/monsw.h>

#define MONSW_DEV       "/dev/monsw"

extern int errno;

static char *srcname[] = { "none", "seed", "setcfg", "forced" };

static void
usage()
{
	printf("usage: monswtest get | rtg [secs] | native | set <value> | bad\n");
	exit(2);
}

static int
opendev()
{
	int fd;

	fd = open(MONSW_DEV, O_RDWR);
	if (fd < 0) {
		perror("open /dev/monsw");
		printf("MONSW-RESULT OPEN FAIL errno %d\n", errno);
		exit(1);
	}
	return fd;
}

/* a decimal with an optional '-', else usage */
static int
number(s)
char *s;
{
	int v, neg;

	neg = 0;
	if (*s == '-') {
		neg = 1;
		s++;
	}
	if (*s < '0' || *s > '9')
		usage();
	for (v = 0; *s >= '0' && *s <= '9'; s++)
		v = v * 10 + (*s - '0');
	if (*s)
		usage();
	return neg ? -v : v;
}

static void
setcfg(fd, v, bad)
int fd, v, bad;
{
	errno = 0;
	if (ioctl(fd, MONSWIOC_SETCFG, v) == 0) {
		if (bad)
			printf("MONSW-RESULT BAD FAIL (value %d accepted)\n", v);
		else
			printf("MONSW-RESULT SET %d OK\n", v);
		exit(bad ? 1 : 0);
	}
	if (bad && (errno == EINVAL || errno == EBUSY)) {
		printf("MONSW-RESULT BAD PASS (%s)\n", errno == EINVAL ? "EINVAL" : "EBUSY, forced");
		exit(0);
	}
	perror("MONSWIOC_SETCFG");
	printf("MONSW-RESULT %s %d FAIL errno %d%s\n", bad ? "BAD" : "SET", v, errno,
	    errno == EBUSY ? " (the value is forced)" : errno == EPERM ? " (root only)" : "");
	exit(1);
}

main(argc, argv)
int argc;
char **argv;
{
	struct monsw_info mi;
	int fd, secs;

	if (argc < 2)
		usage();
	if (strcmp(argv[1], "get") == 0 && argc == 2) {
		fd = opendev();
		if (ioctl(fd, MONSWIOC_GETCFG, &mi) < 0) {
			perror("MONSWIOC_GETCFG");
			printf("MONSW-RESULT GET FAIL errno %d\n", errno);
			exit(1);
		}
		printf("MONSW-RESULT GET config %d source %s state %d holder %d cards %d\n",
		    mi.mi_config, mi.mi_source >= 0 && mi.mi_source <= 3 ?
		    srcname[mi.mi_source] : "?", mi.mi_state, mi.mi_holder, mi.mi_ncards);
		exit(0);
	}
	if (strcmp(argv[1], "rtg") == 0 && argc <= 3) {
		secs = argc == 3 ? number(argv[2]) : 10;
		fd = opendev();
		if (ioctl(fd, MONSWIOC_RTG, 0) < 0) {
			perror("MONSWIOC_RTG");
			printf("MONSW-RESULT RTG FAIL errno %d\n", errno);
			exit(1);
		}
		printf("MONSW-RESULT RTG OK -- look at the screen; native again in %d s\n", secs);
		fflush(stdout);
		sleep(secs);
		close(fd);
		exit(0);
	}
	if (strcmp(argv[1], "native") == 0 && argc == 2) {
		fd = opendev();
		if (ioctl(fd, MONSWIOC_NATIVE, 0) < 0) {
			perror("MONSWIOC_NATIVE");
			printf("MONSW-RESULT NATIVE FAIL errno %d\n", errno);
			exit(1);
		}
		printf("MONSW-RESULT NATIVE OK -- look at the screen\n");
		exit(0);
	}
	if (strcmp(argv[1], "set") == 0 && argc == 3)
		setcfg(opendev(), number(argv[2]), 0);
	if (strcmp(argv[1], "bad") == 0 && argc == 2)
		setcfg(opendev(), 4, 1);
	usage();
	/*NOTREACHED*/
}
