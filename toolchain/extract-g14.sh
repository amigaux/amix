#!/bin/sh
# extract-g14.sh: the build container's gcc14-cross-amix, on the host.
#
# MIT licence, see LICENSE at the top of the repository.
#
# Usage: toolchain/extract-g14.sh IMAGE [DIR]
#        toolchain/extract-g14.sh --check IMAGE
#   IMAGE      the build container (toolchain/container-build.sh)
#   DIR        where the copy goes (default: out/toolchain/gcc14-cross-amix in
#              the main working tree of this checkout, which build/pkg's
#              layout.sh takes as G14's checkout)
#   --check    only check that IMAGE's gcc14 is the pinned build
# Environment:
#   CONTAINER  docker (default) or podman
#
# The image's /opt/amix/gcc14-cross-amix (the source at the pin and build/,
# the compiler in build/prefix with its sysroot inside it) is copied to DIR.
# Every file is checked against the image's TOOLCHAIN.sha256; the digest of
# that list's gcc14 part must be the one in toolchain/gcc14-cross-amix.tree,
# or nothing is copied. DIR/TOOLCHAIN.sha256 keeps the list. The compiler
# and linker find the sysroot relative to themselves, so the copy builds the
# same bytes as the container.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
tool=${CONTAINER:-docker}
check=
if [ "${1:-}" = --check ]; then
	check=1; shift
fi
image=${1:?usage: extract-g14.sh [--check] IMAGE [DIR]}
pin=$(sed -n 's/^\([0-9a-f]\{64\}\)$/\1/p' "$here/gcc14-cross-amix.tree")
[ -n "$pin" ] || { echo "extract-g14.sh: no digest in toolchain/gcc14-cross-amix.tree" >&2; exit 2; }

# the gcc14 part of a TOOLCHAIN.sha256, paths relative to gcc14-cross-amix/
g14part() { sed -n 's|^\([0-9a-f]\{64\}\)  amix/gcc14-cross-amix/|\1  |p'; }

list=$("$tool" run --rm "$image" cat /opt/amix/TOOLCHAIN.sha256 | g14part)
got=$(printf '%s\n' "$list" | sha256sum | cut -c1-64)
[ "$got" = "$pin" ] || {
	echo "extract-g14.sh: $image's gcc14 is not the pinned build" >&2
	echo "  its digest  $got" >&2
	echo "  pinned      $pin (toolchain/gcc14-cross-amix.tree)" >&2
	exit 1
}
echo "gcc14: $image is the pinned build ($(printf '%s\n' "$list" | wc -l) files, digest $pin)"
[ -z "$check" ] || exit 0

if [ -n "${2:-}" ]; then
	dir=$2
else
	git=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir)
	dir=$(dirname "$git")/out/toolchain/gcc14-cross-amix
fi
mkdir -p "$(dirname "$dir")"
new=$dir.new.$$
trap 'rm -rf "$new"' EXIT INT TERM
c=$("$tool" create "$image")
"$tool" cp "$c:/opt/amix/gcc14-cross-amix" "$new" || { "$tool" rm "$c" >/dev/null; exit 1; }
"$tool" rm "$c" >/dev/null
printf '%s\n' "$list" > "$new/TOOLCHAIN.sha256"
have=$(cd "$new" && find . -type f ! -name TOOLCHAIN.sha256 -print0 | LC_ALL=C sort -z |
	xargs -0 sha256sum | sed 's|  \./|  |')
[ "$have" = "$list" ] || {
	echo "extract-g14.sh: the copy in $new differs from the image's list:" >&2
	printf '%s\n' "$list" > "$new.want"; printf '%s\n' "$have" | diff "$new.want" - >&2 || :
	rm -f "$new.want"
	exit 1
}
rm -rf "$dir"
mv "$new" "$dir"
trap - EXIT INT TERM
echo "gcc14: $dir (G14=$dir/build)"
