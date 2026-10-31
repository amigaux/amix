# common.sh -- sourced by each recipe of kernel/k30/pkg (P-38 S3.3) once it
# has set HERE to its own directory: the amix packaging harness
# (build/pkg/layout.sh, then build/pkg/common) and where the recipes write.
#
#   KSPACE          $AMIX_BUILD_ROOT/kspace (out/pkg/kspace unless make dist
#                   sets AMIX_BUILD_ROOT): <name>/ is a recipe's build,
#                   pkg/ its datastreams, src/ the exports it reads
#   kspace_epoch E  exports SOURCE_DATE_EPOCH=E, the recipe's pin.sh epoch:
#                   every stamp of the roll is the package version's own,
#                   never the environment's (P-38 D-b)
#   kspace_done F   names the datastream F the recipe rolled, for build.sh
#   kspace_amix_file C P OUT     amix's file P at commit C, into OUT
#   kspace_fork_have N C         the pinned fork N's commit C (in full) is in
#                   its repository, fetched by hash when not (N: port, the
#                   amix-040-060-port checkout of dlm-src.sh, whose kit
#                   then finds C by its short form; paula,
#                   kernel/drivers/paula/paula.pin)
#   kspace_fork_file N C P OUT   fork N's file P at commit C, into OUT
#
# Nothing is read from beside the checkout. The port is dlm-src.sh's
# AMIX_PORT_REPO, and a pinned commit it lacks is fetched by hash from
# AMIX_PORT_URL: make dist sets both; unset, they are a cache repository
# under $KSPACE/src and kernel/port/port.pin's URL. paula is the same with
# AMIX_PAULA_REPO and kernel/drivers/paula/paula.pin's URL.
#
# MIT licence, see LICENSE in kernel/k30.

case "${0##*/}" in
common.sh)
	echo "[FAIL] common.sh is sourced, not executed" >&2
	exit 1
	;;
esac

AMIX_TOP=$(cd "$HERE/../../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
. "$AMIX_PKG_COMMON/amix-env.sh"

KSPACE="$AMIX_BUILD_ROOT/kspace"
mkdir -p "$KSPACE/pkg" "$KSPACE/src"

if [ -z "${AMIX_PORT_REPO:-}" ]; then
	AMIX_PORT_REPO="$KSPACE/src/port-repo"
	[ -d "$AMIX_PORT_REPO/.git" ] || git init -q "$AMIX_PORT_REPO"
fi
[ -n "${AMIX_PORT_URL:-}" ] || read -r AMIX_PORT_URL _ < "$AMIX_TOP/kernel/port/port.pin"
if [ -z "${AMIX_PAULA_REPO:-}" ]; then
	AMIX_PAULA_REPO="$KSPACE/src/paula-repo"
	[ -d "$AMIX_PAULA_REPO/.git" ] || git init -q "$AMIX_PAULA_REPO"
fi
[ -n "${AMIX_PAULA_URL:-}" ] || read -r AMIX_PAULA_URL _ < "$AMIX_TOP/kernel/drivers/paula/paula.pin"
export AMIX_PORT_REPO AMIX_PORT_URL AMIX_PAULA_REPO AMIX_PAULA_URL

. "$AMIX_PKG_COMMON/fetch.sh"
. "$AMIX_PKG_COMMON/pkgroll.sh"
. "$AMIX_PKG_COMMON/kpkgroll.sh"
. "$AMIX_PKG_COMMON/gates.sh"
. "$AMIX_PKG_COMMON/dlm-src.sh"
. "$AMIX_PKG_COMMON/kfsmod.sh"

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

kspace_amix_file() {
	git -C "$AMIX_TOP" cat-file -e "$1:$2" 2>/dev/null || {
		echo "[FAIL] amix has no $2 at $1 (a full clone is needed)" >&2; exit 1; }
	git -C "$AMIX_TOP" show "$1:$2" > "$3"
}

kspace_fork_have() {
	case "$1" in
	port) _ff_r=$AMIX_PORT_REPO _ff_u=$AMIX_PORT_URL ;;
	paula) _ff_r=$AMIX_PAULA_REPO _ff_u=$AMIX_PAULA_URL ;;
	*) echo "[FAIL] kspace_fork_have: no fork '$1'" >&2; exit 1 ;;
	esac
	if ! git -C "$_ff_r" cat-file -e "$2^{commit}" 2>/dev/null; then
		git -C "$_ff_r" fetch -q --depth 1 "$_ff_u" "$2" 2>/dev/null || :
	fi
	git -C "$_ff_r" cat-file -e "$2^{commit}" 2>/dev/null || {
		echo "[FAIL] $1: no commit $2 in $_ff_r or at $_ff_u" >&2; exit 1; }
}

kspace_fork_file() {
	kspace_fork_have "$1" "$2"
	git -C "$_ff_r" cat-file -e "$2:$3" 2>/dev/null || {
		echo "[FAIL] $1: no $3 at $2" >&2; exit 1; }
	git -C "$_ff_r" show "$2:$3" > "$4"
	unset _ff_r _ff_u
}
