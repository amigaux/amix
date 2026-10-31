# kfsmod.sh -- the filesystem modules a kernel package carries (amix-dlm
# C2-3 v8 sec 1, C4-6 sec 4): a cut without ufs and s5 built in ships their
# core-tier modules, built with the cut, at /etc/conf/mod.d/<fs> beside the
# kernel.  Sourced by recipes/kernel-k30-m and recipes/kernel-k46-m, never
# executed.
#
#     . "$AMIX_PKG_COMMON/kfsmod.sh"
#     amix_kfsmod_check <line> <fs> <object> <sha256> <size> <build> <kabi> <kit> <outdir> [<module kabi>]
#     amix_kfsmod_rebuild <line> <fs> <carve dir> <object> <kit> <workdir> [<extra>]
#     amix_kcore_strips <dlm-rev file> <pinned core commit> <strip commit>
#     amix_kbuildid3 <unix (ET_REL)> <kabi> <log> <module>...
#
# check: the pin (sha256, size); the kit's modcheck (k46: the 68060 scan
# with the pinned toolchain's scan060); .moddata name=<fs> fs=<fs>
# class=boot tier=core kabi=<module kabi> cc=<the kit's pin> and build= the
# cut's own (C3-1 sec 3: a core-tier module loads only on the kernel build
# it was made with, so the package refuses one of another cut).  <kabi> is
# the kernel's and the kit's (kit.conf KABI=); <module kabi>, default
# <kabi>, what the module says: a module carries the highest minor it
# imports, never below 1.2 (amix-dlm C3-2 v2), so a filesystem module built
# with a kabi 1.3 kit says 1.2.
# rebuild (S5-12 R2): the carve directory's sources (Makefile, Master,
# <fs>_wrap.c; never its build/) copied into <workdir>, `make KIT=<kit>`
# (with <extra>, also EXTRA=<extra>: the stock exp object where it is now,
# when the carve's Makefile names it where the cut was made),
# the result byte-equal to the pinned object, modcheck ok, and no warning
# naming rootvp (the kit's allowlist binds it, amix-dlm 445c12e; COMMON
# warnings naming the module's own symbols are expected).
# kcore_strips (S5-13): the cut's module core (the port's build/dlm-rev/.rev)
# is the pinned amix-dlm commit, and that commit contains <strip commit>
# (7b07bce: plat_dmainit skips the stamp's leading blank; an older core took
# " 68060-..." verbatim and refused every core-tier module, EBADVER).
# kbuildid3: the core's rule over the shipped bytes (kbuildid.py): the
# image's buildid without its leading blanks == the sidecar's build= == each
# module's .moddata build=, byte for byte.  tools/kbuildid-selftest.sh
# proves both refuse.

case "${0##*/}" in
kfsmod.sh)
	echo "[FAIL] kfsmod.sh is sourced, not executed" >&2
	exit 1
	;;
esac

# The period cross toolchain is layout.sh's AMIX_CROSS_ENV, so a worktree and
# the build container work as the main checkout does; without layout.sh it
# is the sibling gcc-cross-amix.
AMIX_CROSS_ENV="${AMIX_CROSS_ENV:-$AMIX_SIBLINGS/gcc-cross-amix/build/env.sh}"

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
	( . "$AMIX_CROSS_ENV" >/dev/null 2>&1
	  command -v m68k-cbm-sysv4-scan060 >/dev/null || { echo "no scan060 on PATH"; exit 1; }
	  python3 -I "$1/tools/modcheck.py" -k "$1" "$2" ) > "$3" 2>&1
}

amix_kfsmod_check() {
	_kf_line=$1 _kf_fs=$2 _kf_obj=$3 _kf_sha=$4 _kf_size=$5 _kf_build=$6 _kf_kabi=$7 _kf_kit=$8 _kf_out=$9
	_kf_mkabi=${10:-$7}
	amix_verify "$_kf_obj" "$_kf_sha"
	[ "$(stat -c%s "$_kf_obj")" = "$_kf_size" ] || {
		echo "[FAIL] $_kf_obj: $(stat -c%s "$_kf_obj") bytes, the pin $_kf_size" >&2; exit 1; }
	grep -qx "LINE=$_kf_line" "$_kf_kit/kit.conf" && grep -qx "KABI=$_kf_kabi" "$_kf_kit/kit.conf" || {
		echo "[FAIL] $_kf_kit is not the $_kf_line kit of kabi $_kf_kabi" >&2; exit 1; }
	_kf_pin=$(sed -n 's/^PIN=//p' "$_kf_kit/kit.conf")
	rm -rf "$_kf_out"; mkdir -p "$_kf_out"; cp "$_kf_obj" "$_kf_out/$_kf_fs"
	amix_kfsmod_modcheck "$_kf_kit" "$_kf_out/$_kf_fs" "$_kf_out/modcheck.out" || {
		cat "$_kf_out/modcheck.out" >&2; echo "[FAIL] modcheck refuses $_kf_fs ($_kf_line)" >&2; exit 1; }
	grep -q "^modcheck: $_kf_fs: ok ($_kf_mkabi, boot, " "$_kf_out/modcheck.out" || {
		cat "$_kf_out/modcheck.out" >&2; echo "[FAIL] modcheck did not say ok ($_kf_mkabi, boot) for $_kf_fs" >&2; exit 1; }
	! grep -q rootvp "$_kf_out/modcheck.out" || {
		grep rootvp "$_kf_out/modcheck.out" >&2; echo "[FAIL] modcheck names rootvp for $_kf_fs" >&2; exit 1; }
	_kf_md=$(amix_kfsmod_moddata "$_kf_obj")
	for _kf_kv in "name=$_kf_fs" "fs=$_kf_fs" class=boot tier=core "kabi=$_kf_mkabi" "cc=$_kf_pin" "build=$_kf_build"; do
		case " $_kf_md " in *" $_kf_kv "*) ;; *)
			echo "[FAIL] $_kf_fs ($_kf_line): .moddata lacks $_kf_kv: $_kf_md" >&2; exit 1 ;; esac
	done
	echo "  $_kf_fs: ${_kf_sha%${_kf_sha#????????}}... $_kf_size B; $(tail -1 "$_kf_out/modcheck.out"); .moddata $_kf_md"
	unset _kf_line _kf_fs _kf_obj _kf_sha _kf_size _kf_build _kf_kabi _kf_kit _kf_out _kf_pin _kf_md _kf_kv _kf_mkabi
}

amix_kfsmod_rebuild() {
	_kr_line=$1 _kr_fs=$2 _kr_carve=$3 _kr_obj=$4 _kr_kit=$5 _kr_w=$6 _kr_x=${7:-}
	rm -rf "$_kr_w"; mkdir -p "$_kr_w"
	for _kr_f in Makefile Master "${_kr_fs}_wrap.c"; do
		cp "$_kr_carve/$_kr_f" "$_kr_w/" || { echo "[FAIL] no $_kr_carve/$_kr_f" >&2; exit 1; }
	done
	( . "$AMIX_CROSS_ENV" >/dev/null 2>&1
	  make -C "$_kr_w" KIT="$_kr_kit" ${_kr_x:+EXTRA="$_kr_x"} ) > "$_kr_w.log" 2>&1 || {
		tail -15 "$_kr_w.log" >&2; echo "[FAIL] the $_kr_fs carve ($_kr_line) did not rebuild" >&2; exit 1; }
	grep -q "^modcheck: $_kr_fs: ok (" "$_kr_w.log" || {
		tail -5 "$_kr_w.log" >&2; echo "[FAIL] the rebuilt $_kr_fs: no modcheck ok" >&2; exit 1; }
	! grep -q rootvp "$_kr_w.log" || {
		grep rootvp "$_kr_w.log" >&2; echo "[FAIL] the rebuilt $_kr_fs: a warning names rootvp" >&2; exit 1; }
	cmp -s "$_kr_w/build/$_kr_line/mod.d/$_kr_fs" "$_kr_obj" || {
		echo "[FAIL] the rebuilt $_kr_fs ($_kr_line) differs from the pinned object" >&2; exit 1; }
	echo "  rebuilt $_kr_fs from $_kr_carve: byte-equal to the pin; $(grep "^modcheck: $_kr_fs: ok" "$_kr_w.log"); $(grep -c "^modcheck: $_kr_fs: warning: COMMON" "$_kr_w.log") COMMON warnings, none naming rootvp (log $_kr_w.log)"
	unset _kr_line _kr_fs _kr_carve _kr_obj _kr_kit _kr_w _kr_f _kr_x
}

amix_kcore_strips() {
	_kc_rev=$(cat "$1" 2>/dev/null)
	_kc_pin=$(git -C "$AMIX_DLM" rev-parse "$2^{commit}" 2>/dev/null)
	if [ -z "$_kc_rev" ] || [ "$_kc_rev" != "$_kc_pin" ]; then
		echo "[FAIL] the cut's module core ($1: '$_kc_rev') is not amix-dlm $2" >&2
		unset _kc_rev _kc_pin; return 1
	fi
	if ! git -C "$AMIX_DLM" merge-base --is-ancestor "$3" "$_kc_rev" 2>/dev/null; then
		echo "[FAIL] the cut's core $2 predates $3: it keeps the stamp's leading blank and refuses every core-tier module (S5-13)" >&2
		unset _kc_rev _kc_pin; return 1
	fi
	echo "  the cut's core: amix-dlm $2 (dlm-rev ${_kc_rev%${_kc_rev#???????}}), contains $3 (skips the stamp's leading blank)"
	unset _kc_rev _kc_pin
}

amix_kbuildid3() {
	_kb_u=$1 _kb_k=$2 _kb_log=$3; shift 3
	if ! python3 -I "$AMIX_PKG_COMMON/kbuildid.py" "$_kb_u" "$_kb_k" "$@" > "$_kb_log" 2>&1; then
		cat "$_kb_log" >&2; echo "[FAIL] the core's build-id rule refuses (kbuildid.py)" >&2
		unset _kb_u _kb_k _kb_log; return 1
	fi
	sed 's/^/  /' "$_kb_log"
	unset _kb_u _kb_k _kb_log
}
