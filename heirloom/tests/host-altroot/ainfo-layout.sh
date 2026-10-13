#!/bin/sh
#
# ainfo-layout.sh - print the `struct ainfo` layout for BOTH the host
# and the m68k target, in particular the padding between the end of
# `group[]` and `major`.
#
# Why this exists: item 0 (`pkgadd -R` averify SIGSEGV) once turned on
# an *inferred* claim that m68k had zero padding there while the host
# had two zero bytes - i.e. a structural asymmetry that would make the
# bug host-unreproducible by construction.  Measuring it refuted that:
# BOTH are PAD=2.  Keep this runnable so the next round cannot re-derive
# the same wrong inference.
#
# The target side asks the COMPILER (offsetof emitted as initialized
# data, read back out of the .s) rather than running anything, so no
# box and no working m68k runtime are needed.
#
CROSS="${CROSS:-$HOME/opt/amix-cross/bin/m68k-cbm-sysv4-gcc}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' 0

cat > "$W/probe.c" <<'EOF'
#include <sys/types.h>
#include <stddef.h>
#define ATRSIZ 64
struct ainfo {
	char	*local;
	mode_t	mode;
	char	owner[ATRSIZ+1];
	char	group[ATRSIZ+1];
	major_t	major;
	minor_t	minor;
};
unsigned long probe[] = {
	(unsigned long)sizeof(struct ainfo),
	(unsigned long)offsetof(struct ainfo, owner),
	(unsigned long)offsetof(struct ainfo, group),
	(unsigned long)offsetof(struct ainfo, major),
	(unsigned long)offsetof(struct ainfo, minor),
	(unsigned long)(offsetof(struct ainfo, major)
	    - (offsetof(struct ainfo, group) + ATRSIZ + 1))
};
EOF

echo "fields: sizeof owner group major minor PAD"

# ---- host (needs the typedefs heirloom supplies on non-SVR4) --------
cat > "$W/host.c" <<'EOF'
#include <stdio.h>
#include <stddef.h>
#include <sys/types.h>
#define ATRSIZ 64
typedef dev_t major_t; typedef dev_t minor_t;
struct ainfo { char *local; mode_t mode; char owner[ATRSIZ+1];
	char group[ATRSIZ+1]; major_t major; minor_t minor; };
int main(void) {
	printf("host              : %zu %zu %zu %zu %zu PAD=%zu\n",
	    sizeof(struct ainfo), offsetof(struct ainfo, owner),
	    offsetof(struct ainfo, group), offsetof(struct ainfo, major),
	    offsetof(struct ainfo, minor),
	    offsetof(struct ainfo, major)
	        - (offsetof(struct ainfo, group) + ATRSIZ + 1));
	return 0;
}
EOF
gcc -std=gnu89 "$W/host.c" -o "$W/host" && "$W/host"

# ---- m68k target ---------------------------------------------------
if [ ! -x "$CROSS" ]; then
	echo "m68k: SKIP (no cross compiler at $CROSS; set CROSS=)"
	exit 0
fi
for flags in "-O" "-O2" "-O0" "" "-O2 -fpack-struct"; do
	if "$CROSS" $flags -S "$W/probe.c" -o "$W/probe.s" 2>/dev/null; then
		vals=$(grep -E "^[[:space:]]*\.long" "$W/probe.s" \
			| sed 's/.*\.long[ \t]*//' | tr '\n' ' ')
		set -- $vals
		printf "m68k %-14s: %s %s %s %s %s PAD=%s\n" \
			"[${flags:-bare}]" "$1" "$2" "$3" "$4" "$5" "$6"
	else
		echo "m68k [${flags:-bare}]: COMPILE FAIL"
	fi
done

echo
echo "Expected (2026-07-19): host PAD=2, m68k PAD=2 for every flag set"
echo "except -fpack-struct (PAD=0), which the tree does NOT use"
echo "(mk.config.amix: CFLAGS=-O).  Same layout on both -> no"
echo "structural asymmetry."
