#!/usr/bin/env bash
#
# build-install-iso.sh -- assemble the installer payload into an /install/ tree,
# then master the install CD with it via build-iso.sh. This is the W5.3
# re-master: it turns the Wave-4 package disc into a self-contained install disc
# the miniroot driver can run start-to-finish.
#
# The /install/ tree it builds (paths the driver + miniroot shim expect):
#
#   /install/bin/pkgadd,pkgtrans,pkginfo,pkgchk   static CD engine (amix-packagemanager)
#   /install/bin/pkginstall                       static pkginstall (the shim exec target)
#   /install/bin/sum                              genuine SVR4 `sum` (from core) -- the
#                                                 on-target boot-chain verifier runs it
#   /install/bin/apkg                             static apkg, IF present (optional)
#   /install/admin/pkgadd                         permissive pkgadd -a policy
#   /install/admin/default                        the 183-B stock admin (seeded to target)
#   /install/order                                install order for the mastered set
#   /install/order.<set>                          one per NAMED SET this medium can
#                                                 satisfy in full (W3b)
#   /install/sets                                 the interview's tier table (W3b)
#   /install/profiles/*.profile                   target specs (copied verbatim)
#   /install/boot/<profile>/{bootslice.img,boot2.boot,bootslice.manifest}
#   /install/bin/install.sh + firstboot/*         the driver + first-boot payload
#   /install/bin/setup.sh                         the W2 interactive interview
#   /install/profiles/BASE                        the base profile this medium was
#                                                 mastered for (setup.sh reads it
#                                                 when launched with no argument)
#   /install/stand/{boot1.boot,makeiblk}          /stand framing tools the driver lays
#                                                 down for updbootpart (P5.4-FT)
#   /install/syslog/{syslog.conf,syslogd.init,syslogd}  the 2.1c syslog unit, init
#                                                 ENABLED (vendor exit commented, §5)
#
# Sources (read-only): ../amix-packagemanager heirloom/build-amix-static (engine),
# its repo-staging/stock/.t/core (sum + the 183-B admin), and this repo's
# src/installer, payload/firstboot, profiles/, deps via the sibling's deps.conf.
#
# The staged tree + the ISO are build artefacts (Commodore boot-slice chain, sum
# binary and packages). Never committed; the staging dir sits under work/
# (gitignored) and build-iso.sh's release gate refuses a git-tracked ISO path.
# Publishing a built disc is a per-artefact owner decision (docs/install-iso.md).
#
#   tools/build-install-iso.sh                       # bench profile, base set
#   tools/build-install-iso.sh --profile metal-a4000-z3660 --profile bench-a3000-a4091
#   tools/build-install-iso.sh --set full            # full package set
#
# Requires: bash, python3, xorriso (via build-iso.sh), rdbtool not needed here.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"
LAB_REPO="$repo"; . "$repo/tools/lib/lab-env.sh"   # bench/local.env: the bench's real addresses

PKGMGR="${PKGMGR:-$repo/../amix-packagemanager}"
STATIC="${STATIC:-$PKGMGR/heirloom/build-amix-static}"
CORE_T="${CORE_T:-$PKGMGR/build/repo-staging/stock/.t/core}"
STAGING="${STAGING:-$PKGMGR/build/repo-staging}"
# Authored metadata comes from the sibling's REPO TREE, never its build staging:
# the staging copy of deps.conf has been observed lagging (it predates the kernel-
# package edges), and sets.conf/cats.conf are not staged there at all. Same rule as
# build-iso.sh, deliberately -- the two must agree about what a set contains.
DEPS="${DEPS:-$PKGMGR/tools/repo/deps.conf}"
SETS_PY="${SETS_PY:-$PKGMGR/tools/repo/sets.py}"
SETS_CONF="${SETS_CONF:-$PKGMGR/tools/repo/sets.conf}"

# ---------------------------------------------------------------------------
# ATTESTED SETS -- which named sets have a REFERENCE INSTALLED-TREE DIGEST
# ---------------------------------------------------------------------------
# Plan §5.7, locked: a named set WITH an attested reference is digest-gated; a
# named set WITHOUT one, and every Custom selection, runs with the digest gate
# explicitly WAIVED and is marked "unattested selection" on the interview's
# confirmation screen and in the install log. The install matrix only ever drives
# attested sets.
#
# This list is what the medium tells the interview. Its counterpart is
# tools/install-matrix.sh's SET_REFS table, which holds the actual digests; the two
# are cross-checked by installer-selftest audit X, so a set can never be advertised
# as attested here while the matrix has no reference digest for it (or the
# reverse). `standard` joined it on 2026-08-11 when the cd-standard bench run
# recorded 4ad8e17b69b32208c9fffa600596a428 / 11012 objects; `developer` and
# `x11` joined on 2026-08-12 (W6) at ebd61ce15699fbb34cf0f6a2d0a07024 / 11497 and
# 5439f78fc1caf4da46af82db360f5d13 / 11546.
#
# ★★ `full` JOINED 2026-08-14 at 68de888084500aef703a9ccd3eeaa0e5 / 28,709
# objects -- the last set to have no reference, and the only one that needed the
# RIG changed twice to get one. It cannot be installed as declared ON s5: FIVE
# groups / TEN objects in gnusrc2 and X11r5src collide under s5's 14-character
# name limit (authority: ../amix-packagemanager docs/s5-14char-collisions.md;
# W6's own scan said three groups and was directory-blind -- it missed the
# ZAPHOD/ copies of the two amixInitExt pairs). On UFS the limit does not exist
# and `full` installs WHOLE, at its natural object count, with nothing dropped
# and no package re-minted. The 2026-08-14 cd-full run proved that half and then
# ran out of DISK inside package thirty (pkgadd spools each datastream onto the
# target: peak = tree + largest package, and the 400 MB rig was 8.5 MiB short);
# the rig went to 512 MB and the re-run went 10/10.
#
# So the packagemanager brief's Option A -- drop 5 objects, re-mint two packages,
# attest at 28,704 -- is now MOOT rather than an alternative: it exists only to
# work around a limit this project no longer meets. Retiring it is that repo's
# call. See install-matrix.sh SET_REFS and docs/installer.md.
#
# A medium mastered for a set NOT on this list still OFFERS it, and says in as
# many words that it is an unattested selection -- and since 2026-08-14 the
# DRIVER re-reads that judgement off the medium for unattended installs too,
# because a canned profile knows its rig and not its set (docs/installer.md,
# *A profile is a rig; a set is a medium*).
ATTESTED_SETS="minimal standard developer x11 full"

PROFILES=()
SET=base
EXTRA_PKGS=()
OUT=""
CDBOOT=""
STAGE="${STAGE:-$repo/work/install-tree}"
KEEP_STAGE=0
STAGE_ONLY=0
BSLICE_ARGS=()

# `base` is this repo's historical spelling of the packagemanager's `minimal` set --
# core bsd net text sysadm cdfs APKGENG APKG, the proven base-8. Before W3b that
# membership was a hardcoded array here AND a different hardcoded array in
# build-iso.sh, and `--set full` used a third rule (every stock/*.pkg) that silently
# dropped the three base/ packages -- so a "Full" install shipped no cdfs, no
# package manager. All three are gone: the membership of every set now comes from
# ../amix-packagemanager/tools/repo/sets.conf through its own resolver.
#
# W6.4b, still true and still the reason the base/ three are in every set: APKGENG
# (the heirloom engine) + APKG (the remote client) mean an installed box has a
# working package manager OUT OF THE BOX. The dynamic apkg needs /usr/lib/libnsl.so
# + /usr/lib/libc.so.1 at runtime; BOTH are core members. The APKG package ships a
# default /etc/apkg.conf (editable, class e); the driver re-writes it
# deterministically post-install, so "conf present with our repo line" is a
# driver-guaranteed invariant rather than contingent on pkgadd's editable placement.
#
# CASE: sets.conf names packages the way the CATALOG does (lowercase); the order
# file needs the SVR4 instance name's own case, because the driver passes each line
# verbatim to `pkgadd -d <file> <NAME>` and resolves `pkgs/{stock,base}/<NAME>-*.pkg`
# case-sensitively on a Rock-Ridge disc. The staging inventory bridges the two.
SET_ALIAS_base=minimal

usage() {
  cat <<EOF
usage: $(basename "$0") [--profile NAME]... [--set NAME] [--pkg NAME]...
                        [--out ISO] [--stage DIR] [--keep-stage]
                        [--source-hdf PROFILE=HDF]... [--no-require-gate]
                        [--cd-boot TREE]

  --profile NAME    target profile to build a boot slice for (repeatable;
                    default: bench-a3000-a4091). Each must exist in profiles/.
  --set NAME        the set this medium is mastered for -- base (= minimal,
                    default), minimal, standard, full, developer, x11.
                    Resolved from the packagemanager's sets.conf.
  --pkg NAME        add a package beyond the set (repeatable)
  --out ISO         output ISO path (default: build-iso.sh's default under work/)
  --stage DIR       /install/ staging dir (default: $STAGE)
  --keep-stage      keep the staged tree after mastering
  --stage-only      build the /install/ payload tree and STOP -- do NOT master an
                    ISO. This is the reusable staging half: tools/build-raw-source.sh
                    calls it to populate the RAW source disk's payload slice with
                    the identical /install/ tree (W6-RAW.1). Implies --keep-stage.
  --source-hdf P=H  override a profile's BOOTSLICE_SOURCE_HDF (repeatable)
  --no-require-gate do NOT require the kerntools bootchain-verify round-trip
                    (default: required -- a missing sibling is fatal)
  --cd-boot TREE    master a bootable CD: passed to build-iso.sh (amix-dlm's
                    mkstore -C tree, System ID AMIGA BOOT)
EOF
}

REQUIRE_GATE=1
declare -A SRC_OVERRIDE=()
while [ $# -gt 0 ]; do case "$1" in
  --profile)   PROFILES+=("$2"); shift 2;;
  --set)       SET="$2"; shift 2;;
  --pkg)       EXTRA_PKGS+=("$2"); shift 2;;
  --out)       OUT="$2"; shift 2;;
  --stage)     STAGE="$2"; shift 2;;
  --keep-stage) KEEP_STAGE=1; shift;;
  --stage-only) STAGE_ONLY=1; KEEP_STAGE=1; shift;;
  --source-hdf) k="${2%%=*}"; v="${2#*=}"; SRC_OVERRIDE["$k"]="$v"; shift 2;;
  --no-require-gate) REQUIRE_GATE=0; shift;;
  --cd-boot)   CDBOOT="$2"; shift 2;;
  -h|--help)   usage; exit 0;;
  *) echo "build-install-iso: unknown argument: $1" >&2; usage >&2; exit 2;;
esac; done

[ "${#PROFILES[@]}" -gt 0 ] || PROFILES=(bench-a3000-a4091)

command -v python3 >/dev/null || { echo "STOP: python3 required" >&2; exit 1; }

# --- preflight: the static engine + sum + admin must all be present ---------
need_file() { [ -f "$1" ] || { echo "STOP: missing $2: $1" >&2; exit 1; }; }
for b in pkgadd pkgtrans pkginfo pkgchk contents-fsck; do need_file "$STATIC/bin/$b" "static engine $b"; done
need_file "$STATIC/sadm-helpers/pkginstall" "static pkginstall"
need_file "$CORE_T/usr/bin/sum" "core /usr/bin/sum (on-target verifier)"
need_file "$CORE_T/var/sadm/install/admin/default" "core 183-B admin default"
need_file "$CORE_T/stand/boot1.boot" "core /stand/boot1.boot (framing source)"
need_file "$DEPS" "deps.conf (install order)"
need_file "$SETS_CONF" "sets.conf (the named install sets)"
need_file "$SETS_PY" "sets.py (the sets.conf reference resolver)"
need_file "$repo/src/installer/install.sh" "the installer driver"
need_file "$repo/src/installer/setup.sh" "the W2 interactive interview"

# vendor pieces from the user-supplied 2.1c patch media (payload/21c, gitignored):
# stand/makeiblk + the syslog unit. The extractor is idempotent and verifies its
# own pinned fingerprints -- a bad/missing archive is a hard STOP here.
"$here/extract-21c-payload.sh" || { echo "STOP: payload/21c extraction/verification failed" >&2; exit 1; }

# ---------------------------------------------------------------------------
# SET RESOLUTION -- sets.conf, through the packagemanager's own resolver
# ---------------------------------------------------------------------------
# The staging inventory, indexed by CATALOG NAME (lowercase), so nothing here has
# to hardcode which package names are capitalised: gen-catalog.py derives the
# catalog name by lowercasing the pkginst, and the pkginst is the .pkg filename's
# leading token, so `X11r5src-2.1.pkg` -> token `X11r5src` -> catalog `x11r5src`.
declare -A PKG_TOKEN=()
shopt -s nullglob
for f in "$STAGING"/stock/*.pkg "$STAGING"/stock/*.pkg.Z \
         "$STAGING"/base/*.pkg "$STAGING"/base/*.pkg.Z; do
  b="${f##*/}"; tok="${b%%-[0-9]*}"
  PKG_TOKEN["${tok,,}"]="$tok"
done
shopt -u nullglob
[ "${#PKG_TOKEN[@]}" -gt 0 ] || { echo "STOP: no packages under $STAGING/{stock,base}" >&2; exit 1; }

# resolve_set NAME -> the set's catalog names, one per line, in the order
# sets.conf DECLARES them (not sorted).
#
# ★ THE ORDER IS LOAD-BEARING AND IT IS NOT COSMETIC. gen-install-order.py breaks
# topological ties by input order, so the input order IS the install order for
# everything the dependency graph does not constrain -- and the base-8 install
# order (core bsd net text sysadm cdfs APKGENG APKG) is the one that produced
# every attested digest this project has. sets.py's `resolve()` returns a SORTED
# membership, which is right for "is this package in the set" and wrong here: it
# would have re-ordered the base-8 install for no reason at all, on a wave whose
# whole acceptance is that the base-8 tree does not move.
#
# So the AUTHORED order is used, expanded in file order -- and then checked
# against sets.py's own resolve() as a SET, so the two can never disagree about
# membership. sets.py stays the reference: this uses its parser and its resolver,
# it only chooses a different traversal order and proves the choice equivalent.
resolve_set() {
  python3 - "$SETS_PY" "$SETS_CONF" "$1" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("amix_sets", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
try:
    sets = m.read_sets(sys.argv[2])
except Exception as exc:
    sys.exit("sets: %s" % exc)
want = sys.argv[3]
if want not in sets:
    sys.exit("sets: no such set: %s" % want)

def expand(name, stack=()):
    if name in stack:
        sys.exit("sets: include cycle: %s -> %s" % (" -> ".join(stack), name))
    out = []
    for mem in sets.get(name, []):
        for p in (expand(mem[1:], stack + (name,)) if mem.startswith("+") else [mem]):
            if p not in out:
                out.append(p)
    return out

got = expand(want)
ref = m.resolve(sets, want)
if sorted(got) != ref:
    sys.exit("sets: file-order expansion of %r disagrees with sets.py resolve(): "
             "%r vs %r" % (want, sorted(got), ref))
sys.stdout.write("".join(p + "\n" for p in got))
PYEOF
}
set_tokens() {    # set_tokens NAME... -> order-file tokens; STOPs on a package
                  # the staging tree does not hold
  local name key out=() miss=()
  for name in "$@"; do
    key="${name,,}"
    if [ -n "${PKG_TOKEN[$key]:-}" ]; then out+=("${PKG_TOKEN[$key]}")
    else miss+=("$name"); fi
  done
  [ "${#miss[@]}" -eq 0 ] || {
    echo "STOP: package(s) not in $STAGING: ${miss[*]}" >&2; return 1; }
  printf '%s\n' ${out[@]+"${out[@]}"}
}

SET_NAME="$SET"
case "$SET" in base) SET_NAME="$SET_ALIAS_base" ;; esac
mapfile -t SET_MEMBERS < <(resolve_set "$SET_NAME") || true
[ "${#SET_MEMBERS[@]}" -gt 0 ] || {
  {
    echo "STOP: --set '$SET' does not resolve against $SETS_CONF"
    resolve_set "$SET_NAME" 2>&1 >/dev/null | sed 's/^/      /'
    echo "      available: $(python3 "$SETS_PY" -f "$SETS_CONF" | awk '{print $1}' | tr '\n' ' ')base"
  } >&2; exit 1; }

# A 1.1 medium's base carries m4: the 2.1c syslogd reads /etc/syslog.conf only through
# /usr/ccs/bin/m4 (the m4 package; Cdev ships the same file) and files nothing without
# it. install.sh refuses a 1.1 order with neither.
for _p in "${PROFILES[@]}"; do
  case "$(sed -n 's/^INSTALL_LAYOUT=//p' "$repo/profiles/$_p.profile" 2>/dev/null | tail -1 | tr -d '"')" in
    1.1)
      case " $(printf '%s ' "${SET_MEMBERS[@]}" ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"} | tr 'A-Z' 'a-z')" in
        *" m4 "*|*" cdev "*) ;;
        *) EXTRA_PKGS+=(m4)
           echo "build-install-iso: profile $_p is INSTALL_LAYOUT=1.1 -- m4 joins the set (/usr/ccs/bin/m4 for syslogd)" ;;
      esac ;;
  esac
done

mapfile -t SELECTED < <(set_tokens "${SET_MEMBERS[@]}" ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"}) || exit 1
[ "${#SELECTED[@]}" -gt 0 ] || { echo "STOP: set '$SET_NAME' resolved to nothing" >&2; exit 1; }

# The medium's inventory, as catalog names -- the set of packages that will be ON
# the disc. A named set is only OFFERED by the interview when this contains all of
# it: an order file naming a package the disc does not carry would fail the driver
# at pkgadd time, which is far too late to learn the disc was mis-mastered.
MEDIA_NAMES=" $(printf '%s ' "${SET_MEMBERS[@]}" ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"} | tr 'A-Z' 'a-z')"
set_satisfiable() {   # set_satisfiable NAME
  local m
  for m in $(resolve_set "$1"); do
    case "$MEDIA_NAMES" in *" ${m,,} "*) ;; *) return 1 ;; esac
  done
  return 0
}
set_attested() {      # set_attested NAME -> y|n
  local a
  for a in $ATTESTED_SETS; do [ "$a" = "$1" ] && { echo y; return 0; }; done
  echo n
}

echo "build-install-iso: set '$SET' = sets.conf '$SET_NAME' (${#SELECTED[@]} package(s))"
echo "  ${SELECTED[*]}"

# ---------------------------------------------------------------------------
# 1. stage /install/
# ---------------------------------------------------------------------------
echo "build-install-iso: staging /install/ at $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/admin" "$STAGE/profiles" "$STAGE/firstboot" "$STAGE/boot"

# engine + shim + sum + contents-fsck (the CD-resident static DB integrity checker
# the driver runs after the pkgadd loop; statically linked, so it runs on the thin
# miniroot with no libc/libnsl dependency -- W6.4b).
cp -p "$STATIC"/bin/{pkgadd,pkgtrans,pkginfo,pkgchk,contents-fsck} "$STAGE/bin/"
cp -p "$STATIC/sadm-helpers/pkginstall" "$STAGE/bin/pkginstall"
cp -p "$CORE_T/usr/bin/sum" "$STAGE/bin/sum"
chmod 0755 "$STAGE"/bin/*

# optional static apkg (the parallel dispatch may have landed it)
if [ -f "$STATIC/bin/apkg" ]; then
  cp -p "$STATIC/bin/apkg" "$STAGE/bin/apkg"; chmod 0755 "$STAGE/bin/apkg"
  echo "build-install-iso: included static apkg (present)"
  APKG_NOTE="apkg: present"
else
  echo "build-install-iso: NOTE static apkg not present -- shipping without it"
  echo "  (the driver does NOT depend on apkg; it is the remote client, not in"
  echo "   the pkgadd -R loop). Re-run after the static-apkg dispatch lands to include it."
  APKG_NOTE="apkg: absent (not required)"
fi

# the driver + the interview + first-boot payload
#
# --- STRIP_INSTALLER_COMMENTS (the 040 ISSUE-10 parse-wall dodge) -------------
# The 68040 lane walls at PARSE time inside /bin/sh's own allocator
# (`User BUS ERROR at 4AFC0003, PC:800023FC` ... `no space`) -- the 040/060
# port's ISSUE-10, whose measured trigger is ARENA GROWTH DISTANCE, not file
# size. These two scripts are ~2/3 comment by volume, so dropping full-line
# comments and blank lines AT STAGING TIME shrinks the parse arena without
# touching one line of executable shell.
#
# DEFAULT OFF. Every 030 profile omits the key, so every existing medium stages
# byte-identical copies exactly as before -- this cannot move a proven digest by
# accident. It is opt-in per profile (the 040 profiles set it), and the base
# profile (PROFILES[0], the one written to /install/profiles/BASE) is what
# decides, because that is the profile this medium is mastered for.
#
# The stripping is done by tools/strip-sh-comments.py, which LEXES rather than
# greps -- these scripts quote the stock 1991 screens verbatim, and a blank line
# inside a multi-line "..." string is DATA. It refuses outright on constructs it
# cannot lex safely (here-docs, `$(...)`), and every strip passes seven gates,
# the load-bearing one being an INDEPENDENT `shlex` token-stream comparison. A
# refusal or a failed gate is fatal here: never ship a half-stripped installer.
STRIP_COMMENTS=""
_base_profile_file="$repo/profiles/${PROFILES[0]}.profile"
if [ -f "$_base_profile_file" ]; then
  STRIP_COMMENTS="$(python3 -c '
import sys
d={}
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if not ln or ln.startswith("#") or "=" not in ln: continue
    k,v=ln.split("=",1); v=v.strip()
    if len(v)>=2 and v[0]=="\"" and v[-1]=="\"": v=v[1:-1]
    d[k.strip()]=v
print(d.get("STRIP_INSTALLER_COMMENTS",""))' "$_base_profile_file")"
fi
case "$STRIP_COMMENTS" in
  [yY]|[yY][eE][sS]|1) STRIP_COMMENTS=1 ;;
  *)                   STRIP_COMMENTS=  ;;
esac

if [ -n "$STRIP_COMMENTS" ]; then
  echo "build-install-iso: STRIP_INSTALLER_COMMENTS=y (profile ${PROFILES[0]}) -- staging comment-stripped /install/bin scripts"
  echo "  (the 040 ISSUE-10 parse-wall dodge; src/installer/*.sh are NOT modified)"
  for _s in install.sh setup.sh; do
    python3 "$here/strip-sh-comments.py" "$repo/src/installer/$_s" "$STAGE/bin/$_s" \
      || { echo "STOP: strip-sh-comments refused $_s -- refusing to ship a half-stripped installer" >&2; exit 1; }
    chmod 0755 "$STAGE/bin/$_s"
  done
else
  cp -p "$repo/src/installer/install.sh" "$STAGE/bin/install.sh"; chmod 0755 "$STAGE/bin/install.sh"
  cp -p "$repo/src/installer/setup.sh"   "$STAGE/bin/setup.sh";   chmod 0755 "$STAGE/bin/setup.sh"
fi
cp -p "$repo"/payload/firstboot/firstboot.sh "$STAGE/firstboot/firstboot.sh"
cp -p "$repo"/payload/firstboot/root.shadow  "$STAGE/firstboot/root.shadow"

# FB_ROOT_SEED_PW (optional profile key): override the SEEDED root password hash.
# Default (key unset) = the shared payload/firstboot/root.shadow ("pass"), byte-
# unchanged for every existing medium. A DISTRIBUTABLE showcase image sets it to a
# throwaway so the image never carries the standing bench password; firstboot still
# FORCES a new root password at first boot, so this is only the pre-firstboot seed.
_seed_pw="$(python3 -c '
import sys
d={}
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if not ln or ln.startswith("#") or "=" not in ln: continue
    k,v=ln.split("=",1); v=v.strip()
    if len(v)>=2 and v[0]=="\"" and v[-1]=="\"": v=v[1:-1]
    d[k.strip()]=v
print(d.get("FB_ROOT_SEED_PW",""))' "$_base_profile_file" 2>/dev/null)"
if [ -n "$_seed_pw" ]; then
  command -v perl >/dev/null || { echo "STOP: FB_ROOT_SEED_PW set but perl (for crypt) is unavailable" >&2; exit 1; }
  _seed_hash="$(perl -e 'print crypt($ARGV[0], "aB")' "$_seed_pw")"
  [ -n "$_seed_hash" ] || { echo "STOP: crypt of FB_ROOT_SEED_PW produced no hash" >&2; exit 1; }
  printf 'root:%s:::::::\n' "$_seed_hash" > "$STAGE/firstboot/root.shadow"
  chmod 0600 "$STAGE/firstboot/root.shadow"
  echo "build-install-iso: FB_ROOT_SEED_PW set (profile ${PROFILES[0]}) -- regenerated root.shadow (throwaway seed; firstboot still forces a new password)"
fi

# --- /install/fpfix (BLIZZARD F2-M1; installed-tree ufs FP patch) -------------
# The 040/060 line runs a UFS root, and on an FPU-less 68060 (the LC060) the
# target's OWN /usr/lib/fs/ufs/{mkfs,fsck} die at a display-only FP expression
# (fsck at its summary, upstream of "STATE SET TO OKAY"), so a shipped image cannot
# fsck its own root. MINIROOT_FP_PATCH already patches the MINIROOT'S copies at
# build time; this stages a host-PATCHED copy of the INSTALLED pair too, which
# install.sh (§5b) cp's over the target after pkgadd and verifies by sum. Source of
# truth = core's own usr/lib/fs/ufs/{mkfs,fsck} (the exact bytes the install lays
# down -- 20092 / 111580 B; F2-M1 §1). patch-ufs-fp.py preserves every length, so
# the installed sizes and the altroot-attest digest do not move; the only reader
# that notices is pkgchk (a cksum mismatch on these two paths -- the same declared
# exception miniroot.proto already carries). Gated on the BASE profile's
# MINIROOT_FP_PATCH: a medium that does not set it stages no fpfix and §5b is inert,
# so every existing medium is byte-unchanged.
FP_PATCH="$(python3 -c '
import sys
d={}
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if not ln or ln.startswith("#") or "=" not in ln: continue
    k,v=ln.split("=",1); v=v.strip()
    if len(v)>=2 and v[0]=="\"" and v[-1]=="\"": v=v[1:-1]
    d[k.strip()]=v
print(d.get("MINIROOT_FP_PATCH",""))' "$_base_profile_file" 2>/dev/null)"
case "$FP_PATCH" in
  [yY]|[yY][eE][sS]|1) FP_PATCH=1 ;;
  *)                   FP_PATCH=  ;;
esac
if [ -n "$FP_PATCH" ]; then
  echo "build-install-iso: MINIROOT_FP_PATCH=yes (profile ${PROFILES[0]}) -- staging FP-patched installed ufs tools at /install/fpfix"
  mkdir -p "$STAGE/fpfix"
  : > "$STAGE/fpfix/SUMS"
  for pair in "mkfs:usr/lib/fs/ufs/mkfs" "fsck:usr/lib/fs/ufs/fsck"; do
    _nm="${pair%%:*}"; _src="$CORE_T/${pair#*:}"
    need_file "$_src" "core ${pair#*:} (FP-patch source)"
    # -o writes the patched copy WITHOUT touching core's tree; the tool asserts the
    # stock bytes and refuses anything else, so a wrong/already-patched source fails.
    python3 "$here/patch-ufs-fp.py" -o "$STAGE/fpfix/$_nm" "$_src" \
      || { echo "STOP: patch-ufs-fp refused to patch $_src -- not shipping an unpatched or mis-patched ufs tool" >&2; exit 1; }
    # length preserved -> installed size unchanged -> digest unmoved
    if [ "$(wc -c < "$STAGE/fpfix/$_nm")" != "$(wc -c < "$_src")" ]; then
      echo "STOP: FP-patched $_nm changed length -- refusing (would move the attested digest)" >&2; exit 1
    fi
    # the BSD `sum -r` CHECKSUM (first field) is portable to the box's SVR4 sum -r;
    # only the block column differs (512 vs 1024), so install.sh compares field 1.
    printf '%s %s\n' "$_nm" "$(sum -r "$STAGE/fpfix/$_nm" | awk '{print $1}')" >> "$STAGE/fpfix/SUMS"
  done
  echo "  staged $STAGE/fpfix/{mkfs,fsck} + SUMS ($(awk '{printf "%s=%s ",$1,$2}' "$STAGE/fpfix/SUMS"))"
fi

# --- /install/UNATTENDED (v3 demo-card auto-run marker) -----------------------
# Written IFF the base profile sets INSTALL_UNATTENDED=yes. It is one half of the
# double gate the miniroot's /etc/profile checks: the marker PLUS the on-slice base
# profile (raw.profile) declaring INSTALL_UNATTENDED=yes. Both are produced only by
# an unattended profile, so an interactive medium can never carry a live marker and
# the interview runs as always. The marker names the medium and the profile for the
# operator; the runtime reads the profile ARG from /install/profiles/BASE, so the
# content is informational.
UNATTENDED="$(python3 -c '
import sys
d={}
for ln in open(sys.argv[1]):
    ln=ln.strip()
    if not ln or ln.startswith("#") or "=" not in ln: continue
    k,v=ln.split("=",1); v=v.strip()
    if len(v)>=2 and v[0]=="\"" and v[-1]=="\"": v=v[1:-1]
    d[k.strip()]=v
print(d.get("INSTALL_UNATTENDED",""))' "$_base_profile_file" 2>/dev/null)"
case "$UNATTENDED" in
  [yY]|[yY][eE][sS]|1) UNATTENDED=1 ;;
  *)                   UNATTENDED=  ;;
esac
if [ -n "$UNATTENDED" ]; then
  {
    echo "# amix-installng unattended demo-card marker (v3)"
    echo "# Presence here + INSTALL_UNATTENDED=yes in the on-slice base profile makes"
    echo "# the miniroot auto-run install.sh with the BASE profile, then halt."
    echo "profile ${PROFILES[0]}"
  } > "$STAGE/UNATTENDED"
  echo "build-install-iso: INSTALL_UNATTENDED=yes (profile ${PROFILES[0]}) -- wrote /install/UNATTENDED (demo-card auto-run)"
fi

# --- /install/updbootpart (W5.5) ---------------------------------------------
# The on-box boot-slice reframe tool the driver lays down at /usr/sbin/updbootpart
# on every target. It used to travel INSIDE install.sh as a quoted here-doc -- and
# the 1991 SVR4 sh materializes every here-doc body into a REAL FILE under /tmp the
# moment it PARSES the script. On the miniroot /tmp IS the 880-block install floppy
# with 46 free blocks, so 15,427 bytes of updbootpart sat on it for the whole
# install, taking blocks the static pkgadd needs for its packaging directory. It
# rides the MEDIUM now (this file), and the driver copies it: the floppy pays
# nothing, and payload/updbootpart stays the single tracked master. The staged copy
# is proven byte-identical to that master here -- the drift lock the here-doc used
# to give us for free (installer-selftest audit O keeps the other half).
cp -p "$repo/payload/updbootpart" "$STAGE/updbootpart"
chmod 0755 "$STAGE/updbootpart"
cmp -s "$repo/payload/updbootpart" "$STAGE/updbootpart" || {
  echo "STOP: staged /install/updbootpart is not byte-identical to payload/updbootpart" >&2; exit 1; }
echo "build-install-iso: staged /install/updbootpart ($(wc -c <"$STAGE/updbootpart") B, byte-identical to payload/updbootpart)"

# --- /install/zenmac (P-3 address-by-card) -----------------------------------
# The zen0 MAC reader install.sh lays down at /usr/amiga/bin/zenmac on a zen0
# flavor; S99zen runs it at every boot to pick the card's address out of
# /etc/inet/zen.conf (docs/address-by-card.md). A build artefact (vendor crt bytes,
# gitignored), rebuilt from src/zenmac by tools/build-zenmac.sh when missing or
# older than its source. REQUIRED when any requested profile is a zen0 flavor
# (without it every boot falls back to the default row, loudly); otherwise staged
# when it can be built and skipped with a note when it cannot.
_want_zenmac=
for _p in "${PROFILES[@]}"; do
  grep -q '^FB_ETHER_IF=zen0' "$repo/profiles/$_p.profile" 2>/dev/null && _want_zenmac=y
done
if [ ! -f "$repo/payload/zenmac" ] || [ "$repo/src/zenmac/zenmac.c" -nt "$repo/payload/zenmac" ]; then
  if ! "$here/build-zenmac.sh"; then
    if [ -n "$_want_zenmac" ]; then
      echo "STOP: a zen0 profile was requested and payload/zenmac cannot be built (tools/build-zenmac.sh)" >&2; exit 1
    fi
    echo "build-install-iso: NOTE: payload/zenmac could not be built -- /install/zenmac not staged (no zen0 profile requested)"
  fi
fi
if [ -f "$repo/payload/zenmac" ]; then
  cp -p "$repo/payload/zenmac" "$STAGE/zenmac"
  chmod 0755 "$STAGE/zenmac"
  cmp -s "$repo/payload/zenmac" "$STAGE/zenmac" || {
    echo "STOP: staged /install/zenmac is not byte-identical to payload/zenmac" >&2; exit 1; }
  echo "build-install-iso: staged /install/zenmac ($(wc -c <"$STAGE/zenmac") B, sha256 $(sha256sum "$STAGE/zenmac" | cut -c1-16)...)"
fi

# --- /install/monsw (P-8 monitor switch) ------------------------------------
# The three files install.sh lays down when a profile sets MONSW (see its "LAY
# DOWN the monitor-switch bits" block): amix-kerntools' rc step S20monsw and its
# cross-built monswctl, and the port line's sys/monsw.h -- the same sources
# kerntools' build-image.sh section b3b uses. Staged ONLY when a requested
# profile sets MONSW to a value (not empty, not "none"), so every other medium is
# byte-for-byte what it was. Both pins are checked HERE, host-side, before any
# box is involved, and a mismatch STOPS the build: monswctl must hash to
# kerntools' tools/monsw/MANIFEST monswctl_sha256; the header to MONSW_H_SHA
# (the same pin build-image.sh and build-monswctl.sh carry).
MONSW_KT="$repo/../amix-kerntools/tools/monsw"
MONSW_H="$repo/../amix-040-060-port/src/sys/monsw.h"
MONSW_H_SHA=66e63e7e7a48131398809c16fa103b11d5b951b898e067a01089707f9523229e
MONSW_MAJOR=52   # cdevsw row of /dev/monsw (port b9992ed); install.sh mknods c 52 0
_want_monsw=
for _p in "${PROFILES[@]}"; do
  _v="$(sed -n 's/^MONSW=//p' "$repo/profiles/$_p.profile" 2>/dev/null | tail -1 | tr -d '"')"
  case "$_v" in
    ''|none) ;;
    0|1|2|3|16|17|18|19|32|33|34|35|48|49|50|51) _want_monsw="$_want_monsw $_p=$_v" ;;
    *) echo "STOP: profile $_p: MONSW='$_v' is not a bit sum of 1 2 16 32 (or 'none')" >&2; exit 1 ;;
  esac
done
if [ -n "$_want_monsw" ]; then
  for _f in "$MONSW_KT/S20monsw" "$MONSW_KT/MANIFEST" "$MONSW_H"; do
    [ -f "$_f" ] || { echo "STOP: MONSW requested by${_want_monsw} but $_f is missing" >&2; exit 1; }
  done
  [ -f "$MONSW_KT/bin/monswctl" ] || {
    echo "STOP: MONSW requested by${_want_monsw} but $MONSW_KT/bin/monswctl is not built (run ../amix-kerntools/tools/monsw/build-monswctl.sh)" >&2; exit 1; }
  _ctl_want="$(sed -n 's/^monswctl_sha256=//p' "$MONSW_KT/MANIFEST")"
  _ctl_got="$(sha256sum "$MONSW_KT/bin/monswctl" | cut -c1-64)"
  [ -n "$_ctl_want" ] && [ "$_ctl_got" = "$_ctl_want" ] || {
    echo "STOP: monswctl sha256 $_ctl_got != kerntools MANIFEST ${_ctl_want:-<none>} ($MONSW_KT/bin/monswctl; rebuild with build-monswctl.sh)" >&2; exit 1; }
  _h_got="$(sha256sum "$MONSW_H" | cut -c1-64)"
  [ "$_h_got" = "$MONSW_H_SHA" ] || {
    echo "STOP: sys/monsw.h sha256 $_h_got != pinned $MONSW_H_SHA ($MONSW_H; re-pin here AND in kerntools together)" >&2; exit 1; }
  # S20monsw self-heals the node at every boot: its mknod must name the SAME major
  # install.sh lays down, or a box that loses /dev/monsw re-creates the wrong row.
  _s20_major="$(sed -n 's|.*mknod [^ ]* c \([0-9][0-9]*\) 0.*|\1|p' "$MONSW_KT/S20monsw" | head -1)"
  [ "$_s20_major" = "$MONSW_MAJOR" ] || {
    echo "STOP: $MONSW_KT/S20monsw self-heals /dev/monsw as c ${_s20_major:-?} 0, but the installed node is c $MONSW_MAJOR 0 (update kerntools' S20monsw first)" >&2; exit 1; }
  mkdir -p "$STAGE/monsw"
  cp "$MONSW_KT/S20monsw" "$STAGE/monsw/S20monsw"
  cp "$MONSW_KT/bin/monswctl" "$STAGE/monsw/monswctl"
  cp "$MONSW_H" "$STAGE/monsw/monsw.h"
  chmod 0755 "$STAGE/monsw/S20monsw" "$STAGE/monsw/monswctl"
  chmod 0644 "$STAGE/monsw/monsw.h"
  cmp -s "$MONSW_KT/S20monsw" "$STAGE/monsw/S20monsw" && cmp -s "$MONSW_KT/bin/monswctl" "$STAGE/monsw/monswctl" \
    && cmp -s "$MONSW_H" "$STAGE/monsw/monsw.h" || {
    echo "STOP: staged /install/monsw is not byte-identical to its sources" >&2; exit 1; }
  echo "build-install-iso: staged /install/monsw for${_want_monsw}: monswctl ${_ctl_got:0:16}... (== MANIFEST), monsw.h ${_h_got:0:16}... (== pin), S20monsw $(sha256sum "$STAGE/monsw/S20monsw" | cut -c1-16)..."
else
  echo "build-install-iso: no requested profile sets MONSW -- /install/monsw not staged"
fi

# --- /install/x11kit (K1 RTG desktop kit, X11KIT=rtg) -------------------------
# The kit install.sh lays down for X11KIT=rtg (its "LAY DOWN the RTG X11 kit" block).
# Cut 4: the RTG station's own manifest amix-z3660rtg/x11/KIT.sha256 is the pin for
# its four files (server, rtg-kbdback, startx-rtg, xinitrc-rtg), all taken from
# amix-z3660rtg/build/out/; KIT.sha256 itself is pinned HERE, so a new kit is a
# deliberate re-pin. zz9k_monsw (the P-7 fallback switch) is not in the kit and keeps
# its own pin. A missing file or any mismatch STOPS the build. Staged only when a
# requested profile sets X11KIT=rtg, so every other medium is unchanged.
X11KIT_RTG="$repo/../amix-z3660rtg"
X11KIT_KIT="$X11KIT_RTG/x11/KIT.sha256"
X11KIT_KIT_SHA=afd7068c9c89fbec829f950b07ff1882ee65d778c3387e34335f3f80222f5f9d   # the published kit (s14rt04)
# The 1.0 media carry kit 8beaa7bf (startx-rtg e948dbf4, xinitrc-rtg 69f6b68c); the published kit
# (startx-rtg 5ec6a2fa, xinitrc-rtg 8f867980) differs from those files in comments only.
X11KIT_MONSW="$X11KIT_RTG/build/tools/zz9k_monsw"
X11KIT_MONSW_SHA=8149544a8e563cda0e2ec8b177e5999170c8013ed820c4f84f8adc15898c96bf   # P-7 fallback
_want_x11kit=
for _p in "${PROFILES[@]}"; do
  _v="$(sed -n 's/^X11KIT=//p' "$repo/profiles/$_p.profile" 2>/dev/null | tail -1 | tr -d '"')"
  case "$_v" in
    ''|none) ;;
    rtg) _want_x11kit="$_want_x11kit $_p" ;;
    *) echo "STOP: profile $_p: X11KIT='$_v' is not 'rtg' (or 'none')" >&2; exit 1 ;;
  esac
done
if [ -n "$_want_x11kit" ]; then
  [ -f "$X11KIT_KIT" ] || { echo "STOP: X11KIT=rtg requested by${_want_x11kit} but $X11KIT_KIT is missing" >&2; exit 1; }
  _kit_got="$(sha256sum "$X11KIT_KIT" | cut -c1-64)"
  [ "$_kit_got" = "$X11KIT_KIT_SHA" ] || {
    echo "STOP: $X11KIT_KIT sha256 $_kit_got != pinned $X11KIT_KIT_SHA (a new RTG kit: re-pin deliberately)" >&2; exit 1; }
  [ "$(awk 'END{print NR}' "$X11KIT_KIT")" = 4 ] || { echo "STOP: $X11KIT_KIT does not list exactly four files" >&2; exit 1; }
  (cd "$X11KIT_RTG/build/out" && sha256sum --quiet -c "$X11KIT_KIT") || {
    echo "STOP: amix-z3660rtg/build/out does not match x11/KIT.sha256" >&2; exit 1; }
  [ -f "$X11KIT_MONSW" ] || { echo "STOP: X11KIT=rtg requested by${_want_x11kit} but $X11KIT_MONSW is not built" >&2; exit 1; }
  [ "$(sha256sum "$X11KIT_MONSW" | cut -c1-64)" = "$X11KIT_MONSW_SHA" ] || { echo "STOP: zz9k_monsw sha256 != pinned $X11KIT_MONSW_SHA" >&2; exit 1; }
  rm -rf "$STAGE/x11kit"; mkdir -p "$STAGE/x11kit"
  _kit_list=
  while read -r _sha _name; do
    case "$_name" in
      Xzz9000-*) _dst=Xzz9000 ;;
      rtg-kbdback|startx-rtg|xinitrc-rtg) _dst="$_name" ;;
      *) echo "STOP: $X11KIT_KIT names an unknown kit file '$_name'" >&2; exit 1 ;;
    esac
    cp "$X11KIT_RTG/build/out/$_name" "$STAGE/x11kit/$_dst"
    [ "$(sha256sum "$STAGE/x11kit/$_dst" | cut -c1-64)" = "$_sha" ] || { echo "STOP: staged x11kit/$_dst != $_sha" >&2; exit 1; }
    _kit_list="$_kit_list $_dst=${_sha:0:8}"
  done < "$X11KIT_KIT"
  for _f in Xzz9000 rtg-kbdback startx-rtg xinitrc-rtg; do
    [ -f "$STAGE/x11kit/$_f" ] || { echo "STOP: the kit did not provide $_f" >&2; exit 1; }
  done
  cp "$X11KIT_MONSW" "$STAGE/x11kit/zz9k_monsw"
  chmod 0755 "$STAGE/x11kit/Xzz9000" "$STAGE/x11kit/rtg-kbdback" "$STAGE/x11kit/startx-rtg" "$STAGE/x11kit/zz9k_monsw"
  chmod 0644 "$STAGE/x11kit/xinitrc-rtg"
  echo "build-install-iso: staged /install/x11kit for${_want_x11kit}: KIT.sha256 ${X11KIT_KIT_SHA:0:16}... ==${_kit_list}, zz9k_monsw=${X11KIT_MONSW_SHA:0:8} (all == pins)"
else
  echo "build-install-iso: no requested profile sets X11KIT -- /install/x11kit not staged"
fi

# --- /install/setclk (IN-rtc, RTC=setclk -- the default) ------------------------
# Our Y2K-fixed, plausibility-gated setclk, which install.sh copies over the stock
# /usr/amiga/bin/setclk. A build artefact (the stock Commodore source never enters
# git): tools/build-setclk.sh makes it when missing, deterministically, and it is
# pinned HERE by sha256 -- a different binary is a different product, re-pin
# deliberately. Staged when any requested profile leaves RTC at its default or
# sets RTC=setclk; RTC=none profiles alone stage nothing.
SETCLK_SHA=02e1a8835bdbf6306dd54af5ca9936edbb82ae11c104ddb861137f0cda35e0ce
_want_setclk=
for _p in "${PROFILES[@]}"; do
  _v="$(sed -n 's/^RTC=//p' "$repo/profiles/$_p.profile" 2>/dev/null | tail -1 | tr -d '"')"
  case "$_v" in
    ''|setclk) _want_setclk="$_want_setclk $_p" ;;
    none) ;;
    *) echo "STOP: profile $_p: RTC='$_v' is not 'setclk' or 'none'" >&2; exit 1 ;;
  esac
done
if [ -n "$_want_setclk" ]; then
  if [ ! -f "$repo/payload/setclk" ]; then
    "$here/build-setclk.sh" || { echo "STOP: RTC=setclk requested by${_want_setclk} and payload/setclk cannot be built (tools/build-setclk.sh)" >&2; exit 1; }
  fi
  _sc_got="$(sha256sum "$repo/payload/setclk" | cut -c1-64)"
  [ "$_sc_got" = "$SETCLK_SHA" ] || {
    echo "STOP: payload/setclk sha256 $_sc_got != pinned $SETCLK_SHA (rebuild with tools/build-setclk.sh, or re-pin deliberately)" >&2; exit 1; }
  cp "$repo/payload/setclk" "$STAGE/setclk"; chmod 0755 "$STAGE/setclk"
  cmp -s "$repo/payload/setclk" "$STAGE/setclk" || { echo "STOP: staged /install/setclk is not byte-identical to payload/setclk" >&2; exit 1; }
  echo "build-install-iso: staged /install/setclk (${SETCLK_SHA:0:16}... == pin) for${_want_setclk}"
else
  echo "build-install-iso: every requested profile sets RTC=none -- /install/setclk not staged"
fi

# --- /install/tz (IN-rtc-2, TZFILES=tzdata -- the default) ----------------------
# Every zone file Amix ships, regenerated from current tzdata in the 1991 layout by
# tools/build-tzfile.py (the 1991 files end EU summer time in September, US DST on
# the pre-2007 rule, ...); install.sh lays the set over /usr/lib/locale/TZ. Pinned
# by the sha256 of the set's MANIFEST. TZFILES=stock profiles alone stage nothing.
TZSET_SHA=07a54a87dfdfff81d6f48fcf89f0305b1daa4800d4015a83394606b9fc309d06
_want_tz=
for _p in "${PROFILES[@]}"; do
  _v="$(sed -n 's/^TZFILES=//p' "$repo/profiles/$_p.profile" 2>/dev/null | tail -1 | tr -d '"')"
  case "$_v" in
    ''|tzdata) _want_tz="$_want_tz $_p" ;;
    stock) ;;
    *) echo "STOP: profile $_p: TZFILES='$_v' is not 'tzdata' or 'stock'" >&2; exit 1 ;;
  esac
done
if [ -n "$_want_tz" ]; then
  if [ ! -f "$repo/payload/tz/MANIFEST" ]; then
    python3 "$here/build-tzfile.py" || { echo "STOP: TZFILES=tzdata requested by${_want_tz} and payload/tz cannot be built (tools/build-tzfile.py)" >&2; exit 1; }
  fi
  _tz_got="$(sha256sum "$repo/payload/tz/MANIFEST" | cut -c1-64)"
  [ "$_tz_got" = "$TZSET_SHA" ] || {
    echo "STOP: payload/tz/MANIFEST sha256 $_tz_got != pinned $TZSET_SHA (rebuild with tools/build-tzfile.py, or re-pin deliberately)" >&2; exit 1; }
  (cd "$repo/payload/tz" && sha256sum --quiet -c <(awk '{print $1"  "$3}' MANIFEST)) || {
    echo "STOP: payload/tz does not match its MANIFEST (rebuild with tools/build-tzfile.py)" >&2; exit 1; }
  rm -rf "$STAGE/tz"; cp -r "$repo/payload/tz" "$STAGE/tz"; chmod -R a+rX "$STAGE/tz"
  diff -r "$repo/payload/tz" "$STAGE/tz" >/dev/null || { echo "STOP: staged /install/tz is not identical to payload/tz" >&2; exit 1; }
  echo "build-install-iso: staged /install/tz ($(awk 'END{print NR}' "$repo/payload/tz/MANIFEST") zones, ${TZSET_SHA:0:16}... == pin) for${_want_tz}"
else
  echo "build-install-iso: every requested profile sets TZFILES=stock -- /install/tz not staged"
fi

# --- /install/l11: the 1.1 disk layout (INSTALL_LAYOUT=1.1, amix-dlm spec 40) -------
# The driver's 1.1 half (src/installer/l11.sh) and what it runs: the static apkg 0.3
# and the FILE source with the kbootset, loader-amix and kernel packages (the box's
# kbootset and loader are those packages' files, installed on the target). All of it
# comes from work/l11 (tools/build-l11-inputs.sh: clean exports at named revisions,
# INPUTS records them); each staged file is cmp'd against its source.
L11_IN="${L11_IN:-$repo/work/l11}"
_want_l11=
for _p in "${PROFILES[@]}"; do
  _v="$(sed -n 's/^INSTALL_LAYOUT=//p' "$repo/profiles/$_p.profile" 2>/dev/null | tail -1 | tr -d '"')"
  case "$_v" in
    ''|1.0) ;;
    1.1) _want_l11="$_want_l11 $_p" ;;
    *) echo "STOP: profile $_p: INSTALL_LAYOUT='$_v' is not 1.0 or 1.1" >&2; exit 1 ;;
  esac
done
if [ -n "$_want_l11" ]; then
  for _f in apkg/apkg kpkg/catalog INPUTS; do
    [ -f "$L11_IN/$_f" ] || { echo "STOP: INSTALL_LAYOUT=1.1 requested by${_want_l11} but $L11_IN/$_f is missing (tools/build-l11-inputs.sh)" >&2; exit 1; }
  done
  for _p in kbootset loader-amix; do
    grep -q "^$_p|\|^#kpkg $_p " "$L11_IN/kpkg/catalog" \
      || { echo "STOP: $L11_IN/kpkg/catalog carries no $_p package (every 1.1 disk installs it)" >&2; exit 1; }
  done
  # each profile's kernel, and for a module kernel modtools and its modules (S3-31):
  # rows of the medium's catalog, of the kernel's line
  _kkey() { grep -m1 "^#kpkg $1 " "$L11_IN/kpkg/catalog" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
  for _p in $_want_l11; do
    _pf="$repo/profiles/$_p.profile"
    _kk="$(sed -n 's/^KERNEL_KPKG=//p' "$_pf" | tail -1 | tr -d '"')"
    _km="$(sed -n 's/^KERNEL_MODPKGS=//p' "$_pf" | tail -1 | tr -d '"')"
    [ "$(_kkey "$_kk" role)" = kernel ] \
      || { echo "STOP: profile $_p: KERNEL_KPKG=$_kk is not a kernel row of $L11_IN/kpkg/catalog" >&2; exit 1; }
    _kl="$(_kkey "$_kk" line)"
    if [ "$(_kkey "$_kk" kabi)" != static ]; then
      grep -q "^modtools|" "$L11_IN/kpkg/catalog" \
        || { echo "STOP: profile $_p: $_kk is a module kernel but $L11_IN/kpkg/catalog carries no modtools" >&2; exit 1; }
    elif [ -n "$_km" ]; then
      echo "STOP: profile $_p: KERNEL_MODPKGS='$_km' with the static kernel $_kk" >&2; exit 1
    fi
    for _m in $_km; do
      [ "$(_kkey "$_m" role)" = module ] && [ "$(_kkey "$_m" line)" = "$_kl" ] \
        || { echo "STOP: profile $_p: $_m is not a role=module row of line $_kl in $L11_IN/kpkg/catalog" >&2; exit 1; }
    done
  done
  rm -rf "$STAGE/l11"; mkdir -p "$STAGE/l11/bin" "$STAGE/l11/kpkg"
  if [ -n "$STRIP_COMMENTS" ]; then
    python3 "$here/strip-sh-comments.py" "$repo/src/installer/l11.sh" "$STAGE/l11/l11.sh" \
      || { echo "STOP: strip-sh-comments refused l11.sh" >&2; exit 1; }
  else
    cp "$repo/src/installer/l11.sh" "$STAGE/l11/l11.sh"
  fi
  cp "$L11_IN/apkg/apkg" "$STAGE/l11/bin/apkg"
  cp -r "$L11_IN/kpkg/catalog" "$L11_IN/kpkg/pkgs" "$STAGE/l11/kpkg/"
  cp "$L11_IN/INPUTS" "$STAGE/l11/INPUTS"
  # the CD boot tree is the medium's, not work/l11's: say which, or why there is none
  if [ -n "$CDBOOT" ]; then
    echo "cd-boot $CDBOOT, BOOT/amix-cdboot sha256 $(sha256sum < "$CDBOOT/BOOT/amix-cdboot" | cut -c1-64)" >> "$STAGE/l11/INPUTS"
  else
    echo "# cd-boot: none -- the install kernel boots from the floppy pair; amix-dlm D-3 §10 (option B) adds the CD boot tree (S3-31 part 3)" >> "$STAGE/l11/INPUTS"
  fi
  cp "$repo/payload/updbootpart-l11" "$STAGE/l11/updbootpart"
  # /sbin/bcheckrc with `kbootset retry` before each of the three reboots of its root
  # fsck block (amix-dlm C2-4 v5 §7): a repair reboot must not spend a trial's single
  # attempt. Made here from core's own file (2.1, pinned) by inserting one line before
  # each `/sbin/uadmin 1 1`; install.sh writes it over the target's only while that is
  # still the stock file (bcheckrc.stock: its `sum -r`).
  _bc="$CORE_T/sbin/bcheckrc"
  [ "$(md5sum < "$_bc" | cut -c1-32)" = bff26ae7c4a0e5c23aeba6044d3421d2 ] \
    || { echo "STOP: $_bc is not the 2.1 bcheckrc (md5 bff26ae7...)" >&2; exit 1; }
  [ "$(grep -c "^		/sbin/uadmin 1 1\$" "$_bc")" = 3 ] \
    || { echo "STOP: $_bc does not carry exactly three root-fsck reboots" >&2; exit 1; }
  sed 's|^		/sbin/uadmin 1 1$|		[ -x /sbin/kbootset ] \&\& /sbin/kbootset retry >/dev/console 2>\&1\n&|' \
    "$_bc" > "$STAGE/l11/bcheckrc"
  [ "$(grep -c '^		\[ -x /sbin/kbootset \] && /sbin/kbootset retry >/dev/console 2>&1$' "$STAGE/l11/bcheckrc")" = 3 ] \
    && [ "$(wc -l < "$STAGE/l11/bcheckrc")" = "$(( $(wc -l < "$_bc") + 3 ))" ] \
    || { echo "STOP: the bcheckrc retry patch did not insert exactly three lines" >&2; exit 1; }
  sum -r "$_bc" | awk '{print $1}' > "$STAGE/l11/bcheckrc.stock"
  # /etc/inittab as modtools' postinstall must leave it (amix-dlm C3-5 v4 §5): core's,
  # with the dlm line before its first sysinit entry; install.sh compares the target's
  _it="$CORE_T/etc/inittab"
  [ "$(md5sum < "$_it" | cut -c1-32)" = 06b13538fb68ef8ba305ba04f844c3b8 ] \
    || { echo "STOP: $_it is not the 2.1 inittab (md5 06b13538...)" >&2; exit 1; }
  awk -F: 'BEGIN { L = "dlm::sysinit:/sbin/modadmin -B </dev/console >/dev/console 2>&1"; d = 0 }
    d == 0 && $3 == "sysinit" { print L; d = 1 } { print } END { if (d == 0) exit 1 }' "$_it" > "$STAGE/l11/inittab" \
    && [ "$(grep -c '^dlm:' "$STAGE/l11/inittab")" = 1 ] \
    && [ "$(grep -v '^dlm:' "$STAGE/l11/inittab" | md5sum | cut -c1-32)" = 06b13538fb68ef8ba305ba04f844c3b8 ] \
    || { echo "STOP: the expected inittab is not core's plus the one dlm line" >&2; exit 1; }
  # core's 1992 kernel, which stays when install.sh removes the name /stand/unix
  sum -r "$CORE_T/stand/2.1_unix" | awk '{print $1}' > "$STAGE/l11/2.1_unix.sum"
  # apkg's conf for finishing a target's pending transaction from the repair path
  # (install.sh names it when it stops on one): the medium's engine and kernel space
  printf '%s\n' "# apkg 0.3 -R /mnt recover, from the repair path (install.sh, l11.sh)" \
    "repo=file:///cdrom/install/l11/kpkg" "cachedir=/mnt/tmp/kpkgcache" \
    "admin=/cdrom/install/admin/pkgadd" "pkgadd=/cdrom/install/bin/pkgadd" \
    "kbootset=/mnt/sbin/kbootset" > "$STAGE/l11/recover.conf"
  chmod 0755 "$STAGE/l11/bin/apkg" "$STAGE/l11/updbootpart"
  chmod 0744 "$STAGE/l11/bcheckrc"
  chmod 0644 "$STAGE/l11/l11.sh" "$STAGE/l11/INPUTS" "$STAGE/l11/recover.conf" "$STAGE/l11/bcheckrc.stock" \
    "$STAGE/l11/inittab" "$STAGE/l11/2.1_unix.sum"
  { [ -n "$STRIP_COMMENTS" ] || cmp -s "$repo/src/installer/l11.sh" "$STAGE/l11/l11.sh"; } \
    && cmp -s "$repo/payload/updbootpart-l11" "$STAGE/l11/updbootpart" && cmp -s "$L11_IN/apkg/apkg" "$STAGE/l11/bin/apkg" \
    && diff -r "$L11_IN/kpkg/pkgs" "$STAGE/l11/kpkg/pkgs" >/dev/null \
    || { echo "STOP: staged /install/l11 is not byte-identical to $L11_IN" >&2; exit 1; }
  echo "build-install-iso: staged /install/l11 for${_want_l11}: apkg $(sha256sum "$STAGE/l11/bin/apkg" | cut -c1-16)..., $(grep -c '^#kpkg ' "$STAGE/l11/kpkg/catalog") kernel-space and $(grep -c '^[a-z][^#]*|' "$STAGE/l11/kpkg/catalog") userland package(s)"
else
  echo "build-install-iso: no requested profile sets INSTALL_LAYOUT=1.1 -- /install/l11 not staged"
fi

# --- /stand framing tools + the syslog unit (P5.4 field findings) -------------
# Every staged byte is fingerprint-gated: `sum -r` checksum AND byte size must
# match the pin or the build STOPS -- the installer's laydown must be the
# golden-proven bytes or nothing.
sum_gate() { # sum_gate FILE WANT_SUM WANT_SIZE DESC
  local got size
  got="$(sum -r "$1" | awk '{print $1}')"; size="$(wc -c <"$1")"
  if [ "$((10#$got))" -ne "$((10#$2))" ] || [ "$size" -ne "$3" ]; then
    echo "STOP: $4: sum -r $got/$size bytes, expected $2/$3 ($1)" >&2; exit 1
  fi
}

# /install/stand -- the updbootpart framing sources install.sh lays down at
# /stand (P5.4-FT; M-RUN4b field: the KERN handoff fail-closed without them).
#   boot1.boot : the 2.1 original (NOT touched by the 2.1c patch, so core's
#                extracted copy IS the golden's copy) -- 1,024 B, sum -r 41892.
#   makeiblk   : the 2.1c PATCHED build the goldens run and the metal reframe
#                was proven with -- 14,924 B, sum -r 58483 (payload/21c).
mkdir -p "$STAGE/stand"
cp "$CORE_T/stand/boot1.boot" "$STAGE/stand/boot1.boot"
cp "$repo/payload/21c/stand/makeiblk" "$STAGE/stand/makeiblk"
chmod 0644 "$STAGE/stand/boot1.boot"; chmod 0755 "$STAGE/stand/makeiblk"
sum_gate "$STAGE/stand/boot1.boot" 41892 1024  "staged boot1.boot is not the 2.1 original"
sum_gate "$STAGE/stand/makeiblk"  58483 14924 "staged makeiblk is not the 2.1c patched build"

# /install/syslog -- the 2.1c syslog unit install.sh lays down (base-8 ships
# core's syslogd BINARY but no unit: no init script, no rc links, no conf, no
# /var/log). The staged init script is the ENABLED copy: the vendor disable
# (a single bare `exit`, kerntools docs/inetd-telnet-throttle.md §4/§5) is
# commented HERE, host-side -- the miniroot driver has no sed, so the transform
# cannot happen at laydown. Gated three ways: the vendor copy must carry exactly
# ONE bare `exit` line, the enabled copy NONE (and one `#exit`), and the enabled
# bytes must match the pin.
mkdir -p "$STAGE/syslog"
cp "$repo/payload/21c/etc/syslog.conf"  "$STAGE/syslog/syslog.conf"
cp "$repo/payload/21c/usr/sbin/syslogd" "$STAGE/syslog/syslogd"
chmod 0644 "$STAGE/syslog/syslog.conf" "$STAGE/syslog/syslogd"
sum_gate "$STAGE/syslog/syslog.conf" 63870 1928  "staged syslog.conf is not the 2.1c conf 1.1"
sum_gate "$STAGE/syslog/syslogd"     53154 22728 "staged syslogd is not the 2.1c daemon"
nexit="$(grep -c '^exit$' "$repo/payload/21c/etc/init.d/syslogd" || true)"
[ "$nexit" = 1 ] || { echo "STOP: vendor init.d/syslogd carries $nexit bare 'exit' line(s), expected exactly 1 -- refusing to transform" >&2; exit 1; }
sed 's/^exit$/#exit/' "$repo/payload/21c/etc/init.d/syslogd" > "$STAGE/syslog/syslogd.init"
# The vendor start branch trusts /etc/syslog.pid with `kill -0`, and nothing removes the
# file at boot: when an earlier boot's syslogd pid belongs to another live process on
# this boot (the dlm sysinit line and S01kbnamelist move the numbering; per disk it then
# collides on every boot), syslogd never starts and no kernel message is kept. start
# and stop trust the pid only when `ps -p` shows a syslogd, and drop a stale file. The
# 1991 sh and grep: no grep -q, no read loop.
python3 - "$STAGE/syslog/syslogd.init" <<'PY' || { echo "STOP: syslogd.init pid-file transform failed" >&2; exit 1; }
import sys
p = sys.argv[1]
s = open(p).read()
start = (
    "\t    #\n\t    #\tTest for the presense of a running syslogd\n\t    #\n"
    "\t    kill -0 $pid 2> /dev/null\n"
    "\t    #\n\t    #\tIf there wasn't a pid to kill, or the process\n\t    #\tdid not exists, start syslogd\n\t    #\n"
    "\t    if [ -z \"$pid\" -o $? -ne 0 ]\n\t    then\n\t\t/usr/sbin/syslogd\n\t    fi\n")
start_new = (
    "\t    #\n\t    #\tTest for the presense of a running syslogd. The pid file\n"
    "\t    #\toutlives the boot: trust it only when ps shows that pid is a\n"
    "\t    #\tsyslogd (an earlier boot's pid can be any process now)\n\t    #\n"
    "\t    s=\n\t    if [ -n \"$pid\" ]\n\t    then\n"
    "\t\ts=`ps -p $pid 2> /dev/null | grep syslogd`\n\t    fi\n"
    "\t    if [ -z \"$s\" ]\n\t    then\n"
    "\t\trm -f /etc/syslog.pid\n\t\t/usr/sbin/syslogd\n\t    fi\n")
stop = "'stop')\n\tkill $pid 2> /dev/null\n\t;;\n"
stop_new = ("'stop')\n\ts=\n\tif [ -n \"$pid\" ]\n\tthen\n"
            "\t\ts=`ps -p $pid 2> /dev/null | grep syslogd`\n\tfi\n"
            "\tif [ -n \"$s\" ]\n\tthen\n\t\tkill $pid 2> /dev/null\n\tfi\n"
            "\trm -f /etc/syslog.pid\n\t;;\n")
if s.count(start) != 1 or s.count(stop) != 1:
    sys.exit("syslogd.init: the vendor start/stop text is not as pinned")
open(p, "w").write(s.replace(start, start_new).replace(stop, stop_new))
PY
chmod 0644 "$STAGE/syslog/syslogd.init"
if grep -q '^exit$' "$STAGE/syslog/syslogd.init" || \
   [ "$(grep -c '^#exit$' "$STAGE/syslog/syslogd.init")" != 1 ]; then
  echo "STOP: syslogd.init enablement transform failed (a live 'exit' remains or '#exit' count != 1)" >&2; exit 1
fi
sum_gate "$STAGE/syslog/syslogd.init" 28819 967 "enabled syslogd.init does not match the pinned transform"
echo "build-install-iso: staged /install/stand (boot1.boot 41892, makeiblk 58483) +"
echo "  /install/syslog (conf 63870, syslogd 53154, init ENABLED 28819 -- vendor exit commented, pid file checked by ps)"

# admin(4): the permissive install-time policy + the 183-B stock default
cat >"$STAGE/admin/pkgadd" <<'EOF'
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
cp -p "$CORE_T/var/sadm/install/admin/default" "$STAGE/admin/default"

# profiles verbatim. MEDIUM_PROFILES (read off the BASE profile, PROFILES[0]):
#   all (default) -- every tracked profile (each through lab_localize: the bench's
#                    real addresses from bench/local.env, tools/lib/lab-env.sh);
#   requested     -- ONLY the --profile names. A public disc must not carry the
#                    LAN profiles beside its own: they name the bench's addresses,
#                    zone and card MACs, and they would grep straight off the disc.
_mp="$(sed -n 's/^MEDIUM_PROFILES=//p' "$repo/profiles/${PROFILES[0]}.profile" 2>/dev/null | tail -1 | tr -d '"')"
case "$_mp" in
  ''|all)    for _f in "$repo"/profiles/*.profile; do
               lab_localize < "$_f" > "$STAGE/profiles/${_f##*/}" && touch -r "$_f" "$STAGE/profiles/${_f##*/}"; done ;;
  requested) for _p in "${PROFILES[@]}"; do
               lab_localize < "$repo/profiles/$_p.profile" > "$STAGE/profiles/$_p.profile" \
                 && touch -r "$repo/profiles/$_p.profile" "$STAGE/profiles/$_p.profile"; done
             echo "build-install-iso: MEDIUM_PROFILES=requested -> /install/profiles carries only: ${PROFILES[*]}" ;;
  *) echo "STOP: profile ${PROFILES[0]}: MEDIUM_PROFILES='$_mp' is not 'all' or 'requested'" >&2; exit 1 ;;
esac

# --- /install/profiles/BASE: the medium's own declaration of which profile it -
# was mastered for. A medium carries ONE boot slice per family, so "which rig is
# this disc for" is a mastering-time fact, not something the operator should have
# to retype: setup.sh launched with no argument reads this file, which is what
# lets the W4 miniroot hand off with a bare
#     exec sh /cdrom/install/bin/setup.sh
# The FIRST --profile wins (it is the one whose boot slice the driver defaults
# to); an explicit argument still overrides it, so every existing runbook and
# matrix invocation is unaffected.
printf '%s\n' "${PROFILES[0]}" > "$STAGE/profiles/BASE"
echo "build-install-iso: /install/profiles/BASE -> ${PROFILES[0]} (setup.sh's default base profile)"

# ---------------------------------------------------------------------------
# INSTALL ORDER(S) -- /install/order + one /install/order.<set> per offered set
# ---------------------------------------------------------------------------
# /install/order is the medium's DEFAULT order (the mastered set). It keeps its
# name and its meaning: install.sh reads it when no INSTALL_ORDER key is set, so
# every existing profile, runbook line and matrix cell is unaffected by W3b.
#
# /install/order.<set> is one file per NAMED SET this medium can satisfy in full.
# The interview's tier menu points at them by name and the driver's INSTALL_ORDER
# key consumes them; the custom screen reads order.standard for its `standard`
# keyword. All the ordering intelligence stays HERE, host-side -- a subset of a
# topological order is still topological, so the on-box custom screen only has to
# FILTER one of these files, never to solve anything.
python3 "$here/gen-install-order.py" --deps "$DEPS" --set "$SET_NAME" \
        --out "$STAGE/order" "${SELECTED[@]}"

OFFERED_SETS=()
for s in $(python3 "$SETS_PY" -f "$SETS_CONF" | awk '{print $1}'); do
  # An EMPTY set is not an installer set, and "satisfiable" is the wrong question
  # to ask about one: a medium carries all zero of its packages, so set_satisfiable
  # says yes and gen-install-order then -- correctly -- refuses a selection with no
  # `core` (its Gate 13). sets.conf declares exactly one such set on purpose:
  # `extra`, "the named handle for the packages amix-packages publishes",
  # deliberately empty, disjoint from the five installer sets "now and always",
  # and installed with `apkg install $(sets.py extra)` on a box that is already up.
  # It is not a smaller install, it is a different mechanism -- so it is skipped
  # here by the one property that distinguishes it, rather than by name. Without
  # this, adding any empty set to sets.conf breaks EVERY re-master (it did:
  # `extra` landed 2026-08-28 in packagemanager fdf299e; the previous re-master was
  # 2026-08-14, so this is the first master since, and it broke on the first try).
  # NB: set_tokens ends in `printf '%s\n' <array>`, and printf applies its format
  # ONCE even with no arguments -- so an empty set comes back as one EMPTY line,
  # i.e. an array of length 1, not 0. Count real tokens, and pass only those on.
  mapfile -t _raw < <(set_tokens $(resolve_set "$s")) || exit 1
  stoks=()
  for _t in ${_raw[@]+"${_raw[@]}"}; do [ -n "$_t" ] && stoks+=("$_t"); done
  if [ "${#stoks[@]}" -eq 0 ]; then
    echo "build-install-iso: set '$s' NOT offered (declared EMPTY -- not an installer set)"
    continue
  fi
  set_satisfiable "$s" || { echo "build-install-iso: set '$s' NOT offered (this medium does not carry all of it)"; continue; }
  python3 "$here/gen-install-order.py" --deps "$DEPS" --set "$s" \
          --out "$STAGE/order.$s" "${stoks[@]}"
  OFFERED_SETS+=("$s")
done
[ "${#OFFERED_SETS[@]}" -gt 0 ] || {
  echo "STOP: this medium satisfies NO named set -- the interview would have nothing to offer" >&2
  exit 1; }

# ---------------------------------------------------------------------------
# /install/sets -- the interview's three-tier menu, as data
# ---------------------------------------------------------------------------
# amixpkg's menu is three rows and always was (plan §2.7, screen frozen in
# docs/installer.md): row 1 the default install, row 2 everything on the medium,
# row 3 Custom. Rows 1 and 2 are MEDIA FACTS, so they are authored here rather
# than derived on the box:
#
#   <setname> <orderfile> <attested> <label...>
#
#   row 1  the `standard` set when this medium carries all of it -- that is what
#          "Standard Amiga UNIX installation" MEANT on the tape -- otherwise the
#          medium's own mastered set (on a base-8 disc there is no larger truth).
#   row 2  everything on the disc, which IS the mastered set: build-iso.sh puts
#          exactly this set's packages on the medium and refuses a base/ package
#          the set does not name.
#
# On a minimal medium the two rows are the same set, and the menu says so twice
# rather than hiding a row -- a menu whose numbering depends on the medium is a
# menu the blind-console matrix cannot type into.
ROW1_SET="$SET_NAME"; ROW1_ORD=order
if set_satisfiable standard; then
  ROW1_SET=standard
  [ -f "$STAGE/order.standard" ] && ROW1_ORD=order.standard
fi
ROW2_SET="$SET_NAME"
if [ "${#EXTRA_PKGS[@]}" -gt 0 ]; then
  # --pkg put packages on the disc that the named set does not contain, so
  # "everything on the disc" is no longer that named set and cannot borrow its
  # attestation. Fail SAFE: it becomes an unattested media-specific selection.
  ROW2_SET=media
fi
{
  echo "# amix-installng package-set table (generated by build-install-iso.sh)"
  echo "# <num> <setname> <orderfile> <attested> <label...>  -- label runs to end of line"
  echo "# attested=y means a REFERENCE INSTALLED-TREE DIGEST exists for this set."
  echo "# attested=n runs with the digest gate explicitly waived (plan §5.7) and is"
  echo "# marked \"unattested selection\" on the confirmation screen and in the log."
  echo "1 $ROW1_SET $ROW1_ORD `set_attested "$ROW1_SET"` Standard Amiga UNIX installation"
  echo "2 $ROW2_SET order `set_attested "$ROW2_SET"` Everything on the disc"
} > "$STAGE/sets"
echo "build-install-iso: /install/sets -> (1) $ROW1_SET [$ROW1_ORD, attested=`set_attested "$ROW1_SET"`]" \
     "/ (2) $ROW2_SET [order, attested=`set_attested "$ROW2_SET"`]"
echo "build-install-iso: per-set order files: ${OFFERED_SETS[*]}"

# ---------------------------------------------------------------------------
# 2. per-profile boot slice (extract + gate + manifest)
# ---------------------------------------------------------------------------
for p in "${PROFILES[@]}"; do
  pf="$repo/profiles/$p.profile"
  [ -f "$pf" ] || { echo "STOP: unknown profile '$p' ($pf)" >&2; exit 1; }
  # a 1.1 profile carries no framed chain: kbootset composes its store from the
  # kernel package in /install/l11 (staged above)
  if [ "$(sed -n 's/^INSTALL_LAYOUT=//p' "$pf" | tail -1 | tr -d '"')" = 1.1 ]; then
    echo; echo "build-install-iso: profile '$p' is INSTALL_LAYOUT=1.1 -- no boot slice; the store comes from /install/l11"
    continue
  fi
  outdir="$STAGE/boot/$(basename "$p")"
  # the profile's BOOTSLICE_IMG names boot/<name>/...; keep that <name> as the dir.
  name="$(sed -n 's/^BOOTSLICE_IMG=boot\/\([^/]*\)\/.*/\1/p' "$pf" | head -1)"
  [ -n "$name" ] || name="$p"
  outdir="$STAGE/boot/$name"
  BSARGS=(--profile "$pf" --outdir "$outdir")
  [ "$REQUIRE_GATE" -eq 1 ] && BSARGS+=(--require-gate)
  [ -n "${SRC_OVERRIDE[$p]:-}" ] && BSARGS+=(--source "${SRC_OVERRIDE[$p]}")
  # 040/060: install.sh 8b lays the framed kernel as /stand/unix -> ship it as boot/<p>/unix.
  case "$(sed -n 's/^INSTALL_CPU=//p' "$pf" | tail -1)" in 040|060) BSARGS+=(--write-kernel);; esac
  echo
  echo "build-install-iso: boot slice for profile '$p' -> boot/$name/"
  python3 "$here/build-bootslice.py" "${BSARGS[@]}"

  # Q-4.15 pick-at-install (RUN_UNIT=install): one pre-framed chain per installable unit,
  # boot/<name>/u<N>/{bootslice.img,bootslice.manifest,boot2.boot,unix}, and boot/<name>/units
  # (<id> <rootdev> <kernel sum -r> per row) -- install.sh picks the row of the chosen target id.
  run_unit="$(sed -n 's/^RUN_UNIT=//p' "$pf" | tail -1)"
  if [ "$run_unit" = install ]; then
    utab="$(sed -n 's/^UNIT_TABLE=//p' "$pf" | tail -1)"
    uids="$(sed -n 's/^INSTALLABLE_IDS=//p' "$pf" | tail -1 | tr -d '"')"
    [ -n "$utab" ] && [ -f "$repo/$utab" ] || { echo "STOP: profile $p RUN_UNIT=install but UNIT_TABLE '$utab' is missing" >&2; exit 1; }
    [ -n "$uids" ] || { echo "STOP: profile $p RUN_UNIT=install but INSTALLABLE_IDS is empty" >&2; exit 1; }
    ufam="$(sed -n 's/^FAMILY=//p' "$repo/$utab")"
    bash "$here/build-unit-donors.sh" "$repo/$utab" "$uids"
    : > "$outdir/units"
    for n in $uids; do
      set -- $(sed -n "s/^UNIT=$n //p" "$repo/$utab")
      [ "$#" -ge 4 ] || { echo "STOP: unit $n missing from $utab" >&2; exit 1; }
      echo "build-install-iso: unit $n ($1, sum -r $3, rootdev $4) -> boot/$name/u$n/"
      UBS=(--profile "$pf" --outdir "$outdir/u$n" --source "$repo/work/bootslice-donor/units/$ufam-c0-u$n.hdf"
           --expect-sumr "$3" --write-kernel)
      [ "$REQUIRE_GATE" -eq 1 ] && UBS+=(--require-gate)
      python3 "$here/build-bootslice.py" "${UBS[@]}"
      echo "$n $4 $3" >> "$outdir/units"
    done
    echo "build-install-iso: boot/$name/units:"; sed 's/^/    /' "$outdir/units"
  fi

  # D-2 (r6) fallback B, RUN_UNIT=stamp: ONE family chain on the medium + per-unit patch rows.
  # The per-unit chains are built and gated exactly as above, but in a scratch dir; only their
  # manifests, the patch rows (tools/rth1-media.py stamp: refused unless the rows reproduce the
  # unit chain byte for byte) and boot/<name>/stamp/units ("<id> <rootdev> <sum -r> <kernel bytes>")
  # are shipped.
  if [ "$run_unit" = stamp ]; then
    utab="$(sed -n 's/^UNIT_TABLE=//p' "$pf" | tail -1)"
    uids="$(sed -n 's/^INSTALLABLE_IDS=//p' "$pf" | tail -1 | tr -d '"')"
    [ -n "$utab" ] && [ -f "$repo/$utab" ] || { echo "STOP: profile $p RUN_UNIT=stamp but UNIT_TABLE '$utab' is missing" >&2; exit 1; }
    [ -n "$uids" ] || { echo "STOP: profile $p RUN_UNIT=stamp but INSTALLABLE_IDS is empty" >&2; exit 1; }
    ufam="$(sed -n 's/^FAMILY=//p' "$repo/$utab")"
    bash "$here/build-unit-donors.sh" "$repo/$utab" "$uids"
    ustage="$(mktemp -d "${TMPDIR:-/tmp}/build-install-iso-stamp.XXXXXX")"
    mkdir -p "$outdir/stamp"
    : > "$outdir/stamp/units"
    UNITARGS=()
    for n in $uids; do
      set -- $(sed -n "s/^UNIT=$n //p" "$repo/$utab")
      [ "$#" -ge 4 ] || { echo "STOP: unit $n missing from $utab" >&2; exit 1; }
      UBS=(--profile "$pf" --outdir "$ustage/u$n" --source "$repo/work/bootslice-donor/units/$ufam-c0-u$n.hdf"
           --expect-sumr "$3" --write-kernel)
      [ "$REQUIRE_GATE" -eq 1 ] && UBS+=(--require-gate)
      python3 "$here/build-bootslice.py" "${UBS[@]}"
      man="$ustage/u$n/bootslice.manifest"; [ -f "$man" ] || man="$ustage/u$n/bootslice.man"
      cp "$man" "$outdir/stamp/u$n.manifest"
      echo "$n $4 $3 $(stat -c%s "$ustage/u$n/unix")" >> "$outdir/stamp/units"
      UNITARGS+=(--unit "$n:$ustage/u$n/bootslice.img")
    done
    python3 "$here/rth1-media.py" stamp --family "$outdir/bootslice.img" "${UNITARGS[@]}" --out "$outdir/stamp"
    rm -rf "$ustage"
    echo "build-install-iso: boot/$name/stamp/units:"; sed 's/^/    /' "$outdir/stamp/units"
  fi

  # D-2 (r6): the RTO1 root-record table, when the profile names a separate boot disk
  # (ROOT_RECORD_DISK) -- one 28-byte record per installable id, the controller identity per
  # card from ROOT_RECORD_CARD<c>="<base> <id> <flags>" (RTH1 spec, amix-040-060-port 09d5c4d).
  rrd="$(sed -n 's/^ROOT_RECORD_DISK=//p' "$pf" | tail -1)"
  if [ -n "$rrd" ]; then
    rids="$(sed -n 's/^INSTALLABLE_IDS=//p' "$pf" | tail -1 | tr -d '"')"
    [ -n "$rids" ] || rids="$(sed -n 's/^TARGET_SCSI_ID=//p' "$pf" | tail -1)"
    CARDARGS=()
    for c in 0 1; do
      cv="$(sed -n "s/^ROOT_RECORD_CARD$c=//p" "$pf" | tail -1 | tr -d '"')"
      [ -n "$cv" ] && CARDARGS+=(--card "$c" $cv)
    done
    [ "${#CARDARGS[@]}" -gt 0 ] || { echo "STOP: profile $p sets ROOT_RECORD_DISK but no ROOT_RECORD_CARD0/1 identity" >&2; exit 1; }
    python3 "$here/rth1-media.py" rto1 --chain "$outdir/bootslice.img" --ids "$rids" "${CARDARGS[@]}" --out "$outdir/rto1"
  fi
done

echo
echo "=== staged /install/ tree ==="
( cd "$STAGE" && find . -type f | LC_ALL=C sort | sed 's/^/  install\//' )

# staged-engine sum table -- the frozen CD engine set (incl. the W6.4b static
# contents-fsck: sum -r 23366, 29468 bytes). `sum -r` is the BSD algorithm, and its
# checksum field == the on-box SVR4 `sum -r` first field, so a re-master's table is
# directly comparable to a value read on the box. (Byte count avoids the SVR4-vs-GNU
# 512/1024 block-size difference in the second column.)
echo
echo "=== staged /install/bin engine sums (sum -r checksum | bytes) ==="
for b in pkgadd pkgtrans pkginfo pkgchk contents-fsck pkginstall sum apkg; do
  f="$STAGE/bin/$b"
  [ -f "$f" ] || continue
  s="$(sum -r "$f" | awk '{print $1}')"
  z="$(wc -c <"$f")"
  printf '  %-14s sum-r %-7s %9s bytes\n' "$b" "$s" "$z"
done

# ---------------------------------------------------------------------------
# 3. master the ISO with the payload  (skipped for --stage-only)
# ---------------------------------------------------------------------------
if [ "$STAGE_ONLY" -eq 1 ]; then
  echo
  echo "build-install-iso: --stage-only -- staged /install/ tree at $STAGE (no ISO mastered)."
  echo "  $APKG_NOTE"
  echo "  (tools/build-raw-source.sh consumes this tree onto the RAW source disk's payload slice.)"
  exit 0
fi

echo
echo "=== mastering install CD (build-iso.sh --install-src) ==="
BIARGS=(--set "$SET" --install-src "$STAGE")
[ -n "$OUT" ] && BIARGS+=(--out "$OUT")
[ -n "$CDBOOT" ] && BIARGS+=(--cd-boot "$CDBOOT")
for x in ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"}; do BIARGS+=(--pkg "$x"); done
"$here/build-iso.sh" "${BIARGS[@]}"

echo
echo "build-install-iso: done. $APKG_NOTE"
[ "$KEEP_STAGE" -eq 1 ] || echo "(staged tree kept at $STAGE -- gitignored; pass --keep-stage is default here)"
