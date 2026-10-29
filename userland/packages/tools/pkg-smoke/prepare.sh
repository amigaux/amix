#!/bin/sh
#
# prepare.sh -- stage the on-box acceptance of P-31 sec 10.9 packages.
#
#     sh tools/pkg-smoke/prepare.sh recipes/<name>...
#
# INTERIM, with recipes/common/style-configure.sh: replaced by amix build/'s
# framework at move-in.  Writes build/pkg-smoke/stage/, which host-extra.sh
# pushes to the guest's /tmp/pks:
#   <PKG>-<VERSION>-<PKGREV>.pkg   each package's datastream (TOOLCHAIN's pkg dir)
#   <name>/tests/                  each package's tests (smoke.sh runs from <name>/)
#   PKGLIST                        "<PKG> <datastream> <name>" per package
#   admin                          the non-interactive admin file (PORTING.md 7)
#   guest.sh, MANIFEST.sum         sum -r of every file above, for the push check

set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
S="${PKS_STAGE:-$REPO/build/pkg-smoke/stage}"
[ $# -ge 1 ] || { echo "usage: sh tools/pkg-smoke/prepare.sh recipes/<name>..." >&2; exit 2; }

rm -rf "$S"; mkdir -p "$S"
: > "$S/PKGLIST"
for r in "$@"; do
	R=$(cd "$r" && pwd)
	( TOOLCHAIN=gcc14 PREFIX=/opt/amix
	  . "$R/package.sh"
	  case $TOOLCHAIN in gcc14) P="$REPO/build/gcc14/pkg" ;; *) P="$REPO/build/pkg" ;; esac
	  f="$PKG-$VERSION-$PKGREV.pkg"
	  [ -f "$P/$f" ] || { echo "[FAIL] $P/$f not built" >&2; exit 1; }
	  cp "$P/$f" "$S/"
	  mkdir -p "$S/$NAME"
	  cp -r "$R/tests" "$S/$NAME/"
	  echo "$PKG $f $NAME" >> "$S/PKGLIST"
	  echo "staged $f ($(md5sum "$S/$f" | cut -d' ' -f1)) + $NAME/tests" )
done
cat > "$S/admin" <<'ADM'
mail=
instance=overwrite
partial=nocheck
runlevel=nocheck
idepend=nocheck
rdepend=nocheck
space=quit
setuid=nocheck
conflict=nocheck
action=nocheck
basedir=default
ADM
cp "$HERE/guest.sh" "$S/guest.sh"
( cd "$S" && find . -type f ! -name MANIFEST.sum | sed 's|^\./||' | sort | while read -r f; do
	echo "$(sum -r "$f" | awk '{print $1}') $(stat -c%s "$f") $f"; done ) > "$S/MANIFEST.sum"
echo "stage: $S ($(grep -c . "$S/MANIFEST.sum") files)"
