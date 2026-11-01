#!/bin/sh
# modadmin.sh -- modadmin's full status (-q, -Q, -S) as core/series ships
# it, built on the host with the six system calls stubbed: a module the
# core reports locked (unload=never, patch 0016) reads "Unload Delay: never
# (locked)", one declaring unload=allowed its delay in seconds (patch 0047).
# The driver includes what modadmin.c does, so both see one struct layout.
# Run from the repository root.
set -e
B=${B:-build}
T=$B/modadmin
rm -rf "${T:?}" && mkdir -p $T
sh tools/stagecore.sh $T/core
cat > $T/drv.c <<'C'
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/param.h>
#include "sys/mod.h"
#include "sys/ksym.h"
void full();
int modload() { return -1; }
int moduload() { return -1; }
int modpath() { return -1; }
int modstat() { return -1; }
int modadm() { return -1; }
int getksym() { return -1; }
static void
one(name, flags)
	char *name;
	int flags;
{
	struct modstatus st;

	memset(&st, 0, sizeof st);
	strcpy(st.ms_name, name);
	st.ms_unload_delay = 60;
	st.ms_flags = flags;
	full(&st);
}
int
main()
{
	one("pinned", MS_LOCKED | MS_CAND);
	one("allowed", MS_CAND);
	return 0;
}
C
${HOSTCC:-cc} -std=gnu89 -w -I$T/core/include -Dmain=modadmin_main -c -o $T/modadmin.o $T/core/modadmin.c
${HOSTCC:-cc} -std=gnu89 -w -I$T/core/include -c -o $T/drv.o $T/drv.c
${HOSTCC:-cc} -o $T/t $T/modadmin.o $T/drv.o
$T/t > $T/out
# the Unload Delay line after each Module Name line
awk -F'\t' '/^Module Name:/ { n = $NF } /^Unload Delay:/ { print n ": " $NF }' $T/out > $T/got
printf 'pinned: never (locked)\nallowed: 60 seconds\n' > $T/want
cmp -s $T/want $T/got || { echo "modadmin: got" >&2; cat $T/got >&2; exit 1; }
grep -q '^Flags:			locked candidate$' $T/out
echo "modadmin: a locked module's delay reads never (locked), an unloadable one's 60 seconds"
