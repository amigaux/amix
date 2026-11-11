#!/bin/sh
# container-media.sh: build the media image on the build container, and show
# the toolchains in it are the build container's.
#
# MIT licence, see LICENSE at the top of the repository.
#
# Usage: toolchain/container-media.sh [--check] [BASE_IMAGE] [TAG]
#   BASE_IMAGE  the build container (default amix-toolchain:dist)
#   TAG         the media image's tag (default amix-toolchain:media)
#   --check     build nothing: only check TAG's toolchains against BASE_IMAGE's
#               (toolchain/image-pull, for a published pair)
# Environment:
#   CONTAINER       docker (default) or podman
#   AMIX_DISTFILES  a local directory of distfiles
#
# The media step's tools go on top of the build container (Containerfile.media);
# nothing below them is rebuilt, and the build container keeps its digest. The
# image is refused if a file /opt/amix/TOOLCHAIN.sha256 lists differs in it, or
# if that list is not the build container's.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
tool=${CONTAINER:-docker}
check=
[ "${1:-}" != --check ] || { check=1; shift; }
base=${1:-amix-toolchain:dist}
tag=${2:-amix-toolchain:media}

if [ -z "$check" ]; then
	work=$(mktemp -d)
	trap 'rm -rf "${work:?}"' EXIT INT TERM
	# kept in out/cache, as make dist keeps its distfiles
	f=$(sh "$here/fetch-distfile" "$here/amitools.distfile")
	cp "$f" "$work/"
	"$tool" build -f "$here/Containerfile.media" --build-arg BASE="$base" -t "$tag" "$work"
fi

list() { "$tool" run --rm "$1" sha256sum /opt/amix/TOOLCHAIN.sha256 | cut -c1-64; }
want=$(list "$base")
got=$(list "$tag")
[ "$want" = "$got" ] || {
	echo "[FAIL] container-media.sh: $tag's toolchain list $got is not $base's $want" >&2
	exit 1
}
"$tool" run --rm --entrypoint sh "$tag" -c 'cd /opt && sha256sum -c --quiet amix/TOOLCHAIN.sha256' || {
	echo "[FAIL] container-media.sh: a file of $tag's toolchains is not what its list says" >&2
	exit 1
}
if [ -n "$check" ]; then
	echo "$tag is on $base; toolchains unchanged, list $got"
else
	echo "built $tag on $base; toolchains unchanged, list $got"
fi
