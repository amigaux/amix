# kmodpkg.sh -- roll one MODULE package (amix-dlm C3-5 v4 sec 1): one
# driver repository's module object for one kernel line.  Sourced, never
# executed; the recipe (recipes/<module>/build.sh) sources its pin.sh first.
#
#     . "$AMIX_PKG_COMMON/kmodpkg.sh"
#     amix_kmodpkg <recipe dir> <k30|k46>
#
# The variables it reads from the recipe's pin.sh:
#     KM_NAME          the module's name (.moddata name=, the file name)
#     KM_SHORT         C3-5 sec 1.1 short name (pkginst = short + line digits)
#     KM_REPO          the driver repository (sibling directory name)
#     KM_VERSION       the module's release, = <repo>/module/VERSION
#     KM_VERSION_FILE  optional: that file, relative to the siblings, when it
#                      is not $KM_REPO/module/VERSION (a repository's second
#                      module, e.g. amix-a4091/module/a4kt710/VERSION)
#     KM_K30_OBJ / KM_K46_OBJ        the object, relative to the siblings
#     KM_K30_SHA / KM_K46_SHA        its sha256
#     KM_K30_DEPS / KM_K46_DEPS      "<path> <sha256>" per line: modules the
#                      object names in depend=, for modcheck -d only (never
#                      packaged)
#     KM_KIT_COMMIT    amix-dlm commit whose `make kit` gives modcheck
#     KM_LICENCES      "<path> <sha256>" per line, relative to the siblings
#     KM_SOURCE_EPOCH
#     KM_EXTRA_NOTE    optional: a paragraph for the copyright file
#     KM_PAGESHIFT_OK  optional: the module Makefile's PAGESHIFT_OK, passed
#                      to modcheck as -w (functions whose shifts by 11 are
#                      not page arithmetic; kit 8fc87de or later)
#     KM_FILES         optional: "<installed path> <source> <sha256> <mode>"
#                      per line, the source relative to the siblings: further
#                      plain files the package ships beside the module (a
#                      driver's interface header), verified and copied
#                      verbatim; the prototype lists each as `f none`
# and, from the recipe directory: pkginfo.<line>, prototype, modreg.
#
# Installs /etc/conf/mod.d/<name> (the object, verbatim) and
# /etc/conf/modreg.d/<name> (the package's defaults, the recipe's modreg
# file).  Pure files, no scripts (C3-5 sec 1.2 allows pure-sh ones; none is
# needed), rolled by amix_kpkgroll.  Gates: the object's sha256 and size,
# module/VERSION, the kit's modcheck.py (C3-1; on k46 the 68060 scan with
# the pinned gcc-cross-amix's scan060 and the 4 KiB page rule), its
# .moddata name/kabi/cc against the line, and a byte round trip.

case "${0##*/}" in
kmodpkg.sh)
	echo "[FAIL] kmodpkg.sh is sourced, not executed" >&2
	exit 1
	;;
esac

amix_kmodpkg() {
	_km_dir="$1"; _km_line="$2"
	case "$_km_line" in
	k30) _km_obj="$AMIX_SIBLINGS/$KM_K30_OBJ"; _km_sha=$KM_K30_SHA; _km_deps=$KM_K30_DEPS ;;
	k46) _km_obj="$AMIX_SIBLINGS/$KM_K46_OBJ"; _km_sha=$KM_K46_SHA; _km_deps=$KM_K46_DEPS ;;
	*) echo "[FAIL] no kernel line '$_km_line' (k30, k46)" >&2; exit 1 ;;
	esac
	_km_cat="$KM_NAME-$_km_line"
	_km_pkg="$KM_SHORT${_km_line#k}"
	_km_build="$REPO/build/kspace/$_km_cat"
	_km_dest="$_km_build/dest"
	_km_work="$_km_build/work"
	_km_out="$REPO/build/kspace/pkg/$_km_pkg-$KM_VERSION.pkg"
	echo "=== $_km_cat $KM_VERSION (PKG=$_km_pkg) ==="
	[ "${#KM_SHORT}" -le 7 ] || { echo "[FAIL] short name $KM_SHORT over 7 bytes (C3-5 sec 1.1)" >&2; exit 1; }

	echo "--- verify the inputs ---"
	amix_verify "$_km_obj" "$_km_sha"
	_km_vf=${KM_VERSION_FILE:-$KM_REPO/module/VERSION}
	_km_v=$(cat "$AMIX_SIBLINGS/$_km_vf")
	[ "$_km_v" = "$KM_VERSION" ] || {
		echo "[FAIL] $_km_vf says '$_km_v', the pin $KM_VERSION" >&2; exit 1; }
	echo "  $_km_vf = $KM_VERSION"
	echo "$KM_LICENCES" | while read _n _h; do if [ -n "$_n" ]; then amix_verify "$AMIX_SIBLINGS/$_n" "$_h"; fi; done
	_km_d=
	echo "$_km_deps" | while read _p _h; do if [ -n "$_p" ]; then amix_verify "$AMIX_SIBLINGS/$_p" "$_h"; fi; done
	for _p in $(echo "$_km_deps" | awk 'NF {print $1}'); do _km_d="$_km_d -d $AMIX_SIBLINGS/$_p"; done

	echo "--- modcheck (the kit of amix-dlm $KM_KIT_COMMIT) ---"
	amix_dlm_kit "$KM_KIT_COMMIT" >/dev/null
	_km_kit="$AMIX_DLM_TREE/build/kit/$_km_line"
	_km_kabi=$(sed -n 's/^KABI=//p' "$_km_kit/kit.conf")
	_km_pin=$(sed -n 's/^PIN=//p' "$_km_kit/kit.conf")
	mkdir -p "$_km_build"
	rm -rf "$_km_build/chk"; mkdir -p "$_km_build/chk"; cp "$_km_obj" "$_km_build/chk/$KM_NAME"
	( . "$AMIX_SIBLINGS/gcc-cross-amix/build/env.sh" >/dev/null 2>&1
	  command -v m68k-cbm-sysv4-scan060 >/dev/null || { echo "no scan060 on PATH"; exit 1; }
	  python3 -I "$_km_kit/tools/modcheck.py" -k "$_km_kit" $_km_d \
		${KM_PAGESHIFT_OK:+-w "$KM_PAGESHIFT_OK"} "$_km_build/chk/$KM_NAME" ) \
		> "$_km_build/modcheck.out" 2>&1 || {
		cat "$_km_build/modcheck.out" >&2; echo "[FAIL] modcheck refuses $KM_NAME ($_km_line)" >&2; exit 1; }
	grep -q "^modcheck: $KM_NAME: ok ($_km_kabi, " "$_km_build/modcheck.out" || {
		cat "$_km_build/modcheck.out" >&2; echo "[FAIL] modcheck did not say ok for $_km_kabi" >&2; exit 1; }
	sed 's/^/  /' "$_km_build/modcheck.out"
	# the .moddata keys the catalog row and kbootset read
	_km_md=$(python3 -I - "$_km_obj" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
shoff, = struct.unpack('>I', d[32:36]); shentsize, shnum, shstrndx = struct.unpack('>HHH', d[46:52])
sh = [struct.unpack('>10I', d[shoff + i * shentsize: shoff + i * shentsize + 40]) for i in range(shnum)]
strs = sh[shstrndx]
nm = lambda o: d[strs[4] + o: d.index(b'\0', strs[4] + o)].decode()
s = [x for x in sh if nm(x[0]) == '.moddata'][0]
body = d[s[4]: s[4] + s[5]]
print(' '.join(k.decode() for k in body[8:].split(b'\0') if b'=' in k and not k.startswith((b'desc=', b'param='))))
PY
)
	echo "  .moddata: $_km_md"
	case " $_km_md " in *" name=$KM_NAME "*) ;; *) echo "[FAIL] .moddata name= is not $KM_NAME" >&2; exit 1 ;; esac
	case " $_km_md " in *" kabi=$_km_kabi "*) ;; *) echo "[FAIL] .moddata kabi= is not $_km_kabi" >&2; exit 1 ;; esac
	case " $_km_md " in *" cc=$_km_pin "*) ;; *) echo "[FAIL] .moddata cc= is not $_km_pin" >&2; exit 1 ;; esac

	rm -rf "$_km_dest" "$_km_work"
	mkdir -p "$_km_dest/etc/conf/mod.d" "$_km_dest/etc/conf/modreg.d" "$_km_work"
	cp "$_km_obj" "$_km_dest/etc/conf/mod.d/$KM_NAME"
	cp "$_km_dir/modreg" "$_km_dest/etc/conf/modreg.d/$KM_NAME"
	echo "${KM_FILES:-}" | while read _p _s _h _m; do
		[ -n "$_p" ] || continue
		case "$_p" in /etc/conf/*|/dev/*|/stand/*|*/../*|*/./*|[!/]*)
			echo "[FAIL] KM_FILES: $_p is not a plain path outside /etc/conf, /dev and /stand" >&2; exit 1 ;; esac
		grep -q "^f none $_p $_m " "$_km_dir/prototype" || {
			echo "[FAIL] KM_FILES: the prototype has no 'f none $_p $_m'" >&2; exit 1; }
		amix_verify "$AMIX_SIBLINGS/$_s" "$_h"
		mkdir -p "$_km_dest${_p%/*}"
		cp "$AMIX_SIBLINGS/$_s" "$_km_dest$_p"
		chmod "$_m" "$_km_dest$_p"
		echo "  $_p = $_s"
	done || exit 1

	{
		echo "$_km_cat $KM_VERSION -- the $KM_NAME kernel module of Amiga UNIX (Amix), line $_km_line"
		echo "(kabi $_km_kabi), built in $KM_REPO with the amix-dlm ABI kit."
		echo
		echo "The module is linked against the Amiga UNIX kernel interface; Amiga UNIX is"
		echo "Commodore's port of AT&T UNIX System V Release 4, portions copyright AT&T,"
		echo "UNIX System Laboratories and their successors, and Commodore-Amiga, Inc."
		echo "On 2026-09-23 Amiga Corporation approved the distribution of the Commodore"
		echo "Amiga binaries this project builds on.  This project and its developers are"
		echo "not affiliated with, endorsed by, or sponsored by Amiga Corporation.  Amiga"
		echo "is a registered trademark of Amiga Corporation."
		[ -z "${KM_EXTRA_NOTE:-}" ] || { echo; echo "$KM_EXTRA_NOTE"; }
		echo "$KM_LICENCES" | while read _n _h; do
			[ -n "$_n" ] || continue
			echo; echo "======== $_n ========"; echo
			cat "$AMIX_SIBLINGS/$_n"
		done
		echo; echo "======== the amix-dlm ABI kit (module wrapper, headers): LICENSE ========"; echo
		cat "$_km_kit/LICENSE"
	} > "$_km_work/copyright"

	find "$_km_dest" -exec touch -h -d "@$KM_SOURCE_EPOCH" {} +
	chmod 0644 "$_km_dest/etc/conf/mod.d/$KM_NAME" "$_km_dest/etc/conf/modreg.d/$KM_NAME"
	cmp -s "$_km_dest/etc/conf/mod.d/$KM_NAME" "$_km_obj" || { echo "[FAIL] staged object differs" >&2; exit 1; }
	# the payload is exactly the two /etc/conf files and KM_FILES
	_km_n=$(find "$_km_dest" -type f | wc -l)
	[ "$_km_n" -eq $((2 + $(echo "${KM_FILES:-}" | awk 'NF' | wc -l))) ] || {
		echo "[FAIL] $_km_n files staged in $_km_dest" >&2; exit 1; }

	echo "--- package ---"
	cp "$_km_dir/pkginfo.$_km_line" "$_km_work/pkginfo"
	cp "$_km_dir/prototype" "$_km_work/prototype"
	amix_kpkgroll "$_km_work" "$_km_dest" "$_km_pkg" "$KM_VERSION" "$_km_out"
	unset _km_dir _km_line _km_obj _km_sha _km_deps _km_cat _km_pkg _km_build _km_dest _km_work _km_out \
		_km_v _km_vf _km_d _km_kit _km_kabi _km_pin _km_md _km_n _p _n _h _s _m
}
