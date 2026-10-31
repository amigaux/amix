#!/bin/sh
# build.sh -- kernel/modules/random's kernel-space packages (P-38 S3.3):
# random-k30 (random30) and random-k46 (random46), amix-dlm C3-5 sec 1.
#
# usage: sh kernel/modules/random/pkg/build.sh [k30|k46]...   (default: both)
#
# make dist's kspace step calls it (build/dist.sh), after the modules step
# has built kernel/modules/random/build/<line>/mod.d/random.  build/pkg's
# kmodpkg verifies the object against pin.sh, runs the kit of KM_KIT_COMMIT's
# modcheck, stages the object and KM_FILES and rolls the datastream; this
# copies it to $AMIX_BUILD_ROOT/kspace/pkg/ (out/pkg/kspace/pkg/ unless
# AMIX_BUILD_ROOT is set) and prints `pkg <file> <sha256>` for each.  The
# roll's work tree is $AMIX_BUILD_ROOT/kspace/random/, its log beside it.
# Exit status 1 on any failure, 2 for usage, 3 when an object is not built
# (its [MISSING] line on standard error).
#
# Per line, a recipe directory is assembled under the work tree: pkginfo.<line>,
# modreg and prototype.<line> as kmodpkg's prototype, since the whatis
# fragment's name (/opt/amix/man/whatis.d/<PKG>) is the line's instance.
#
# MIT licence, see kernel/modules/LICENSE in the amix repository.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
lines=${*:-k30 k46}
for l in $lines; do
	case $l in
	k30|k46) ;;
	*) echo "usage: build.sh [k30|k46]..." >&2; exit 2 ;;
	esac
done

AMIX_TOP=$(cd "$HERE/../../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
. "$AMIX_PKG_COMMON/amix-env.sh"
. "$AMIX_PKG_COMMON/fetch.sh"
. "$AMIX_PKG_COMMON/kpkgroll.sh"
. "$AMIX_PKG_COMMON/dlm-src.sh"
. "$AMIX_PKG_COMMON/kmodpkg.sh"
. "$HERE/pin.sh"

KM_ROOT=$AMIX_REPO_ROOT
KSPACE=$AMIX_BUILD_ROOT/kspace
work=$KSPACE/random
mkdir -p "$KSPACE/pkg" "$work"

missing=
for l in $lines; do
	eval obj=\$KM_$(echo $l | tr k K)_OBJ
	[ -f "$KM_ROOT/$obj" ] || missing="$missing $obj"
done
if [ -n "$missing" ]; then
	for o in $missing; do
		echo "[MISSING] kernel/modules/random/pkg: $o is not built (make -C kernel/modules/random/module)" >&2
	done
	exit 3
fi

for l in $lines; do
	pkg=$KM_SHORT${l#k}
	r=$work/recipe-$l
	rm -rf "$r"; mkdir -p "$r"
	cp "$HERE/pkginfo.$l" "$HERE/modreg" "$r/"
	cp "$HERE/prototype.$l" "$r/prototype"
	KM_FILES="$KM_FILES_COMMON
/opt/amix/man/whatis.d/$pkg $KM_WHATIS $KM_WHATIS_SHA 0644"
	log=$work/$KM_NAME-$l.log
	if ! ( REPO=$work; amix_kmodpkg "$r" "$l" ) > "$log" 2>&1; then
		tail -20 "$log" >&2
		echo "[FAIL] kernel/modules/random/pkg: $KM_NAME-$l did not roll; log $log" >&2
		exit 1
	fi
	f=$work/build/kspace/pkg/$pkg-$KM_VERSION.pkg
	[ -f "$f" ] || { echo "[FAIL] $f was not rolled" >&2; exit 1; }
	cp "$f" "$KSPACE/pkg/"
	[ -z "${KSPACE_LIST:-}" ] || echo "$KSPACE/pkg/${f##*/}" >> "$KSPACE_LIST"
	echo "pkg ${f##*/} $(sha256sum < "$f" | cut -c1-64)"
done
