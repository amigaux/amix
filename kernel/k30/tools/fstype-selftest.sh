#!/bin/bash
# fstype-selftest.sh -- host-side self-test for tools/fstype-lib.sh: the fstypes.conf
# parser (fstype_parse: path resolution incl. $CDFS/, the md5= provenance pin) and the
# on-box fstype integration (fstype_gen_onbox_patch / fstype_verify_onbox_output /
# fstype_stage_onbox), an arm where an earlier generator wrote blind and reported
# success.  Proves it WITHOUT an Amix box: the real generator emits the real script, and
# it is run by the real `sh` over throwaway fixture trees (FSPFX), with stub
# amixsh/amixsync standing in for the box so even fstype_stage_onbox runs end to end.
#
#   0. fstype_parse: the md5= pin (match / mismatch / malformed / unpinned), $CDFS/
#      resolution (unset -> refused, set -> resolved, object missing -> refused), and
#      /dev/null (build-cross-kernel.sh --no-fstypes) -> zero records with no CDFS.  When
#      CDFS is set, the LIVE fstypes.conf pin is checked against the object there;
#      without CDFS that arm is skipped with a note.
#   1. the generator emits valid sh, honours FSPFX, and never prints "patched" from a path
#      that has not verified the edit.
#   2. FRESH tree -> full integration; the vfssw ROW is asserted to be INSIDE the vfssw[]
#      span (not merely present in the file, not in fmodsw[]), the extern above it, the
#      OPT_SUBEXP entry directly under its anchor, and $(FSLIB) on the final ld line.
#   3. IDEMPOTENT -- a second run reports "ok" everywhere and leaves every file BYTE-IDENTICAL.
#   4. HALF-PATCH (extern present, row absent -- what a close-brace drift leaves behind) is
#      DETECTED, reported, and REPAIRED.  Mutation-checked: the old name-wide `grep <init>`
#      guard is shown to match that tree, i.e. it really would have skipped it forever.
#   5. WRONG-TABLE drift (vfssw's close brace unindented while a later table still has one)
#      is REFUSED BEFORE ANY WRITE, and filesys.c is byte-unchanged.  Mutation-checked: the
#      bare pre-fix ed body is run on the same fixture and shown to land the row inside
#      fmodsw[] -- silently, exit 0.  That is the defect, reproduced, then refused.
#   6. a missing vfssw declaration anchor is refused, file unchanged.
#   7. ed's exit status is really consulted: the generated script is mutated so the ROW
#      address misses (the known failure mode -- the extern insert has already been
#      written by then), and the run must ABORT naming the half-patch instead of printing
#      "FSC patched".  A normal run afterwards repairs the tree.
#   8. fstype_verify_onbox_output refuses a missing FSTYPE_OK, a missing FSTYPE_DONE and an
#      FSTYPE_ABORT -- the host half matters because the remote-shell helper's single exit
#      status cannot say which record failed.
#   9. fstype_stage_onbox end-to-end through the stubs: green tree sets GATE_FS; a
#      wrong-table tree exits 2 instead of gating a kernel without the filesystem; a bare
#      CROSS_PREFIX is resolved on PATH.
#  10. `bash -n` for the lib, this test and build-cross-kernel.sh, and build-cross-kernel.sh
#      is asserted to source the lib, call fstype_parse and keep --no-fstypes.
#
# Optional inputs: CDFS (a built amix-cdfs checkout: enables the live-pin arm) and
# AMIX_SYSTEM (an amix-system checkout: arm 2b runs the integration on the stock
# usr/sys/master.d/filesys.c).  Without them those arms print a skip note.
# Exit 0 = all green; non-zero on the first failure.
set -euo pipefail

KT="$(cd "$(dirname "$0")/.." && pwd)"
LIVE_CDFS="${CDFS:-}"
. "$KT/tools/fstype-lib.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "SELFTEST FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
TAB="$(printf '\t')"

NM=cdfs IT=cdfsinit

# ---------------------------------------------------------------- fixture material ----
# A faithful pristine filesys.c: vfssw[] closed by a TAB-indented `};`, fmodsw[] right
# below it closed at column 0 -- the real stock shape (usr/sys/master.d/filesys.c).
synth_filesys() {
  cat <<EOF
#include "sys/conf.h"
#include "sys/vfs.h"

extern struct vfsops vfs_strayops;
extern int s5init(),ufsinit(),nfsinit(),bfinit(),prinit();
struct vfssw vfssw[] = {
${TAB}{ "BADVFS",${TAB}0,${TAB}&vfs_strayops,${TAB}0},
${TAB}{ NAMES5,${TAB}s5init,${TAB}${TAB}0,${TAB}0},
${TAB}{ NAMEUFS,${TAB}ufsinit,${TAB}0,${TAB}0},
${TAB}{ NAMEBF,${TAB}bfinit,${TAB}${TAB}0,${TAB}0},
${TAB}{ NAMEPR,${TAB}prinit,${TAB}${TAB}0,${TAB}0},
${TAB}{ NAMENFS,${TAB}nfsinit,${TAB}0,${TAB}0},
${TAB}};

int nfstype = (sizeof(vfssw)/sizeof(vfssw[0]));
int nullflag[1] = {0,};
int oldflag[1] = {D_OLD,};

extern struct streamtab modtab;
extern struct streamtab ldtrinfo;

struct fmodsw fmodsw[] = {
/* name         streamtab       flags */
{ "module",${TAB}&modtab,${TAB}oldflag, },
{ "ldterm",${TAB}&ldtrinfo,${TAB}nullflag, },
};

int fmodcnt = (sizeof(fmodsw)/sizeof(fmodsw[0]));
EOF
}

synth_fsmakefile() {
  cat <<EOF
#
#${TAB}You may delete unused filesystem types from this list
#

OPT_SUBEXP =${TAB}bfs/exp \\
${TAB}${TAB}s5/exp \\
${TAB}${TAB}ufs/exp \\
${TAB}${TAB}rfs/exp

exp:    fs.exp \$(OPT_SUBEXP)
${TAB}ld -r -o exp fs.exp \$(OPT_SUBEXP)
EOF
}

synth_topmakefile() {
  cat <<EOF
OBJS = amiga/exp master.d/exp fs/exp

unix:${TAB}\$(OBJS)
${TAB}ld -o \$@ \$(LINKARGS) \$(OBJS) \$(PLATFORM)/config/\$(KERNEL).o
EOF
}

# mkroot <name> -> path to a fresh fixture /usr/sys tree
mkroot() {
  local r="$TMP/$1"
  mkdir -p "$r/usr/sys/fs" "$r/usr/sys/master.d" "$r/tmp"
  synth_filesys    > "$r/usr/sys/master.d/filesys.c"
  synth_fsmakefile > "$r/usr/sys/fs/Makefile"
  synth_topmakefile> "$r/usr/sys/Makefile"
  echo "$r"
}

echo "== 0. fstype_parse exp-provenance pin and path resolution =="
# The conf path names no revision: an unvalidated object at the same path once poisoned
# kernels, which is why the pin exists.  Assert all four behaviors: a matching pin passes and
# says so, a mismatch REFUSES naming both md5s, a malformed pin REFUSES (a pin that can
# never match is a pin that silently stopped pinning), and an unpinned record still
# prints the staged object's identity so every build log records what went in.
PEXP="$TMP/pin-exp.o"; printf 'PROVENANCE-FIXTURE-EXP\n' > "$PEXP"
PMD5="$(md5sum "$PEXP" | awk '{print $1}')"
PBAD="00000000000000000000000000000000"
_parse() {  # <conf> -> RC + ROUT (fstype_parse exits on refusal, so subshell it)
  RC=0; ROUT="$( fstype_parse "$1" "$KT" 2>&1 )" || RC=$?
}
_parse_cdfs() {  # <conf> <CDFS value, or "" for unset> -> RC + ROUT
  RC=0; ROUT="$( if [ -n "$2" ]; then CDFS="$2"; else unset CDFS; fi
                 fstype_parse "$1" "$KT" 2>&1 )" || RC=$?
}
printf 'fstype pfx pfxinit %s 0 md5=%s\n' "$PEXP" "$PMD5" > "$TMP/pin-good.conf"
_parse "$TMP/pin-good.conf"
[ "$RC" -eq 0 ] || fail "provenance: matching pin refused (rc $RC): $ROUT"
case "$ROUT" in *"md5=$PMD5"*"(pin OK)"*) : ;; *) fail "provenance: no pin-OK identity line: $ROUT";; esac
ok "matching md5= pin passes and the identity line says (pin OK)"
printf 'fstype pfx pfxinit %s 0 md5=%s\n' "$PEXP" "$PBAD" > "$TMP/pin-bad.conf"
_parse "$TMP/pin-bad.conf"
[ "$RC" -eq 2 ] || fail "provenance: WRONG pin exited $RC, want 2: $ROUT"
case "$ROUT" in *"PROVENANCE MISMATCH"*) : ;; *) fail "provenance: no MISMATCH headline: $ROUT";; esac
case "$ROUT" in *"$PMD5"*) : ;; *) fail "provenance: refusal does not name the FOUND md5: $ROUT";; esac
case "$ROUT" in *"$PBAD"*) : ;; *) fail "provenance: refusal does not name the PINNED md5: $ROUT";; esac
ok "wrong md5= pin refused (rc 2), naming found AND pinned values"
printf 'fstype pfx pfxinit %s 0 md5=nothex\n' "$PEXP" > "$TMP/pin-malformed.conf"
_parse "$TMP/pin-malformed.conf"
[ "$RC" -eq 2 ] || fail "provenance: malformed pin exited $RC, want 2: $ROUT"
case "$ROUT" in *MALFORMED*) : ;; *) fail "provenance: malformed pin not diagnosed: $ROUT";; esac
ok "malformed md5= pin refused (rc 2) rather than silently un-pinning"
printf 'fstype pfx pfxinit %s 0\n' "$PEXP" > "$TMP/pin-none.conf"
_parse "$TMP/pin-none.conf"
[ "$RC" -eq 0 ] || fail "provenance: unpinned record refused (rc $RC): $ROUT"
case "$ROUT" in *"md5=$PMD5"*UNPINNED*) : ;; *) fail "provenance: unpinned record lacks the identity line: $ROUT";; esac
ok "unpinned record still prints the exp identity (always-record)"
# $CDFS/ resolution: the record names its object relative to the CDFS input.
mkdir -p "$TMP/cdfsfix/obj"; cp "$PEXP" "$TMP/cdfsfix/obj/pin-exp.o"
printf 'fstype pfx pfxinit $CDFS/obj/pin-exp.o 0 md5=%s\n' "$PMD5" > "$TMP/cdfs.conf"
_parse_cdfs "$TMP/cdfs.conf" ""
[ "$RC" -eq 2 ] || fail "\$CDFS record with CDFS unset exited $RC, want 2: $ROUT"
case "$ROUT" in *"CDFS is not set"*) : ;; *) fail "\$CDFS record with CDFS unset: refusal does not say so: $ROUT";; esac
ok "\$CDFS/ record with CDFS unset refused (rc 2), naming CDFS"
_parse_cdfs "$TMP/cdfs.conf" "$TMP/cdfsfix"
[ "$RC" -eq 0 ] || fail "\$CDFS record with CDFS set refused (rc $RC): $ROUT"
case "$ROUT" in *"exp<-$TMP/cdfsfix/obj/pin-exp.o"*"(pin OK)"*) : ;; *) fail "\$CDFS record not resolved under CDFS: $ROUT";; esac
_parse_cdfs "$TMP/cdfs.conf" "$TMP/cdfsfix/"
case "$ROUT" in *"exp<-$TMP/cdfsfix/obj/pin-exp.o"*"(pin OK)"*) : ;; *) fail "\$CDFS with a trailing slash not resolved cleanly: $ROUT";; esac
ok "\$CDFS/ record resolves under CDFS (trailing slash too) and the pin still applies"
mkdir -p "$TMP/cdfs-empty"
_parse_cdfs "$TMP/cdfs.conf" "$TMP/cdfs-empty"
[ "$RC" -eq 2 ] || fail "\$CDFS record with the object missing exited $RC, want 2: $ROUT"
case "$ROUT" in *"exp-source not found"*) : ;; *) fail "\$CDFS record with the object missing: no diagnosis: $ROUT";; esac
ok "\$CDFS/ record whose object is missing under CDFS refused (rc 2)"
# --no-fstypes: build-cross-kernel.sh passes /dev/null -- zero records, no CDFS needed.
_parse_cdfs /dev/null ""
[ "$RC" -eq 0 ] || fail "/dev/null (--no-fstypes) refused (rc $RC): $ROUT"
[ -z "$ROUT" ] || fail "/dev/null (--no-fstypes) produced records/output: $ROUT"
ok "/dev/null (--no-fstypes) -> zero records, rc 0, with CDFS unset"
# And the LIVE conf: the shipped pin must match the artifact actually in CDFS -- this
# turns every selftest run with CDFS set into a standing provenance check.  Without CDFS
# the live record must refuse cleanly, naming CDFS.
if [ -n "$LIVE_CDFS" ]; then
  _parse_cdfs "$KT/fstypes.conf" "$LIVE_CDFS"
  [ "$RC" -eq 0 ] || fail "provenance: the LIVE fstypes.conf pin does not match the artifact under CDFS=$LIVE_CDFS: $ROUT"
  case "$ROUT" in *"(pin OK)"*) : ;; *) fail "provenance: live conf carries no active pin: $ROUT";; esac
  ok "LIVE fstypes.conf pin matches the artifact under CDFS=$LIVE_CDFS (pin active)"
else
  echo "  note: CDFS is not set -- live-conf pin check skipped (set CDFS to a built amix-cdfs checkout to run it)"
  if grep -q '^[[:space:]]*fstype[[:space:]].*[[:space:]]\$CDFS/' "$KT/fstypes.conf"; then
    _parse_cdfs "$KT/fstypes.conf" ""
    [ "$RC" -eq 2 ] || fail "LIVE fstypes.conf without CDFS exited $RC, want 2: $ROUT"
    case "$ROUT" in *"CDFS is not set"*) : ;; *) fail "LIVE fstypes.conf without CDFS: refusal does not name CDFS: $ROUT";; esac
    ok "LIVE fstypes.conf without CDFS refuses cleanly (rc 2), naming CDFS"
  fi
fi

# the host's own reading of "is the row inside the vfssw[] table" -- deliberately written
# independently of the generated script's sed, so a shared bug cannot green both.
vfssw_span() {   # <filesys.c>
  awk '/^struct vfssw vfssw\[\] = \{/ { inv=1 } inv { print } inv && /^\t\};/ { exit }' "$1"
}
fmodsw_span() {  # <filesys.c>
  awk '/^struct fmodsw fmodsw\[\] = \{/ { inf=1 } inf { print } inf && /^\};/ { exit }' "$1"
}

# run <root> [script] -> rc in RC, combined output in ROUT
run() {
  local root="$1" scr="${2:-$TMP/gen.sh}"
  RC=0
  ROUT="$(FSPFX="$root/usr/sys" sh "$scr" 2>&1)" || RC=$?
}
expect_abort() {  # <label> <root> <phrase>
  local label="$1" root="$2" phrase="$3"
  run "$root"
  [ "$RC" -ne 0 ] || fail "$label: expected a non-zero exit, got 0 -- output: $ROUT"
  case "$ROUT" in *FSTYPE_ABORT*) : ;; *) fail "$label: no FSTYPE_ABORT in: $ROUT";; esac
  case "$ROUT" in *"$phrase"*) : ;; *) fail "$label: abort lacks '$phrase': $ROUT";; esac
  case "$ROUT" in *"FSC patched"*) fail "$label: printed 'FSC patched' on a refused run: $ROUT";; esac
  fstype_verify_onbox_output "$ROUT" 2>/dev/null && fail "$label: the host verifier ACCEPTED a refused run"
  ok "$label -> refused (rc $RC), '$phrase', host verifier refuses too"
}

FS_NAMES=("$NM"); FS_INITS=("$IT"); FS_EXPS=("$TMP/fake-exp"); FS_FLAGS=(0)
: > "$TMP/fake-exp"

echo "== 1. the generator emits valid sh and honours FSPFX =="
fstype_gen_onbox_patch "$TMP/gen.sh"
sh -n "$TMP/gen.sh" || fail "the generated script is not valid sh"
ok "generated script parses under $(readlink -f /bin/sh)"
grep -q 'FSPFX=${FSPFX:-/usr/sys}' "$TMP/gen.sh" \
  || fail "the generated script does not honour FSPFX (nothing could test it without a box)"
ok "FSPFX hook present, default /usr/sys"
# Every "patched" line must be preceded by an fsfail-guarded verify in the same arm; the
# behavioural tests below are the real proof, but a bare unconditional echo would mean the
# generator regressed to the old blind-write shape, so catch it structurally too.
[ "$(grep -c 'patched (' "$TMP/gen.sh")" -eq 3 ] || fail "expected exactly 3 'patched' announcements (FSM/FSC/TOPMK)"
[ "$(grep -c 'if \[ \$? -ne 0 \]; then fsfail' "$TMP/gen.sh")" -eq 4 ] \
  || fail "expected 4 ed exit-status checks (FSM, FSC extern, FSC row, TOPMK) -- an ed rc is being discarded again"
ok "3 'patched' announcements, 4 ed exit-status checks"

echo "== 2. FRESH tree: the row lands INSIDE vfssw[] =="
R="$(mkroot fresh)"
run "$R"
[ "$RC" -eq 0 ] || fail "fresh run exited $RC: $ROUT"
fstype_verify_onbox_output "$ROUT" || fail "host verifier refused a good run: $ROUT"
FSCF="$R/usr/sys/master.d/filesys.c"
vfssw_span "$FSCF" | grep -q "\"$NM\", $IT" || fail "the $NM row is NOT inside the vfssw[] span"
fmodsw_span "$FSCF" | grep -q "$NM" && fail "the $NM row landed inside fmodsw[]"
grep -q "^extern int $IT();" "$FSCF" || fail "the extern was not inserted"
[ "$(grep -n "^extern int $IT();" "$FSCF" | cut -d: -f1)" \
  -lt "$(grep -n '^struct vfssw vfssw\[\] = {' "$FSCF" | cut -d: -f1)" ] \
  || fail "the extern is not above the vfssw[] declaration"
sed -n '/^OPT_SUBEXP/{n;p;}' "$R/usr/sys/fs/Makefile" | grep -q "$NM/exp" \
  || fail "$NM/exp did not land directly under OPT_SUBEXP"
grep 'ld -o $@ $(LINKARGS)' "$R/usr/sys/Makefile" | grep -q 'FSLIB' \
  || fail "the final ld line does not carry \$(FSLIB)"
case "$ROUT" in *"FSM patched"*"FSC patched"*"TOPMK patched"*) : ;; *) fail "unexpected fresh output: $ROUT";; esac
ok "fresh tree integrated: row inside vfssw[], extern above it, OPT_SUBEXP + FSLIB hooked"

echo "== 2b. the same, on the REAL stock master.d/filesys.c =="
# The synthetic fixture above is written to the stock shape, but the shape is the whole
# point -- so when the stock tree is available (AMIX_SYSTEM), run the identical
# integration against a throwaway copy of the real file.  A drift in the stock layout (a
# table that stops closing with a TAB, an anchor that gains whitespace) then fails HERE
# rather than on the box.
REALFSC=""
c="${AMIX_SYSTEM:-}/usr/sys/master.d/filesys.c"
if [ -n "${AMIX_SYSTEM:-}" ] && [ -f "$c" ] && grep -q '^struct vfssw vfssw\[\] = {' "$c"; then
  REALFSC="$c"
fi
if [ -n "$REALFSC" ]; then
  R="$(mkroot real)"
  FSCF="$R/usr/sys/master.d/filesys.c"
  # pristine-ise: strip our own two lines in case the input is an already-integrated tree
  grep -v "^extern int $IT();" "$REALFSC" | grep -v "\"$NM\", $IT" > "$FSCF"
  chmod u+w "$FSCF"
  vfssw_span "$FSCF" | grep -q "$IT" && fail "could not pristine-ise $REALFSC (row still in vfssw[])"
  run "$R"
  [ "$RC" -eq 0 ] || fail "real stock filesys.c: run exited $RC: $ROUT"
  fstype_verify_onbox_output "$ROUT" || fail "real stock filesys.c: host verifier refused: $ROUT"
  vfssw_span "$FSCF" | grep -q "\"$NM\", $IT" || fail "real stock filesys.c: row is not inside vfssw[]"
  fmodsw_span "$FSCF" | grep -q "$NM" && fail "real stock filesys.c: row landed in fmodsw[]"
  ok "real stock filesys.c ($REALFSC): integrated into vfssw[], not fmodsw[]"
else
  echo "  note: AMIX_SYSTEM is not set (or has no usr/sys/master.d/filesys.c) -- skipping the real-tree arm (synthetic fixtures still run)"
fi

echo "== 3. IDEMPOTENT: a second run changes nothing =="
R="$(mkroot fresh2)"
run "$R"
[ "$RC" -eq 0 ] || fail "idempotency fixture: first run exited $RC: $ROUT"
FSCF="$R/usr/sys/master.d/filesys.c"
cp "$FSCF" "$TMP/after1.c"; cp "$R/usr/sys/fs/Makefile" "$TMP/after1.mk"; cp "$R/usr/sys/Makefile" "$TMP/after1.top"
run "$R"
[ "$RC" -eq 0 ] || fail "second run exited $RC: $ROUT"
case "$ROUT" in *"FSC ok"*) : ;; *) fail "second run did not report FSC ok: $ROUT";; esac
case "$ROUT" in *patched*) fail "second run claims to have patched something: $ROUT";; esac
cmp -s "$FSCF" "$TMP/after1.c"                 || fail "filesys.c changed on the idempotent re-run"
cmp -s "$R/usr/sys/fs/Makefile" "$TMP/after1.mk"  || fail "fs/Makefile changed on the idempotent re-run"
cmp -s "$R/usr/sys/Makefile" "$TMP/after1.top"    || fail "top Makefile changed on the idempotent re-run"
fstype_verify_onbox_output "$ROUT" || fail "host verifier refused the idempotent re-run: $ROUT"
ok "re-run reports ok everywhere, all three files byte-identical"

echo "== 4. HALF-PATCH (extern present, row absent) is detected and repaired =="
R="$(mkroot half)"
FSCF="$R/usr/sys/master.d/filesys.c"
# exactly what a row-address miss leaves behind: the extern written, no row
sed -i "/^struct vfssw vfssw\[\] = {/i extern int $IT();" "$FSCF"
# MUTATION CHECK on the fixture: the OLD name-wide guard matches this tree, so the pre-fix
# script would have said "FSC ok" and skipped it forever.  If this ever stops holding, the
# fixture no longer reproduces the defect and the assertion below proves nothing.
grep -q "$IT" "$FSCF" || fail "half-patch fixture does not even mention $IT"
vfssw_span "$FSCF" | grep -q "$IT" && fail "half-patch fixture already has the row -- not a half-patch"
ok "fixture reproduces the trap: the name-wide 'grep $IT' matches, the vfssw[] span does not"
run "$R"
[ "$RC" -eq 0 ] || fail "half-patch repair exited $RC: $ROUT"
case "$ROUT" in *"HALF-PATCHED"*) : ;; *) fail "the half-patch was not reported: $ROUT";; esac
vfssw_span "$FSCF" | grep -q "\"$NM\", $IT" || fail "the half-patch was not repaired -- still no row in vfssw[]"
[ "$(grep -c "^extern int $IT();" "$FSCF")" -eq 1 ] || fail "the extern was duplicated during repair"
fstype_verify_onbox_output "$ROUT" || fail "host verifier refused the repaired run: $ROUT"
ok "half-patch reported, row inserted, extern not duplicated"

echo "== 5. WRONG-TABLE drift is refused before any write =="
R="$(mkroot wrongtable)"
FSCF="$R/usr/sys/master.d/filesys.c"
# the drift: vfssw's close brace loses its tab, fmodsw's gains one.  ed's row address is a
# forward-WRAPPING search for the first tab-indented close, so it now finds fmodsw's.
perl -0pi -e "s/\n\t\};\n/\n\};\n/" "$FSCF"
perl -0pi -e "s/\n\};\n\n int fmodcnt/\n\};\n\n int fmodcnt/" "$FSCF"
python3 - "$FSCF" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
# give fmodsw[] a TAB-indented close so the wrapping search has somewhere wrong to land
i=s.index('struct fmodsw fmodsw[] = {')
head,tail=s[:i],s[i:]
tail=tail.replace('\n};\n','\n\t};\n',1)
open(p,'w').write(head+tail)
PY
grep -q '^	};' "$FSCF" || fail "wrong-table fixture has no tab-indented close at all"
grep -q '^struct vfssw vfssw\[\] = {' "$FSCF" || fail "wrong-table fixture lost the vfssw declaration"
# MUTATION CHECK: run the BARE pre-fix ed body on a copy and show it lands the row in
# fmodsw[], quietly, exit 0.  That is the defect, reproduced.
cp "$FSCF" "$TMP/wrong-bare.c"
ed - "$TMP/wrong-bare.c" >/dev/null 2>&1 <<ED || true
/^struct vfssw vfssw\[\] = {/i
extern int $IT();
.
/^struct vfssw vfssw\[\] = {/
/^${TAB}};/i
${TAB}{ "$NM", $IT, 0, 0 },
.
w
q
ED
fmodsw_span "$TMP/wrong-bare.c" | grep -q "$NM" \
  || fail "the bare ed body did NOT land the row in fmodsw[] -- the fixture no longer reproduces the wrong-table defect"
ok "pre-fix ed body demonstrably lands the $NM row inside fmodsw[] on this tree (silently)"
cp "$FSCF" "$TMP/wrong-before.c"
expect_abort "wrong-table drift" "$R" "WRONG table"
cmp -s "$FSCF" "$TMP/wrong-before.c" || fail "filesys.c was modified despite the refusal"
ok "filesys.c byte-unchanged after the refusal"

echo "== 6. a missing vfssw[] declaration anchor is refused =="
R="$(mkroot noanchor)"
FSCF="$R/usr/sys/master.d/filesys.c"
sed -i 's/^struct vfssw vfssw\[\] = {/struct vfssw vfssw[]= {/' "$FSCF"
cp "$FSCF" "$TMP/noanchor-before.c"
expect_abort "drifted vfssw[] declaration" "$R" "declaration anchor"
cmp -s "$FSCF" "$TMP/noanchor-before.c" || fail "filesys.c was modified despite the refusal"
ok "filesys.c byte-unchanged after the refusal"

echo "== 7. ed's exit status is consulted (the row address misses mid-script) =="
R="$(mkroot edrc)"
FSCF="$R/usr/sys/master.d/filesys.c"
# Mutate the GENERATED script so only the ROW address misses.  The extern arm still runs
# and still WRITES -- that is precisely the measured mode: an address miss is not a no-op.
sed "s|^/\^${TAB}};/i\$|/^${TAB}}THIS-ADDRESS-CANNOT-MATCH;/i|" "$TMP/gen.sh" > "$TMP/gen-edrc.sh"
cmp -s "$TMP/gen.sh" "$TMP/gen-edrc.sh" && fail "the ed-rc mutation did not change the generated script"
RC=0; ROUT="$(FSPFX="$R/usr/sys" sh "$TMP/gen-edrc.sh" 2>&1)" || RC=$?
[ "$RC" -ne 0 ] || fail "a missed ed row address exited 0 -- ed's status is being discarded"
case "$ROUT" in *FSTYPE_ABORT*) : ;; *) fail "missed row address did not abort: $ROUT";; esac
case "$ROUT" in *"HALF-PATCHED"*|*"ALREADY WRITTEN"*) : ;; *) fail "the abort does not say the file is half-patched: $ROUT";; esac
case "$ROUT" in *"FSC patched"*) fail "printed 'FSC patched' after a failed ed: $ROUT";; esac
fstype_verify_onbox_output "$ROUT" 2>/dev/null && fail "the host verifier accepted a half-patched run"
grep -q "^extern int $IT();" "$FSCF" || fail "the fixture did not reach the half-patched state the test is about"
vfssw_span "$FSCF" | grep -q "$IT" && fail "the row landed despite the mutated address"
ok "missed row address -> non-zero exit, FSTYPE_ABORT naming the half-patch, no 'patched' line"
# and the normal script repairs the tree it left behind
run "$R"
[ "$RC" -eq 0 ] || fail "the repair run exited $RC: $ROUT"
vfssw_span "$FSCF" | grep -q "\"$NM\", $IT" || fail "the repair run did not insert the row"
ok "a normal run afterwards repairs the half-patched tree"

echo "== 8. the host verifier is the real gate (one remote exit status names no record) =="
fstype_verify_onbox_output "FSM ok
FSC ok
FSTYPE_OK $NM
FSTYPE_DONE" || fail "verifier refused a complete transcript"
ok "complete transcript accepted"
fstype_verify_onbox_output "FSM ok
FSTYPE_DONE" 2>/dev/null && fail "verifier accepted a transcript with no FSTYPE_OK"
ok "missing FSTYPE_OK refused"
fstype_verify_onbox_output "FSTYPE_OK $NM" 2>/dev/null && fail "verifier accepted a transcript with no FSTYPE_DONE"
ok "missing FSTYPE_DONE refused"
fstype_verify_onbox_output "FSTYPE_OK $NM
FSTYPE_ABORT: something
FSTYPE_DONE" 2>/dev/null && fail "verifier accepted a transcript carrying FSTYPE_ABORT"
ok "FSTYPE_ABORT refused even when the other sentinels are present"
# CRLF (telnet) must not defeat it
fstype_verify_onbox_output "$(printf 'FSTYPE_OK %s\r\nFSTYPE_DONE\r\n' "$NM")" \
  || fail "verifier refused a CRLF transcript"
ok "CRLF transcript accepted"

echo "== 9. fstype_stage_onbox end-to-end, through stub amixsh/amixsync =="
# The stubs stand in for the box: amixsh runs each command under sh with /usr/sys and /tmp
# redirected into the fixture root.  Two box behaviors are modeled because both matter:
#   * the remote-shell helper PROPAGATES the worst on-box rc as its exit status (a stub
#     that always exits 0 would let the mkdir regression below pass unseen), and
#   * the box's SVR4 mkdir errors `mkdir: "<dir>": File exists` rc 2 on an existing
#     FINAL component even under -p -- a bindir shim ahead of PATH reproduces that,
#     since the host's GNU mkdir -p succeeds there and would un-test the case.
mkdir -p "$TMP/svr4bin"
cat > "$TMP/svr4bin/mkdir" <<'SH'
#!/bin/bash
# SVR4-mkdir model: -p does NOT tolerate an existing final component.
last=""
for a in "$@"; do case "$a" in -*) ;; *) last="$a" ;; esac; done
if [ -n "$last" ] && [ -e "$last" ]; then
  echo "mkdir: \"$last\": File exists" >&2
  exit 2
fi
exec /bin/mkdir "$@"
SH
chmod +x "$TMP/svr4bin/mkdir"
cat > "$TMP/amixsh.py" <<'PY'
import os, re, subprocess, sys
root = os.environ["STUBROOT"]
env = dict(os.environ); env["FSPFX"] = root + "/usr/sys"
env["PATH"] = os.environ["SVR4BIN"] + os.pathsep + env.get("PATH", "")
rc_overall = 0
for cmd in sys.argv[1:]:
    # ONE regex pass, not two sequential .replace() calls: the fixture root itself
    # lives under /tmp (mktemp), so a second pass would re-rewrite the root the first
    # pass had just inserted, silently mangling every /usr/sys path into root+root --
    # and a bare on-box mkdir would then look green.
    cmd = re.sub(r'(/usr/sys|/tmp/)', lambda m: root + m.group(0), cmd)
    p = subprocess.run(["sh", "-c", cmd], capture_output=True, text=True, env=env)
    sys.stdout.write(p.stdout); sys.stdout.write(p.stderr)
    if p.returncode != 0 and rc_overall == 0: rc_overall = p.returncode
sys.exit(rc_overall)   # the real helper exits with the worst on-box rc -- model that
PY
export SVR4BIN="$TMP/svr4bin"
cat > "$TMP/amixsync.py" <<'PY'
import os, shutil, sys
root = os.environ["STUBROOT"]
if sys.argv[1] == "push":
    dst = root + sys.argv[3]
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy(sys.argv[2], dst)
PY
mkdir -p "$TMP/xtool/bin" "$TMP/xtool/lib/gcc-lib/m68k-cbm-sysv4/2.7.2.3"
: > "$TMP/xtool/lib/gcc-lib/m68k-cbm-sysv4/2.7.2.3/libgcc.a"
export CROSS_PREFIX="$TMP/xtool/bin/m68k-cbm-sysv4-"
R="$(mkroot stage)"
mkdir -p "$TMP/stagework"
rc=0
( export STUBROOT="$R"
  fstype_stage_onbox "$TMP/amixsh.py" "$TMP/amixsync.py" "$TMP/stagework" >"$TMP/stage.log" 2>&1 ) || rc=$?
[ "$rc" -eq 0 ] || { cat "$TMP/stage.log"; fail "fstype_stage_onbox exited $rc on a good tree"; }
vfssw_span "$R/usr/sys/master.d/filesys.c" | grep -q "\"$NM\", $IT" \
  || fail "fstype_stage_onbox did not integrate the row"
[ -f "$R/usr/sys/fs/$NM/exp" ]      || fail "fs/$NM/exp was not pushed"
[ -f "$R/usr/sys/fs/libfsgcc.a" ]   || fail "libfsgcc.a was not pushed"
grep -q 'FSTYPE_OK' "$TMP/stage.log" || fail "the on-box transcript was not echoed into the build log"
ok "green tree: exp + libgcc pushed, row integrated, transcript in the log"
# GATE_FS is set for the caller (a subshell cannot hand it back, so re-derive it here)
R2="$(mkroot stage2)"
rc=0
( export STUBROOT="$R2"
  fstype_stage_onbox "$TMP/amixsh.py" "$TMP/amixsync.py" "$TMP/stagework" >/dev/null 2>&1
  [ "$GATE_FS" = "--fs /usr/sys/fs/libfsgcc.a" ] || exit 9
  [ "$FS_DESC" = "; fs: $NM" ] || exit 9 ) || rc=$?
[ "$rc" -eq 0 ] || fail "fstype_stage_onbox did not set GATE_FS/FS_DESC (rc $rc)"
ok "GATE_FS and FS_DESC set as before"
# A tree that ALREADY CARRIES fs/<name> (a box image that was integrated before): SVR4
# mkdir -p errors rc 2 on an existing final component and the helper propagates it.  First prove the MODEL reproduces the
# regression (the old bare command must die through the stubs -- otherwise the tolerance
# assertion below would pass vacuously), then prove the guarded staging tolerates it.
R4="$(mkroot stage-exists)"
mkdir -p "$R4/usr/sys/fs/$NM"
rc=0
( export STUBROOT="$R4"
  python3 "$TMP/amixsh.py" "mkdir -p /usr/sys/fs/$NM" >/dev/null 2>&1 ) || rc=$?
[ "$rc" -eq 2 ] || fail "model check: bare 'mkdir -p' on an existing dir exited $rc through the stubs, expected the box's 2"
ok "model reproduces the regression: bare mkdir -p on an existing fs/$NM exits 2"
rc=0
( export STUBROOT="$R4"
  fstype_stage_onbox "$TMP/amixsh.py" "$TMP/amixsync.py" "$TMP/stagework" >"$TMP/stage-exists.log" 2>&1 ) || rc=$?
[ "$rc" -eq 0 ] || { cat "$TMP/stage-exists.log"; fail "fstype_stage_onbox exited $rc on a tree already carrying fs/$NM (the exists case must be tolerated)"; }
vfssw_span "$R4/usr/sys/master.d/filesys.c" | grep -q "\"$NM\", $IT" \
  || fail "exists case: row was not integrated"
[ -f "$R4/usr/sys/fs/$NM/exp" ] || fail "exists case: fs/$NM/exp was not pushed"
ok "pre-existing fs/$NM tolerated: staging completes, row integrated, exp pushed"
# and a wrong-table tree must stop the build, not gate a kernel without the filesystem
R3="$(mkroot stagebad)"
python3 - "$R3/usr/sys/master.d/filesys.c" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('\n\t};\n','\n};\n',1)
i=s.index('struct fmodsw fmodsw[] = {'); head,tail=s[:i],s[i:]
open(p,'w').write(head+tail.replace('\n};\n','\n\t};\n',1))
PY
cp "$R3/usr/sys/master.d/filesys.c" "$TMP/stagebad-before.c"
rc=0
( export STUBROOT="$R3"
  fstype_stage_onbox "$TMP/amixsh.py" "$TMP/amixsync.py" "$TMP/stagework" >"$TMP/stagebad.log" 2>&1 ) || rc=$?
[ "$rc" -eq 2 ] || fail "fstype_stage_onbox exited $rc on a wrong-table tree, expected 2"
grep -q 'REFUSED to patch' "$TMP/stagebad.log" || fail "the refusal was not diagnosed: $(cat "$TMP/stagebad.log")"
cmp -s "$R3/usr/sys/master.d/filesys.c" "$TMP/stagebad-before.c" || fail "filesys.c was modified on the refused staging"
ok "wrong-table tree: staging exits 2, diagnosed, filesys.c untouched"
# A bare CROSS_PREFIX (the default, m68k-cbm-sysv4-) names tools on PATH; libgcc.a is
# found beside the gcc that PATH resolves.
printf '#!/bin/sh\nexit 0\n' > "$TMP/xtool/bin/m68k-cbm-sysv4-gcc"; chmod +x "$TMP/xtool/bin/m68k-cbm-sysv4-gcc"
R5="$(mkroot stage-bare)"
rc=0
( export STUBROOT="$R5" CROSS_PREFIX=m68k-cbm-sysv4- PATH="$TMP/xtool/bin:$PATH"
  fstype_stage_onbox "$TMP/amixsh.py" "$TMP/amixsync.py" "$TMP/stagework" >"$TMP/stage-bare.log" 2>&1 ) || rc=$?
[ "$rc" -eq 0 ] || { cat "$TMP/stage-bare.log"; fail "fstype_stage_onbox with a bare CROSS_PREFIX exited $rc"; }
grep -q "libfsgcc.a <- $TMP/xtool/lib/gcc-lib/" "$TMP/stage-bare.log" \
  || fail "bare CROSS_PREFIX: libgcc.a was not taken from beside the PATH gcc: $(cat "$TMP/stage-bare.log")"
ok "bare CROSS_PREFIX resolved on PATH; libgcc.a found beside that gcc"

echo "== 10. bash -n syntax + build-cross-kernel.sh uses the lib =="
for f in "$KT/tools/fstype-lib.sh" "$KT/tools/fstype-selftest.sh" "$KT/build-cross-kernel.sh"; do
  bash -n "$f" || fail "syntax error in $f"
  ok "$(basename "$f") parses"
done
f="$KT/build-cross-kernel.sh"; b="$(basename "$f")"
grep -qF '. "$KT/tools/fstype-lib.sh"' "$f" || fail "$b does not source tools/fstype-lib.sh"
# call sites only -- a mention in a comment parses nothing.  `|| true` is load-bearing
# under pipefail: a grep that matches nothing exits 1 (that IS the regression being tested).
cline="$(grep -n '^[[:space:]]*fstype_parse' "$f" | head -1 | cut -d: -f1 || true)"
[ -n "$cline" ] || fail "$b does not call fstype_parse"
ok "$b sources the lib and calls fstype_parse at line $cline"
grep -q -- '--no-fstypes' "$f" && grep -q 'FSTYPES_CONF=/dev/null' "$f" \
  || fail "$b no longer maps --no-fstypes to FSTYPES_CONF=/dev/null (arm 0 proves /dev/null needs no CDFS)"
ok "$b keeps --no-fstypes -> FSTYPES_CONF=/dev/null"

echo "SELFTEST PASS"
