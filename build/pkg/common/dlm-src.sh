# dlm-src.sh -- build amix-dlm artefacts (loader, kbootset, modadmin, the
# ABI kits) from a PINNED commit, in this repository's build/.  Sourced,
# never executed.
#
#     . "$AMIX_PKG_COMMON/dlm-src.sh"
#     amix_dlm_build <commit> <target>...
#         e.g. boot1.img boot2.bin box/kbootset box/modadmin
#     amix_dlm_kit <commit> [<amix-modules commit>] [<port commit>]
#         `make kit`: $AMIX_DLM_TREE/build/kit/{k30,k46}, KIT_REV=<commit>
#
# amix-dlm now lives in the amix monorepo under kernel/dlm, amix-modules
# under kernel/modules (moved in by subtree merge, hashes kept).  The sibling
# checkout ../amix is only READ: `git archive` exports the pinned commit's
# tree into build/kspace/src/amix-dlm-<commit>/ (the fetch-at-build rule: a
# pinned revision, never "whatever the working tree holds"), and amix-dlm's
# own Makefile builds the targets there.  A commit from before the move-in
# has the project at its root and is archived whole (the same tree as in the
# old repository); a later amix commit is archived as <commit>:kernel/dlm
# (amix_src_treeish).  AMIX_DLM / AMIX_MODULES name another checkout.  The
# period cross toolchain is layout.sh's AMIX_CROSS_ENV, gcc-cross-amix's
# env.sh (boot1/boot2 need it), GCC 14 its AMIX_G14_BUILD (kbootset,
# modadmin), so a worktree and the build container work as the main checkout
# does; without layout.sh they are the siblings.  A box/ target first proves that
# prefix is the pinned toolchain (gcc14-pin.sh, the same pins and ABI
# self-check as TOOLCHAIN=gcc14 recipes).  Each recipe then verifies the
# outputs against its own sha256 pins, so a commit that builds different
# bytes fails rather than ships.

case "${0##*/}" in
dlm-src.sh)
	echo "[FAIL] dlm-src.sh is sourced, not executed" >&2
	exit 1
	;;
esac

AMIX_DLM="${AMIX_DLM:-$AMIX_SIBLINGS/amix}"
AMIX_MODULES="${AMIX_MODULES:-$AMIX_SIBLINGS/amix}"
AMIX_G14_BUILD="${AMIX_G14_BUILD:-$AMIX_SIBLINGS/gcc14-cross-amix/build}"
AMIX_CROSS_ENV="${AMIX_CROSS_ENV:-$AMIX_SIBLINGS/gcc-cross-amix/build/env.sh}"
# the port's checkout the kit's headers come from (AMIX_PORT_REPO); a
# pinned commit it lacks is fetched by hash from AMIX_PORT_URL (make dist
# gives a cache repository and kernel/port/port.pin's URL)
AMIX_PORT_REPO="${AMIX_PORT_REPO:-$AMIX_SIBLINGS/amix-040-060-port}"

# amix_src_treeish <checkout> <commit> <subdir> <probe> -- the tree-ish to
# archive for a project at <commit>: <commit> itself when <probe> is at its
# root (a commit from before the move-in), <commit>:<subdir> when it is under
# <subdir> (an amix commit).  Prints it; returns 1 when neither holds.
amix_src_treeish() {
	if git -C "$1" cat-file -e "$2:$4" 2>/dev/null; then
		echo "$2"
	elif git -C "$1" cat-file -e "$2:$3/$4" 2>/dev/null; then
		echo "$2:$3"
	else
		return 1
	fi
}

# amix_dlm_export <commit> -- the git archive of <commit> in
# build/kspace/src/amix-dlm-<commit>/ (once); sets AMIX_DLM_TREE.
amix_dlm_export() {
	git -C "$AMIX_DLM" rev-parse --git-dir >/dev/null 2>&1 || {
		echo "[FAIL] no amix checkout at $AMIX_DLM" >&2; exit 1; }
	git -C "$AMIX_DLM" cat-file -e "$1^{commit}" 2>/dev/null || {
		echo "[FAIL] amix-dlm has no commit $1 in $AMIX_DLM" >&2; exit 1; }
	_de_t=$(amix_src_treeish "$AMIX_DLM" "$1" kernel/dlm Makefile) || {
		echo "[FAIL] amix-dlm $1: no Makefile at the root or under kernel/dlm" >&2; exit 1; }
	AMIX_DLM_TREE="$AMIX_BUILD_ROOT/kspace/src/amix-dlm-$1"
	if [ ! -f "$AMIX_DLM_TREE/Makefile" ]; then
		rm -rf "$AMIX_DLM_TREE"; mkdir -p "$AMIX_DLM_TREE"
		git -C "$AMIX_DLM" archive "$_de_t" | tar -x -C "$AMIX_DLM_TREE"
	fi
	unset _de_t
	export AMIX_DLM_TREE
}

# amix_dlm_g14_check -- before a box/ target: amix-dlm's Makefile links the
# box binaries with $AMIX_G14_BUILD's prefix directly (no gcc14-env.sh), so
# the prefix must be the pinned toolchain (gcc14-pin.sh: the sha256 pins, the
# return-value ABI self-check of its compiler) and its sysroot the
# $AMIX_G14_BUILD/sysroot the Makefile links against.
amix_dlm_g14_check() {
	. "$AMIX_PKG_COMMON/gcc14-pin.sh"
	amix_g14_identity "$AMIX_G14_BUILD/prefix" || return 1
	_dg_sr=$("$AMIX_G14_BUILD/prefix/bin/m68k-elf-gcc" -print-sysroot 2>/dev/null)
	[ "$(cd "$_dg_sr" 2>/dev/null && pwd -P)" = "$(cd "$AMIX_G14_BUILD/sysroot" 2>/dev/null && pwd -P)" ] || {
		echo "[FAIL] gcc14: the compiler's sysroot '$_dg_sr' is not $AMIX_G14_BUILD/sysroot" >&2
		unset _dg_sr; return 1; }
	unset _dg_sr
	echo "  gcc14 identity ok: gcc14-cross-amix $(echo "$AMIX_GCC14_COMMIT" | cut -c1-7) pins, return-value ABI self-check passed ($AMIX_G14_BUILD/prefix)"
}

amix_dlm_build() {
	_db_c="$1"; shift
	amix_dlm_export "$_db_c"
	_db_t=
	for _db_x in "$@"; do _db_t="$_db_t build/$_db_x"; done
	# box/: the pinned toolchain, and no object left from another one --
	# amix-dlm's object rules do not depend on the compiler, so an export
	# built before a re-pin would keep its old objects (amix-dlm's own
	# build/box at 4442c76 links three pre-cf461e3 objects that way)
	_db_st="$AMIX_DLM_TREE/build/box/.g14-pins"
	case " $* " in *" box/"*)
		amix_dlm_g14_check || exit 1
		if [ -d "$AMIX_DLM_TREE/build/box" ] && [ "$(cat "$_db_st" 2>/dev/null)" != "$AMIX_GCC14_PINS" ]; then
			echo "  amix-dlm $_db_c: build/box was not built by this toolchain: removed"
			rm -rf "$AMIX_DLM_TREE/build/box"
		fi ;;
	*) _db_st= ;;
	esac
	(
		. "$AMIX_CROSS_ENV" >/dev/null 2>&1
		make -C "$AMIX_DLM_TREE" G14="$AMIX_G14_BUILD" $_db_t
	) > "$AMIX_DLM_TREE.log" 2>&1 || {
		echo "[FAIL] amix-dlm $_db_c: make$_db_t failed:" >&2
		tail -15 "$AMIX_DLM_TREE.log" >&2; exit 1; }
	[ -z "$_db_st" ] || echo "$AMIX_GCC14_PINS" > "$_db_st"
	echo "  amix-dlm $_db_c built:$_db_t (log $AMIX_DLM_TREE.log)"
	export AMIX_DLM_TREE
	unset _db_c _db_t _db_x _db_st
}

# amix_dlm_kit <commit> -- amix-dlm's own `make kit` (tools/mkkit.sh, both
# lines) in the export: build/kit/{k30,k46} under $AMIX_DLM_TREE.  mkkit.sh
# labels the kit with `git rev-parse --short HEAD` and a dirty check, which
# in an export under this repository would answer for THIS repository; the
# export is the pinned commit by construction, so a shim answers for it
# (KIT_REV=<commit>, never dirty).  The k46 kit also records PORT_REV, the
# commit of ../amix-040-060-port its 4 KiB headers come from (include-modelb/,
# with a -dirty check on immu.h/param.h; the port is AMIX_PORT_REPO, and a
# <port commit> it lacks is fetched by hash from AMIX_PORT_URL).  With
# <port commit>, mkkit's PORT
# is the git archive of that commit's include-modelb/ (and src/sys/monsw.h
# when it has one) in build/kspace/src/port-<commit>/, and the shim answers
# its two calls (PORT_REV=<port commit>, never dirty), so the kit does not
# follow the port's live HEAD.  Without it PORT is the sibling checkout and
# those two read-only calls go to the real git (PORT_REV = its HEAD).  Any
# other git call is refused.  The stock headers come from gcc-cross-amix's sysroot,
# as in amix-dlm.
# With <amix-modules commit>, sys/monsw.h comes from the git archive of that
# commit (build/kspace/src/kitmods-<commit>/amix-modules/, MONSW_H), and the
# shim answers mkkit's three calls on it (since amix-dlm 6492c3b: the commit,
# a clean diff, the toplevel), so kit.conf says MONSW_REV=amix-modules@<commit>.
# Without it mkkit finds no amix-modules beside the export and takes the
# port's src/sys/monsw.h (kits before 6492c3b record no MONSW_REV).
amix_dlm_kit() {
	amix_dlm_export "$1"
	_dk_shim="$AMIX_BUILD_ROOT/kspace/src/gitshim-$1"
	_dk_port="$AMIX_PORT_REPO"
	_dk_git=$(command -v git)
	_dk_mh=
	_dk_pc="${3:-}"
	if [ -n "$_dk_pc" ]; then
		if ! git -C "$_dk_port" cat-file -e "$_dk_pc^{commit}" 2>/dev/null && [ -n "${AMIX_PORT_URL:-}" ]; then
			# the recipe's pinned commit, fetched by hash -- by its full
			# hash only: git cannot fetch a short one.  The label (the
			# kit's PORT_REV) stays as the recipe gives it.
			if echo "$_dk_pc" | grep -Eqx '[0-9a-f]{40}'; then
				git -C "$_dk_port" fetch -q --depth 1 "$AMIX_PORT_URL" "$_dk_pc" 2>/dev/null || :
			else
				echo "[FAIL] amix-040-060-port: $_dk_port has no commit $_dk_pc, and git cannot fetch a short hash;" >&2
				echo "       give the recipe's full port hash, or an AMIX_PORT_REPO that has $_dk_pc" >&2
				exit 1
			fi
		fi
		git -C "$_dk_port" cat-file -e "$_dk_pc^{commit}" 2>/dev/null || {
			echo "[FAIL] amix-040-060-port has no commit $_dk_pc in $_dk_port${AMIX_PORT_URL:+ or at $AMIX_PORT_URL}" >&2; exit 1; }
		_dk_pt="$AMIX_BUILD_ROOT/kspace/src/port-$_dk_pc"
		if [ ! -f "$_dk_pt/include-modelb/sys/immu.h" ]; then
			rm -rf "$_dk_pt"; mkdir -p "$_dk_pt"
			_dk_pf=include-modelb
			git -C "$_dk_port" cat-file -e "$_dk_pc:src/sys/monsw.h" 2>/dev/null &&
				_dk_pf="$_dk_pf src/sys/monsw.h"
			git -C "$_dk_port" archive "$_dk_pc" $_dk_pf | tar -x -C "$_dk_pt"
		fi
		_dk_port="$_dk_pt"
	fi
	# an amix commit (after the move-in) carries kernel/modules beside
	# kernel/dlm: with no modules commit given, the kit takes sys/monsw.h
	# from the same commit
	_dk_mc="${2:-}"
	if [ -z "$_dk_mc" ] && git -C "$AMIX_DLM" cat-file -e "$1:kernel/modules/include/sys/monsw.h" 2>/dev/null; then
		_dk_mc=$1
	fi
	if [ -n "$_dk_mc" ]; then
		_dk_mr="$AMIX_BUILD_ROOT/kspace/src/kitmods-$_dk_mc/amix-modules"
		git -C "$AMIX_MODULES" cat-file -e "$_dk_mc^{commit}" 2>/dev/null || {
			echo "[FAIL] amix-modules has no commit $_dk_mc in $AMIX_MODULES" >&2; exit 1; }
		_dk_mt=$(amix_src_treeish "$AMIX_MODULES" "$_dk_mc" kernel/modules include/sys/monsw.h) || {
			echo "[FAIL] amix-modules $_dk_mc: no include/sys/monsw.h at the root or under kernel/modules" >&2; exit 1; }
		if [ ! -f "$_dk_mr/include/sys/monsw.h" ]; then
			rm -rf "$_dk_mr"; mkdir -p "$_dk_mr"
			git -C "$AMIX_MODULES" archive "$_dk_mt" | tar -x -C "$_dk_mr"
		fi
		_dk_mh="$_dk_mr/include/sys/monsw.h"
	fi
	mkdir -p "$_dk_shim"
	{
		echo '#!/bin/sh'
		echo 'case "$*" in'
		if [ -n "$_dk_pc" ]; then
			echo "\"-C $_dk_port rev-parse --short HEAD\") echo $_dk_pc ;;"
			echo "\"-C $_dk_port diff --quiet HEAD -- \"*) exit 0 ;;"
		else
			echo "\"-C $_dk_port rev-parse --short HEAD\"|\"-C $_dk_port diff --quiet HEAD -- \"*) exec $_dk_git \"\$@\" ;;"
		fi
		if [ -n "$_dk_mh" ]; then
			echo "\"-C $_dk_mr/include/sys rev-parse --short HEAD\") echo $_dk_mc ;;"
			echo "\"-C $_dk_mr/include/sys diff --quiet HEAD -- $_dk_mh\") exit 0 ;;"
			echo "\"-C $_dk_mr/include/sys rev-parse --show-toplevel\") echo $_dk_mr ;;"
		fi
		echo "*\"rev-parse --short HEAD\") echo $1 ;;"
		echo '*"status --porcelain"*) ;;'
		echo '*) echo "dlm-src.sh git shim: refused: git $*" >&2; exit 1 ;;'
		echo 'esac'
	} > "$_dk_shim/git"
	chmod +x "$_dk_shim/git"
	(
		. "$AMIX_CROSS_ENV" >/dev/null 2>&1
		if [ -n "$_dk_mh" ]; then export MONSW_H="$_dk_mh"; fi
		# KIT_REV: an archive of an amix commit is no git checkout, so
		# its mkkit takes the commit from the environment
		PATH="$_dk_shim:$PATH" GCA="$(dirname "$AMIX_CROSS_ENV")" \
			PORT="$_dk_port" KIT_REV="$1" \
			make -C "$AMIX_DLM_TREE" G14="$AMIX_G14_BUILD" kit
	) > "$AMIX_DLM_TREE.kit.log" 2>&1 || {
		echo "[FAIL] amix-dlm $1: make kit failed:" >&2
		tail -15 "$AMIX_DLM_TREE.kit.log" >&2; exit 1; }
	for _dk_l in k30 k46; do
		grep -qx "KIT_REV=$1" "$AMIX_DLM_TREE/build/kit/$_dk_l/kit.conf" || {
			echo "[FAIL] amix-dlm $1: the $_dk_l kit is not labelled KIT_REV=$1" >&2; exit 1; }
	done
	if [ -n "$_dk_pc" ]; then
		grep -qx "PORT_REV=$_dk_pc" "$AMIX_DLM_TREE/build/kit/k46/kit.conf" || {
			echo "[FAIL] amix-dlm $1: the k46 kit is not labelled PORT_REV=$_dk_pc" >&2; exit 1; }
	fi
	echo "  amix-dlm $1 built: kit k30 k46, KIT_REV=$1${_dk_pc:+ PORT_REV=$_dk_pc} (log $AMIX_DLM_TREE.kit.log)"
	unset _dk_shim _dk_l _dk_port _dk_git _dk_mr _dk_mh _dk_mt _dk_pc _dk_pt _dk_pf _dk_mc
}
