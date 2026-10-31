# amix-env.sh -- the one place a recipe learns what "build for Amix" means.
#
#     . "$AMIX_PKG_COMMON/amix-env.sh"
#
# Sourced, never executed.  Every recipe sources exactly this and re-derives
# nothing: PORTING.md sec 5 ("automate the recipe, never automate the porting")
# makes the harness the mechanical half, and a flag re-derived per recipe is a
# flag that will eventually differ per recipe.
#
# WHY CC IS SET EXPLICITLY AND LOUDLY.  m68k-cbm-sysv4-gcc is not a compiler,
# it is the wrapper shell script that post-processes SGS assembly through
# fix_asm before assembling (PORTING.md sec 2.2).  Six miscompiles are repaired
# there -- one of them, the fcmp operand swap, reverses floating-point
# comparisons with NO diagnostic.  A Makefile that finds gcc.real, that passes
# -S, or that calls $(AS) itself loses all six and exits 0.  So: CC is exported,
# never defaulted; recipes must not let a build system split compile from
# assemble.
#
# Host tools (sha256sum, pkgmk, pkgtrans) are named here too so a recipe cannot
# quietly fall back to a host `pkgmk` that is not the Heirloom one.

# --- guard: sourced, not run -------------------------------------------------
case "${0##*/}" in
amix-env.sh)
	echo "[FAIL] amix-env.sh is sourced, not executed" >&2
	exit 1
	;;
esac

# --- where this checkout is, and where its siblings are ----------------------
# Sibling repositories are resolved RELATIVE TO THIS CHECKOUT, never against a
# developer's $HOME: the workspace lays gcc-cross-amix and amix-packagemanager
# out beside this repo, so a clone anywhere works as long as that holds.  Every
# recipe already computes $REPO (its own repo root) before sourcing this file;
# the fallback is $0's grandparent, which is the same directory for a
# recipes/<tool>/build.sh caller.  Both siblings stay env-overridable below.
AMIX_REPO_ROOT="${AMIX_REPO_ROOT:-${REPO:-$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)}}"
AMIX_PKG_COMMON="${AMIX_PKG_COMMON:-$AMIX_REPO_ROOT/build/pkg/common}"
if [ ! -f "$AMIX_PKG_COMMON/amix-env.sh" ]; then
	echo "[FAIL] cannot locate the harness from '$0'" >&2
	echo "       Set AMIX_REPO_ROOT to the top of the amix checkout." >&2
	exit 1
fi
AMIX_SIBLINGS=$(cd "$AMIX_REPO_ROOT/.." && pwd)

# --- which toolchain ---------------------------------------------------------
# TOOLCHAIN=period (the default): gcc-cross-amix, gcc 2.7.2.3 behind the
# fix_asm wrapper -- the toolchain every published package was built with.
# TOOLCHAIN=gcc14: gcc14-cross-amix, GCC 14 (owner decision D-3 sec 9,
# 2026-10-25: the USERLAND compiler; kernel space stays on the period one).
# Everything gcc14 changes is in gcc14-env.sh.  A recipe opts in by setting
# AMIX_RECIPE_TOOLCHAINS="period gcc14" before sourcing this file; one that
# has not been ported refuses gcc14 rather than half-building.
# TOOLCHAIN=none: a script-only recipe (shell scripts, data); no compiler,
# and every compiler, assembler, linker and archiver is common/nocc, which
# refuses to run.
AMIX_TOOLCHAIN="${TOOLCHAIN:-${AMIX_TOOLCHAIN:-period}}"
case "$AMIX_TOOLCHAIN" in
period|gcc14|none) ;;
*)
	echo "[FAIL] TOOLCHAIN=$AMIX_TOOLCHAIN -- known: period (default), gcc14, none" >&2
	exit 1
	;;
esac
case " ${AMIX_RECIPE_TOOLCHAINS:-period} " in
*" $AMIX_TOOLCHAIN "*) ;;
*)
	echo "[FAIL] this recipe is not ported to TOOLCHAIN=$AMIX_TOOLCHAIN" >&2
	echo "       (it declares: ${AMIX_RECIPE_TOOLCHAINS:-period})" >&2
	exit 1
	;;
esac
export AMIX_TOOLCHAIN
# The triplet configure is told (--host): the target OS is SVR4 whatever
# compiler builds for it.  AMIX_TARGET stays the tool prefix.
export AMIX_HOST_TRIPLET=m68k-cbm-sysv4

if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
	. "$AMIX_PKG_COMMON/gcc14-env.sh"
elif [ "$AMIX_TOOLCHAIN" = none ]; then
	TARGET=none
	for _ae_t in CC CXX CPP AMIX_CPP AR RANLIB LD NM OBJDUMP STRIP; do
		eval "$_ae_t=\$AMIX_PKG_COMMON/nocc"
		export "$_ae_t"
	done
	unset _ae_t
	export AMIX_TARGET=none AMIX_ARCH_FLAGS= AMIX_CFLAGS= AMIX_CONFIGURE_LENIENT=
	export AMIX_BUILD_ROOT="${AMIX_BUILD_ROOT:-$AMIX_REPO_ROOT/out/pkg}"
else
# The period toolchain -- from here to the matching `fi', unindented.

# --- the cross toolchain -----------------------------------------------------
# The prefix and sysroot are gcc-cross-amix's, and that repo's build/env.sh is
# their source of truth.  We source it when it is there rather than duplicating
# its paths, because a second copy of a path is a path that will drift.
AMIX_CROSS_ENV="${AMIX_CROSS_ENV:-$AMIX_SIBLINGS/gcc-cross-amix/build/env.sh}"
if [ -f "$AMIX_CROSS_ENV" ]; then
	. "$AMIX_CROSS_ENV"
else
	echo "[FAIL] cross toolchain env not found: $AMIX_CROSS_ENV" >&2
	echo "       Build ../gcc-cross-amix first, or point AMIX_CROSS_ENV at its build/env.sh." >&2
	exit 1
fi

TARGET="${AMIX_CROSS_TARGET:-m68k-cbm-sysv4}"
export CC="$TARGET-gcc"
export AR="$TARGET-ar"
export RANLIB="$TARGET-ranlib"
export LD="$TARGET-ld"
export NM="$TARGET-nm"
export OBJDUMP="$TARGET-objdump"
export STRIP="$TARGET-strip"
export AMIX_TARGET="$TARGET"

command -v "$CC" >/dev/null 2>&1 || {
	echo "[FAIL] $CC not on PATH (prefix ${AMIX_CROSS_PREFIX:-unset})" >&2
	exit 1
}

# The wrapper must BE the wrapper.  If someone ever points CC at gcc.real the
# whole fix_asm story silently evaporates, so assert the shape once, here.
case "$(command -v "$CC")" in
*gcc.real)
	echo "[FAIL] CC resolves to gcc.real -- that bypasses fix_asm (PORTING.md 2.2)" >&2
	exit 1
	;;
esac

# --- the 68060 integer rule (D4, strict since 2026-10-05) --------------------
# gcc 2.7.2.3 emits the 68060-unimplemented 64-bit MULU.L/MULS.L for every
# divide or modulo by a constant.  The wrapper's fix_asm rule 11
# (gcc-cross-amix 2ab2b22) rewrites each into 16x16 mulu.w partial products,
# ON by default; AMIX_MUL64=keep turns it off and is refused here, because a
# package built that way is SIGKILLed on a 68060.  AMIX_SCAN060=1 makes the
# wrapper scan every object it compiles and fail on a hit; the gates in
# gates.sh then scan every shipped file again, and amix_pkgroll scans the
# whole staged payload, so a hit can leave no build alive.
case "${AMIX_MUL64:-expand}" in
expand) ;;
*)
	echo "[FAIL] AMIX_MUL64=$AMIX_MUL64 -- packages here must be built with the" >&2
	echo "       68060 multiply expansion (the wrapper default); unset it." >&2
	exit 1
	;;
esac
command -v "$TARGET-scan060" >/dev/null 2>&1 || {
	echo "[FAIL] $TARGET-scan060 not found: the toolchain predates gcc-cross-amix" >&2
	echo "       2ab2b22 (68060 rule 11 + scanner).  Reinstall ../gcc-cross-amix." >&2
	exit 1
}
export AMIX_MUL64=expand
export AMIX_SCAN060=1

# --- the standard target flags ----------------------------------------------
# -m68020        stock Amix is a 68020/68030 with a real MMU (PORTING.md sec 1).
#                -m68060 is silently accepted and does nothing on gcc 2.7.
# -O             not -O2: the family's own engine builds run -O, and PORTING.md
#                sec 2.3 wants FP-sensitive translation units at -O0 instead.
#                A recipe that computes with floats overrides this per TU.
# -Wall          load-bearing, not hygiene.  gcc 2.7 compiles a call to an
#                undeclared function as int-returning and hands back the wrong
#                value -- the implicit-declaration trap that silently
#                invalidated a family FP probe (PORTING.md sec 3.1).  Every
#                "implicit declaration" warning is a defect.
# NO -ansi, NO -D_POSIX_SOURCE: on this vintage they REMOVE API (sec 2.4).
AMIX_ARCH_FLAGS="${AMIX_ARCH_FLAGS:--m68020}"
AMIX_CFLAGS="${AMIX_CFLAGS:-$AMIX_ARCH_FLAGS -O -Wall}"
export AMIX_ARCH_FLAGS AMIX_CFLAGS

export AMIX_CPP="$AMIX_PKG_COMMON/amix-cpp"
export AMIX_BUILD_ROOT="${AMIX_BUILD_ROOT:-$AMIX_REPO_ROOT/out/pkg}"
export AMIX_CONFIGURE_LENIENT=
fi
# --- end of the toolchain selection -----------------------------------------

# --- host tooling ------------------------------------------------------------
# Heirloom pkgmk/pkgtrans, host build, from the packagemanager repo.  That repo
# is the authority on the .pkg format; we consume its binaries rather than
# reimplementing datastream assembly.
AMIX_PKGMGR="${AMIX_PKGMGR:-$AMIX_SIBLINGS/amix-packagemanager}"
export AMIX_PKGMK="${AMIX_PKGMK:-$AMIX_PKGMGR/heirloom/build-host/bin/pkgmk}"
export AMIX_PKGTRANS="${AMIX_PKGTRANS:-$AMIX_PKGMGR/heirloom/build-host/bin/pkgtrans}"

# --- the installation prefix -------------------------------------------------
# THE SETTLED POLICY IS /opt/amix (COEXISTENCE.md sec 1, ROADMAP D11).  This
# default is still the older /usr/local because the two Wave-0 packages
# (libamixcompat, patch) were built and bench-proven there, and moving the
# default is coupled to the decision on whether those two get re-minted -- see
# BATCH-1.md's caveats.  Until that is decided, every BATCH-1 recipe exports
# AMIX_PREFIX=/opt/amix before sourcing this file, and a NEW recipe must do the
# same.  Recipes must not hard-code a prefix; they interpolate $AMIX_PREFIX so
# moving it stays one edit.
export AMIX_PREFIX="${AMIX_PREFIX:-/usr/local}"

amix_env_banner() {
	echo "  toolchain : $AMIX_TOOLCHAIN -- $CC ($TARGET)"
	echo "  sysroot   : ${AMIX_SYSROOT:-<unset>}"
	echo "  cflags    : $AMIX_CFLAGS"
	echo "  prefix    : $AMIX_PREFIX"
}
