#!/bin/sh
# dist.sh: the steps of make dist (P-38 S1.5).
#
# MIT licence, see LICENSE at the top of the repository.
#
#     make dist SYSTEM=<amix-system checkout>     (the top Makefile, or make -C build)
#     sh build/dist.sh <step>...
#
# Steps, in make dist's order, provider before consumer:
#
#   kit          kernel/dlm's ABI kits, k30 and k46, with the port at
#                kernel/port/port.pin: out/kit/{k30,k46,kit.digests}
#   kernel-k30   the 68030 cut (P-38 S2.2, k30)            not in make dist yet
#   kernel-k46   the 68040/68060 cut (P-38 S2.3, port)     not in make dist yet
#   modules      kernel/modules/*/module on both lines: out/modules/<line>/<name>
#   drivers      kernel/drivers' modules (P-38 S3.2)       not in make dist yet
#   kspace       the kernel-space packages (P-38 S3.3)     not in make dist yet
#   userland     every package.sh of userland/packages and userland/base/pkg:
#                out/userland/pkgs/*.pkg, one version per name
#   catalogs     both catalogs (P-38 S5.1, pkgtools)       not in make dist yet
#   media        CD, netinstall, floppies (P-38 S6.1)      not in make dist yet
#   lock         out/lock (P-38 S1.6)                      not in make dist yet
#
# and `dist` (all of them, stopping at the first that fails or is not in
# make dist yet), `tools` (the build container, toolchain/container-build.sh),
# `recipes/<name>` (one userland package) and `drivers/<name>`.
#
# Every step but `tools` runs in the build container: outside it, dist.sh
# runs itself there (AMIX_IMAGE, default amix-toolchain:dist; CONTAINER,
# docker or podman), as the calling user, with the checkout at /src (a fixed
# path, for the period compiler, which cannot remap one), its git directory
# where git expects it, and SYSTEM read-only at /system. DIST_HOST=1 runs the
# steps on this host instead, for development; a release is built in the
# container.
#
# Before any step: SYSTEM (or AMIX_SYSTEM; default the amix-system checkout
# beside the main working tree) must match system/MANIFEST.sha256, and the
# checkout must not be shallow, since a package's epoch is its directory's
# last commit (P-38 D-b). Exit 0 done, 1 failed, 2 usage, 3 a step that is
# not in make dist yet.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
out=$top/out

usage() {
	sed -n '/^# Steps,/,/^# and `dist`/p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}
[ $# -gt 0 ] || usage
for s; do
	case $s in
	dist|tools|kit|kernel-k30|kernel-k46|modules|drivers|drivers/?*|kspace|userland|recipes/?*|catalogs|media|lock) ;;
	*) echo "[FAIL] unknown step: $s" >&2; usage ;;
	esac
done

missing() {	# missing <step> <P-38 step and owner>
	echo "[MISSING] $1: not in make dist yet ($2)" >&2
	exit 3
}

# --- outside the container: preconditions, then run there --------------------
if [ "${1:-}" = tools ]; then
	sys=${SYSTEM:-${AMIX_SYSTEM:-}}
	[ -n "$sys" ] || { AMIX_TOP=$top; . "$here/pkg/layout.sh"; sys=$AMIX_SYSTEM; }
	exec "$top/toolchain/container-build.sh" "$sys" "${AMIX_IMAGE:-amix-toolchain:dist}"
fi
if [ -z "${AMIX_IN_CONTAINER:-}" ]; then
	sys=${SYSTEM:-${AMIX_SYSTEM:-}}
	[ -n "$sys" ] || { AMIX_TOP=$top; . "$here/pkg/layout.sh"; sys=${AMIX_SYSTEM:-}; }
	[ -n "$sys" ] && [ -d "$sys" ] || {
		echo "[FAIL] make dist: no system input; SYSTEM=<amix-system checkout> (system/fetch-amix-system makes one)" >&2
		exit 1
	}
	sys=$(cd "$sys" && pwd)
	"$top/system/check-amix-system" "$sys" || exit 1
	[ "$(git -C "$top" rev-parse --is-shallow-repository 2>/dev/null)" = false ] || {
		echo "[FAIL] make dist: $top is a shallow clone, or not a git checkout; a package's epoch" >&2
		echo "       is its directory's last commit, so make dist needs the history (P-38 D-b)" >&2
		exit 1
	}
	if [ -n "${DIST_HOST:-}" ]; then
		AMIX_SYSTEM=$sys AMIX_IN_CONTAINER=host exec sh "$0" "$@"
	fi
	gitdir=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir)
	tool=${CONTAINER:-docker}
	exec "$tool" run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e AMIX_IN_CONTAINER=1 \
		-e AMIX_SYSTEM=/system -v "$top:/src" -v "$gitdir:$gitdir:ro" -v "$sys:/system:ro" \
		-w /src "${AMIX_IMAGE:-amix-toolchain:dist}" sh build/dist.sh "$@"
fi
if [ "$AMIX_IN_CONTAINER" = 1 ]; then
	git config --global --add safe.directory /src
fi

# --- the steps -------------------------------------------------------------------
AMIX_TOP=$top
. "$here/pkg/layout.sh"
: "${GCA:?dist.sh: GCA is not set (the build container sets it)}"

port_at_pin() {	# the port at kernel/port/port.pin, in out/cache/port
	read -r url commit < "$top/kernel/port/port.pin"
	p=$out/cache/port
	if [ "$(git -C "$p" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
		rm -rf "$p"
		git init -q "$p"
		git -C "$p" fetch -q --depth 1 "${PORT_REPO:-$url}" "$commit"
		git -C "$p" -c advice.detachedHead=false checkout -q "$commit"
	fi
	echo "$p"
}

step_kit() {
	port=$(port_at_pin)
	( . "$GCA/env.sh"; make -C "$top/kernel/dlm" kit GCA="$GCA" PORT="$port" )
	rm -rf "$out/kit"
	mkdir -p "$out/kit"
	cp -R "$top/kernel/dlm/build/kit/k30" "$top/kernel/dlm/build/kit/k46" "$out/kit/"
	cp "$top/kernel/dlm/build/kit.digests" "$out/kit/kit.digests"
	echo "kit: out/kit"
	cat "$out/kit/kit.digests"
}

step_modules() {
	[ -f "$top/kernel/dlm/build/kit.digests" ] || step_kit
	( . "$GCA/env.sh"; for m in "$top"/kernel/modules/*/module; do make -C "$m"; done )
	rm -rf "$out/modules"
	for obj in "$top"/kernel/modules/*/build/*/mod.d/*; do
		line=$(basename "$(dirname "$(dirname "$obj")")")
		mkdir -p "$out/modules/$line"
		cp "$obj" "$out/modules/$line/"
		echo "module $line $(basename "$obj") $(sha256sum < "$obj" | cut -c1-64)"
	done
}

recipe_dir() {	# the package directory of a userland package name
	for r in "$top/userland/packages/$1" "$top/userland/base/pkg/$1"; do
		[ -f "$r/package.sh" ] && { echo "$r"; return 0; }
	done
	echo "[FAIL] no userland package $1 (userland/packages, userland/base/pkg)" >&2
	exit 1
}

roll_recipe() {	# roll_recipe <package dir>
	AMIX_BUILD_ROOT=$out/build/userland AMIX_GCC14_BUILD_ROOT=$out/build/userland \
		sh "$here/pkg/pkgbuild.sh" "$1" > "$out/build/userland/$(basename "$1").log" 2>&1 || {
		tail -20 "$out/build/userland/$(basename "$1").log" >&2
		echo "[FAIL] userland: $(basename "$1") did not build; log out/build/userland/$(basename "$1").log" >&2
		exit 1
	}
	mkdir -p "$out/userland/pkgs"
	for p in "$out/build/userland/pkg/"*.pkg; do
		cmp -s "$p" "$out/userland/pkgs/${p##*/}" 2>/dev/null || cp "$p" "$out/userland/pkgs/"
	done
	grep '^pkg ' "$out/build/userland/$(basename "$1")/BUILD.txt" | sed "s|$out/||"
}

step_userland() {
	python3 -I "$here/pkg/pkgmeta" check "$top/userland/packages" "$top/userland/base/pkg" >/dev/null
	rm -rf "$out/userland" "$out/build/userland"
	mkdir -p "$out/build/userland" "$out/userland/pkgs"
	for r in "$top"/userland/packages/*/package.sh "$top"/userland/base/pkg/*/package.sh; do
		[ -f "$r" ] && roll_recipe "$(dirname "$r")"
	done
	python3 -I "$here/pkg/pkgmeta" guard "$out/userland/pkgs"
}

run() {
	case $1 in
	kit) step_kit ;;
	kernel-k30) missing kernel-k30 "P-38 S2.2, the k30 station: make kernel-k30 wraps the cut" ;;
	kernel-k46) missing kernel-k46 "P-38 S2.3, the port station: the cut in the container" ;;
	modules) step_modules ;;
	drivers|drivers/*) missing "$1" "P-38 S3.2, each driver's station: its module on both lines" ;;
	kspace) missing kspace "P-38 S3.3, packages-fa with each directory: the kernel-space recipes" ;;
	userland) step_userland ;;
	recipes/*)
		d=$(recipe_dir "${1#recipes/}") || exit 1
		mkdir -p "$out/build/userland"
		roll_recipe "$d"
		;;
	catalogs) missing catalogs "P-38 S5.1, pkgtools: gen-catalog over out/" ;;
	media) missing media "P-38 S6.1, installng after its move-in" ;;
	lock) missing lock "P-38 S1.6, infra: out/lock" ;;
	dist)
		# each step its own process: set -e holds inside it
		for s in kit kernel-k30 kernel-k46 modules drivers kspace userland catalogs media lock; do
			echo "=== make dist: $s"
			sh "$0" "$s" || { rc=$?; echo "make dist: stopped at $s" >&2; exit "$rc"; }
		done
		echo "make dist: done; out/"
		;;
	*) echo "[FAIL] unknown step: $1" >&2; usage ;;
	esac
}

for s; do
	run "$s"
done
