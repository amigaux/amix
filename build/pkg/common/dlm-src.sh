# dlm-src.sh -- build amix-dlm artefacts (loader, kbootset, modadmin) from
# a PINNED commit, in this repository's build/.  Sourced, never executed.
#
#     . "$REPO/recipes/common/dlm-src.sh"
#     amix_dlm_build <commit> <target>...
#         e.g. boot1.img boot2.bin box/kbootset box/modadmin
#
# The sibling checkout ../amix-dlm is only READ: `git archive <commit>` exports
# the tree into build/kspace/src/amix-dlm-<commit>/ (the fetch-at-build rule:
# a pinned revision, never "whatever the working tree holds"), and amix-dlm's
# own Makefile builds the targets there.  The period cross toolchain comes
# from gcc-cross-amix's env.sh (boot1/boot2 need it), GCC 14 from the sibling
# gcc14-cross-amix (kbootset, modadmin).  Each recipe then verifies the
# outputs against its own sha256 pins, so a commit that builds different
# bytes fails rather than ships.

case "${0##*/}" in
dlm-src.sh)
	echo "[FAIL] dlm-src.sh is sourced, not executed" >&2
	exit 1
	;;
esac

AMIX_DLM="${AMIX_DLM:-$AMIX_SIBLINGS/amix-dlm}"
AMIX_G14_BUILD="${AMIX_G14_BUILD:-$AMIX_SIBLINGS/gcc14-cross-amix/build}"

amix_dlm_build() {
	_db_c="$1"; shift
	[ -d "$AMIX_DLM/.git" ] || { echo "[FAIL] no amix-dlm checkout at $AMIX_DLM" >&2; exit 1; }
	git -C "$AMIX_DLM" cat-file -e "$_db_c^{commit}" 2>/dev/null || {
		echo "[FAIL] amix-dlm has no commit $_db_c" >&2; exit 1; }
	AMIX_DLM_TREE="$AMIX_BUILD_ROOT/kspace/src/amix-dlm-$_db_c"
	if [ ! -f "$AMIX_DLM_TREE/Makefile" ]; then
		rm -rf "$AMIX_DLM_TREE"; mkdir -p "$AMIX_DLM_TREE"
		git -C "$AMIX_DLM" archive "$_db_c" | tar -x -C "$AMIX_DLM_TREE"
	fi
	_db_t=
	for _db_x in "$@"; do _db_t="$_db_t build/$_db_x"; done
	(
		. "$AMIX_SIBLINGS/gcc-cross-amix/build/env.sh" >/dev/null 2>&1
		make -C "$AMIX_DLM_TREE" G14="$AMIX_G14_BUILD" $_db_t
	) > "$AMIX_DLM_TREE.log" 2>&1 || {
		echo "[FAIL] amix-dlm $_db_c: make$_db_t failed:" >&2
		tail -15 "$AMIX_DLM_TREE.log" >&2; exit 1; }
	echo "  amix-dlm $_db_c built:$_db_t (log $AMIX_DLM_TREE.log)"
	export AMIX_DLM_TREE
	unset _db_c _db_t _db_x
}
