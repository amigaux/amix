#!/usr/bin/env bash
# build-core-tree.sh -- the stock core package extracted host-side into out/build/media/core/root, the
# tree tools/build-install-iso.sh reads as CORE_T (/usr/bin/sum, the 183-B admin default,
# /stand/boot1.boot, /sbin/bcheckrc, /etc/inittab, /stand/2.1_unix).
#
#   tools/build-core-tree.sh [--pkg FILE] [--out DIR]
#
#   --pkg   core-2.1.pkg (default: the inputs' staging/stock, make dist's release tree); refused unless its
#           sha256 is CORE_SHA256 below
#   --out   default out/build/media/core (gitignored): DIR/root is the tree, DIR/pkgmap and
#           DIR/pkginfo the package's own
#
# The host heirloom pkgtrans (amix userland/pkgtools, built into the inputs by media/build.sh) writes
# the package's files and directories; its l (hard link) and s (symlink) entries are made
# here from the pkgmap, as an installed core has them. Until 2026-10-30 this tree was the
# sibling's build/repo-staging/stock/.t/core, which stayed in the frozen workspace.

set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
repo="$(cd "$here/.." && pwd)"
. "$here/lib/media-paths.sh"

CORE_SHA256=12cfa10323048a2149959932d4444f656a5881d1d198e1f35bf22ed0d28610f1
PKG="$L11_IN/staging/stock/core-2.1.pkg"
OUT="$MEDIA_SCRATCH/core"
while [ $# -gt 0 ]; do
	case "$1" in
	--pkg)	PKG="$2"; shift 2;;
	--out)	OUT="$2"; shift 2;;
	*)	sed -n '2,14p' "$0"; exit 2;;
	esac
done
die() { echo "build-core-tree: $*" >&2; exit 1; }

PKGTRANS="$L11_IN/pkgtools/heirloom/build-host/bin/pkgtrans"
[ -x "$PKGTRANS" ] || die "no host pkgtrans at $PKGTRANS"
[ -f "$PKG" ] || die "no $PKG"
got="$(sha256sum < "$PKG" | cut -d' ' -f1)"
[ "$got" = "$CORE_SHA256" ] || die "$PKG has sha256 $got, not core-2.1's $CORE_SHA256"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/core-tree.XXXXXX")"
trap 'rm -rf "${tmp:?}"' EXIT
"$PKGTRANS" "$PKG" "$tmp" core > "$tmp/pkgtrans.log" 2>&1 || { cat "$tmp/pkgtrans.log" >&2; die "pkgtrans failed"; }
[ -d "$tmp/core/root" ] || die "pkgtrans wrote no core/root"

# the l and s entries: `part type class path=target ...`; a hard link's target is a path in
# the package, a symlink's is written as it stands
nl=0 ns=0
while read -r _ type _ spec _; do
	case "$type" in l|s) ;; *) continue;; esac
	path="${spec%%=*}" tgt="${spec#*=}"
	dst="$tmp/core/root$path"
	mkdir -p "$(dirname "$dst")"
	[ -e "$dst" ] || [ -L "$dst" ] && continue
	if [ "$type" = s ]; then
		ln -s "$tgt" "$dst"; ns=$((ns + 1))
	else
		[ -e "$tmp/core/root$tgt" ] || die "hard link $path: no $tgt in the package"
		ln "$tmp/core/root$tgt" "$dst"; nl=$((nl + 1))
	fi
done < "$tmp/core/pkgmap"

rm -rf "${OUT:?}"; mkdir -p "$(dirname "$OUT")"
mv "${tmp:?}/core" "${OUT:?}"
for f in usr/bin/sum var/sadm/install/admin/default stand/boot1.boot sbin/bcheckrc etc/inittab stand/2.1_unix; do
	[ -e "$OUT/root/$f" ] || die "the tree has no /$f"
done
echo "build-core-tree: $OUT/root from $(basename "$PKG") (sha256 ${CORE_SHA256:0:16}), $nl hard links, $ns symlinks"
