#!/usr/bin/env bash
# build-repo-tree.sh -- the release's package repository tree, as it is published, from the inputs of record.
#
#   tools/build-repo-tree.sh --out DIR [--release 1.1] [--previous DIR]
#
# Writes DIR/<release>/ (catalog, catalog.md5, pkgs/) with amix's
# userland/pkgtools/tools/repo/assemble-release.py, the tool that writes the published tree: one catalog
# with the kernel-space packages in its #ext kpkg block, APKG/APKGENG under pkgs/base/, Commodore's
# datastreams under pkgs/stock/, everything else flat in pkgs/. The netinstall cells serve DIR/<release>
# (install-matrix.sh --mirror), so the tree a box installs from is the one a user's box will.
#
# Inputs ($L11_IN, tools/build-l11-inputs.sh; INPUTS names them):
#   make dist's userland   $L11_IN/base: the datastreams and their rows (catalog.lines), laid out here as
#                          the gen-catalog tree assemble-release takes (catalog, catalog.md5, pkgs/)
#   kernel space           the set's kspace directory (a candidate root: catalog, catalog.md5, pkgs/)
#   APKG, APKGENG          the staging's base/APKG-*.pkg and base/APKGENG-*.pkg (the set's apkg-pkg lines)
#   Commodore's            the staging's stock/ (held by assemble-release to stock-<release>.lock)
# The tree passes amix's tools/release-check and apkg's own reading of it (the inputs' host apkg). Then the userland datastreams in the tree are checked against the CD's base/
# ones, byte for byte. Needs $PRIVACY_PATTERNS (the bench's local names). Exit 0 written, 1 refused, 2 usage.
set -uo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; repo="$(dirname "$here")"
# the workspace: the directory holding this repository's git directory (a worktree's too)
ws="$(cd "$(dirname "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)")/.." && pwd)"
OUT= REL=1.1
while [ $# -gt 0 ]; do
	case "$1" in
	--out) OUT="$2"; shift 2 ;;
	--release) REL="$2"; shift 2 ;;
	--previous) PREV="$2"; shift 2 ;;
	*) sed -n '2,22p' "$0"; exit 2 ;;
	esac
done
die() { echo "build-repo-tree: STOP: $*" >&2; exit 1; }
# --previous DIR: the published tree, read-only: assemble-release keeps its older versions, and refuses a
# published name and version whose bytes differ, so a re-publish removes nothing a box may have listed
[ -z "${PREV:-}" ] || [ -d "$PREV" ] || die "--previous: no directory $PREV"
[ -n "$OUT" ] || { sed -n '2,6p' "$0" >&2; exit 2; }
[ -n "${PRIVACY_PATTERNS:-}" ] && [ -f "$PRIVACY_PATTERNS" ] || die "PRIVACY_PATTERNS (the bench's local names) is required"
L11_IN="${L11_IN:-$repo/work/l11}"
[ -f "$L11_IN/INPUTS" ] || die "no $L11_IN/INPUTS (tools/build-l11-inputs.sh)"
[ ! -s "$L11_IN/UNPINNED" ] || die "$L11_IN rolled userland unpinned: not inputs of record"
# the pinned tools ($L11_IN: pkgtools and amix tools/ at the set's revision), never the amix checkout's tip
AR="$L11_IN/pkgtools/tools/repo/assemble-release.py" RC="$L11_IN/amix-tools/release-check"
[ -f "$AR" ] && [ -x "$RC" ] || die "no pinned assemble-release or release-check under $L11_IN (tools/build-l11-inputs.sh)"
# scan060-g14 applies its KNOWN_STOCK_DATA (the stock archive members whose tables sit in .text, e.g.
# libcrypt.a's des_crypt.o) only with the GCC 14 sysroot named, as make dist's release step does;
# without it those tables scan as code (48 movepw in dropbear). G14: build-l11-inputs' toolchain.
G14="${G14:-$ws/gcc14-cross-amix/build}"
AMIX_SYSROOT=$("$G14/prefix/bin/m68k-elf-gcc" -print-sysroot 2>/dev/null) && [ -d "$AMIX_SYSROOT/usr/lib" ] \
	|| die "no GCC 14 sysroot from $G14/prefix/bin/m68k-elf-gcc -print-sysroot (scan060-g14 needs it for its known stock data)"
export AMIX_SYSROOT
[ -f "$AR" ] || die "no $AR (amix master)"
KS="$(sed -n 's/^#   kspace //p' "$L11_IN/INPUTS")"
[ -n "$KS" ] && [ -f "$ws/$KS/catalog" ] || die "INPUTS names no kernel-space tree ($KS)"
ST="$L11_IN/staging"
W="$OUT/work"
rm -rf "${W:?}"; mkdir -p "$W/userland/pkgs" "$W/apkg"
# make dist's userland as a gen-catalog tree: its rows verbatim, its datastreams flat in pkgs/
{ echo "#apkg-catalog 1"; sort "$L11_IN/base/catalog.lines"; } > "$W/userland/catalog"
while IFS='|' read -r n v i f m s _; do
	[ -f "$L11_IN/base/$f" ] || die "no $L11_IN/base/$f ($n $v)"
	cp "$L11_IN/base/$f" "$W/userland/pkgs/$f"
done < "$L11_IN/base/catalog.lines"
( cd "$W/userland" && md5sum catalog > catalog.md5 )
for p in APKG APKGENG; do
	set -- "$ST"/base/$p-[0-9]*.pkg
	[ $# = 1 ] && [ -f "$1" ] || die "the staging's base/ has not exactly one $p datastream"
	cp "$1" "$W/apkg/"
done
D="$OUT/$REL"
rm -rf "${D:?}"
# its 68060 scan unpacks each datastream with the inputs' host pkgtrans; GCC 14 ELFs go through build/pkg's
# scan060-g14.py at the same revision, where the inputs have it (an older assemble-release has no such scan)
G14=(); [ ! -f "$L11_IN/amix-gcc14/scan060-g14.py" ] || G14=(--scan060-g14 "$L11_IN/amix-gcc14/scan060-g14.py")
AMIX_PKGTRANS="$L11_IN/pkgtools/heirloom/build-host/bin/pkgtrans" python3 "$AR" --userland "$W/userland" --kspace "$ws/$KS" --apkg "$W/apkg" --stock "$ST/stock" --release "$REL" \
	--out "$D" --release-check "$RC" --rom-register "$ws/roms/MANIFEST.sha256" \
	--private-patterns "$PRIVACY_PATTERNS" --apkg-bin "$L11_IN/apkg/apkg-host" "${G14[@]+"${G14[@]}"}" ${PREV:+--previous "$PREV"} > "$OUT/assemble.log" 2>&1
rc=$?
[ "$rc" = 0 ] || { tail -15 "$OUT/assemble.log" >&2; die "assemble-release.py refused or failed (rc $rc; $OUT/assemble.log)"; }
# the CD's bytes: every userland row's datastream is the one the CD carries in base/ (under its pkginst name)
while IFS='|' read -r n v i f m s _; do
	cmp -s "$D/pkgs/$f" "$ST/../base/$i.pkg" 2>/dev/null || cmp -s "$D/pkgs/$f" "$L11_IN/base/$f" \
		|| die "the tree's pkgs/$f is not the inputs' $n datastream"
done < "$L11_IN/base/catalog.lines"
grep -q '^#ext kpkg 1$' "$D/catalog" || die "the tree's catalog has no kernel-space block"
echo "build-repo-tree: $D: $(grep -c '|' "$D/catalog") rows, $(grep -c '^#kpkg ' "$D/catalog") kernel-space; catalog md5 $(cut -c1-8 "$D/catalog.md5")"
