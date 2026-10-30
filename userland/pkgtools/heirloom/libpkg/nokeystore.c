/*
 * nokeystore.c - no-op replacements for security.c/keystore.c entry
 * points, for builds without OpenSSL (e.g. Amix/SVR4.0 target).
 * Any attempt to actually use signing (pkgtrans -g, https download)
 * fails cleanly.
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Jussi Alanärä.  A new Amix-port file, not derived from
 * the CDDL heirloom sources -- see heirloom/AMIX-PORT.md, "Licensing".  It
 * only satisfies the entry points keystore.h/pkglib.h declare.
 */
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include "pkglib.h"
#include "keystore.h"

void
sec_init(void)
{
}

int
open_keystore(PKG_ERR *err, char *keystore_file, char *app,
	keystore_passphrase_cb cb, long flags, keystore_handle_t *result)
{
	(void)keystore_file; (void)app; (void)cb; (void)flags; (void)result;
	pkgerr_add(err, PKGERR_UNSUP,
	    "package signing support not compiled in");
	return (1);
}

int
close_keystore(PKG_ERR *err, keystore_handle_t handle,
	keystore_passphrase_cb cb)
{
	(void)err; (void)handle; (void)cb;
	return (0);
}

/*
 * AMIX PORT additions: passphrase entry points from the removed
 * security.c that pkgtrans/pkgadd still reference on their signing
 * paths.  Signing is not supported in this build; the callback
 * reports failure if it is ever invoked.
 */
void
set_passphrase_prompt(char *prompt)
{
	(void)prompt;
}

void
set_passphrase_passarg(char *passarg)
{
	(void)passarg;
}

int
pkg_passphrase_cb(char *buf, int size, int rw, void *data)
{
	(void)buf; (void)size; (void)rw; (void)data;
	return (-1);
}

/*
 * AMIX PORT additions: the two pkgweb.c entry points still referenced
 * outside the removed web-install code paths.
 */

/* verbatim logic from the removed pkgweb.c (CDDL, same tree) */
boolean_t
path_valid(char *path)
{
	if (path == NULL) {
		return (B_FALSE);
	} else if (strlen(path) > PATH_MAX) {
		return (B_FALSE);
	} else if (strlen(path) >= 1) {
		return (B_TRUE);
	} else {
		/* path < 1 */
		return (B_FALSE);
	}
}

/* no web install support: there is never a proxy port to strip */
unsigned short
strip_port(char *proxy)
{
	(void)proxy;
	return (0);
}
