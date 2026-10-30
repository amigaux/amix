/*
 * dns-driver.c - test vehicle for apkg's stub resolver (dns.c).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
 *
 * NOT shipped and not part of apkg: this links dns.c + util.c and calls
 * the resolver directly.
 *
 * WHY A DRIVER RATHER THAN ONLY END-TO-END apkg RUNS.  The resolver's
 * step (b) is reached only when the HOST DATABASE has said nothing, and
 * on a test machine gethostbyname() is whatever that machine's NSS says
 * -- which cannot be scripted from here.  The bench host this was
 * written on has a wildcard upstream that answers EVERY name, including
 * reserved .invalid ones, so a test that assumed "an invalid name does
 * not resolve" would have silently exercised nothing while passing.
 * The driver removes the variable: -D calls apkg_dns_query() directly,
 * so the fake nameserver is the only thing that can answer.  The
 * ordering rules (literal, then hosts, then DNS) are what the
 * end-to-end apkg tests cover, using names every machine agrees about.
 *
 * usage: dns-driver [-v] [-D] [-t secs] [-r n] -s <ip[:port]> ... <host>
 *   -D  query the nameservers only (skip literal + host database)
 *   -v  apkg's -v: the resolver prints what it did and how
 * Prints "resolved <host> <ip>" and exits 0, or a message and exits 1.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../apkg.h"

/* normally main.c's; the driver links neither main.c nor the rest */
int opt_dryrun = 0;
int opt_force = 0;
int opt_verbose = 0;

static void usage(void)
{
    fprintf(stderr,
            "usage: dns-driver [-v] [-D] [-t secs] [-r n] "
            "[-s ip[:port]]... <host>\n");
    exit(2);
}

int main(int argc, char **argv)
{
    struct dnsopts d;
    char *servers[APKG_MAX_NAMESERVERS];
    unsigned long addr;
    char ip[16];
    const char *host;
    int dns_only;
    int i;

    d.servers = servers;
    d.nservers = 0;
    d.timeout = APKG_DEF_DNSTIMEO;
    d.retries = APKG_DEF_DNSRETRIES;
    dns_only = 0;
    host = NULL;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0) {
            opt_verbose = 1;
        } else if (strcmp(argv[i], "-D") == 0) {
            dns_only = 1;
        } else if (strcmp(argv[i], "-s") == 0 && i + 1 < argc) {
            if (d.nservers >= APKG_MAX_NAMESERVERS)
                usage();
            servers[d.nservers++] = argv[++i];
        } else if (strcmp(argv[i], "-t") == 0 && i + 1 < argc) {
            d.timeout = atol(argv[++i]);
        } else if (strcmp(argv[i], "-r") == 0 && i + 1 < argc) {
            d.retries = atoi(argv[++i]);
        } else if (argv[i][0] == '-') {
            usage();
        } else if (host == NULL) {
            host = argv[i];
        } else {
            usage();
        }
    }
    if (host == NULL)
        usage();

    if (dns_only)
        i = apkg_dns_query(host, &d, &addr);
    else
        i = apkg_resolve(host, &d, APKG_DEF_CONNTIMEO, &addr);
    if (i != 0) {
        fprintf(stderr, "dns-driver: %s not resolved\n", host);
        return 1;
    }
    apkg_ipv4_str(addr, ip);
    printf("resolved %s %s\n", host, ip);
    return 0;
}
