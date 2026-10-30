#!/bin/bash
# kpatch-selftest.sh -- host-side self-test for the kernel-patch verify-then-apply mechanism
# (tools/kpatch-lib.sh + kernel-patches.conf).  Proves the logic WITHOUT an Amix box:
#   1. kernel-patches.conf parses to the expected records, the a4091 driver's support.c
#      patch is still the hardened probe, and the retired never-apply rule has not crept back.
#  1b. the stock column: `usr/sys/...` resolves against $AMIX_SYSTEM and is refused when it
#      is unset; absolute and other relative paths resolve as before.
#   2. every pristine stock really is pristine (marker absent) -- so `patch` always applies
#      forward.
#   3. each driver-repo patch applies to its stock and the marker then appears
#      (kpatch_apply_host succeeds), and the result byte-matches a straight GNU-patch apply.
#   4. an already-patched target is detected as such (dry-run "Reversed") -- i.e. we would
#      NEVER double-apply; the marker probe is what makes the on-box step idempotent.
#   5. `bash -n` (syntax) is clean for the library and this test.
#   6. the `exp=` option: validation refuses anything that could widen (glob, absolute
#      path, `..`, bare `exp`), and the emitted invalidation names exactly one file.
#   7. THE REBUILD ITSELF, at fixture level with no box: `make -n` over the real
#      amiga/driver/Makefile rule shows that a newer aen.c does NOT rebuild an existing
#      aen/exp, and that removing exactly that exp -- the command kpatch emits -- does.
#   8. the revision binding + the whole ensure step end to end through stub runner/pusher:
#      fresh apply, no-op re-run, a REVISED patch behind the SAME marker (which must
#      re-apply), and a stampless box (which must re-establish).
#   9. drift guards on the stock tree: amiga/driver's aen/exp rule still has no
#      prerequisites (so the option is still needed) and amiga/alien's exp rule still has
#      them (so its rows still do not need one).
#  12. THE WIRE BUDGET (MAX_CANON).  Every on-box line this library generates, for every
#      record in the REAL conf at the worst-case revision width, measured against a 240-byte
#      wire budget (command + the runner's 16-byte completion suffix) under SVR4's
#      MAX_CANON = 256 -- plus the guard's own teeth and the split-sentinel echo immunity.
#      12b is the regression fixture for the exact shape that broke: the aen record's OLD
#      &&-chained post-push verify, reconstructed from the real conf, shown to overrun and to
#      answer NOTHING through the stub's tty model -- and to WEDGE the session for the
#      command after it, the measured signature -- and the new per-leg shape shown to fit and
#      to answer.  Section 8's stub models that tty, so these fixtures cannot pass vacuously.
#  13. THE CONF-VS-GLOB RECONCILIATION.  kpatch_always_extra, the entry point the GLOB-driven
#      host cross builder uses: an `always:` row is emitted when no offered dir supplies it,
#      deduped when one supplies it byte-identically (so builds that pass the owning repo are
#      unchanged), REFUSED when an offered dir holds a different patch for the same file, and
#      REFUSED when the row's repo is not present.  Driven on fixture repos for every branch
#      (plus the amix-insensitive key match), and then on the real conf, where every
#      `always:` row must resolve to the a4091 driver.
# (Sections 10, 11 and 14 -- tools/onbox-build.sh's kernel-patch arm, amix-build's
# records.sh join, bundle-exclude.conf and the offline bundler's always: handling -- live
# with the on-box builders, which have not moved into kernel/k30.)
#
# Inputs:
#   AMIX_SYSTEM   a checkout of amigaux/amix-system (the pristine stock tree).  Unset: every
#                 arm that reads a stock base or parses the REAL conf prints a SKIP line and
#                 the run continues; the synthetic fixtures always run.
#   AMIX_DRIVERS  where the driver repos live (default: kernel/drivers, i.e. $KT/../drivers),
#                 as amix-a4091 or a4091 etc.  Live arms that need the a4091 driver skip,
#                 with a note, when it is absent.
# The number of skips is printed at the end.  Exit 0 = all green; non-zero on the first
# failure.
set -euo pipefail

KT="$(cd "$(dirname "$0")/.." && pwd)"
. "$KT/tools/kpatch-lib.sh"
CONF="$KT/kernel-patches.conf"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "SELFTEST FAIL: $*" >&2; exit 1; }
ok()   { echo "  ok: $*"; }
SKIPS=0
skip() { echo "  SKIP: $*"; SKIPS=$((SKIPS + 1)); }

HAVE_SYS=0
if [ -n "${AMIX_SYSTEM:-}" ]; then
  [ -d "$AMIX_SYSTEM/usr/sys" ] \
    || fail "AMIX_SYSTEM=$AMIX_SYSTEM has no usr/sys -- it must be a checkout of amigaux/amix-system"
  HAVE_SYS=1
  echo "AMIX_SYSTEM=$AMIX_SYSTEM"
else
  echo "AMIX_SYSTEM is not set -- arms that read the stock tree or parse the real conf will SKIP"
fi
DRVROOT="${AMIX_DRIVERS:-$KT/../drivers}"
DRVDIRS=()
if [ -d "$DRVROOT" ]; then
  for d in "$DRVROOT"/*; do [ -d "$d" ] && DRVDIRS+=("$d"); done
fi
echo "driver dirs: $DRVROOT (${#DRVDIRS[@]} found)"
# the a4091 driver, as the live arms look for it: amix-a4091 or a4091 under $DRVROOT
A4091="$(kpatch_repo_dir amix-a4091 "$KT" ${DRVDIRS[@]+"${DRVDIRS[@]}"} || true)"

echo "== 1. parse kernel-patches.conf =="
if [ "$HAVE_SYS" = 1 ]; then
  kpatch_parse "$CONF" "$KT"
  # Expected count is DERIVED from the file, not hardcoded: the check that matters is "the
  # parser dropped nothing", and a literal count silently goes stale every time a record is
  # added.
  WANT="$(grep -Evc '^[[:space:]]*(#|$)' "$CONF")"
  [ "${#KP_REPO[@]}" -eq "$WANT" ] || fail "expected $WANT records (non-comment lines in $CONF), got ${#KP_REPO[@]}"
  [ "${#KP_REPO[@]}" -ge 1 ] || fail "kernel-patches.conf parsed to zero records"
  ok "$WANT records parsed (one per non-comment line)"
else
  skip "parsing the real conf needs AMIX_SYSTEM (its stock column is usr/sys/... in amigaux/amix-system)"
fi
# support.c is PERMITTED.  An older rule said stock support.c had to stay unpatched because
# the patched probe failed under Amiberry; amix-a4091 adf3875 hardened the WD33C93 probe
# against the Amiberry ECS open-bus alias, and the patched install kernel then passed the
# full install matrix at 64 MB and at 16 MB.  A support.c row is an ORDINARY row --
# sections 2..4 exercise it exactly like every other record.  What IS asserted is the inverse
# of the retired rule, because reviving it is silent and expensive: with the patch absent,
# stock support.c:305 keeps its `end > 0x07000000` RAM-SIZE GUESS at the a3091's only
# registration point, and any kernel running with Fast RAM extending below that line loses
# the controller -- SCSI cards renumber and the install target vanishes.  So the patch must
# still EXIST in the a4091 driver, and must still be the hardened two-register revision, not
# the pre-adf3875 single-register probe an open bus can spoof.
SUPPORT_PATCH="${A4091:+$A4091/src/kernel-patches/support.c.patch}"
if [ -n "$SUPPORT_PATCH" ] && [ -f "$SUPPORT_PATCH" ]; then
  # The tests are anchored to the diff's ADDED lines -- the RAM-size gate legitimately appears
  # on a REMOVED line, which is the whole point of the patch.
  #
  # The discriminator is the SECOND REGISTER, not the ports: both the superseded probe and the
  # hardened one drive the indirect SASR/SCMD pair (0xDD0041/0xDD0043), so those addresses alone
  # cannot tell the revisions apart.  What adf3875 added is a write to WD33C93 register 0x03
  # (`*sasr = 0x03`) -- the pre-adf3875 probe wrote 0x55 and then 0xAA to register 0x02 ONLY, and
  # a per-address open-bus latch answers that pattern exactly like a real chip.
  grep -q '^+.*0xDD0041' "$SUPPORT_PATCH" && grep -q '^+.*0xDD0043' "$SUPPORT_PATCH" \
    || fail "$SUPPORT_PATCH no longer ADDS the 0xDD0041/0xDD0043 SASR/SCMD probe -- it is not the A3000-SCSI detection patch any more"
  grep -q '^+.*sasr = 0x03' "$SUPPORT_PATCH" \
    || fail "$SUPPORT_PATCH adds no write to WD33C93 register 0x03 -- this is the single-register probe from before amix-a4091 adf3875, which an open-bus latch spoofs (phantom A3000, card-shift) under Amiberry"
  grep -q '^-.*0x07000000' "$SUPPORT_PATCH" \
    || fail "$SUPPORT_PATCH no longer REMOVES the stock 0x07000000 RAM-size gate -- that guess is the defect it exists to close"
  grep -q '^+.*0x07000000' "$SUPPORT_PATCH" \
    && fail "$SUPPORT_PATCH re-introduces 0x07000000 on an ADDED line -- the RAM-size guess is back"
  ok "support.c is permitted; the a4091 driver's patch is the two-register probe (SASR/SCMD + reg 0x03) and removes the 0x07000000 RAM-size gate"
else
  skip "support.c patch checks: the a4091 driver is not present under $DRVROOT (amix-a4091 or a4091)"
fi
# and the retired prohibition must not creep back into the conf as prose
grep -q 'never be auto-applied' "$CONF" \
  && fail "$CONF has revived the retired 'support.c must never be auto-applied' rule -- refuted (see the conf's own support.c block)"
ok "the retired never-apply rule has not crept back into $CONF"

echo "== 1b. the stock column: usr/sys/... resolves against AMIX_SYSTEM =="
mkdir -p "$TMP/fakesys/usr/sys/amiga/alien" "$TMP/fakekt/stock"
: > "$TMP/fakesys/usr/sys/amiga/alien/x.c"; : > "$TMP/fakekt/stock/y.c"; : > "$TMP/abs.c"
{ echo "kpatch kpx p.patch amiga/alien/x.c MX usr/sys/amiga/alien/x.c"
  echo "kpatch kpx p.patch amiga/alien/y.c MY stock/y.c"
  echo "kpatch kpx p.patch amiga/alien/z.c MZ $TMP/abs.c"
} > "$TMP/conf-stock"
( unset AMIX_SYSTEM; kpatch_parse "$TMP/conf-stock" "$TMP/fakekt" ) >/dev/null 2>"$TMP/stock.err" \
  && fail "kpatch_parse accepted a usr/sys/ stock with AMIX_SYSTEM unset"
grep -q 'AMIX_SYSTEM is not set' "$TMP/stock.err" || fail "the AMIX_SYSTEM refusal does not say why: $(cat "$TMP/stock.err")"
ok "a usr/sys/ stock with AMIX_SYSTEM unset is refused (exit 2), naming AMIX_SYSTEM"
GOT="$( AMIX_SYSTEM="$TMP/fakesys"; kpatch_parse "$TMP/conf-stock" "$TMP/fakekt"; printf '%s\n' "${KP_STOCK[@]}" )"
[ "$GOT" = "$(printf '%s\n' "$TMP/fakesys/usr/sys/amiga/alien/x.c" "$TMP/fakekt/stock/y.c" "$TMP/abs.c")" ] \
  || fail "the stock column resolved wrongly: $GOT"
ok "usr/sys/... -> \$AMIX_SYSTEM/usr/sys/..., other relative -> the kt root, absolute unchanged"

echo "== 2..4. per-record apply / idempotency =="
if [ "$HAVE_SYS" != 1 ]; then
  skip "sections 2..4 read the stock bases of the real conf -- they need AMIX_SYSTEM"
else
for i in "${!KP_REPO[@]}"; do
  repo="${KP_REPO[$i]}"; prel="${KP_PATCHREL[$i]}"; mrk="${KP_MARKER[$i]}"; stock="${KP_STOCK[$i]}"
  # resolve the repo key through the SAME helper the on-box path uses, so a kernel/k30-owned
  # (unconditional) record is exercised here exactly as a driver-repo one is.  Every driver
  # dir present is offered; a record whose driver is not present is skipped, with a note.
  repodir="$(kpatch_repo_dir "$repo" "$KT" ${DRVDIRS[@]+"${DRVDIRS[@]}"} || true)"
  if [ -z "$repodir" ]; then
    skip "record $i: driver '$repo' is not present under $DRVROOT"
    continue
  fi
  patchabs="$repodir/$prel"
  if [ ! -f "$patchabs" ]; then
    case "$repo" in
      always:*) skip "record $i: '$repo' -- its driver is not present ($patchabs)"; continue ;;
      *) fail "driver patch missing: $patchabs" ;;
    esac
  fi
  echo "-- $repo :: $(basename "$patchabs") (marker '$mrk') --"

  # UNCONDITIONALITY is the property that matters for a boot-critical row, so assert it
  # directly rather than trusting the key's spelling: resolve the record again with NO
  # driver dirs offered at all (a z3660scsi-only build, the case that shipped an
  # unbootable kernel) and require an `always:`/k30 row to still resolve, to the same
  # directory, with its patch file present.  A plain driver-repo row must NOT resolve.
  bare="$(kpatch_repo_dir "$repo" "$KT" || true)"
  case "$repo" in
    always:*|"$(basename "$KT")")
      [ -n "$bare" ] || fail "record $i: '$repo' is unconditional but does not resolve with no driver dirs"
      [ "$(cd "$bare" && pwd)" = "$(cd "$repodir" && pwd)" ] \
        || fail "record $i: '$repo' resolves to $bare unconditionally but $repodir when selected"
      [ -f "$bare/$prel" ] \
        || fail "record $i: '$repo' is unconditional but its patch is missing: $bare/$prel"
      ok "unconditional: resolves with no driver dirs selected, patch present" ;;
    *)
      [ -z "$bare" ] || fail "record $i: '$repo' is a plain driver-repo key but resolved with no driver dirs"
      ok "conditional: correctly does not resolve when its repo is not in the build" ;;
  esac

  # 2. stock is pristine (marker absent) so the forward apply is always unambiguous
  if grep -q "$mrk" "$stock"; then fail "stock $stock already contains marker '$mrk' (not pristine)"; fi
  ok "stock pristine (no '$mrk')"

  # patch must apply cleanly to the pristine stock
  cp "$stock" "$TMP/ref"
  patch -s -N --no-backup-if-mismatch "$TMP/ref" < "$patchabs" || fail "patch does not apply to stock"

  # 3. kpatch_apply_host produces the marker AND byte-matches the straight apply
  out="$TMP/out"
  kpatch_apply_host "$patchabs" "$stock" "$out" "$mrk" || fail "kpatch_apply_host failed"
  cmp -s "$out" "$TMP/ref" || fail "kpatch_apply_host output differs from a straight GNU-patch apply"
  ok "apply -> marker '$mrk' present, matches reference"

  # 4a. IDEMPOTENCY (the real guard): the on-box marker probe would report the applied patch
  #     as PRESENT, so kpatch_ensure_onbox no-ops -- it never re-patches an applied target.
  grep -q "$mrk" "$out" || fail "marker probe would MISS the applied patch (idempotency broken)"
  ok "marker probe sees the applied patch (on-box path would no-op)"
  # 4b. defence in depth: even a second FORWARD apply is refused (never a silent double-apply);
  #     --dry-run -N (no -f) is non-interactive and reports the already-applied hunks.
  reapply="$(patch --dry-run -N --no-backup-if-mismatch "$out" < "$patchabs" 2>&1 || true)"
  case "$reapply" in
    *"previously applied"*|*"Reversed"*|*"Skipping"*|*"ignored"*)
      ok "second forward apply is refused (Reversed/previously applied)";;
    *) fail "second forward apply was NOT refused as already-applied: $reapply";;
  esac
done
fi

echo "== 5. bash -n syntax =="
for f in "$KT/tools/kpatch-lib.sh" "$KT/tools/kpatch-selftest.sh"; do
  bash -n "$f" || fail "syntax error in $f"
  ok "$(basename "$f") parses"
done

echo "== 6. the exp= option cannot widen, and the invalidation is surgical =="
for bad in "" "/usr/sys/amiga/driver/aen/exp" "amiga/driver/*/exp" "amiga/driver/aen/exp?" \
           "amiga/../etc/exp" "exp" "amiga/driver/aen/exp extra" "amiga/driver/aen/aen.o"; do
  kpatch_check_exp "$bad" && fail "kpatch_check_exp accepted '$bad' -- an exp= value that can widen"
done
ok "refuses: empty, absolute, glob (* ? [ ]), '..', bare 'exp', embedded space, non-/exp"
kpatch_check_exp "amiga/driver/aen/exp" || fail "kpatch_check_exp rejected the legitimate aen value"
ok "accepts the one legitimate shape (amiga/driver/aen/exp)"
# a bad option in the conf must ABORT the parse, not be ignored -- a mis-spelled key would
# quietly restore the very bug the option closes.  The stock is a real file ($TMP/abs.c from
# 1b), so the refusal can only come from the option.
for badrec in "kpatch kpx p.patch t.c M $TMP/abs.c exp=amiga/*/exp" \
              "kpatch kpx p.patch t.c M $TMP/abs.c xep=amiga/driver/aen/exp"; do
  printf '%s\n' "$badrec" > "$TMP/badconf"
  ( kpatch_parse "$TMP/badconf" "$KT" ) >/dev/null 2>"$TMP/badconf.err" \
    && fail "kpatch_parse accepted a bad record: $badrec"
  grep -Eq "bad exp= value|unknown option" "$TMP/badconf.err" \
    || fail "kpatch_parse refused '$badrec' for the wrong reason: $(cat "$TMP/badconf.err")"
done
ok "kpatch_parse exits on a glob exp= and on an unknown option key"
# the emitted commands: exactly one rm per file, no glob, no -r, and the stamp write
CMDS="$(kpatch_invalidate_cmds /usr/sys/amiga/driver/aen/aen.o /usr/sys/amiga/driver/aen/exp \
        /usr/sys/amiga/driver/aen/aen.c.kprev deadbeef1234)"
[ "$(printf '%s\n' "$CMDS" | wc -l)" -eq 3 ] || fail "expected 3 invalidation commands, got: $CMDS"
printf '%s\n' "$CMDS" | grep -qx 'rm -f /usr/sys/amiga/driver/aen/exp' \
  || fail "the exp removal is not the exact single path: $CMDS"
printf '%s\n' "$CMDS" | grep -qx 'rm -f /usr/sys/amiga/driver/aen/aen.o' || fail "the .o removal is missing: $CMDS"
case "$CMDS" in *'*'*|*'rm -r'*|*'rm -f /usr/sys/amiga/driver/aen '*) fail "the invalidation is not surgical: $CMDS";; esac
ok "invalidation = rm the .o, rm the ONE named exp, write the stamp (no glob, no -r)"
[ "$(kpatch_invalidate_cmds /a/b.o "" /a/b.c.kprev cafe12345678 | wc -l)" -eq 2 ] \
  || fail "a record with no exp= must emit no exp removal at all"
ok "a record without exp= emits no exp removal"

echo "== 7. the rebuild itself: an existing subsystem exp is never rebuilt =="
if ! command -v make >/dev/null 2>&1; then
  skip "no make on this host -- the rebuild fixture"
else
  MKFIX="$TMP/mkfix"; mkdir -p "$MKFIX/aen"
  # The no-prerequisite rule is taken from the REAL stock amiga/driver/Makefile when the
  # stock tree is present, so a change in the stock Makefile's shape reaches this test.
  REALDRVMK=""
  if [ "$HAVE_SYS" = 1 ] && [ -f "$AMIX_SYSTEM/usr/sys/amiga/driver/Makefile" ]; then
    REALDRVMK="$AMIX_SYSTEM/usr/sys/amiga/driver/Makefile"
  fi
  if [ -n "$REALDRVMK" ]; then
    AENRULE="$(awk '/^aen\/exp[ \t]*:/{p=1} p{print} p&&/^$/{exit}' "$REALDRVMK")"
    [ -n "$AENRULE" ] || fail "no aen/exp rule found in $REALDRVMK -- this test is stale"
    ok "aen/exp rule lifted from the real $REALDRVMK"
  else
    AENRULE="$(printf 'aen/exp :\n\tcd aen; $(MAKE)\n')"
    skip "lifting the aen/exp rule from the real amiga/driver/Makefile needs AMIX_SYSTEM -- using the documented rule text"
  fi
  { printf 'OBJ\t= aen/exp\n\nexp : $(OBJ)\n\tld -r -o exp $(OBJ)\n\n'; printf '%s\n' "$AENRULE"; } > "$MKFIX/Makefile"
  printf 'exp:\n\ttouch exp\n' > "$MKFIX/aen/Makefile"
  : > "$MKFIX/aen/exp"; : > "$MKFIX/exp"; : > "$MKFIX/aen/aen.c"
  touch -d '2020-01-01 00:00' "$MKFIX/aen/exp"
  touch -d '2020-01-02 00:00' "$MKFIX/exp"
  touch -d '2030-01-01 00:00' "$MKFIX/aen/aen.c"      # source far newer than everything
  BEFORE="$(make -n -C "$MKFIX" exp 2>&1 || true)"
  case "$BEFORE" in
    *"cd aen"*) fail "the fixture does not reproduce the defect -- make DID descend into aen with aen/exp present: $BEFORE";;
  esac
  ok "aen.c newer than everything, aen/exp present -> make does NOT descend into aen (the defect)"
  # now do exactly what kpatch does, using its own command
  eval "$(kpatch_invalidate_cmds "$MKFIX/aen/aen.o" "$MKFIX/aen/exp" "$MKFIX/aen/aen.c.kprev" abcdef123456)"
  [ ! -f "$MKFIX/aen/exp" ] || fail "kpatch's own command did not remove aen/exp"
  [ -f "$MKFIX/aen/aen.c.kprev" ] || fail "kpatch's own command did not write the stamp"
  AFTER="$(make -n -C "$MKFIX" exp 2>&1 || true)"
  case "$AFTER" in
    *"cd aen"*) ok "after removing exactly aen/exp, make DOES descend into aen (the fix)";;
    *) fail "removing aen/exp still did not make make descend into aen: $AFTER";;
  esac
  case "$AFTER" in *"ld -r -o exp"*) ok "and amiga/driver/exp is relinked from the rebuilt aen/exp";;
    *) fail "driver/exp was not relinked after aen/exp came back: $AFTER";; esac
fi

echo "== 8. the revision binding, end to end through stub runner/pusher =="
# Stubs stand in for the box: the runner runs each command with /usr/sys redirected into a
# fixture root and -- like the real telnet command runner -- ALWAYS EXITS 0.
#
# The stub also models the box's CANONICAL TTY, because that is what broke the verify: the
# runner sends each command as one telnet line with its own 16-byte `; echo D''ONE_$?`
# appended, and SVR4 caps a canonical line at MAX_CANON = 256 bytes.
#
# WHAT PAST THE CAP LOOKS LIKE.  Measured on a real box with a padding ladder: 229 bytes on
# the wire answer normally, 269 answer NOTHING AT ALL -- no output, no bell, no error -- and
# the LOGIN STAYS WEDGED, so every later command in that session answers nothing either,
# until the caller reconnects.  (A truncated echo ending in bells is one shape that has been
# seen, but it is not the signature.)  The stub models the silence and the wedge, which is
# the harsher of the two: no output to key on, and the damage outlives the offending
# command.  Modelling it here (rather than assuming every line is deliverable) is what makes
# sections 8 and 12 a real transport test -- with the old &&-chained verify these fixtures
# fail.
#
# One stub INVOCATION is one login, so the wedge lasts to the end of argv and a fresh
# invocation is the "reconnect".  That mirrors the real runner, which opens one session per
# run.
cat > "$TMP/runner.py" <<'PY'
import os, subprocess, sys
root = os.environ["STUBROOT"]
MAXCANON = int(os.environ.get("STUBMAXCANON", "256"))
wedged = False
for cmd in sys.argv[1:]:
    wire = cmd + "; echo D''ONE_$?"          # exactly what the runner puts on the tty
    if wedged or len(wire) > MAXCANON:
        # measured: no output whatsoever, and the session stays wedged from here on
        wedged = True
        continue
    cmd = cmd.replace("/usr/sys", root + "/usr/sys")
    p = subprocess.run(["sh", "-c", cmd], capture_output=True, text=True)
    sys.stdout.write(p.stdout); sys.stdout.write(p.stderr)
sys.exit(0)
PY
cat > "$TMP/pusher.py" <<'PY'
import os, shutil, sys
root = os.environ["STUBROOT"]
if sys.argv[1] == "push":
    dst = root + sys.argv[3]
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy(sys.argv[2], dst)
PY
MARK=TESTMARK_ioc_arg
mkdir -p "$TMP/kpx/patches" "$TMP/stock" "$TMP/ework"
printf 'line1\nline2\nline3\n' > "$TMP/stock/aen.c"
# two patch REVISIONS carrying the SAME marker -- the shape the revision binding exists for
cp "$TMP/stock/aen.c" "$TMP/v1.c"; sed -i "1a $MARK" "$TMP/v1.c"
cp "$TMP/v1.c" "$TMP/v2.c";       sed -i "/line2/a TESTMARK_extra_v2" "$TMP/v2.c"
diff -u "$TMP/stock/aen.c" "$TMP/v1.c" > "$TMP/kpx/patches/v1.patch" || true
diff -u "$TMP/stock/aen.c" "$TMP/v2.c" > "$TMP/kpx/patches/v2.patch" || true
grep -q "$MARK" "$TMP/kpx/patches/v1.patch" && grep -q "$MARK" "$TMP/kpx/patches/v2.patch" \
  || fail "the two revisions do not both carry the marker -- the revision fixture is wrong"
ok "two patch revisions built, BOTH carrying marker '$MARK' (the old probe could not tell them apart)"
mkconf() { printf 'kpatch kpx patches/%s amiga/driver/aen/aen.c %s %s exp=amiga/driver/aen/exp\n' \
            "$1" "$MARK" "$TMP/stock/aen.c" > "$TMP/conf-$1"; }
mkconf v1.patch; mkconf v2.patch
REV1="$(kpatch_rev "$TMP/kpx/patches/v1.patch" "$TMP/stock/aen.c")"
REV2="$(kpatch_rev "$TMP/kpx/patches/v2.patch" "$TMP/stock/aen.c")"
[ "$REV1" != "$REV2" ] || fail "the two revisions hash the same -- kpatch_rev is not version-bearing"
ok "kpatch_rev distinguishes them ($REV1 vs $REV2) though the marker cannot"

BOX="$TMP/box"; AENDIR="$BOX/usr/sys/amiga/driver/aen"
resetbox() {   # <source-for-aen.c>
  rm -rf "$BOX"; mkdir -p "$AENDIR"
  cp "$1" "$AENDIR/aen.c"; : > "$AENDIR/aen.o"; : > "$AENDIR/exp"
}
ensure() {     # <conf> -> ELOG, rc in ERC
  ERC=0
  ELOG="$( export STUBROOT="$BOX"
           kpatch_ensure_onbox "$TMP/runner.py" "$TMP/pusher.py" "$TMP/ework" "$KT" "$1" "$TMP/kpx" 2>&1 )" || ERC=$?
}
STAMP="$AENDIR/aen.c.kprev"

# 8a. FRESH box (stock source, prebuilt exp): apply, and invalidate BOTH the .o and the exp
resetbox "$TMP/stock/aen.c"
ensure "$TMP/conf-v1.patch"
[ "$ERC" -eq 0 ] || fail "fresh apply exited $ERC: $ELOG"
grep -q "$MARK" "$AENDIR/aen.c" || fail "the patched aen.c was not pushed"
[ ! -f "$AENDIR/aen.o" ] || fail "the stale aen.o was not removed"
[ ! -f "$AENDIR/exp" ]   || fail "the prebuilt aen/exp was NOT removed -- the patch would never reach the kernel"
grep -q "$REV1" "$STAMP"  || fail "the revision stamp was not written"
case "$ELOG" in *"applied"*) : ;; *) fail "no 'applied' line: $ELOG";; esac
ok "fresh box: patched source pushed, aen.o AND aen/exp removed, stamped $REV1"

# 8b. RE-RUN with the same revision: a true no-op -- a restored exp must survive it
: > "$AENDIR/exp"; : > "$AENDIR/aen.o"
ensure "$TMP/conf-v1.patch"
[ "$ERC" -eq 0 ] || fail "no-op re-run exited $ERC: $ELOG"
[ -f "$AENDIR/exp" ] && [ -f "$AENDIR/aen.o" ] || fail "the no-op re-run invalidated the rebuilt objects"
case "$ELOG" in *"no-op"*) ok "re-run at the same revision is a no-op (nothing invalidated)";;
  *) fail "re-run did not report a no-op: $ELOG";; esac

# 8c. a REVISED patch behind the SAME marker must NOT no-op
ensure "$TMP/conf-v2.patch"
[ "$ERC" -eq 0 ] || fail "revised apply exited $ERC: $ELOG"
grep -q TESTMARK_extra_v2 "$AENDIR/aen.c" || fail "the REVISED patch did not reach the box -- the revision binding is broken"
grep -q "$REV2" "$STAMP" || fail "the stamp was not moved to the new revision"
[ ! -f "$AENDIR/exp" ] || fail "the revised apply did not remove aen/exp"
case "$ELOG" in *"NO matching revision stamp"*) ok "revised patch, same marker -> re-applied, and the log says why";;
  *) fail "the revised apply did not diagnose the stale revision: $ELOG";; esac

# 8d. a tree patched BEFORE stamping existed: marker present, no stamp -> re-establish
rm -f "$STAMP"; : > "$AENDIR/exp"; : > "$AENDIR/aen.o"
ensure "$TMP/conf-v2.patch"
[ "$ERC" -eq 0 ] || fail "stampless re-establish exited $ERC: $ELOG"
grep -q "$REV2" "$STAMP" || fail "the stampless box was not stamped"
[ ! -f "$AENDIR/exp" ] || fail "the stampless re-establish did not remove aen/exp"
ok "stampless box (marker present, revision unknown) is re-established, not assumed good"

# 8e. fail-closed: a box that answers nothing must abort, never be guessed at
printf 'import sys\nsys.exit(0)\n' > "$TMP/runner-mute.py"
ERC=0
ELOG="$( export STUBROOT="$BOX"
         kpatch_ensure_onbox "$TMP/runner-mute.py" "$TMP/pusher.py" "$TMP/ework" "$KT" "$TMP/conf-v2.patch" "$TMP/kpx" 2>&1 )" || ERC=$?
[ "$ERC" -eq 3 ] || fail "a silent box did not abort with 3 (got $ERC): $ELOG"
ok "a box that answers neither PRESENT nor ABSENT aborts (exit 3), never guesses"

# 8f. a post-push verify LEG that answers nothing must fail the record, and name that leg.
#     The box is fine, the answer never arrives.  Fail-closed was never in doubt -- what
#     matters is a message that says WHICH question went unanswered, so the next occurrence
#     is diagnosable in one read.
cat > "$TMP/runner-dropleg.py" <<'PY'
import os, subprocess, sys
root = os.environ["STUBROOT"]
for cmd in sys.argv[1:]:
    quiet = "_EXPOK" in cmd                    # swallow exactly the EXP leg's answer
    cmd = cmd.replace("/usr/sys", root + "/usr/sys")
    p = subprocess.run(["sh", "-c", cmd], capture_output=True, text=True)
    if not quiet:
        sys.stdout.write(p.stdout); sys.stdout.write(p.stderr)
sys.exit(0)
PY
resetbox "$TMP/stock/aen.c"
ERC=0
ELOG="$( export STUBROOT="$BOX"
         kpatch_ensure_onbox "$TMP/runner-dropleg.py" "$TMP/pusher.py" "$TMP/ework" "$KT" "$TMP/conf-v2.patch" "$TMP/kpx" 2>&1 )" || ERC=$?
[ "$ERC" -eq 1 ] || fail "a verify leg that answered nothing did not fail the record (rc $ERC): $ELOG"
case "$ELOG" in *"EXP(no answer)"*) ok "an unanswered verify leg fails the record and is named: EXP(no answer)";;
  *) fail "the failure did not name the unanswered leg: $ELOG";; esac
case "$ELOG" in *"MARK(no answer)"*|*"STAMP(no answer)"*) fail "legs that DID answer were reported as failing too: $ELOG";; esac
ok "the legs that answered OK are not implicated"

echo "== 9. drift guards on the stock Makefiles =="
if [ "$HAVE_SYS" = 1 ]; then
  m="$AMIX_SYSTEM/usr/sys/amiga/driver/Makefile"
  [ -f "$m" ] || fail "$m is missing -- AMIX_SYSTEM is not a complete stock tree"
  grep -Eq '^aen/exp[[:space:]]*:[[:space:]]*$' "$m" \
    || fail "$m: the aen/exp rule now has prerequisites -- re-check whether exp= is still needed (and whether it is still SAFE)"
  ok "amiga/driver/Makefile still builds aen/exp from a rule with NO prerequisites (exp= still required)"
  m="$AMIX_SYSTEM/usr/sys/amiga/alien/Makefile"
  [ -f "$m" ] || fail "$m is missing -- AMIX_SYSTEM is not a complete stock tree"
  grep -Eq '^exp:[[:space:]]*\$\(OBJ\)' "$m" \
    || fail "$m: the alien exp rule no longer depends on \$(OBJ) -- its kpatch rows may now need an exp= too"
  ok "amiga/alien/Makefile still builds exp from \$(OBJ) (its rows correctly carry no exp=)"
else
  skip "the Makefile drift guards read the stock tree -- they need AMIX_SYSTEM"
fi
# and the conf itself: the aen row must still carry the option
grep -q 'amiga/driver/aen/aen.c.*exp=amiga/driver/aen/exp' "$CONF" \
  || fail "$CONF: the aen row lost its exp= option -- the aen fix goes back to never reaching the kernel"
ok "kernel-patches.conf: the aen row still carries exp=amiga/driver/aen/exp"

echo "== 12. every on-box line fits MAX_CANON, for every record in the real conf =="
# WHY THIS SECTION EXISTS.  The runner sends each command as ONE telnet tty line plus its
# own 16-byte "; echo D''ONE_$?"; SVR4 caps a canonical line at MAX_CANON = 256 bytes, so
# an over-long command never runs and answers nothing at all.  The post-push verify -- once
# a single `if <marker grep> && <stamp grep> && test ! -f <exp>` chain -- came to 260 bytes
# on the wire for the aen record and failed closed over a box that was in fact correctly
# patched.  Measuring is the only defence that survives somebody adding a record with a
# longer path, so it is measured here for EVERY record, against the REAL conf, at the
# worst-case revision width.
#
# Budget is on the WIRE length (command + the runner's suffix), which is the thing MAX_CANON
# actually caps -- not the command alone.
if [ "$HAVE_SYS" = 1 ]; then
kpatch_parse "$CONF" "$KT"
BUDGET_MAX=0; BUDGET_WORST=""
for i in "${!KP_TARGET[@]}"; do
  tgt="${KP_TARGET[$i]}"; mrk="${KP_MARKER[$i]}"; exp="${KP_EXP[$i]}"
  onbox="/usr/sys/$tgt"; ofile="${onbox%.c}.o"; stamp="$(kpatch_stamp_path "$onbox")"
  expabs=""; [ -z "$exp" ] || expabs="/usr/sys/$exp"
  # kpatch_rev is fixed-width (12 hex), so f-times-12 IS the worst case, not a guess.
  worstrev=ffffffffffff
  nlines=0
  while IFS= read -r c; do
    nlines=$((nlines + 1))
    w="$(kpatch_wire_len "$c")"
    [ "$w" -le "$KPATCH_LINE_BUDGET" ] \
      || fail "$tgt: an on-box line is $w bytes on the wire (budget $KPATCH_LINE_BUDGET, MAX_CANON $KPATCH_MAX_CANON): $c"
    [ "$w" -le "$BUDGET_MAX" ] || { BUDGET_MAX="$w"; BUDGET_WORST="$tgt: $c"; }
    # echo immunity: the command text must NOT contain the joined token, or the box's
    # echo of the command would read as a verdict (the split '' is what prevents it).
    case "$c" in *KPATCH_*) fail "$tgt: an on-box command carries a JOINED sentinel -- the echo would read as a result: $c";; esac
  done < <(kpatch_onbox_cmds "$onbox" "$mrk" "$stamp" "$worstrev" "$ofile" "$expabs")
  # 2 probe + 2 invalidate + 2 verify = 6 without exp=; the option adds one of each = 8.
  want=6; [ -z "$expabs" ] || want=8
  [ "$nlines" -eq "$want" ] \
    || fail "$tgt: kpatch_onbox_cmds emitted $nlines lines, expected $want -- the enumeration and the sender have drifted"
  ok "$tgt: $nlines on-box lines, all within the budget"
done
ok "worst wire line over the whole conf = $BUDGET_MAX bytes (budget $KPATCH_LINE_BUDGET, MAX_CANON $KPATCH_MAX_CANON) -- $BUDGET_WORST"
else
  skip "measuring every record of the real conf needs AMIX_SYSTEM (the conf does not parse without it)"
fi

# the guard has teeth: it must REFUSE a line over the budget, not just measure it
LONG="echo $(printf '%300s' '' | tr ' ' x)"
kpatch_line_budget_check "a selftest fixture" "$LONG" 2>/dev/null \
  && fail "kpatch_line_budget_check accepted a $(kpatch_wire_len "$LONG")-byte line"
kpatch_line_budget_check "a selftest fixture" "echo short" \
  || fail "kpatch_line_budget_check rejected a short line"
ok "kpatch_line_budget_check refuses an over-budget line and passes a short one"

echo "== 12b. the aen shape, exactly: the line that broke the verify =="
# The regression fixture is the REAL aen record's paths, so it goes stale only if that record
# does, and it asserts BOTH halves: the old shape really did overrun (the fixture is not
# vacuous) and the new per-leg shape really does fit.
if [ "$HAVE_SYS" = 1 ]; then
AENIDX=""
for i in "${!KP_TARGET[@]}"; do
  [ "${KP_TARGET[$i]}" = "amiga/driver/aen/aen.c" ] && { AENIDX="$i"; break; }
done
[ -n "$AENIDX" ] || fail "no amiga/driver/aen/aen.c record in $CONF -- this regression fixture is stale"
AMRK="${KP_MARKER[$AENIDX]}"; AEXP="${KP_EXP[$AENIDX]}"
[ -n "$AEXP" ] || fail "the aen record lost its exp= -- the three-leg verify shape is gone"
AONBOX="/usr/sys/${KP_TARGET[$AENIDX]}"; ASTAMP="$(kpatch_stamp_path "$AONBOX")"
AEXPABS="/usr/sys/$AEXP"
# The revision is always 12 hex, so the fixture's own $REV2 is length-exact for the real
# one -- and it is the revision the fixture box below is actually stamped with, so the box
# WOULD answer NOWOK and any silence is provably the transport's doing.
# The OLD single-chain command, reconstructed verbatim:
OLDCMD="if grep '$AMRK' $AONBOX >/dev/null 2>&1 && grep $REV2 $ASTAMP >/dev/null 2>&1 && test ! -f $AEXPABS; then echo KPATCH''_NOWOK; else echo KPATCH''_NOWBAD; fi"
OLDW="$(kpatch_wire_len "$OLDCMD")"
[ "$OLDW" -gt "$KPATCH_MAX_CANON" ] \
  || fail "the reconstructed old verify is only $OLDW bytes -- it no longer reproduces the overrun, so this fixture proves nothing"
ok "the old &&-chained verify is $OLDW bytes on the wire -- over MAX_CANON $KPATCH_MAX_CANON (defect reproduced)"
# and through the tty model it answers NOTHING -- neither token -- which is exactly what the
# failed runs saw.  The fixture box is put in the state that answers OK to all three legs --
# REAL marker in the source, the stamp written, no exp -- so a leg that stays silent below
# can only be the transport, never the box disagreeing.
resetbox "$TMP/v2.c"; printf '%s\n' "$AMRK" >> "$AENDIR/aen.c"
rm -f "$AENDIR/exp"; echo "$REV2" > "$STAMP"
OLDOUT="$( export STUBROOT="$BOX"; python3 "$TMP/runner.py" "$OLDCMD" )"
case "$OLDOUT" in *KPATCH_NOWOK*|*KPATCH_NOWBAD*) fail "the tty model delivered the old line: $OLDOUT";; esac
ok "over the tty model the old line answers neither NOWOK nor NOWBAD (the observed failure)"
# the MEASURED signature, both halves: nothing comes back at all -- there is no truncated
# echo and no bell to notice -- AND the session is wedged, so a following SHORT command that
# would otherwise answer is silent too.  The second half is what makes an over-long line
# look like a dead box rather than one bad command, and it is why the budget check runs
# before the FIRST box call of a record rather than per line.
[ -z "$OLDOUT" ] || fail "the over-long line produced output; the measured behaviour is silence: $(printf '%s' "$OLDOUT" | cat -v)"
ok "and it produces NO output at all -- no truncated echo, no bell (as measured)"
SHORT="$(kpatch_verify_cmds "$AONBOX" "$AMRK" "$ASTAMP" "$REV2" "$AEXPABS" | head -1)"; SHORT="${SHORT#* }"
WEDGED="$( export STUBROOT="$BOX"; python3 "$TMP/runner.py" "$OLDCMD" "$SHORT" )"
[ -z "$WEDGED" ] || fail "the session was not wedged: a command after the over-long one still answered: $WEDGED"
FRESH="$( export STUBROOT="$BOX"; python3 "$TMP/runner.py" "$SHORT" )"
case "$FRESH" in *KPATCH_MARKOK*) : ;; *) fail "the same short command does not answer in a FRESH session either -- the fixture proves nothing: $FRESH";; esac
ok "and it WEDGES the login: the next short command is silent too, yet answers on reconnect"
# the NEW shape: three legs, each its own short line, each answering
NLEGS=0
while IFS= read -r l; do
  NLEGS=$((NLEGS + 1))
  leg="${l%% *}"; c="${l#* }"
  w="$(kpatch_wire_len "$c")"
  [ "$w" -le "$KPATCH_LINE_BUDGET" ] || fail "aen verify leg $leg is $w bytes on the wire: $c"
  out="$( export STUBROOT="$BOX"; python3 "$TMP/runner.py" "$c" )"
  case "$out" in *"KPATCH_${leg}OK"*) : ;; *) fail "aen verify leg $leg did not answer OK over the tty model: $out";; esac
done < <(kpatch_verify_cmds "$AONBOX" "$AMRK" "$ASTAMP" "$REV2" "$AEXPABS")
[ "$NLEGS" -eq 3 ] || fail "the aen record's verify emitted $NLEGS legs, expected 3 (MARK, STAMP, EXP)"
ok "the new shape: 3 legs (MARK/STAMP/EXP), each under budget, each answering OK over the same model"
else
  skip "the aen regression fixture is built from the real conf's aen record -- it needs AMIX_SYSTEM"
fi
# a record with no exp= has two legs, not three
[ "$(kpatch_verify_cmds /usr/sys/a/b.c M /usr/sys/a/b.c.kprev cafe12345678 "" | wc -l)" -eq 2 ] \
  || fail "a record without exp= must emit exactly 2 verify legs"
ok "a record without exp= emits 2 legs (no EXP question to ask)"
# and kpatch_ensure_onbox refuses HOST-SIDE, before any box call, a record whose lines cannot fit
LONGTGT="amiga/driver/$(printf '%0180d' 0 | tr '0' 'd')/aen.c"
printf 'kpatch kpx patches/v2.patch %s %s %s\n' "$LONGTGT" "$MARK" "$TMP/stock/aen.c" > "$TMP/conf-long"
ERC=0
ELOG="$( export STUBROOT="$BOX"
         kpatch_ensure_onbox "$TMP/runner.py" "$TMP/pusher.py" "$TMP/ework" "$KT" "$TMP/conf-long" "$TMP/kpx" 2>&1 )" || ERC=$?
[ "$ERC" -eq 2 ] || fail "an over-budget record was not refused host-side (rc $ERC): $ELOG"
case "$ELOG" in *"too long"*"MAX_CANON"*) ok "an over-budget record is refused host-side (exit 2), naming the budget and MAX_CANON";;
  *) fail "the over-budget refusal does not explain itself: $ELOG";; esac

echo "== 13. the conf-vs-glob reconciliation for the GLOB-driven cross builder =="
# kpatch_always_extra is what stops a HOST CROSS kernel shipping without an `always:` patch
# while gating green on all four arms -- the one path where that was structurally possible.
# Fixture repos, so the branches are exercised on bytes we control rather than on whatever
# happens to be checked out.  The owning repo sits in a fixture drivers dir, found through
# AMIX_DRIVERS exactly as kernel/drivers/<name> is in a real build.
AL="$TMP/always"; ALKT="$AL/kt"; ALDRV="$AL/drivers"
mkdir -p "$ALKT" "$ALDRV/owner/src/kernel-patches" "$AL/dup/src/kernel-patches" \
         "$AL/stale/src/kernel-patches" "$AL/plain/src/kernel-patches" "$AL/stock"
printf 'a\nb\nc\n' > "$AL/stock/support.c"
printf 'a\nb\nc\n' > "$AL/stock/other.c"
# the boot-critical patch (an `always:` row) and a DIFFERENT patch to the SAME file
cp "$AL/stock/support.c" "$AL/good.c"; sed -i '2a A3KSCSI_PROBE' "$AL/good.c"
cp "$AL/stock/support.c" "$AL/old.c";  sed -i '2a A3KSCSI_SPOOFABLE' "$AL/old.c"
( cd "$AL" && diff -u stock/support.c good.c > drivers/owner/src/kernel-patches/support.c.patch || true )
( cd "$AL" && diff -u stock/support.c old.c  > stale/src/kernel-patches/support.c.patch || true )
sed -i 's#^+++ good.c#+++ amiga/kernel/support.c#; s#^--- stock/support.c#--- amiga/kernel/support.c#' \
    "$ALDRV/owner/src/kernel-patches/support.c.patch"
sed -i 's#^+++ old.c#+++ amiga/kernel/support.c#;  s#^--- stock/support.c#--- amiga/kernel/support.c#' \
    "$AL/stale/src/kernel-patches/support.c.patch"
cp "$ALDRV/owner/src/kernel-patches/support.c.patch" "$AL/dup/src/kernel-patches/support.c.patch"
# a CONDITIONAL row's patch, which must never be pulled in by this function
cp "$AL/stock/other.c" "$AL/other-new.c"; sed -i '2a OTHER_MARK' "$AL/other-new.c"
( cd "$AL" && diff -u stock/other.c other-new.c > plain/src/kernel-patches/other.c.patch || true )
sed -i 's#^+++ other-new.c#+++ amiga/alien/other.c#; s#^--- stock/other.c#--- amiga/alien/other.c#' \
    "$AL/plain/src/kernel-patches/other.c.patch"
{ printf 'kpatch always:owner src/kernel-patches/support.c.patch amiga/kernel/support.c A3KSCSI_PROBE %s\n' "$AL/stock/support.c"
  printf 'kpatch plain src/kernel-patches/other.c.patch amiga/alien/other.c OTHER_MARK %s\n' "$AL/stock/other.c"
} > "$AL/conf"
alx() { AERC=0; AOUT="$(AMIX_DRIVERS="$ALDRV" kpatch_always_extra "$AL/conf" "$ALKT" "$@" 2>"$TMP/alerr")" || AERC=$?; AERR="$(cat "$TMP/alerr")"; }

# (a) nothing offered: the `always:` row is emitted from its OWN repo, the plain row is not.
alx "$ALKT"
[ "$AERC" -eq 0 ] || fail "kpatch_always_extra failed with no dirs offered (rc $AERC): $AERR"
[ "$AOUT" = "$ALDRV/owner/src/kernel-patches/support.c.patch" ] \
  || fail "expected the always: row's patch, got: $AOUT"
ok "a build offering NO driver dirs still gets the always: patch (and not the conditional one)"

# and it is not merely NAMED -- applying it changes the tree, correctly.
mkdir -p "$AL/tree/amiga/kernel"; cp "$AL/stock/support.c" "$AL/tree/amiga/kernel/support.c"
( cd "$AL/tree" && patch -p0 -F0 --dry-run < "$AOUT" >/dev/null 2>&1 ) \
  || fail "the emitted patch does not apply -F0 to a stock tree"
( cd "$AL/tree" && patch -p0 -F0 < "$AOUT" >/dev/null 2>&1 ) || fail "the emitted patch failed to apply"
grep -q A3KSCSI_PROBE "$AL/tree/amiga/kernel/support.c" \
  || fail "the patched target does not carry the marker -- the emission is cosmetic"
cmp -s "$AL/stock/support.c" "$AL/tree/amiga/kernel/support.c" \
  && fail "the patched target is byte-identical to stock -- nothing was applied"
ok "and applying it really does change the target (marker present, bytes differ from stock)"

# (b) the owning repo IS in the build: the glob already supplies it -> emit NOTHING, so the
# build's patch list is unchanged.
alx "$ALKT" "$ALDRV/owner"
[ "$AERC" -eq 0 ] || fail "rc $AERC with the owning repo offered: $AERR"
[ -z "$AOUT" ] || fail "the owning repo was offered, yet the row was still emitted: $AOUT"
case "$AERR" in *"already supplied byte-identically"*) : ;;
  *) fail "the skip is not explained on stderr: $AERR";; esac
ok "with the owning repo in the build nothing extra is emitted (existing builds unchanged)"

# (c) a byte-identical copy under another name -- a patch-carrier dir -- counts too.
alx "$ALKT" "$AL/dup"
[ "$AERC" -eq 0 ] || fail "rc $AERC with a byte-identical carrier: $AERR"
[ -z "$AOUT" ] || fail "a byte-identical carrier still produced an emission: $AOUT"
ok "a byte-identical carrier copy is recognised as the same patch (no double-apply)"

# (d) a DIFFERENT patch to the same file -- the stale carrier -- is REFUSED, not resolved.
# Silently preferring either copy is how a superseded probe wins; that is the defect.
alx "$ALKT" "$AL/stale"
[ "$AERC" -eq 2 ] || fail "a stale carrier was not refused (rc $AERC): $AERR"
case "$AERR" in *CONFLICT*"amiga/kernel/support.c"*) : ;;
  *) fail "the conflict refusal does not name the file: $AERR";; esac
case "$AERR" in *"$AL/stale/src/kernel-patches/support.c.patch"*) : ;;
  *) fail "the conflict refusal does not name the offending copy: $AERR";; esac
ok "a carrier holding a DIFFERENT patch for the same file is refused, naming both copies"

# (e) the always: repo is not present at all -> hard refusal, same rule as on-box.
printf 'kpatch always:nosuchrepo src/kernel-patches/support.c.patch amiga/kernel/support.c A3KSCSI_PROBE %s\n' \
    "$AL/stock/support.c" > "$AL/conf-missing"
AERC=0; AERR="$(AMIX_DRIVERS="$ALDRV" kpatch_always_extra "$AL/conf-missing" "$ALKT" "$ALKT" 2>&1 >/dev/null)" || AERC=$?
[ "$AERC" -eq 2 ] || fail "a missing always: patch was not refused (rc $AERC): $AERR"
case "$AERR" in *"refusing to skip a boot-critical patch"*) : ;;
  *) fail "the missing-patch refusal does not say why: $AERR";; esac
ok "an always: row whose repo is absent is a hard refusal, never a silent skip"

# (g) keys match amix-insensitively: a driver repo may be a standalone amix-<name> checkout
# or kernel/drivers/<name>, and the conf key may be spelled either way.
[ "$(AMIX_DRIVERS="$ALDRV" kpatch_repo_dir always:amix-owner "$ALKT")" = "$ALDRV/owner" ] \
  || fail "always:amix-owner did not fall back to \$AMIX_DRIVERS/owner"
mkdir -p "$ALDRV/amix-both" "$ALDRV/both"
[ "$(AMIX_DRIVERS="$ALDRV" kpatch_repo_dir always:amix-both "$ALKT")" = "$ALDRV/amix-both" ] \
  || fail "always:amix-both did not prefer \$AMIX_DRIVERS/amix-both over .../both"
[ "$(kpatch_repo_dir amix-plain "$ALKT" "$AL/plain")" = "$AL/plain" ] \
  || fail "the key amix-plain did not match the driver dir plain"
[ "$(kpatch_repo_dir plain "$ALKT" "$AL/amix-plain")" = "$AL/amix-plain" ] \
  || fail "the key plain did not match the driver dir amix-plain"
kpatch_repo_dir amix-other "$ALKT" "$AL/plain" >/dev/null \
  && fail "the key amix-other matched an unrelated driver dir"
[ "$(kpatch_repo_dir kt "$ALKT")" = "$ALKT" ] || fail "the kt key (basename of the kt root) did not resolve to it"
ok "keys match amix-insensitively (both directions, always: fallback <key> then <key without amix->); the kt key is its basename"

# (f) the REAL conf against the REAL layout: every always: row resolves to the a4091 driver
# and is emitted for a build that names no driver dir.  This is the live tie to what ships.
if [ "$HAVE_SYS" != 1 ]; then
  skip "13f drives the real conf -- it needs AMIX_SYSTEM"
else
kpatch_parse "$CONF" "$KT"          # kpatch_always_extra above left the FIXTURE conf parsed
NALWAYS=0
for i in "${!KP_REPO[@]}"; do case "${KP_REPO[$i]}" in always:*) NALWAYS=$((NALWAYS+1));; esac; done
[ "$NALWAYS" -ge 1 ] || fail "$CONF has no always: rows -- section 13f proves nothing"
if [ -n "$A4091" ] && [ -d "$A4091/src/kernel-patches" ]; then
  AERC=0; AOUT="$(kpatch_always_extra "$CONF" "$KT" "$KT" 2>/dev/null)" || AERC=$?
  [ "$AERC" -eq 0 ] || fail "the real conf's always: rows cannot be honoured (rc $AERC)"
  [ "$(printf '%s\n' "$AOUT" | grep -c .)" -eq "$NALWAYS" ] \
    || fail "expected $NALWAYS always: patch(es) for a driver-less build, got: $AOUT"
  while IFS= read -r f; do [ -f "$f" ] || fail "emitted a path that is not a file: $f"; done <<< "$AOUT"
  ok "the real $( basename "$CONF" ): all $NALWAYS always: row(s) emitted for a build naming no driver dir"
  # and offering the a4091 driver makes every one of them a no-op again
  AOUT="$(kpatch_always_extra "$CONF" "$KT" "$KT" "$A4091" 2>/dev/null)" || fail "rc with the a4091 driver offered"
  [ -z "$AOUT" ] || fail "the a4091 driver was offered, yet rows were still emitted: $AOUT"
  ok "and offering $(basename "$A4091") makes all $NALWAYS a no-op (that build's output is unchanged)"
else
  skip "13f's live arm: the a4091 driver is not present under $DRVROOT (fixtures above still ran)"
fi
fi

echo "skipped: $SKIPS (see the SKIP lines above)"
echo "SELFTEST PASS"
