#!/bin/sh
# test-tell.sh -- host test of dhcpc's tell(), compiled from dhcpc.c itself:
# the daemon tells the foreground parent once, and lives on when that parent
# has stopped waiting (the pipe closed), with SIGPIPE back at its default.
#
#   sh userland/base/dhcpc/test-tell.sh [cc]     (default cc)
#
# DHCPC_C=<file> tests another copy of dhcpc.c (the one before the fix fails).
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
CC=${1:-cc}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-tell.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0
same() { # same <name> <want> <got>
	if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: want '$2', got '$3'"; fi
}

# the function as dhcpc.c has it, from its comment to its closing brace
awk '/^\/\* the foreground parent, told once/ { on = 1 } on { print } on && /^}/ { exit }' \
	"${DHCPC_C:-$here/dhcpc.c}" > "$T/tell.c"
same "tell() found in dhcpc.c" 1 "$(grep -c '^tell(c)' "$T/tell.c")"

cat > "$T/main.c" <<'EOF'
#include <signal.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/wait.h>
static int tellfd = -1;
#include "tell.c"
/* argv[1]: "gone" closes the read end first (the parent stopped waiting),
 * "there" keeps it and reads the byte */
int main(int argc, char **argv)
{
	int p[2], st;
	pid_t pid;
	char b = 0;
	void (*h)(int);

	if (argc < 2 || pipe(p) < 0)
		return 2;
	if ((pid = fork()) == 0) {
		close(p[0]);
		tellfd = p[1];
		sleep(1);
		tell('B');
		h = signal(SIGPIPE, SIG_DFL);
		printf("alive tellfd=%d sigpipe=%s\n", tellfd, h == SIG_DFL ? "default" : "changed");
		fflush(stdout);
		_exit(0);
	}
	close(p[1]);
	if (argv[1][0] == 'g')
		close(p[0]);
	else if (read(p[0], &b, 1) != 1)
		b = '-';
	waitpid(pid, &st, 0);
	if (b)
		printf("read %c\n", b);
	printf("child %s %d\n", WIFSIGNALED(st) ? "signal" : "exit",
	    WIFSIGNALED(st) ? WTERMSIG(st) : WEXITSTATUS(st));
	return 0;
}
EOF
if ! $CC -std=gnu89 -w -o "$T/t" "$T/main.c" 2> "$T/cc.err"; then
	cat "$T/cc.err"
	echo "test-tell: cannot compile"
	exit 1
fi
o=$("$T/t" gone)
same "parent gone: the daemon lives on" "alive tellfd=-1 sigpipe=default
child exit 0" "$o"
o=$("$T/t" there)
same "parent waiting: it reads B" "alive tellfd=-1 sigpipe=default
read B
child exit 0" "$o"

echo "test-tell: $pass passed, $fail failed ($CC)"
[ "$fail" -eq 0 ]
