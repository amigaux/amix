/*
 * fetch30.c -- does an instruction survive a fault on its own fetch?  The shape of a lazy binding's PLT entry: a jmp through
 * memory arrives at `movel #IMM,%sp@-`, here at every offset around a page boundary, in a file mapping whose pages are not
 * yet in the process (and with -i, not in memory either).  The instruction pushes IMM; the code pops it and returns it.
 * A skipped push pops the return address instead.  Each try runs in a child; prints what came back.
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/wait.h>

#define PG 2048
#define IMM 0x12345678UL
#define TF "/tmp/fetch30.dat"

static unsigned char code[] = {
	0x2f, 0x3c, 0x12, 0x34, 0x56, 0x78,	/* movel #IMM,%sp@- */
	0x20, 0x1f,				/* movel %sp@+,%d0 */
	0x4e, 0x75				/* rts */
};

static int try(int off, int invalidate)
{
	static unsigned char b[4 * PG];
	int fd, st, i;
	pid_t c;

	for (i = 0; i < (int)sizeof b; i += 2)
		b[i] = 0x4e, b[i + 1] = 0x71;		/* nops */
	memcpy(b + 2 * PG + off, code, sizeof code);
	if ((fd = open(TF, O_RDWR | O_CREAT | O_TRUNC, 0644)) < 0 || write(fd, (char *)b, sizeof b) != sizeof b)
		return -2;
	if ((c = fork()) == 0) {
		char *p = mmap((caddr_t)0, sizeof b, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
		unsigned long (*f)();
		unsigned long r;

		if (p == (char *)-1)
			_exit(90);
		if (invalidate)
			msync((caddr_t)p, sizeof b, MS_INVALIDATE | MS_ASYNC);
		f = (unsigned long (*)())(p + 2 * PG + off);
		alarm(10);
		r = f();
		_exit(r == IMM ? 0 : 1);
	}
	waitpid(c, &st, 0);
	close(fd);
	return st;
}

int main(int ac, char **av)
{
	int off, r, bad = 0, n = 0, rounds = ac > 1 ? atoi(av[1]) : 20, i, inv = ac > 2;

	for (i = 0; i < rounds; i++)
		for (off = -10; off <= 4; off += 2) {
			r = try(off, inv);
			n++;
			if (r != 0) {
				bad++;
				if (bad < 30)
					printf("offset %d round %d: status %#x\n", off, i, r);
				fflush(stdout);
			}
		}
	printf("fetch30: %d tries, %d bad\n", n, bad);
	return bad != 0;
}
