/*
 * version.c - build identity for libacompat.
 *
 * Copyright (c) 2026 Jussi Alanärä.  BSD-2-Clause; see LICENSE.
 *
 * A smoke test that says "libacompat works" is worth very little if it cannot
 * say WHICH libacompat.  The bench box keeps whatever was pushed last; a test
 * binary linked against a stale archive passes just as happily as one linked
 * against the archive under test.  So the version string is compiled in and
 * printed by the on-box test, which turns "it works" into "this build works".
 *
 * AMIX_COMPAT_VERSION is supplied by the build script (-D), not edited here,
 * so the recipe's version and the binary's version cannot disagree.
 */

#include "amixcompat.h"

#ifndef AMIX_COMPAT_VERSION
#define AMIX_COMPAT_VERSION "unknown"
#endif

static const char version[] = "libacompat " AMIX_COMPAT_VERSION;

const char *
amix_compat_version(void)
{
	return (version);
}
