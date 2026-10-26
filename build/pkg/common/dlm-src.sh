# dlm-src.sh -- build amix-dlm artefacts (loader, kbootset, modadmin, the
# ABI kits) from a PINNED commit, in this repository's build/.  Sourced,
# never executed.
#
#     . "$REPO/recipes/common/dlm-src.sh"
#     amix_dlm_build <commit> <target>...
#         e.g. boot1.img boot2.bin box/kbootset box/modadmin
#     amix_dlm_kit <commit>
#         `make kit`: $AMIX_DLM_TREE/build/kit/{k30,k46}, KIT_REV=<commit>
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

# amix_dlm_export <commit> -- the git archive of <commit> in
# build/kspace/src/amix-dlm-<commit>/ (once); sets AMIX_DLM_TREE.
amix_dlm_export() {
	[ -d "$AMIX_DLM/.git" ] || { echo "[FAIL] no amix-dlm checkout at $AMIX_DLM" >&2; exit 1; }
	git -C "$AMIX_DLM" cat-file -e "$1^{commit}" 2>/dev/null || {
		echo "[FAIL] amix-dlm has no commit $1" >&2; exit 1; }
	AMIX_DLM_TREE="$AMIX_BUILD_ROOT/kspace/src/amix-dlm-$1"
	if [ ! -f "$AMIX_DLM_TREE/Makefile" ]; then
		rm -rf "$AMIX_DLM_TREE"; mkdir -p "$AMIX_DLM_TREE"
		git -C "$AMIX_DLM" archive "$1" | tar -x -C "$AMIX_DLM_TREE"
	fi
	export AMIX_DLM_TREE
}

amix_dlm_build() {
	_db_c="$1"; shift
	amix_dlm_export "$_db_c"
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

# amix_dlm_kit <commit> -- amix-dlm's own `make kit` (tools/mkkit.sh, both
# lines) in the export: build/kit/{k30,k46} under $AMIX_DLM_TREE.  mkkit.sh
# labels the kit with `git rev-parse --short HEAD` and a dirty check, which
# in an export under this repository would answer for THIS repository; the
# export is the pinned commit by construction, so a shim answers for it
# (KIT_REV=<commit>, never dirty) and refuses any other git call.  The
# stock headers come from gcc-cross-amix's sysroot, the k46 4 KiB headers
# from ../amix-040-060-port (include-modelb/), as in amix-dlm.
amix_dlm_kit() {
	amix_dlm_export "$1"
	_dk_shim="$AMIX_BUILD_ROOT/kspace/src/gitshim-$1"
	mkdir -p "$_dk_shim"
	{
		echo '#!/bin/sh'
		echo 'case "$*" in'
		echo "*\"rev-parse --short HEAD\") echo $1 ;;"
		echo '*"status --porcelain"*) ;;'
		echo '*) echo "dlm-src.sh git shim: refused: git $*" >&2; exit 1 ;;'
		echo 'esac'
	} > "$_dk_shim/git"
	chmod +x "$_dk_shim/git"
	(
		. "$AMIX_SIBLINGS/gcc-cross-amix/build/env.sh" >/dev/null 2>&1
		PATH="$_dk_shim:$PATH" GCA="$AMIX_SIBLINGS/gcc-cross-amix/build" \
			PORT="$AMIX_SIBLINGS/amix-040-060-port" \
			make -C "$AMIX_DLM_TREE" G14="$AMIX_G14_BUILD" kit
	) > "$AMIX_DLM_TREE.kit.log" 2>&1 || {
		echo "[FAIL] amix-dlm $1: make kit failed:" >&2
		tail -15 "$AMIX_DLM_TREE.kit.log" >&2; exit 1; }
	for _dk_l in k30 k46; do
		grep -qx "KIT_REV=$1" "$AMIX_DLM_TREE/build/kit/$_dk_l/kit.conf" || {
			echo "[FAIL] amix-dlm $1: the $_dk_l kit is not labelled KIT_REV=$1" >&2; exit 1; }
	done
	echo "  amix-dlm $1 built: kit k30 k46, KIT_REV=$1 (log $AMIX_DLM_TREE.kit.log)"
	unset _dk_shim _dk_l
}
