# kpkgroll.sh -- roll a KERNEL-SPACE package (kernel or loader, contract
# amix-dlm C2-3) into an SVR4 .pkg datastream.  Sourced, never executed.
#
#     . "$AMIX_PKG_COMMON/kpkgroll.sh"
#     amix_kpkgroll <workdir> <destroot> <PKG> <version> <outfile>
#     (with SOURCE_DATE_EPOCH, the time of every stamp: dsroll.sh)
#
# Same pkgmk/pkgtrans path and the same name/arch/s5/newc gates as
# amix_pkgroll (pkgroll.sh), with three differences, each from a contract:
#
#  1. PURE FILES (amix-dlm spec 40 sec 6; apkg 0.3 ds_pure_files and
#     gen-catalog's pure_files_problem refuse anything else): the prototype
#     holds only `f`/`d` objects of class none and `i` entries pkginfo,
#     depend or copyright.  No install scripts, no links, no classes.
#     A module package (an f under /etc/conf/mod.d/) may also carry the
#     device nodes of its driver's majors as `c <class> /dev/<node> <major>
#     <minor> <mode> <owner> <group>` (amix-dlm C3-5 sec 1.2, 568b9ac), and
#     a block driver's as `b <class> /dev/dsk/<node> ...` (C3-5 v8 sec 1.2).
#     The class is the module's name, its file name in /etc/conf/mod.d
#     (C3-5 v18 sec 1.2), and pkginfo's CLASSES lists it (dsroll.sh
#     amix_classes); `none` stays legal for a package minted before v18.
#  2. NO USERLAND 68060 GATE.  A kernel image is not a userland program: the
#     040/060 kernel carries fpsp060/isp060 tables a scanner reads as movep,
#     and a k30 kernel never runs on a 68060.  Kernel objects are gated by
#     the kernel build (k0-gates, scan060 on the objects it compiles); boot1
#     and boot2 are raw code, not ELF.  This roll checks the bytes instead:
#     every payload file must come back out of the datastream unchanged.
#  3. No KSUM_R / BOOT2_SHA in pkginfo: those mark the old private kernel
#     packages, which gen-catalog refuses from any catalog.

case "${0##*/}" in
kpkgroll.sh)
	echo "[FAIL] kpkgroll.sh is sourced, not executed" >&2
	exit 1
	;;
esac

amix_kpkgroll() {
	_kr_work="$1"
	_kr_root="$2"
	_kr_pkg="$3"
	_kr_ver="$4"
	_kr_final="$5"
	# rolled under the work dir; installed at <outfile> only through the
	# one-version check (onever.sh), which leaves <outfile> as it was on refusal
	_kr_out="$_kr_work/.roll/$(basename "$_kr_final")"
	command -v amix_one_version >/dev/null 2>&1 || . "$AMIX_PKG_COMMON/onever.sh"

	[ -x "$AMIX_PKGMK" ]    || { echo "[FAIL] host pkgmk missing: $AMIX_PKGMK" >&2; exit 1; }
	[ -x "$AMIX_PKGTRANS" ] || { echo "[FAIL] host pkgtrans missing: $AMIX_PKGTRANS" >&2; exit 1; }
	[ -f "$_kr_work/pkginfo" ]   || { echo "[FAIL] no pkginfo in $_kr_work" >&2; exit 1; }
	[ -f "$_kr_work/prototype" ] || { echo "[FAIL] no prototype in $_kr_work" >&2; exit 1; }

	# GATE 1 -- PKG name <= 9 characters (stock pkgadd silently drops longer).
	[ "${#_kr_pkg}" -le 9 ] || {
		echo "[FAIL] PKG name '$_kr_pkg' is ${#_kr_pkg} characters (> 9)" >&2; exit 1; }

	# GATE 2 -- pkginfo says what we think, and carries no private marker.
	grep -q "^PKG=$_kr_pkg\$" "$_kr_work/pkginfo" || {
		echo "[FAIL] pkginfo does not say PKG=$_kr_pkg" >&2; exit 1; }
	grep -q '^ARCH=Amiga$' "$_kr_work/pkginfo" || {
		echo "[FAIL] pkginfo must say ARCH=Amiga" >&2; exit 1; }
	grep -q "^VERSION=$_kr_ver\$" "$_kr_work/pkginfo" || {
		echo "[FAIL] pkginfo VERSION is not $_kr_ver" >&2; exit 1; }
	if grep -Eq '^(KSUM_R|BOOT2_SHA)=.' "$_kr_work/pkginfo"; then
		echo "[FAIL] pkginfo carries KSUM_R/BOOT2_SHA (the private-kernel markers)" >&2
		exit 1
	fi

	# GATE 3 -- pure files (40 sec 6).
	awk '
		/^[ \t]*#/ || NF == 0 { next }
		$1 == "i" { if ($2 !~ /^(pkginfo|depend|copyright)$/) print "BAD i " $2; next }
		$1 == "f" || $1 == "d" { if ($2 != "none") print "BAD class " $2 " " $3;
		                          if ($1 == "f") nf++;
		                          if ($1 == "f" && $3 ~ /^\/etc\/conf\/mod\.d\//) {
		                              mod++; m = $3; sub(/.*\//, "", m); sub(/=.*$/, "", m) }
		                          next }
		$1 == "c" { if ($3 !~ /^\/dev\// || NF != 8 || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/)
		                print "BAD device entry " $0;
		            nc++; node[nc] = $2 " " $3; next }
		$1 == "b" { if ($3 !~ /^\/dev\/dsk\// || NF != 8 || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/)
		                print "BAD block device entry " $0;
		            nc++; node[nc] = $2 " " $3; next }
		{ print "BAD type " $1 " " $3 }
		END { if (!nf) print "BAD no file"
		      if (nc && !mod) print "BAD device entries outside a module package"
		      for (i = 1; i <= nc; i++) {
		          split(node[i], f, " ")
		          if (f[1] != "none" && f[1] != m)
		              print "BAD class " f[1] " " f[2] " (a node'"'"'s class is its module'"'"'s name, " m ", or none before C3-5 v18)"
		      } }
	' "$_kr_work/prototype" > "$_kr_work/.pure"
	if [ -s "$_kr_work/.pure" ]; then
		echo "[FAIL] kernel-space package is not pure files (40 sec 6):" >&2
		cat "$_kr_work/.pure" >&2
		exit 1
	fi
	rm -f "$_kr_work/.pure"

	# GATE 4 -- s5 14-byte basenames (pkgroll.sh gate 3, same rule).
	awk '
		$1 ~ /^[fdcb]$/ && NF >= 3 {
			p = $3; sub(/=.*$/, "", p);
			n = split(p, seg, "/"); base = seg[n];
			if (length(base) > 14) print "TRUNC " p;
		}' "$_kr_work/prototype" > "$_kr_work/.s5scan"
	if [ -s "$_kr_work/.s5scan" ]; then
		echo "[FAIL] basename over the s5 14-byte limit:" >&2
		cat "$_kr_work/.s5scan" >&2; exit 1
	fi
	rm -f "$_kr_work/.s5scan"

	# pkgmk and pkgtrans, every time stamp SOURCE_DATE_EPOCH (dsroll.sh)
	command -v amix_dsroll >/dev/null 2>&1 || . "$AMIX_PKG_COMMON/dsroll.sh"
	amix_dsroll "$_kr_work" "$_kr_root" "$_kr_pkg" "$_kr_out"

	# GATE 5 -- newc members.
	_kr_magic=$(dd if="$_kr_out" bs=1 skip=512 count=6 2>/dev/null)
	[ "$_kr_magic" = 070701 ] || {
		echo "[FAIL] $_kr_out member magic '$_kr_magic' != 070701" >&2; exit 1; }

	# GATE 6 -- round trip: every payload file back out, byte for byte.
	_kr_rt="$_kr_work/.roundtrip"
	rm -rf "$_kr_rt"; mkdir -p "$_kr_rt"
	"$AMIX_PKGTRANS" "$_kr_out" "$_kr_rt" "$_kr_pkg" >/dev/null 2>&1 || true
	[ -f "$_kr_rt/$_kr_pkg/pkgmap" ] || {
		echo "[FAIL] cannot unpack $_kr_out" >&2; exit 1; }
	_kr_n=0
	for _kr_p in $(awk '$1 == "f" {p = $3; sub(/=.*$/, "", p); print p}' "$_kr_work/prototype"); do
		cmp -s "$_kr_root$_kr_p" "$_kr_rt/$_kr_pkg/root$_kr_p" || {
			echo "[FAIL] round trip: $_kr_p differs in the datastream" >&2; exit 1; }
		_kr_n=$((_kr_n + 1))
	done
	echo "  round trip: $_kr_n payload file(s) identical; pkgmap classes:" \
		"$(awk '$1 ~ /^[0-9]+$/ {print $2 "/" $3}' "$_kr_rt/$_kr_pkg/pkgmap" | sort -u | tr '\n' ' ')"
	rm -rf "$_kr_rt" "$_kr_work/.spool"

	amix_one_version "$_kr_out" "$_kr_pkg" "$_kr_ver" "$_kr_final"
	echo "  built   $_kr_final ($(stat -c%s "$_kr_final") bytes, sha256 $(sha256sum "$_kr_final" | cut -c1-64))"
	unset _kr_work _kr_root _kr_pkg _kr_ver _kr_out _kr_final _kr_magic _kr_rt _kr_n _kr_p
}

# amix_kstage_sidecar <build-sidecar> <shipped-unix> <out> <bss> -- the
# kernel build's sidecar FOR THE FORM SHIPPED (C2-3 v4 sec 2, sec 5).  The
# kernel build wrote it for its ET_REL link; stage 2 ships the brel, and the
# recipe step that converts ET_REL -> brel is the last step of that build, so
# it writes the brel's sidecar here: every line of the build's sidecar byte
# for byte, except size= and sha256=, which describe the brel file, and
# bss=, added after sha256= -- the bytes past the brel image to the kernel's
# end (bss and COMMON), which a brel does not record.  Packaging then copies
# this file verbatim.  Refuses unless size= and sha256= exist once and the
# build's sidecar carries no bss= of its own that disagrees.
amix_kstage_sidecar() {
	_ks_size=$(stat -c%s "$2")
	_ks_sha=$(sha256sum "$2" | cut -c1-64)
	[ "$(grep -c '^size=' "$1")" = 1 ] && [ "$(grep -c '^sha256=' "$1")" = 1 ] || {
		echo "[FAIL] $1 lacks exactly one size= and one sha256=" >&2; exit 1; }
	case "$4" in ''|*[!0-9]*) echo "[FAIL] amix_kstage_sidecar: bss '$4' is not a number" >&2; exit 1 ;; esac
	if grep -q '^bss=' "$1" && ! grep -qx "bss=$4" "$1"; then
		echo "[FAIL] $1 already says $(grep '^bss=' "$1"), not bss=$4" >&2; exit 1
	fi
	awk -v s="$_ks_size" -v h="$_ks_sha" -v b="$4" '
		/^bss=/    { next }
		/^size=/   { print "size=" s; next }
		/^sha256=/ { print "sha256=" h; print "bss=" b; next }
		{ print }' "$1" > "$3"
	# exactly size=, sha256= and bss= may differ
	_ks_d=$(diff "$1" "$3" | grep -c '^>' || true)
	[ "$_ks_d" -le 3 ] || { echo "[FAIL] sidecar restatement changed $_ks_d lines" >&2; exit 1; }
	unset _ks_size _ks_sha _ks_d
}

# amix_kbrel_bss <et_rel> <brel> <axrel> -- the brel's bss= measured twice:
# elf2brel's own bss-tail (the converter that stamps `end`) is passed in by
# the caller as K_BSS_E2B; the loader's relocator binds the ET_REL at 0 and
# its end minus the brel's combined image size is the second reading.  The
# two must agree; prints the value.
amix_kbrel_bss() {
	_kb_end=$("$3" "$1" 0 /dev/null pcrel 2>&1 | sed -n 's/.*end 0x\([0-9a-f]*\)$/\1/p')
	_kb_img=$("$3" "$2" 0 /dev/null 2>&1 | sed -n 's/.*end 0x\([0-9a-f]*\)$/\1/p')
	[ -n "$_kb_end" ] && [ -n "$_kb_img" ] || { echo "[FAIL] axrel could not bind $1 / $2" >&2; exit 1; }
	_kb_bss=$(( 0x$_kb_end - 0x$_kb_img ))
	[ "$_kb_bss" = "$K_BSS_E2B" ] || {
		echo "[FAIL] bss: elf2brel says $K_BSS_E2B, the loader's relocator $_kb_bss" >&2; exit 1; }
	echo "$_kb_bss"
	unset _kb_end _kb_img _kb_bss
}
