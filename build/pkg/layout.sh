# layout.sh: where the packaging harness finds things in an amix checkout.
#
# MIT licence, see LICENSE at the top of the repository.
#
#     AMIX_TOP=<top of the checkout> . build/pkg/layout.sh
#
# Sourced by pkgbuild.sh before the harness's amix-env.sh when the harness
# is build/pkg/common (or any directory other than an amix-packages
# recipes/common). Exports, keeping every value already set:
#
#   AMIX_REPO_ROOT        the top of the checkout
#   AMIX_PKG_COMMON       the harness directory (default build/pkg/common)
#   AMIX_BUILD_ROOT       where builds write: out/pkg (ignored); also
#   AMIX_GCC14_BUILD_ROOT   for TOOLCHAIN=gcc14
#   AMIX_CROSS_ENV        $GCA/env.sh, the period toolchain
#   AMIX_GCC14_ROOT       the gcc14-cross-amix checkout holding $G14,
#   AMIX_GCC14_PREFIX       $G14/prefix, the compiler, and
#   AMIX_G14_BUILD          $G14 itself (dlm-src.sh's box builds)
#   AMIX_GCA_PIN          the commits in toolchain/gcc-cross-amix.pin and
#   AMIX_G14_PIN            toolchain/gcc14-cross-amix.pin
#   AMIX_PKGMGR           userland/pkgtools; AMIX_PKGMK and AMIX_PKGTRANS
#                         are its heirloom/build-host.sh output, and
#                         AMIX_PM_SCAN060 its tools/repo/scan060.py
#   AMIX_DLM, AMIX_MODULES  this checkout (kernel/dlm and kernel/modules)
#
# GCA and G14 name the toolchains' build/ directories as in the build
# container (toolchain/README.md). Unset, GCA is the gcc-cross-amix checkout
# beside the main working tree of this checkout, and G14 the container's
# gcc14 that toolchain/extract-g14.sh copies into that main working tree's
# out/toolchain/gcc14-cross-amix.

case "${0##*/}" in
layout.sh)
	echo "[FAIL] layout.sh is sourced, not executed" >&2
	exit 1
	;;
esac

[ -n "${AMIX_TOP:-}" ] && [ -f "$AMIX_TOP/toolchain/gcc14-cross-amix.pin" ] || {
	echo "[FAIL] layout.sh: AMIX_TOP must name the top of an amix checkout" >&2
	exit 1
}

export AMIX_REPO_ROOT="${AMIX_REPO_ROOT:-$AMIX_TOP}"
export AMIX_PKG_COMMON="${AMIX_PKG_COMMON:-$AMIX_TOP/build/pkg/common}"
export AMIX_BUILD_ROOT="${AMIX_BUILD_ROOT:-$AMIX_TOP/out/pkg}"
export AMIX_GCC14_BUILD_ROOT="${AMIX_GCC14_BUILD_ROOT:-$AMIX_BUILD_ROOT}"

if [ -z "${GCA:-}" ] || [ -z "${G14:-}" ]; then
	_l_git=$(git -C "$AMIX_TOP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
		_l_sib=$(dirname "$(dirname "$_l_git")") || _l_sib=
	if [ -n "$_l_sib" ]; then
		GCA="${GCA:-$_l_sib/gcc-cross-amix/build}"
		G14="${G14:-$(dirname "$_l_git")/out/toolchain/gcc14-cross-amix/build}"
	fi
fi
if [ -n "${GCA:-}" ]; then
	export AMIX_CROSS_ENV="${AMIX_CROSS_ENV:-$GCA/env.sh}"
fi
if [ -n "${G14:-}" ]; then
	export AMIX_GCC14_ROOT="${AMIX_GCC14_ROOT:-$(dirname "$G14")}"
	export AMIX_GCC14_PREFIX="${AMIX_GCC14_PREFIX:-$G14/prefix}"
	export AMIX_G14_BUILD="${AMIX_G14_BUILD:-$G14}"
fi
read -r _l_url AMIX_GCA_PIN < "$AMIX_TOP/toolchain/gcc-cross-amix.pin"
read -r _l_url AMIX_G14_PIN < "$AMIX_TOP/toolchain/gcc14-cross-amix.pin"
export AMIX_GCA_PIN AMIX_G14_PIN

export AMIX_PKGMGR="${AMIX_PKGMGR:-$AMIX_TOP/userland/pkgtools}"
export AMIX_PKGMK="${AMIX_PKGMK:-$AMIX_PKGMGR/heirloom/build-host/bin/pkgmk}"
export AMIX_PKGTRANS="${AMIX_PKGTRANS:-$AMIX_PKGMGR/heirloom/build-host/bin/pkgtrans}"
export AMIX_PM_SCAN060="${AMIX_PM_SCAN060:-$AMIX_PKGMGR/tools/repo/scan060.py}"

export AMIX_DLM="${AMIX_DLM:-$AMIX_TOP}"
export AMIX_MODULES="${AMIX_MODULES:-$AMIX_TOP}"
unset _l_git _l_sib _l_url
