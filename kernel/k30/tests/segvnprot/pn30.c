/*
 * pn30.c -- what a denied access does on the 68030 kernel: a signal, or a return of EFAULT, never a process that spins
 * or a system call that does not come back.  Each case runs in a child with alarm(10): signal 14 means it spun.
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/wait.h>

#define PG 2048
static int zfd;

static char *map(int len, int prot)
{
	char *p = mmap((caddr_t)0, len, prot, MAP_PRIVATE, zfd, 0);

	if (p == (char *)-1) {
		perror("mmap");
		exit(99);
	}
	return p;
}

static void none_read(void)		{ volatile char *p = map(PG, PROT_NONE); printf("read %d\n", *p); }
static void none_write(void)		{ volatile char *p = map(PG, PROT_NONE); *p = 1; printf("stored\n"); }
static void none_exec(void)		{ void (*f)(void) = (void (*)(void))map(PG, PROT_NONE); f(); printf("returned\n"); }
static void ro_write(void)		{ volatile char *p = map(PG, PROT_READ); *p = 1; printf("stored\n"); }

static void part_ro_write(void)
{
	volatile char *p = map(2 * PG, PROT_READ | PROT_WRITE);

	p[0] = p[PG] = 1;
	if (mprotect((caddr_t)p + PG, PG, PROT_READ) < 0)
		perror("mprotect");
	p[PG] = 2;
	printf("stored\n");
}

static void part_none_read(void)
{
	volatile char *p = map(2 * PG, PROT_READ | PROT_WRITE);

	p[0] = p[PG] = 1;
	if (mprotect((caddr_t)p + PG, PG, PROT_NONE) < 0)
		perror("mprotect");
	printf("read %d\n", p[PG]);
}

/* a long word across a page boundary, the page behind it unmapped or denied */
static char *across(int prot)
{
	char *p = map(2 * PG, PROT_READ | PROT_WRITE);

	p[0] = 1;
	if (prot < 0)
		munmap((caddr_t)p + PG, PG);
	else
		mprotect((caddr_t)p + PG, PG, prot);
	return p + PG - 2;
}
static void across_write_unmapped(void)	{ *(volatile long *)across(-1) = 0x11223344; printf("stored\n"); }
static void across_write_none(void)	{ *(volatile long *)across(PROT_NONE) = 0x11223344; printf("stored\n"); }
static void across_write_ro(void)	{ *(volatile long *)across(PROT_READ) = 0x11223344; printf("stored\n"); }
static void across_read_none(void)	{ printf("read %lx\n", *(volatile long *)across(PROT_NONE)); }

/* the kernel's own copies: -1 EFAULT, not a hang */
static void copyin_none(void)
{
	char *p = map(PG, PROT_NONE);
	int fd = open("/dev/null", O_WRONLY), n = write(fd, p, 4);

	printf("write rc=%d errno %d\n", n, errno);
}

static void copyout_none(void)
{
	char *p = map(PG, PROT_NONE);
	int fd = open("/dev/zero", O_RDONLY), n = read(fd, p, 4);

	printf("read rc=%d errno %d\n", n, errno);
}

static void copyin_part(void)
{
	char *p = across(PROT_NONE);
	int fd = open("/dev/null", O_WRONLY), n = write(fd, p, 4);

	printf("write across rc=%d errno %d\n", n, errno);
}

/* the same through a regular file, whose driver does copy: /dev/null ignores its buffer */
static void copyin_file(void)
{
	char *p = map(PG, PROT_NONE);
	int fd = open("/tmp/pn30.dat", O_RDWR | O_CREAT | O_TRUNC, 0666), n = write(fd, p, 4);

	printf("write rc=%d errno %d\n", n, errno);
}

static void copyout_file(void)
{
	char *p = map(PG, PROT_NONE), b[64];
	int fd = open("/tmp/pn30.dat", O_RDWR | O_CREAT | O_TRUNC, 0666), n;

	memset(b, 1, 64);
	write(fd, b, 64);
	lseek(fd, 0L, 0);
	n = read(fd, p, 4);
	printf("read rc=%d errno %d\n", n, errno);
}

static void copyin_file_ro(void)
{
	char *p = map(PG, PROT_READ);
	int fd = open("/tmp/pn30.dat", O_RDWR | O_CREAT | O_TRUNC, 0666), n = write(fd, p, 4);

	printf("write from PROT_READ rc=%d errno %d (want 4)\n", n, errno);
}

static void copyout_file_ro(void)
{
	char *p = map(PG, PROT_READ), b[64];
	int fd = open("/tmp/pn30.dat", O_RDWR | O_CREAT | O_TRUNC, 0666), n;

	memset(b, 1, 64);
	write(fd, b, 64);
	lseek(fd, 0L, 0);
	n = read(fd, p, 4);
	printf("read into PROT_READ rc=%d errno %d (want -1, 14)\n", n, errno);
}

/* a mapping with execute permission alone: a read is allowed by the hardware, a write must not restart for ever */
static void xonly_write(void)		{ volatile char *p = map(PG, PROT_EXEC); *p = 1; printf("stored\n"); }

static void xonly_copyout(void)
{
	char *p = map(PG, PROT_EXEC), b[64];
	int fd = open("/tmp/pn30.dat", O_RDWR | O_CREAT | O_TRUNC, 0666), n;

	memset(b, 1, 64);
	write(fd, b, 64);
	lseek(fd, 0L, 0);
	n = read(fd, p, 4);
	printf("read rc=%d errno %d\n", n, errno);
}

/* a private file page made write-only: a read succeeds, and so does the kernel's copy of it */
static char *wonly(void)
{
	char b[PG], *p;
	int fd = open("/tmp/pn30.dat", O_RDWR | O_CREAT | O_TRUNC, 0666);

	memset(b, 1, PG);
	write(fd, b, PG);
	p = mmap((caddr_t)0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
	if (p == (char *)-1)
		exit(99);
	mprotect((caddr_t)p, PG, PROT_WRITE);
	return p;
}
static void wonly_read(void)		{ volatile char *p = wonly(); printf("read %d\n", *p); }
static void wonly_copyin(void)
{
	char *p = wonly();
	int fd = open("/tmp/pn30.d2", O_RDWR | O_CREAT | O_TRUNC, 0666), n = write(fd, p, 4);

	printf("write rc=%d errno %d\n", n, errno);
}

/* a read-modify-write of a page it may not write: the fault's read half must not restart for ever */
static void tas_ro(void)		{ volatile char *p = map(PG, PROT_READ); __asm__("tas %0" : "=m" (*p)); printf("stored\n"); }
static void cas_ro(void)
{
	volatile long *p = (volatile long *)map(PG, PROT_READ);
	long o = 0, n = 1;

	__asm__("casl %0,%2,%1" : "=d" (o), "=m" (*p) : "d" (n), "0" (o));
	printf("stored\n");
}

static struct { const char *name; void (*f)(void); } cases[] = {
	{ "read, PROT_NONE", none_read },
	{ "write, PROT_NONE", none_write },
	{ "execute, PROT_NONE", none_exec },
	{ "write, PROT_READ", ro_write },
	{ "write, part made PROT_READ", part_ro_write },
	{ "read, part made PROT_NONE", part_none_read },
	{ "write across, unmapped", across_write_unmapped },
	{ "write across, PROT_NONE", across_write_none },
	{ "write across, PROT_READ", across_write_ro },
	{ "read across, PROT_NONE", across_read_none },
	{ "write(2) from PROT_NONE", copyin_none },
	{ "read(2) into PROT_NONE", copyout_none },
	{ "write(2) across, PROT_NONE", copyin_part },
	{ "write(2) to a file, PROT_NONE", copyin_file },
	{ "read(2) of a file, PROT_NONE", copyout_file },
	{ "write(2) to a file, PROT_READ", copyin_file_ro },
	{ "read(2) of a file, PROT_READ", copyout_file_ro },
	{ "write, PROT_EXEC alone", xonly_write },
	{ "read(2) of a file, PROT_EXEC", xonly_copyout },
	{ "read, private file PROT_WRITE", wonly_read },
	{ "write(2) from that page", wonly_copyin },
	{ "tas, PROT_READ", tas_ro },
	{ "cas, PROT_READ", cas_ro },
	{ 0, 0 }
};

/* pn30 [-u] [FIRST [LAST]]: the cases by number from 1; -u runs them as an ordinary user.  Each line reaches the
 * disk before the next case starts, so a machine that stops still shows how far it got. */
int main(int ac, char **av)
{
	int i = 1, first = 1, last = 99, n, st, a = 1;
	pid_t c;

	if (a < ac && strcmp(av[a], "-u") == 0) {
		setgid(60001);
		setuid(60001);
		a++;
	}
	if (a < ac)
		first = last = atoi(av[a++]);
	if (a < ac)
		last = atoi(av[a++]);
	zfd = open("/dev/zero", O_RDWR);
	for (n = 0; cases[n].name; n++, i++) {
		if (i < first || i > last)
			continue;
		printf("%2d %-30s uid %d: ", i, cases[n].name, (int)geteuid());
		fflush(stdout);
		fsync(1);
		sync();
		if ((c = fork()) == 0) {
			alarm(10);
			cases[n].f();
			fflush(stdout);
			exit(0);
		}
		waitpid(c, &st, 0);
		printf("%s %d\n", WIFSIGNALED(st) ? "signal" : "exit", WIFSIGNALED(st) ? WTERMSIG(st) & 0177 : WEXITSTATUS(st));
		fflush(stdout);
		fsync(1);
		sync();
	}
	printf("pn30-done\n");
	return 0;
}
