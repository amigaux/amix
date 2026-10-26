/*
 * apkg.h - common declarations for apkg, the Amix remote package client.
 *
 * Copyright (c) 2026 Jussi Alanärä
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef APKG_H
#define APKG_H

#include <stdio.h>

#define APKG_VERSION "0.3.3"

/*
 * Built-in defaults for every knob on the fetch path.  All seven are
 * overridable from /etc/apkg.conf (conf.c) -- nothing on this path is
 * a compiled-in constant an operator cannot move.
 *
 * The load-bearing one is APKG_DEF_TIMEOUT, and since 2026-09-16 it
 * measures network SILENCE, not transfer duration (http.c re-arms the
 * timer on every chunk that arrives).  That distinction, not the
 * number, is what fixed the A4000D failure: an 8.2 MB package over
 * the measured ~37 KB/s A4000D -> pkg.amigaux.org path takes ~220 s
 * while flowing continuously, so the OLD 60 s whole-transfer cap
 * killed a perfectly healthy fetch -- whereas an idle threshold of
 * even 60 s would not have noticed it.  The idle threshold is about
 * stalls, never about size, so it is sized against the longest
 * legitimate GAP between two chunks (TCP retransmit storms, an Amix
 * box paging hard mid-install), not against how big packages get.
 *
 * 300 s is that, with room to spare.  It is deliberately NOT huge:
 * the only thing a larger value buys is a longer hang on a link that
 * is genuinely dead, and with retries on top the worst case
 * multiplies.  Callers that must fail fast (an unattended installer)
 * set timeout= down; callers on a truly awful link set it up.
 */
#define APKG_DEF_TIMEOUT      300L   /* idle/inactivity threshold, s   */
#define APKG_DEF_CONNTIMEO     30L   /* resolve + TCP connect, s       */
#define APKG_DEF_RETRIES         2   /* extra attempts after the first */
#define APKG_DEF_RETRYDELAY     5L   /* s before retry 1, then doubles */
#define APKG_DEF_PROGRESS  262144L   /* bytes between progress lines   */
#define APKG_DEF_BUFSIZE     8192L   /* socket read buffer, bytes      */
#define APKG_DEF_REDIRECTS       1   /* 301/302 hops followed          */

/*
 * THE STUB RESOLVER (dns.c).
 *
 * Stock Amix has no resolver: libsocket's gethostbyname() reads
 * /etc/inet/hosts and nothing else, resolv.conf is inert, and the
 * client contract is HOSTNAME ONLY (the repo host is a name-based
 * virtual host and answers a bare-IP Host: with 404) -- so on a stock
 * box "no resolver" means "no repository" until somebody hand-edits a
 * hosts line.  The Saku demo cards carry exactly such a line.
 *
 * apkg therefore carries a stub resolver for ITS OWN lookups: one UDP
 * A query, recursion requested, no EDNS, no cache, no search list, no
 * TCP fallback, no resolv.conf.  It does NOT make the box resolve
 * names -- telnet, ftp and everything else still read the hosts file.
 *
 * The nameservers are config (`nameserver=`, repeatable, tried in
 * order) and the DEFAULT LIST IS EMPTY: with nothing configured apkg
 * behaves exactly as it always did, hosts file only.  The hosts file
 * is consulted FIRST in any case, so a box that resolves today cannot
 * regress and an operator's hand-written line cannot be shadowed.
 *
 * dns_timeout is per QUERY ATTEMPT (not per name and not per server):
 * a UDP query either comes back quickly or it is lost, so this is
 * small.  dns_retries is the extra attempts PER NAMESERVER; every
 * configured server is asked in turn regardless.  Worst case for a
 * name nothing answers is therefore
 * nameservers x (dns_retries+1) x dns_timeout seconds.
 */
#define APKG_DEF_DNSTIMEO       5L   /* s per DNS query attempt        */
#define APKG_DEF_DNSRETRIES      2   /* extra attempts per nameserver  */
#define APKG_DNS_PORT           53   /* default nameserver port        */
#define APKG_MAX_NAMESERVERS     8   /* refuse an absurd list          */

/*
 * The TCP receive window, and the send buffer beside it for symmetry.
 *
 * THE DEFAULT IS 0 -- LEAVE THE STACK'S WINDOW ALONE -- AND THAT IS A
 * MEASURED RESULT, NOT CAUTION.  On a bandwidth-delay-bound path the
 * receive window normally caps a single stream (throughput <= window /
 * RTT), and Amix's compiled-in 4096 looked exactly like that cap.  It
 * is not.  Two wire captures of a real 68LC060 A4000D fetching from
 * pkg.amigaux.org over z3660eth (2026-09-14/15) showed:
 *
 *   - SO_RCVBUF 64 K requested before connect(); window advertised in
 *     the SYN and in all 2999 steady-state ACKs: 4096.  The socket
 *     option does not reach this tcp module at all.
 *   - INITQPARMS 16384 (below): the window on the wire really does
 *     become 16384 -- and throughput gets WORSE.  4096 -> ~54 KB/s;
 *     8192 -> ~32 KB/s; 16384 -> ~36-40 KB/s.
 *   - Why: the RX path loses packets past ~8 segments in flight
 *     (~10 KB outstanding).  <=7 segments per burst: 2-3 % loss.
 *     8: ~60 %.  >=9: ~100 %.  Then dup-ACKs and a server RTO.
 *   - The stock 4096 window allows at most 8 segments (7x536+344) and
 *     therefore sits RIGHT AT the loss-free edge.  It is near-optimal
 *     for this driver as it stands.
 *
 * So the window is NOT the lever here; the RX drop mechanism is (the
 * Z3660 firmware's discard-whole-backlog on overflow, and/or the
 * 16.67 ms poll quantum), and that lives in the driver and firmware
 * repos.  Until it is fixed, raising this on z3660eth makes apkg
 * SLOWER.  Do not ship a raised default, and do not read a bigger
 * number here as a speed fix.
 *
 * What rcvbuf > 0 DOES, when an operator explicitly asks for it:
 *
 *   1. The STREAMS INITQPARMS ioctl (IQP_RQ|IQP_HIWAT) on the tcp
 *      module -- the one that actually moves the window, confirmed on
 *      the metal.  Root only.  It rewrites the module's DEFAULT hiwat,
 *      so the change is BOX-WIDE until reboot, reaches every TCP
 *      stream opened afterwards (not just apkg's), and must be issued
 *      BEFORE the stream it is meant to affect is opened.  There is no
 *      INITQPARMS read-back, and sockmod's cached so->rcvbuf starts at
 *      0 (sockmod.c:264-265), so nothing can report the value that was
 *      there first -- apkg cannot and does not restore it.  Put it
 *      back with a root run at rcvbuf=4096 (the stock value), or by
 *      rebooting.
 *   2. SO_RCVBUF with setsockopt() before connect(), kept as the
 *      non-root fallback and for non-Amix hosts.  On Amix it is known
 *      not to reach TCP; the getsockopt() value apkg prints can be
 *      served from sockmod's own cached copy, so treat the -v line as
 *      "what we asked, and what the socket layer says" -- never as
 *      "what TCP is using".
 *
 * http.c carries the full source-cited rationale, the libsocket and
 * sockmod pass-through proofs and the ordering argument; read it
 * before touching this.
 *
 * Bounds if you do set it: nothing above 65535 can ever be advertised
 * (Amix predates RFC 1323, so no window scaling), INITQPARMS caps at
 * 65535 anyway because iqp_value is a 16-bit field, and 16384 is the
 * highest anyone should consider on z3660eth -- MSS to a non-local
 * host is pinned at 536 and the firmware RX ring has 32 usable slots,
 * so past ~32 x 536 ~= 17 KB the ring itself overruns, and that
 * firmware DISCARDS its whole queued backlog rather than
 * back-pressuring.
 */
#define APKG_DEF_RCVBUF         0L   /* TCP window: 0 = leave it alone */
#define APKG_DEF_SNDBUF         0L   /* SO_SNDBUF; 0 = stack default   */
#define APKG_MAX_SOCKBUF   1048576L  /* refuse absurd requests         */

/* hard bounds on bufsize: below 512 the syscall overhead dominates on
 * a 68030, above 256 KB it is just wasted address space on a box whose
 * per-process data rlimit is measured in single-digit megabytes */
#define APKG_MIN_BUFSIZE      512L
#define APKG_MAX_BUFSIZE   262144L

/* Exit codes (docs/design.md section 2). */
#define EX_OK      0   /* success */
#define EX_USAGE   1   /* usage or configuration error */
#define EX_NET     2   /* network failure */
#define EX_VERIFY  3   /* md5/size/catalog verification failure */
#define EX_PKGCMD  4   /* pkgadd/pkgrm (or zcat step) failure */
#define EX_DEPS    5   /* dependency cycle or missing dependency; also a
                          kernel-space pre-flight refusal (kabi, pin, line) */
#define EX_BOOTSET 6   /* kbootset could not run, failed (status 1) or
                          rejected its arguments (2); the packages are
                          installed, `apkg recover` retries the build */
#define EX_BOOTGATE 7  /* kbootset refused by a rule (3) or a gate (4):
                          the committed generation is unchanged */

/* Catalog header line required on the first line of every catalog. */
#define CATALOG_MAGIC "#apkg-catalog 1"

/* The kernel-space block (amix-dlm docs/contracts/C2-2-kpkg.md §1):
 *     #ext kpkg 1
 *     #kpkg <name> <version> role= line= kabi= pin= size= sha256= file=
 *     #ksig <key-id> <file>
 *     #end kpkg
 * Every line starts with '#' in column 0, so a 0.2.x client skips the
 * block whole and never sees kernel space. */
#define KPKG_EXT     "#ext kpkg"
#define KPKG_VERSION 1
#define KPKG_END     "#end kpkg"

/* -------- global option flags (set in main.c) -------- */

extern int opt_dryrun;   /* -n */
extern int opt_force;    /* -f */
extern int opt_verbose;  /* -v */

/* -------- configuration (conf.c) -------- */

struct conf {
    char *root;        /* APKG_ROOT prefix, compiled-in defaults ("" off) */
    char *target;      /* -R target root ("" when unset)               */
    char *conffile;    /* config file actually consulted               */
    char *repo;        /* repository / source spec (URL, /path, raw:..) */
    char *cachedir;    /* package download cache                       */
    char *pkgadd;      /* pkgadd binary (engine; NOT -R prefixed)       */
    char *pkgrm;       /* pkgrm binary (engine; NOT -R prefixed)        */
    char *admin;       /* admin(4) file passed with -a                 */
    long timeout;      /* HTTP idle/inactivity threshold, seconds      */
    long conn_timeout; /* resolve + connect budget, seconds            */
    int  retries;      /* extra attempts after a failed network fetch  */
    long retry_delay;  /* seconds before the first retry; then doubles */
    long progress;     /* bytes between progress lines; 0 disables     */
    long bufsize;      /* socket read buffer, bytes                    */
    int  redirects;    /* 301/302 hops followed; 0 disables            */
    long rcvbuf;       /* SO_RCVBUF before connect; 0 = stack default  */
    long sndbuf;       /* SO_SNDBUF before connect; 0 = stack default  */
    char **nameservers;   /* nameserver= values, in config order       */
    int  nnameservers;    /* 0 = hosts file only (the default)         */
    long dns_timeout;  /* seconds per DNS query attempt                */
    int  dns_retries;  /* extra DNS attempts per nameserver            */
    char *catalog;     /* local catalog path: dirname(cachedir)/catalog */
    char *sadmpkg;     /* <root><target>/var/sadm/pkg (the TARGET DB)  */
    char *contents;    /* <root><target>/var/sadm/install/contents     */
    char *kpkgdir;     /* <root><target>/var/apkg/kpkg (C2-2 records)  */
    char *txnfile;     /* <root><target>/var/apkg/txn (the journal)    */
    char *bootsetconf; /* <root><target>/etc/default/bootset           */
    char *kbootset;    /* kbootset binary (engine-like: NOT -R prefixed) */
    char *kbootset_journal; /* --journal handed to kbootset; "" = the
                               contract default <target>/var/kbootset/journal */
    int pkgadd_is_default; /* pkgadd came from built-in default        */
    int pkgrm_is_default;  /* pkgrm came from built-in default         */
};

/* conffile_opt is the -c argument or NULL; target_opt is the -R argument
 * or NULL (installs into that root without moving the engine/config). */
extern int conf_load(const char *conffile_opt, const char *target_opt,
                     struct conf *cf);
extern char *conf_pkgcmd(const struct conf *cf, int is_rm);

/* the resolver's -v line (nameserver list, dns_timeout, dns_retries),
 * printed beside the fetch one; a no-op unless -v */
extern void conf_note_dns(const struct conf *cf);

/* The admin(4) file to hand `pkgadd -a` / `pkgrm -a`, MATERIALISED on
 * the spot: the APKG package owns /var/apkg/admin as an `e` entry, so
 * a `pkgrm APKG` deletes it and any later pkgadd that merely assumed
 * it was there died with "unable to open admin file" -- which is how
 * the old upgrade verb bricked apkg on metal.  overwrite != 0 returns
 * a DERIVED <admin>.overwrite carrying instance=overwrite (every other
 * key copied from the operator's own admin file), which is what lets
 * pkgadd replace an installed instance of a different version.
 * Allocated path, or NULL on failure (message printed).  Writes
 * nothing under -n. */
extern char *conf_adminfile(const struct conf *cf, int overwrite);

/* -------- catalog (catalog.c) -------- */

struct pkgent {
    char *name;
    char *version;
    char *pkginst;
    char *filename;
    char *md5;        /* 32 lowercase hex chars */
    long size;        /* bytes of the file as transported */
    char **deps;      /* dependency package names */
    int ndeps;
    char *category;
    char *desc;
    long offset;      /* RAW byte offset (optional 10th field); -1 = absent */
    int mark;         /* scratch: topological sort state */
    /* kernel space (#ext kpkg 1); all NULL / 0 on an ordinary entry */
    int kspace;       /* 1 = an entry of the kernel-space block        */
    char *role;       /* kernel | loader | module                      */
    char *kline;      /* k30 | k46; "any" for the loader               */
    char *kabi;       /* kabi tag, e.g. k46.1.0 or static; "-" loader  */
    char *pin;        /* compiler pin; "-" for the loader              */
    char *sha256;     /* 64 lowercase hex of the datastream as served  */
    char *loaderv;    /* loader=<n> of a loader entry; "-" otherwise   */
    char *kpkginst;   /* optional pkginst= key; NULL = from the datastream */
    char *refused;    /* NULL, or why the entry may not be installed   */
};

struct catalog {
    struct pkgent *ents;
    int n;
    int cap;
    int nk;           /* kernel-space entries among ents (refused incl.) */
    char *ksig_key;   /* #ksig key id, NULL when absent (always in 1.1) */
    char *ksig_file;  /* #ksig signature file name                      */
    int kverified;    /* the verification hook's verdict: always 0 in 1.1 */
};

#define CAT_OK       0
#define CAT_ENOENT  -1   /* file does not exist / unreadable */
#define CAT_EBADHDR -2   /* missing #apkg-catalog 1 header   */
#define CAT_EFORMAT -3   /* malformed entry line             */

extern int catalog_load(const char *path, struct catalog *cat);
extern struct pkgent *catalog_find(struct catalog *cat, const char *name);
extern void catalog_free(struct catalog *cat);

/* -------- version compare (vercmp.c) -------- */

extern int apkg_vercmp(const char *a, const char *b);

/* -------- HTTP client (http.c) -------- */

#define HTTP_OK        0   /* 200, body stored in dest */
#define HTTP_ENET     -1   /* network / protocol / timeout error */
#define HTTP_ESTATUS  -2   /* server replied non-200 (status in *status) */

/* Every tunable of one fetch, in one place, so the knobs travel
 * together from apkg.conf to the socket instead of as a widening
 * argument list. */
/* Everything the stub resolver needs, carried inside struct httpopts so
 * the resolver's knobs travel with the fetch's.  `servers` points at the
 * struct conf's own array and is NOT owned here -- copying a struct
 * httpopts copies the pointer, never the strings. */
struct dnsopts {
    char **servers;     /* nameservers in config order; NULL = none   */
    int  nservers;
    long timeout;       /* seconds per query attempt                  */
    int  retries;       /* extra attempts per nameserver              */
};

struct httpopts {
    long timeout;       /* seconds of silence tolerated mid-transfer  */
    long conn_timeout;  /* seconds for resolve + connect              */
    int  retries;       /* extra attempts after a network failure     */
    long retry_delay;   /* seconds before retry 1; doubles thereafter */
    long progress;      /* bytes between progress lines; 0 = quiet    */
    long bufsize;       /* socket read buffer                         */
    int  redirects;     /* 301/302 hops followed                      */
    long rcvbuf;        /* SO_RCVBUF, set before connect; 0 = leave    */
    long sndbuf;        /* SO_SNDBUF, set before connect; 0 = leave    */
    struct dnsopts dns; /* the stub resolver's own knobs               */
};

/* fill o with the compiled-in defaults / with the configured values */
extern void http_opts_default(struct httpopts *o);
extern void http_opts_from_conf(struct httpopts *o, const struct conf *cf);

extern int http_get(const char *url, const char *dest,
                    const struct httpopts *o, int *status);

/* -------- name resolution (dns.c) --------
 *
 * Compiled only into the HTTP-capable build: the FILE+RAW static
 * variant (-DAPKG_NO_HTTP) has no sockets at all.
 *
 * apkg_resolve() is the whole step -- IPv4 literal, then the host
 * database (gethostbyname, i.e. /etc/inet/hosts on Amix), then the stub
 * resolver -- and prints under -v which of the three answered.
 * apkg_dns_query() is the stub resolver alone, exposed so it can be
 * tested without a host database in the way.  Both fill *addr in
 * NETWORK byte order and return 0 / -1 (message already printed). */
extern int apkg_resolve(const char *host, const struct dnsopts *d,
                        long hosts_timeout, unsigned long *addr);
extern int apkg_dns_query(const char *host, const struct dnsopts *d,
                          unsigned long *addr);
extern int apkg_ipv4_parse(const char *s, unsigned long *addr);
extern void apkg_ipv4_str(unsigned long addr, char *buf);  /* buf >= 16 */

/* -------- installed state + verbs (install.c) -------- */

/* returns 0 = not installed; 1 = installed, version copied into ver
 * (empty string when the pkginfo has no VERSION= line) */
extern int installed_version(const struct conf *cf, const char *pkginst,
                             char *ver, unsigned verlen);

extern int cmd_download(const struct conf *cf, struct catalog *cat,
                        const char *name);
extern int cmd_install(const struct conf *cf, struct catalog *cat,
                       char **names, int nnames);
extern int cmd_upgrade(const struct conf *cf, struct catalog *cat,
                       char **names, int nnames);
extern int cmd_remove(const struct conf *cf, struct catalog *cat,
                      const char *name);
extern int cmd_recover(const struct conf *cf);

/* -------- kernel space (kspace.c) -------- */

/* SHA-256 of a file as 64 lowercase hex chars; 0 ok / -1 unreadable */
extern int sha256_file(const char *path, char hexout[65]);

/* The verification hook of 60 §4: runs once the catalog is read and
 * before any kernel-space entry is used.  In 1.1 it records
 * "unverified" (cat->kverified = 0) and passes; a later release puts
 * the signature check here and may refuse the block. */
extern void kspace_verify_hook(struct catalog *cat);

/* The record file is /var/apkg/kpkg/<key>, key = the pkginst: the
 * entry's pkginst= when given, else its name (C2-2 v4 §2; struct
 * pkgent's pkginst field is exactly that).  The full name is its `name`
 * line.
 * installed version of a kernel-space package, from its record:
 * 0 = no record, 1 = record (version copied) */
extern int kpkg_installed(const struct conf *cf, const char *key,
                          char *ver, unsigned verlen);
/* the record of a package given by name or pkginst; its file name into
 * key.  1 = found, 0 = none */
extern int kpkg_find(const struct conf *cf, const char *arg, char *key,
                     unsigned cap);
/* the pkginst a datastream carries (its header); 0 ok / -1 */
extern int ds_pkginst(const char *path, char *out, unsigned outlen);
/* 40 §6 "pure files": the datastream's pkgmap holds only f and d objects
 * of class none and no install scripts (i: pkginfo, depend, copyright),
 * and at least one f; with module set, also c entries of class none
 * under /dev/ and b entries under /dev/dsk/ (C3-5 v8 §1.2: the driver's
 * device nodes).  0 = pure;
 * -1 = not, or unreadable (why[] says) */
extern int ds_pure_files(const char *path, int module, char *why,
                         unsigned cap);
/* write the C2-2 v4 §2 record <key> after a successful pkgadd: one
 * `file` line per plain file the contents database lists for pkginst
 * (the datastream's instance), with the size and SHA-256 of the
 * installed file.  EX_* code. */
extern int kpkg_write_record(const struct conf *cf, const struct pkgent *e,
                             const char *pkginst, const char *source);
extern int kpkg_write_record_fields(const struct conf *cf,
    const char *key, const char *name, const char *version, const char *role,
    const char *line, const char *kabi, const char *pin,
    const char *loaderv, const char *sha256, const char *pkginst,
    const char *source);
/* the pkginst owning a recorded package's files (contents database);
 * 0 ok / -1 */
extern int kpkg_owner(const struct conf *cf, const char *key,
                      char *pkginst, unsigned len);
extern int kpkg_remove_record(const struct conf *cf, const char *key);
/* pre-flight of 40 §6 over the kernel-space members of a transaction:
 * refused entries, kabi family/major/minor, compiler pin, line.  0 ok,
 * EX_* on refusal (message printed). */
extern int kspace_preflight(const struct conf *cf, struct pkgent **todo,
                            int nt);
/* One kernel package per line (C2-2 v5 §2.1).  Every kernel package of a
 * line installs /stand/<line>/unix, so a transaction that installs a
 * role=kernel package replaces the kernel package of the same line that
 * is recorded under another pkginst ("the other kernel package"): its
 * pkgrm and record removal come first, then the new pkgadd, all in one
 * journal.  kspace_replaces() finds them and prints the plan line; it
 * refuses (EX_DEPS, message printed) two kernel packages of one line in
 * the transaction, and two or more kernel records of a line the
 * transaction installs a kernel or module for.  *rep is allocated (free
 * it), *nrep may be 0. */
struct kreplace {
    char key[64];       /* the other package's record file (its pkginst=) */
    char name[256];     /* its record's name line                        */
    char pkginst[64];   /* the instance pkgrm removes                     */
    char line[16];      /* k30 | k46                                      */
};
extern int kspace_replaces(const struct conf *cf, struct pkgent **todo,
                           int nt, struct kreplace **rep, int *nrep);
/* the trigger of C2-4 §3: `kbootset build` then `kbootset commit`
 * (bootset=auto), or print the command (bootset=manual).  Once the
 * build succeeded the journal t (may be NULL) is saved in state
 * "built".  Returns EX_OK, EX_BOOTSET or EX_BOOTGATE (message
 * printed). */
struct txn;
extern int kspace_trigger(const struct conf *cf, struct txn *t);

/* -------- util.c -------- */

extern char *xmalloc(unsigned n);
extern char *xrealloc(char *p, unsigned n);
extern char *xstrdup(const char *s);
extern char *cat2(const char *a, const char *b);
extern char *cat3(const char *a, const char *b, const char *c);
extern int ci_streq(const char *a, const char *b);
extern int ci_strfind(const char *hay, const char *needle);
extern int mkpath(const char *dir);
extern int file_exists(const char *path);
extern long file_size(const char *path);
extern char *dirname_of(const char *path);
/* Unblock SIGALRM after a longjmp out of its own handler -- the block a
 * handler runs under is lifted by RETURNING from it, which a longjmp
 * never does, and whether setjmp/longjmp restore the mask is a libc
 * flavour question.  Without this the SECOND alarm() a process arms is
 * never delivered.  See the comment on the definition in util.c. */
extern void unblock_alarm(void);

extern void note(const char *fmt, ...);
extern void warnx2(const char *fmt, ...);

/* -------- md5 helper (md5.c wrapper, see md5.h for the engine) ---- */

extern int md5_file(const char *path, char hexout[33]);

/* -------- transaction journal (txn.c) --------
 *
 * /var/apkg/txn (under -R: the target's) records a transaction from
 * the moment every package is staged and verified until it is done, so
 * an interrupted one can be finished by `apkg recover`. */

struct txnpkg {
    int done;         /* pkgadd (and the record) / pkgrm finished      */
    int ow;           /* pkgadd with instance=overwrite                */
    int kspace;
    long size;        /* size of the staged file                       */
    char *name;
    char *version;
    char *pkginst;
    char *hash;       /* catalog md5/sha256 of the staged file, or "-" */
    char *staged;     /* staged datastream, or "-": a pkgrm (a remove,
                         or the other kernel package an install
                         replaces, C2-2 v5 §2.1)                      */
    char *role, *kline, *kabi, *pin, *loaderv, *sha256, *source;
                      /* kspace: the record's fields                  */
    char *reckey;     /* kspace: the record's file name (C2-2 v4)      */
};

struct txn {
    char verb[16];    /* install | upgrade | remove                    */
    char state[16];   /* installing | installed | built                */
    long started;
    int kspace;       /* the transaction changes kernel space          */
    struct txnpkg *p;
    int n;
};

extern int txn_exists(const struct conf *cf);
extern int txn_refuse_if_pending(const struct conf *cf);
extern int txn_save(const struct conf *cf, const struct txn *t);
extern int txn_load(const struct conf *cf, struct txn *t);
extern void txn_clear(const struct conf *cf);
extern void txn_free(struct txn *t);
/* one package into the journal; staged = the datastream pkgadd gets
 * ("-" for a remove), source = the record's `source` (kernel space) */
extern void txn_add(struct txn *t, const struct pkgent *e,
                    const char *pkginst, const char *staged, int ow,
                    const char *source);
extern void txn_init(struct txn *t, const char *verb);

#endif /* APKG_H */
