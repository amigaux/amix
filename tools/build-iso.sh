#!/usr/bin/env bash
#
# build-iso.sh — author the Amix 2.1 install CD: the disc the installer uses as its
# package source.
#
# Layout (mirrors the published apkg repo tree, so the catalog format works
# unchanged — publish.sh serves <repo>/pkgs/<filename>, and the catalog's filename
# field is relative to pkgs/, which is exactly what /pkgs/<filename> is here):
#
#   /catalog            apkg catalog v1, pipe-delimited
#   /catalog.md5        its md5, as gen-catalog.py writes it
#   /pkgs/stock/*.pkg   the repackaged Amix 2.1 factory packages  (Commodore)
#   /pkgs/base/*.pkg    our own apkg client + heirloom engine     (ours, MIT)
#   /install/           installer driver + engine binaries — structure only for now
#   /MANIFEST           what this disc is: content set, every package, classification
#   /LICENSING          release status: cleared 2026-09-23, publication owner-gated
#   /BOOT/, /S/         --cd-boot only: the CD boot tree amix-dlm's `mkstore -C`
#                       writes (amix-cdboot, K30/K46 generations, Startup-Sequence)
#
# CONTENT SET. The set names are NOT ours: they are resolved from
# ../amix-packagemanager/tools/repo/sets.conf, the authored set definitions
# (minimal / standard / full / developer / x11, locked by the user 2026-08-11,
# plan §8.4), through that repo's own reference resolver `sets.py`. There is one
# grammar and one resolver for install sets, exactly as there is one catalog
# format and one generator -- a second implementation here would be a second
# thing to keep in step.
#
#   --set minimal    the proven base-8 (core bsd net text sysadm cdfs APKGENG APKG)
#   --set base       DEPRECATED SPELLING of minimal, kept because every runbook,
#                    matrix invocation and ISO filename in this repo says "base"
#   --set standard   the 14 non-opt stock packages + our three (17)
#   --set full       all 27 stock + our three (30, ~298 MB, of which 202 MB is six
#                    source packages: X11r5src 63M, Xsource 51M, gnusrc2 37M,
#                    gnusrc 22M, pubsrc 18M, emacsrc 11M)
#   --set developer  standard + Xdev/oldev (19)
#   --set x11        standard + Xtras (18)
#
# Iteration count is the real budget on this project, so the big sets stay an
# explicit choice. Whichever is chosen is recorded in /MANIFEST on the disc, so a
# disc on the bench can always say what it is.
#
# CATALOG METADATA comes from the packagemanager's REPO TREE (tools/repo/*.conf),
# not from its build staging: deps.conf (install order + the catalog's deps field),
# cats.conf (the authored category taxonomy that replaces stock's undifferentiated
# CATEGORY=system), and sets.conf. They are pure metadata -- editing one and
# re-running changes no .pkg byte and no .pkg md5 -- and the staging copy of
# deps.conf has already been observed lagging the repo tree, so the repo tree wins.
#
# HARD CONSTRAINTS — each of these breaks the disc SILENTLY, which is why each is a
# refusal rather than a warning, and why tools/lib/isocheck.py verifies them against
# the MASTERED IMAGE rather than the staging tree (see --self-test):
#
#   SINGLE SESSION.  Amix cdfs leaves read_toc and read_last_session_lba NULL, so a
#                    second session is not unsupported — it is INVISIBLE.
#   ROCK RIDGE, NO .Z. cdfs hybrid precedence is RR > Joliet > plain ISO, so RR is
#                    what our reads resolve through; Joliet is deliberately OFF
#                    rather than inherited. We have 700 MB and a 68030 — zcat costs
#                    more than the sectors, and needs writable temp space the
#                    installer environment may not have.
#   NO SPACES in any on-disc pathname. prototype(5) cannot represent one; exactly
#                    one file was excluded tape-wide from the 28,866-member stock
#                    repackaging for this reason.
#   ZERO RENAMES.    cdfs applies deterministic ~2/~3 renaming on a name collision,
#                    which silently breaks the catalog's filename lookup — the
#                    catalog says one thing, the disc holds another.
#   ODFS_NAME_MAX = 512 on Amix (the 128 cap is the AmigaOS platform only).
#   SYSTEM ID.       Blank, except on the bootable CD (--cd-boot): the A4091/A4092
#                    ROM boots a data CD whose System ID reads "AMIGA BOOT" at
#                    priority 2, above every hard disk -- right for that disc, a
#                    hijacked boot for any other.
#   RELEASE STAMP.   Stock package content is Commodore material, release-cleared
#                    2026-09-23 (Amiga Corporation's approval to distribute the
#                    Commodore Amiga binaries). Publishing a disc is still a per-artefact
#                    owner decision: the disc records it (/LICENSING + MANIFEST
#                    "publication:"), --published-by-owner DATE stamps it, and the
#                    image is never written to a git-tracked path. (Until 2026-09-23
#                    this was a private-only gate; retired 2026-09-26.)
#
# Sources are read-only: ../amix-packagemanager/build/repo-staging/ for the packages
# and its tools/repo/gen-catalog.py as the catalog generator (reused, not
# reimplemented — one catalog format with one implementation).
#
# The ISO is a build artifact and is never committed.
#
#   tools/build-iso.sh                     # base set  -> work/iso/
#   tools/build-iso.sh --set full          # all 27 stock packages
#   tools/build-iso.sh --pkg man --pkg conf
#   tools/build-iso.sh --self-test         # prove every constraint above FIRES
#   tools/build-iso.sh --set full --install-src S --cd-boot TREE   # bootable CD
#
# CD BOOT (--cd-boot TREE, amix-dlm docs/spec/10-boot-loader.md §4.4, D-3 §10). The
# A4091/A4092 ROM mounts the disc with its CD filesystem (ODFileSystem, ROM profile:
# ISO9660 + Rock Ridge + Joliet, RR first, names compared case-insensitively) and
# Kickstart runs S/Startup-Sequence -> SYS:BOOT/amix-cdboot, which loads the kernel
# and the RAM-disk root of /BOOT/K30 or /BOOT/K46. The long names (amix-cdboot,
# Startup-Sequence) resolve through Rock Ridge, already on; the line directories are
# 8.3 and read the same without it (checked on the plain ISO9660 names). The loader
# is mastered 0755: without an owner execute bit ODFileSystem reports FIBF_EXECUTE
# and AmigaDOS will not run it. The disc stays an ordinary data CD.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

PKGMGR="${PKGMGR:-$repo/../amix-packagemanager}"
STAGING="${STAGING:-$PKGMGR/build/repo-staging}"
GEN_CATALOG="${GEN_CATALOG:-$PKGMGR/tools/repo/gen-catalog.py}"
# Authored metadata, read from the sibling's REPO TREE (never its build staging).
SETS_PY="${SETS_PY:-$PKGMGR/tools/repo/sets.py}"
SETS_CONF="${SETS_CONF:-$PKGMGR/tools/repo/sets.conf}"
CATS_CONF="${CATS_CONF:-$PKGMGR/tools/repo/cats.conf}"
DEPS_CONF="${DEPS_CONF:-$PKGMGR/tools/repo/deps.conf}"

SET=base
OUT=""
VOLID="AMIX21_INSTALL"
EXTRA_PKGS=()
PUBLISHED=""
SELFTEST=0
KEEP_STAGE=0
INSTALL_SRC=""
CDBOOT=""

# `base` is this repo's historical spelling of the packagemanager's `minimal` set.
# Every runbook line, matrix invocation and ISO filename says "base", so the
# spelling is kept as an ALIAS rather than renamed; the membership is resolved from
# sets.conf like every other set, so there is no second hardcoded list to drift.
SET_ALIAS_base=minimal

usage() {
  cat <<EOF
usage: $(basename "$0") [--set NAME] [--pkg NAME]... [--out ISO] [--volid ID]
                        [--staging DIR] [--published-by-owner DATE] [--keep-stage]
                        [--self-test]

  --set NAME        content set, resolved from the packagemanager's sets.conf:
                      base       alias of 'minimal' (default; this repo's spelling)
                      minimal    the proven base-8, ~26 MB
                      standard   the 14 non-opt stock packages + our three (17)
                      full       every stock package + ours (30; ~298 MB)
                      developer  standard + Xdev/oldev (19)
                      x11        standard + Xtras (18)
  --pkg NAME        add a package by catalog name, beyond the set (repeatable)
  --out ISO         output path (default: work/iso/amix21-install-<set>-<date>.iso)
  --volid ID        ISO volume id (default: $VOLID)
  --staging DIR     package staging root (default: $STAGING)
  --published-by-owner DATE
                    record on the disc that the owner decided (on DATE,
                    YYYY-MM-DD) to publish this medium. Without it the disc is
                    stamped 'publication: unpublished'. Recording only: the
                    tool never publishes or copies anything.
  --keep-stage      keep the staged disc tree for inspection
  --install-src DIR populate /install/ on the disc from DIR (the installer
                    payload: driver, order, engine, boot-slice images, firstboot,
                    sum). Assembled by tools/build-install-iso.sh. When omitted a
                    PLACEHOLDER is written and /install/ is structure-only.
  --cd-boot TREE    make the disc bootable from an A4091/A4092 ROM: add the CD
                    boot tree amix-dlm's 'mkstore -C TREE -x amix-cdboot' wrote
                    (/BOOT, /S) and master with System ID 'AMIGA BOOT'
  --self-test       master synthetic discs and prove each hard constraint fires,
                    then exit. Needs no packages and writes no ISO to --out.
EOF
}

while [ $# -gt 0 ]; do case "$1" in
  --set)             SET="$2"; shift 2;;
  --pkg)             EXTRA_PKGS+=("$2"); shift 2;;
  --out)             OUT="$2"; shift 2;;
  --volid)           VOLID="$2"; shift 2;;
  --staging)         STAGING="$2"; shift 2;;
  --published-by-owner) PUBLISHED="$2"; shift 2;;
  --redistributable)
    echo "build-iso: --redistributable was retired 2026-09-26; use --published-by-owner DATE" >&2
    exit 2;;
  --keep-stage)      KEEP_STAGE=1; shift;;
  --install-src)     INSTALL_SRC="$2"; shift 2;;
  --cd-boot)         CDBOOT="$2"; shift 2;;
  --self-test)       SELFTEST=1; shift;;
  -h|--help)         usage; exit 0;;
  *) echo "build-iso: unknown argument: $1" >&2; usage >&2; exit 2;;
esac; done

export PYTHONPATH="$here/lib${PYTHONPATH:+:$PYTHONPATH}"

command -v xorriso >/dev/null || {
  echo "STOP: xorriso required (ISO authoring + reading the result back)" >&2; exit 1; }
command -v python3 >/dev/null || { echo "STOP: python3 required" >&2; exit 1; }

# --- self-test: prove the constraints fire, then stop -----------------------
if [ "$SELFTEST" -eq 1 ]; then
  exec python3 "$here/iso-selftest.py"
fi

# --- set resolution: sets.conf, through the packagemanager's own resolver ------
for f in "$SETS_PY" "$SETS_CONF" "$CATS_CONF" "$DEPS_CONF"; do
  [ -r "$f" ] || {
    {
      echo "STOP: authored package metadata not readable: $f"
      echo "      The install sets, the dependency graph and the category taxonomy"
      echo "      live in ../amix-packagemanager/tools/repo/ and have exactly one"
      echo "      implementation each. Restore that checkout."
    } >&2; exit 1; }
done
SET_NAME="$SET"
case "$SET" in base) SET_NAME="$SET_ALIAS_base" ;; esac
mapfile -t SET_MEMBERS < <(python3 "$SETS_PY" -f "$SETS_CONF" "$SET_NAME" 2>&1) || true
if [ "${#SET_MEMBERS[@]}" -eq 0 ] || printf '%s\n' "${SET_MEMBERS[@]}" | grep -q '^sets: '; then
  {
    echo "STOP: --set '$SET' does not resolve against $SETS_CONF"
    printf '%s\n' "${SET_MEMBERS[@]+${SET_MEMBERS[@]}}" | sed 's/^/      /'
    echo "      available: $(python3 "$SETS_PY" -f "$SETS_CONF" | awk '{print $1}' | tr '\n' ' ')base"
  } >&2; exit 2
fi

[ -d "$STAGING" ] || {
  {
    echo "STOP: package staging not found: $STAGING"
    echo "      This disc's content comes from the amix-packagemanager sibling's"
    echo "      repackaged stock tree (gitignored there, ~298 MB). It is read"
    echo "      read-only. Restore that checkout, or pass --staging <dir>."
  } >&2; exit 1; }
[ -r "$GEN_CATALOG" ] || {
  {
    echo "STOP: catalog generator not found: $GEN_CATALOG"
    echo "      The catalog format has ONE implementation and it lives in"
    echo "      amix-packagemanager. Reimplementing it here would be a second"
    echo "      thing to keep in step with the client that parses it."
  } >&2; exit 1; }

stamp="$(date -u +%Y%m%d)"
[ -n "$OUT" ] || OUT="$repo/work/iso/amix21-install-$SET-$stamp.iso"

# ===========================================================================
# RELEASE GATE — mechanical, enforced on ourselves, before anything is built
# ===========================================================================
# The stock content is release-cleared (2026-09-23), but media are never committed
# (large build artefacts; this repo is local-only) and publishing one is a
# per-artefact owner decision the disc records (see --published-by-owner).

# Gate 1 — the artifact must not be able to land somewhere committable. A ~300 MB
# ISO inside a tracked path is one `git add -A` away from being permanent, so we
# require the output to be git-ignored (or outside any git work tree entirely).
outdir="$(cd "$(dirname "$OUT")" 2>/dev/null && pwd || true)"
if [ -z "$outdir" ]; then
  outdir="$(dirname "$OUT")"; mkdir -p "$outdir"; outdir="$(cd "$outdir" && pwd)"
fi
outabs="$outdir/$(basename "$OUT")"
if git -C "$outdir" rev-parse --show-toplevel >/dev/null 2>&1; then
  if ! git -C "$outdir" check-ignore -q "$outabs"; then
    {
      echo "STOP (release gate): refusing to write the ISO to a path git would track:"
      echo "        $outabs"
      echo "      inside repo $(git -C "$outdir" rev-parse --show-toplevel)"
      echo
      echo "      Media are never committed. Write it somewhere gitignored (work/"
      echo "      is, and is the default) or outside any git work tree. This is a"
      echo "      mechanical gate, not advice — the tool will not emit the artifact"
      echo "      into a tracked path even when asked directly."
    } >&2
    exit 1
  fi
fi

# ===========================================================================
# 1. selection — explicit, and recorded in the artifact
# ===========================================================================
work="$(mktemp -d "${TMPDIR:-/tmp}/build-iso.XXXXXX")"
root="$work/disc"
TMPISO="$outabs.tmp.$$"
# Cleanup must preserve the script's exit status. The image is extracted back with
# ISO permissions (dirs r-xr-xr-x), so a plain rm -rf fails on them — and under
# `set -e` that failure inside the EXIT trap would overwrite a successful build's
# status with 1, turning a green build into a reported failure.
cleanup() {
  local rc=$?
  trap - EXIT
  if [ "$KEEP_STAGE" -eq 1 ]; then
    echo "(--keep-stage: staged tree left at $root)"
  else
    chmod -R u+w "$work" 2>/dev/null || true
    rm -rf "${work:?}" 2>/dev/null || true
  fi
  rm -f "${TMPISO:?}" 2>/dev/null || true
  exit "$rc"
}
trap cleanup EXIT

mkdir -p "$root/pkgs/stock" "$root/pkgs/base" "$root/install"

echo "build-iso: staging '$SET' set (= $SET_NAME, ${#SET_MEMBERS[@]} package(s)) from $STAGING"

# The staging inventory, indexed by CATALOG NAME. sets.conf names packages the way
# the catalog does (lowercase), while the .pkg FILES carry the SVR4 instance name's
# own case -- Cdev-2.1.pkg, X11r5src-2.1.pkg, APKGENG-1.12.0.pkg. gen-catalog.py
# bridges the two by lowercasing the pkginst, so the index does exactly that and
# nothing has to hardcode which names are capitalised.
declare -A PKG_FILE=()
declare -A PKG_AREA=()
shopt -s nullglob
for f in "$STAGING"/stock/*.pkg "$STAGING"/stock/*.pkg.Z \
         "$STAGING"/base/*.pkg "$STAGING"/base/*.pkg.Z; do
  b="${f##*/}"; tok="${b%%-[0-9]*}"
  key="${tok,,}"
  [ -z "${PKG_FILE[$key]:-}" ] || {
    echo "STOP: two staged packages both resolve to catalog name '$key': ${PKG_FILE[$key]} and $f" >&2
    exit 1; }
  PKG_FILE["$key"]="$f"
  case "$f" in "$STAGING"/stock/*) PKG_AREA["$key"]=stock ;; *) PKG_AREA["$key"]=base ;; esac
done
shopt -u nullglob

selected_stock=()
selected_base=()
missing=()
for name in "${SET_MEMBERS[@]}" ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"}; do
  key="${name,,}"
  [ -n "${PKG_FILE[$key]:-}" ] || { missing+=("$name"); continue; }
  case "${PKG_AREA[$key]}" in
    stock) selected_stock+=("${PKG_FILE[$key]}") ;;
    base)  selected_base+=("${PKG_FILE[$key]}") ;;
  esac
done
if [ "${#missing[@]}" -gt 0 ]; then
  {
    echo "STOP: set '$SET' names package(s) the staging tree does not hold: ${missing[*]}"
    echo "      staging: $STAGING (stock/ + base/)"
    echo "      A set is a promise about the disc; shipping it short would leave the"
    echo "      installer with an order file naming packages that are not there."
  } >&2; exit 1
fi
# Every base/ package must be IN the set. base/ (our apkg client, the heirloom
# engine, the cdfs userland) is what makes a disc installable at all, and all five
# authored sets carry all three -- but a disc that carried a base package the set
# does NOT name would be a disc whose contents and whose order file disagree.
shopt -s nullglob
for f in "$STAGING"/base/*.pkg "$STAGING"/base/*.pkg.Z; do
  b="${f##*/}"; key="${b%%-[0-9]*}"; key="${key,,}"
  found=0
  for name in "${SET_MEMBERS[@]}" ${EXTRA_PKGS[@]+"${EXTRA_PKGS[@]}"}; do
    [ "${name,,}" = "$key" ] && { found=1; break; }
  done
  [ "$found" = 1 ] || {
    echo "STOP: staged base package '$key' ($f) is not a member of set '$SET_NAME'." >&2
    echo "      The disc would carry a package its own install order never names." >&2
    exit 1; }
done
shopt -u nullglob
[ "${#selected_stock[@]}" -gt 0 ] || { echo "STOP: empty stock selection" >&2; exit 1; }
[ "${#selected_base[@]}" -gt 0 ] || {
  echo "STOP: set '$SET_NAME' selects no base/ package -- no engine, no installable disc" >&2
  exit 1; }
basefiles=("${selected_base[@]}")

# Gate 2 — the owner publication record must be a real date, not a free-form claim.
if [ -n "$PUBLISHED" ] && ! printf '%s' "$PUBLISHED" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  echo "STOP (release gate): --published-by-owner wants the owner's decision date as YYYY-MM-DD, got: $PUBLISHED" >&2
  exit 2
fi
if [ -n "$PUBLISHED" ]; then
  PUBLINE="published by owner decision $PUBLISHED"
else
  PUBLINE="unpublished (publishing this medium is a per-artefact owner decision)"
fi

# --- .Z refusal (gen-catalog accepts .pkg.Z, so this must be checked, not assumed)
for f in "${selected_stock[@]}" "${basefiles[@]}"; do
  case "$f" in *.Z)
    {
      echo "STOP: refusing compressed payload: $f"
      echo "      No .Z on this disc. We have 700 MB of medium and a 68030: zcat"
      echo "      costs more than the sectors it saves, and decompression needs"
      echo "      writable temp space the installer environment may not have."
    } >&2; exit 1;; esac
done

for f in "${selected_stock[@]}"; do cp -p "$f" "$root/pkgs/stock/"; done
for f in "${basefiles[@]}";   do cp -p "$f" "$root/pkgs/base/";  done
nstock="${#selected_stock[@]}"; nbase="${#basefiles[@]}"
echo "build-iso: selected $nstock stock + $nbase base package(s)"

# ===========================================================================
# 2. catalog — generated by amix-packagemanager's generator, reused unchanged
# ===========================================================================
# gen-catalog.py emits `filename` relative to its staging root, so running it on
# $root/pkgs yields rows like `stock/core-2.1.pkg` — which is exactly what
# /pkgs/<filename> resolves to on this disc, and exactly what the published HTTP
# repo serves. Same catalog, same client, different transport.
# gen-catalog.py reads its override files from the STAGING ROOT it is pointed at,
# so both are copied in beside the packages and removed again straight after. They
# are inputs, not disc content -- a stray deps.conf/cats.conf on the disc would be
# an uncatalogued file the installer would have to explain.
#
#   deps.conf  the authored dependency graph -> the catalog's `deps` field
#   cats.conf  the authored category taxonomy -> the catalog's `category` field,
#              replacing stock's undifferentiated CATEGORY=system on all 27
#              factory packages. Applied at CATALOG level: no package is re-minted,
#              so no .pkg byte and no .pkg md5 moves (W3b, plan §5.4).
#
# --isize appends the installed-size extension block (`#ext isize 1` + one
# `#isize <name> <bytes>` line per package) as a COMMENT trailer after the entry
# lines. It is what the installer's package menu sizes its sets from and what the
# free-space gate budgets against. Passing it here was blocked until tools/lib/
# isocheck.py's parse_catalog learned to skip '#' lines (W3b item 1) -- that
# parser is the one this build runs over the mastered image below.
cp -p "$DEPS_CONF" "$root/pkgs/deps.conf"
cp -p "$CATS_CONF" "$root/pkgs/cats.conf"
echo
python3 "$GEN_CATALOG" --isize "$root/pkgs" -o "$root"
# metadata inputs, not disc content (sets.conf is never staged here -- the disc's
# set table is authored by build-install-iso.sh into /install/sets)
rm -f "${root:?}/pkgs/deps.conf" "${root:?}/pkgs/cats.conf" "${root:?}/pkgs/names.conf"

[ -s "$root/catalog" ] || { echo "STOP: gen-catalog produced no catalog" >&2; exit 1; }
(cd "$root" && md5sum -c catalog.md5 >/dev/null) || {
  echo "STOP: catalog.md5 does not match the catalog it was generated with" >&2
  exit 1; }

# ===========================================================================
# 3. the rest of the disc: install/ structure, manifest, release notice
# ===========================================================================
if [ -n "$INSTALL_SRC" ]; then
  [ -d "$INSTALL_SRC" ] || {
    echo "STOP: --install-src is not a directory: $INSTALL_SRC" >&2; exit 1; }
  echo "build-iso: populating /install/ from $INSTALL_SRC"
  # copy the whole payload tree into /install/. The post-master constraint checks
  # (no spaces, no .Z, name length, zero renames) run over EVERYTHING including
  # this tree, so a malformed payload is caught at master time, not on the box.
  cp -a "$INSTALL_SRC"/. "$root/install/"
  # the static engine must be executable on the box; mastering normalises perms
  # with -rational-rock, but keep the staged tree honest.
  [ -f "$root/install/bin/pkgadd" ] || {
    echo "STOP: --install-src has no bin/pkgadd -- not a valid installer payload" >&2
    exit 1; }
  [ -f "$root/install/bin/pkginstall" ] || {
    echo "STOP: --install-src has no bin/pkginstall -- the miniroot shim exec's" \
         "/cdrom/install/bin/pkginstall; it MUST be present" >&2
    exit 1; }
else
  cat >"$root/install/PLACEHOLDER" <<'EOF'
This directory carries the installer driver and the engine binaries that run it.
It is created here so the disc layout is stable; it is populated by a later step
(build-install-iso.sh --install-src), not by build-iso.sh alone.
EOF
fi

SYSID_ARGS=()
if [ -n "$CDBOOT" ]; then
  CDBOOT="$(cd "$CDBOOT" 2>/dev/null && pwd)" || {
    echo "STOP: --cd-boot is not a directory" >&2; exit 1; }
  echo "build-iso: adding the CD boot tree from $CDBOOT"
  python3 - "$CDBOOT" <<'PY'
import sys
from isocheck import check_cdboot_tree
v = check_cdboot_tree(sys.argv[1])
for x in v:
    print("  FAIL  %s" % x)
if v:
    print("\nSTOP: --cd-boot tree is not a mkstore -C tree -- refusing to master.")
    sys.exit(1)
PY
  for d in BOOT S; do
    [ ! -e "$root/$d" ] || { echo "STOP: the disc already has /$d" >&2; exit 1; }
    cp -R "$CDBOOT/$d" "$root/$d"
  done
  find "$root/BOOT" "$root/S" -type d -exec chmod 0755 {} +
  find "$root/BOOT" "$root/S" -type f -exec chmod 0644 {} +
  chmod 0755 "$root/BOOT/amix-cdboot"
  SYSID_ARGS=(-sysid "AMIGA BOOT")
fi

cat >"$root/LICENSING" <<EOF
Amix 2.1 install CD -- release-cleared 2026-09-23.

/pkgs/stock/ holds Amix 2.1 factory packages repackaged from the original Commodore
install tape. On 2026-09-23 Amiga Corporation approved distributing the Commodore
Amiga binaries, and the project owner ruled that Amiga UNIX may be released.

Publication: $PUBLINE.

/pkgs/base/ (the apkg client and the heirloom-derived engine) is ours and carries
its own licenses. See tools/build-iso.sh.
EOF

{
  echo "amix-installng install CD"
  echo "built:        $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "content-set:  $SET (sets.conf '$SET_NAME', ${#SET_MEMBERS[@]} member(s))"
  echo "members:      ${SET_MEMBERS[*]}"
  if [ "${#EXTRA_PKGS[@]}" -gt 0 ]; then echo "extra --pkg:  ${EXTRA_PKGS[*]}"; fi
  echo "volume-id:    $VOLID"
  echo "xorriso:      $(xorriso --version 2>&1 | sed -n 's/^xorriso version *: *//p' | head -1)"
  echo "catalog:      apkg catalog v1 + the isize extension block (gen-catalog.py --isize)"
  echo "metadata:     deps.conf + cats.conf from amix-packagemanager/tools/repo/"
  echo "sessions:     1 (single-session ONLY — Amix cdfs cannot see a second one)"
  echo "extensions:   Rock Ridge on, Joliet off, no .Z compression"
  if [ -n "$CDBOOT" ]; then
    echo "system-id:    AMIGA BOOT (boots from an A4091/A4092 ROM: S/Startup-Sequence -> BOOT/amix-cdboot)"
    echo "cd-boot tree: (amix-dlm mkstore -C; sha256 | path)"
    (cd "$root" && find BOOT S -type f | LC_ALL=C sort | xargs sha256sum | sed 's/^/  /')
  else
    echo "system-id:    blank (never boots from a CD ROM ahead of a disk)"
  fi
  echo "release:      cleared 2026-09-23 (Amiga Corporation approval)"
  echo "publication:  $PUBLINE"
  echo
  echo "packages (classification | on-disc path):"
  for f in "${selected_stock[@]}"; do
    echo "  Commodore factory (release-cleared) | pkgs/stock/$(basename "$f")"
  done
  for f in "${basefiles[@]}"; do
    echo "  OURS (apkg / heirloom engine)   | pkgs/base/$(basename "$f")"
  done
} >"$root/MANIFEST"

# ===========================================================================
# 4. pre-master constraint checks (the half that is knowable before mastering)
# ===========================================================================
echo
echo "=== pre-master constraint checks ==="
python3 - "$root" <<'PY'
import sys
from isocheck import (walk_rel, walk_rel_dirs, check_no_spaces, check_name_length,
                      check_no_compression, check_no_collisions)
root = sys.argv[1]
files = walk_rel(root)
paths = files + walk_rel_dirs(root)
v = (check_no_spaces(paths) + check_name_length(paths)
     + check_no_compression(files) + check_no_collisions(files))
for x in v:
    print("  FAIL  %s" % x)
if v:
    print("\nSTOP: %d staging violation(s) — refusing to master." % len(v))
    sys.exit(1)
print("  OK    %d files / %d paths: no spaces, no .Z, no case-collisions, "
      "all components <= 512" % (len(files), len(paths)))
PY

# ===========================================================================
# 5. master — ONE session, Rock Ridge on, Joliet explicitly off
# ===========================================================================
# Both name spaces are chosen explicitly rather than inherited: cdfs precedence is
# RR > Joliet > plain ISO, so RR is what our reads resolve through, and a Joliet
# tree we did not ask for would be a second set of names that could disagree with
# the one the catalog was generated against. -r (rational-rock) turns RR on and
# normalises uid/gid/permissions; omitting -J leaves Joliet off, and step 6 asserts
# both rather than trusting the flags.
#
# WHY -as mkisofs AND NOT THE NATIVE -outdev/-commit (measured 2026-07-19):
# xorriso's native write path emits a GROWABLE layout -- the session lands at LBA 32
# with its own PVD at 48, plus a relocated superblock at LBA 16, i.e. TWO volume
# descriptor sets on a disc nobody asked to be appendable. Amix cdfs leaves read_toc
# and read_last_session_lba NULL, so it cannot resolve that ambiguity; it just reads
# LBA 16 and hopes. -as mkisofs emits the classic single-set layout, one PVD at 16.
# This was caught by the self-test's positive control, not by reasoning about flags,
# which is the argument for checking the mastered image rather than the command.
#
# No -M and no -C anywhere: those are what genuinely append a second session.
echo
echo "=== xorriso: mastering (single session, RR on, Joliet off) ==="
rm -f "${TMPISO:?}"
xorriso -as mkisofs \
        -o "$TMPISO" \
        -V "$VOLID" \
        -publisher "amix-installng" \
        -A "AMIX 2.1 INSTALL" \
        -iso-level 3 \
        -rational-rock \
        ${SYSID_ARGS[@]+"${SYSID_ARGS[@]}"} \
        "$root" 2>&1 | sed 's/^/  /'

[ -s "$TMPISO" ] || { echo "STOP: xorriso produced no image" >&2; exit 1; }

# ===========================================================================
# 6. post-master verification — read the MASTERED IMAGE back
# ===========================================================================
# Everything below is checked against the finished artifact, not the staging tree.
# Renames, on-disc names, session count and catalog resolution are only observable
# after mastering; a staging tree that looks right and an image that came out wrong
# is exactly the failure this is here to catch.
echo
echo "=== post-master verification (reading the image back) ==="
exdir="$work/extract"
xorriso -osirrox on -indev "$TMPISO" -extract / "$exdir" >/dev/null 2>&1 || {
  echo "STOP: could not read the mastered image back with xorriso" >&2; exit 1; }

python3 - "$TMPISO" "$root" "$exdir" "$CDBOOT" <<'PY'
import sys
from isocheck import (walk_rel, walk_rel_dirs, check_single_session, check_rockridge,
                      check_no_joliet, check_blank_system_id, check_no_spaces, check_name_length,
                      check_no_compression, check_zero_renames, parse_catalog,
                      check_catalog_resolves, check_no_orphan_packages,
                      parse_catalog_isize, check_catalog_isize,
                      CDBOOT_SYSTEM_ID, check_system_id, check_cdboot_plain_names,
                      check_cdboot_disc)

iso_p, staged_p, disc_p, cdboot = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
img = open(iso_p, 'rb').read()
staged = walk_rel(staged_p)
disc = walk_rel(disc_p)
disc_all = disc + walk_rel_dirs(disc_p)

fails = []
def group(title, viols):
    if viols:
        print("  FAIL  %s" % title)
        for v in viols:
            print("        %s" % v)
        fails.extend(viols)
    else:
        print("  OK    %s" % title)

group("single session (exactly one primary volume descriptor)",
      check_single_session(img))
group("Rock Ridge present (cdfs resolves RR before Joliet before plain ISO)",
      check_rockridge(img))
group("Joliet off (a second name space cdfs would never resolve through)",
      check_no_joliet(img))
if cdboot:
    group("PVD System ID '%s' (the A4091/A4092 ROM boots the disc at pri 2)"
          % CDBOOT_SYSTEM_ID, check_system_id(img, CDBOOT_SYSTEM_ID))
    group("CD boot tree on the disc byte for byte, BOOT/amix-cdboot executable",
          check_cdboot_disc(cdboot, disc_p))
    group("BOOT/K30, BOOT/K46 members keep their 8.3 names without Rock Ridge",
          check_cdboot_plain_names(img, cdboot))
else:
    group("PVD System ID blank (an A4092 ROM boots a 'CDTV'/'AMIGA BOOT' disc at pri 2)",
          check_blank_system_id(img))
group("zero collision renames: on-disc names == staged names (%d files)" % len(disc),
      check_zero_renames(staged, disc))
group("no spaces in any on-disc pathname (%d paths)" % len(disc_all),
      check_no_spaces(disc_all))
group("every on-disc name component <= ODFS_NAME_MAX (512)",
      check_name_length(disc_all))
group("no .Z payloads on the disc", check_no_compression(disc))

import os
cat_p = os.path.join(disc_p, "catalog")
if not os.path.isfile(cat_p):
    print("  FAIL  catalog present on the disc")
    fails.append("no catalog")
else:
    cat_text = open(cat_p, encoding="utf-8").read()
    rows, bad = parse_catalog(cat_text)
    group("catalog parses as apkg v1 (%d row(s))" % len(rows), bad)
    group("every catalog row resolves on the disc with matching size + md5",
          check_catalog_resolves(rows, disc_p))
    group("no .pkg on the disc is missing from the catalog",
          check_no_orphan_packages(rows, disc))
    isz = parse_catalog_isize(cat_text)
    group("the isize extension block is well-formed (%d of %d row(s) sized)"
          % (len(isz), len(rows)),
          check_catalog_isize(rows, cat_text))
    if isz:
        nb = sum(isz.values())
        print("        installed size: %d byte(s) over %d package(s); the "
              "installer budgets ~1.10x for the s5 footprint (%.1f MB)"
              % (nb, len(isz), (nb + nb // 10) / 1048576.0))
        unsized = [r["name"] for r in rows if r["name"] not in isz]
        if unsized:
            print("        UNSIZED (menu will print no figure -- never 0.0): %s"
                  % ", ".join(unsized))

print()
if fails:
    print("VERIFICATION FAILED: %d problem(s) — nothing published." % len(fails))
    sys.exit(1)
print("post-master verification: all checks passed")
PY

# ===========================================================================
# 7. publish — only a fully-verified image appears at OUT
# ===========================================================================
mkdir -p "$outdir"
mv "${TMPISO:?}" "${outabs:?}"
echo
printf 'built install CD: %s (%s bytes, %s)\n' \
  "$outabs" "$(wc -c <"$outabs")" "$(du -h "$outabs" | cut -f1)"
echo "content set: $SET — $nstock stock + $nbase base package(s); see /MANIFEST on the disc"
[ -z "$CDBOOT" ] || echo "cd boot:     System ID AMIGA BOOT, /BOOT + /S from $CDBOOT"
echo "publication: $PUBLINE"
echo "Build artefact: never commit it; publishing it is a per-artefact owner decision."
