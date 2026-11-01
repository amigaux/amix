# kdrv.sh -- the body of every kernel/drivers/<d>/pkg/build.sh: roll the
# directory's kernel-space driver packages from the module objects make
# dist's drivers step built in the build container, out/modules/<line>/<name>.
# Sourced, never executed, after the recipe has set HERE to its own
# directory:
#
#     HERE=$(cd "$(dirname "$0")" && pwd)
#     . "$HERE/../../../../build/pkg/common/kdrv.sh"
#     kdrv_roll "$@"
#
# A directory with one package keeps its recipe files in pkg/ itself; one
# with several has a subdirectory per package (kernel/drivers/a4091/pkg/a4091/
# and .../a4kt710/), all rolled by the one build.sh.
#
# kdrv_roll [<name>...]   (default: every recipe) rolls each recipe's k30 and
# k46 lines through kmodpkg.sh with KM_ROOT the checkout, copies each
# datastream to $AMIX_BUILD_ROOT/kspace/pkg/ (out/pkg/kspace/pkg/ unless
# AMIX_BUILD_ROOT is set) and prints `pkg <file> <sha256>`.  The work tree is
# $AMIX_BUILD_ROOT/kspace/<name>/, the log of each line beside it.  Exit
# status 1 on any failure, 2 for usage, 3 when an object is not built (a
# [MISSING] line on standard error; the other recipes still roll).
#
# From each recipe's pin.sh, beside kmodpkg's KM_* variables (KM_PKG_VERSION
# for a package-only revision):
#   KM_K30_OBJ, KM_K46_OBJ  default out/modules/<line>/<KM_NAME>
#   KM_FILES_COMMON  KM_FILES lines the same on both lines (may be empty)
#   kdrv_prepare     optional function, run before the rolls: builds what
#                    KM_FILES names that the drivers step does not (tools),
#                    in its own compiler environment
# and from the recipe directory: pkginfo.<line>, modreg, and prototype.<line>
# when the lines' payloads differ, else prototype.
#
# Rolling compiles nothing: the harness is sourced with TOOLCHAIN=none, and
# modcheck runs in the period toolchain's environment (AMIX_CROSS_ENV).
#
# MIT licence, see LICENSE at the top of the repository.

case "${0##*/}" in
kdrv.sh)
	echo "[FAIL] kdrv.sh is sourced, not executed" >&2
	exit 1
	;;
esac

AMIX_TOP=$(cd "$HERE/../../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
TOOLCHAIN=none AMIX_RECIPE_TOOLCHAINS=none
. "$AMIX_PKG_COMMON/amix-env.sh"
. "$AMIX_PKG_COMMON/fetch.sh"
. "$AMIX_PKG_COMMON/kpkgroll.sh"
. "$AMIX_PKG_COMMON/dlm-src.sh"
. "$AMIX_PKG_COMMON/kmodpkg.sh"

# kdrv_one <recipe dir> [<name>...] -- one recipe, in a subshell
kdrv_one() {
	_d_dir=$1; shift
	unset -f kdrv_prepare 2>/dev/null || :
	KM_FILES_COMMON= KM_K30_OBJ= KM_K46_OBJ= KM_PKG_VERSION=
	. "$_d_dir/pin.sh"
	if [ $# -gt 0 ]; then
		case " $* " in *" $KM_NAME "*) ;; *) return 0 ;; esac
	fi
	KM_ROOT=$AMIX_REPO_ROOT
	KM_K30_OBJ=${KM_K30_OBJ:-out/modules/k30/$KM_NAME}
	KM_K46_OBJ=${KM_K46_OBJ:-out/modules/k46/$KM_NAME}
	_d_space=$AMIX_BUILD_ROOT/kspace
	_d_work=$_d_space/$KM_NAME
	mkdir -p "$_d_space/pkg" "$_d_work"

	_d_miss=
	for _d_o in "$KM_K30_OBJ" "$KM_K46_OBJ"; do
		[ -f "$KM_ROOT/$_d_o" ] || _d_miss="$_d_miss $_d_o"
	done
	if [ -n "$_d_miss" ]; then
		for _d_o in $_d_miss; do
			echo "[MISSING] $KM_REPO/pkg: $KM_NAME's $_d_o is not built (make drivers)" >&2
		done
		return 3
	fi
	if command -v kdrv_prepare >/dev/null 2>&1; then
		kdrv_prepare > "$_d_work/prepare.log" 2>&1 || {
			tail -20 "$_d_work/prepare.log" >&2
			echo "[FAIL] $KM_REPO/pkg: $KM_NAME's kdrv_prepare failed; log $_d_work/prepare.log" >&2
			return 1
		}
	fi

	for _d_l in k30 k46; do
		_d_pkg=$KM_SHORT${_d_l#k}
		_d_r=$_d_work/recipe-$_d_l
		rm -rf "${_d_r:?}"; mkdir -p "$_d_r"
		cp "$_d_dir/pkginfo.$_d_l" "$_d_dir/modreg" "$_d_r/"
		if [ -f "$_d_dir/prototype.$_d_l" ]; then
			cp "$_d_dir/prototype.$_d_l" "$_d_r/prototype"
		else
			cp "$_d_dir/prototype" "$_d_r/prototype"
		fi
		KM_FILES=${KM_FILES_COMMON:-}
		_d_log=$_d_work/$KM_NAME-$_d_l.log
		if ! ( REPO=$_d_work; amix_kmodpkg "$_d_r" "$_d_l" ) > "$_d_log" 2>&1; then
			tail -20 "$_d_log" >&2
			echo "[FAIL] $KM_REPO/pkg: $KM_NAME-$_d_l did not roll; log $_d_log" >&2
			return 1
		fi
		_d_f=$_d_work/build/kspace/pkg/$_d_pkg-${KM_PKG_VERSION:-$KM_VERSION}.pkg
		[ -f "$_d_f" ] || { echo "[FAIL] $_d_f was not rolled" >&2; return 1; }
		cp "$_d_f" "$_d_space/pkg/"
		[ -z "${KSPACE_LIST:-}" ] || echo "$_d_space/pkg/${_d_f##*/}" >> "$KSPACE_LIST"
		echo "pkg ${_d_f##*/} $(sha256sum < "$_d_f" | cut -c1-64)"
	done
}

kdrv_roll() {
	_d_recipes=
	if [ -f "$HERE/pin.sh" ]; then
		_d_recipes=$HERE
	else
		for _d_p in "$HERE"/*/pin.sh; do
			[ -f "$_d_p" ] && _d_recipes="$_d_recipes ${_d_p%/pin.sh}"
		done
	fi
	[ -n "$_d_recipes" ] || { echo "[FAIL] $HERE: no recipe (no pin.sh here or in a subdirectory)" >&2; exit 1; }
	_d_names=$(for _d_dir in $_d_recipes; do ( . "$_d_dir/pin.sh"; echo "$KM_NAME" ); done)
	for _d_n; do
		echo "$_d_names" | grep -qx "$_d_n" || {
			echo "usage: build.sh [<name>...], names here: $(echo $_d_names)" >&2; exit 2; }
	done
	_d_rc=0
	for _d_dir in $_d_recipes; do
		_d_one=0
		( kdrv_one "$_d_dir" "$@" ) || _d_one=$?
		case $_d_one in
		0) ;;
		3) [ "$_d_rc" -ne 0 ] || _d_rc=3 ;;
		*) exit 1 ;;
		esac
	done
	exit $_d_rc
}
