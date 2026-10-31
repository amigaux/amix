/* amix-xlibc.h -- the C library's declarations for X11R6.3's 1990s sources.
 * Force-included into every X compile (build.sh), before amix-decls.h: many
 * files call malloc, sprintf, read, signal or waitpid without including the
 * header that declares them, which gcc 14 refuses (implicit declaration). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <ctype.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <grp.h>
/* in libc.so.1, declared by no AMIX header (SVR4 STREAMS ptys, xterm) */
extern int grantpt(int);
extern int unlockpt(int);
extern char *ptsname(int);
/* libcurses' termcap entry point (<term.h> declares it, but is not included) */
extern int tgetent(char *, char *);
