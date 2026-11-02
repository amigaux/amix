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
#   drivers      every driver module on both lines, on the kit:
#                kernel/drivers/{a4091,z3660scsi,z3660eth}/module and
#                the forks at their pins (cdfs, gayle-ide, paula, z3660rtg):
#                out/modules/<line>/<name>
#   kspace       the kernel-space packages: each kernel/<dir>/pkg/build.sh,
#                provider before consumer (dlm, k30, port, the modules, the
#                drivers), into out/kspace/pkgs, one version per name; a
#                directory without one yet is named, and the step exits 3
#   userland     every package.sh of userland/packages and userland/base/pkg,
#                each after the packages its BUILD_DEPENDS names:
#                out/userland/pkgs/*.pkg, one version per name
#   catalogs     both catalogs, by pkgtools' gen-catalog.py over
#                out/{kspace,userland}/pkgs with their conf layers:
#                out/{kspace,userland}/{catalog,catalog.md5}
#   media        CD, netinstall, floppies                  not in make dist yet
#   lock         out/lock, every input and output (release/README.md); with
#                LOCK=<file>, refuses a build that is not that lock
#
# and `dist` (all of them, stopping at the first that fails or is not in
# make dist yet), `tools` (the build container, toolchain/container-build.sh),
# `recipes/<name>` (one userland package, after its BUILD_DEPENDS) and
# `drivers/<name>`.
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
# last commit. Exit 0 done, 1 failed, 2 usage, 3 a step that is
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

missing() {	# missing <step>
	echo "[MISSING] $1: not in make dist yet" >&2
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
		echo "       is its directory's last commit, so make dist needs the history" >&2
		exit 1
	}
	if [ -n "${DIST_HOST:-}" ]; then
		AMIX_SYSTEM=$sys AMIX_IN_CONTAINER=host exec sh "$0" "$@"
	fi
	gitdir=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir)
	tool=${CONTAINER:-docker}
	image=${AMIX_IMAGE:-amix-toolchain:dist}
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
	exec "$tool" run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e AMIX_IN_CONTAINER=1 -e LOCK \
		-e AMIX_SYSTEM=/system -v "$top:/src" -v "$gitdir:$gitdir:ro" -v "$sys:/system:ro" "$@"
fi
if [ "$AMIX_IN_CONTAINER" = 1 ]; then
	git config --global --add safe.directory /src
fi

# --- the steps -------------------------------------------------------------------
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

step_modules() {
	[ -f "$top/kernel/dlm/build/kit.digests" ] || step_kit
	( . "$GCA/env.sh"; for m in "$top"/kernel/modules/*/module; do make -C "$m" clean; make -C "$m"; done )
	rm -rf "${out:?}/modules"
	for obj in "$top"/kernel/modules/*/build/*/mod.d/*; do
		line=$(basename "$(dirname "$(dirname "$obj")")")
		mkdir -p "$out/modules/$line"
		cp "$obj" "$out/modules/$line/"
		echo "module $line $(basename "$obj") $(sha256sum < "$obj" | cut -c1-64)"
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
	for d in "$top"/kernel/modules/*/module; do
		[ -d "$d" ] && echo "kernel/modules/$(basename "$(dirname "$d")")"
	done
	for d in "$top"/kernel/drivers/*/; do
		[ -d "$d" ] && echo "kernel/drivers/$(basename "$d")"
	done
	return 0
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
	for d in $(kspace_dirs); do
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
		0) ;;
		3) waiting="$waiting $d" ;;
		*) echo "[FAIL] kspace: $d/pkg/build.sh failed (exit $rc)" >&2; exit 1 ;;
		esac
	done
	for p in "$out/build/kspace/kspace/pkg/"*.pkg; do
		[ -f "$p" ] && cp "$p" "$out/kspace/pkgs/"
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
	recipes/*)
		order=$(build_order "${1#recipes/}") || exit 1
		host_pkgtools
		mkdir -p "$out/build/userland"
		for d in $order; do
			roll_recipe "$d"
		done
		;;
	catalogs) step_catalogs ;;
	media) missing media ;;
	lock)
		# LOCK=<lock of record>: refuse a build that differs from it
		python3 -I "$here/mklock" "$top" "$out" ${LOCK:+--check "$LOCK"}
		;;
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
