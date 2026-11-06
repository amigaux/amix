/*
 * sigrace.c -- libc's sigaction and a signal that arrives during it.
 *
 * sigaction in libc.so.1 stores the new handler in _siguhandler and then makes the system call, and the handler the kernel
 * holds until then is libc's sigacthandler, which calls whatever _siguhandler has.  A signal between the two, when the new
 * handler is SIG_DFL, calls address 0.  Each child here changes SIGALRM between a handler and SIG_DFL under a repeating
 * timer until the signal ends it: by SIGALRM if the kernel had SIG_DFL, by SIGSEGV if it went through address 0.  The kernel
 * logs the second as a user fault at PC 0, so a row running this reports bus errors on purpose.  It is user code and the
 * count varies with timing; the point is whether SIGSEGV appears at all.
 *
 * sigrace [TRIALS]
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#define _POSIX_SOURCE		/* for struct sigaction, and it hides the timer below */
#include <signal.h>
#undef _POSIX_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/wait.h>

static void h(int sig)
{
}

static void child(void)
{
	struct sigaction hnd, dfl;
	struct rlimit rl;
	struct itimerval it;

	rl.rlim_cur = rl.rlim_max = 0;
	setrlimit(RLIMIT_CORE, &rl);
	sigemptyset(&hnd.sa_mask);
	hnd.sa_flags = 0;
	hnd.sa_handler = h;
	dfl = hnd;
	dfl.sa_handler = SIG_DFL;
	sigaction(SIGALRM, &hnd, (struct sigaction *)0);
	it.it_interval.tv_sec = it.it_value.tv_sec = 0;
	it.it_interval.tv_usec = it.it_value.tv_usec = 10000;
	setitimer(ITIMER_REAL, &it, (struct itimerval *)0);
	for (;;) {
		sigaction(SIGALRM, &dfl, (struct sigaction *)0);
		sigaction(SIGALRM, &hnd, (struct sigaction *)0);
	}
}

int main(int ac, char **av)
{
	int n = ac > 1 ? atoi(av[1]) : 2000, i, st, alrm = 0, segv = 0, other = 0;
	pid_t c;

	for (i = 0; i < n; i++) {
		if ((c = fork()) == 0)
			child();
		if (c < 0 || waitpid(c, &st, 0) < 0) {
			perror("fork or wait");
			return 2;
		}
		if (WIFSIGNALED(st) && WTERMSIG(st) == SIGALRM)
			alrm++;
		else if (WIFSIGNALED(st) && WTERMSIG(st) == SIGSEGV)
			segv++;
		else
			other++;
	}
	printf("sigrace: %d children, %d by SIGALRM, %d by SIGSEGV through address 0, %d otherwise\n", n, alrm, segv, other);
	return 0;
}
