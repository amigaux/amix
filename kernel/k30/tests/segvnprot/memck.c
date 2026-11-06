/*
 * memck.c -- data stays what it was under heavy paging.  memck MB SECS [w] (w maps the anonymous region write-only):
 * an anonymous region and a private copy-on-write
 * one, each page stamped with its own value, re-read and re-stamped in a loop until SECS is up, in a parent and a forked
 * child.  Prints every page that came back wrong, and a total.
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/wait.h>

#define PG 2048

static long check(char *who, unsigned long *p, long pages, unsigned long tag, time_t end)
{
	long i, bad = 0, passes = 0, checked = 0;
	unsigned long gen = 0;

	for (i = 0; i < pages; i++)
		p[i * PG / sizeof(long)] = tag ^ i, p[(i * PG + PG - sizeof(long)) / sizeof(long)] = ~(tag ^ i);
	do {					/* at least one whole check, however long the stamping took */
		for (i = 0; i < pages; i++) {
			unsigned long *a = &p[i * PG / sizeof(long)], *b = &p[(i * PG + PG - sizeof(long)) / sizeof(long)];

			if (*a != ((tag + gen) ^ i) || *b != ~((tag + gen) ^ i)) {
				if (bad++ < 20)
					printf("%s page %ld: %lx %lx, wanted %lx %lx\n", who, i, *a, *b, (tag + gen) ^ i, ~((tag + gen) ^ i));
				fflush(stdout);
			}
			*a = (tag + gen + 1) ^ i;
			*b = ~((tag + gen + 1) ^ i);
			checked++;
		}
		gen++;
		passes++;
	} while (time((time_t *)0) < end);
	printf("%s: %ld passes, %ld pages, %ld checked, %ld bad\n", who, passes, pages, checked, bad);
	fflush(stdout);
	return bad;
}

int main(int ac, char **av)
{
	long mb = ac > 1 ? atol(av[1]) : 8, secs = ac > 2 ? atol(av[2]) : 120, pages = mb * 1024 * 1024 / PG;
	int z = open("/dev/zero", O_RDWR), st;
	unsigned long *p = (unsigned long *)mmap((caddr_t)0, (size_t)(pages * PG), ac > 3 ? PROT_WRITE : PROT_READ | PROT_WRITE, MAP_PRIVATE, z, 0);
	time_t end = time((time_t *)0) + secs;
	pid_t c;
	long i;

	if (p == (unsigned long *)-1) {
		perror("mmap");
		return 9;
	}
	for (i = 0; i < pages; i++)
		p[i * PG / sizeof(long)] = i;		/* present before the fork, so the child's first write copies */
	if ((c = fork()) == 0)
		exit(check("child", p, pages, 0x5a5a0000UL, end) ? 1 : 0);
	i = check("parent", p, pages, 0xa5a50000UL, end);
	waitpid(c, &st, 0);
	printf("memck-done %ld %d\n", i, st);
	return i || st;
}
