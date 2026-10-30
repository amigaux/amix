#!/bin/sh
#
# prepare.sh -- stage the on-box acceptance of P-31 sec 10.9 packages.
#
#     sh userland/packages/tools/pkg-smoke/prepare.sh userland/packages/<name>...
#
# Each package is built first with build/pkg/pkgbuild.sh, which writes
# out/pkg/pkg/<PKG>-<VERSION>-<PKGREV>.pkg and out/pkg/<name>/work/ (or
# under AMIX_BUILD_ROOT).  Writes out/pkg-smoke/stage/ (or PKS_STAGE), which
# the rig's host side pushes to the guest's /tmp/pks:
#   <PKG>-<VERSION>-<PKGREV>.pkg   each package's datastream
#   <name>/tests/                  each package's tests (smoke.sh runs from <name>/);
#                                  a tests/fixtures file lists source-tree paths
#                                  (one per line) copied in beside them, e.g.
#                                  upstream's own test vectors
#   PKGLIST                        "<PKG> <datastream> <name> <pkg|tests>" per
#                                  package: where its smoke.sh runs from
#   admin                          the non-interactive admin file (docs/porting.md 7)
#   guest.sh, MANIFEST.sum         sum -r of every file above, for the push check

set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../../../.." && pwd)
OUT="${AMIX_BUILD_ROOT:-$TOP/out/pkg}"
S="${PKS_STAGE:-$TOP/out/pkg-smoke/stage}"
[ $# -ge 1 ] || { echo "usage: sh userland/packages/tools/pkg-smoke/prepare.sh userland/packages/<name>..." >&2; exit 2; }

rm -rf "$S"; mkdir -p "$S"
: > "$S/PKGLIST"
for r in "$@"; do
	R=$(cd "$r" && pwd)
	( SRCDIR=
	  . "$R/package.sh"
	  P="$OUT/pkg"
	  f="$PKG-$VERSION-$PKGREV.pkg"
	  [ -f "$P/$f" ] || { echo "[FAIL] $P/$f not built" >&2; exit 1; }
	  cp "$P/$f" "$S/"
	  mkdir -p "$S/$NAME"
	  [ -d "$R/tests" ] && cp -r "$R/tests" "$S/$NAME/"
	  # where smoke.sh runs: a script whose usage line is `sh tests/smoke.sh'
	  # runs from <name>/, an older one (`sh smoke.sh') from <name>/tests/,
	  # beside its fixtures; a tests/mkfixture.py makes tests/fixture.tar here
	  M=tests
	  grep '^#  *sh tests/smoke.sh' "$R/tests/smoke.sh" >/dev/null 2>&1 && M=pkg
	  if [ -f "$R/tests/mkfixture.py" ]; then
		  python3 -I "$R/tests/mkfixture.py" "$S/$NAME/tests/fixture.tar" >/dev/null ||
			  { echo "[FAIL] $NAME/tests/mkfixture.py" >&2; exit 1; }
	  fi
	  if [ -f "$R/tests/fixtures" ]; then
		  T="$OUT/$NAME/work/${SRCDIR:-$NAME-$VERSION}"
		  grep -v '^#' "$R/tests/fixtures" | while read -r f; do
			  [ -n "$f" ] || continue
			  cp "$T/$f" "$S/$NAME/tests/" || { echo "[FAIL] fixture $T/$f" >&2; exit 1; }
		  done
	  fi
	  echo "$PKG $f $NAME $M" >> "$S/PKGLIST"
	  echo "staged $f ($(md5sum "$S/$f" | cut -d' ' -f1))$( [ -f "$R/tests/smoke.sh" ] && echo " + $NAME/tests" || echo ", no smoke test" )" )
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
