/*
 * kmedia.c -- the media writer of the host kbootset (docs/plan/stage-2.md
 * S2-04): mkstore's engine (tools/mkstore.c: disk stores, the floppy pair,
 * the CD tree), compiled in under another name, so media built by kbootset
 * and the test tool share one implementation.  kbootset composes and gates
 * the generation and hands it over as a mkstore spec.  Host only.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#define main mkstore_main
#include "../tools/mkstore.c"
