#!/bin/sh
# container-build.sh: build the amix build container from the toolchain pins.
#
# MIT licence, see LICENSE at the top of the repository.
#
# Usage: toolchain/container-build.sh AMIX_SYSTEM [TAG]
#   AMIX_SYSTEM  a clone of amigaux/amix-system holding system/amix-system.pin's
#                commit (its AMIX root under usr/); that commit's tree is checked
#                against system/MANIFEST.sha256 and system/SYMLINKS
#   TAG          image tag (default amix-toolchain:<short gcc14 pin>)
# Environment:
#   CONTAINER    docker (default) or podman
#   GCA_REPO     a local clone of gcc-cross-amix to take the pinned commit
#                from, instead of fetching it from the pin's URL
#   G14_REPO     the same for gcc14-cross-amix
#   NO_CACHE     1: build every stage again, using no cached layer (to
#                compare two builds' TOOLCHAIN.sha256)
#
# Each toolchain's source and the system input are exported with `git archive`
# at the pinned commit into a scratch directory, so nothing but the tree at that
# commit reaches the build: no .git, no local edits, no build products, no empty
# directory a working copy happens to hold.  The fixed umask keeps the host's out
# of the image's modes.  The .pin files go into the image as /opt/amix/PINS, which
# make dist checks (check-image).
set -eu
umask 022

here=$(cd "$(dirname "$0")" && pwd)
sys=${1:?usage: container-build.sh AMIX_SYSTEM [TAG]}
tool=${CONTAINER:-docker}
top=$(dirname "$here")

work=$(mktemp -d)
trap 'rm -rf "${work:?}"' EXIT INT TERM

# export NAME PIN LOCAL: the tree of PIN's commit into $work/NAME.
export_pin() {
	read -r url commit < "$2"
	src=$3
	if [ -z "$src" ]; then
		src=$work/$1.git
		git init -q --bare "$src"
		git -C "$src" fetch -q --depth 1 "$url" "$commit"
	fi
	git -C "$src" cat-file -e "$commit^{commit}" 2>/dev/null || {
		echo "container-build.sh: $commit ($1) is not in ${3:-$url}" >&2; exit 2; }
	mkdir "$work/$1"
	git -C "$src" archive --format=tar "$commit" | tar -x -C "$work/$1"
	echo "$1: $url $commit"
}

export_pin gca "$here/gcc-cross-amix.pin" "${GCA_REPO:-}"
export_pin g14 "$here/gcc14-cross-amix.pin" "${G14_REPO:-}"
export_pin sys "$top/system/amix-system.pin" "$sys"
# what is checked is what is built, before anything is
"$top/system/check-amix-system" "$work/sys"
read -r _ g14 < "$here/gcc14-cross-amix.pin"
tag=${2:-amix-toolchain:$(printf %.7s "$g14")}

set --
[ "${NO_CACHE:-}" != 1 ] || set -- --no-cache
"$tool" build "$@" -f "$here/Containerfile" \
	--build-context gca-src="$work/gca" \
	--build-context g14-src="$work/g14" \
	--build-context amix-system="$work/sys" \
	-t "$tag" "$here"
echo "built $tag"
