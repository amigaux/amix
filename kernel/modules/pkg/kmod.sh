# kmod.sh -- the body of every kernel/modules/<m>/pkg/build.sh: roll the
# module's kernel-space packages, <m>-k30 and <m>-k46.  Sourced, never
# executed, after the recipe has set HERE to its own directory:
#
#     HERE=$(cd "$(dirname "$0")" && pwd)
#     . "$HERE/../../pkg/kmod.sh"
#     kmod_roll "$@"
#
# kmod_roll [k30|k46]...   (default: both) sources build/pkg's harness and
# the recipe's pin.sh, then for each line runs build/pkg's kmodpkg with
# KM_ROOT the checkout, copies the datastream to $AMIX_BUILD_ROOT/kspace/pkg/
# (out/pkg/kspace/pkg/ unless AMIX_BUILD_ROOT is set) and prints
# `pkg <file> <sha256>`.  The work tree is $AMIX_BUILD_ROOT/kspace/<m>/, the
# log of each line beside it.  Exit status 1 on any failure, 2 for usage,
# 3 when an object is not built (a [MISSING] line on standard error).
#
# From pin.sh, beside kmodpkg's KM_* variables:
#   KM_FILES_COMMON  KM_FILES lines the same on both lines (may be empty)
#   KM_WHATIS        optional: the whatis fragment, relative to KM_ROOT, and
#   KM_WHATIS_SHA    its sha256; installed as /opt/amix/man/whatis.d/<PKG>
#   kmod_prepare     optional function, run before the rolls: builds what
#                    KM_FILES names that make dist's modules step does not
# and from the recipe directory: pkginfo.<line>, modreg, and prototype.<line>
# when the lines' payloads differ (the whatis fragment's name), else prototype.
#
# MIT licence, see kernel/modules/LICENSE in the amix repository.

case "${0##*/}" in
kmod.sh)
	echo "[FAIL] kmod.sh is sourced, not executed" >&2
	exit 1
	;;
esac

kmod_roll() {
	_k_lines=${*:-k30 k46}
	for _k_l in $_k_lines; do
		case $_k_l in
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
	_k_space=$AMIX_BUILD_ROOT/kspace
	_k_work=$_k_space/$KM_NAME
	mkdir -p "$_k_space/pkg" "$_k_work"

	_k_miss=
	for _k_l in $_k_lines; do
		eval _k_obj=\$KM_$(echo $_k_l | tr k K)_OBJ
		[ -f "$KM_ROOT/$_k_obj" ] || _k_miss="$_k_miss $_k_obj"
	done
	if [ -n "$_k_miss" ]; then
		for _k_o in $_k_miss; do
			echo "[MISSING] $KM_REPO/pkg: $_k_o is not built (make -C $KM_REPO/module)" >&2
		done
		exit 3
	fi
	if command -v kmod_prepare >/dev/null 2>&1; then
		kmod_prepare > "$_k_work/prepare.log" 2>&1 || {
			tail -20 "$_k_work/prepare.log" >&2
			echo "[FAIL] $KM_REPO/pkg: kmod_prepare failed; log $_k_work/prepare.log" >&2
			exit 1
		}
	fi

	for _k_l in $_k_lines; do
		_k_pkg=$KM_SHORT${_k_l#k}
		_k_r=$_k_work/recipe-$_k_l
		rm -rf "$_k_r"; mkdir -p "$_k_r"
		cp "$HERE/pkginfo.$_k_l" "$HERE/modreg" "$_k_r/"
		if [ -f "$HERE/prototype.$_k_l" ]; then
			cp "$HERE/prototype.$_k_l" "$_k_r/prototype"
		else
			cp "$HERE/prototype" "$_k_r/prototype"
		fi
		KM_FILES=${KM_FILES_COMMON:-}
		if [ -n "${KM_WHATIS:-}" ]; then
			KM_FILES="$KM_FILES
/opt/amix/man/whatis.d/$_k_pkg $KM_WHATIS $KM_WHATIS_SHA 0644"
		fi
		_k_log=$_k_work/$KM_NAME-$_k_l.log
		if ! ( REPO=$_k_work; amix_kmodpkg "$_k_r" "$_k_l" ) > "$_k_log" 2>&1; then
			tail -20 "$_k_log" >&2
			echo "[FAIL] $KM_REPO/pkg: $KM_NAME-$_k_l did not roll; log $_k_log" >&2
			exit 1
		fi
		_k_f=$_k_work/build/kspace/pkg/$_k_pkg-$KM_VERSION.pkg
		[ -f "$_k_f" ] || { echo "[FAIL] $_k_f was not rolled" >&2; exit 1; }
		cp "$_k_f" "$_k_space/pkg/"
		[ -z "${KSPACE_LIST:-}" ] || echo "$_k_space/pkg/${_k_f##*/}" >> "$KSPACE_LIST"
		echo "pkg ${_k_f##*/} $(sha256sum < "$_k_f" | cut -c1-64)"
	done
}
