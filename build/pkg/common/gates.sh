# gates.sh -- the build-time correctness gates every recipe ends in.
# Sourced, never executed.
#
# recipes/README.md rule 2: "Verify the encoding, never the exit status."  On
# this toolchain a clean exit proves nothing -- fcmp operand order, SGS
# '#'-as-comment and constant-folded FP all produce exit 0 and a wrong binary.
# So each of these reads OBJECT CODE out of the shipped artifact.
#
#     . "$REPO/recipes/common/gates.sh"
#     amix_gate_d4   build/dest/usr/local/bin/patch   (file, archive or dir)
#     amix_gate_060_tree build/dest                    (pkgroll runs this)
#     amix_gate_elf  build/dest/usr/local/bin/patch
#     amix_gate_undef build/dest/usr/local/bin/patch

case "${0##*/}" in
gates.sh)
	echo "[FAIL] gates.sh is sourced, not executed" >&2
	exit 1
	;;
esac

# amix_gate_d4 <file|dir...> -- ROADMAP D4, the 68060 gate.  STRICT since
# 2026-10-05: ANY 68060-unimplemented integer instruction fails the build.
#
# The 68060 does not implement MULU.L/MULS.L <ea>,Dh:Dl (64-bit product),
# DIVU.L/DIVS.L <ea>,Dr:Dq (64-bit dividend), MOVEP, CMP2, CHK2 or CAS2; each
# raises vector 61, and the release kernels SIGKILL the process ("u_trap ...
# because of vector 0xF4").  gcc 2.7.2.3 emits the 64-bit product for EVERY
# divide or modulo by a constant (x / 10, x % 1000), so nearly every program
# had some.  Until 2026-10-05 this gate allowed the #imm32 source form on the
# strength of an ISP vector-61 handler that emulates it; the project decision
# of 2026-10-05 ships no package that leans on kernel emulation, and
# the add-ons that passed under the old rule carried 1-30 sites each.  The
# fix is the toolchain's: gcc-cross-amix 2ab2b22 (fix_asm rule 11) rewrites
# every 64-bit multiply into 16x16 mulu.w partial products and fails the
# compile on any 64-bit form left; amix-env.sh refuses AMIX_MUL64=keep and
# turns on the wrapper's per-object post-check (AMIX_SCAN060=1).
#
# ★ THE GATE READS ENCODINGS, NOT MNEMONICS (2026-09-26).  binutils 2.8.1's
# objdump prints MIT syntax (`mulul %fp@(12),%d1,%d2`, no dot, no colon), so a
# mnemonic grep never fires.  Three encoding scanners must ALL pass:
#
#   1. amix_d4_scan (awk, below): every MUL.L/DIV.L (opword 0x4c00-0x4c7f)
#      whose extension word has bit 10 set, whatever the source; and the
#      cmp2/chk2/cas2 mnemonics.  No switch-table awareness, so it does not
#      look for movep (table words decode as movep).
#   2. the toolchain's $TARGET-scan060: the same encoding rule plus movep,
#      decoding around gcc's switch tables.  ★ Run it with a modern m68k
#      objdump (AMIX_SCAN060_OBJDUMP, default m68k-linux-gnu-objdump when
#      installed): binutils 2.8.1 prints a linked executable's 0x8000xxxx
#      addresses sign-extended (ffffffff80000c98), scan060's table finder then
#      skips every table, and table data is reported as movep -- measured
#      2026-10-05 on the published grep-2.5.1a-2 (10 false movep) and fpbench
#      (2).  Without a modern objdump the gate still runs and fails CLOSED.
#
#   3. ../amix-packagemanager/tools/repo/scan060.py (read-only use; the
#      packagemanager's mint gate and the scanner of record for LINKED files
#      and .pkg datastreams): run on every ELF that is not an ar archive --
#      it does not open archives, which is why scanner 2 covers those
#      (the 2026-10-05 scan of the published add-ons missed the 10 sites in
#      libz.a and the one in libacompat.a for that reason).  amix_pkgroll also
#      runs it on the finished datastream (amix_gate_pkg060).
#
# On the published add-ons scanners 2 (with a modern objdump) and 3 agree
# exactly, file by file.
#
# amix_gate_d4_selftest runs on the first amix_gate_d4 call of a build and
# must see every scanner reject probes before any pass is trusted.
amix_d4_scan() {
	"$OBJDUMP" -d "$1" 2>/dev/null | awk -F'\t' '
		function hex(s,   i, c, v) {
			v = 0; s = tolower(s)
			for (i = 1; i <= length(s); i++) {
				c = index("0123456789abcdef", substr(s, i, 1))
				if (c == 0) return -1
				v = v * 16 + c - 1
			}
			return v
		}
		NF >= 3 {
			n = split($2, w, " ")
			if (n >= 1 && length(w[1]) == 4) {
				op = hex(w[1])
				if (op >= 19456 && op <= 19583 && n >= 2 && length(w[2]) == 4) {
					ext = hex(w[2])
					if (int(ext / 1024) % 2 == 1) {
						if (op <= 19519) mul++
						else div++
						print "BAD " $0
					}
				}
			}
			if ($3 ~ /^(cmp2|chk2|cas2)/) { other++; print "BAD " $0 }
		}
		END { printf "SUMMARY %d %d %d\n", mul + 0, div + 0, other + 0 }'
}

# Which objdump scan060 decodes with (see above).
amix_scan060_objdump() {
	if [ -n "$AMIX_SCAN060_OBJDUMP" ]; then
		echo "$AMIX_SCAN060_OBJDUMP"
	elif command -v m68k-linux-gnu-objdump >/dev/null 2>&1; then
		command -v m68k-linux-gnu-objdump
	else
		command -v "$OBJDUMP"
	fi
}

# amix_scan060 <file|dir...> -- the toolchain scanner, quiet unless it hits.
# Under TOOLCHAIN=gcc14 that is gcc14-cross-amix's check-68060-safe.py.
amix_scan060() {
	if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
		amix_check060 "$@"
		return $?
	fi
	AMIX_OBJDUMP=$(amix_scan060_objdump) "$AMIX_TARGET-scan060" "$@"
}

# The name scanner 2 reports under.
amix_scan060_name() {
	if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
		echo "check-68060-safe.py"
	else
		echo "$AMIX_TARGET-scan060"
	fi
}

# amix_check060 [--quiet] <file|dir...> -- gcc14-cross-amix's
# tools/check-68060-safe.py (read-only use) on every m68k ELF object,
# executable or archive at or under each argument.  Exit 0 only if every one
# is clean; its "untrustworthy listing" verdict (exit 3) fails like a hit.
amix_check060() {
	_c6_q=0
	[ "$1" = --quiet ] && { _c6_q=1; shift; }
	_c6_rc=0
	for _c6_a in "$@"; do
		for _c6_e in $(amix_gate_elfs "$_c6_a"); do
			# It reads an ELF or an objdump listing, not an ar archive:
			# an archive goes in as its listing.
			_c6_in="$_c6_e"
			case "$(od -An -c -N8 "$_c6_e" | tr -d ' ')" in
			'!<arch>\n')
				_c6_in=$(mktemp "${TMPDIR:-/tmp}/amix-c6.XXXXXX")
				"$OBJDUMP" -d "$_c6_e" > "$_c6_in" 2>/dev/null
				;;
			esac
			if _c6_out=$(python3 "$AMIX_CHECK060" "$_c6_in" 2>&1); then
				[ $_c6_q -eq 1 ] || echo "  $_c6_e: $(echo "$_c6_out" | tail -1)"
			else
				echo "  $_c6_e:"
				echo "$_c6_out" | sed 's/^/    /'
				_c6_rc=1
			fi
			[ "$_c6_in" = "$_c6_e" ] || rm -f "$_c6_in"
		done
	done
	unset _c6_q _c6_a _c6_e _c6_in _c6_out
	return $_c6_rc
}

# amix_pm_scan060 <elf|pkg|dir...> -- the packagemanager's scanner.
amix_pm_scan060() {
	_pm_s="${AMIX_PM_SCAN060:-$AMIX_PKGMGR/tools/repo/scan060.py}"
	[ -f "$_pm_s" ] || {
		echo "[FAIL] packagemanager scan060.py not found: $_pm_s" >&2
		unset _pm_s; return 1; }
	python3 "$_pm_s" "$@"
	_pm_rc=$?; unset _pm_s; return $_pm_rc
}

amix_gate_d4() {
	_g4_bad=0
	# Prove the gate can fail before trusting any pass -- once per build.
	if [ -z "$AMIX_D4_SELFTESTED" ]; then
		_g4_td=$(mktemp -d "${TMPDIR:-/tmp}/amix-d4.XXXXXX")
		amix_gate_d4_selftest "$_g4_td" || { rm -rf "$_g4_td"; return 1; }
		rm -rf "$_g4_td"
		unset _g4_td
	fi
	for _g4_f in "$@"; do
		[ -e "$_g4_f" ] || { echo "[FAIL] D4 gate: no such file $_g4_f" >&2; return 1; }
		# scanner 1, per ELF/archive (a directory is walked for them)
		for _g4_e in $(amix_gate_elfs "$_g4_f"); do
			_g4_out=$(amix_d4_scan "$_g4_e")
			_g4_sum=$(echo "$_g4_out" | sed -n 's/^SUMMARY //p')
			[ -n "$_g4_sum" ] || { echo "[FAIL] D4 gate: could not disassemble $_g4_e" >&2; return 1; }
			if [ "$_g4_sum" != "0 0 0" ]; then
				echo "  D4 FAIL $_g4_e -- 64-bit mul/div/other: $_g4_sum" >&2
				echo "$_g4_out" | sed -n 's/^BAD /          /p' >&2
				_g4_bad=1
			fi
		done
		# scanner 3, the packagemanager's, per linked ELF (not archives)
		for _g4_e in $(amix_gate_elfs "$_g4_f"); do
			case "$(od -An -c -N2 "$_g4_e" | tr -d ' ')" in 177E) ;; *) continue ;; esac
			if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
				amix_g14_scan3 "$_g4_e" || _g4_bad=1
			elif ! _g4_out=$(amix_pm_scan060 "$_g4_e" 2>&1); then
				echo "  D4 FAIL $_g4_e -- amix-packagemanager scan060.py:" >&2
				echo "$_g4_out" | sed 's/^/          /' >&2
				_g4_bad=1
			fi
		done
		# scanner 2, the toolchain's, on the same argument
		if _g4_out=$(amix_scan060 --quiet "$_g4_f" 2>&1); then
			[ $_g4_bad -ne 0 ] || echo "  D4 ok   $_g4_f (no 64-bit mul/div, movep, cmp2/chk2/cas2; all three scanners)"
		else
			echo "  D4 FAIL $_g4_f -- $(amix_scan060_name):" >&2
			echo "$_g4_out" | sed 's/^/          /' >&2
			_g4_bad=1
		fi
	done
	unset _g4_f _g4_e _g4_out _g4_sum
	return $_g4_bad
}

# amix_gate_elfs <file|dir> -- the m68k ELF objects, executables and ar
# archives at or under a path, one per line (paths with blanks unsupported;
# none of ours have any).
amix_gate_elfs() {
	find "$1" -type f 2>/dev/null | while read -r _ge_p; do
		case "$(od -An -c -N8 "$_ge_p" 2>/dev/null | tr -d ' ')" in
		177ELF*|'!<arch>\n') echo "$_ge_p" ;;
		esac
	done
}

# amix_gate_060_tree <destroot> -- the package-level 68060 gate, run by
# amix_pkgroll on the staged tree BEFORE pkgmk, so no recipe can roll a
# datastream that carries a 68060-unimplemented instruction, whether or not
# it remembered to call amix_gate_d4 on each binary.
amix_gate_060_tree() {
	_amix_gate_060_tree_impl "$@"
}
# The implementation, called directly by the gcc14 datastream gate so that a
# test which stubs amix_gate_060_tree still exercises the datastream path.
_amix_gate_060_tree_impl() {
	_gt_n=$(amix_gate_elfs "$1" | grep -c . || true)
	if [ "$_gt_n" -eq 0 ]; then
		echo "  060 gate: no m68k ELF or archive in the payload (data-only package)"
		unset _gt_n
		return 0
	fi
	echo "  060 gate: $_gt_n m68k ELF/archive file(s) in the payload"
	unset _gt_n
	amix_gate_d4 "$1" || return 1
	[ "$AMIX_TOOLCHAIN" = gcc14 ] || return 0
	_gt_bad=0
	for _gt_e in $(amix_gate_elfs "$1"); do
		# every ELF and archive: no 040/060-only FPU form (a 68881/2 lacks them)
		amix_gate_g14_fpu "$_gt_e" || _gt_bad=1
		case "$(od -An -tx1 -j16 -N2 "$_gt_e" | tr -d ' ')" in 0002) ;; *) continue ;; esac
		amix_gate_g14_needed "$_gt_e" || _gt_bad=1
		amix_gate_g14_llprintf "$_gt_e" || _gt_bad=1
	done
	unset _gt_e
	return $_gt_bad
}

# amix_gate_pkg060 <datastream> -- the packagemanager's scanner on the rolled
# .pkg itself (what the catalog serves), run by amix_pkgroll last.
amix_gate_pkg060() {
	# Under gcc14, scan060.py on the datastream reports GCC 14's switch tables
	# as code (see amix_g14_scan3), so the datastream's payload is unpacked and
	# put through the whole gcc14 tree gate instead: the same bytes, read by
	# the awk scanner, check-68060-safe.py, scan060-g14.py and scan060.py
	# (cross-examined), plus the NEEDED/ll-printf gates.
	if [ "$AMIX_TOOLCHAIN" = gcc14 ]; then
		_gp_d=$(mktemp -d "${TMPDIR:-/tmp}/amix-pkg060.XXXXXX")
		"$AMIX_PKGTRANS" "$1" "$_gp_d" all >/dev/null 2>&1 || {
			echo "  060 FAIL datastream $1 -- pkgtrans could not unpack it" >&2
			rm -rf "$_gp_d"; unset _gp_d; return 1; }
		echo "  060 gate: datastream $(basename "$1") unpacked; the payload as served:"
		if _amix_gate_060_tree_impl "$_gp_d"; then
			rm -rf "$_gp_d"; unset _gp_d; return 0
		fi
		rm -rf "$_gp_d"; unset _gp_d; return 1
	fi
	if _gp_out=$(amix_pm_scan060 "$1" 2>&1); then
		echo "  060 gate: datastream $(basename "$1") -- $(echo "$_gp_out" | tail -1)"
		unset _gp_out; return 0
	fi
	echo "  060 FAIL datastream $1 -- scan060.py:" >&2
	echo "$_gp_out" | sed 's/^/          /' >&2
	unset _gp_out; return 1
}

# amix_gate_d4_selftest <workdir> -- prove the D4 gate can FAIL before
# trusting a pass.  Probes, compiled through the real wrapper:
#   keep.o   AMIX_MUL64=keep: a memory-source 64-bit multiply and a constant
#            divide (the #imm form) -> both scanners must reject it, the awk
#            one counting exactly 2 multiplies;
#   expand.o the same source, default wrapper -> both scanners clean (this is
#            also the proof that the installed wrapper carries rule 11);
#   AMIX_SCAN060=1 with keep -> the wrapper itself must fail the compile;
#   $TARGET-scan060 --self-test (movep, divs.l 64, switch-table skipping).
amix_gate_d4_selftest() {
	[ "$AMIX_TOOLCHAIN" = gcc14 ] && { amix_gate_d4_selftest_g14 "$1"; return $?; }
	_gs_d="$1"
	mkdir -p "$_gs_d"
	cat > "$_gs_d/d4probe.c" <<'D4EOF'
long long d4_bad(long a, long *p) { return (long long)a * *p; }
unsigned d4_imm(unsigned x) { return x / 10; }
D4EOF
	_gs_fail() {
		echo "[FAIL] D4 selftest: $*" >&2
		echo "       The 68060 gate is vacuous or the toolchain lacks rule 11; no pass can be trusted." >&2
	}
	"$AMIX_TARGET-scan060" --self-test >/dev/null 2>&1 || {
		_gs_fail "$AMIX_TARGET-scan060 --self-test failed"; return 1; }
	amix_pm_scan060 --self-test >/dev/null 2>&1 || {
		_gs_fail "amix-packagemanager scan060.py --self-test failed"; return 1; }
	AMIX_MUL64=keep AMIX_SCAN060=0 "$CC" $AMIX_ARCH_FLAGS -O -c "$_gs_d/d4probe.c" -o "$_gs_d/keep.o" || {
		_gs_fail "keep probe did not compile"; return 1; }
	AMIX_MUL64=expand AMIX_SCAN060=0 "$CC" $AMIX_ARCH_FLAGS -O -c "$_gs_d/d4probe.c" -o "$_gs_d/expand.o" || {
		_gs_fail "expanded probe did not compile"; return 1; }
	_gs_sum=$(amix_d4_scan "$_gs_d/keep.o" | sed -n 's/^SUMMARY //p')
	[ "$_gs_sum" = "2 0 0" ] || { _gs_fail "awk scanner on keep.o: want '2 0 0', got '$_gs_sum'"; return 1; }
	_gs_sum=$(amix_d4_scan "$_gs_d/expand.o" | sed -n 's/^SUMMARY //p')
	[ "$_gs_sum" = "0 0 0" ] || { _gs_fail "awk scanner on expand.o: want '0 0 0', got '$_gs_sum'"; return 1; }
	if amix_scan060 --quiet "$_gs_d/keep.o" >/dev/null 2>&1; then
		_gs_fail "$AMIX_TARGET-scan060 passed keep.o"; return 1
	fi
	amix_scan060 --quiet "$_gs_d/expand.o" >/dev/null 2>&1 || {
		_gs_fail "$AMIX_TARGET-scan060 rejected expand.o"; return 1; }
	rm -f "$_gs_d/post.o"
	if AMIX_MUL64=keep AMIX_SCAN060=1 "$CC" $AMIX_ARCH_FLAGS -O -c "$_gs_d/d4probe.c" -o "$_gs_d/post.o" >/dev/null 2>&1 \
	   || [ -f "$_gs_d/post.o" ]; then
		_gs_fail "AMIX_SCAN060=1 did not fail the keep compile"; return 1
	fi
	printf 'int main(int c, char **v) { return (int)((unsigned)c / 10); }\n' > "$_gs_d/main.c"
	AMIX_MUL64=keep AMIX_SCAN060=0 "$CC" $AMIX_ARCH_FLAGS -O -o "$_gs_d/keep" "$_gs_d/main.c" >/dev/null 2>&1 || {
		_gs_fail "keep executable did not link"; return 1; }
	AMIX_MUL64=expand AMIX_SCAN060=0 "$CC" $AMIX_ARCH_FLAGS -O -o "$_gs_d/expand" "$_gs_d/main.c" >/dev/null 2>&1 || {
		_gs_fail "expanded executable did not link"; return 1; }
	if amix_pm_scan060 "$_gs_d/keep" >/dev/null 2>&1; then
		_gs_fail "scan060.py passed a linked keep executable"; return 1
	fi
	amix_pm_scan060 "$_gs_d/expand" >/dev/null 2>&1 || {
		_gs_fail "scan060.py rejected the linked expanded executable"; return 1; }
	echo "  D4 selftest ok (keep probes rejected by all three scanners and by AMIX_SCAN060; expanded probes clean)"
	AMIX_D4_SELFTESTED=1
	unset _gs_d _gs_sum
	return 0
}

# amix_g14_scan3 <linked elf> -- scanner 3 under TOOLCHAIN=gcc14.
# scan060.py sizes switch tables for gcc 2.7's layout and reads GCC 14's
# tables as code (recipes/common/gcc14/scan060-g14.py says how), so here
# scanner 3 is scan060-g14.py, which sizes each table from its bound check and
# refuses a verdict on one it cannot size; and scan060.py still runs as an
# independent decoder: any hit it reports must be explained by scan060-g14.py
# (inside a sized table, or at an odd address), or the gate fails.
amix_g14_scan3() {
	_g3_s="$AMIX_REPO_ROOT/recipes/common/gcc14/scan060-g14.py"
	if ! _g3_out=$(OBJDUMP="$OBJDUMP" python3 "$_g3_s" "$1" 2>&1); then
		echo "  D4 FAIL $1 -- scan060-g14.py:" >&2
		echo "$_g3_out" | sed 's/^/          /' >&2
		unset _g3_s _g3_out; return 1
	fi
	echo "$_g3_out"
	_g3_tmp=$(mktemp "${TMPDIR:-/tmp}/amix-s6.XXXXXX")
	if amix_pm_scan060 "$1" > "$_g3_tmp" 2>&1; then
		echo "  scan060.py: clean"
	elif _g3_out=$(OBJDUMP="$OBJDUMP" python3 "$_g3_s" --explain "$_g3_tmp" "$1" 2>&1); then
		echo "  scan060.py hits on $(basename "$1"):$(echo "$_g3_out" | sed 's/^ *explained [^:]*://')"
	else
		echo "  D4 FAIL $1 -- scan060.py hits not explained by table sizing:" >&2
		sed 's/^/          /' "$_g3_tmp" >&2
		echo "$_g3_out" | sed 's/^/          /' >&2
		rm -f "$_g3_tmp"; unset _g3_s _g3_out _g3_tmp; return 1
	fi
	rm -f "$_g3_tmp"
	unset _g3_s _g3_out _g3_tmp
	return 0
}

# amix_gate_d4_selftest_g14 <workdir> -- the same proof under TOOLCHAIN=gcc14.
# GCC 14 has no AMIX_MUL64 switch; -m68020 is what brings the 64-bit forms
# back (it emits MULS.L <ea>,Dh:Dl for a long long product and MULU.L #imm,
# Dh:Dl for x / 10), and the recipe flags (-m68020-60: tuned for the 060) keep
# them out.  So: the probe
# built -m68020 must be rejected by all three scanners, the awk one counting
# exactly 2 multiplies; built with the recipe flags it must be clean; and the
# same for a linked executable, which is what scan060.py reads.
amix_gate_d4_selftest_g14() {
	_gs_d="$1"
	mkdir -p "$_gs_d"
	cat > "$_gs_d/d4probe.c" <<'D4EOF'
long long d4_bad(long a, long *p) { return (long long)a * *p; }
unsigned d4_imm(unsigned x) { return x / 10; }
D4EOF
	printf 'int main(int c, char **v) { return (int)((unsigned)c / 10); }\n' > "$_gs_d/main.c"
	_gs_fail() {
		echo "[FAIL] D4 selftest (gcc14): $*" >&2
		echo "       The 68060 gate is vacuous; no pass can be trusted." >&2
	}
	amix_pm_scan060 --self-test >/dev/null 2>&1 || {
		_gs_fail "amix-packagemanager scan060.py --self-test failed"; return 1; }
	$CC -m68020 -O2 -c "$_gs_d/d4probe.c" -o "$_gs_d/keep.o" || {
		_gs_fail "-m68020 probe did not compile"; return 1; }
	$CC $AMIX_ARCH_FLAGS -O2 -c "$_gs_d/d4probe.c" -o "$_gs_d/expand.o" || {
		_gs_fail "$AMIX_ARCH_FLAGS probe did not compile"; return 1; }
	$CC -m68020 -O2 -o "$_gs_d/keep" "$_gs_d/main.c" || {
		_gs_fail "-m68020 executable did not link"; return 1; }
	$CC $AMIX_ARCH_FLAGS -O2 -o "$_gs_d/expand" "$_gs_d/main.c" || {
		_gs_fail "$AMIX_ARCH_FLAGS executable did not link"; return 1; }
	_gs_sum=$(amix_d4_scan "$_gs_d/keep.o" | sed -n 's/^SUMMARY //p')
	[ "$_gs_sum" = "2 0 0" ] || { _gs_fail "awk scanner on keep.o: want '2 0 0', got '$_gs_sum'"; return 1; }
	_gs_sum=$(amix_d4_scan "$_gs_d/expand.o" | sed -n 's/^SUMMARY //p')
	[ "$_gs_sum" = "0 0 0" ] || { _gs_fail "awk scanner on expand.o: want '0 0 0', got '$_gs_sum'"; return 1; }
	for _gs_f in keep.o keep; do
		if amix_check060 --quiet "$_gs_d/$_gs_f" >/dev/null 2>&1; then
			_gs_fail "check-68060-safe.py passed $_gs_f"; return 1
		fi
	done
	for _gs_f in expand.o expand; do
		amix_check060 --quiet "$_gs_d/$_gs_f" >/dev/null 2>&1 || {
			_gs_fail "check-68060-safe.py rejected $_gs_f"; return 1; }
	done
	if amix_pm_scan060 "$_gs_d/keep" >/dev/null 2>&1; then
		_gs_fail "scan060.py passed the linked -m68020 executable"; return 1
	fi
	amix_pm_scan060 "$_gs_d/expand" >/dev/null 2>&1 || {
		_gs_fail "scan060.py rejected the linked $AMIX_ARCH_FLAGS executable"; return 1; }
	# scan060-g14.py: rejects the 64-bit product and a movep; sizes a GCC 14
	# switch table (the probe's) and passes it; refuses an unsized table.
	cat > "$_gs_d/sw.c" <<'D4EOF'
int g[8];
int sw(int c, int x) { switch (c) { case 0: x += g[1]; break; case 1: x ^= g[2]; break; case 2: x -= g[3] * 3; break;
  case 3: x = g[4] << x; break; case 4: x |= g[5]; break; case 5: x = g[6] / (x | 1); break; case 6: x &= g[7]; break;
  default: x = 0; } return x; }
int mp(int *p) { int r; __asm__ volatile ("movepl %1@(0),%0" : "=d" (r) : "a" (p)); return r; }
int main(int c, char **v) { return sw(c, c) + mp(g); }
D4EOF
	$CC $AMIX_ARCH_FLAGS -O2 -o "$_gs_d/sw" "$_gs_d/sw.c" || {
		_gs_fail "switch probe did not link"; return 1; }
	_gs_g14="$AMIX_REPO_ROOT/recipes/common/gcc14/scan060-g14.py"
	OBJDUMP="$OBJDUMP" python3 "$_gs_g14" "$_gs_d/expand" >/dev/null 2>&1 || {
		_gs_fail "scan060-g14.py rejected the $AMIX_ARCH_FLAGS executable"; return 1; }
	if OBJDUMP="$OBJDUMP" python3 "$_gs_g14" "$_gs_d/keep" >/dev/null 2>&1; then
		_gs_fail "scan060-g14.py passed the -m68020 executable"; return 1
	fi
	_gs_out=$(OBJDUMP="$OBJDUMP" python3 "$_gs_g14" "$_gs_d/sw" 2>&1)
	case "$_gs_out" in
	*"HITS "*) ;;
	*) _gs_fail "scan060-g14.py on the movep+switch probe: $_gs_out"; return 1 ;;
	esac
	echo "$_gs_out" | grep 'movep' >/dev/null || {
		_gs_fail "scan060-g14.py did not report the movep: $_gs_out"; return 1; }
	echo "$_gs_out" | grep -E '\(([1-9][0-9]*) insns, ([1-9][0-9]*) switch tables sized' >/dev/null || {
		_gs_fail "scan060-g14.py sized no switch table in the probe: $_gs_out"; return 1; }
	echo "  D4 selftest ok (gcc14: -m68020 probes rejected by all three scanners; $AMIX_ARCH_FLAGS probes clean;"
	echo "                  scan060-g14.py sizes a switch table and catches a movep)"
	AMIX_D4_SELFTESTED=1
	unset _gs_d _gs_sum _gs_f _gs_g14 _gs_out
	return 0
}

# --- TOOLCHAIN=gcc14 gates ---------------------------------------------------
# Run by amix_gate_060_tree (so by every amix_pkgroll) on each linked m68k
# executable in the payload when AMIX_TOOLCHAIN=gcc14.  gcc14-env.sh says why
# each exists.

# amix_gate_g14_needed <elf> -- the dynamic section a box can load: interpreter
# /usr/lib/libc.so.1; every DT_NEEDED either /usr/lib/libc.so.1 (libc's own
# SONAME, which every stock binary records) or a BARE name the guest resolves
# from its own /usr/lib (libsocket.so, libnsl.so) -- never a host path; no
# RPATH/RUNPATH; no TEXTREL.
amix_gate_g14_needed() {
	_gn_f="$1"; _gn_bad=0
	_gn_dyn=$("$READELF" -d "$_gn_f" 2>/dev/null)
	_gn_interp=$("$READELF" -l "$_gn_f" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')
	[ "$_gn_interp" = /usr/lib/libc.so.1 ] || {
		echo "  NEEDED FAIL $_gn_f -- interpreter '$_gn_interp'" >&2; _gn_bad=1; }
	_gn_list=$(echo "$_gn_dyn" | sed -n 's/.*(NEEDED).*\[\([^]]*\)\].*/\1/p')
	for _gn_n in $_gn_list; do
		case "$_gn_n" in
		/usr/lib/libc.so.1) ;;
		*/*) echo "  NEEDED FAIL $_gn_f -- '$_gn_n' is a path, not a bare name" >&2; _gn_bad=1 ;;
		esac
	done
	if echo "$_gn_dyn" | grep -E '\((RPATH|RUNPATH|TEXTREL)\)' >/dev/null; then
		echo "  NEEDED FAIL $_gn_f -- RPATH/RUNPATH/TEXTREL present" >&2; _gn_bad=1
	fi
	[ $_gn_bad -ne 0 ] || echo "  NEEDED ok  $(basename "$_gn_f"): interp /usr/lib/libc.so.1, NEEDED $(echo $_gn_list)"
	unset _gn_f _gn_dyn _gn_interp _gn_list _gn_n
	return $_gn_bad
}

# amix_gate_g14_llprintf <elf> -- the 64-bit printf caveat.  AMIX libc's
# printf family reads ll as l; only libamixc99's snprintf/vsnprintf are right.
# A binary that imports printf/fprintf/vprintf/vfprintf/vsprintf/_doprnt AND
# carries an ll/j/q/L integer conversion in its strings fails, unless the
# recipe has reviewed the sites and says why in AMIX_LL_PRINTF_REVIEWED.
# sprintf is not in that list: libamixc99's own vsnprintf imports libc sprintf
# to format single conversions it has already split off (never an ll one), so
# its presence proves nothing; with ll strings present it is reported for a
# human to check that no ll conversion reaches libc sprintf directly.
amix_gate_g14_llprintf() {
	_gl_f="$1"
	_gl_all=$( { "$NM" -D -u "$_gl_f" 2>/dev/null; "$NM" -u "$_gl_f" 2>/dev/null; } | awk '{print $NF}' | sort -u)
	_gl_imp=$(echo "$_gl_all" | grep -xE '_?(printf|fprintf|vprintf|vfprintf|vsprintf|_doprnt)' | tr '\n' ' ')
	_gl_spr=$(echo "$_gl_all" | grep -xE '_?sprintf' | tr '\n' ' ')
	_gl_fmt=$(LC_ALL=C strings -a "$_gl_f" | grep -E "%[-+ #0'0-9.*]*(ll|j|q|L)[diouxX]" | sort -u)
	_gl_rc=0
	if [ -z "$_gl_fmt" ]; then
		echo "  LLPRINTF ok  $(basename "$_gl_f"): no ll/j/q/L integer conversion in its strings"
	elif [ -n "$_gl_imp" ] && [ -z "$AMIX_LL_PRINTF_REVIEWED" ]; then
		echo "  LLPRINTF FAIL $_gl_f -- imports $_gl_imp and carries 64-bit conversions:" >&2
		echo "$_gl_fmt" | sed 's/^/          /' >&2
		echo "          libc printf prints ll as l; route them through snprintf, or" >&2
		echo "          set AMIX_LL_PRINTF_REVIEWED='<why it is safe>' in the recipe." >&2
		_gl_rc=1
	elif [ -n "$_gl_imp" ]; then
		echo "  LLPRINTF reviewed $(basename "$_gl_f"): $AMIX_LL_PRINTF_REVIEWED"
	elif [ -n "$_gl_spr" ]; then
		echo "  LLPRINTF note $(basename "$_gl_f"): 64-bit conversions present and libc sprintf imported"
		echo "           (libamixc99 uses it for single non-ll conversions); review that no ll"
		echo "           conversion reaches libc sprintf directly:"
		echo "$_gl_fmt" | sed 's/^/             /'
	else
		echo "  LLPRINTF ok  $(basename "$_gl_f"): 64-bit conversions present, no libc printf-family import"
	fi
	unset _gl_f _gl_all _gl_imp _gl_spr _gl_fmt
	return $_gl_rc
}

# amix_gate_g14_fpu <elf|archive> -- the FPU gate.  FAILS on any 68040/68060-only
# FPU form: fsmove/fdmove, fsadd/fdadd, fssub/fdsub, fsmul/fdmul, fsdiv/fddiv,
# fssqrt/fdsqrt, fsabs/fdabs, fsneg/fdneg (single/double-rounding variants).
# A 68881/68882 does not have them: on the 030 golden row (68030 + 68882,
# stock 2.1c kernel) the first one kills the process with SIGSYS ("Bad System
# Call", PHASE2 2026-10-25, gcc14 make built -mcpu=68060).  -m68020-60 keeps
# them out of compiled code; the toolchain runtime (libgcc, libamixc99) built
# --with-cpu=68060 still carries them, so a binary that links such a member
# fails here and the gate names the symbol it sits in.  Then it counts the
# FPU instructions (informational): a nonzero count means the binary needs a
# 68881/2 or an 040/060 FPU (not an LC part without the kernel's FPE).
amix_gate_g14_fpu() {
	_gf_bad=$("$OBJDUMP" -d "$1" 2>/dev/null | awk -F'\t' '
		/^[0-9a-f]+ <.*>:$/ { fn = $0; sub(/^[0-9a-f]+ /, "", fn); sub(/:$/, "", fn) }
		/^In archive / { mem = "" }
		/:     file format / { mem = $0; sub(/:.*/, "", mem); sub(/.*\//, "", mem) }
		NF >= 3 { split($3, a, " ");
			if (a[1] ~ /^f[sd](move|add|sub|mul|div|sqrt|abs|neg)[bwlsdxp]?$/)
				printf "%s%s %s %s\n", (mem != "" ? mem ":" : ""), fn, $1, $3 }')
	if [ -n "$_gf_bad" ]; then
		echo "  FPU FAIL $1 -- 68040/68060-only FPU forms (a 68881/68882 lacks them):" >&2
		# a stripped executable has no .symtab: objdump labels code by the
		# nearest DYNAMIC symbol, which is not the function the code is in
		"$READELF" -S "$1" 2>/dev/null | grep -q "\.symtab" || echo "          (stripped: the labels are the nearest dynamic symbols; read the unstripped build for the function)" >&2
		echo "$_gf_bad" | awk '{c[$1]++; if (!($1 in ex)) ex[$1] = $3 " " $4}
			END {for (s in c) printf "          %-40s %3d  e.g. %s\n", s, c[s], ex[s]}' | sort >&2
		unset _gf_bad
		return 1
	fi
	_gf_n=$("$OBJDUMP" -d "$1" 2>/dev/null | awk -F'\t' 'NF >= 3 && $3 ~ /^f/ && $3 != "ff1" {n++} END {print n + 0}')
	if [ "$_gf_n" -eq 0 ]; then
		echo "  FPU      $(basename "$1"): 0 FPU instructions (runs without an FPU), no 040/060-only form"
	else
		echo "  FPU      $(basename "$1"): $_gf_n FPU instructions, none 040/060-only -- NEEDS an FPU (68881/2, 040, 060)"
	fi
	unset _gf_n _gf_bad
	return 0
}

# amix_gate_g14_strict <makelog> -- the gcc14 build ran with the strict
# flags: no -Wno-error from configure's lenient run reached a compile line.
amix_gate_g14_strict() {
	if grep -- '-Wno-error' "$1" >/dev/null 2>&1; then
		echo "[FAIL] a -Wno-error flag reached the gcc14 build (configure-only leniency leaked):" >&2
		grep -- '-Wno-error' "$1" | head -3 >&2
		return 1
	fi
	echo "  STRICT ok  no -Wno-error on any compile line (configure-only leniency did not leak)"
	return 0
}

# amix_gate_g14_compat <makelog> -- one owner per compat symbol: libacompat is
# never on a gcc14 link line (libamixc99 owns the overlap; gcc14-env.sh).
amix_gate_g14_compat() {
	if grep -E -- '-lacompat|libacompat' "$1" >/dev/null 2>&1; then
		echo "[FAIL] gcc14 build links libacompat -- libamixc99 owns snprintf/strcasecmp/usleep here" >&2
		return 1
	fi
	echo "  COMPAT ok  libacompat not linked; snprintf/strcasecmp/usleep from libamixc99"
	return 0
}

# amix_gate_elf <file...> -- the artifact really is an Amix binary.
#
# A cross build that silently fell back to the host compiler produces a working
# x86 ELF and a green build log.  recipes/README.md: "unset, you silently get
# gcc 1.4.2" -- the same class.  Check the machine, not the exit status.
amix_gate_elf() {
	_ge_bad=0
	for _ge_f in "$@"; do
		_ge_d=$(LC_ALL=C file -b "$_ge_f" 2>/dev/null)
		case "$_ge_d" in
		*"ELF 32-bit MSB"*"Motorola m68k"*)
			echo "  ELF ok  $_ge_f -- $_ge_d"
			;;
		*)
			echo "  ELF FAIL $_ge_f is not an m68k SVR4 ELF: $_ge_d" >&2
			_ge_bad=1
			;;
		esac
	done
	unset _ge_f _ge_d
	return $_ge_bad
}

# amix_gate_undef <file> [allowed-extra...] -- every undefined symbol in a
# shipped executable must resolve on the box.
#
# This is the mechanical form of PORTING.md sec 3.1's implicit-declaration trap.
# gcc 2.7 compiles a call to an undeclared snprintf without complaint, the
# linker is happy because the reference is satisfied from libamixcompat, and the
# defect only shows up as a runtime failure on a box nobody wants to debug on.
# Listing the undefined symbols of the final binary makes the libc surface it
# actually depends on reviewable BEFORE it is pushed anywhere.
amix_gate_undef() {
	_gu_f="$1"
	[ -f "$_gu_f" ] || { echo "[FAIL] undef gate: no such file $_gu_f" >&2; return 1; }
	echo "  undefined symbols in $(basename "$_gu_f"):"
	"$NM" -u "$_gu_f" 2>/dev/null | awk '{print $NF}' | sort -u | sed 's/^/          /'
	unset _gu_f
	return 0
}

# amix_gate_noasm <dir> -- no imported assembly reached the build.
#
# In SGS syntax '&' is the immediate prefix and '#' STARTS A COMMENT, so
# `nop #junk` assembles to a bare nop with exit 0 (PORTING.md sec 2.2).  The
# standing rule is that imported .s files and inline asm are banned unless a
# reviewer has read objdump -d.  This gate is how a recipe asserts it imported
# none.
amix_gate_noasm() {
	_gn_d="$1"
	_gn_hits=$(find "$_gn_d" \( -name '*.s' -o -name '*.S' \) -print 2>/dev/null || true)
	if [ -n "$_gn_hits" ]; then
		echo "  ASM WARN assembly sources present under $_gn_d:" >&2
		echo "$_gn_hits" | sed 's/^/          /' >&2
		echo "          Each must be disabled or read through objdump -d by a human." >&2
		unset _gn_d _gn_hits
		return 1
	fi
	echo "  ASM ok  no .s/.S sources under $(basename "$_gn_d")"
	unset _gn_d _gn_hits
	return 0
}
