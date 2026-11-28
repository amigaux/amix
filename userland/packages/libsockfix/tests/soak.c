/*
 * soak.c -- how much the socket library's heap grows per operation, ON THE BOX.
 *
 *     soak OP N [NAME]
 *       udp | tcp | unix    socket() then close(2), N times (Internet UDP, TCP, UNIX stream)
 *       atcp | aunix        accept() then close(2), N times; a child connects N times,
 *                           only the accepting process is measured
 *       dns NAME            gethostbyname(NAME), N times
 *
 * Prints the break's growth after a warm-up of 8 operations and N more:
 *     SOAK <op> <n>: brk grew <bytes> bytes (<bytes per op> per op)
 * and exits 0 when it grew by nothing, 1 when it grew, 2 on an error.
 * The stock library grows by about 200 bytes per operation (4.4 Kbytes for
 * UNIX domain); the fixed one by none.
 *
 * MIT licence, see LICENSE in userland/packages.
 */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* the sysroot declares none of these */
extern void *sbrk(int);
extern int socket(int, int, int), bind(int, void *, int), listen(int, int);
extern int accept(int, void *, int *), connect(int, void *, int);
extern int getsockname(int, void *, int *);

#define UPATH "/tmp/soak.sock"

static int one_socket(const char *op)
{
	int s = socket(strcmp(op, "unix") ? AF_INET : AF_UNIX, strcmp(op, "udp") ? SOCK_STREAM : SOCK_DGRAM, 0);
	if (s < 0) { perror("socket"); return -1; }
	close(s);
	return 0;
}

/* a listener for atcp/aunix; the address it took into sa */
static int listener(int unixdom, struct sockaddr_in *in, struct sockaddr_un *un)
{
	int l = socket(unixdom ? AF_UNIX : AF_INET, SOCK_STREAM, 0), n;
	if (l < 0) { perror("socket"); return -1; }
	if (unixdom) {
		memset(un, 0, sizeof *un); un->sun_family = AF_UNIX; strcpy(un->sun_path, UPATH);
		unlink(UPATH);
		if (bind(l, un, sizeof *un) < 0) { perror("bind"); return -1; }
	} else {
		memset(in, 0, sizeof *in); in->sin_family = AF_INET; in->sin_addr.s_addr = htonl(0x7f000001);
		if (bind(l, in, sizeof *in) < 0) { perror("bind"); return -1; }
		n = sizeof *in;
		if (getsockname(l, in, &n) < 0) { perror("getsockname"); return -1; }
	}
	if (listen(l, 5) < 0) { perror("listen"); return -1; }
	return l;
}

/* the child: connect total times, each closed after the server's accept */
static void connector(int unixdom, struct sockaddr_in *in, struct sockaddr_un *un, int total)
{
	int i, s;
	for (i = 0; i < total; i++) {
		s = socket(unixdom ? AF_UNIX : AF_INET, SOCK_STREAM, 0);
		if (s < 0 || connect(s, unixdom ? (void *)un : (void *)in, unixdom ? sizeof *un : sizeof *in) < 0) _exit(2);
		close(s);
	}
	_exit(0);
}

int main(int argc, char **argv)
{
	const char *op = argc > 1 ? argv[1] : "";
	int n = argc > 2 ? atoi(argv[2]) : 0, i, l = -1, c, st, unixdom = 0;
	long b0 = 0, b1;
	pid_t kid = 0;
	struct sockaddr_in in;
	struct sockaddr_un un;

	if (n <= 0 || !(strcmp(op, "udp") == 0 || strcmp(op, "tcp") == 0 || strcmp(op, "unix") == 0 ||
	    strcmp(op, "atcp") == 0 || strcmp(op, "aunix") == 0 || (strcmp(op, "dns") == 0 && argc > 3))) {
		fprintf(stderr, "usage: soak udp|tcp|unix|atcp|aunix N, or soak dns N NAME\n");
		return 2;
	}
	if (op[0] == 'a') {
		unixdom = strcmp(op, "aunix") == 0;
		if ((l = listener(unixdom, &in, &un)) < 0) return 2;
		if ((kid = fork()) == 0) { close(l); connector(unixdom, &in, &un, n + 8); }
	}
	for (i = 0; i < n + 8; i++) {
		if (i == 8) b0 = (long)sbrk(0);
		if (op[0] == 'a') {
			if ((c = accept(l, NULL, NULL)) < 0) { perror("accept"); return 2; }
			close(c);
		} else if (strcmp(op, "dns") == 0) {
			gethostbyname(argv[3]);
		} else if (one_socket(op) < 0)
			return 2;
	}
	b1 = (long)sbrk(0);
	if (kid > 0) { waitpid(kid, &st, 0); close(l); }
	if (unixdom) unlink(UPATH);
	printf("SOAK %s %d: brk grew %ld bytes (%ld per op)\n", op, n, b1 - b0, (b1 - b0) / n);
	return b1 == b0 ? 0 : 1;
}
