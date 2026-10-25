/*
 * sha256-driver.c - test vehicle for apkg's sha256_file() (kspace.c over
 * the amix-dlm loader/common SHA-256).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
 *
 * NOT shipped and not part of apkg: it links every apkg source but
 * main.c and prints, for each file argument, "<64 hex>  <file>" -- the
 * sha256sum(1) format, so run-tests.sh compares the two byte for byte
 * and checks the FIPS 180-4 vectors.  Exit 1 when a file is unreadable.
 */

#include <stdio.h>

#include "../apkg.h"

int opt_dryrun = 0;
int opt_force = 0;
int opt_verbose = 0;

int main(int argc, char **argv)
{
    char hex[65];
    int i;
    int rc;

    rc = 0;
    for (i = 1; i < argc; i++) {
        if (sha256_file(argv[i], hex) != 0) {
            fprintf(stderr, "sha256-driver: cannot read %s\n", argv[i]);
            rc = 1;
            continue;
        }
        printf("%s  %s\n", hex, argv[i]);
    }
    return rc;
}
