/*
 * amix-rdate.c -- getaddrinfo for Amix, IPv4 only, from gethostbyname and
 * getservbyname (amix-rdate.h).  A numeric address is used as it is, with
 * no lookup; a service that /etc/inet/services lacks falls back to its
 * well-known port (ntp 123, time 37).
 *
 * A name is looked up in a child process when an alarm is pending (rdate
 * arms one per try): the resolver behind libsockdns.so retries an
 * unreachable name server on its own timers for minutes and does not give
 * way to the caller's alarm (measured: 185 s under a 5 s alarm).  The
 * child writes the answer to a pipe; when the alarm's time runs out first,
 * the child is killed and the lookup fails with EAI_AGAIN.  MIT, this
 * repository.
 */
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>
#include <arpa/inet.h>

extern int h_errno;

#define MAXADDRS 16

struct answer {			/* what the child writes to the pipe */
	int herr;		/* h_errno, when no address */
	int n;			/* addresses that follow */
	struct in_addr a[MAXADDRS];
};

static void
resolve(const char *host, struct answer *ans)
{
	struct hostent *he;
	int i;

	memset(ans, 0, sizeof *ans);
	he = gethostbyname(host);
	if (he == NULL || he->h_addrtype != AF_INET || he->h_addr_list[0] == NULL) {
		ans->herr = he == NULL ? h_errno : HOST_NOT_FOUND;
		return;
	}
	for (i = 0; i < MAXADDRS && he->h_addr_list[i] != NULL; i++)
		memcpy(&ans->a[i], he->h_addr_list[i], sizeof ans->a[i]);
	ans->n = i;
}

/* -> 0 with ans filled, or EAI_AGAIN when the time ran out */
static int
resolve_bounded(const char *host, struct answer *ans)
{
	unsigned rem = alarm(0);
	time_t t0 = time(NULL), left;
	struct timeval tv;
	fd_set rfds;
	int p[2], r, got = 0;
	pid_t pid;

	if (rem == 0 || pipe(p) < 0) {	/* no bound asked for */
		if (rem)
			alarm(rem);
		resolve(host, ans);
		return 0;
	}
	alarm(rem + 2);			/* the caller's alarm stays a backstop */
	if ((pid = fork()) < 0) {
		close(p[0]);
		close(p[1]);
		resolve(host, ans);
		goto rearm;
	}
	if (pid == 0) {
		close(p[0]);
		alarm(0);
		resolve(host, ans);
		(void) write(p[1], ans, sizeof *ans);
		_exit(0);
	}
	close(p[1]);
	for (;;) {
		left = (time_t)rem - (time(NULL) - t0);
		if (left <= 0)
			break;
		FD_ZERO(&rfds);
		FD_SET(p[0], &rfds);
		tv.tv_sec = left;
		tv.tv_usec = 0;
		r = select(p[0] + 1, &rfds, NULL, NULL, &tv);
		if (r < 0 && errno == EINTR)
			continue;
		if (r == 1)
			got = read(p[0], ans, sizeof *ans) == sizeof *ans;
		break;
	}
	close(p[0]);
	if (!got)
		kill(pid, SIGKILL);
	while (waitpid(pid, NULL, 0) < 0 && errno == EINTR)
		;
rearm:
	left = (time_t)rem - (time(NULL) - t0);
	alarm(left > 0 ? (unsigned)left : 1);
	if (!got && pid > 0)
		return EAI_AGAIN;
	return 0;
}

static int
service_port(const char *serv, int socktype)
{
	struct servent *se;

	if (serv == NULL)
		return 0;
	se = getservbyname(serv, socktype == SOCK_DGRAM ? "udp" : "tcp");
	if (se != NULL)
		return ntohs((unsigned short)se->s_port);
	if (strcmp(serv, "ntp") == 0)
		return 123;
	if (strcmp(serv, "time") == 0)
		return 37;
	return -1;
}

static struct addrinfo *
one(struct in_addr a, int port, const struct addrinfo *hints)
{
	struct addrinfo *ai;
	struct sockaddr_in *sin;

	ai = calloc(1, sizeof(*ai) + sizeof(*sin));
	if (ai == NULL)
		return NULL;
	sin = (struct sockaddr_in *)(ai + 1);
	sin->sin_family = AF_INET;
	sin->sin_port = htons((unsigned short)port);
	sin->sin_addr = a;
	ai->ai_family = AF_INET;
	ai->ai_socktype = hints->ai_socktype;
	ai->ai_protocol = 0;
	ai->ai_addrlen = sizeof(*sin);
	ai->ai_addr = (struct sockaddr *)sin;
	return ai;
}

int
getaddrinfo(const char *host, const char *serv, const struct addrinfo *hints,
	    struct addrinfo **res)
{
	struct addrinfo *head = NULL, **tail = &head, *ai;
	struct answer ans;
	struct in_addr a;
	unsigned long n;
	int port, i;

	*res = NULL;
	if (hints->ai_family != PF_UNSPEC && hints->ai_family != PF_INET)
		return EAI_FAMILY;
	if ((port = service_port(serv, hints->ai_socktype)) < 0)
		return EAI_SERVICE;
	n = inet_addr(host);
	if (n != (unsigned long)-1 || strcmp(host, "255.255.255.255") == 0) {
		a.s_addr = n;
		if ((*res = one(a, port, hints)) == NULL)
			return EAI_MEMORY;
		return 0;
	}
	if (resolve_bounded(host, &ans) != 0)
		return EAI_AGAIN;
	if (ans.n == 0)
		return ans.herr == TRY_AGAIN ? EAI_AGAIN :
		       ans.herr == NO_RECOVERY ? EAI_FAIL : EAI_NONAME;
	for (i = 0; i < ans.n; i++) {
		a = ans.a[i];
		if ((ai = one(a, port, hints)) == NULL) {
			freeaddrinfo(head);
			return EAI_MEMORY;
		}
		*tail = ai;
		tail = &ai->ai_next;
	}
	*res = head;
	return 0;
}

void
freeaddrinfo(struct addrinfo *ai)
{
	struct addrinfo *next;

	for (; ai != NULL; ai = next) {
		next = ai->ai_next;
		free(ai);
	}
}

const char *
gai_strerror(int e)
{
	switch (e) {
	case EAI_NONAME:	return "host not found";
	case EAI_AGAIN:		return "name server not answering, try again";
	case EAI_FAIL:		return "name server failure";
	case EAI_FAMILY:	return "only IPv4 on this system";
	case EAI_SERVICE:	return "unknown service";
	case EAI_MEMORY:	return "out of memory";
	default:		return "name lookup failed";
	}
}
