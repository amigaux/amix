/*
 * http.c - minimal HTTP/1.0 GET client for apkg.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * Hand-rolled on BSD sockets so it runs against the 1992 Amix libc
 * (SVR4.0, sockets from libsocket/libnsl, gethostbyname only - no
 * getaddrinfo, no TLS).  Behaviour per docs/design.md section 2:
 *
 *   - HTTP/1.0 GET with a Host: header (pkg.amigaux.org is a
 *     name-based virtual host, so Host: is load-bearing -- a request
 *     carrying a bare IP as the Host: value is answered 404) and
 *     Connection: close
 *   - streams the body to <dest>.part, renames to <dest> on success
 *   - status line + headers parsed case-insensitively
 *   - Content-Length, when present, drives progress output and a
 *     truncation check
 *   - follows exactly one 301/302 Location (absolute URL or
 *     absolute path)
 *   - INACTIVITY timeout with alarm()/longjmp.  The timer is re-armed
 *     immediately before every call that can block -- resolve,
 *     connect, send, and each recv -- so every chunk that arrives
 *     resets the clock.  A slow but flowing transfer therefore never
 *     trips it however long it takes, while a connection that has
 *     gone silent still fails.  It replaced a single whole-transfer
 *     alarm() whose 60 s cap killed a healthy 8.2 MB fetch on real
 *     hardware (A4000D over Z3660 ethernet, 2026-09-16; that path
 *     runs ~37 KB/s, so the package needs ~220 s of legitimate,
 *     continuously-flowing transfer).
 *   - resolve+connect run under their OWN, much shorter budget, so a
 *     dead host fails in seconds instead of inheriting the patience
 *     that mid-transfer stalls need
 *   - retries with doubling backoff on NETWORK failures only; a
 *     non-200 status is an answer, not a failure, and is never retried
 *   - progress lines on stderr every opts->progress bytes (quartered
 *     under -v) so the operator can see a long fetch moving
 *   - SO_RCVBUF/SO_SNDBUF REQUESTED before connect(), so that if the
 *     request takes effect it is in force when the SYN advertises the
 *     window, and read back with getsockopt() so -v reports what the
 *     socket layer says.  On the stock Amix stack that readback is NOT
 *     proof the tcp module honoured it -- see apkg.h
 *   - plain http:// only; port parsed from the URL, default 80
 *   - name resolution is dns.c's: an IPv4 literal (parsed by hand --
 *     the SVR4 gethostbyname is not guaranteed to accept dotted
 *     quads), then the host database, then apkg's own stub DNS
 *     resolver when `nameserver=` is configured.  It runs with this
 *     file's inactivity timer DISARMED, because a resolver timeout has
 *     to be recoverable (next attempt / next nameserver) and a longjmp
 *     out to the retry loop is not
 *
 * Every number above comes from struct httpopts, i.e. from
 * /etc/apkg.conf -- this file holds no unreachable constant.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <setjmp.h>
#include <signal.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <unistd.h>

#include "apkg.h"

/*
 * ---------------------------------------------------------------
 * The SECOND mechanism behind the rcvbuf knob: STREAMS INITQPARMS.
 * ---------------------------------------------------------------
 *
 * WHY A SECOND ONE EXISTS.  A server-side capture of a real A4000D
 * fetch (pkg.amigaux.org, Xcore-2.1.pkg, 2026-09-14 23:57 EEST)
 * settled the question the -v readback could not: Amix advertised
 * "win 4096" in its SYN and in all 2999 steady-state ACKs, even
 * though apkg had requested SO_RCVBUF 65536 before connect().  The
 * socket option does not reach the tcp module's receive high-water
 * mark on this stack.
 *
 * AND WHY IT IS NOT ON BY DEFAULT.  The obvious next step -- raise
 * the window, take the 4x that window/RTT promises -- was measured on
 * the metal (A4000D/68LC060, round-2 capture, 2026-09-15) and it is
 * WRONG.  INITQPARMS works: after setting 16384 the box really did
 * advertise win 16384 in the SYN and in every steady-state ACK, on
 * streams it had not yet opened -- which is also the first-party
 * confirmation of the module-template semantics derived below.  But
 * throughput got worse, not better:
 *
 *     window    WAN throughput    server-side retransmits
 *     4096          ~54 KB/s      64/6305   = 1.0 %
 *     8192          ~32 KB/s      (loss zone)
 *     16384       ~36-40 KB/s     155/4328 = 3.6 %, 101/3525 = 2.9 %
 *
 * The binding constraint is not the window but an RX-path loss cliff
 * at ~8 segments in flight (~10 KB outstanding): <=7 segments per
 * burst lose 2-3 %, 8 lose ~60 %, >=9 lose ~100 %, and each loss costs
 * a server RTO.  The stock 4096 window admits at most 8 segments
 * (7x536+344 = 4096) and therefore sits exactly at the loss-free
 * edge -- near-optimal for this driver as it stands.  The real lever
 * is the RX drop mechanism (the Z3660 firmware discarding its whole
 * backlog on overflow, and/or the 16.67 ms poll quantum), and it
 * lives in the driver and firmware repos, not here.
 *
 * So APKG_DEF_RCVBUF is 0: apkg leaves the window alone unless an
 * operator explicitly asks.  What follows is an operator knob, not a
 * speed fix, and on z3660eth any value above 4096 is SLOWER until the
 * RX loss is addressed.
 *
 * WHAT INITQPARMS IS.  Amix's TCP is Lachman "System V STREAMS TCP
 * Release 3.0".  Its modules implement a privileged STREAMS ioctl
 * that rewrites their queue water marks at run time; the interface
 * is declared in the Amix sysroot header <net/strioc.h> (struct
 * iocqp, IQP_RQ, IQP_HIWAT, INITQPARMS).  We do not include that
 * header -- it is proprietary and is not part of this repository --
 * so the three constants and the two-field payload are restated
 * below under our own names, byte-compatible with it.  Build with
 * -DAPKG_CHECK_STRIOC against a real Amix sysroot to have the
 * compiler prove the restatement matches (see the assertion below).
 *
 * DOES ANYTHING SWALLOW IT?  No -- answered from source at both
 * layers that could, not from hope.
 *
 * (a) libsocket.  Amix's libsocket supplies its OWN ioctl() over the
 * syscall (our apkg.amix shows "T ioctl" from s_ioctl.o beside
 * "U _ioctl").  That wrapper switches on exactly six BSD-specific
 * requests -- FIOASYNC, FIOSETOWN, FIOGETOWN, SIOCSPGRP, SIOCGPGRP,
 * SIOCATMARK -- and ends with an unconditional
 *
 *     return _ioctl(des, request, arg);
 *
 * so I_STR reaches the real syscall untouched (SVR4.0 reference tree,
 * usr/src/lib/libsocket/socket/s_ioctl.c:74-228).
 *
 * (b) sockmod.  A BSD socket on SVR4 is a stream with sockmod pushed
 * above the transport provider, so an I_STR on the socket fd becomes
 * an M_IOCTL travelling down through sockmod.  sockmod's write-side
 * M_IOCTL switch ends in a plain pass-through for every command it
 * does not itself implement:
 *
 *     case M_IOCTL:
 *         switch (iocbp->ioc_cmd) {
 *         default:
 *                 putnext(q, mp);        <- our INITQPARMS goes here
 *
 * (USL SVR4.2 reference tree, common/uts/net/transport/sockmod.c
 * :2412,:2424-2427; the returning M_IOCACK / M_IOCNAK is passed
 * back up the same way at :487-496 and :514-523.)  The tcp module
 * then handles it in tcpioctl(): common/uts/net/tcpip/tcp_main.c
 * :568-575 -> initqparms(bp, tcpm_info, MUXDRVR_INFO_SZ).  So there
 * is no need to bypass the socket and open /dev/tcp directly; doing
 * so would also mean reimplementing connect() as a T_CONN_REQ over
 * TLI, which is a lot of 1992-shaped code to buy nothing.
 *
 * ORDERING -- THIS IS THE LOAD-BEARING PART.  initqparms() does NOT
 * touch the live queue.  It writes the module's module_info
 * template:
 *
 *     case IQP_HIWAT:
 *             minfo[i].mi_hiwat = iqpp->iqp_value;
 *
 * (common/uts/net/tcpip/netlib.c:148-179), and STREAMS copies that
 * template into a queue's q_hiwat when the stream is OPENED
 * (i386/uts/io/strsubr.c:989, "rq->q_hiwat = rinit->qi_minfo->
 * mi_hiwat").  tcp_output() then reads the live q_hiwat as
 * "recvspace" for every segment it builds (tcp_output.c:141,:207,
 * :404).  Therefore the ioctl must be issued on a stream opened
 * BEFORE the one whose window we care about.  apkg issues it once
 * per process on a throwaway socket, before the first fetch socket
 * exists, and then again on the fetch socket itself -- the second
 * call is belt-and-braces for the possibility that the Amix-vintage
 * initqparms() writes the live queue instead of the template, and
 * is a harmless no-op if it does not.
 *
 * SIDE EFFECT, STATED PLAINLY.  Because it is the template that
 * changes, this raises the default receive high-water mark for
 * every TCP stream opened on the box afterwards -- BOX-WIDE, not
 * apkg-wide, and it outlives the process: it stands until reboot.
 * A high-water mark is a flow-control threshold, not an allocation,
 * so the cost is bounded, but it is not scoped to us.  That is why
 * apkg says so at warning level, not only under -v, whenever the
 * ioctl is actually accepted.
 *
 * WHY apkg DOES NOT RESTORE IT ON EXIT.  It cannot learn what was
 * there before: INITQPARMS is set-only (netlib.c:148-179 has no get),
 * and getsockopt(SO_RCVBUF) cannot stand in for one because sockmod
 * initialises its cached so->rcvbuf to 0 at open (sockmod.c:264-265)
 * rather than from the module's hiwat.  The only value apkg could
 * "restore" is the stock compiled-in 4096 -- a value it never
 * measured on this box, and one that would silently clobber a
 * deliberate system-wide setting made by someone else.  Two further
 * reasons not to: an apkg killed mid-fetch would not restore anyway,
 * so the guarantee would be false exactly when it mattered; and the
 * knob's actual use is the bench workflow of set, measure, revert,
 * which spans several runs.  So: apkg sets and says so; putting it
 * back is `rcvbuf=4096` on a root run, or a reboot.
 *
 * rcvbuf=0 -- the default -- disables the whole mechanism.
 *
 * PRIVILEGE.  initqparms() starts with drv_priv(ioc_cr) and returns
 * EPERM for an unprivileged caller (netlib.c:154-155).  "apkg
 * install" already runs as root; a non-root apkg falls back to the
 * plain SO_RCVBUF request and says so under -v.
 *
 * All of the above is from the USL SVR4.2 reference tree, matched to
 * Amix by byte-identical Lachman headers in Amix's own sysroots.
 * Confidence: derived, not read out of an Amix binary.  What a box
 * test must show is written up in NOTES.md.
 */
#if defined(APKG_STREAMS) || defined(APKG_NO_STREAMS)
/* explicit build-time override wins over the detection below */
#elif defined(__AMIX__) || defined(__svr4__)
#define APKG_STREAMS 1
#endif

#ifdef APKG_STREAMS
#include <stropts.h>
#endif

/* Restatement of the <net/strioc.h> interface, under our own names. */
#define APKG_IQP_RQ       0x00            /* IQP_RQ:    standard read queue */
#define APKG_IQP_HIWAT    0x20            /* IQP_HIWAT: high water mark     */
#define APKG_INITQPARMS   (('Q' << 8) | 0x01)
#define APKG_IQP_MAX      65535L          /* iqp_value is an unsigned short */

struct apkg_qparm {                       /* == struct iocqp */
    unsigned short type;
    unsigned short value;
};

#ifdef APKG_CHECK_STRIOC
/* Opt-in proof that the restatement above matches the real Amix
 * header.  Not on by default: <net/strioc.h> only exists in an Amix
 * sysroot, and apkg must build without one. */
#include <net/strioc.h>
typedef char apkg_iqp_matches_strioc_h[
    (APKG_IQP_RQ == IQP_RQ && APKG_IQP_HIWAT == IQP_HIWAT &&
     APKG_INITQPARMS == INITQPARMS &&
     sizeof(struct apkg_qparm) == sizeof(struct iocqp)) ? 1 : -1];
#endif

/* Sanity cap on response header size.  Deliberately NOT a config key:
 * it is a bound on what a hostile/broken server can make us allocate,
 * and there is no operational reason to raise it -- 64 KB of headers
 * from a static file server is already absurd. */
#define HDRMAX   65536L

/* state that the timeout handler must be able to clean up */
static jmp_buf timeout_jmp;
static int g_sock = -1;
static FILE *g_out = NULL;
static char *g_part = NULL;

/* inactivity-timer state: the window currently armed, and how many
 * body bytes have arrived (so the message can say where it died) */
static long g_timeout = APKG_DEF_TIMEOUT;
static long g_total = 0L;

static void on_alarm(int sig)
{
    (void)sig;
    longjmp(timeout_jmp, 1);
}

/*
 * (Re)arm the inactivity timer.  Called immediately before every call
 * that can block, which is what turns one whole-transfer cap into a
 * per-chunk one: each arrival restarts the countdown, so the timeout
 * measures SILENCE, not duration.
 */
static void to_arm(long secs)
{
    g_timeout = secs;
    alarm((unsigned)secs);
}

static void net_cleanup(void)
{
    if (g_sock >= 0) {
        close(g_sock);
        g_sock = -1;
    }
    if (g_out != NULL) {
        fclose(g_out);
        g_out = NULL;
    }
    if (g_part != NULL) {
        unlink(g_part);
        free(g_part);
        g_part = NULL;
    }
}

/* ---------------- URL handling ---------------- */

struct urlparts {
    char host[256];
    int port;
    char *path;     /* allocated */
};

static int ci_starts(const char *s, const char *prefix)
{
    while (*prefix != '\0') {
        if (tolower((unsigned char)*s) != tolower((unsigned char)*prefix))
            return 0;
        s++;
        prefix++;
    }
    return 1;
}

/* returns 0 ok / -1 bad; fills u; u->path is allocated */
static int parse_url(const char *url, struct urlparts *u)
{
    const char *p;
    const char *hstart;
    unsigned hlen;

    if (!ci_starts(url, "http://"))
        return -1;
    p = url + 7;
    hstart = p;
    while (*p != '\0' && *p != ':' && *p != '/')
        p++;
    hlen = (unsigned)(p - hstart);
    if (hlen == 0 || hlen >= sizeof(u->host))
        return -1;
    memcpy(u->host, hstart, hlen);
    u->host[hlen] = '\0';
    u->port = 80;
    if (*p == ':') {
        p++;
        if (!isdigit((unsigned char)*p))
            return -1;
        u->port = atoi(p);
        if (u->port <= 0 || u->port > 65535)
            return -1;
        while (isdigit((unsigned char)*p))
            p++;
        if (*p != '\0' && *p != '/')
            return -1;
    }
    u->path = (*p == '\0') ? xstrdup("/") : xstrdup(p);
    return 0;
}

/*
 * Issue INITQPARMS on the stream behind `fd`, asking the tcp module
 * for a receive high-water mark of `want` bytes.
 *
 * Returns  1  the ioctl was issued and the module accepted it
 *          0  nothing was attempted; *why says which gate stopped it
 *         -1  it was issued and refused; *why is strerror(errno)
 *
 * *clamped receives the value actually asked for, which is `want`
 * capped at 65535 because iqp_value is a 16-bit field.
 */
static int tcp_hiwat(int fd, long want, long *clamped, const char **why)
{
    struct apkg_qparm qp;

    *why = NULL;
    *clamped = want > APKG_IQP_MAX ? APKG_IQP_MAX : want;

    if (want <= 0) {
        *why = "rcvbuf=0";
        return 0;
    }
    /* initqparms() is gated by drv_priv() and returns EPERM to an
     * unprivileged caller; ask geteuid() first so the -v line names
     * the real reason instead of printing "Not owner". */
    if (geteuid() != 0) {
        *why = "not root -- INITQPARMS is privileged";
        return 0;
    }

    qp.type  = (unsigned short)(APKG_IQP_RQ | APKG_IQP_HIWAT);
    qp.value = (unsigned short)*clamped;

#ifdef APKG_STREAMS
    {
        struct strioctl si;

        si.ic_cmd = APKG_INITQPARMS;
        si.ic_timout = 0;                  /* stream-head default */
        si.ic_len = (int)sizeof(qp);
        si.ic_dp = (char *)&qp;
        if (ioctl(fd, I_STR, (char *)&si) < 0) {
            *why = strerror(errno);
            return -1;
        }
        return 1;
    }
#else
    (void)fd;
    (void)qp;
    *why = "this build has no STREAMS";
    return 0;
#endif
}

/* One attempt plus its -v line.  `where` says which of the two calls
 * this is, because they mean different things: "template" is the one
 * that works under the semantics the source actually shows, "stream"
 * is the belt for the other possibility. */
static void tcp_hiwat_try(int fd, long want, const char *where)
{
    static int clamp_noted = 0;
    static int warned = 0;
    const char *why;
    long asked;
    int rc;

    if (want <= 0)
        return;                 /* rcvbuf=0 disables the mechanism */
    rc = tcp_hiwat(fd, want, &asked, &why);
    /* the clamp is a property of the configured value, not of this
     * attempt, so say it once rather than twice per fetch */
    if (asked != want && !clamp_noted) {
        clamp_noted = 1;
        note("INITQPARMS: rcvbuf %ld clamped to %ld (iqp_value is 16-bit)",
             want, asked);
    }
    if (rc > 0) {
        note("INITQPARMS(%s): IQP_RQ|IQP_HIWAT <- %ld accepted by the tcp module",
             where, asked);
        /* Warning level, not -v: this changed the BOX, not this
         * process, and nothing will change it back.  Said once. */
        if (!warned) {
            warned = 1;
            warnx2("tcp receive window set to %ld box-wide until reboot "
                   "(every new TCP stream, not just apkg); restore with "
                   "rcvbuf=4096 as root, or reboot", asked);
            warnx2("on z3660eth a window above 4096 is SLOWER "
                   "(RX loss past ~8 segments in flight); measured "
                   "4096 ~54 KB/s, 8192 ~32, 16384 ~36-40");
        }
    } else if (rc < 0)
        note("INITQPARMS(%s): IQP_RQ|IQP_HIWAT <- %ld refused (%s)",
             where, asked, why);
    else
        note("INITQPARMS(%s): IQP_RQ|IQP_HIWAT <- %ld not attempted (%s)",
             where, asked, why);
}

/*
 * Raise the tcp module's module_info template once per process, on a
 * throwaway stream, BEFORE the first fetch socket is opened -- see the
 * ORDERING note at the top of this file.  A socket we cannot even
 * create is not worth a diagnostic here: do_get() is about to fail on
 * its own socket() with a real message.
 */
static void tcp_tune(const struct httpopts *o)
{
    static int done = 0;
    int fd;

    if (done || o->rcvbuf <= 0)
        return;
    done = 1;
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return;
    tcp_hiwat_try(fd, o->rcvbuf, "template");
    (void)close(fd);
}

/* Request a socket buffer size and report what the socket layer says
 * it is.  `want` of 0 means "leave the stack default alone" -- but we
 * still read the value back under -v, because knowing the default is
 * half of knowing whether raising it is worth anything.
 *
 * "reports" is deliberate wording: on the stock Amix stack sockmod may
 * answer from its own cached value while the tcp module below it keeps
 * its 4096 hiwat, so this line says what we asked and what the socket
 * layer claims -- never what TCP is actually using. */
static void set_sockbuf(int sock, int optname, const char *what, long want)
{
    int v;
    int got;
    int len;

    if (want > 0) {
        v = (int)want;
        if (setsockopt(sock, SOL_SOCKET, optname,
                       (char *)&v, (int)sizeof(v)) < 0) {
            warnx2("%s %ld refused by the stack (%s); "
                   "continuing with its default", what, want,
                   strerror(errno));
        }
    }
    got = 0;
    len = (int)sizeof(got);
    /* the 5th argument is int* on SVR4 and socklen_t* on modern hosts;
     * void* converts implicitly to either, so one cast serves both */
    if (getsockopt(sock, SOL_SOCKET, optname, (char *)&got,
                   (void *)&len) == 0)
        note("%s: asked %ld, socket layer reports %d "
             "(not proof TCP honoured it)", what, want, got);
    else
        note("%s: asked %ld, socket layer will not report a value",
             what, want);
}

static int send_all(int sock, const char *buf, unsigned len, long idle)
{
    int n;

    while (len > 0) {
        to_arm(idle);
        n = send(sock, buf, (int)len, 0);
        if (n <= 0)
            return -1;
        buf += n;
        len -= (unsigned)n;
    }
    return 0;
}

/* case-insensitive header line match; returns pointer past "name:"
 * (with following spaces skipped) or NULL */
static const char *header_value(const char *line, const char *name)
{
    unsigned nl;

    nl = (unsigned)strlen(name);
    if (!ci_starts(line, name))
        return NULL;
    if (line[nl] != ':')
        return NULL;
    line += nl + 1;
    while (*line == ' ' || *line == '\t')
        line++;
    return line;
}

/* one GET request/response; may recurse once for a redirect */
static int do_get(const char *url, const char *dest,
                  const struct httpopts *o, char *iobuf, long iobufsz,
                  int *status, int depth)
{
    struct urlparts u;
    struct sockaddr_in sin;
    unsigned long ipaddr;
    char *req;
    char *hdr;
    long hdrlen, hdrcap;
    char *body;
    long bodyleft;
    const char *val;
    char *location;
    char *line;
    char *next;
    long content_length;
    long total;
    long chunkmark;
    long step;
    int code;
    int n;
    int rc;

    location = NULL;
    hdr = NULL;
    u.path = NULL;

    if (parse_url(url, &u) != 0) {
        warnx2("bad URL: %s", url);
        return HTTP_ENET;
    }
    note("GET %s", url);

    memset((char *)&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons((unsigned short)u.port);
    /*
     * Resolution runs OUTSIDE this fetch's inactivity timer, and that is
     * deliberate.  dns.c owns its own, much shorter per-attempt budget
     * and has to be able to RECOVER from a timeout -- fall through to
     * the next attempt, the next nameserver, or (when the host database
     * hangs) to the resolver at all.  Our timer cannot express that: it
     * longjmps out to http_get()'s retry loop and kills the fetch.  So
     * disarm it across the call, then put it back.
     *
     * apkg_resolve() prints its own diagnostics, including which of the
     * three sources answered under -v, so there is no message here.
     */
    alarm(0);
    signal(SIGALRM, SIG_DFL);
    rc = apkg_resolve(u.host, &o->dns, o->conn_timeout, &ipaddr);
    signal(SIGALRM, on_alarm);
    if (rc != 0) {
        free(u.path);
        return HTTP_ENET;
    }
    memcpy((char *)&sin.sin_addr, (char *)&ipaddr, 4);

    /* Before socket(), because INITQPARMS rewrites the tcp module's
     * module_info template and STREAMS copies that template into
     * q_hiwat at OPEN time -- issuing it later would miss this very
     * stream.  Runs once per process. */
    tcp_tune(o);

    g_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (g_sock < 0) {
        warnx2("cannot create socket");
        free(u.path);
        return HTTP_ENET;
    }
    /* Before connect(), so SO_RCVBUF is in force when the SYN carries
     * the advertised window -- setting it afterwards is too late to
     * affect the handshake on most stacks.  A stack that refuses or
     * silently clamps the request is not an error; getsockopt() says
     * what we really got, and -v prints it.  That readback IS the
     * probe: it is how the honoured maximum was measured on Amix. */
    set_sockbuf(g_sock, SO_RCVBUF, "SO_RCVBUF", o->rcvbuf);
    set_sockbuf(g_sock, SO_SNDBUF, "SO_SNDBUF", o->sndbuf);
    /* Belt for the live-queue reading of initqparms(); a harmless
     * no-op under the template reading the source actually shows. */
    tcp_hiwat_try(g_sock, o->rcvbuf, "stream");
    to_arm(o->conn_timeout);
    if (connect(g_sock, (struct sockaddr *)&sin, sizeof(sin)) < 0) {
        warnx2("cannot connect to %s port %d", u.host, u.port);
        net_cleanup();
        free(u.path);
        return HTTP_ENET;
    }

    /* request; length pre-computed, sprintf is bounded by construction */
    req = xmalloc((unsigned)(strlen(u.path) + strlen(u.host) + 96));
    if (u.port == 80)
        sprintf(req,
            "GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: apkg/%s\r\nConnection: close\r\n\r\n",
            u.path, u.host, APKG_VERSION);
    else
        sprintf(req,
            "GET %s HTTP/1.0\r\nHost: %s:%d\r\nUser-Agent: apkg/%s\r\nConnection: close\r\n\r\n",
            u.path, u.host, u.port, APKG_VERSION);
    if (send_all(g_sock, req, (unsigned)strlen(req), o->timeout) != 0) {
        warnx2("failed to send request to %s", u.host);
        free(req);
        net_cleanup();
        free(u.path);
        return HTTP_ENET;
    }
    free(req);

    /* read until end of headers */
    hdrcap = iobufsz;
    hdr = xmalloc((unsigned)hdrcap);
    hdrlen = 0;
    body = NULL;
    bodyleft = 0;
    for (;;) {
        char *split;

        to_arm(o->timeout);
        n = recv(g_sock, iobuf, (int)iobufsz, 0);
        if (n < 0) {
            warnx2("read error from %s", u.host);
            free(hdr);
            net_cleanup();
            free(u.path);
            return HTTP_ENET;
        }
        if (n == 0) {
            hdr[hdrlen < hdrcap ? hdrlen : hdrcap - 1] = '\0';
            split = strstr(hdr, "\n\r\n");
            if (split == NULL)
                split = strstr(hdr, "\n\n");
            if (split == NULL) {
                warnx2("short response from %s", u.host);
                free(hdr);
                net_cleanup();
                free(u.path);
                return HTTP_ENET;
            }
            break;
        }
        if (hdrlen + n + 1 > hdrcap) {
            if (hdrcap * 2 > HDRMAX + iobufsz) {
                warnx2("response headers too large from %s", u.host);
                free(hdr);
                net_cleanup();
                free(u.path);
                return HTTP_ENET;
            }
            hdrcap *= 2;
            hdr = xrealloc(hdr, (unsigned)hdrcap);
        }
        memcpy(hdr + hdrlen, iobuf, (unsigned)n);
        hdrlen += n;
        hdr[hdrlen] = '\0';
        if (strstr(hdr, "\r\n\r\n") != NULL ||
            strstr(hdr, "\n\n") != NULL)
            break;
    }

    /* split headers from any body bytes already read */
    {
        char *split;
        long skip;

        split = strstr(hdr, "\r\n\r\n");
        skip = 4;
        if (split == NULL) {
            split = strstr(hdr, "\n\n");
            skip = 2;
        }
        if (split == NULL) {
            warnx2("malformed response from %s", u.host);
            free(hdr);
            net_cleanup();
            free(u.path);
            return HTTP_ENET;
        }
        *split = '\0';
        body = split + skip;
        bodyleft = hdrlen - (long)(body - hdr);
        if (bodyleft < 0)
            bodyleft = 0;
    }

    /* status line */
    if (!ci_starts(hdr, "HTTP/")) {
        warnx2("not an HTTP response from %s", u.host);
        free(hdr);
        net_cleanup();
        free(u.path);
        return HTTP_ENET;
    }
    code = 0;
    {
        char *sp;

        sp = strchr(hdr, ' ');
        if (sp != NULL)
            code = atoi(sp + 1);
    }
    if (code <= 0) {
        warnx2("bad status line from %s", u.host);
        free(hdr);
        net_cleanup();
        free(u.path);
        return HTTP_ENET;
    }

    /* headers */
    content_length = -1;
    line = strchr(hdr, '\n');
    while (line != NULL) {
        line++;
        next = strchr(line, '\n');
        if (next != NULL)
            *next = '\0';
        if (line[0] != '\0' && line[strlen(line) - 1] == '\r')
            line[strlen(line) - 1] = '\0';
        val = header_value(line, "content-length");
        if (val != NULL)
            content_length = atol(val);
        val = header_value(line, "location");
        if (val != NULL) {
            if (location != NULL)
                free(location);
            location = xstrdup(val);
        }
        line = next;
    }

    if ((code == 301 || code == 302) && location != NULL &&
        depth < o->redirects) {
        char *newurl;

        close(g_sock);
        g_sock = -1;
        if (ci_starts(location, "http://")) {
            newurl = xstrdup(location);
        } else if (location[0] == '/') {
            char portbuf[16];

            if (u.port == 80)
                portbuf[0] = '\0';
            else
                sprintf(portbuf, ":%d", u.port);  /* bounded: <= 6 chars */
            newurl = xmalloc((unsigned)(7 + strlen(u.host) +
                                        strlen(portbuf) +
                                        strlen(location) + 1));
            sprintf(newurl, "http://%s%s%s", u.host, portbuf, location);
        } else {
            warnx2("unsupported redirect location: %s", location);
            free(location);
            free(hdr);
            free(u.path);
            return HTTP_ENET;
        }
        note("redirected (%d) to %s", code, newurl);
        free(location);
        free(hdr);
        free(u.path);
        rc = do_get(newurl, dest, o, iobuf, iobufsz, status, depth + 1);
        free(newurl);
        return rc;
    }
    if (location != NULL) {
        free(location);
        location = NULL;
    }

    if (code != 200) {
        *status = code;
        note("HTTP status %d for %s", code, url);
        free(hdr);
        net_cleanup();
        free(u.path);
        return HTTP_ESTATUS;
    }

    /* stream the body to dest.part, then rename */
    g_part = cat2(dest, ".part");
    g_out = fopen(g_part, "wb");
    if (g_out == NULL) {
        warnx2("cannot write %s", g_part);
        free(hdr);
        net_cleanup();
        free(u.path);
        return HTTP_ENET;
    }
    total = 0;
    chunkmark = 0;
    /* -v quarters the configured interval; progress=0 silences it */
    step = o->progress;
    if (step > 0 && opt_verbose) {
        step /= 4;
        if (step < 1)
            step = 1;
    }
    if (bodyleft > 0) {
        if (fwrite(body, 1, (unsigned)bodyleft, g_out) !=
            (unsigned)bodyleft) {
            warnx2("write error on %s", g_part);
            free(hdr);
            net_cleanup();
            free(u.path);
            return HTTP_ENET;
        }
        total += bodyleft;
        g_total = total;
    }
    free(hdr);
    hdr = NULL;
    for (;;) {
        to_arm(o->timeout);
        n = recv(g_sock, iobuf, (int)iobufsz, 0);
        if (n < 0) {
            warnx2("read error from %s", u.host);
            net_cleanup();
            free(u.path);
            return HTTP_ENET;
        }
        if (n == 0)
            break;
        if (fwrite(iobuf, 1, (unsigned)n, g_out) != (unsigned)n) {
            warnx2("write error on %s", g_part);
            net_cleanup();
            free(u.path);
            return HTTP_ENET;
        }
        total += n;
        g_total = total;
        if (step > 0 && total - chunkmark >= step) {
            chunkmark = total;
            if (content_length > 0)
                fprintf(stderr, "apkg: ... %ld/%ld bytes\n",
                        total, content_length);
            else
                fprintf(stderr, "apkg: ... %ld bytes\n", total);
        }
    }
    close(g_sock);
    g_sock = -1;
    if (fclose(g_out) != 0) {
        g_out = NULL;
        warnx2("write error closing %s", g_part);
        net_cleanup();
        free(u.path);
        return HTTP_ENET;
    }
    g_out = NULL;

    if (content_length >= 0 && total != content_length) {
        warnx2("truncated transfer: got %ld of %ld bytes from %s",
               total, content_length, url);
        net_cleanup();      /* unlinks the .part file */
        free(u.path);
        return HTTP_ENET;
    }
    if (rename(g_part, dest) != 0) {
        warnx2("cannot rename %s to %s", g_part, dest);
        net_cleanup();
        free(u.path);
        return HTTP_ENET;
    }
    free(g_part);
    g_part = NULL;
    note("fetched %ld bytes -> %s", total, dest);
    free(u.path);
    return HTTP_OK;
}

/*
 * Public entry.  Returns HTTP_OK / HTTP_ENET / HTTP_ESTATUS (the
 * non-200 code goes into *status).
 *
 * Owns two things do_get must not: the read buffer (so the redirect
 * recursion can share one allocation and no exit path has to free it)
 * and the retry loop.  Only HTTP_ENET is retried -- a non-200 status
 * is the server ANSWERING, and asking a static file server the same
 * question again will not turn a 404 into a package.
 */
int http_get(const char *url, const char *dest, const struct httpopts *o,
             int *status)
{
    struct httpopts opts;
    char *iobuf;
    long iobufsz;
    long delay;
    int attempt;
    int rc;

    if (o != NULL)
        opts = *o;
    else
        http_opts_default(&opts);
    if (opts.timeout <= 0)
        opts.timeout = APKG_DEF_TIMEOUT;
    if (opts.conn_timeout <= 0)
        opts.conn_timeout = APKG_DEF_CONNTIMEO;
    if (opts.retries < 0)
        opts.retries = 0;
    if (opts.retry_delay < 0)
        opts.retry_delay = 0;
    if (opts.progress < 0)
        opts.progress = 0;
    if (opts.redirects < 0)
        opts.redirects = 0;
    if (opts.rcvbuf < 0)
        opts.rcvbuf = 0;
    if (opts.sndbuf < 0)
        opts.sndbuf = 0;
    iobufsz = opts.bufsize;
    if (iobufsz < APKG_MIN_BUFSIZE)
        iobufsz = APKG_MIN_BUFSIZE;
    if (iobufsz > APKG_MAX_BUFSIZE)
        iobufsz = APKG_MAX_BUFSIZE;
    opts.bufsize = iobufsz;
    iobuf = xmalloc((unsigned)iobufsz);

    delay = opts.retry_delay;
    for (attempt = 0; ; attempt++) {
        *status = 0;
        g_timeout = opts.timeout;
        g_total = 0;
        if (setjmp(timeout_jmp) != 0) {
            alarm(0);
            signal(SIGALRM, SIG_DFL);
            /* We arrived here by longjmp FROM the SIGALRM handler, so
             * SIGALRM may still be blocked -- and the loop below is
             * about to arm alarm() again for the retry.  Without this
             * the second stall would never time out and the client
             * would hang forever (reproduced host-side 2026-09-16; the
             * stall test only ever took the first timeout, because it
             * runs with retries=0). */
            unblock_alarm();
            net_cleanup();
            warnx2("timeout: no data for %ld s (%ld bytes received) "
                   "fetching %s", g_timeout, g_total, url);
            rc = HTTP_ENET;
        } else {
            signal(SIGALRM, on_alarm);
            rc = do_get(url, dest, &opts, iobuf, iobufsz, status, 0);
            alarm(0);
            signal(SIGALRM, SIG_DFL);
        }
        if (rc != HTTP_ENET || attempt >= opts.retries)
            break;
        warnx2("retrying %s (attempt %d of %d) in %ld s",
               url, attempt + 2, opts.retries + 1, delay);
        if (delay > 0)
            sleep((unsigned)delay);
        delay = (delay > 0) ? delay * 2 : 0;
    }
    free(iobuf);
    return rc;
}
