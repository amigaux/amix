/*
 * knode.h -- the sd disk nodes of a four-card kernel (C4-1 §2.4, C2-4 §14).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef KNODE_H
#define KNODE_H

/* kb_nodes' results */
#define KB_ND_TWO	0	/* no four-card kernel installed: core's nodes stand */
#define KB_ND_COMPLETE	1	/* the four-card set is there and registered */
#define KB_ND_MISSING	2	/* check: nodes missing or wrong, d1 nodes left, or unregistered */
#define KB_ND_MADE	3	/* make: nodes made or removed, or registered */
#define KB_ND_FAIL	(-1)	/* make: a node or the registration failed */

/* the four-card set under ROOT: checked (make 0) or made (make 1); one
 * line for a person in msg (300 bytes), without "kbootset: " */
int kb_nodes(const char *root, int make, char *msg);

#endif
