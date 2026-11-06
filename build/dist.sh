#!/bin/sh
# dist.sh: the steps of make dist.
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
#   kernel-k30   the 68030 cut of record (kernel/k30/cuts/CURRENT), by k30's
#                hook kernel/k30/cuts/build.sh, into kernel/k30/build/cuts/<id>/
#                (where kern30m reads it); its sums in out/kernels/k30.list
#   kernel-k46   the 68040/68060 cut of record (kernel/port/cuts/CURRENT), by
#                the port's hook kernel/port/cuts/build.sh, into
#                kernel/port/build/cuts/<id>/ (where kern46m reads it); its sums
#                in out/kernels/k46.list
#   modules      kernel/modules/*/module on both lines: out/modules/<line>/<name>
#                (the module directories that hold files git tracks)
#   drivers      every driver module on both lines, on the kit:
#                kernel/drivers/{a4091,z3660scsi,z3660eth}/module and
#                the forks at their pins (cdfs, gayle-ide, paula, z3660rtg):
#                out/modules/<line>/<name>
#   kspace       the kernel-space packages: each kernel/<dir>/pkg/build.sh,
#                provider before consumer (dlm, k30, port, the modules, the
#                drivers: the directories that hold files git tracks), into
#                out/kspace/pkgs, one version per name; a directory without
#                one yet is named, and the step exits 3
#   userland     every package.sh of userland/packages and userland/base/pkg,
#                each after the packages its BUILD_DEPENDS names:
#                out/userland/pkgs/*.pkg, one version per name
#   apkg         APKG and APKGENG, by pkgtools' make dist: out/apkg/*.pkg
#   catalogs     both catalogs, by pkgtools' gen-catalog.py over
#                out/{kspace,userland}/pkgs with their conf layers:
#                out/{kspace,userland}/{catalog,catalog.md5}
#   release      the 1.1 repository tree, by pkgtools' assemble-release.py
#                over out/{userland,kspace,apkg}, the stock packages and the
#                published tree (RELEASE_PREVIOUS=<dir>, if any), checked by
#                tools/release-check with ROM_MANIFEST=<file> and
#                PRIVACY_PATTERNS=<file>: out/release/1.1/. The stock packages
#                are what stock-1.1.lock names, from STOCK=<dir>, else fetched
#                into out/cache from the release assets system/stock-1.1.assets
#                names (STOCK_URL=<base> names others); the sha256 decides.
#                RELEASE_PUBLIC=1 runs without the two files, on the content
#                check's public tests. A stock package not to be had, or
#                neither file without RELEASE_PUBLIC, exits 3
#   media        CD, netinstall, floppies: media/build.sh in the media image
#                (toolchain/Containerfile.media), into out/media/; it exits 3
#                while there is no media/build.sh or no media image
#   lock         out/lock, every input and output (release/README.md); with
#                LOCK=<file>, refuses a build that is not that lock
#
# and `dist` (all of them: a step that exits 3 is a gap, named at the end, and
# the others still run, the lock too; one that fails stops it), `tools` (the
# build containers, toolchain/container-build.sh and container-media.sh),
# `recipes/<name>` (one userland package, after its BUILD_DEPENDS) and
# `drivers/<name>`.
#
# Every step but `tools` runs in the build container: outside it, dist.sh
# runs itself there (AMIX_IMAGE, default amix-toolchain:dist; the media step
# AMIX_MEDIA_IMAGE, default amix-toolchain:media; CONTAINER, docker or podman),
# as the calling user, with the checkout at /src (a fixed path, for the period
# compiler, which cannot remap one), its git directory where git expects it,
# and SYSTEM read-only at /system. A step gets only its own inputs: STOCK,
# STOCK_URL, RELEASE_PREVIOUS, ROM_MANIFEST, PRIVACY_PATTERNS and RELEASE_PUBLIC
# reach the release step (the last three the media step too), LOCK the lock
# step, so a name a kernel's recipe reads for itself is never set by accident.
# DIST_HOST=1 runs the steps on this host instead, for development; a release
# is built in the container.
#
# Before any step: SYSTEM (or AMIX_SYSTEM; default the amix-system checkout
# beside the main working tree) must match system/MANIFEST.sha256, and the
# checkout must not be shallow, since a package's epoch is its directory's
# last commit. Exit 0 done, 1 failed, 2 usage, 3 a gap: an input or a step that
# is not there yet. (`make` itself reports any failure of its recipe as 2.)
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
	dist|tools|kit|kernel-k30|kernel-k46|modules|drivers|drivers/?*|kspace|userland|apkg|recipes/?*|catalogs|release|media|lock) ;;
	*) echo "[FAIL] unknown step: $s" >&2; usage ;;
	esac
done

# more than one step: each its own process, so each gets only its own inputs
if [ $# -gt 1 ]; then
	for s; do
		sh "$0" "$s" || exit
	done
	exit 0
fi

missing() {	# missing <step>
	echo "[MISSING] $1: not in make dist yet" >&2
	exit 3
}

# dist: every step, each its own process (set -e holds inside it, and the media
# step has its own image). A step's exit 3 is a gap: the rest still run, the
# lock last, and the gaps are named at the end, exit 3.
dist_loop() {
	gaps=
	for s in kit kernel-k30 kernel-k46 modules drivers kspace userland apkg catalogs release media lock; do
		echo "=== make dist: $s"
		rc=0
		sh "$0" "$s" || rc=$?
		case $rc in
		0) ;;
		3) gaps="$gaps $s" ;;
		*) echo "make dist: stopped at $s" >&2; exit "$rc" ;;
		esac
	done
	if [ -n "$gaps" ]; then
		echo "make dist: done but for:$gaps (their [MISSING] lines above); out/lock has no lines for them" >&2
		exit 3
	fi
	echo "make dist: done; out/"
}

# --- outside the container: preconditions, then run there --------------------
if [ "${1:-}" = tools ]; then
	sys=${SYSTEM:-${AMIX_SYSTEM:-}}
	[ -n "$sys" ] || { AMIX_TOP=$top; . "$here/pkg/layout.sh"; sys=$AMIX_SYSTEM; }
	"$top/toolchain/container-build.sh" "$sys" "${AMIX_IMAGE:-amix-toolchain:dist}"
	exec "$top/toolchain/container-media.sh" "${AMIX_IMAGE:-amix-toolchain:dist}" "${AMIX_MEDIA_IMAGE:-amix-toolchain:media}"
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
		echo "       is its directory's last commit, so make dist needs the history" >&2
		exit 1
	}
	if [ -n "${DIST_HOST:-}" ]; then
		AMIX_SYSTEM=$sys AMIX_IN_CONTAINER=host exec sh "$0" "$@"
	fi
	[ "$1" != dist ] || { dist_loop; exit 0; }
	step=$1
	gitdir=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir)
	tool=${CONTAINER:-docker}
	image=${AMIX_IMAGE:-amix-toolchain:dist}
	if [ "$1" = media ]; then
		[ -f "$top/media/build.sh" ] || missing media
		image=${AMIX_MEDIA_IMAGE:-amix-toolchain:media}
		"$tool" image inspect "$image" > /dev/null 2>&1 || {
			echo "[MISSING] media: no image $image (make tools builds it)" >&2
			exit 3
		}
	fi
	# the calling user's uid and gid need names in the image (the host
	# pkgtools' smoke tests ask id(1); a CI runner's uid is not the image's
	# 1000): the image's passwd and group, plus the caller where absent
	ids=$out/.ids
	mkdir -p "$ids"
	"$tool" run --rm "$image" cat /etc/passwd > "$ids/passwd"
	"$tool" run --rm "$image" cat /etc/group > "$ids/group"
	awk -F: -v u="$(id -u)" '$3 == u { f = 1 } END { exit !f }' "$ids/passwd" ||
		echo "builder:x:$(id -u):$(id -g)::/tmp:/bin/sh" >> "$ids/passwd"
	awk -F: -v g="$(id -g)" '$3 == g { f = 1 } END { exit !f }' "$ids/group" ||
		echo "builder:x:$(id -g):" >> "$ids/group"
	# AMIX_DISTFILES, a local directory of distfiles, read-only at /distfiles
	set -- -w /src -v "$ids/passwd:/etc/passwd:ro" -v "$ids/group:/etc/group:ro" "$image" sh build/dist.sh "$@"
	if [ -n "${AMIX_DISTFILES:-}" ]; then
		set -- -e AMIX_DISTFILES=/distfiles -v "$(cd "$AMIX_DISTFILES" && pwd):/distfiles:ro" "$@"
	fi
	# a step's inputs from outside the checkout, read-only under /release-in:
	# STOCK and RELEASE_PREVIOUS (directories), ROM_MANIFEST and PRIVACY_PATTERNS
	# (files, never in this repository), LOCK; its settings by name
	inputs= settings=
	case $step in
	release) inputs="STOCK RELEASE_PREVIOUS ROM_MANIFEST PRIVACY_PATTERNS"; settings="STOCK_URL RELEASE_PUBLIC" ;;
	media) inputs="ROM_MANIFEST PRIVACY_PATTERNS"; settings=RELEASE_PUBLIC ;;
	lock) inputs=LOCK ;;
	esac
	for v in $inputs; do
		eval "p=\${$v:-}"
		[ -n "$p" ] || continue
		# LOCK is the checkout's: a relative one is from its top
		[ "$v" != LOCK ] || case $p in /*) ;; *) p=$top/$p ;; esac
		[ -e "$p" ] || { echo "[FAIL] make dist: $v=$p does not exist" >&2; exit 1; }
		p=$(cd "$(dirname "$p")" && pwd)/$(basename "$p")
		set -- -e "$v=/release-in/$v" -v "$p:/release-in/$v:ro" "$@"
	done
	for v in $settings; do
		eval "p=\${$v:-}"
		[ -z "$p" ] || set -- -e "$v=$p" "$@"
	done
	exec "$tool" run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e AMIX_IN_CONTAINER=1 \
		-e AMIX_SYSTEM=/system -v "$top:/src" -v "$gitdir:$gitdir:ro" -v "$sys:/system:ro" "$@"
fi
if [ "$AMIX_IN_CONTAINER" = 1 ]; then
	git config --global --add safe.directory /src
	# the image is built from this checkout's toolchain pins, or nothing runs
	sh "$top/toolchain/check-image" || exit 1
fi

# --- the steps -------------------------------------------------------------------
# a step sees only its own inputs, on this host too (DIST_HOST)
case $1 in
dist) ;;
release) unset LOCK 2>/dev/null || : ;;
media) unset LOCK STOCK STOCK_URL RELEASE_PREVIOUS 2>/dev/null || : ;;
lock) unset STOCK STOCK_URL RELEASE_PREVIOUS ROM_MANIFEST PRIVACY_PATTERNS RELEASE_PUBLIC 2>/dev/null || : ;;
*) unset LOCK STOCK STOCK_URL RELEASE_PREVIOUS ROM_MANIFEST PRIVACY_PATTERNS RELEASE_PUBLIC 2>/dev/null || : ;;
esac
AMIX_TOP=$top
. "$here/pkg/layout.sh"
: "${GCA:?dist.sh: GCA is not set (the build container sets it)}"

full_hash() {	# full_hash <pin> <commit>: git fetches a commit by its full hash only
	echo "$2" | grep -Eqx '[0-9a-f]{40}' || {
		echo "[FAIL] $1: '$2' is not a full 40-digit commit hash; git cannot fetch a short one" >&2
		exit 1
	}
}

port_at_pin() {	# the port at kernel/port/port.pin, in out/cache/port
	read -r url commit < "$top/kernel/port/port.pin"
	full_hash kernel/port/port.pin "$commit"
	p=$out/cache/port
	if [ "$(git -C "$p" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
		rm -rf "${p:?}"
		git init -q "$p"
		git -C "$p" fetch -q --depth 1 "${PORT_REPO:-$url}" "$commit"
		git -C "$p" -c advice.detachedHead=false checkout -q "$commit"
	fi
	echo "$p"
}

step_kit() {
	port=$(port_at_pin)
	( . "$GCA/env.sh"; make -C "$top/kernel/dlm" kit GCA="$GCA" PORT="$port" )
	rm -rf "${out:?}/kit"
	mkdir -p "$out/kit"
	cp -R "$top/kernel/dlm/build/kit/k30" "$top/kernel/dlm/build/kit/k46" "$out/kit/"
	cp "$top/kernel/dlm/build/kit.digests" "$out/kit/kit.digests"
	echo "kit: out/kit"
	cat "$out/kit/kit.digests"
}

# tracked_names <dir> [<sub>]: each <name> whose <dir>/<name>[/<sub>] holds a
# file git tracks, in C order; a leftover untracked directory (a removed
# driver's gitignored build output) is not a recipe
tracked_names() {
	_tn=$(git -C "$top" ls-files -- "$1") || {
		echo "[FAIL] git ls-files $1 failed in $top" >&2; return 1; }
	printf '%s\n' "$_tn" | sed -n "s|^$1/\([^/]*\)/${2:+$2/}.*|\1|p" | LC_ALL=C sort -u
}

step_modules() {
	[ -f "$top/kernel/dlm/build/kit.digests" ] || step_kit
	mods=$(tracked_names kernel/modules module) || exit 1
	( . "$GCA/env.sh"; for m in $mods; do
		make -C "$top/kernel/modules/$m/module" clean; make -C "$top/kernel/modules/$m/module"; done )
	rm -rf "${out:?}/modules"
	for m in $mods; do
		for obj in "$top/kernel/modules/$m"/build/*/mod.d/*; do
			[ -f "$obj" ] || continue
			line=$(basename "$(dirname "$(dirname "$obj")")")
			mkdir -p "$out/modules/$line"
			cp "$obj" "$out/modules/$line/"
			echo "module $line $(basename "$obj") $(sha256sum < "$obj" | cut -c1-64)"
		done
	done
}

# the drivers: ours in kernel/drivers, and the forks at their pins
DRIVERS="a4091 z3660scsi z3660eth cdfs gayle-ide paula z3660rtg"

fork_at_pin() {	# fork_at_pin <name>: the fork at kernel/drivers/<name>/<name>.pin, in out/cache/forks
	read -r url commit < "$top/kernel/drivers/$1/$1.pin"
	full_hash "kernel/drivers/$1/$1.pin" "$commit"
	f=$out/cache/forks/$1
	if [ "$(git -C "$f" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
		rm -rf "${f:?}"
		git init -q "$f"
		git -C "$f" fetch -q --depth 1 "$url" "$commit"
		git -C "$f" -c advice.detachedHead=false checkout -q "$commit"
	fi
	rm -rf "${f:?}/build"
	echo "$f"
}

build_driver() {	# build_driver <name>: its module on both lines, built against this checkout's kit
	dlm=$top/kernel/dlm
	case $1 in
	a4091|z3660scsi|z3660eth)
		# a4091's module/ builds a4kt710 (the A4000T's onboard 53C710) too;
		# clean first, so no object of an earlier kit survives
		make -C "$top/kernel/drivers/$1/module" DLM="$dlm" clean
		make -C "$top/kernel/drivers/$1/module" DLM="$dlm"
		;;
	cdfs)
		f=$(fork_at_pin cdfs)
		make -C "$f/platform/amix-kernel/module" DLM="$dlm"
		;;
	gayle-ide|paula)
		f=$(fork_at_pin "$1")
		make -C "$f/module" DLM="$dlm"
		;;
	z3660rtg)
		# depend= names monsw: the real monsw module of each line (out/modules)
		f=$(fork_at_pin z3660rtg)
		for line in k30 k46; do
			make -C "$f/module" KIT="$dlm/build/kit/$line" \
				MONSWMOD="$out/modules/$line/monsw" \
				LOCALIZE_OBJCOPY="$G14/prefix/bin/m68k-elf-objcopy"
		done
		;;
	*) echo "[FAIL] drivers: no driver $1 (known: $DRIVERS)" >&2; exit 1 ;;
	esac
}

driver_objects() {	# the module objects a driver's build leaves
	case $1 in
	a4091) set -- "$top/kernel/drivers/a4091" ;;
	z3660scsi|z3660eth) set -- "$top/kernel/drivers/$1" ;;
	*) set -- "$out/cache/forks/$1" ;;
	esac
	find "$1" -path '*/build/*' -path '*/mod.d/*' -type f | LC_ALL=C sort
}

step_drivers() {	# step_drivers [<name>...]
	[ -f "$top/kernel/dlm/build/kit.digests" ] || sh "$0" kit
	[ -f "$out/modules/k30/monsw" ] && [ -f "$out/modules/k46/monsw" ] || sh "$0" modules
	[ $# -gt 0 ] || set -- $DRIVERS
	for d; do
		echo "--- driver $d"
		( . "$GCA/env.sh"; build_driver "$d" ) > "$out/build/driver-$d.log" 2>&1 || {
			tail -20 "$out/build/driver-$d.log" >&2
			echo "[FAIL] drivers: $d did not build; log out/build/driver-$d.log" >&2
			exit 1
		}
		n=0
		for obj in $(driver_objects "$d"); do
			line=$(basename "$(dirname "$(dirname "$obj")")")
			case $line in k30|k46) ;; *) continue ;; esac
			mkdir -p "$out/modules/$line"
			cp "$obj" "$out/modules/$line/"
			echo "module $line $(basename "$obj") $(sha256sum < "$obj" | cut -c1-64)"
			n=$((n + 1))
		done
		[ "$n" -gt 0 ] || { echo "[FAIL] drivers: $d built no module object" >&2; exit 1; }
	done
}

# step_catalogs: pkgtools' gen-catalog.py (userland/pkgtools/tools/repo),
# called as it is, over each space's packages. Its two conf layers: the
# staging root's, tools/repo's deps/names/cats/descs.conf copied into each
# pkgs/ (the stock, kernel-space and pkgtools packages, and the category
# vocabulary), and the space's own: userland/packages/conf, or kernel/conf
# for kernel space, whose names.conf gives each kernel package its catalog
# name (zeth46: z3660eth-k46). A kernel-space catalog with packages and no
# such names is refused: boxes, kbootset and installng ask for the names.
step_catalogs() {
	gencat=$top/userland/pkgtools/tools/repo/gen-catalog.py
	for space in kspace userland; do
		[ -d "$out/$space/pkgs" ] || {
			echo "[FAIL] catalogs: no out/$space/pkgs; make $space first" >&2; exit 1; }
		case $space in
		userland) conf=$top/userland/packages/conf ;;
		kspace)
			conf=$top/kernel/conf
			if [ ! -f "$conf/names.conf" ]; then
				ls "$out/kspace/pkgs/"*.pkg >/dev/null 2>&1 && {
					echo "[FAIL] catalogs: kernel-space packages but no kernel/conf/names.conf; their" >&2
					echo "       catalog names (zeth46: z3660eth-k46) would be bare instances" >&2
					exit 1
				}
				conf=none
			fi
			;;
		esac
		for c in deps names cats descs; do
			cp "$top/userland/pkgtools/tools/repo/$c.conf" "$out/$space/pkgs/$c.conf"
		done
		python3 -I -B "$gencat" --packages-conf "$conf" -o "$out/$space" "$out/$space/pkgs"
		echo "catalog $space $(cut -c1-32 "$out/$space/catalog.md5") $(grep -c '^[^#]' "$out/$space/catalog" || :) row(s)"
	done
}

# step_kernel <line> <dir>: the line's hook, <dir>/cuts/build.sh (k30's
# kernel/k30, the port's kernel/port), rebuilds the cut of record and refuses
# sums other than the record's; it prints `kernel <line> <path> <sha256>` per
# file, which the lock takes verbatim. Its exit status is passed through (3:
# an input is absent).
step_kernel() {
	mkdir -p "$out/kernels" "$out/build"
	export GCA G14 AMIX_SYSTEM
	rc=0
	sh "$top/$2/cuts/build.sh" > "$out/build/kernel-$1.log" 2>&1 || rc=$?
	grep "^kernel $1 " "$out/build/kernel-$1.log" > "$out/kernels/$1.list.new" || :
	if [ "$rc" -ne 0 ]; then
		tail -20 "$out/build/kernel-$1.log" >&2
		rm -f "$out/kernels/$1.list.new"
		echo "[FAIL] kernel-$1: $2/cuts/build.sh exited $rc; log out/build/kernel-$1.log" >&2
		exit "$rc"
	fi
	[ -s "$out/kernels/$1.list.new" ] || {
		echo "[FAIL] kernel-$1: the hook printed no kernel $1 lines" >&2; exit 1; }
	mv "$out/kernels/$1.list.new" "$out/kernels/$1.list"
	cat "$out/kernels/$1.list"
}

# build_order [<name>...]: the userland recipe directories in BUILD_DEPENDS
# order (pkgmeta build-order): each after the packages it builds against, or
# with names only those and what they need; a name that is no package, or a
# cycle, is refused
build_order() {
	_bo_r=
	for _bo_d in "$top/userland/packages" "$top/userland/base/pkg"; do
		[ -d "$_bo_d" ] && _bo_r="$_bo_r $_bo_d"
	done
	if [ -z "$_bo_r" ]; then
		[ $# -eq 0 ] || { echo "[FAIL] userland: no userland package $1" >&2; exit 1; }
		return 0
	fi
	_bo=$(python3 -I "$here/pkg/pkgmeta" build-order $_bo_r \
		$(for n; do printf ' --for %s' "$n"; done) 2>&1) || {
		echo "$_bo" | sed 's/^pkgmeta: /[FAIL] userland: /' >&2; exit 1; }
	echo "$_bo"
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

# host_pkgtools: the host pkgmk and pkgtrans every roll uses, make dist's
# own: pkgtools' heirloom/build-host.sh run in a copy of userland/pkgtools
# (build-host.sh reads ../research) under out/build/pkgtools-host/, never the
# checkout's build-host/. build-host.sh
# compiles its absolute directory into the tools (BINDIR, where pkgtrans finds
# its cpio), so tools built in the checkout on the host name a path the
# container lacks. A stamp of the copied files' digest skips a rebuild of the
# same sources.
host_pkgtools() {
	_hp=$out/build/pkgtools-host
	_hp_files=$(cd "$top/userland/pkgtools" && git ls-files -co --exclude-standard | LC_ALL=C sort)
	_hp_sum=$(cd "$top/userland/pkgtools" && echo "$_hp_files" | while read -r f; do
		sha256sum "$f"; done | sha256sum | cut -c1-64)
	AMIX_PKGMK=$_hp/pkgtools/heirloom/build-host/bin/pkgmk AMIX_PKGTRANS=$_hp/pkgtools/heirloom/build-host/bin/pkgtrans
	export AMIX_PKGMK AMIX_PKGTRANS
	if [ "$(cat "$_hp/stamp" 2>/dev/null)" = "$_hp_sum" ] && [ -x "$AMIX_PKGMK" ] && [ -x "$AMIX_PKGTRANS" ]; then
		return 0
	fi
	echo "--- host pkgtools: userland/pkgtools/heirloom/build-host.sh, in out/build/pkgtools-host"
	rm -rf "${_hp:?}"
	mkdir -p "$_hp/pkgtools"
	( cd "$top/userland/pkgtools" && echo "$_hp_files" | tr '\n' '\0' |
		tar --null -T - -cf - ) | tar -x -C "$_hp/pkgtools"
	( cd "$_hp/pkgtools/heirloom" && ./build-host.sh ) > "$out/build/pkgtools-host.log" 2>&1 || {
		tail -20 "$out/build/pkgtools-host.log" >&2
		echo "[FAIL] host pkgtools did not build; log out/build/pkgtools-host.log" >&2
		exit 1
	}
	[ -x "$AMIX_PKGMK" ] && [ -x "$AMIX_PKGTRANS" ] || {
		echo "[FAIL] build-host.sh left no $AMIX_PKGMK" >&2; exit 1; }
	echo "$_hp_sum" > "$_hp/stamp"
}

# step_kspace: every kernel directory's recipes, kernel/<dir>/pkg/build.sh.
# Each rolls all its recipes, writes its .pkg files to
# $AMIX_BUILD_ROOT/kspace/pkg/ and prints a `pkg <file> <sha256>` line for
# each; exit 0, 3 when an input outside the recipe is absent (with a
# [MISSING] line naming the input), or another code for a
# failure. Run in provider order; the directories that have none yet, or
# exit 3, are named, the others still run, and the step then exits 3.
kspace_dirs() {
	for d in kernel/dlm kernel/k30 kernel/port; do
		[ -d "$top/$d" ] && echo "$d"
	done
	_kd_m=$(tracked_names kernel/modules module) || return 1
	_kd_d=$(tracked_names kernel/drivers) || return 1
	for d in $_kd_m; do echo "kernel/modules/$d"; done
	for d in $_kd_d; do echo "kernel/drivers/$d"; done
	return 0
}

# what a directory's recipes leave beside their packages for the media: when
# all of them rolled (exit 0), a file of its list that is not there fails the
# step, rather than the media and the lock going without it
kspace_beside() {
	case $1 in
	kernel/dlm) echo amix-cdboot ;;
	esac
}

step_kspace() {
	host_pkgtools
	# every shared directory alike in every kernel-space prototype
	python3 -I "$here/pkg/pkgmeta" dirs "$top/kernel" >/dev/null
	rm -rf "${out:?}/kspace" "${out:?}/build/kspace"
	mkdir -p "$out/build/kspace/kspace/pkg" "$out/kspace/pkgs"
	# the port's headers at each recipe's own pinned commit (dlm-src.sh):
	# a cache repository that fetches a commit it lacks by hash
	read -r AMIX_PORT_URL _pc < "$top/kernel/port/port.pin"
	full_hash kernel/port/port.pin "$_pc"
	AMIX_PORT_REPO=$out/cache/port-repo
	[ -d "$AMIX_PORT_REPO/.git" ] || git init -q "$AMIX_PORT_REPO"
	AMIX_PORT_URL=${PORT_REPO:-$AMIX_PORT_URL}
	# port.pin's commit, by its full hash, so a recipe pinned to it finds it
	# under either spelling; a recipe with an older pin fetches its own
	git -C "$AMIX_PORT_REPO" cat-file -e "$_pc^{commit}" 2>/dev/null ||
		git -C "$AMIX_PORT_REPO" fetch -q --depth 1 "$AMIX_PORT_URL" "$_pc"
	export AMIX_PORT_URL AMIX_PORT_REPO
	missing= waiting=
	kdirs=$(kspace_dirs) || exit 1
	for d in $kdirs; do
		if [ ! -f "$top/$d/pkg/build.sh" ]; then
			missing="$missing $d"
			continue
		fi
		echo "--- $d"
		# exit 3: an input outside the recipe is absent (a cut's output); the
		# hook has printed its [MISSING] line, and the rest still run
		rc=0
		AMIX_BUILD_ROOT=$out/build/kspace sh "$top/$d/pkg/build.sh" || rc=$?
		case $rc in
		0)
			for f in $(kspace_beside "$d"); do
				_kb=$out/build/kspace/kspace/beside/$f
				if [ -L "$_kb" ] || [ ! -f "$_kb" ]; then
					echo "[FAIL] kspace: $d's recipes rolled, but left no file beside/$f" >&2
					exit 1
				fi
			done
			;;
		3) waiting="$waiting $d" ;;
		*) echo "[FAIL] kspace: $d/pkg/build.sh failed (exit $rc)" >&2; exit 1 ;;
		esac
	done
	for p in "$out/build/kspace/kspace/pkg/"*.pkg; do
		[ -f "$p" ] && cp "$p" "$out/kspace/pkgs/"
	done
	# what a recipe builds beside its package, for the media; the lock names it
	for p in "$out/build/kspace/kspace/beside/"*; do
		[ -f "$p" ] || continue
		mkdir -p "$out/kspace/beside"
		cp "$p" "$out/kspace/beside/"
	done
	if [ -n "$(ls "$out/kspace/pkgs")" ]; then
		python3 -I "$here/pkg/pkgmeta" guard "$out/kspace/pkgs"
	fi
	for d in $missing; do
		echo "[MISSING] kspace: $d has no pkg/build.sh yet" >&2
	done
	for d in $waiting; do
		echo "[MISSING] kspace: $d/pkg/build.sh is waiting for an input (its [MISSING] line above)" >&2
	done
	[ -z "$missing$waiting" ] || exit 3
}

step_apkg() {
	rm -rf "${out:?}/apkg"
	mkdir -p "$out/build"
	make -C "$top/userland/pkgtools" dist OUT="$out/apkg" STAGE="$out/build/pkgtools" GCA="$GCA" \
		> "$out/build/apkg.log" 2>&1 || {
		tail -20 "$out/build/apkg.log" >&2
		echo "[FAIL] apkg: pkgtools' make dist failed; log out/build/apkg.log" >&2
		exit 1
	}
	# pkgtools' make dist leaves its catalog layer beside the datastreams
	rm -f "${out:?}/apkg/"*.conf
	(cd "$out/apkg" && md5sum APKG-*.pkg APKGENG-*.pkg)
}

# the stock packages stock-$release.lock names, into out/cache/stock-$release:
# from AMIX_DISTFILES or the release assets at STOCK_URL, else at the URL in
# system/stock-$release.assets. Prints the directory; none named: prints nothing.
# What each fetch said is in out/build/stock-fetch.log; a failure prints its end.
stock_fetch() {
	_lk=$top/userland/pkgtools/tools/repo/stock-$release.lock
	_base=${STOCK_URL:-}
	if [ -z "$_base" ] && [ -f "$top/system/stock-$release.assets" ]; then
		read -r _base < "$top/system/stock-$release.assets"
	fi
	[ -n "$_base" ] && [ -f "$_lk" ] || return 0
	_d=$out/cache/stock-$release
	mkdir -p "$_d"
	_log=$out/build/stock-fetch.log
	: > "$_log"
	. "$here/pkg/common/fetch.sh"
	grep -v '^#' "$_lk" | while read -r _n _sz _md5 _sha; do
		[ -n "$_n" ] || continue
		( amix_fetch "$_base/$_n" "$_sha" "$_d/$_n" ) >> "$_log" 2>&1 || {
			tail -6 "$_log" >&2
			echo "[MISSING] release: stock package $_n: not to be had at $_base with its pinned sha256" >&2
			exit 3
		}
	done || exit
	echo "$_d"
}

release=1.1
step_release() {
	rm -rf "${out:?}/release/$release" "${out:?}/build/release-previous"
	for d in userland kspace; do
		[ -f "$out/$d/catalog" ] || missing_input "out/$d/catalog: make $d catalogs first"
	done
	ls "$out/apkg/"APKG-*.pkg >/dev/null 2>&1 || missing_input "out/apkg: make apkg first"
	host_pkgtools		# AMIX_PKGTRANS, for the tool's scan060
	# scan060-g14 takes the stock members' tables in .text as data by their
	# sha256 in the GCC 14 sysroot (libcrypt's DES tables, which dropbear
	# links), as the D4 gate does when the package is rolled
	AMIX_SYSROOT=$("${G14:?release: G14 is not set (the build container sets it)}/prefix/bin/m68k-elf-gcc" -print-sysroot) &&
		[ -d "$AMIX_SYSROOT/usr/lib" ] || {
		echo "[FAIL] release: no GCC 14 sysroot from $G14/prefix/bin/m68k-elf-gcc" >&2; exit 1; }
	export AMIX_SYSROOT
	mkdir -p "$out/build"
	if [ -z "${STOCK:-}" ]; then
		STOCK=$(stock_fetch) || exit
	fi
	# the published tree this one is built on: its catalog's digest, for the lock
	if [ -n "${RELEASE_PREVIOUS:-}" ] && [ -f "$RELEASE_PREVIOUS/catalog" ]; then
		sha256sum "$RELEASE_PREVIOUS/catalog" | cut -c1-64 > "$out/build/release-previous"
	fi
	# a public rebuild has no ROM register and no private list: empty ones, so
	# the check's public tests run. The tree is the same bytes.
	if [ -n "${RELEASE_PUBLIC:-}" ]; then
		: > "$out/build/release-public-empty"
		ROM_MANIFEST=${ROM_MANIFEST:-$out/build/release-public-empty}
		PRIVACY_PATTERNS=${PRIVACY_PATTERNS:-$out/build/release-public-empty}
		export ROM_MANIFEST PRIVACY_PATTERNS
		echo "release: public rebuild: no ROM register or private list; the content check's public tests only"
	fi
	make -C "$top/userland/pkgtools/src/apkg" apkg > "$out/build/apkg-host.log" 2>&1 || {
		tail -20 "$out/build/apkg-host.log" >&2
		echo "[FAIL] release: the host apkg did not build; log out/build/apkg-host.log" >&2
		exit 1
	}
	rc=0
	python3 -I "$top/userland/pkgtools/tools/repo/assemble-release.py" \
		--userland "$out/userland" --kspace "$out/kspace" --apkg "$out/apkg" \
		${STOCK:+--stock "$STOCK"} ${RELEASE_PREVIOUS:+--previous "$RELEASE_PREVIOUS"} \
		--release "$release" --out "$out/release/$release" \
		--release-check "$top/tools/release-check" \
		--apkg-bin "$top/userland/pkgtools/src/apkg/apkg" || rc=$?
	exit $rc
}

missing_input() {	# missing_input <what>
	echo "[MISSING] release: $1" >&2
	exit 3
}

# media: media/build.sh, into out/media/. The hook exits 3 for an input it lacks;
# what the image holds goes to out/build/media-tools, for the lock
step_media() {
	rm -rf "${out:?}/media" "${out:?}/build/media-tools"
	[ -f "$top/media/build.sh" ] || missing media
	mkdir -p "$out/media" "$out/build"
	[ ! -f /opt/amix-media/TOOLS ] || cp /opt/amix-media/TOOLS "$out/build/media-tools"
	AMIX_TOP=$top sh "$top/media/build.sh"
}

step_userland() {
	host_pkgtools
	python3 -I "$here/pkg/pkgmeta" check "$top/userland/packages" "$top/userland/base/pkg" >/dev/null
	rm -rf "${out:?}/userland" "${out:?}/build/userland"
	mkdir -p "$out/build/userland" "$out/userland/pkgs"
	order=$(build_order) || exit 1
	for d in $order; do
		roll_recipe "$d"
	done
	python3 -I "$here/pkg/pkgmeta" guard "$out/userland/pkgs"
}

run() {
	case $1 in
	kit) step_kit ;;
	kernel-k30) step_kernel k30 kernel/k30 ;;
	kernel-k46) step_kernel k46 kernel/port ;;
	modules) step_modules ;;
	drivers) mkdir -p "$out/build"; step_drivers ;;
	drivers/*) mkdir -p "$out/build"; step_drivers "${1#drivers/}" ;;
	kspace) step_kspace ;;
	userland) step_userland ;;
	apkg) step_apkg ;;
	release) step_release ;;
	recipes/*)
		order=$(build_order "${1#recipes/}") || exit 1
		host_pkgtools
		mkdir -p "$out/build/userland"
		for d in $order; do
			roll_recipe "$d"
		done
		;;
	catalogs) step_catalogs ;;
	media) step_media ;;
	lock)
		# LOCK=<lock of record>: refuse a build that differs from it
		python3 -I "$here/mklock" "$top" "$out" ${LOCK:+--check "$LOCK"}
		;;
	dist) dist_loop ;;
	*) echo "[FAIL] unknown step: $1" >&2; usage ;;
	esac
}

run "$1"
