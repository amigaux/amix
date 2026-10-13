# pin.sh -- which less tarball this recipe builds from, and nothing else.
# Sourced, never executed.  One URL, one sha256 (recipes/common/fetch.sh's rule).
#
# ---------------------------------------------------------------------------
# WHY 704
#
# registry/less.yaml and ROADMAP D5: less 704 (2026) is the clearest case that
# the naive "oldest version wins" heuristic is wrong.  It STILL supports SVR4
# regcmp/libgen and the BSD termcap API, STILL needs no config.sub, and has no
# gnulib dependency -- so taking the 2026 release costs nothing and gains 20
# years of fixes over the archived less 290.
#
# WHAT MADE IT ACTUALLY BUILD (see build.sh + patches/):
#   - REGEX = the SVR4 regcmp backend (libgen), selected by putting
#     -L<sysroot>/usr/ccs/lib on the configure LDFLAGS so AC_SEARCH_LIBS finds
#     regcmp in -lgen.  patches/02 fixes less's own stale regcmp/regex prototypes
#     (they were fixed-arg; SVR4's are variadic in <libgen.h>).
#   - TERMINAL = the BSD termcap API via -lcurses (D2; libcurses exports it and,
#     on SVR4, tgetent reads the terminfo database).  Built -DUSE_TERMCAP to take
#     the termcap path and skip the SVR4 <term.h>, whose TERMINAL struct needs a
#     `struct termio' that <termios.h>'s VINTR suppresses.
#   - THREE header gaps a strict-ANSI SVR4 opens: no ssize_t, stale regcmp
#     protos, and a clutch of __STDC__-gated / header-less functions (fileno,
#     popen, kill, fchmod, strdup, and the termcap calls).  patches/01-03.
#   - HAVE_STAT seeded yes: SVR4 `stat' is an inline wrapper over _xstat, so the
#     autoconf symbol link-test fails though stat works -- and without HAVE_STAT
#     less skips <sys/stat.h> and struct stat comes out incomplete.
#
# ---------------------------------------------------------------------------
# WHY THIS URL / SCHEME
#
# www.greenwoodsoftware.com/less is upstream's own site (less is not on GNU's
# mirrors).  As always the sha256 is the trust anchor, not the transport.
#
# Verified reachable 2026-08-30: https://www.greenwoodsoftware.com/less/less-704.tar.gz
# is 996650 bytes with the sha256 below.

LESS_VERSION=704
LESS_URL=https://www.greenwoodsoftware.com/less/less-704.tar.gz
LESS_SHA256=20a0b0a2bb2525fa53c7eee9beb854b4c9cf172eabb209af7020743547bfe9fb
LESS_SIZE=996650
