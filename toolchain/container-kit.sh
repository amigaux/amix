#!/bin/sh
# container-kit.sh: build the dlm ABI kit and the generic modules in the
# build container.
#
# MIT licence, see LICENSE at the top of the repository.
#
# Usage: toolchain/container-kit.sh IMAGE
#   IMAGE      the build container (toolchain/container-build.sh)
# Environment:
#   CONTAINER  docker (default) or podman
#   PORT_REPO  a local clone of the 68040/68060 port to take the commit in
#              kernel/port/port.pin from, instead of fetching it from the URL
#
# Runs, from the top of this checkout mounted at /src: `make kit` in
# kernel/dlm with the port at its pin, then `make kit-test` and both lines of
# every module in kernel/modules. Prints a digest of each kit (over its file
# list, taken before the tests) and the sha256 of each module object. The
# build runs as the calling user, so the tree is left as a host build would
# leave it.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
image=${1:?usage: container-kit.sh IMAGE}
tool=${CONTAINER:-docker}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
read -r url commit < "$top/kernel/port/port.pin"
git init -q "$work/port"
git -C "$work/port" fetch -q --depth 1 "${PORT_REPO:-$url}" "$commit"
git -C "$work/port" -c advice.detachedHead=false checkout -q "$commit"
echo "port: $url $commit"

incontainer() {
	"$tool" run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
		-v "$top:/src" -v "$work/port:/port:ro" -w /src "$image" \
		sh -ec ". \"\$GCA/env.sh\"; $1"
}

incontainer 'make -C kernel/dlm kit GCA="$GCA" PORT=/port'

# A kit's digest, taken before the kit tests build their samples inside it:
# the sha256 of its sorted "sha256  path" list. The second leaves out
# kit.conf and NOTICE, whose revision lines name the amix commit.
digest() {
	_d=$1; shift
	(cd "$_d" && find . -type f "$@" | LC_ALL=C sort | xargs sha256sum) | sha256sum | cut -c1-64
}
digests=$(for kit in "$top"/kernel/dlm/build/kit/*; do
	echo "kit ${kit##*/} $(digest "$kit") $(digest "$kit" ! -path ./kit.conf ! -path ./NOTICE)" \
		"$(grep '^KIT_REV=' "$kit/kit.conf" 2>/dev/null || echo KIT_REV=?)"
done)

incontainer 'make -C kernel/dlm kit-test GCA="$GCA" G14="$G14" PORT=/port
	for m in kernel/modules/*/module; do make -C "$m"; done'

echo "$digests"
for obj in "$top"/kernel/modules/*/build/*/mod.d/*; do
	rel=${obj#"$top"/}
	echo "module $rel $(sha256sum "$obj" | cut -c1-64)"
done
