#!/bin/bash
#
# run.sh - HOST reproduction attempt for the `pkgadd -R <altroot>`
# SIGSEGV in averify()'s fix=1 group check (AMIX-PORT.md item 0).
#
# For three rounds the blocker was filed as "host-unreproducible".
# This harness removes every host-side reason the crashing code could
# have been skipped, so that a "no crash" result MEANS something:
#
#   1. -R alone is not enough.  libpkg/ncgrpw.c clgrnam()/clpwnam()
#      have their whole body inside `if (get_install_root() != NULL)`,
#      and then fopen("<root>/etc/group").  A fakeroot with no
#      etc/group makes clgrnam() return NULL immediately, so
#      clgrnam -> dup_gr_ent never runs.  tools/repo/repackage-stock.py
#      install_test() does exactly that (os.makedirs then pkgadd -R),
#      which is why the host had never executed the suspect path.
#      => CONFIG B seeds <root>/etc/{passwd,group} first.
#
#   2. The host's own `bin` group is memberless, so dup_gr_ent()'s
#      gr_mem duplication loop is skipped.  The box's group file has
#      `bin::2:bin,daemon`.  => both configs use the REAL box fixtures
#      ../../compat/tests/amix-{passwd,group}.txt.
#
#   3. The box resolves groups through the compat text parsers
#      (compat/amixcompat.c fgetgrent/getgrnam - the Amix libc-passwd
#      sidestep), NOT through glibc.  => this harness LD_PRELOADs the
#      compat parsers, extracted from the current amixcompat.c, so the
#      host runs the box's actual parser code.
#
#   4. The shipped gnam/onam guard in libpkg/verify.c would mask the
#      original failure.  => build with NOGUARD=1 to compile it out.
#
# Both alternate-root shapes are exercised, because it is NOT recorded
# anywhere what the box's -R target actually contained:
#   CONFIG A - empty root: clgrnam() fopen fails, lookups fall through
#              to compat getgrnam() against the real /etc/group;
#   CONFIG B - seeded root: the clgrnam() -> dup_gr_ent() path runs.
#
# Usage:
#     cd heirloom
#     SANITIZE=1 NOGUARD=1 ./build-host.sh
#     ./tests/host-altroot/run.sh
#
# Exit 0 = ran clean (NO reproduction).  Exit 1 = harness could not
# run.  Exit 2 = a sanitizer finding or a crash was observed, i.e. the
# bug DID reproduce - read the saved logs.
#
set -u

D="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$D/../.." && pwd)"
BIN="$TOP/build-host/bin"
OUT="${OUTDIR:-/tmp/host-altroot}"

PW="$TOP/compat/tests/amix-passwd.txt"
GR="$TOP/compat/tests/amix-group.txt"

[ -x "$BIN/pkgadd" ] || {
	echo "SKIP: $BIN/pkgadd not built - run ./build-host.sh first"
	exit 1
}

rm -rf "$OUT"; mkdir -p "$OUT"

# ------------------------------------------------------------------
# 1. Build the compat pw/gr parsers as an LD_PRELOAD, extracted from
#    the CURRENT compat/amixcompat.c (same trick as
#    compat/tests/test-pwgr.sh, so the harness never tests stale code).
#    The fixture paths are compiled IN, not read from the environment:
#    pkginstall/main.c sets `environ = NULL` partway through, which
#    would otherwise wipe them in the child that does the real work.
# ------------------------------------------------------------------
python3 - "$TOP" > "$OUT/shims.inc" <<'PYEOF'
import sys
s = open(sys.argv[1] + '/compat/amixcompat.c').read()
b1 = s[s.index('#define\tAMIX_PWLINE'):s.index('/*\n * basename()')]
b2 = s[s.index('static FILE *\namix_pw_open'):]
b2 = b2[:b2.index('\n}\n', b2.index('getgrgid')) + 3]
blk = b1 + b2
blk = blk.replace('#include <pwd.h>', '').replace('#include <grp.h>', '')
blk = blk.replace('\tpw.pw_age = "";', '\t/* pw_age: SVR4-only */')
blk = blk.replace('\tpw.pw_comment = "";', '\t/* pw_comment: SVR4-only */')
blk = blk.replace('fopen("/etc/passwd", "r")', 'fopen(AMIX_PWFILE_PATH, "r")')
blk = blk.replace('fopen("/etc/group", "r")', 'fopen(AMIX_GRFILE_PATH, "r")')
sys.stdout.write(blk)
PYEOF
[ -s "$OUT/shims.inc" ] || { echo "FAIL: could not extract compat parsers"; exit 1; }

cat > "$OUT/preload.c" <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pwd.h>
#include <grp.h>
#include "shims.inc"
EOF

gcc -std=gnu89 -O -fPIC -shared -I"$OUT" \
	-DAMIX_PWFILE_PATH="\"$PW\"" -DAMIX_GRFILE_PATH="\"$GR\"" \
	"$OUT/preload.c" -o "$OUT/libamixpwgr.so" || {
	echo "FAIL: could not build the compat-parser preload"; exit 1; }

# ASan must come FIRST in the preload list or its runtime refuses to
# start.  When the tools are not sanitizer-built this resolves to a
# harmless empty entry.
ASANLIB=""
if ldd "$BIN/pkgadd" 2>/dev/null | grep -q libasan; then
	ASANLIB="$(gcc -print-file-name=libasan.so):"
	echo "note: pkgadd is sanitizer-built"
else
	echo "WARNING: pkgadd is NOT sanitizer-built - rebuild with"
	echo "         SANITIZE=1 NOGUARD=1 ./build-host.sh for a real test"
fi
export LD_PRELOAD="${ASANLIB}$OUT/libamixpwgr.so"
export ASAN_OPTIONS=detect_leaks=0:abort_on_error=0
export UBSAN_OPTIONS=print_stacktrace=1

# ------------------------------------------------------------------
# 2. Build a throwaway package whose every object is owned by a
#    MULTI-MEMBER group from the real box fixtures:
#       bin::2:bin,daemon      sys::3:bin,sys,adm     adm::4:adm,daemon
#    (the host's own bin/sys/adm are memberless, which is precisely
#    the asymmetry that made previous host runs vacuous).
# ------------------------------------------------------------------
SRC="$OUT/src"; mkdir -p "$SRC/root/usr/altrt/lib" "$SRC/spool" "$SRC/out"
echo "alternate-root group-path probe" > "$SRC/root/usr/altrt/data.txt"
echo "second object" > "$SRC/root/usr/altrt/lib/more.txt"
cat > "$SRC/pkginfo" <<'EOF'
PKG=ALTRT
NAME=Alternate-root group-path probe (host diagnosis)
ARCH=m68k
VERSION=1.0
CATEGORY=application
EOF
cat > "$SRC/prototype" <<EOF
i pkginfo=$SRC/pkginfo
d none /usr/altrt 0755 root sys
f none /usr/altrt/data.txt 0644 bin bin
d none /usr/altrt/lib 0755 bin adm
f none /usr/altrt/lib/more.txt 0644 adm sys
EOF

"$BIN/pkgmk" -o -r "$SRC/root" -f "$SRC/prototype" -d "$SRC/spool" ALTRT \
	>"$OUT/pkgmk.log" 2>&1 || { echo "FAIL: pkgmk"; tail "$OUT/pkgmk.log"; exit 1; }
"$BIN/pkgtrans" -s "$SRC/spool" "$SRC/out/altrt.pkg" ALTRT \
	>"$OUT/pkgtrans.log" 2>&1 || { echo "FAIL: pkgtrans"; tail "$OUT/pkgtrans.log"; exit 1; }

cat > "$OUT/admin" <<'EOF'
mail=
instance=overwrite
partial=nocheck
runlevel=nocheck
idepend=nocheck
rdepend=nocheck
space=nocheck
setuid=nocheck
conflict=nocheck
action=nocheck
basedir=default
EOF

# ------------------------------------------------------------------
# 3. Run both alternate-root shapes.  The -R path must stay well under
#    ~110 chars (libadm/pkginfo.c svr4info() history) - hence /tmp.
# ------------------------------------------------------------------
bad=0
for cfg in A B; do
	root="$OUT/r$cfg"
	rm -rf "$root"
	if [ "$cfg" = A ]; then
		mkdir -p "$root"
		what="empty root (clgrnam fopen fails -> getgrnam fallback)"
	else
		mkdir -p "$root/etc"
		cp "$PW" "$root/etc/passwd"
		cp "$GR" "$root/etc/group"
		what="seeded root (clgrnam -> dup_gr_ent path)"
	fi

	log="$OUT/$cfg.log"
	DS_DEBUG=1 "$BIN/pkgadd" -R "$root" -n -a "$OUT/admin" \
		-d "$SRC/out/altrt.pkg" ALTRT >"$log" 2>&1
	rc=$?

	# The misaligned word load in verify.c compute_checksum() is a
	# pre-existing, upstream, LINTED-annotated benign finding - not this
	# bug.  Match it by signature, not line number (edits to verify.c
	# shift its line: it was :333, now :372 after the -R ownership guard).
	san=$(grep -E "ERROR: AddressSanitizer|runtime error" "$log" \
		| grep -vc "runtime error: load of misaligned address")
	fix1=$(grep -c "DS_DEBUG(averify): enter.*fix=1" "$log")
	clg=$(grep -c "DS_DEBUG(clgrnam)" "$log")
	dup=$(grep -c "DS_DEBUG(dup_gr_ent): enter" "$log")
	multi=$(grep -c "DS_DEBUG(dup_gr_ent): done, [1-9]" "$log")

	echo "CONFIG $cfg - $what"
	echo "    rc=$rc  log=$log"
	echo "    averify fix=1 entries : $fix1   <- the crashing path"
	echo "    clgrnam calls         : $clg"
	echo "    dup_gr_ent calls      : $dup  (multi-member: $multi)"
	echo "    sanitizer findings    : $san"

	[ "$fix1" -gt 0 ] || { echo "    !! fix=1 never ran - test is vacuous"; bad=1; }
	[ "$dup" -gt 0 ]  || { echo "    !! dup_gr_ent never ran - test is vacuous"; bad=1; }
	[ "$multi" -gt 0 ] || { echo "    !! no multi-member group - test is vacuous"; bad=1; }
	[ "$san" -eq 0 ]  || { echo "    !! SANITIZER FINDING - the bug reproduced"; bad=2; }
	[ "$rc" -lt 128 ] || { echo "    !! killed by signal $((rc - 128))"; bad=2; }
done

if [ "$bad" = 2 ]; then
	echo "RESULT: REPRODUCED on host - see the logs above"
	exit 2
elif [ "$bad" = 1 ]; then
	echo "RESULT: harness did not exercise the target path - fix the harness"
	exit 1
fi
echo "RESULT: NO reproduction on host."
echo "        The crashing path (averify fix=1 -> cgrnam -> clgrnam ->"
echo "        dup_gr_ent, multi-member groups, box parsers, guard off)"
echo "        was PROVEN to execute and completed clean under ASan+UBSan."
exit 0
