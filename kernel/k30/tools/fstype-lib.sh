# fstype-lib.sh -- shared fstype staging helpers for the Amix kernel builders.
#
# The SINGLE definition of the `fstype` grammar + on-box staging, sourced by every
# builder so they never fork it:
#   * build-cross-kernel.sh  (host cross-link)  -- fstype_parse only
#   * an on-box builder      (relinks on a running Amix box; not part of this repo)
#                                               -- fstype_parse + fstype_stage_onbox
# Source this file, then call fstype_parse, and (for an on-box builder) fstype_stage_onbox.
#
#     fstype_parse <fstypes.conf-path> <kt-root>
#
# Grammar (one record per line; blank lines and '#' comments ignored):
#     fstype <name> <init-func> <exp-source-path> [flags] [md5=<32-hex>]
#   <name>            vfssw[] name string + the fs/<name>/ staging dir (e.g. cdfs)
#   <init-func>       the vsw_init routine the exp exports (e.g. cdfsinit)
#   <exp-source-path> the prebuilt `ld -r` relocatable to stage as fs/<name>/exp.
#                     The cross-repo CONTRACT -- staged verbatim, never compiled from
#                     source.  Resolved as:
#                       $CDFS/<rest>  -> "$CDFS/<rest>", CDFS being the environment
#                                        variable naming a built amix-cdfs checkout
#                                        (the literal text `$CDFS/` in the conf; read
#                                        with `read -r`, never shell-expanded).  Exit 2
#                                        when CDFS is unset or empty.
#                       /<abs>        -> used as is
#                       anything else -> relative to <kt-root>
#   [flags]           reserved (parsed + carried, not yet consumed); default 0
#   [md5=<32-hex>]    OPTIONAL exp PROVENANCE PIN.  When present, fstype_parse
#                     md5sums the exp-source and REFUSES the build (exit 2) unless
#                     it matches -- and a malformed pin value is refused outright,
#                     because a typo'd pin that silently un-pins is worse than none.
#                     Pin or no pin, the staged object's identity (md5 + size +
#                     sum -r) is ALWAYS printed, so every build log records exactly
#                     which exp went into the link.  Why: the path alone names no
#                     revision.  A provider checkout once sat on an unvalidated branch,
#                     several kernels silently linked the object at the same path, and
#                     one panicked on a cdfs remount.  Update the pin ONLY when
#                     deliberately adopting a new proven artifact.
#
# On return it has (re)populated these globals -- arrays cleared then filled, one entry
# per ACTIVE record:
#   FS_NAMES[]  FS_INITS[]  FS_EXPS[] (absolute)  FS_FLAGS[]
#   FS_EXTERNS  -- "extern int <init>();\n" per record   (filesys.c injection)
#   FS_VFSSW    -- "\t{ \"<name>\", <init>, 0, 0 },\n" per record
# Exits 2 on a malformed record, a $CDFS/ record with CDFS unset, or a missing exp-source
# file.  A missing fstypes.conf is NOT an error (zero records -- callers stay inert,
# exactly like the SCSI/net paths); neither is /dev/null, which is how
# build-cross-kernel.sh --no-fstypes asks for no records (no CDFS needed then).
fstype_parse() {
  local _conf="$1" _kt="$2"
  FS_NAMES=() FS_INITS=() FS_EXPS=() FS_FLAGS=()
  FS_EXTERNS="" FS_VFSSW=""
  [ -f "$_conf" ] || return 0
  local kw fname finit fexp frest fflags fpin ftok fpath fmd5 fsize fsumr
  while read -r kw fname finit fexp frest; do
    [ "$kw" = fstype ] || { echo "fstypes.conf: record must start with 'fstype' (got '$kw'): $kw $fname" >&2; exit 2; }
    [ -n "$fname" ] && [ -n "$finit" ] && [ -n "$fexp" ] || { echo "fstypes.conf: incomplete record (need: fstype <name> <init> <exp-src> [flags] [md5=<hex>])" >&2; exit 2; }
    fflags="" fpin=""
    for ftok in $frest; do
      case "$ftok" in
        md5=*) fpin="${ftok#md5=}" ;;
        *)     [ -n "$fflags" ] || fflags="$ftok" ;;
      esac
    done
    fflags="${fflags:-0}"
    case "$fexp" in
      '$CDFS/'*)
        if [ -z "${CDFS:-}" ]; then
          echo "fstype $fname: exp-source $fexp needs CDFS, and CDFS is not set (from $_conf)." >&2
          echo "        Set CDFS to an amix-cdfs checkout that has been built (make amix-kernel)," >&2
          echo "        or build without in-kernel filesystems (build-cross-kernel.sh --no-fstypes)." >&2
          exit 2
        fi
        fpath="${CDFS%/}/${fexp#\$CDFS/}" ;;
      /*) fpath="$fexp" ;;
      *)  fpath="$_kt/$fexp" ;;
    esac
    if [ ! -f "$fpath" ]; then
      echo "fstype $fname: exp-source not found: $fpath (from $_conf)" >&2
      case "$fexp" in '$CDFS/'*)
        echo "        CDFS=$CDFS does not carry ${fexp#\$CDFS/} -- build it there (make amix-kernel)" >&2
        echo "        or point CDFS at a built amix-cdfs checkout." >&2 ;;
      esac
      exit 2
    fi
    # ---- exp PROVENANCE ----------------------------------------------------------
    # The identity of the staged object is printed UNCONDITIONALLY so every build log
    # records which bytes went into the link; a declared md5= pin is enforced.  The
    # path in this conf names no revision, so only the pin says which artifact it is.
    fmd5="$(md5sum "$fpath" | awk '{print $1}')"
    fsize="$(stat -c%s "$fpath")"
    fsumr="$(sum -r "$fpath" | awk '{print $1}')"
    if [ -n "$fpin" ]; then
      case "$fpin" in
        *[!0-9a-f]*)
          echo "fstype $fname: MALFORMED md5= pin '$fpin' (want 32 lowercase hex) -- refusing," >&2
          echo "        a pin that cannot match is a pin that silently stopped pinning." >&2
          exit 2 ;;
      esac
      if [ "${#fpin}" -ne 32 ]; then
        echo "fstype $fname: MALFORMED md5= pin '$fpin' (${#fpin} chars, want 32) -- refusing." >&2
        exit 2
      fi
      if [ "$fmd5" != "$fpin" ]; then
        echo "ABORT: fstype $fname: exp-source PROVENANCE MISMATCH -- refusing to build." >&2
        echo "       staged object : $fpath" >&2
        echo "       found         : md5 $fmd5  (size $fsize B, sum -r $fsumr)" >&2
        echo "       pinned        : md5 $fpin  (fstypes.conf)" >&2
        echo "       The object at that path is NOT the proven artifact this conf pins." >&2
        echo "       Check the provider repo's checked-out branch/state (an unvalidated" >&2
        echo "       object at the same path has poisoned kernels before).  Update the" >&2
        echo "       md5= pin ONLY when deliberately adopting a new proven artifact." >&2
        exit 2
      fi
    fi
    FS_NAMES+=("$fname"); FS_INITS+=("$finit"); FS_EXPS+=("$fpath"); FS_FLAGS+=("$fflags")
    FS_EXTERNS="${FS_EXTERNS}extern int ${finit}();"$'\n'
    FS_VFSSW="${FS_VFSSW}	{ \"${fname}\", ${finit}, 0, 0 },"$'\n'
    echo "fstype: $fname  init=$finit  flags=$fflags  exp<-$fpath"
    echo "fstype: $fname  exp identity md5=$fmd5 size=$fsize sum_r=$fsumr$([ -n "$fpin" ] && echo '  (pin OK)' || echo '  (UNPINNED -- no md5= in conf)')"
  done < <(grep -Ev '^[[:space:]]*(#|$)' "$_conf")
}

# fstype_gen_onbox_patch <outfile> -- emit an IDEMPOTENT on-box `ed` patch script (run
# via sh on the box) that, per active fstype record (FS_NAMES/FS_INITS from fstype_parse),
# appends <name>/exp to fs/Makefile OPT_SUBEXP and injects the extern + vfssw[] row into
# master.d/filesys.c, then once appends $(FSLIB) to the top usr/sys/Makefile final ld
# line.  The OPT_SUBEXP entry is inserted right AFTER the `OPT_SUBEXP =` line so it is a
# MIDDLE entry (always backslash-continued) and the existing terminal entry stays terminal
# -- no fragile terminal-line surgery.
#
# FAIL-CLOSED, per arm (an earlier generator wrote blind and reported success; all three
# of the failure modes it had are closed here):
#
#   * PRE-PROBE before any write.  The vfssw[] arm refuses outright unless the declaration
#     anchor is present AND the table is closed by a TAB-indented `};` AND no other
#     `struct ...` table starts inside that span.  That last one is the silent killer: ed's
#     row-insert address is a forward-WRAPPING search for the first tab-indented close, so
#     on close-brace drift it can land the vfssw row INSIDE THE NEXT TABLE with no error
#     whatsoever (filesys.c's fmodsw[] sits right below vfssw[]).
#   * ONE ed RUN PER EDIT, and ed's exit status is checked after each.  The old single body
#     did the extern insert and the row insert together: a row-address miss still left the
#     extern written and the file saved -- and the name-wide `grep <init>` guard then
#     reported ok forever.  Split runs mean the diagnosis can say exactly which half landed.
#   * ROW-SCOPED GUARD + POST-VERIFY.  "Is this already patched" is answered by looking for
#     the init inside the vfssw span, not anywhere in the file; extern-present-row-absent is
#     the half-patch and is reported and REPAIRED (row only) rather than skipped.  After
#     the edit the span is re-checked and the row must be inside it.  "patched" is printed
#     only after that, never unconditionally.
#
# Contract with the host: exactly one `FSTYPE_OK <name>` per record and one `FSTYPE_DONE`
# at the end; any refusal prints `FSTYPE_ABORT: <why>` and exits 3.  fstype_stage_onbox
# gates on those sentinels because the remote-shell helper's exit status cannot say which
# record failed (and older helpers did not propagate it at all) -- so `sh /tmp/...`
# "succeeding" proves nothing on its own.
#
# FSPFX (default /usr/sys) prefixes every edited path, so the generated script can be run
# against a throwaway fixture tree host-side.  That is what tools/fstype-selftest.sh does.
fstype_gen_onbox_patch() {
  local out="$1" i nm it TAB; TAB="$(printf '\t')"
  {
    cat <<'FSGEN_HEAD'
#!/bin/sh
# On-box fstype integration -- GENERATED by tools/fstype-lib.sh from fstypes.conf.
# Do not edit on the box; edit the generator.  Idempotent, and fail-closed: every arm
# pre-probes its anchor, checks ed's exit status, and post-verifies that the edit landed
# where it was meant to -- only then does it say "patched".
set -u
FSPFX=${FSPFX:-/usr/sys}
FSM=$FSPFX/fs/Makefile; FSC=$FSPFX/master.d/filesys.c; TOPMK=$FSPFX/Makefile
VFSSW='^struct vfssw vfssw\[\] = {'

fsfail() {
	echo "FSTYPE""_ABORT: $*"
	exit 3
}

# The vfssw[] table AND NOTHING ELSE: its declaration through the first TAB-indented close
# brace -- byte-for-byte the span ed's row-insert address walks.
fsc_table() {
	sed -n "/$VFSSW/,/^	};/p" $FSC
}

# Refuse to run ed at all unless that span really is the vfssw table.
fsc_check_table() {
	if grep "$VFSSW" $FSC >/dev/null 2>&1; then :; else
		fsfail "no line matching the vfssw[] declaration anchor in $FSC"
	fi
	if fsc_table | grep '^	};' >/dev/null 2>&1; then :; else
		fsfail "vfssw[] in $FSC has no TAB-indented close brace -- ed's row address would wrap to some other table"
	fi
	if fsc_table | sed '1d' | grep '^struct ' >/dev/null 2>&1; then
		fsfail "vfssw[] in $FSC is not closed before the next table starts -- ed's row address would land the row in the WRONG table"
	fi
}
FSGEN_HEAD
    for i in "${!FS_NAMES[@]}"; do
      nm="${FS_NAMES[$i]}"; it="${FS_INITS[$i]}"
      printf '\n# ---------- %s (%s) ----------\n' "$nm" "$it"
      # --- fs/Makefile OPT_SUBEXP arm ---
      printf 'if grep %s/exp $FSM >/dev/null 2>&1; then\n' "$nm"
      printf '\techo "FSM ok (%s/exp present)"\n' "$nm"
      printf 'else\n'
      printf '\tif grep "^OPT_SUBEXP" $FSM >/dev/null 2>&1; then :; else\n'
      printf '\t\tfsfail "no OPT_SUBEXP line in $FSM"\n'
      printf '\tfi\n'
      printf '\tcp $FSM $FSM.bnkorig 2>/dev/null\n'
      printf '\tchmod 644 $FSM\n'
      printf "\ted - \$FSM <<'ED'\n"
      printf '/^OPT_SUBEXP/a\n'
      printf '%s%s%s/exp \\\n' "$TAB" "$TAB" "$nm"
      printf '.\nw\nq\nED\n'
      printf '\tif [ $? -ne 0 ]; then fsfail "ed failed on the OPT_SUBEXP arm of $FSM ($FSM.bnkorig is the pre-edit copy)"; fi\n'
      printf "\tif sed -n '/^OPT_SUBEXP/{n;p;}' \$FSM | grep %s/exp >/dev/null 2>&1; then :; else\n" "$nm"
      printf '\t\tfsfail "$FSM: %s/exp did not land directly under OPT_SUBEXP"\n' "$nm"
      printf '\tfi\n'
      printf '\techo "FSM patched (+%s/exp)"\n' "$nm"
      printf 'fi\n'
      # --- master.d/filesys.c vfssw[] arm ---
      printf 'fsc_check_table\n'
      printf 'FSCROW=no; if fsc_table | grep %s >/dev/null 2>&1; then FSCROW=yes; fi\n' "$it"
      printf 'FSCEXT=no; if grep "extern int %s()" $FSC >/dev/null 2>&1; then FSCEXT=yes; fi\n' "$it"
      printf 'if [ $FSCROW = yes ] && [ $FSCEXT = yes ]; then\n'
      printf '\techo "FSC ok (%s vfssw row + extern %s present)"\n' "$nm" "$it"
      printf 'else\n'
      printf '\tif [ $FSCEXT = yes ]; then\n'
      printf '\t\techo "FSC HALF-PATCHED: extern %s is present but NO %s row is in vfssw[] -- repairing the row"\n' "$it" "$nm"
      printf '\tfi\n'
      printf '\tif [ $FSCROW = yes ]; then\n'
      printf '\t\techo "FSC HALF-PATCHED: the %s vfssw row is present but extern %s is not -- repairing the extern"\n' "$nm" "$it"
      printf '\tfi\n'
      printf '\tcp $FSC $FSC.bnkorig 2>/dev/null\n'
      printf '\tchmod 644 $FSC\n'
      printf '\tif [ $FSCEXT = no ]; then\n'
      printf "\ted - \$FSC <<'ED'\n"
      printf '/^struct vfssw vfssw\\[\\] = {/i\n'
      printf 'extern int %s();\n' "$it"
      printf '.\nw\nq\nED\n'
      printf '\t\tif [ $? -ne 0 ]; then fsfail "ed failed inserting the %s extern into $FSC ($FSC.bnkorig is the pre-edit copy)"; fi\n' "$it"
      printf '\tfi\n'
      printf '\tif [ $FSCROW = no ]; then\n'
      printf "\ted - \$FSC <<'ED'\n"
      printf '/^struct vfssw vfssw\\[\\] = {/\n'
      printf '/^%s};/i\n' "$TAB"
      printf '%s{ "%s", %s, 0, 0 },\n' "$TAB" "$nm" "$it"
      printf '.\nw\nq\nED\n'
      printf '\t\tif [ $? -ne 0 ]; then fsfail "ed failed inserting the %s vfssw row into $FSC -- any extern insert above IS ALREADY WRITTEN, so $FSC is HALF-PATCHED; restore $FSC.bnkorig"; fi\n' "$nm"
      printf '\tfi\n'
      printf '\tfsc_check_table\n'
      printf '\tif fsc_table | grep %s >/dev/null 2>&1; then :; else\n' "$it"
      printf '\t\tfsfail "$FSC: the %s row is NOT inside vfssw[] after patching"\n' "$nm"
      printf '\tfi\n'
      printf '\tif grep "extern int %s()" $FSC >/dev/null 2>&1; then :; else\n' "$it"
      printf '\t\tfsfail "$FSC: extern %s is missing after patching"\n' "$it"
      printf '\tfi\n'
      printf '\techo "FSC patched (+%s vfssw row)"\n' "$nm"
      printf 'fi\n'
      printf 'echo "FSTYPE""_OK %s"\n' "$nm"
    done
    cat <<'FSGEN_TAIL'

# ---------- top Makefile: the $(FSLIB) hook on the final ld ----------
if grep FSLIB $TOPMK >/dev/null 2>&1; then
	echo "TOPMK ok (FSLIB present)"
else
	if grep 'ld -o $@ $(LINKARGS)' $TOPMK >/dev/null 2>&1; then :; else
		fsfail "no final 'ld -o' link line in $TOPMK -- refusing to guess where the FSLIB hook goes"
	fi
	cp $TOPMK $TOPMK.bnkorig 2>/dev/null
	chmod 644 $TOPMK
	ed - $TOPMK <<'ED'
/ld -o $@ $(LINKARGS)/s/$/ $(FSLIB)/
w
q
ED
	if [ $? -ne 0 ]; then fsfail "ed failed adding the FSLIB hook to $TOPMK ($TOPMK.bnkorig is the pre-edit copy)"; fi
	if grep 'ld -o $@ $(LINKARGS)' $TOPMK | grep FSLIB >/dev/null 2>&1; then :; else
		fsfail "$TOPMK: the final ld line does not carry FSLIB after patching"
	fi
	echo "TOPMK patched (FSLIB hook)"
fi
echo "FSTYPE""_DONE"
FSGEN_TAIL
  } > "$out"
}

# fstype_verify_onbox_output <output-text>
# The host half of the generated script's contract: one FSTYPE_OK per active record plus a
# final FSTYPE_DONE, and no FSTYPE_ABORT.  Returns 1 with a loud diagnosis otherwise.
# This is NOT belt-and-braces -- it is the only per-record enforcement there is: the
# remote-shell helper folds the remote status into one exit code (older ones always
# exited 0), so the builder's `set -e` cannot see which on-box arm refused.  Matched with `case`, not `grep -q`: the callers run
# under `set -o pipefail` and a grep -q that exits on first match can SIGPIPE its feeder.
# Telnet CRLF is harmless here -- every token is matched as a substring, never to end-of-line.
fstype_verify_onbox_output() {
  local _out="$1" _i _nm _missing=""
  case "$_out" in
    *FSTYPE_ABORT*)
      echo "fstype: the on-box integration REFUSED to patch -- see FSTYPE_ABORT above." >&2
      echo "        Nothing was half-written past that point; the pre-edit copies are the" >&2
      echo "        .bnkorig files beside each target.  Refusing to gate a kernel whose" >&2
      echo "        vfssw[] table may not carry the filesystem." >&2
      return 1 ;;
  esac
  for _i in "${!FS_NAMES[@]}"; do
    _nm="${FS_NAMES[$_i]}"
    case "$_out" in *"FSTYPE_OK $_nm"*) : ;; *) _missing="$_missing $_nm" ;; esac
  done
  if [ -n "$_missing" ]; then
    echo "fstype: the on-box integration never confirmed:$_missing" >&2
    echo "        (no 'FSTYPE_OK <name>' for it).  Either the pushed script did not run, or" >&2
    echo "        it died before that record.  Refusing to gate the kernel." >&2
    return 1
  fi
  case "$_out" in
    *FSTYPE_DONE*) : ;;
    *) echo "fstype: the on-box integration never reached FSTYPE_DONE -- the top Makefile" >&2
       echo "        FSLIB hook is unconfirmed.  Refusing to gate the kernel." >&2
       return 1 ;;
  esac
  return 0
}

# fstype_stage_onbox <amixsh> <amixsync> <work-dir> -- the on-box builders' helper.
# <amixsh> is a python script that runs its argument as a shell command on the box (exit
# status = the worst on-box rc); <amixsync> one that copies a host file to the box
# (`push <src> <dst>`).  For each active fstype record push
# the prebuilt fs/<name>/exp + the cross libgcc.a (fs 64-bit soft-arith, ABI-matched:
# the exp is cross m68k-cbm-sysv4, same toolchain) to the box, then run the generated
# idempotent ed patch.  SETS globals: GATE_FS (the gate's `--fs <archive>` flag, or "")
# and FS_DESC (a "; fs: ..." log suffix, or "").  No-op (both "") when no fstype record
# is active, so every on-box builder stays byte-identical without a record.  Honors
# CROSS_PREFIX (default m68k-cbm-sysv4-, found on PATH after `. "$GCA/env.sh"`; an
# absolute prefix works too).  Shared by every on-box builder so the staging logic lives
# in exactly one place.
# EXITS 2 when the on-box integration did not confirm every record (see
# fstype_verify_onbox_output).  A filesystem that is staged but NOT in vfssw[] must never
# reach the clean gate: it links, it gates green, and the only symptom is a mount that
# fails much later on a box nobody is watching.
fstype_stage_onbox() {
  local amixsh="$1" amixsync="$2" work="$3"
  GATE_FS=""; FS_DESC=""
  [ "${#FS_NAMES[@]}" -gt 0 ] || return 0
  local cross_prefix libgcc i nm
  cross_prefix="${CROSS_PREFIX:-m68k-cbm-sysv4-}"
  # A bare prefix names tools on PATH: resolve it to the gcc's directory so libgcc.a can
  # be found beside it (<prefix-dir>/../lib/gcc-lib/...).
  case "$cross_prefix" in
    */*) ;;
    *) local _cgcc
       _cgcc="$(command -v "${cross_prefix}gcc" 2>/dev/null || true)"
       [ -n "$_cgcc" ] || { echo "fstype active but ${cross_prefix}gcc is not on PATH (source \$GCA/env.sh, or set CROSS_PREFIX)" >&2; exit 2; }
       cross_prefix="${_cgcc%gcc}" ;;
  esac
  libgcc="$(ls "$(dirname "$(dirname "$cross_prefix")")"/lib/gcc-lib/m68k-cbm-sysv4/*/libgcc.a 2>/dev/null | head -1)"
  [ -n "$libgcc" ] && [ -f "$libgcc" ] || { echo "fstype active but cross libgcc.a not found under $(dirname "$(dirname "$cross_prefix")")/lib/gcc-lib (need __udivdi3 etc.)" >&2; exit 2; }
  for i in "${!FS_NAMES[@]}"; do
    nm="${FS_NAMES[$i]}"
    # Test-first, then mkdir: the box's SVR4 mkdir errors `mkdir: "<dir>": File exists`
    # with rc 2 on an existing FINAL component even under -p, and the remote-shell helper
    # propagates the worst on-box rc as its own exit status -- so under the callers'
    # `set -e` a bare `mkdir -p` kills the whole build whenever the box's tree already
    # carries fs/<name>.  The guard tolerates EXACTLY the already-exists case; a mkdir
    # that genuinely fails (permissions, missing parent, read-only fs) still propagates
    # its rc and stays fatal.
    python3 "$amixsh"   "[ -d /usr/sys/fs/$nm ] || mkdir -p /usr/sys/fs/$nm"
    python3 "$amixsync" push "${FS_EXPS[$i]}" "/usr/sys/fs/$nm/exp"
    echo "  pushed fs/$nm/exp <- ${FS_EXPS[$i]}"
  done
  python3 "$amixsync" push "$libgcc" /usr/sys/fs/libfsgcc.a
  echo "  pushed /usr/sys/fs/libfsgcc.a <- $libgcc"
  fstype_gen_onbox_patch "$work/onbox-fstype-patch.sh"
  python3 "$amixsync" push "$work/onbox-fstype-patch.sh" /tmp/onbox-fstype-patch.sh
  echo "integrating fs/Makefile + master.d/filesys.c + top Makefile on-box (idempotent ed) ..."
  # The script's OUTPUT is the verdict, not its exit status: one lumped exit status
  # cannot say WHICH record failed, so the per-record FSTYPE_OK sentinels are the gate,
  # and the ed-script's own exit statuses are checked inside the pushed script.
  # So capture, echo it for the build log, and refuse to continue unless every record confirmed.
  local _out=""
  _out="$(python3 "$amixsh" "sh /tmp/onbox-fstype-patch.sh" 2>&1)" || true
  printf '%s\n' "$_out"
  fstype_verify_onbox_output "$_out" || exit 2
  GATE_FS="--fs /usr/sys/fs/libfsgcc.a"
  FS_DESC="; fs: ${FS_NAMES[*]}"
}
