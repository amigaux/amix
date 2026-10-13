/*
 * amixcompat.c - target-only stubs for linking apkg on Amix (SVR4.0).
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * Compiled ONLY into the m68k/Amix build (see Makefile).  The static
 * libsocket.a shipped with Amix references syslog() from its internal
 * error paths, but the Amix libc does not export it, so GNU ld
 * refuses to close the link.  apkg never configures syslog and never
 * wants socket-library chatter in a system log it cannot see, so a
 * no-op satisfies the reference safely.
 */

void syslog(int priority, const char *message, ...)
{
    (void)priority;
    (void)message;
}
