/*
 * dns.c - a stub DNS resolver for apkg.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * WHY THIS EXISTS.  Stock Amix has NO resolver at all.  libsocket's
 * gethostbyname() reads /etc/inet/hosts and nothing else; there is no
 * resolv.conf path behind it (a resolv.conf on an Amix box is inert -
 * nothing reads it), no /etc/nsswitch.conf, and no in.named worth
 * pointing at.  So the only way a stock box turns pkg.amigaux.org into
 * an address is a hand-written hosts line, which is exactly what the
 * Saku demo cards carry.  That works, and it is also the reason a fresh
 * install cannot reach the repository until somebody edits a file: the
 * client contract is HOSTNAME ONLY (the repo host is a name-based
 * virtual host and answers a bare-IP Host: with 404), so "no resolver"
 * means "no repository".
 *
 * This file closes that gap for apkg's OWN lookups and for nothing
 * else.  It is a stub resolver in the strict sense: one UDP query per
 * attempt, A records only, recursion requested, no EDNS, no cache
 * beyond the life of the process, no search list, no TCP fallback, no
 * /etc/resolv.conf.  The nameservers come from the apkg config, the
 * same place every other knob on the fetch path comes from.
 *
 * ORDER, AND WHY IT IS THIS WAY ROUND:
 *
 *   1. an IPv4 literal is used as-is (SVR4 gethostbyname is not
 *      guaranteed to take dotted quads);
 *   2. the HOST DATABASE, via gethostbyname() - unchanged behaviour,
 *      and on Amix that IS /etc/inet/hosts;
 *   3. only if that says nothing, the stub resolver below.
 *
 * Hosts-first means an existing box cannot regress: every card with a
 * hosts line resolves exactly as it did, whatever nameserver= says, and
 * a wrong nameserver cannot shadow an entry the operator wrote by hand.
 * It also means an operator can override DNS locally, which is the
 * behaviour every other Unix has.
 *
 * WHAT IT DOES NOT DO, deliberately: it does not make the BOX resolve
 * names.  telnet, ftp, rlogin and everything else on an Amix box still
 * read /etc/inet/hosts and are untouched by this.  Only apkg's own
 * lookups go through here.
 *
 * TIMEOUTS.  Each UDP read is guarded by alarm() + longjmp, local to
 * this file, so a timeout is RECOVERABLE: it falls through to the next
 * attempt, then the next nameserver, rather than killing the fetch.
 * That is why http.c disarms its own inactivity timer around the call -
 * its timer longjmps out to the retry loop, which cannot express "try
 * the second nameserver".  setjmp/longjmp rather than SIGALRM+EINTR
 * because signal() has BSD (restarting) semantics on the Linux host
 * where these paths are tested and System V (interrupting) semantics on
 * Amix; a longjmp behaves identically on both.  It does need
 * unblock_alarm() on the way out, though - a handler runs with its own
 * signal blocked and a longjmp never performs the return that lifts it,
 * so without that the SECOND query would arm an alarm nothing could
 * deliver and hang.  See util.c; the same defect was live in http.c's
 * retry loop.
 *
 * PARSING IS DEFENSIVE, because a UDP reply is the one input here an
 * attacker (or a broken middlebox) picks:
 *   - the socket is connect()ed, so the kernel drops anything not from
 *     the nameserver we asked;
 *   - the reply's transaction id, QR bit, opcode, and the echoed
 *     question (name, type, class) must all match what we sent;
 *   - compression pointers must point strictly BACKWARDS, which makes
 *     an infinite name impossible, and are counted on top of that;
 *   - every offset is bounds-checked against the datagram length, and
 *     an A record is only believed with class IN and rdlength 4;
 *   - anything else is "malformed": the reply is dropped and the next
 *     attempt/nameserver is tried, never a partial answer.
 * TTLs are read past and ignored: nothing here caches.
 */

#ifndef APKG_NO_HTTP

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <setjmp.h>
#include <signal.h>
#include <time.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>

#include "apkg.h"

#define DNS_HDRLEN      12
#define DNS_MAXMSG     512      /* no EDNS: a UDP DNS message fits 512 */
#define DNS_MAXNAME    256      /* decoded dotted name, with the NUL   */
#define DNS_MAXJUMPS    32      /* compression-pointer budget          */
#define DNS_MAXCHAIN     8      /* CNAME hops followed inside a reply  */
#define DNS_MAXANS      64      /* answer RRs we are willing to walk   */

#define DNS_T_A          1
#define DNS_T_CNAME      5
#define DNS_C_IN         1

/* reply_parse() verdicts */
#define RP_OK            0      /* an address was found                */
#define RP_MALFORMED    (-1)    /* not a usable answer to OUR question */
#define RP_NOANSWER     (-2)    /* well-formed, but carries no address */

/* ---------------- IPv4 literals ---------------- */

/* dotted-quad parser.  SVR4 gethostbyname is not guaranteed to accept a
 * numeric host, and this is also how a nameserver= value is read.
 * returns 0 (addr filled, network byte order) / -1 not a literal */
int apkg_ipv4_parse(const char *s, unsigned long *addr)
{
    unsigned long parts[4];
    int i;

    for (i = 0; i < 4; i++) {
        if (!isdigit((unsigned char)*s))
            return -1;
        parts[i] = 0;
        while (isdigit((unsigned char)*s)) {
            parts[i] = parts[i] * 10 + (unsigned long)(*s - '0');
            if (parts[i] > 255)
                return -1;
            s++;
        }
        if (i < 3) {
            if (*s != '.')
                return -1;
            s++;
        }
    }
    if (*s != '\0')
        return -1;
    *addr = htonl((parts[0] << 24) | (parts[1] << 16) |
                  (parts[2] << 8) | parts[3]);
    return 0;
}

/* format a network-order address; buf must hold at least 16 bytes */
void apkg_ipv4_str(unsigned long addr, char *buf)
{
    unsigned char b[4];

    memcpy((char *)b, (char *)&addr, 4);
    sprintf(buf, "%u.%u.%u.%u", (unsigned)b[0], (unsigned)b[1],
            (unsigned)b[2], (unsigned)b[3]);
}

/* ---------------- nameserver specs ---------------- */

/*
 * A nameserver= value is an IPv4 literal with an OPTIONAL ":port".
 *
 * A name would be a bootstrap problem (resolving the resolver), so only
 * a literal is accepted.  The port suffix is there because port 53 is
 * privileged: it is what lets the whole resolver be exercised host-side
 * against a fake server on 127.0.0.1:<high port>, and it costs one
 * strrchr.  Operators should not normally need it.
 */
static int server_parse(const char *spec, unsigned long *addr, int *port)
{
    char host[64];
    const char *colon;
    unsigned len;
    long p;

    *port = APKG_DNS_PORT;
    colon = strrchr(spec, ':');
    if (colon == NULL) {
        return apkg_ipv4_parse(spec, addr);
    }
    len = (unsigned)(colon - spec);
    if (len == 0 || len >= sizeof(host))
        return -1;
    memcpy(host, spec, len);
    host[len] = '\0';
    colon++;
    if (!isdigit((unsigned char)*colon))
        return -1;
    p = 0;
    while (isdigit((unsigned char)*colon)) {
        p = p * 10 + (long)(*colon - '0');
        if (p > 65535)
            return -1;
        colon++;
    }
    if (*colon != '\0' || p <= 0)
        return -1;
    *port = (int)p;
    return apkg_ipv4_parse(host, addr);
}

/* ---------------- wire-format names ---------------- */

/*
 * Encode a host name into DNS wire format.  A single trailing '.' is
 * accepted (it is the root label and the name is already absolute).
 * Returns the number of bytes written, or -1 for a name the format
 * cannot carry (an empty label, a label over 63 bytes, or a wire form
 * over 255 bytes).
 */
static int name_put(unsigned char *out, int outsz, const char *host)
{
    int n;
    const char *p;
    const char *lab;
    unsigned llen;

    n = 0;
    p = host;
    if (*p == '\0')
        return -1;
    for (;;) {
        lab = p;
        while (*p != '\0' && *p != '.')
            p++;
        llen = (unsigned)(p - lab);
        if (llen == 0 || llen > 63)
            return -1;
        if (n + 1 + (int)llen + 1 > outsz || n + 1 + (int)llen + 1 > 255)
            return -1;
        out[n++] = (unsigned char)llen;
        memcpy((char *)(out + n), lab, llen);
        n += (int)llen;
        if (*p == '\0')
            break;
        p++;                    /* step over the '.' */
        if (*p == '\0')
            break;              /* a single trailing dot: absolute name */
    }
    out[n++] = 0;               /* root label */
    return n;
}

/*
 * Decode the name at msg[off] into `out` (dotted, lowercased, no
 * trailing dot), following compression pointers.
 *
 * *end receives the offset just past the name AS ENCODED AT off - i.e.
 * just past the first pointer when one is used, which is what a record
 * walk needs.  Returns 0 / -1.
 *
 * A pointer must point strictly backwards.  That single rule is what
 * makes an infinite name impossible (each jump strictly decreases the
 * offset, so the chain is finite); DNS_MAXJUMPS is a second, cheaper
 * bound on top of it.
 */
static int name_get(const unsigned char *msg, int msglen, int off,
                    char *out, int outsz, int *end)
{
    int o;
    int jumps;
    int first;
    int len;
    int l;
    int i;

    o = off;
    jumps = 0;
    first = 1;
    len = 0;
    if (end != NULL)
        *end = -1;
    for (;;) {
        if (o < 0 || o >= msglen)
            return -1;
        l = msg[o];
        if ((l & 0xc0) == 0xc0) {
            int ptr;

            if (o + 1 >= msglen)
                return -1;
            ptr = ((l & 0x3f) << 8) | msg[o + 1];
            if (first) {
                if (end != NULL)
                    *end = o + 2;
                first = 0;
            }
            if (++jumps > DNS_MAXJUMPS)
                return -1;
            if (ptr >= o)
                return -1;              /* must point BACKWARDS */
            o = ptr;
            continue;
        }
        if ((l & 0xc0) != 0)
            return -1;                  /* reserved label type */
        if (l == 0) {
            if (first) {
                if (end != NULL)
                    *end = o + 1;
                first = 0;
            }
            break;
        }
        if (o + 1 + l > msglen)
            return -1;
        if (len + l + 1 >= outsz)
            return -1;
        if (len > 0)
            out[len++] = '.';
        for (i = 0; i < l; i++)
            out[len++] = (char)tolower((unsigned char)msg[o + 1 + i]);
        o += 1 + l;
    }
    out[len] = '\0';
    return 0;
}

/* case-insensitive name compare (both sides are already lowercased by
 * name_get; the query name comes from a URL and may not be) */
static int name_eq(const char *a, const char *b)
{
    while (*a != '\0' && *b != '\0') {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b))
            return 0;
        a++;
        b++;
    }
    /* tolerate one trailing dot on either side */
    if (*a == '.' && a[1] == '\0')
        a++;
    if (*b == '.' && b[1] == '\0')
        b++;
    return *a == '\0' && *b == '\0';
}

/* ---------------- resource records ---------------- */

struct dnsrr {
    char owner[DNS_MAXNAME];
    int type;
    int rrclass;
    int rdlen;
    int rdoff;          /* offset of the rdata inside the message */
};

/* read one RR at `off`; *next receives the offset of the RR after it */
static int rr_get(const unsigned char *msg, int msglen, int off,
                  struct dnsrr *r, int *next)
{
    int p;

    if (name_get(msg, msglen, off, r->owner, (int)sizeof(r->owner), &p) != 0)
        return -1;
    if (p < 0 || p + 10 > msglen)
        return -1;
    r->type = (msg[p] << 8) | msg[p + 1];
    r->rrclass = (msg[p + 2] << 8) | msg[p + 3];
    /* msg[p+4..p+7] is the TTL: read past, never used - nothing caches */
    r->rdlen = (msg[p + 8] << 8) | msg[p + 9];
    r->rdoff = p + 10;
    if (r->rdoff + r->rdlen > msglen)
        return -1;
    *next = r->rdoff + r->rdlen;
    return 0;
}

/* ---------------- query / reply ---------------- */

static int query_build(unsigned char *buf, int bufsz, unsigned id,
                       const char *host)
{
    int n;

    if (bufsz < DNS_HDRLEN + 5)
        return -1;
    memset((char *)buf, 0, DNS_HDRLEN);
    buf[0] = (unsigned char)((id >> 8) & 0xff);
    buf[1] = (unsigned char)(id & 0xff);
    buf[2] = 0x01;              /* RD: ask the server to recurse */
    buf[3] = 0x00;
    buf[5] = 0x01;              /* qdcount = 1 */
    n = name_put(buf + DNS_HDRLEN, bufsz - DNS_HDRLEN - 4, host);
    if (n < 0)
        return -1;
    n += DNS_HDRLEN;
    buf[n++] = 0;
    buf[n++] = DNS_T_A;
    buf[n++] = 0;
    buf[n++] = DNS_C_IN;
    return n;
}

/*
 * Turn one reply into an address.  RP_OK / RP_MALFORMED / RP_NOANSWER.
 *
 * The CNAME chain is followed inside this one reply: start at the name
 * we asked for, look for an A record that OWNS that name, and on a
 * CNAME move to its target and look again.  Re-walking the answer
 * section per hop (rather than trusting the server's record order)
 * costs nothing at these sizes and is right even when the chain comes
 * back shuffled.
 */
static int reply_parse(const unsigned char *msg, int msglen, unsigned id,
                       const char *qname, unsigned long *addr)
{
    char cur[DNS_MAXNAME];
    char qn[DNS_MAXNAME];
    struct dnsrr rr;
    int flags;
    int qdcount;
    int ancount;
    int off;
    int ansoff;
    int hop;
    int i;

    if (msglen < DNS_HDRLEN)
        return RP_MALFORMED;
    if ((unsigned)((msg[0] << 8) | msg[1]) != id)
        return RP_MALFORMED;            /* not our transaction */
    flags = (msg[2] << 8) | msg[3];
    if ((flags & 0x8000) == 0)
        return RP_MALFORMED;            /* not a response */
    if (((flags >> 11) & 0x0f) != 0)
        return RP_MALFORMED;            /* not a standard query reply */
    qdcount = (msg[4] << 8) | msg[5];
    ancount = (msg[6] << 8) | msg[7];
    if (qdcount != 1)
        return RP_MALFORMED;

    /* the echoed question must be the one we asked */
    if (name_get(msg, msglen, DNS_HDRLEN, qn, (int)sizeof(qn), &off) != 0)
        return RP_MALFORMED;
    if (off < 0 || off + 4 > msglen)
        return RP_MALFORMED;
    if (((msg[off] << 8) | msg[off + 1]) != DNS_T_A ||
        ((msg[off + 2] << 8) | msg[off + 3]) != DNS_C_IN)
        return RP_MALFORMED;
    if (!name_eq(qn, qname))
        return RP_MALFORMED;
    ansoff = off + 4;

    if ((flags & 0x000f) != 0) {
        note("dns: server answered rcode %d for %s", flags & 0x000f, qname);
        return RP_NOANSWER;
    }
    if ((flags & 0x0200) != 0)
        note("dns: reply for %s is truncated (TC); using what arrived, "
             "no TCP retry", qname);
    if (ancount <= 0)
        return RP_NOANSWER;
    if (ancount > DNS_MAXANS)
        ancount = DNS_MAXANS;

    strcpy(cur, qn);
    for (hop = 0; hop < DNS_MAXCHAIN; hop++) {
        int found;

        found = 0;
        off = ansoff;
        for (i = 0; i < ancount; i++) {
            int next;

            if (rr_get(msg, msglen, off, &rr, &next) != 0)
                return RP_MALFORMED;
            off = next;
            if (rr.rrclass != DNS_C_IN || !name_eq(rr.owner, cur))
                continue;
            if (rr.type == DNS_T_A) {
                if (rr.rdlen != 4)
                    return RP_MALFORMED;
                memcpy((char *)addr, (char *)(msg + rr.rdoff), 4);
                return RP_OK;
            }
            if (rr.type == DNS_T_CNAME) {
                char target[DNS_MAXNAME];

                if (name_get(msg, msglen, rr.rdoff, target,
                             (int)sizeof(target), (int *)0) != 0)
                    return RP_MALFORMED;
                note("dns: %s is a CNAME for %s", cur, target);
                strcpy(cur, target);
                found = 1;
                break;
            }
        }
        if (!found)
            break;              /* no A, and the chain went nowhere new */
    }
    return RP_NOANSWER;
}

/* ---------------- the UDP exchange ---------------- */

/*
 * The socket and the receive buffer are file-scope because a longjmp
 * out of recv() must be able to close and report them: a local modified
 * between setjmp() and longjmp() has an indeterminate value afterwards
 * unless it is volatile, and this is cheaper than getting that subtle.
 */
static int g_dnssock = -1;
static unsigned char g_dnsmsg[DNS_MAXMSG];
static jmp_buf dns_jmp;

static void dns_on_alarm(int sig)
{
    (void)sig;
    /* System V signal() resets the disposition on delivery; re-arm so a
     * stray second SIGALRM cannot reach the default (terminate) action */
    signal(SIGALRM, dns_on_alarm);
    longjmp(dns_jmp, 1);
}

static unsigned next_id(void)
{
    static unsigned seq = 0;
    static unsigned seed = 0;

    if (seed == 0) {
        seed = (unsigned)getpid() ^ (unsigned)time((time_t *)0);
        seed |= 1;
    }
    seq += 0x9e37;              /* odd stride: 65536 ids before a repeat */
    return (seed + seq) & 0xffffu;
}

/*
 * One query to one nameserver.  Returns RP_OK (addr filled),
 * RP_NOANSWER (this server says there is no address - do not retry it)
 * or RP_MALFORMED (no usable reply - a retry may help).
 */
static int ask_once(const char *spec, unsigned long srvaddr, int port,
                    const char *host, long timeout, unsigned long *addr)
{
    struct sockaddr_in sin;
    unsigned id;
    int qlen;
    int n;
    int rc;

    id = next_id();
    qlen = query_build(g_dnsmsg, (int)sizeof(g_dnsmsg), id, host);
    if (qlen < 0) {
        warnx2("dns: %s cannot be encoded as a DNS name", host);
        return RP_NOANSWER;
    }

    g_dnssock = socket(AF_INET, SOCK_DGRAM, 0);
    if (g_dnssock < 0) {
        warnx2("dns: cannot create a UDP socket (%s)", strerror(errno));
        return RP_MALFORMED;
    }
    memset((char *)&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons((unsigned short)port);
    memcpy((char *)&sin.sin_addr, (char *)&srvaddr, 4);
    /* connect() a UDP socket so the kernel drops every datagram that did
     * not come from the server we asked - one spoofing class gone for
     * free, and send()/recv() lose two arguments */
    if (connect(g_dnssock, (struct sockaddr *)&sin, sizeof(sin)) < 0) {
        warnx2("dns: cannot reach nameserver %s (%s)", spec, strerror(errno));
        close(g_dnssock);
        g_dnssock = -1;
        return RP_MALFORMED;
    }
    if (send(g_dnssock, (char *)g_dnsmsg, (unsigned)qlen, 0) != qlen) {
        warnx2("dns: query to %s not sent (%s)", spec, strerror(errno));
        close(g_dnssock);
        g_dnssock = -1;
        return RP_MALFORMED;
    }
    note("dns: asked %s for A %s (id %u, %ld s)", spec, host, id, timeout);

    if (setjmp(dns_jmp) != 0) {
        alarm(0);
        signal(SIGALRM, SIG_DFL);
        /* longjmp'd out of the handler: SIGALRM is still blocked, and
         * the next attempt / next nameserver is about to arm alarm()
         * again.  Without this only the FIRST query could ever time
         * out and the second would hang forever. */
        unblock_alarm();
        close(g_dnssock);
        g_dnssock = -1;
        note("dns: no reply from %s within %ld s", spec, timeout);
        return RP_MALFORMED;
    }
    signal(SIGALRM, dns_on_alarm);
    alarm((unsigned)timeout);
    n = recv(g_dnssock, (char *)g_dnsmsg, (int)sizeof(g_dnsmsg), 0);
    alarm(0);
    signal(SIGALRM, SIG_DFL);
    close(g_dnssock);
    g_dnssock = -1;

    if (n <= 0) {
        note("dns: no usable reply from %s (%s)", spec,
             n == 0 ? "empty datagram" : strerror(errno));
        return RP_MALFORMED;
    }
    rc = reply_parse(g_dnsmsg, n, id, host, addr);
    if (rc == RP_MALFORMED)
        note("dns: reply from %s (%d bytes) is malformed or answers a "
             "different question - discarded", spec, n);
    return rc;
}

/* ---------------- public entry points ---------------- */

/*
 * The stub resolver proper: every configured nameserver in order, each
 * tried d->retries+1 times.  A server that ANSWERS "no such address"
 * is not retried - that is an answer, not a failure, the same
 * distinction http.c makes between a 404 and a dead socket - but the
 * next nameserver is still asked, because a stub with two servers
 * configured is asking for a second opinion.
 *
 * Returns 0 (addr filled, network byte order) / -1.
 */
int apkg_dns_query(const char *host, const struct dnsopts *d,
                   unsigned long *addr)
{
    unsigned long srvaddr;
    long timeout;
    int retries;
    int port;
    int i;
    int try;
    int rc;

    if (d == NULL || d->nservers <= 0)
        return -1;
    timeout = d->timeout > 0 ? d->timeout : APKG_DEF_DNSTIMEO;
    retries = d->retries >= 0 ? d->retries : APKG_DEF_DNSRETRIES;

    for (i = 0; i < d->nservers; i++) {
        if (server_parse(d->servers[i], &srvaddr, &port) != 0) {
            warnx2("dns: nameserver '%s' is not an IPv4 address "
                   "(optionally with :port) - skipped", d->servers[i]);
            continue;
        }
        for (try = 0; try <= retries; try++) {
            if (try > 0)
                note("dns: retrying %s (attempt %d of %d)",
                     d->servers[i], try + 1, retries + 1);
            rc = ask_once(d->servers[i], srvaddr, port, host, timeout, addr);
            if (rc == RP_OK) {
                char ip[16];

                apkg_ipv4_str(*addr, ip);
                note("resolve: %s -> %s (dns %s)", host, ip, d->servers[i]);
                return 0;
            }
            if (rc == RP_NOANSWER)
                break;          /* an answer, just not an address */
        }
    }
    warnx2("cannot resolve host %s: no nameserver answered with an address "
           "(%d configured)", host, d->nservers);
    return -1;
}

/*
 * The whole resolution step: literal, then the host database, then the
 * stub resolver.  hosts_timeout bounds step 2 (a hung host database is
 * not a reason to skip step 3).
 *
 * Returns 0 (addr filled, network byte order) / -1 with a message
 * already printed.
 */

static jmp_buf hosts_jmp;
static struct hostent *g_he;

static void hosts_on_alarm(int sig)
{
    (void)sig;
    signal(SIGALRM, hosts_on_alarm);
    longjmp(hosts_jmp, 1);
}

int apkg_resolve(const char *host, const struct dnsopts *d,
                 long hosts_timeout, unsigned long *addr)
{
    char ip[16];

    if (apkg_ipv4_parse(host, addr) == 0) {
        note("resolve: %s is an address literal", host);
        return 0;
    }

    /* (a) the host database - unchanged behaviour, and on Amix that is
     * /etc/inet/hosts and nothing else.  A hosts entry WINS over DNS so
     * that no box which works today can regress, and so that an
     * operator's hand-written line cannot be shadowed by a nameserver. */
    g_he = (struct hostent *)0;
    if (setjmp(hosts_jmp) == 0) {
        signal(SIGALRM, hosts_on_alarm);
        alarm((unsigned)(hosts_timeout > 0 ? hosts_timeout
                                           : APKG_DEF_CONNTIMEO));
        g_he = gethostbyname(host);
        alarm(0);
        signal(SIGALRM, SIG_DFL);
    } else {
        alarm(0);
        signal(SIGALRM, SIG_DFL);
        unblock_alarm();        /* see ask_once() and util.c */
        g_he = (struct hostent *)0;
        warnx2("hosts lookup for %s gave up after %ld s", host,
               hosts_timeout);
    }
    if (g_he != NULL && g_he->h_addr_list != NULL &&
        g_he->h_addr_list[0] != NULL && g_he->h_length >= 4) {
        memcpy((char *)addr, g_he->h_addr_list[0], 4);
        apkg_ipv4_str(*addr, ip);
        note("resolve: %s -> %s (hosts file)", host, ip);
        return 0;
    }

    /* (b) the stub resolver */
    if (d == NULL || d->nservers <= 0) {
        warnx2("cannot resolve host %s: it is not in the hosts file and no "
               "nameserver= is configured", host);
        return -1;
    }
    note("resolve: %s is not in the hosts file; asking %d nameserver(s)",
         host, d->nservers);
    return apkg_dns_query(host, d, addr);
}

#else  /* APKG_NO_HTTP */

/* The FILE+RAW-only build has no sockets at all (that is the point: it
 * links fully static, with none of the libnsl netconfig(3N) closure the
 * socket path drags in), so there is nothing here to compile.  The
 * typedef keeps this a legal translation unit. */
typedef int apkg_dns_not_in_this_build;

#endif /* !APKG_NO_HTTP */
