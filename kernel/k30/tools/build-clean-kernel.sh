#!/bin/sh
# build-clean-kernel.sh [driver.c ...]   (runs ON the Amix box; pre-POSIX sh)
#
# Works around the intermittent ld kernel-image corruption (the "D245
# boot-breaker", amix-a4091 NOTES s18): ~70% of `make` runs shift one ~8KB
# block of the linked kernel by 8 bytes, randomly placed.  The CLEAN ld output
# is byte-deterministic; each corruption is unique.  So: rebuild (link-only)
# until a `sum` value RECURS -- the recurring value is the deterministic clean
# kernel.  Then relocunix is guaranteed good and `make install` is safe.
#
# Args: the driver source basenames in /usr/sys/amiga/alien to force-rebuild
# each round (default: a4091.c).  E.g.:  sh /tmp/build-clean-kernel.sh a4091.c z3660.c
#
# Usage:  sh /tmp/build-clean-kernel.sh [driver.c ...]
#         exit 0 = clean relocunix ready; 1 = could not stabilize.
set -u
if [ $# -eq 0 ]; then set a4091.c; fi
SRCS="$*"
OBJS=""
for f in $SRCS; do
  o=`echo $f | sed 's/\.c$/.o/'`
  OBJS="$OBJS $o"
done
cd /usr/sys || exit 2
: > /tmp/bck_seen.txt
n=1
while [ $n -le 25 ]; do
  cd /usr/sys/amiga/alien; rm -f $OBJS exp; touch $SRCS
  cd /usr/sys; rm -f relocunix unix OLDrelocunix amiga/exp amiga/config/unix.o master.d/exp
  make > /tmp/bck_build.log 2>&1
  s=`sum -r relocunix 2>/dev/null | awk '{print $1}'`
  if [ "X$s" = X ]; then
    # No relocunix. The boot-breaker ld corruption ALSO manifests as
    # "Unresolved Symbol(s)!" at the final `ld -o unix` (corrupted symtab in an
    # intermediate exp) -- this is INTERMITTENT, so retry like a bad sum.
    # Only a genuine deterministic build error (e.g. a compile error) aborts.
    if grep "Unresolved Symbol" /tmp/bck_build.log > /dev/null 2>&1; then
      echo "build $n: ld symtab corruption (Unresolved Symbol) -- retry"
      n=`expr $n + 1`
      continue
    fi
    tail -20 /tmp/bck_build.log
    echo "FAILED: make produced no relocunix (build error, see /tmp/bck_build.log)"
    exit 1
  fi
  echo "build $n: sum=$s"
  if grep "^$s\$" /tmp/bck_seen.txt > /dev/null 2>&1; then
    # sum reproduced => deterministic clean output. Confirm symtab too.
    /root/checkunix relocunix > /tmp/bck_chk.log 2>&1
    if [ $? -ne 0 ]; then
      cat /tmp/bck_chk.log
      echo "FAILED: sum recurred but checkunix reports a corrupt symtab"
      exit 1
    fi
    echo "STABLE after $n builds: clean relocunix (sum=$s)"
    cat /tmp/bck_chk.log
    exit 0
  fi
  echo "$s" >> /tmp/bck_seen.txt
  n=`expr $n + 1`
done
echo "FAILED: relocunix did not stabilize in 25 builds"
exit 1
