/*
 * nokeystore.c - no-op replacements for security.c/keystore.c entry
 * points, for builds without OpenSSL (e.g. Amix/SVR4.0 target).
 * Any attempt to actually use signing (pkgtrans -g, https download)
 * fails cleanly.
 */
#include <stdio.h>
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
