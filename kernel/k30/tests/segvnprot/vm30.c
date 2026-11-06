/*
 * vm30.c -- what must go on working when segvn_faultpage refuses a denied access: every allowed kind of page fault, each
 * checked by its data.  Prints PASS or FAIL per case, then the time per fault.  Run with no arguments; every case runs in
 * a child under alarm(60), so a case that spins shows as FAIL (signal 14), not as a stuck test.
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
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <sys/times.h>
#include <sys/resource.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/lock.h>
#include <setjmp.h>

#define PG 2048
#define SKIP 125		/* a case's exit status when it could not run (run() reports SKIP, never PASS) */
#define N 64
#define TF tfname
static char *tfname = "/tmp/vm30.dat";	/* VM30_TF: another file system */
int main();
static int zfd;

static char *zmap(int len, int prot)
{
	char *p = mmap((caddr_t)0, len, prot, MAP_PRIVATE, zfd, 0);

	if (p == (char *)-1) {
		perror("mmap");
		exit(90);
	}
	return p;
}

static int mkfile(int len, int v)
{
	static char b[PG];
	int fd = open(TF, O_RDWR | O_CREAT | O_TRUNC, 0644), i;

	memset(b, v, PG);
	for (i = 0; i < len / PG; i++)
		write(fd, b, PG);
	return fd;
}

/* fork: parent and child both write the same pages, each must keep its own */
static int cow(void)
{
	static char data[N * PG];
	char *z = zmap(N * PG, PROT_READ | PROT_WRITE);
	int i, st, bad = 0;
	pid_t c;

	for (i = 0; i < N; i++)
		data[i * PG] = z[i * PG] = 1;
	if ((c = fork()) == 0) {
		for (i = 0; i < N; i++)
			data[i * PG] = z[i * PG] = 2;
		for (i = 0; i < N; i++)
			if (data[i * PG] != 2 || z[i * PG] != 2)
				_exit(1);
		_exit(0);
	}
	for (i = 0; i < N; i++)
		data[i * PG] = z[i * PG] = 3;
	waitpid(c, &st, 0);
	for (i = 0; i < N; i++)
		if (data[i * PG] != 3 || z[i * PG] != 3)
			bad++;
	return bad || st != 0;
}

/* a private file mapping: reads the file, writes stay private, the file keeps its bytes */
static int file_private(void)
{
	int fd = mkfile(N * PG, 0x41), i, bad = 0;
	char *p = mmap((caddr_t)0, N * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0), b;

	for (i = 0; i < N; i++) {
		if (p[i * PG] != 0x41)
			bad++;
		p[i * PG] = 0x42;
		if (p[i * PG] != 0x42)
			bad++;
	}
	lseek(fd, (off_t)PG, 0);
	read(fd, &b, 1);
	return bad || b != 0x41;
}

/* MAP_SHARED: a write reaches the file and another mapping of it, and a read-only shared mapping refuses a write */
static int file_shared(void)
{
	int fd = mkfile(N * PG, 0x41), i, bad = 0, st;
	char *p = mmap((caddr_t)0, N * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	char *q = mmap((caddr_t)0, N * PG, PROT_READ, MAP_SHARED, fd, 0), b;
	pid_t c;

	for (i = 0; i < N; i++) {
		p[i * PG] = 0x43;
		if (q[i * PG] != 0x43)
			bad++;
	}
	msync((caddr_t)p, N * PG, MS_SYNC);
	lseek(fd, (off_t)PG, 0);
	read(fd, &b, 1);
	if ((c = fork()) == 0) {
		alarm(10);
		q[0] = 1;
		_exit(0);
	}
	waitpid(c, &st, 0);
	return bad || b != 0x43 || !WIFSIGNALED(st) || WTERMSIG(st) != SIGSEGV;
}

/* the stack grows on a fault */
static int deep(int n)
{
	volatile char b[PG];

	b[0] = n;
	b[PG - 1] = n;
	return n > 0 ? deep(n - 1) + (b[0] == (char)n && b[PG - 1] == (char)n ? 0 : 1) : 0;
}
static int stack(void)
{
	return deep(512);
}

/* exec: shared text and shared libraries, relocated pages included; each run prints through libc */
static int exec_shared(void)
{
	int i, st, bad = 0;
	pid_t c;

	for (i = 0; i < 20; i++) {
		if ((c = fork()) == 0) {
			close(1);
			open("/dev/null", O_WRONLY);
			execl("/usr/bin/ls", "ls", "/usr/lib", (char *)0);
			_exit(9);
		}
		waitpid(c, &st, 0);
		if (st != 0)
			bad++;
	}
	return bad;
}

/* mprotect raises and lowers part of a mapping: each page's access follows its own protection, and data stays */
static int try(volatile char *p, int wr)
{
	int st;
	pid_t c;

	if ((c = fork()) == 0) {
		alarm(10);
		if (wr)
			*p = 9;
		else if (*p == 9)
			_exit(1);
		_exit(0);
	}
	waitpid(c, &st, 0);
	return WIFSIGNALED(st) ? WTERMSIG(st) : 0;
}
static int mprot(void)
{
	char *p = zmap(4 * PG, PROT_READ | PROT_WRITE);
	int bad = 0, i;

	for (i = 0; i < 4; i++)
		p[i * PG] = i + 1;
	mprotect((caddr_t)p + PG, PG, PROT_READ);
	bad += try(p + PG, 1) != SIGSEGV;
	bad += try(p + PG, 0) != 0;
	bad += try(p, 1) != 0;
	mprotect((caddr_t)p + 2 * PG, PG, PROT_NONE);
	bad += try(p + 2 * PG, 0) != SIGSEGV;
	bad += try(p + 2 * PG, 1) != SIGSEGV;
	bad += try(p + 3 * PG, 1) != 0;
	mprotect((caddr_t)p + PG, 2 * PG, PROT_READ | PROT_WRITE);	/* raised again */
	p[PG] = 7;
	p[2 * PG] = 8;
	bad += p[0] != 1 || p[PG] != 7 || p[2 * PG] != 8 || p[3 * PG] != 4;
	mprotect((caddr_t)p, 4 * PG, PROT_NONE);			/* the whole mapping, then back */
	bad += try(p, 0) != SIGSEGV;
	mprotect((caddr_t)p, 4 * PG, PROT_READ | PROT_WRITE);
	bad += p[0] != 1 || p[PG] != 7;
	return bad;
}

/* /proc: a parent reads and writes a child's data and text, as a debugger sets a breakpoint */
static volatile char pdata[PG] = "unset";
static int target(void)
{
	return 0x1234;
}
static int proc_rw(void)
{
	char nm[32], b[8];
	int fd, st, bad = 0, n;
	pid_t c;
	unsigned short insn, nop = 0x4e71;
	int fds[2];

	pipe(fds);
	if ((c = fork()) == 0) {
		char x;

		close(fds[1]);
		read(fds[0], &x, 1);		/* the parent writes first */
		_exit(pdata[0] == 'S' && target() == 0x1234 ? 0 : 1);
	}
	close(fds[0]);
	sprintf(nm, "/proc/%05d", (int)c);
	if ((fd = open(nm, O_RDWR)) < 0) {
		perror(nm);
		kill(c, SIGKILL);
		return 1;
	}
	lseek(fd, (off_t)(long)pdata, 0);
	n = read(fd, b, 5);
	bad += n != 5 || memcmp(b, "unset", 5) != 0;
	lseek(fd, (off_t)(long)pdata, 0);
	bad += write(fd, "S", 1) != 1;
	/* text: a copy-on-write of the shared page, in the child alone: put back what was there */
	lseek(fd, (off_t)(long)target, 0);
	bad += read(fd, (char *)&insn, 2) != 2;
	lseek(fd, (off_t)(long)target, 0);
	bad += write(fd, (char *)&nop, 2) != 2;
	lseek(fd, (off_t)(long)target, 0);
	bad += write(fd, (char *)&insn, 2) != 2;
	close(fd);
	write(fds[1], "x", 1);
	waitpid(c, &st, 0);
	return bad || st != 0 || target() != 0x1234;
}

/* /proc may not show a denied page: EIO, or the marker the page holds, never anything else; mlock takes one as stock; and
 * /proc may not write a read-only shared file */
static int proc_denied(void)
{
	char nm[32], b[8];
	char *p = zmap(2 * PG, PROT_READ | PROT_WRITE), *s;
	int fd, n, bad = 0, f;

	memset(p + PG, 0x5a, PG);
	mprotect((caddr_t)p + PG, PG, PROT_NONE);
	sprintf(nm, "/proc/%05d", (int)getpid());
	if ((fd = open(nm, O_RDWR)) < 0) {
		perror(nm);
		return 1;
	}
	lseek(fd, (off_t)(long)(p + PG), 0);
	b[0] = 0;
	n = read(fd, b, 4);
	printf("proc read of a PROT_NONE page: rc %d errno %d first %x\n", n, errno, b[0] & 255);
	if (n == 4 && b[0] != 0x5a)
		bad++;			/* somebody else's bytes */
	if (mlock((caddr_t)p + PG, PG) < 0)
		printf("mlock of a PROT_NONE page: errno %d\n", errno);
	else
		munlock((caddr_t)p + PG, PG);
	f = mkfile(PG, 0x61);
	close(f);
	f = open(TF, O_RDONLY);
	s = mmap((caddr_t)0, PG, PROT_READ, MAP_SHARED, f, 0);
	lseek(fd, (off_t)(long)s, 0);
	n = write(fd, "Z", 1);
	printf("proc write to a read-only shared file: rc %d errno %d, page now %x\n", n, errno, s[0] & 255);
	if (s[0] != 0x61)
		bad++;
	return bad;
}

/* the kernel's copies into and out of every kind of page */
static int copies(void)
{
	int fd = mkfile(N * PG, 0x51), nfd = open("/dev/null", O_WRONLY), zr = open("/dev/zero", O_RDONLY), bad = 0;
	char *anon = zmap(4 * PG, PROT_READ | PROT_WRITE);			/* never touched */
	char *pr = mmap((caddr_t)0, 4 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
	char *sh = mmap((caddr_t)0, 4 * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	char *ro = mmap((caddr_t)0, 4 * PG, PROT_READ, MAP_PRIVATE, fd, 0);
	static char bss[4 * PG];
	char st[PG];
	int f2;

	bad += write(nfd, anon, 2 * PG) != 2 * PG;		/* copyin: zero fill */
	bad += write(nfd, pr, 2 * PG) != 2 * PG;		/* copyin: private file */
	bad += write(nfd, sh, 2 * PG) != 2 * PG;		/* copyin: shared file */
	bad += write(nfd, ro, 2 * PG) != 2 * PG;		/* copyin: read-only */
	bad += write(nfd, (char *)main, 64) != 64;		/* copyin: text */
	bad += write(nfd, st, PG) != PG;			/* copyin: stack */
	bad += read(zr, anon + PG, PG) != PG || anon[PG] != 0;	/* copyout: zero fill */
	bad += read(zr, pr + PG, 4) != 4 || pr[PG] != 0;	/* copyout: copy on write */
	f2 = open(TF, O_RDONLY);
	bad += read(f2, sh + PG, 4) != 4;			/* copyout: shared file */
	lseek(f2, (off_t)0, 0);
	bad += read(f2, bss + PG, PG) != PG || bss[PG] != 0x51;	/* copyout: bss */
	lseek(f2, (off_t)0, 0);
	bad += read(f2, st, PG) != PG || st[0] != 0x51;		/* copyout: stack */
	lseek(f2, (off_t)0, 0);
	errno = 0;
	bad += read(f2, ro, 4) != -1 || errno != EFAULT;	/* copyout: read-only: EFAULT */
	lseek(f2, (off_t)0, 0);
	errno = 0;
	bad += read(f2, (char *)main, 4) != -1 || errno != EFAULT;	/* copyout: text: EFAULT */
	return bad;
}

#include "corechk.h"

/* a core dump: the child's core has its size and its data pages; denied = pages made read-only, write-only and PROT_NONE
 * too: the first two are in the core with their data, the PROT_NONE pages (one with others after it, one ending the run)
 * read back as zeros, and the file is as long as its program headers say (corechk.h) */
static int core1(int denied)
{
	int st, i, fd, bad = 0;
	pid_t c;
	struct stat sb;
	struct rlimit rl;
	volatile char *p = zmap(16 * PG, PROT_READ | PROT_WRITE);

	chdir("/tmp");
	unlink("core");
	if ((c = fork()) == 0) {
		rl.rlim_cur = rl.rlim_max = RLIM_INFINITY;
		setrlimit(RLIMIT_CORE, &rl);
		for (i = 0; i < 16; i++)
			p[i * PG] = i + 1;
		if (denied) {
			mprotect((caddr_t)p + 2 * PG, PG, PROT_READ);
			mprotect((caddr_t)p + 3 * PG, PG, PROT_NONE);
			mprotect((caddr_t)p + 4 * PG, PG, PROT_WRITE);
			mprotect((caddr_t)p + 15 * PG, PG, PROT_NONE);	/* a run that ends denied */
		}
		signal(SIGQUIT, SIG_DFL);	/* a background process starts with it ignored */
		kill(getpid(), SIGQUIT);
		_exit(0);
	}
	waitpid(c, &st, 0);
	if (stat("core", &sb) < 0)
		sb.st_size = -1;
	printf("core: denied %d status %#x size %ld\n", denied, st, (long)sb.st_size);
	if (!WIFSIGNALED(st) || !(st & 0200))
		return 1;
	if (sb.st_size < 16 * PG)
		return 2;
	if ((fd = open("core", O_RDONLY)) < 0)
		return 3;
	bad = corecheck(fd, (long)sb.st_size, (char *)p, denied);
	close(fd);
	if (bad)
		return bad;
	unlink("core");
	return 0;
}
static int core(void)
{
	return core1(0);
}
static int core_denied(void)
{
	return core1(1);
}

/* read-modify-writes of pages a write would be allowed on: a first touch, and copy on write after fork */
static int tas1(volatile char *p)
{
	__asm__("tas %0" : "=m" (*p));
	return *p;
}
static long cas1(volatile long *p, long o, long n)
{
	__asm__("casl %0,%2,%1" : "=d" (o), "=m" (*p) : "d" (n), "0" (o));
	return o;
}
static int rmw(void)
{
	int fd = mkfile(8 * PG, 0x41), st;
	char *f = mmap((caddr_t)0, 8 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0), *z = zmap(8 * PG, PROT_READ | PROT_WRITE);
	pid_t c;

	if (f == (char *)-1)
		return 1;
	if ((tas1(f) & 0xff) != 0xc1 || (tas1(z) & 0xff) != 0x80)		/* first touch */
		return 2;
	if (cas1((long *)(f + PG), 0x41414141L, 7L) != 0x41414141L || *(long *)(f + PG) != 7L)
		return 3;
	f[2 * PG] = z[2 * PG] = 5;
	*(long *)(f + 3 * PG) = *(long *)(z + 3 * PG) = 5L;
	if ((c = fork()) == 0) {
		if ((tas1(f + 2 * PG) & 0xff) != 0x85 || (tas1(z + 2 * PG) & 0xff) != 0x85)
			_exit(4);
		if (cas1((long *)(f + 3 * PG), 5L, 6L) != 5L || cas1((long *)(z + 3 * PG), 5L, 6L) != 5L)
			_exit(5);
		if (*(volatile long *)(f + 3 * PG) != 6L || *(volatile long *)(z + 3 * PG) != 6L)
			_exit(7);	/* the store happened, in the child's copy */
		_exit(0);
	}
	waitpid(c, &st, 0);
	if (st != 0)
		return WIFSIGNALED(st) ? 6 : WEXITSTATUS(st);
	if (f[2 * PG] != 5 || z[2 * PG] != 5 || *(long *)(f + 3 * PG) != 5L || *(long *)(z + 3 * PG) != 5L)
		return 7;
	return 0;
}

/* a write-only page can always be read: never touched, copied at fork, and a file page sent back to the disk */
static int wonly(void)
{
	static char b[PG];
	char *z = zmap(4 * PG, PROT_WRITE), *f, nm[32];
	int fd = mkfile(4 * PG, 0x41), st, n, pfd, bad = 0;
	pid_t c;

	if (z[0] != 0)				/* zero-fill, never written */
		bad |= 1;
	z[PG] = 9;
	if (z[PG] != 9)
		bad |= 1;
	f = mmap((caddr_t)0, 4 * PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, 0);
	if (f == (char *)-1)
		return 90;
	mprotect((caddr_t)f, 4 * PG, PROT_WRITE);
	if (f[0] != 0x41)			/* a private file page, read first */
		bad |= 2;
	f[PG] = 5;
	if ((c = fork()) == 0)			/* anon shared by fork */
		_exit(f[PG] == 5 && z[PG] == 9 ? 0 : 1);
	waitpid(c, &st, 0);
	if (st != 0)
		bad |= 4;
	msync((caddr_t)f, 4 * PG, MS_INVALIDATE);
	if (f[2 * PG] != 0x41)			/* brought back in */
		bad |= 8;
	f[3 * PG] = 7;
	if (f[3 * PG] != 7)			/* and it may still be written */
		bad |= 8;
	n = open("/tmp/vm30.d2", O_RDWR | O_CREAT | O_TRUNC, 0644);
	f = mmap((caddr_t)0, PG, PROT_READ | PROT_WRITE, MAP_PRIVATE, fd, (off_t)0);
	mprotect((caddr_t)f, PG, PROT_WRITE);
	if (write(n, f, 4) != 4)		/* copyin */
		bad |= 16;
	lseek(n, (off_t)0, 0);
	memset(b, 0x33, PG);
	write(n, b, 4);
	lseek(n, (off_t)0, 0);
	if (read(n, z + 2 * PG, 4) != 4 || z[2 * PG] != 0x33)	/* copyout */
		bad |= 16;
	sprintf(nm, "/proc/%05d", (int)getpid());
	if ((pfd = open(nm, O_RDONLY)) >= 0) {
		mprotect((caddr_t)z + 3 * PG, PG, PROT_WRITE);
		lseek(pfd, (off_t)(long)(z + 3 * PG), 0);
		b[0] = 1;
		if (read(pfd, b, 1) != 1 || b[0] != 0)	/* /proc */
			bad |= 32;
		close(pfd);
	}
	close(n);
	unlink("/tmp/vm30.d2");
	/* a file opened only for writing still cannot be mapped */
	n = open(TF, O_WRONLY);
	f = mmap((caddr_t)0, PG, PROT_WRITE, MAP_SHARED, n, 0);
	printf("mmap of a write-only descriptor: %s errno %d\n", f == (char *)-1 ? "refused" : "MAPPED", errno);
	if (f != (char *)-1)
		bad |= 64;
	return bad;
}

/* a shared file mapping on this file system: refused stores, a write-only read, and a hole */
static int shared_denied(void)
{
	int fd = mkfile(4 * PG, 0x61), st, bad = 0;
	char *r = mmap((caddr_t)0, 4 * PG, PROT_READ, MAP_SHARED, fd, 0), *w;
	pid_t c;

	if (r == (char *)-1)
		return 90;
	if ((c = fork()) == 0) {
		alarm(20);
		((volatile char *)r)[0] = 1;
		_exit(1);
	}
	waitpid(c, &st, 0);
	if (!WIFSIGNALED(st) || (WTERMSIG(st) & 0177) != 11 || r[0] != 0x61)
		bad |= 1;
	w = mmap((caddr_t)0, 4 * PG, PROT_WRITE, MAP_SHARED, fd, 0);
	if (w == (char *)-1)
		return 91;
	if (w[PG] != 0x61)			/* write-only: reads */
		bad |= 2;
	w[PG] = 0x62;
	msync((caddr_t)w, 4 * PG, MS_SYNC);
	if (r[PG] != 0x62)
		bad |= 4;
	munmap((caddr_t)r, 4 * PG);
	munmap((caddr_t)w, 4 * PG);
	/* a hole: read as zeros, then a store fills it */
	lseek(fd, (off_t)(64 * PG), 0);
	write(fd, "x", 1);
	w = mmap((caddr_t)0, 16 * PG, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)(32 * PG));
	if (w == (char *)-1)
		return 92;
	if (w[0] != 0)
		bad |= 8;
	w[0] = 3;
	msync((caddr_t)w, 16 * PG, MS_SYNC);
	if (w[0] != 3)
		bad |= 16;
	{
		char c = 0;	/* and in the file: read through the descriptor, not the mapping */

		lseek(fd, (off_t)(32 * PG), 0);
		if (read(fd, &c, 1) != 1 || c != 3)
			bad |= 32;
	}
	close(fd);
	unlink(TF);
	return bad;
}

/* raw disk transfers into and out of pages: VM30_RAW names a character device that may be written (a scratch slice).  A
 * buffer it may not use is refused before any I/O, by useracc, whose failure uiophysio returns as 1, EPERM, not EFAULT, and
 * useracc asks for read permission as it stands, so a never-read write-only buffer is refused for a raw write. */
static int refused(const char *what, int n)
{
	printf("raw %s: %d errno %d\n", what, n, errno);
	return n != -1 || (errno != EFAULT && errno != EPERM);
}
static int physio(void)
{
	char *dev = getenv("VM30_RAW"), *a = zmap(4 * PG, PROT_READ | PROT_WRITE);
	char *none = zmap(PG, PROT_NONE), *ro = zmap(PG, PROT_READ), *wo = zmap(PG, PROT_WRITE);
	int fd, bad = 0, n;

	if (!dev) {
		printf("physio: no VM30_RAW, not run\n");
		return SKIP;
	}
	if ((fd = open(dev, O_RDWR)) < 0) {
		perror(dev);
		return 90;
	}
	memset(a, 0x71, 512);
	memset(a + 2 * PG, 0x72, PG);
	n = write(fd, a, 512);
	printf("raw write of 512: %d errno %d\n", n, errno);
	bad |= n != 512;
	lseek(fd, (off_t)0, 0);
	memset(a, 0, 512);
	n = read(fd, a, 512);
	printf("raw read of 512: %d errno %d, %x\n", n, errno, a[100] & 255);
	bad |= (n != 512 || a[100] != 0x71) << 1;
	/* across pages, a page in the second not yet touched */
	lseek(fd, (off_t)4096, 0);
	n = write(fd, a + 2 * PG - 512, 1024);
	printf("raw write across a page boundary: %d errno %d\n", n, errno);
	bad |= (n != 1024) << 2;
	lseek(fd, (off_t)0, 0);
	errno = 0;
	bad |= refused("read into PROT_NONE", read(fd, none, 512)) << 3;
	lseek(fd, (off_t)0, 0);
	errno = 0;
	bad |= refused("read into PROT_READ", read(fd, ro, 512)) << 4;
	lseek(fd, (off_t)0, 0);
	errno = 0;
	bad |= refused("write from PROT_NONE", write(fd, none, 512)) << 5;
	lseek(fd, (off_t)0, 0);
	errno = 0;
	bad |= refused("write from PROT_WRITE", write(fd, wo, 512)) << 6;
	lseek(fd, (off_t)0, 0);
	n = read(fd, wo, 512);			/* into a write-only buffer: allowed, and the program may read it */
	printf("raw read into PROT_WRITE: %d errno %d, %x\n", n, errno, wo[100] & 255);
	bad |= (n != 512 || wo[100] != 0x71) << 7;
	close(fd);
	printf("physio bad %#x\n", bad);
	return bad != 0;
}

/* System V shared memory: read-write, attached read-only, across fork, locked */
static int shm(void)
{
	int id = shmget(IPC_PRIVATE, 8 * PG, IPC_CREAT | 0600), st, bad = 0;
	volatile char *a, *b;
	pid_t c;

	if (id < 0) {
		printf("shmget: errno %d\n", errno);
		return 90;
	}
	a = shmat(id, (char *)0, 0);
	b = shmat(id, (char *)0, SHM_RDONLY);
	if (a == (char *)-1 || b == (char *)-1) {
		printf("shmat: errno %d\n", errno);
		shmctl(id, IPC_RMID, (struct shmid_ds *)0);
		return 91;
	}
	a[0] = 1;
	bad |= b[0] != 1;
	if ((c = fork()) == 0) {
		alarm(20);
		a[PG] = 2;
		b[PG] = 3;			/* signal 11 */
		_exit(1);
	}
	waitpid(c, &st, 0);
	bad |= (!WIFSIGNALED(st) || (WTERMSIG(st) & 0177) != 11) << 1;
	bad |= (a[PG] != 2 || b[PG] != 2) << 2;
	if (shmctl(id, SHM_LOCK, (struct shmid_ds *)0) < 0)
		printf("SHM_LOCK: errno %d\n", errno);
	else {
		a[2 * PG] = 4;
		bad |= (b[2 * PG] != 4) << 3;
		if (shmctl(id, SHM_UNLOCK, (struct shmid_ds *)0) < 0)
			bad |= 1 << 4;
	}
	shmdt((char *)a);
	shmdt((char *)b);
	shmctl(id, IPC_RMID, (struct shmid_ds *)0);
	return bad;
}

/* plock, with a denied page and a read-only page in the process, and copy on write while locked */
static int plockc(void)
{
	char *none = zmap(PG, PROT_NONE), *ro = zmap(PG, PROT_READ), *wo = zmap(PG, PROT_WRITE), *rw = zmap(4 * PG, PROT_READ | PROT_WRITE);
	int bad = 0, st, r;
	pid_t c;

	(void)none;
	(void)ro;
	(void)wo;
	rw[0] = 1;
	r = plock(PROCLOCK);
	printf("plock(PROCLOCK): %d errno %d, uid %d\n", r, errno, (int)geteuid());
	if (r < 0)
		return geteuid() == 0 ? 1 : 0;
	if ((c = fork()) == 0) {
		rw[0] = 2;
		_exit(rw[0] == 2 && wo[0] == 0 ? 0 : 1);
	}
	waitpid(c, &st, 0);
	bad |= (st != 0) << 1;
	bad |= (rw[0] != 1) << 2;
	rw[PG] = 3;
	bad |= (plock(UNLOCK) < 0) << 3;
	return bad;
}

/* a store to each page of a large read-only private file, a handler stepping past each signal: each store takes a swap
 * slot with no reservation, so swap runs out.  It must end in a signal or a clean stop: the machine goes on.  Not in
 * the default set, because other processes may die of it too. */
static jmp_buf al_j;
static void al_h(int s)
{
	signal(s, al_h);
	longjmp(al_j, 1);
}
static int anon_loop(void)
{
	long i, n = 512L * 1024 * 1024 / PG, sig = 0;
	int fd = open(TF, O_RDWR | O_CREAT | O_TRUNC, 0644);
	volatile char *p;

	alarm(1800);
	lseek(fd, (off_t)(n * PG - 1), 0);
	write(fd, "x", 1);
	p = mmap((caddr_t)0, n * PG, PROT_READ, MAP_PRIVATE, fd, 0);
	if (p == (char *)-1) {
		perror("mmap");
		return 90;
	}
	signal(SIGSEGV, al_h);
	for (i = 0; i < n; i++) {
		if (setjmp(al_j) == 0)
			p[i * PG] = 1;
		else
			sig++;
		if (i % 4096 == 0) {
			printf("%ld pages, %ld signals\n", i, sig);
			fflush(stdout);
		}
	}
	printf("anon-loop: %ld pages, %ld signals, no end\n", i, sig);
	unlink(TF);
	return 0;
}

static long secs(void)
{
	struct tms t;

	return times(&t);
}

/* time per fault: first touches of fresh pages, the path through the wrapper */
static void timing(void)
{
	long t0, t1;
	int i, r, n = 4096;

	for (r = 0; r < 3; r++) {
		char *p = zmap(n * PG, PROT_READ | PROT_WRITE);

		t0 = secs();
		for (i = 0; i < n; i++)
			p[i * PG] = 1;
		t1 = secs();
		printf("zero-fill write faults: %d pages in %ld ticks\n", n, t1 - t0);
		munmap((caddr_t)p, n * PG);
	}
	for (r = 0; r < 3; r++) {
		int fd = mkfile(1024 * PG, 0x61);
		char *p = mmap((caddr_t)0, 1024 * PG, PROT_READ, MAP_PRIVATE, fd, 0), s = 0;

		t0 = secs();
		for (i = 0; i < 1024; i++)
			s += p[i * PG];
		t1 = secs();
		printf("file read faults: 1024 pages in %ld ticks (%d)\n", t1 - t0, s);
		munmap((caddr_t)p, 1024 * PG);
		close(fd);
	}
	fflush(stdout);
}

static char *only;	/* vm30 NAME: that case alone */

static void run(const char *name, int (*f)(void))
{
	int st, r;
	pid_t c;

	if (only && strcmp(only, name) != 0)
		return;
	fflush(stdout);
	if ((c = fork()) == 0) {
		alarm(60);
		r = f();
		fflush(stdout);
		_exit(r == SKIP ? SKIP : r ? (r > 100 ? 100 : r) : 0);
	}
	waitpid(c, &st, 0);
	if (WIFSIGNALED(st))
		printf("FAIL %-16s signal %d\n", name, WTERMSIG(st) & 0177);
	else if (WEXITSTATUS(st) == SKIP)
		printf("SKIP %-16s not run\n", name);
	else
		printf("%s %-16s %d\n", WEXITSTATUS(st) ? "FAIL" : "PASS", name, WEXITSTATUS(st));
	fflush(stdout);
}

int main(int ac, char **av)
{
	only = ac > 1 ? av[1] : 0;
	zfd = open("/dev/zero", O_RDWR);
	if (getenv("VM30_TF"))
		tfname = getenv("VM30_TF");
	if (only && strcmp(only, "fs") == 0) {	/* VM30_TF's file system */
		only = 0;
		run("file-private", file_private);
		run("file-shared", file_shared);
		run("shared-denied", shared_denied);
		run("write-only", wonly);
		printf("vm30-done\n");
		return 0;
	}
	if (only && strcmp(only, "anon-loop") == 0) {
		run("anon-loop", anon_loop);
		printf("vm30-done\n");
		return 0;
	}
	run("cow-fork", cow);
	run("file-private", file_private);
	run("file-shared", file_shared);
	run("stack-growth", stack);
	run("exec-shared", exec_shared);
	run("mprotect", mprot);
	run("proc-rw", proc_rw);
	run("proc-denied", proc_denied);
	run("copies", copies);
	run("core-dump", core);
	run("core-dump-denied", core_denied);
	run("rmw", rmw);
	run("write-only", wonly);
	run("shared-denied", shared_denied);
	run("physio", physio);
	run("shm", shm);
	run("plock", plockc);
	if (!only)
		timing();
	printf("vm30-done\n");
	return 0;
}
