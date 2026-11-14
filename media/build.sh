#!/bin/sh
# media/build.sh -- the installer media of a release, from make dist's out/ (its `media` step).
#
# MIT licence, see LICENSE at the top of the repository.
#
#     AMIX_TOP=<checkout> sh media/build.sh        (make dist runs it in the media container)
#
# Reads, and nothing else (media/README.md has the whole interface):
#   out/kspace/{catalog,catalog.md5,pkgs/*.pkg,beside/amix-cdboot}   the kernel-space packages
#   out/release/<v>/{catalog,pkgs/*.pkg,pkgs/stock/*.pkg}           the release tree (one <v>)
#   out/apkg/{APKG,APKGENG}-*.pkg                                   the package manager's packages
#   $AMIX_SYSTEM/usr/sbin/syslogd                                    the 2.1c daemon (sha256-pinned)
#   $GCA/env.sh                                                      gcc-cross-amix
#   this checkout's HEAD: kernel/dlm (host kbootset, mkstore, lsstore) and userland/pkgtools (the
#     disc's static engine and apkg, the host pkgtrans and apkg), built under out/build/media
#   media/inputs/*.distfile                                          the RAM-disk images, by sha256
#     (toolchain/fetch-distfile: out/cache, AMIX_DISTFILES, then the URLs)
#   ROM_MANIFEST and PRIVACY_PATTERNS for the content check, or RELEASE_PUBLIC=1 (its public tests)
# Writes out/media/: amix-<v>-install.iso, amix-<v>-netinstall.iso, amix-<v>-boot-k30-1.adf,
# amix-<v>-boot-k30-2.adf, amix-<v>-boot-k46-1.adf, amix-<v>-boot-k46-2.adf, amix-<v>-boot-z3660.hdf,
# MEDIA.txt and SHA256SUMS; scratch, logs and RELEASE-CHECK.txt under out/build/media.
# Every time stamp is SOURCE_DATE_EPOCH, else HEAD's commit time: the same inputs give the same bytes.
# Exit 0 built and clean, 1 failed, 3 an input missing (a `[MISSING] media:` line for each).
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
set -euo pipefail

repo="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
top="$(cd "${AMIX_TOP:-$repo/..}" && pwd)"
[ "$repo" = "$top/media" ] || { echo "[FAIL] media: AMIX_TOP=$top does not hold this media/ ($repo)" >&2; exit 1; }
out="$top/out"
MEDIA_TOP="$top" MEDIA_SCRATCH="$out/build/media"
L11_IN="$MEDIA_SCRATCH/in"
export MEDIA_TOP MEDIA_SCRATCH L11_IN
tools="$repo/tools"
log="$MEDIA_SCRATCH/log"
fail() { echo "[FAIL] media: $*" >&2; exit 1; }
gaps=0
gap() { echo "[MISSING] media: $*" >&2; gaps=1; }
step() { echo "--- media: $*"; }

# --- the inputs are there ----------------------------------------------------------------------
rels=()
for d in "$out"/release/*/; do [ -f "$d/catalog" ] && rels+=("$(basename "$d")"); done
case ${#rels[@]} in
	1) REL=${rels[0]} ;;
	0) gap "no release tree out/release/<v>/catalog (make dist's release step)"; REL= ;;
	*) fail "more than one release tree under out/release: ${rels[*]}" ;;
esac
RT="$out/release/$REL"
# the media's own version (VERSION beside this script): the release, or a point release that goes into
# that release's repository (1.1.1 into pkg.amigaux.org/1.1). It names the files and the volume id;
# the repository the installed system names stays $REL.
VER=$REL
if [ -f "$repo/VERSION" ]; then
	VER=$(sed -n '1p' "$repo/VERSION")
	case "$VER" in
		"$REL"|"$REL".[0-9]|"$REL".[0-9][0-9]) ;;
		*) [ -z "$REL" ] || fail "media/VERSION says $VER, which is neither the release tree's $REL nor a point release of it" ;;
	esac
fi
for f in kspace/catalog kspace/catalog.md5 kspace/beside/amix-cdboot; do
	[ -f "$out/$f" ] || gap "no out/$f (make dist's kspace step)"
done
ls "$out"/kspace/pkgs/*.pkg > /dev/null 2>&1 || gap "no out/kspace/pkgs/*.pkg (make dist's kspace step)"
[ -z "$REL" ] || ls "$RT"/pkgs/stock/*.pkg > /dev/null 2>&1 || gap "no stock packages in out/release/$REL/pkgs/stock"
for p in APKG APKGENG; do
	n=$(ls "$out"/apkg/$p-*.pkg 2>/dev/null | wc -l)
	[ "$n" = 1 ] || gap "out/apkg holds $n $p-*.pkg, not one (make dist's apkg step)"
done
[ -n "${AMIX_SYSTEM:-}" ] && [ -f "$AMIX_SYSTEM/usr/sbin/syslogd" ] || gap "no AMIX_SYSTEM/usr/sbin/syslogd (the amix-system checkout)"
[ -n "${GCA:-}" ] && [ -f "$GCA/env.sh" ] || gap "no GCA/env.sh (gcc-cross-amix, toolchain/gcc-cross-amix.pin)"
for c in xorriso xdftool rdbtool python3 make cc git tar patch strings file zic; do
	command -v "$c" > /dev/null || gap "no $c on PATH (the media container, toolchain/Containerfile.media)"
done
# the content check: the ROM register and the private names, never in this repository
if [ -z "${RELEASE_PUBLIC:-}" ]; then
	[ -n "${ROM_MANIFEST:-}" ] && [ -f "$ROM_MANIFEST" ] && [ -n "${PRIVACY_PATTERNS:-}" ] && [ -f "$PRIVACY_PATTERNS" ] \
		|| gap "the content check needs ROM_MANIFEST and PRIVACY_PATTERNS, or RELEASE_PUBLIC=1 (its public tests)"
fi
[ "$gaps" = 0 ] || exit 3

# --- the epoch, the scratch, the pinned RAM-disk images ----------------------------------------
HEAD=$(git -C "$top" rev-parse HEAD)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$top" log -1 --format=%ct HEAD)}
export SOURCE_DATE_EPOCH LC_ALL=C TZ=UTC
DIRTY=
[ -z "$(git -C "$top" status --porcelain -- media kernel/dlm userland/pkgtools 2>/dev/null)" ] || DIRTY=" dirty"
rm -rf "${MEDIA_SCRATCH:?}"
mkdir -p "$L11_IN" "$log" "$out/media" "$MEDIA_SCRATCH/tmp"
# every tool's temporary files under the scratch too, not the system's
export TMPDIR="$MEDIA_SCRATCH/tmp"
declare -A IMG
for i in rdm-k46 rdm-k30 ni-k46 ni-k30; do
	pin="$repo/inputs/ramdisk-$i.distfile"
	[ -f "$pin" ] || fail "no $pin"
	IMG[$i]=$(sh "$top/toolchain/fetch-distfile" "$pin" "$out/cache" 2> "$log/fetch-$i.log" | tail -1) && [ -f "${IMG[$i]}" ] \
		|| { cat "$log/fetch-$i.log" >&2; gap "the RAM-disk image $i (media/inputs/ramdisk-$i.distfile: not in out/cache or AMIX_DISTFILES, and not to be fetched)"; }
done
[ "$gaps" = 0 ] || exit 3

# --- the inputs, laid out as the media tools read them ($L11_IN) --------------------------------
step "inputs: kernel/dlm and userland/pkgtools at ${HEAD:0:12}${DIRTY}, out/ at $REL"
# shellcheck disable=SC1091
. "$GCA/env.sh"
src="$MEDIA_SCRATCH/src"
mkdir -p "$src"
git -C "$top" archive HEAD kernel/dlm userland/pkgtools | tar -x -C "$src"
make -C "$src/kernel/dlm" tools > "$log/dlm-tools.log" 2>&1 || { tail -20 "$log/dlm-tools.log" >&2; fail "kernel/dlm make tools (log out/build/media/log/dlm-tools.log)"; }
B="$L11_IN/dlm/build"
mkdir -p "$B/box"
for t in kbootset mkstore lsstore; do cp "$src/kernel/dlm/build/$t" "$B/$t"; done
cp "$out/kspace/beside/amix-cdboot" "$B/amix-cdboot"
mkdir -p "$L11_IN/kspace-beside"
cp "$out/kspace/beside/amix-cdboot" "$L11_IN/kspace-beside/amix-cdboot"
PT="$L11_IN/pkgtools"
mv "${src:?}/userland/pkgtools" "${PT:?}"
( cd "$PT/heirloom" && ./build-host.sh ) > "$log/pkgtools-host.log" 2>&1 || { tail -20 "$log/pkgtools-host.log" >&2; fail "pkgtools build-host.sh"; }
( cd "$PT/heirloom" && GCA="$GCA" ./build-amix-static.sh ) > "$log/pkgtools-static.log" 2>&1 \
	&& grep -q 'STATIC BUILD OK' "$log/pkgtools-static.log" || { tail -20 "$log/pkgtools-static.log" >&2; fail "pkgtools build-amix-static.sh"; }
mkdir -p "$L11_IN/apkg"
cp "$PT/heirloom/build-amix-static/bin/apkg" "$L11_IN/apkg/apkg"
m68k-cbm-sysv4-strip "$L11_IN/apkg/apkg"
make -C "$PT/src/apkg" host > "$log/apkg-host.log" 2>&1 && cp "$PT/src/apkg/apkg" "$L11_IN/apkg/apkg-host" \
	|| { tail -20 "$log/apkg-host.log" >&2; fail "the host apkg"; }
make -C "$PT/src/apkg" amix AMIX_SYSROOT="$AMIX_SYSROOT" AMIX_CRT_DIR="$AMIX_CRT_DIR" > "$log/apkg-http.log" 2>&1 \
	&& cp "$PT/src/apkg/apkg.amix" "$L11_IN/apkg/apkg-http" && m68k-cbm-sysv4-strip "$L11_IN/apkg/apkg-http" \
	|| { tail -20 "$log/apkg-http.log" >&2; fail "the HTTP apkg"; }
PKGTRANS="$PT/heirloom/build-host/bin/pkgtrans"
# the kernel-space FILE source: make dist's catalog and packages as they are
mkdir -p "$L11_IN/kpkg/pkgs"
cp "$out/kspace/catalog" "$out/kspace/catalog.md5" "$L11_IN/kpkg/"
cp "$out"/kspace/pkgs/*.pkg "$L11_IN/kpkg/pkgs/"
( cd "$L11_IN/kpkg" && md5sum -c --quiet catalog.md5 ) || fail "out/kspace/catalog is not its catalog.md5"
# the box's kbootset: the kbootset package's own sbin/kbootset
kb=$(awk -F'|' '$1 == "kbootset" { print $3 " " $4 }' "$L11_IN/kpkg/catalog")
[ "$(echo "$kb" | grep -c .)" = 1 ] || fail "out/kspace/catalog has no one kbootset row"
kbu="$MEDIA_SCRATCH/kbootset-pkg"; mkdir -p "$kbu"
"$PKGTRANS" "$L11_IN/kpkg/pkgs/${kb#* }" "$kbu" "${kb% *}" > "$log/kbootset-pkg.log" 2>&1 || fail "pkgtrans could not open ${kb#* }"
cp "$kbu/${kb% *}/root/sbin/kbootset" "$B/box/kbootset" || fail "${kb#* } holds no sbin/kbootset"
# the base packages (conf/base-packages.conf): the release tree's rows and datastreams
mkdir -p "$L11_IN/base"
: > "$L11_IN/base/catalog.lines"; : > "$L11_IN/base/sets"
while read -r name sets; do
	case $name in ''|\#*) continue ;; esac
	row=$(awk -F'|' -v n="$name" '$1 == n' "$RT/catalog")
	[ "$(printf '%s\n' "$row" | grep -c .)" = 1 ] || fail "out/release/$REL/catalog has no one $name row"
	IFS='|' read -r _ _ inst file md5 size _ <<< "$row"
	f="$RT/pkgs/$file"
	[ -f "$f" ] && [ "$(md5sum < "$f" | cut -c1-32)" = "$md5" ] && [ "$(wc -c < "$f")" = "$size" ] \
		|| fail "out/release/$REL/pkgs/$file is not its catalog row"
	cp "$f" "$L11_IN/base/$file"
	printf '%s\n' "$row" >> "$L11_IN/base/catalog.lines"
	echo "$inst${sets:+ $sets}" >> "$L11_IN/base/sets"
done < "$repo/conf/base-packages.conf"
# the package staging: the stock set from the release tree, APKG and APKGENG from out/apkg
mkdir -p "$L11_IN/staging/stock" "$L11_IN/staging/base"
cp "$RT"/pkgs/stock/*.pkg "$L11_IN/staging/stock/"
cp "$out"/apkg/APKG-*.pkg "$out"/apkg/APKGENG-*.pkg "$L11_IN/staging/base/"
echo "$SOURCE_DATE_EPOCH" > "$L11_IN/EPOCH"
# development only: MEDIA_PAYLOAD, a directory holding zenmac and setclk built elsewhere (a host whose
# gcc-cross-amix is not the pin's builds other bytes); build-install-iso.sh holds them to the same sha256
# pins. A make dist build in the container leaves it unset and builds both.
if [ -n "${MEDIA_PAYLOAD:-}" ]; then
	mkdir -p "$MEDIA_SCRATCH/payload"
	for t in zenmac setclk; do cp "$MEDIA_PAYLOAD/$t" "$MEDIA_SCRATCH/payload/$t"; done
	DIRTY="$DIRTY payload-from-elsewhere"
fi
# INPUTS: what the media are made of, by sha256; it goes on the install disc (/install/l11/INPUTS)
{
	echo "# the inputs of the amix $VER installer media (media/build.sh), paths under out/build/media/in"
	echo "amix $HEAD$DIRTY"
	echo "release $REL"
	[ "$VER" = "$REL" ] || echo "media $VER"
	echo "epoch $SOURCE_DATE_EPOCH"
	echo "tool kernel/dlm $(git -C "$top" rev-parse HEAD:kernel/dlm) (make tools: kbootset mkstore lsstore)"
	echo "tool userland/pkgtools $(git -C "$top" rev-parse HEAD:userland/pkgtools) (heirloom, apkg)"
	for i in rdm-k46 rdm-k30 ni-k46 ni-k30; do
		echo "ramdisk $i $(sha256sum < "${IMG[$i]}" | cut -c1-64) (media/inputs/ramdisk-$i.distfile)"
	done
	( cd "$L11_IN" && sha256sum dlm/build/kbootset dlm/build/mkstore dlm/build/lsstore dlm/build/amix-cdboot \
		dlm/build/box/kbootset apkg/apkg apkg/apkg-host apkg/apkg-http \
		pkgtools/heirloom/build-host/bin/pkgtrans pkgtools/heirloom/build-amix-static/bin/pkgadd \
		kpkg/catalog kpkg/pkgs/*.pkg base/*.pkg staging/base/*.pkg staging/stock/*.pkg )
} > "$L11_IN/INPUTS"

# --- the media -----------------------------------------------------------------------------------
step "the stock core tree"
bash "$tools/build-core-tree.sh" > "$log/core-tree.log" 2>&1 || { tail -5 "$log/core-tree.log" >&2; fail "build-core-tree.sh"; }
step "the CD boot tree"
rc=0
bash "$tools/build-ramdisk-cd.sh" --k46 "${IMG[rdm-k46]}" --k30 "${IMG[rdm-k30]}" --out "$MEDIA_SCRATCH/cd-tree" \
	> "$log/cd-tree.log" 2>&1 || rc=$?
if [ "$rc" != 0 ]; then
	tail -8 "$log/cd-tree.log" >&2
	# a pinned image whose modules are not this kspace's: the on-box step must make new ones
	grep -q 'does not hold what its generation records' "$log/cd-tree.log" && {
		gap "the pinned RAM-disk images do not hold this kspace's boot and demand modules: new images (made on an Amix box) and new media/inputs pins"
		exit 3; }
	fail "build-ramdisk-cd.sh (log out/build/media/log/cd-tree.log)"
fi
step "install CD, floppies, Z3660 boot disk, netinstall CD, content check"
W="$MEDIA_SCRATCH/release"
if [ -n "${RELEASE_PUBLIC:-}" ]; then
	: > "$MEDIA_SCRATCH/public-empty"
	ROM_MANIFEST=${ROM_MANIFEST:-$MEDIA_SCRATCH/public-empty} PRIVACY_PATTERNS=${PRIVACY_PATTERNS:-$MEDIA_SCRATCH/public-empty}
	export ROM_MANIFEST PRIVACY_PATTERNS RELEASE_PUBLIC
fi
MEDIA_SYSTEM="$AMIX_SYSTEM" bash "$tools/build-release-media.sh" --release "$VER" --cd-tree "$MEDIA_SCRATCH/cd-tree" \
	--rdm-k46 "${IMG[rdm-k46]}" --rdm-k30 "${IMG[rdm-k30]}" --ni-k46 "${IMG[ni-k46]}" --ni-k30 "${IMG[ni-k30]}" \
	--out "$W" > "$log/release-media.log" 2>&1 || { tail -15 "$log/release-media.log" >&2; fail "build-release-media.sh (log out/build/media/log/release-media.log)"; }

# --- out/media: the shipped files, their sums and the record -------------------------------------
names="amix-$VER-install.iso amix-$VER-netinstall.iso amix-$VER-boot-k30-1.adf amix-$VER-boot-k30-2.adf
amix-$VER-boot-k46-1.adf amix-$VER-boot-k46-2.adf amix-$VER-boot-z3660.hdf"
for n in $names; do
	[ -f "$W/$n" ] || fail "build-release-media.sh wrote no $n"
	cp "$W/$n" "$out/media/$n"
done
( cd "$out/media" && sha256sum $names > SHA256SUMS )
{
	cat "$W/MEDIA.txt"
	echo "# tools: $(xorriso -version 2>/dev/null | head -1 | cut -d: -f1 | sed 's/ *$//'), amitools $(python3 -c 'import importlib.metadata as m; print(m.version("amitools"))' 2>/dev/null \
		|| "$(sed -n '1s/^#!//p' "$(command -v xdftool)")" -c 'import importlib.metadata as m; print(m.version("amitools"))' 2>/dev/null || echo '?')"
	echo "# content check: $(grep -c 'CLEAN' "$W/RELEASE-CHECK.txt") clean verdict(s)${RELEASE_PUBLIC:+, public tests only (RELEASE_PUBLIC)}; RELEASE-CHECK.txt beside the build"
} > "$out/media/MEDIA.txt"
bash "$tools/sidecar-path-check.sh" "$out/media/MEDIA.txt" "$out/media/SHA256SUMS" || fail "a machine path in out/media's records"
cat "$out/media/SHA256SUMS"
echo "media: out/media/ ($VER, repository $REL, amix ${HEAD:0:12}${DIRTY}, epoch $SOURCE_DATE_EPOCH)"
