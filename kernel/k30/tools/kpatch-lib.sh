# kpatch-lib.sh -- shared helpers for the stock-kernel patches of kernel-patches.conf.
#
# The SINGLE definition of the kernel-patch grammar (kernel-patches.conf), plus two halves
# that use it:
#
#   * the HOST half -- kpatch_parse, kpatch_repo_dir, kpatch_patch_targets,
#     kpatch_always_extra, kpatch_apply_host, kpatch_rev, kpatch_check_exp, kpatch_excluded.
#     kernel/k30's cross build (build-cross-kernel.sh) uses only this half: it reconciles its
#     patch glob with the conf's `always:` rows through kpatch_always_extra.
#   * the ON-BOX half -- kpatch_ensure_onbox and its pure helpers (kpatch_probe_cmds,
#     kpatch_verify_cmds, kpatch_invalidate_cmds, kpatch_onbox_cmds, kpatch_line_budget_check,
#     kpatch_wire_len, kpatch_stamp_path): the flaky-patch-proof verify-then-apply that makes
#     a live box's /usr/sys carry every applicable patch before a kernel is gated.  The
#     on-box builders that call kpatch_ensure_onbox are not part of kernel/k30 yet; the code
#     is kept here so they never fork the grammar.  On an already-patched tree it is a pure
#     no-op; on a stock tree it applies the patches so the kernel still boots and mounts.
#
# Why not just run patch on the box: the on-box patch(1) is FLAKY (reversed-detection /
# silent no-apply), and an FTP GET of the stock >1KB is unreliable.  So instead we (a) PROBE
# a stable marker on-box (read-only grep) and, only if MISSING, (b) apply the driver-repo
# patch to a PRISTINE stock (from the AMIX_SYSTEM input) host-side with reliable GNU patch --
# always a forward apply, never the "Reversed (or previously applied)?" trap -- and PUSH the
# whole patched file (PUSH is reliable), then remove the matching .o so the gate recompiles
# it.  The driver-repo -p0 patch stays the source of truth; the stock is only the base.
#
# TWO THINGS THE MARKER ALONE CANNOT SAY:
#
#   * "the source is patched" is not "the patch is in the kernel".  Removing the sibling .o
#     forces a recompile only where the subsystem's own Makefile has real prerequisites.
#     amiga/driver/Makefile does NOT: `aen/exp :` (no prereqs) + `cd aen; $(MAKE)` means an
#     existing amiga/driver/aen/exp is NEVER rebuilt, so a patched aen.c reached the source
#     tree and never the linked kernel while the marker probe reported PRESENT forever.  A
#     record can therefore name the ONE subsystem exp to remove as well (`exp=` option) --
#     exactly that path, never a glob: over-broad exp deletion bricks the tree, because the
#     generic SVR4 exp blobs ship pre-linked with no source.
#   * a marker is a PRESENCE token, not a patch-version binding.  Revise a patch and keep
#     its marker and every box already carrying the old version silently no-ops.  The
#     patches themselves cannot carry a version -- most live in a driver repo kernel/k30 only
#     reads -- so the version binding lives BESIDE the target instead: <onbox-target>.kprev
#     holds a revision id derived from the patch + the pristine stock, i.e. from exactly the
#     bytes we would push.  Probe = marker present AND stamp matches.  A stampless box (any
#     tree patched before stamping existed) re-establishes the file from pristine stock once
#     and is stable after; that is the fail-closed answer to "we cannot tell which revision
#     this box carries".  No conf edit is needed for it -- the revision is derived, so it can
#     never go stale.
#
# A THIRD THING, and the reason every on-box line below is SHORT:
#
#   * MAX_CANON.  The telnet command runner drives a login, so each command is ONE canonical
#     tty line, and SVR4 caps a canonical line at MAX_CANON = 256 bytes.  A single
#     `if <marker grep> && <stamp grep> && test ! -f <exp>; then ...` verify chain came to
#     244 bytes on the aen record -- the only one with the extra exp= leg, and the longest
#     target path -- and 260 on the wire once the runner appends its own 16-byte
#     `; echo D''ONE_$?`.  The line never ran and the verify, seeing neither token, failed
#     closed over a box whose state was actually CORRECT.  Fail-closed is the right
#     behaviour; the bug was generating a line the transport cannot carry.
#
#     WHAT THE FAILURE LOOKS LIKE.  Measured on a real A4000 with a padding ladder: 229 bytes
#     on the wire answer normally, 269 answer NOTHING AT ALL -- no output, no marker, no
#     error -- and the LOGIN STAYS WEDGED, so every later command in that session also
#     answers nothing until the caller reconnects.  A trailing ^G in the echoed line
#     CONFIRMS an overrun when it is there; its ABSENCE proves nothing.  The practical tell
#     is the second symptom: once one line overruns, the rest of that session answers
#     nothing either.
#     So: every on-box line is a SHORT SINGLE QUESTION with its own split token, the
#     post-push verify is one command PER LEG with the verdict computed host-side from all
#     of them, and kpatch_ensure_onbox MEASURES every line it is about to send against a
#     240-byte wire budget and refuses host-side rather than letting a long conf record
#     mangle again.  The budget stays 240 (a wire line, so <=224 of command): nothing here
#     needs the last 16 bytes.
#
# Source this file, then call kpatch_always_extra (the GLOB-driven host cross builder) or
# kpatch_ensure_onbox (on-box builders) -- see kpatch_always_extra for why the two need
# different entry points.  Every function except kpatch_ensure_onbox is host-only and is
# exercised by the self-test (tools/kpatch-selftest.sh) without a box.

# ---------------------------------------------------------------- the wire budget --
# What the transport can carry, in one place, because three functions have to agree on it.
#   KPATCH_MAX_CANON      SVR4 canonical-input line cap (bytes).  Measured with a padding
#                         ladder: 229 bytes on the wire answer normally, 269 answer nothing
#                         and wedge the session until reconnect -- so 256 is the documented
#                         figure to design against and there is no margin above it.  Past the
#                         cap there is no partial result to salvage and no error to catch:
#                         see the MAX_CANON note above.
#   KPATCH_WIRE_SUFFIX_LEN  what the telnet command runner appends to EVERY command:
#                         `; echo D''ONE_$?` = 16.
#   KPATCH_LINE_BUDGET    what we allow on the wire (command + suffix).  16 bytes below
#                         MAX_CANON on purpose: markers and target paths come from
#                         kernel-patches.conf, which is data, and a budget with no headroom
#                         is a budget that fails on the next record somebody adds.
KPATCH_MAX_CANON=256
KPATCH_WIRE_SUFFIX_LEN=16
KPATCH_LINE_BUDGET=240

# kpatch_wire_len <command> -- bytes this command occupies as a tty line once the runner has
# appended its completion marker.  That total, not the command alone, is what MAX_CANON caps.
kpatch_wire_len() { printf '%s' "$(( ${#1} + KPATCH_WIRE_SUFFIX_LEN ))"; }

# kpatch_line_budget_check <what> <command>...
# 0 iff every command fits KPATCH_LINE_BUDGET on the wire; otherwise names each offender on
# stderr and returns 1.  Called before the first box call of a record, so an over-long line
# is a loud host-side refusal instead of a silent stall with a fail-closed verdict
# somewhere downstream -- and, since an overrun wedges the whole login (see the note at
# the top), instead of poisoning every remaining record of the build as well.
kpatch_line_budget_check() {
  local _what="$1"; shift
  local _c _n _bad=0
  for _c in "$@"; do
    _n="$(kpatch_wire_len "$_c")"
    [ "$_n" -le "$KPATCH_LINE_BUDGET" ] && continue
    _bad=1
    echo "kpatch: on-box command line too long for $_what -- $_n bytes on the wire" >&2
    echo "        (${#_c} of command + the runner's ${KPATCH_WIRE_SUFFIX_LEN}-byte completion suffix), budget" >&2
    echo "        $KPATCH_LINE_BUDGET, SVR4 MAX_CANON $KPATCH_MAX_CANON.  Past the cap the box does not answer at all --" >&2
    echo "        no output, no error, and the login stays WEDGED for every later command until it is" >&2
    echo "        reconnected (measured: 229 bytes answered, 269 stalled).  Split it:" >&2
    echo "        $_c" >&2
  done
  [ "$_bad" = 0 ]
}

# kpatch_parse <kernel-patches.conf-path> <kt-root>
# Populate parallel globals (arrays cleared then filled, one entry per record):
#   KP_REPO[]  KP_PATCHREL[]  KP_TARGET[]  KP_MARKER[]  KP_STOCK[] (absolute)  KP_EXP[]
# The stock column resolves three ways: an absolute path as is; `usr/sys/...` against
# $AMIX_SYSTEM (a checkout of amigaux/amix-system, the pristine Commodore tree); any other
# relative path against <kt-root> (the self-test's fixtures use that).
# Exits 2 on a malformed record, a `usr/sys/` stock with AMIX_SYSTEM unset, a
# missing/!readable stock, or a bad option.
# A missing kernel-patches.conf is NOT an error (zero records -- callers stay inert,
# exactly like a build with no matching driver repo).
kpatch_parse() {
  local _conf="$1" _kt="$2"
  KP_REPO=() KP_PATCHREL=() KP_TARGET=() KP_MARKER=() KP_STOCK=() KP_EXP=()
  [ -f "$_conf" ] || return 0
  local kw repo prel tgt mrk srel opts o expv
  while read -r kw repo prel tgt mrk srel opts; do
    [ "$kw" = kpatch ] || { echo "kernel-patches.conf: record must start with 'kpatch' (got '$kw'): $kw $repo" >&2; exit 2; }
    [ -n "$repo" ] && [ -n "$prel" ] && [ -n "$tgt" ] && [ -n "$mrk" ] && [ -n "$srel" ] || {
      echo "kernel-patches.conf: incomplete record (need: kpatch <repo> <patch-rel> <onbox-target> <marker> <stock> [key=value ...])" >&2; exit 2; }
    case "$srel" in
      /*) : ;;
      usr/sys/*)
        [ -n "${AMIX_SYSTEM:-}" ] || {
          echo "kpatch $repo: stock '$srel' is a path in the AMIX_SYSTEM input, but AMIX_SYSTEM is not set (from $_conf)" >&2
          echo "  Set AMIX_SYSTEM to a checkout of amigaux/amix-system (the pristine stock tree)." >&2
          exit 2; }
        srel="$AMIX_SYSTEM/$srel" ;;
      *) srel="$_kt/$srel" ;;
    esac
    [ -f "$srel" ] || { echo "kpatch $repo: stock fixture not found: $srel (from $_conf)" >&2; exit 2; }
    expv=""
    # trailing key=value options.  Deliberately word-split; an unknown key is a hard error
    # rather than a silently ignored typo -- a mis-spelled `exp=` would restore the bug it
    # exists to close, and nothing downstream would notice.
    for o in ${opts:-}; do
      case "$o" in
        exp=*)
          expv="${o#exp=}"
          kpatch_check_exp "$expv" || {
            echo "kernel-patches.conf: bad exp= value '$expv' for $repo/$tgt -- must be a single" >&2
            echo "  path relative to /usr/sys ending in /exp, with no glob character and no '..'." >&2
            echo "  (Over-broad exp deletion bricks the tree: the generic SVR4 exp blobs ship" >&2
            echo "  pre-linked with no source.  Name exactly one subsystem exp, never a pattern.)" >&2
            exit 2; } ;;
        *) echo "kernel-patches.conf: unknown option '$o' on the $repo/$tgt record (known: exp=)" >&2; exit 2 ;;
      esac
    done
    KP_REPO+=("$repo"); KP_PATCHREL+=("$prel"); KP_TARGET+=("$tgt"); KP_MARKER+=("$mrk")
    KP_STOCK+=("$srel"); KP_EXP+=("$expv")
  done < <(grep -Ev '^[[:space:]]*(#|$)' "$_conf")
}

# kpatch_check_exp <value> -- 0 iff <value> is a single subsystem exp path relative to
# /usr/sys.  The whole point is that it can never widen: no absolute path (which would
# escape /usr/sys), no `..`, no glob metacharacter, and it must end in /exp.
kpatch_check_exp() {
  case "${1:-}" in
    "")                          return 1 ;;
    /*)                          return 1 ;;
    *..*)                        return 1 ;;
    *"*"*|*"?"*|*"["*|*"]"*)     return 1 ;;
    *[[:space:]]*)               return 1 ;;
    exp)                         return 1 ;;   # bare `exp` = the WHOLE amiga tree's blob
    */exp)                       return 0 ;;
    *)                           return 1 ;;
  esac
}

# kpatch_rev <patchfile> <stockfile> -- the revision id stamped on the box: 12 hex digits
# over the patch AND the pristine stock, i.e. over exactly the inputs that determine the
# bytes we would push.  Revise either and the id moves, so a box carrying the previous
# version stops reading as up to date.  Regex-clean (hex) so the on-box probe can be a
# plain `grep`.
kpatch_rev() {
  local _p="$1" _s="$2" _h=""
  if   command -v sha1sum >/dev/null 2>&1; then _h="$(cat "$_p" "$_s" | sha1sum | cut -c1-12)"
  elif command -v shasum  >/dev/null 2>&1; then _h="$(cat "$_p" "$_s" | shasum  | cut -c1-12)"
  elif command -v openssl >/dev/null 2>&1; then _h="$(cat "$_p" "$_s" | openssl dgst -sha1 | sed 's/.*[ =]//' | cut -c1-12)"
  fi
  case "$_h" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) echo "kpatch: cannot derive a revision id for $(basename "$_p") (no sha1sum/shasum/openssl?)" >&2; return 1 ;;
  esac
  printf '%s' "$_h"
}

# kpatch_stamp_path <onbox-target-abs> -- where that target's revision id lives on the box.
# A sibling of the source file, inert to every Makefile here (all the OBJ lists are explicit)
# and invisible to the package database, so it changes no installed-object digest.
kpatch_stamp_path() { printf '%s.kprev' "$1"; }

# kpatch_invalidate_cmds <ofile> <exp-abs-or-empty> <stamp> <rev>
# The on-box commands that make a pushed patch actually reach the linked kernel, one per
# line.  Pure, so the self-test can assert them literally -- the property that matters is
# that the exp removal names ONE file and contains no glob.
kpatch_invalidate_cmds() {
  local _ofile="$1" _exp="$2" _stamp="$3" _rev="$4"
  printf 'rm -f %s\n' "$_ofile"
  [ -z "$_exp" ] || printf 'rm -f %s\n' "$_exp"
  printf 'echo %s > %s\n' "$_rev" "$_stamp"
}

# kpatch_probe_cmds <onbox-target-abs> <marker> <stamp> <rev>
# The read-only BEFORE state, one short question per line: is the marker there at all, and
# is the revision on the box this one.  Pure.
#
# Every sentinel here is SPLIT with '' (KPATCH''_PRESENT).  The runner drives a telnet
# login, so the command line is echoed back by the box's tty into the same stream as its
# output; the remote sh joins the halves, so the assembled token exists only in the OUTPUT
# and the echo can never be mistaken for a result.  (Same trick as the runner's own
# D''ONE_$?.)  `case` on the collected output rather than `printf | grep -q`: under the
# callers' `set -o pipefail` a grep -q that exits on the first match can SIGPIPE its feeder
# and poison the pipeline status.
kpatch_probe_cmds() {
  local _onbox="$1" _mrk="$2" _stamp="$3" _rev="$4"
  printf "if grep '%s' %s >/dev/null 2>&1; then echo KPATCH''_PRESENT; else echo KPATCH''_ABSENT; fi\n" "$_mrk" "$_onbox"
  printf "if grep %s %s >/dev/null 2>&1; then echo KPATCH''_REVOK; else echo KPATCH''_REVBAD; fi\n" "$_rev" "$_stamp"
}

# kpatch_verify_cmds <onbox-target-abs> <marker> <stamp> <rev> <exp-abs-or-empty>
# The post-push verification, as "<LEG> <command>" per line -- ONE SHORT COMMAND PER LEG,
# each answering exactly one question with its own split token.  Pure.
#
# It is one command per leg for a measured reason: the single `&&`-chained form this
# replaces was 260 bytes on the wire for the aen record and never ran, so the verify got no
# token and failed closed over a correctly-patched box (see the MAX_CANON note at the top).
# Splitting also buys the diagnosis for free -- the failure now names WHICH leg missed, and
# distinguishes "the box said BAD" from "the box said nothing".
#
# The leg name is the first word and is also the token infix: leg MARK answers
# KPATCH_MARKOK / KPATCH_MARKBAD.  One naming rule, so a caller that knows the leg names
# knows the tokens and nothing has to be kept in sync by hand.
kpatch_verify_cmds() {
  local _onbox="$1" _mrk="$2" _stamp="$3" _rev="$4" _exp="$5"
  printf "MARK if grep '%s' %s >/dev/null 2>&1; then echo KPATCH''_MARKOK; else echo KPATCH''_MARKBAD; fi\n" "$_mrk" "$_onbox"
  printf "STAMP if grep %s %s >/dev/null 2>&1; then echo KPATCH''_STAMPOK; else echo KPATCH''_STAMPBAD; fi\n" "$_rev" "$_stamp"
  [ -z "$_exp" ] || printf "EXP if test ! -f %s; then echo KPATCH''_EXPOK; else echo KPATCH''_EXPBAD; fi\n" "$_exp"
}

# kpatch_onbox_cmds <onbox-target-abs> <marker> <stamp> <rev> <ofile> <exp-abs-or-empty>
# EVERY line this library sends to the box for one record, bare (no leg prefix), one per
# line.  The single enumeration point: the budget check and the self-test both walk this, so
# a new on-box line that is not emitted here is a line nothing measures -- which is exactly
# how a 260-byte verify shipped.
kpatch_onbox_cmds() {
  local _onbox="$1" _mrk="$2" _stamp="$3" _rev="$4" _ofile="$5" _exp="$6" _l
  kpatch_probe_cmds "$_onbox" "$_mrk" "$_stamp" "$_rev"
  kpatch_invalidate_cmds "$_ofile" "$_exp" "$_stamp" "$_rev"
  while IFS= read -r _l; do printf '%s\n' "${_l#* }"; done \
    < <(kpatch_verify_cmds "$_onbox" "$_mrk" "$_stamp" "$_rev" "$_exp")
}

# kpatch_repo_dir <repo> <kt-root> [driver-dir]...
# Resolve a record's <driver-repo> key to the directory its <patch-rel> is relative to,
# echoing that directory (returns 1, echoing nothing, when the record does not apply to
# this build).  A driver dir matches a key when their basenames are equal after stripping a
# leading `amix-` from both (the key `amix-a4091` matches kernel/drivers/a4091 as well as a
# standalone amix-a4091 checkout).  Three cases:
#   * KERNEL/K30 ITSELF is a valid key: the basename of <kt-root> (`k30`).  kernel/k30 is
#     part of EVERY build, so a record keyed to it ALWAYS applies -- that is how a patch to
#     a STOCK driver, one that no driver repo owns (amiga/driver/aen/aen.c is linked into
#     every Amix kernel whether or not an A2065 is fitted), rides every kernel.  Its patches
#     live under the SAME src/kernel-patches/ convention the driver repos use, so every
#     consumer treats kernel/k30 as just one more patch-carrying repo that happens to always
#     be selected.
#   * `always:<repo>` -- APPLIES TO EVERY BUILD, but the patch still lives in, and stays
#     owned by, <repo>.  This is for a fix to a STOCK driver that no driver repo owns yet
#     whose patch was written inside one: amiga/alien/a3091.c is the A3000 ONBOARD SCSI
#     driver -- nothing to do with the A4091 card -- but its chip-mem bounce patch lives
#     in amix-a4091 because that repo did the work.  Keying it plainly to `amix-a4091`
#     made a BOOT-CRITICAL patch conditional on which unrelated third-party SCSI driver
#     happened to be in the build, which is what silently produced an unbootable
#     z3660scsi+cdfs kernel.  The alternative -- copying the patch into kernel/k30 and
#     keying it `k30` -- would DOUBLE-APPLY it in the glob-driven builders, which glob
#     every *.patch in each given dir's src/kernel-patches/ and hard-fail on the resulting
#     reject.  So the patch stays in one place and only the applies-when rule moves.
#     When <repo> is not among this build's driver dirs, it is looked up in
#     ${AMIX_DRIVERS:-<kt-root>/../drivers}/ as <repo>, then as <repo without amix->.
#     COST, stated plainly: an `always:` record makes <repo> a HARD REQUIREMENT of every
#     build -- kpatch_ensure_onbox and kpatch_always_extra exit 2 if the patch file is not
#     there.  That is deliberate; a boot-critical patch must never be silently skipped.
#   * any other key matches only when a driver dir of that basename is in this build.
kpatch_repo_dir() {
  local repo="$1" kt="$2"; shift 2
  local d b drv
  case "$repo" in
    always:*)
      # unconditional: resolve <repo> the same way, but fall back to the drivers directory
      # when it is not among this build's driver dirs.
      repo="${repo#always:}"
      [ "$repo" = "$(basename "$kt")" ] && { printf '%s' "$kt"; return 0; }
      for d in "$@"; do
        b="$(basename "$d")"
        [ "${b#amix-}" = "${repo#amix-}" ] && { printf '%s' "$d"; return 0; }
      done
      drv="${AMIX_DRIVERS:-$kt/../drivers}"
      [ -d "$drv/$repo" ] && { printf '%s' "$drv/$repo"; return 0; }
      printf '%s' "$drv/${repo#amix-}"; return 0 ;;
  esac
  [ "$repo" = "$(basename "$kt")" ] && { printf '%s' "$kt"; return 0; }
  for d in "$@"; do
    b="$(basename "$d")"
    [ "${b#amix-}" = "${repo#amix-}" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

# kpatch_patch_targets <patchfile> -- the files a -p0 unified diff WRITES, one per line
# (the "+++ " targets; a /dev/null target is skipped).  Pure, no side effects.  It is how
# kpatch_always_extra tells "another copy of the same fix" from "a DIFFERENT patch to the
# same file", which are the two things a glob cannot distinguish.
kpatch_patch_targets() {
  awk '/^\+\+\+ /{ if ($2 != "/dev/null") print $2 }' "$1"
}

# kpatch_excluded <kt-root> <repo-basename> [<exclude-conf>]
# 0 (and the reason on stdout) when <repo-basename> is listed in bundle-exclude.conf -- a
# driver repo that carries a driver.conf but must not be bundled by discovery; 1 otherwise.
# Comments and blank lines are ignored; the first field is the basename, the rest the
# reason.  A missing exclude file excludes nothing.  Builders that name their driver dirs
# explicitly are not filtered.
kpatch_excluded() {
  local _kt="$1" _repo="$2" _conf="${3:-$1/bundle-exclude.conf}" _n _why
  [ -f "$_conf" ] || return 1
  while read -r _n _why; do
    case "$_n" in ''|'#'*) continue ;; esac
    [ "$_n" = "$_repo" ] && { printf '%s\n' "${_why:-(no reason given)}"; return 0; }
  done < "$_conf"
  return 1
}

# kpatch_always_extra <conf> <kt-root> <patch-source-dir>...
# The `always:` records of <conf> that a glob over <patch-source-dir>.../src/kernel-patches/
# *.patch does NOT already supply, echoed one ABSOLUTE patch path per line in conf order.
# Notes go to stderr; stdout is only the list.  Returns 2 (having said why) when the conf
# cannot be honoured -- see the three answers below.
#
# WHY THIS EXISTS.  The on-box builders drive kernel-patches.conf, so an `always:` row rides
# every kernel they build whether or not its owning repo is in that build -- that is the
# whole point of the prefix (kpatch_repo_dir's second case).  The HOST CROSS builder is
# GLOB-driven: build-cross-kernel.sh applies every *.patch it finds in the dirs it was
# handed and, before this function, never read the conf, so it was structurally blind to
# `always:`.  That is the one path where a kernel that should carry a boot-critical patch
# can ship WITHOUT it and still gate green -- undef 0, checkunix clean, relsim 0, and stock
# support.c inside.  A hand-made carrier dir whose only job is to make the glob see those
# patches is unversioned local state that is easy to lose or get wrong; this function
# replaces it.
#
# THE SPLIT OF AUTHORITY, stated once: the GLOB keeps deciding the CONDITIONAL rows -- a repo
# in the build brings its own patches, including ones the conf deliberately excludes -- and
# the CONF decides the UNCONDITIONAL ones.  Neither rule is subordinate; they cover different
# questions, and this function is only the reconciliation between them.
#
# Three answers per `always:` row, and only the first is a no-op:
#   * a globbed patch is BYTE-IDENTICAL to the row's patch -> already supplied, skipped.
#     This is the ordinary case for a build that passes the owning repo and for a
#     byte-identical carrier, and it is what keeps those builds' output UNCHANGED.
#   * a globbed patch writes the SAME target with DIFFERENT bytes -> REFUSE, naming both
#     files.  That is a stale or forked copy: applying both would double-apply (the -F0
#     dry-run turns that into a hard build failure anyway) and picking either one silently is
#     precisely how a superseded probe wins.  A caller who wants the copy must make it match.
#   * otherwise -> emitted, for the caller to apply after its own glob.
# A missing patch file for an `always:` row is a hard failure, the same rule
# kpatch_ensure_onbox enforces: a boot-critical patch is never silently skipped.
kpatch_always_extra() {
  local _conf="$1" _kt="$2"; shift 2
  local _dirs=("$@")
  kpatch_parse "$_conf" "$_kt"
  [ "${#KP_REPO[@]}" -gt 0 ] || return 0
  # flatten the caller's glob ONCE -- this must be the same rule the caller applies, so it
  # is stated here as the caller's dirs, not re-derived from the conf.
  local -a _have=()
  local _d _p _i _repo _dir _abs _t _o _dup
  for _d in ${_dirs[@]+"${_dirs[@]}"}; do
    [ -d "$_d/src/kernel-patches" ] || continue
    shopt -s nullglob; _have+=( "$_d"/src/kernel-patches/*.patch ); shopt -u nullglob
  done
  for _i in "${!KP_REPO[@]}"; do
    _repo="${KP_REPO[$_i]}"
    case "$_repo" in always:*) ;; *) continue ;; esac
    _dir="$(kpatch_repo_dir "$_repo" "$_kt" ${_dirs[@]+"${_dirs[@]}"} || true)"
    _abs="$_dir/${KP_PATCHREL[$_i]}"
    if [ ! -f "$_abs" ]; then
      echo "kpatch: patch not found: $_abs (from $_conf)" >&2
      echo "kpatch: that record is 'always:' -- ${_repo#always:} must be present (a driver dir of the build, or under \${AMIX_DRIVERS:-kernel/drivers}) for ANY kernel build; refusing to skip a boot-critical patch" >&2
      return 2
    fi
    _dup=""
    for _p in ${_have[@]+"${_have[@]}"}; do
      cmp -s "$_abs" "$_p" && { _dup="$_p"; break; }
    done
    if [ -n "$_dup" ]; then
      echo "kpatch: $_repo ${KP_PATCHREL[$_i]} -- already supplied byte-identically by $_dup" >&2
      continue
    fi
    while IFS= read -r _t; do
      for _p in ${_have[@]+"${_have[@]}"}; do
        while IFS= read -r _o; do
          [ "$_o" = "$_t" ] || continue
          echo "kpatch: CONFLICT on $_t -- two DIFFERENT patches write that file:" >&2
          echo "          from the glob: $_p" >&2
          echo "          from the conf: $_abs  ($_repo)" >&2
          echo "        Refusing.  Applying both double-applies (the -F0 dry-run would hard-fail); applying" >&2
          echo "        either one silently is how a superseded copy wins -- which is the defect this check" >&2
          echo "        exists to close.  Make the copy byte-identical, or drop it from the build." >&2
          return 2
        done < <(kpatch_patch_targets "$_p")
      done
    done < <(kpatch_patch_targets "$_abs")
    printf '%s\n' "$_abs"
  done
  return 0
}

# kpatch_apply_host <patchfile> <stockfile> <outfile> <marker>
# Reconstruct the patched target host-side: copy the PRISTINE stock, apply the driver-repo
# patch FORWARD with reliable GNU patch, and assert the marker appears.  -N makes an
# already-applied patch a no-op instead of an interactive "Reversed?" prompt (defensive --
# the stock is pristine so it never triggers); the post-apply marker grep catches any
# patch/stock mismatch.  Returns non-zero (never prompts, never hangs) on any failure.
kpatch_apply_host() {
  local patchfile="$1" stock="$2" out="$3" marker="$4"
  [ -f "$patchfile" ] || { echo "kpatch: patch not found: $patchfile" >&2; return 1; }
  [ -f "$stock" ]     || { echo "kpatch: stock not found: $stock" >&2; return 1; }
  cp "$stock" "$out"  || return 1
  if ! patch -s -N --no-backup-if-mismatch "$out" < "$patchfile"; then
    echo "kpatch: HOST patch FAILED: $(basename "$patchfile") onto $(basename "$stock")" >&2; return 1
  fi
  if ! grep -q "$marker" "$out"; then
    echo "kpatch: marker '$marker' ABSENT after patching $(basename "$out") (patch/stock mismatch?)" >&2; return 1
  fi
  return 0
}

# kpatch_ensure_onbox <cmd-runner> <file-pusher> <work-dir> <kt-root> <conf> <driver-dir>...
# The on-box half (its callers, the on-box kernel builders, are not part of kernel/k30 yet).
# <cmd-runner> is the telnet command runner: `python3 <cmd-runner> <cmd>...` runs each
# command on the box in one login, appending `; echo D''ONE_$?` to each, and always exits 0.
# <file-pusher> is run as `python3 <file-pusher> push <local> <remote>`.
# For every kernel-patches.conf record whose <driver-repo> resolves for this build (a
# passed driver dir, OR kernel/k30 itself -- see kpatch_repo_dir), ensure
# /usr/sys/<onbox-target> carries the patch before the gate.  Read-only PROBE first;
# apply (host-patch + push + rm .o) only when the marker is ABSENT; verify the post-condition.
# Fully inert (no box calls) when no record matches.  NOTE: a `k30`-keyed record always
# matches, so this is not a zero-box-call no-op for builds with no driver-repo match --
# it costs two read-only greps per such record, and stays a pure no-op on a tree whose
# .kprev stamps match.  A tree patched BEFORE stamping existed re-establishes each patched
# file from pristine stock exactly once (see the revision note at the top) and is a no-op
# after.
kpatch_ensure_onbox() {
  local amixsh="$1" amixsync="$2" work="$3" kt="$4" conf="$5"; shift 5
  local dirs=("$@")
  kpatch_parse "$conf" "$kt"
  [ "${#KP_REPO[@]}" -gt 0 ] || return 0
  local i repo matchdir prel tgt mrk stock patchabs onbox ofile base out probe post
  local exprel expabs stamp rev why v leg bad
  local -a cmds=() allcmds=() vlegs=() vnames=() vcmds=()
  local checked=0 applied=0
  for i in "${!KP_REPO[@]}"; do
    repo="${KP_REPO[$i]}"
    matchdir="$(kpatch_repo_dir "$repo" "$kt" ${dirs[@]+"${dirs[@]}"} || true)"
    [ -n "$matchdir" ] || continue        # this record's repo isn't in this build -> skip
    prel="${KP_PATCHREL[$i]}"; tgt="${KP_TARGET[$i]}"; mrk="${KP_MARKER[$i]}"; stock="${KP_STOCK[$i]}"
    patchabs="$matchdir/$prel"
    [ -f "$patchabs" ] || {
      echo "kpatch: patch not found: $patchabs (from $conf)" >&2
      case "$repo" in always:*) echo "kpatch: that record is 'always:' -- ${repo#always:} must be present (a driver dir of the build, or under \${AMIX_DRIVERS:-kernel/drivers}) for ANY kernel build; refusing to skip a boot-critical patch" >&2 ;; esac
      exit 2; }
    onbox="/usr/sys/$tgt"; ofile="${onbox%.c}.o"; base="$(basename "$tgt")"
    exprel="${KP_EXP[$i]}"; expabs=""
    [ -z "$exprel" ] || expabs="/usr/sys/$exprel"
    stamp="$(kpatch_stamp_path "$onbox")"
    rev="$(kpatch_rev "$patchabs" "$stock")" || exit 2
    checked=$((checked + 1))
    echo "kpatch: ensuring $onbox carries $(basename "$patchabs") (marker '$mrk', rev $rev) ..."
    # --- budget: refuse HOST-SIDE anything the tty cannot carry, before the first box call ---
    # kernel-patches.conf is data: a longer target path or marker can push a generated line
    # past MAX_CANON, where the box answers nothing and the login wedges for the rest of the
    # run.  Measure every line of this record up front and say so, rather than meeting it as
    # an unexplained fail-closed verdict mid-build -- or as a build that simply goes quiet.
    mapfile -t allcmds < <(kpatch_onbox_cmds "$onbox" "$mrk" "$stamp" "$rev" "$ofile" "$expabs")
    kpatch_line_budget_check "the $tgt record of $conf" "${allcmds[@]}" || exit 2
    # --- verify: read-only probes with explicit split sentinels (never on-box patch) ---
    mapfile -t cmds < <(kpatch_probe_cmds "$onbox" "$mrk" "$stamp" "$rev")
    probe="$(python3 "$amixsh" "${cmds[@]}" 2>/dev/null || true)"
    why=""
    case "$probe" in
      *KPATCH_PRESENT*)
        case "$probe" in
          *KPATCH_REVOK*)
            echo "  present -- $base already carries rev $rev on-box (no-op)"
            continue ;;
        esac
        why="marker present but NO matching revision stamp"
        echo "  $why -- '$mrk' is in $base, yet $(basename "$stamp") does not say $rev."
        echo "    A marker is a presence token, not a version: a REVISED patch keeps the same"
        echo "    marker and would no-op behind it forever.  Re-establishing from pristine stock." ;;
      *KPATCH_ABSENT*)
        why="marker absent"
        echo "  absent -- reconstructing patched $base host-side + pushing (stock-tree safety net)" ;;
      *)
        echo "kpatch: could not determine on-box state of $onbox (box comms?). Aborting rather than guessing:" >&2
        printf '%s\n' "$probe" >&2
        exit 3 ;;
    esac
    # --- apply: host-patch the pristine stock (reliable GNU patch) + push the whole file ---
    mkdir -p "$work/kpatch"
    out="$work/kpatch/$base"
    kpatch_apply_host "$patchabs" "$stock" "$out" "$mrk" || exit 1
    python3 "$amixsync" push "$out" "$onbox"
    # Invalidate what the build would otherwise reuse -- the sibling .o, and (only when the
    # record says so) the ONE subsystem exp whose Makefile rule has no prerequisites and so
    # would never be rebuilt -- then stamp the revision, then re-verify all of it.
    mapfile -t cmds < <(kpatch_invalidate_cmds "$ofile" "$expabs" "$stamp" "$rev")
    # One SHORT command per verification leg (see kpatch_verify_cmds): the &&-chained single
    # line this replaces overran MAX_CANON on the aen record and came back empty.
    mapfile -t vlegs < <(kpatch_verify_cmds "$onbox" "$mrk" "$stamp" "$rev" "$expabs")
    vnames=(); vcmds=()
    for v in "${vlegs[@]}"; do vnames+=("${v%% *}"); vcmds+=("${v#* }"); done
    post="$(python3 "$amixsh" "${cmds[@]}" "${vcmds[@]}" 2>/dev/null || true)"
    # A leg passes ONLY on its own OK token.  Nothing at all -- a dropped line, a mangled
    # line, a dead session -- is a failure, same as an explicit BAD: this stays fail-closed.
    bad=""
    for leg in "${vnames[@]}"; do
      case "$post" in *"KPATCH_${leg}OK"*) continue ;; esac
      case "$post" in
        *"KPATCH_${leg}BAD"*) bad="$bad $leg(said BAD)" ;;
        *)                    bad="$bad $leg(no answer)" ;;
      esac
    done
    if [ -n "$bad" ]; then
      echo "kpatch: post-push verify FAILED for $onbox -- leg(s):$bad" >&2
      echo "        MARK  -- '$mrk' must be present in $onbox" >&2
      echo "        STAMP -- $stamp must say $rev" >&2
      [ -z "$expabs" ] || echo "        EXP   -- $expabs must be gone" >&2
      echo "        'no answer' means the box returned neither token for that leg: the" >&2
      echo "        command did not run.  An over-long line looks EXACTLY like this -- it" >&2
      echo "        answers nothing and then wedges the login, so every leg after it is silent" >&2
      echo "        too; a trailing ^G in the echo below confirms an overrun but is often" >&2
      echo "        absent.  MAX_CANON is $KPATCH_MAX_CANON and the budget here is $KPATCH_LINE_BUDGET; every line was" >&2
      echo "        measured before the first box call, so if they all fit, suspect the box." >&2
      printf '%s\n' "$post" >&2
      exit 1
    fi
    echo "  applied ($why) -- pushed patched $base, removed $(basename "$ofile")${expabs:+ + $exprel}, stamped rev $rev"
    applied=$((applied + 1))
  done
  [ "$checked" -eq 0 ] || echo "kpatch: $checked target(s) checked, $applied applied ($((checked - applied)) already present)"
}
