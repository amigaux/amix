# kfsmod.sh -- the filesystem modules a kernel package carries (amix-dlm
# C2-3 v8 sec 1, C4-6 sec 4): a cut without ufs and s5 built in ships their
# core-tier modules, built with the cut, at /etc/conf/mod.d/<fs> beside the
# kernel.  Sourced by recipes/kernel-k30-m and recipes/kernel-k46-m, never
# executed.
#
#     . "$REPO/recipes/common/kfsmod.sh"
#     amix_kfsmod_check <line> <fs> <object> <sha256> <size> <build> <kabi> <kit> <outdir>
#     amix_kfsmod_rebuild <line> <fs> <carve dir> <object> <kit> <workdir>
#
# check: the pin (sha256, size); the kit's modcheck (k46: the 68060 scan
# with the pinned toolchain's scan060); .moddata name=<fs> fs=<fs>
# class=boot tier=core kabi=<the line's> cc=<the kit's pin> and build= the
# cut's own (C3-1 sec 3: a core-tier module loads only on the kernel build
# it was made with, so the package refuses one of another cut).
# rebuild (S5-12 R2): the carve directory's sources (Makefile, Master,
# <fs>_wrap.c; never its build/) copied into <workdir>, `make KIT=<kit>`,
# the result byte-equal to the pinned object, modcheck ok, and no warning
# naming rootvp (the kit's allowlist binds it, amix-dlm 445c12e; COMMON
# warnings naming the module's own symbols are expected).

case "${0##*/}" in
kfsmod.sh)
	echo "[FAIL] kfsmod.sh is sourced, not executed" >&2
	exit 1
	;;
esac

# the .moddata keys of an object, space-separated (desc=/param= left out)
amix_kfsmod_moddata() {
	python3 -I - "$1" <<'PY'
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
}

amix_kfsmod_modcheck() {   # <kit> <object copy named <fs>> <out>
	( . "$AMIX_SIBLINGS/gcc-cross-amix/build/env.sh" >/dev/null 2>&1
	  command -v m68k-cbm-sysv4-scan060 >/dev/null || { echo "no scan060 on PATH"; exit 1; }
	  python3 -I "$1/tools/modcheck.py" -k "$1" "$2" ) > "$3" 2>&1
}

amix_kfsmod_check() {
	_kf_line=$1 _kf_fs=$2 _kf_obj=$3 _kf_sha=$4 _kf_size=$5 _kf_build=$6 _kf_kabi=$7 _kf_kit=$8 _kf_out=$9
	amix_verify "$_kf_obj" "$_kf_sha"
	[ "$(stat -c%s "$_kf_obj")" = "$_kf_size" ] || {
		echo "[FAIL] $_kf_obj: $(stat -c%s "$_kf_obj") bytes, the pin $_kf_size" >&2; exit 1; }
	grep -qx "LINE=$_kf_line" "$_kf_kit/kit.conf" && grep -qx "KABI=$_kf_kabi" "$_kf_kit/kit.conf" || {
		echo "[FAIL] $_kf_kit is not the $_kf_line kit of kabi $_kf_kabi" >&2; exit 1; }
	_kf_pin=$(sed -n 's/^PIN=//p' "$_kf_kit/kit.conf")
	rm -rf "$_kf_out"; mkdir -p "$_kf_out"; cp "$_kf_obj" "$_kf_out/$_kf_fs"
	amix_kfsmod_modcheck "$_kf_kit" "$_kf_out/$_kf_fs" "$_kf_out/modcheck.out" || {
		cat "$_kf_out/modcheck.out" >&2; echo "[FAIL] modcheck refuses $_kf_fs ($_kf_line)" >&2; exit 1; }
	grep -q "^modcheck: $_kf_fs: ok ($_kf_kabi, boot, " "$_kf_out/modcheck.out" || {
		cat "$_kf_out/modcheck.out" >&2; echo "[FAIL] modcheck did not say ok ($_kf_kabi, boot) for $_kf_fs" >&2; exit 1; }
	! grep -q rootvp "$_kf_out/modcheck.out" || {
		grep rootvp "$_kf_out/modcheck.out" >&2; echo "[FAIL] modcheck names rootvp for $_kf_fs" >&2; exit 1; }
	_kf_md=$(amix_kfsmod_moddata "$_kf_obj")
	for _kf_kv in "name=$_kf_fs" "fs=$_kf_fs" class=boot tier=core "kabi=$_kf_kabi" "cc=$_kf_pin" "build=$_kf_build"; do
		case " $_kf_md " in *" $_kf_kv "*) ;; *)
			echo "[FAIL] $_kf_fs ($_kf_line): .moddata lacks $_kf_kv: $_kf_md" >&2; exit 1 ;; esac
	done
	echo "  $_kf_fs: ${_kf_sha%${_kf_sha#????????}}... $_kf_size B; $(tail -1 "$_kf_out/modcheck.out"); .moddata $_kf_md"
	unset _kf_line _kf_fs _kf_obj _kf_sha _kf_size _kf_build _kf_kabi _kf_kit _kf_out _kf_pin _kf_md _kf_kv
}

amix_kfsmod_rebuild() {
	_kr_line=$1 _kr_fs=$2 _kr_carve=$3 _kr_obj=$4 _kr_kit=$5 _kr_w=$6
	rm -rf "$_kr_w"; mkdir -p "$_kr_w"
	for _kr_f in Makefile Master "${_kr_fs}_wrap.c"; do
		cp "$_kr_carve/$_kr_f" "$_kr_w/" || { echo "[FAIL] no $_kr_carve/$_kr_f" >&2; exit 1; }
	done
	( . "$AMIX_SIBLINGS/gcc-cross-amix/build/env.sh" >/dev/null 2>&1
	  make -C "$_kr_w" KIT="$_kr_kit" ) > "$_kr_w.log" 2>&1 || {
		tail -15 "$_kr_w.log" >&2; echo "[FAIL] the $_kr_fs carve ($_kr_line) did not rebuild" >&2; exit 1; }
	grep -q "^modcheck: $_kr_fs: ok (" "$_kr_w.log" || {
		tail -5 "$_kr_w.log" >&2; echo "[FAIL] the rebuilt $_kr_fs: no modcheck ok" >&2; exit 1; }
	! grep -q rootvp "$_kr_w.log" || {
		grep rootvp "$_kr_w.log" >&2; echo "[FAIL] the rebuilt $_kr_fs: a warning names rootvp" >&2; exit 1; }
	cmp -s "$_kr_w/build/$_kr_line/mod.d/$_kr_fs" "$_kr_obj" || {
		echo "[FAIL] the rebuilt $_kr_fs ($_kr_line) differs from the pinned object" >&2; exit 1; }
	echo "  rebuilt $_kr_fs from $_kr_carve: byte-equal to the pin; $(grep "^modcheck: $_kr_fs: ok" "$_kr_w.log"); $(grep -c "^modcheck: $_kr_fs: warning: COMMON" "$_kr_w.log") COMMON warnings, none naming rootvp (log $_kr_w.log)"
	unset _kr_line _kr_fs _kr_carve _kr_obj _kr_kit _kr_w _kr_f
}
