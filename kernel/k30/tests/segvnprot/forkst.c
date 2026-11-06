/*
 * forkst.c -- fork and exit under memory pressure: several parents with written private pages fork short-lived
 * children that write some of those pages (copy on write) and sleep before they exit, so whole processes are swapped
 * out while their page tables are shared by fork.  Every page carries its own pattern, checked by each child and by
 * the parent at the end: a wrong word is a lost or misplaced page.
 *
 * forkst PARENTS MB SECS CHILDREN    (CHILDREN alive at once per parent)
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>

#define PG 2048

static long *mem;
static long npg;

static long pat(long i, long gen) { return (i << 12) ^ (gen << 4) ^ 0x5a5a; }

static long check(long gen, long *gens)
{
	long i, bad = 0;

	for (i = 0; i < npg; i++)
		if (mem[i * (PG / sizeof(long))] != pat(i, gens ? gens[i] : gen))
			bad++;
	return bad;
}

static void child(long me)
{
	long i, bad;

	srand((unsigned)(time((time_t *)0) ^ (me << 8) ^ getpid()));
	bad = check(0, (long *)0);
	for (i = rand() % 4; i < npg; i += 4)
		mem[i * (PG / sizeof(long))] = pat(i, 7);
	sleep(rand() % 4);
	for (i = rand() % 4; i < npg; i += 4)
		if (mem[i * (PG / sizeof(long))] != pat(i, 7) && mem[i * (PG / sizeof(long))] != pat(i, 0))
			bad++;
	_exit(bad ? 1 : 0);
}

static void parent(int me, long mb, long secs, int nch)
{
	long i, forks = 0, cbad = 0, sig = 0, live = 0;
	time_t end = time((time_t *)0) + secs;
	int st;
	pid_t c;

	npg = mb * 1024 * 1024 / PG;
	if ((mem = (long *)malloc(npg * PG)) == 0) {
		printf("parent %d: no memory\n", me);
		exit(2);
	}
	for (i = 0; i < npg; i++)
		mem[i * (PG / sizeof(long))] = pat(i, 0);
	while (time((time_t *)0) < end) {
		while (live < nch) {
			if ((c = fork()) == 0)
				child(forks);
			if (c < 0)
				break;
			forks++;
			live++;
		}
		if ((c = wait(&st)) > 0) {
			live--;
			if (WIFSIGNALED(st))
				sig++;
			else if (WEXITSTATUS(st))
				cbad++;
		}
	}
	while (live > 0 && wait(&st) > 0)
		live--;
	printf("parent %d: %ld forks, %ld children saw a wrong page, %ld killed, own pages wrong %ld\n", me, forks, cbad, sig,
	    check(0, (long *)0));
	fflush(stdout);
	exit(cbad || sig ? 1 : 0);
}

int main(int ac, char **av)
{
	int n = ac > 1 ? atoi(av[1]) : 3, k, st, rc = 0;
	long mb = ac > 2 ? atol(av[2]) : 3, secs = ac > 3 ? atol(av[3]) : 600;
	int nch = ac > 4 ? atoi(av[4]) : 3;

	for (k = 0; k < n; k++)
		if (fork() == 0)
			parent(k, mb, secs, nch);
	for (k = 0; k < n; k++)
		if (wait(&st) > 0 && (WIFSIGNALED(st) || WEXITSTATUS(st)))
			rc = 1;
	printf("forkst-done rc=%d\n", rc);
	return rc;
}
