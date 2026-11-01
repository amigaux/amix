/*
 * lmmount.c -- the low-memory row's mount: started BEFORE kmhold drains
 * the kernel allocator, it sleeps, then calls mount(2) itself, so the
 * first mount of a demand-class filesystem meets an empty allocator
 * without a fork or an exec of its own on the way.  It says how long
 * mount(2) took and what it returned, then unmounts (umount(2): no
 * mnttab entry is written).
 *
 *     lmmount SECS SPEC DIR [FSTYPE]      (FSTYPE default cdfs)
 *
 * Built with the userland cross compiler: m68k-cbm-sysv4-gcc -O -o
 * lmmount lmmount.c.  tests/bench/README.md, the low-memory rows.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <sys/types.h>
#include <sys/mount.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

extern int mount(), umount();

int
main(argc, argv)
	int argc;
	char **argv;
{
	char *fs = argc > 4 ? argv[4] : "cdfs";
	time_t t0, t1;
	int r, e;

	if (argc < 4) {
		fprintf(stderr, "usage: lmmount SECS SPEC DIR [FSTYPE]\n");
		return 2;
	}
	setbuf(stdout, (char *)0);
	sleep(atoi(argv[1]));
	t0 = time((time_t *)0);
	r = mount(argv[2], argv[3], MS_DATA | MS_RDONLY, fs, (char *)0, 0);
	e = errno;
	t1 = time((time_t *)0);
	printf("lmmount: mount(2) %s %s -F %s: rc %d errno %d after %ld s\n",
	    argv[2], argv[3], fs, r, r < 0 ? e : 0, (long)(t1 - t0));
	if (r == 0)
		printf("lmmount: umount(2) rc %d\n", umount(argv[3]));
	return r == 0 ? 0 : 1;
}
