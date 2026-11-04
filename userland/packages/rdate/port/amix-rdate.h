/*
 * amix-rdate.h -- what openrdate needs that Amix's 1992 libraries lack.
 * Included ahead of every source file (build.sh).  MIT, this repository.
 *
 * - getaddrinfo, freeaddrinfo, gai_strerror: Amix has gethostbyname and
 *   getservbyname only; amix-rdate.c builds the IPv4 answer list from them.
 * - settimeofday: in libc (it calls stime(2): whole seconds, tv_usec
 *   rounded), declared in no header.
 * - PF_INET6: no IPv6; -6 asks the lookup for a family it refuses.
 * - socklen_t: SVR4.0 passes socket lengths as int.
 */
#ifndef AMIX_RDATE_H
#define AMIX_RDATE_H

#include <sys/types.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>

#ifndef PF_INET6
#define PF_INET6 26
#endif

typedef int socklen_t;

struct addrinfo {
	int ai_flags;
	int ai_family;
	int ai_socktype;
	int ai_protocol;
	socklen_t ai_addrlen;
	struct sockaddr *ai_addr;
	char *ai_canonname;
	struct addrinfo *ai_next;
};

#define EAI_NONAME  8	/* the name does not resolve */
#define EAI_AGAIN   2	/* a temporary failure of the name server */
#define EAI_FAIL    4	/* a failure of the name server */
#define EAI_FAMILY  5	/* a family other than IPv4 */
#define EAI_SERVICE 9	/* the service is unknown */
#define EAI_MEMORY  6

int getaddrinfo(const char *, const char *, const struct addrinfo *, struct addrinfo **);
void freeaddrinfo(struct addrinfo *);
const char *gai_strerror(int);
int settimeofday(struct timeval *, void *);
char *inet_ntoa(struct in_addr);

#endif
