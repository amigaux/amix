/*
 * fstate.c -- what a process that keeps faulting looks like: fstate PID stops it through /proc, prints its registers, the
 * mappings, and words around its PC, stack frame and address registers, then lets it run.  For a user fault that loops
 * under a handler.
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>

/* the few things of <sys/procfs.h> this needs: that header wants the kernel's signal types in a user compile */
#define PIOC		('q' << 8)
#define PIOCSTOP	(PIOC | 2)
#define PIOCRUN		(PIOC | 4)
#define PIOCGREG	(PIOC | 25)
#define PIOCNMAP	(PIOC | 31)
#define PIOCMAP		(PIOC | 32)
#define NGREG		18
typedef struct {
	caddr_t		pr_vaddr;
	unsigned long	pr_size;
	off_t		pr_off;
	long		pr_mflags;
	long		pr_filler[4];
} prmap_t;

static int fd;

static void words(const char *name, unsigned long a, int n)
{
	unsigned long w[32];
	int i, r;

	if (n > 32)
		n = 32;
	lseek(fd, (off_t)a, 0);
	r = read(fd, (char *)w, n * 4);
	printf("%s %08lx:", name, a);
	if (r <= 0)
		printf(" unreadable (%d)", r);
	for (i = 0; i < r / 4; i++)
		printf("%s %08lx", i && i % 8 == 0 ? "\n   " : "", w[i]);
	printf("\n");
}

int main(int ac, char **av)
{
	char nm[32];
	char st[1024];
	prmap_t m[64];
	int i, nmap = 0, a;
	long r[NGREG];

	if (ac < 2)
		return 2;
	sprintf(nm, "/proc/%05d", atoi(av[1]));
	if ((fd = open(nm, O_RDWR)) < 0) {
		perror(nm);
		return 1;
	}
	alarm(30);
	if (ioctl(fd, PIOCSTOP, st) < 0)
		perror("PIOCSTOP");
	if (ioctl(fd, PIOCGREG, r) < 0) {
		perror("PIOCGREG");
		return 1;
	}
	for (i = 0; i < NGREG; i++)
		printf("r%d=%08lx%s", i, (unsigned long)r[i], (i + 1) % 6 == 0 ? "\n" : " ");
	printf("\n");
	if (ioctl(fd, PIOCNMAP, &nmap) == 0 && nmap < 64 && ioctl(fd, PIOCMAP, m) == 0)
		for (i = 0; i < nmap; i++)
			printf("map %08lx %08lx off %08lx flags %lx\n", (unsigned long)m[i].pr_vaddr, (unsigned long)m[i].pr_size,
			    (unsigned long)m[i].pr_off, (unsigned long)m[i].pr_mflags);
	for (i = 0; i < NGREG; i++)
		if ((unsigned long)r[i] >= 0x1000)
			words("reg", (unsigned long)r[i], 16);
	for (a = 2; a < ac; a++)
		words("arg", strtoul(av[a], (char **)0, 16), 32);
	ioctl(fd, PIOCRUN, 0);
	return 0;
}
