/*
 * udprx.c -- the receiving end of a burst: udprx PORT SECS counts the datagrams and bytes that reach a program, reading as
 * fast as it can, and stops SECS after the last one.  What a slow reader or a full queue loses, the sender's count shows.
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

static char buf[65536];
static long n, bytes;

static void done(int s)
{
	(void)s;
	printf("udprx: %ld datagrams, %ld bytes\n", n, bytes);
	fflush(stdout);
	exit(0);
}

int main(int ac, char **av)
{
	struct sockaddr_in a;
	int s = socket(AF_INET, SOCK_DGRAM, 0), secs = ac > 2 ? atoi(av[2]) : 30, sz = 65535;

	if (s < 0 || ac < 2) {
		perror("socket");
		return 2;
	}
	setsockopt(s, SOL_SOCKET, SO_RCVBUF, (char *)&sz, sizeof sz);
	a.sin_family = AF_INET;
	a.sin_addr.s_addr = 0;
	a.sin_port = htons(atoi(av[1]));
	if (bind(s, (struct sockaddr *)&a, sizeof a) < 0) {
		perror("bind");
		return 2;
	}
	signal(SIGALRM, done);
	alarm(secs * 4);			/* nothing came at all */
	for (;;) {
		int r = recv(s, buf, sizeof buf, 0);

		if (r < 0)
			continue;
		n++;
		bytes += r;
		alarm(secs);
	}
}
