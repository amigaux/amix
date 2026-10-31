# common.sh -- sourced by each recipe of kernel/dlm/pkg (P-38 S3.3) once it
# has set HERE to its own directory: the amix packaging harness
# (build/pkg/layout.sh, then build/pkg/common) and where the recipes write.
#
#   KSPACE          $AMIX_BUILD_ROOT/kspace (out/pkg/kspace unless make dist
#                   sets AMIX_BUILD_ROOT): <name>/ is a recipe's build,
#                   pkg/ its datastreams
#   kspace_epoch E  exports SOURCE_DATE_EPOCH=E, the recipe's pin.sh epoch:
#                   every stamp of the roll is the package version's own,
#                   never the environment's (P-38 D-b)
#   kspace_done F   names the datastream F the recipe rolled, for build.sh
#
# Each recipe builds from a git archive of the amix commit its pin.sh names
# (dlm-src.sh), so a later checkout re-rolls the pinned version's payload.
#
# MIT licence, see LICENSE in kernel/dlm.

case "${0##*/}" in
common.sh)
	echo "[FAIL] common.sh is sourced, not executed" >&2
	exit 1
	;;
esac

AMIX_TOP=$(cd "$HERE/../../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
. "$AMIX_PKG_COMMON/amix-env.sh"
# dlm-src.sh finds gcc-cross-amix and amix-040-060-port as siblings of the
# checkout; from a worktree those are the workspace's, the directory holding
# the main working tree, as layout.sh finds it (until dlm-src.sh takes the
# toolchain and the port from layout.sh)
_c_git=$(git -C "$AMIX_TOP" rev-parse --path-format=absolute --git-common-dir)
AMIX_SIBLINGS=$(dirname "$(dirname "$_c_git")")
unset _c_git
. "$AMIX_PKG_COMMON/fetch.sh"
. "$AMIX_PKG_COMMON/pkgroll.sh"
. "$AMIX_PKG_COMMON/kpkgroll.sh"
. "$AMIX_PKG_COMMON/gates.sh"
. "$AMIX_PKG_COMMON/dlm-src.sh"

KSPACE="$AMIX_BUILD_ROOT/kspace"
mkdir -p "$KSPACE/pkg"

kspace_epoch() {
	case "$1" in
	''|*[!0-9]*) echo "[FAIL] pin.sh: SOURCE_EPOCH '$1' is not a number of seconds" >&2; exit 1 ;;
	esac
	SOURCE_DATE_EPOCH=$1
	export SOURCE_DATE_EPOCH
}

kspace_done() {
	[ -f "$1" ] || { echo "[FAIL] $1 was not rolled" >&2; exit 1; }
	[ -z "${KSPACE_LIST:-}" ] || echo "$1" >> "$KSPACE_LIST"
}
