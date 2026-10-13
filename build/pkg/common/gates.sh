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
amix_scan060() {
	AMIX_OBJDUMP=$(amix_scan060_objdump) "$AMIX_TARGET-scan060" "$@"
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
			if ! _g4_out=$(amix_pm_scan060 "$_g4_e" 2>&1); then
				echo "  D4 FAIL $_g4_e -- amix-packagemanager scan060.py:" >&2
				echo "$_g4_out" | sed 's/^/          /' >&2
				_g4_bad=1
			fi
		done
		# scanner 2, the toolchain's, on the same argument
		if _g4_out=$(amix_scan060 --quiet "$_g4_f" 2>&1); then
			[ $_g4_bad -ne 0 ] || echo "  D4 ok   $_g4_f (no 64-bit mul/div, movep, cmp2/chk2/cas2; all three scanners)"
		else
			echo "  D4 FAIL $_g4_f -- $AMIX_TARGET-scan060:" >&2
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
	_gt_n=$(amix_gate_elfs "$1" | grep -c . || true)
	if [ "$_gt_n" -eq 0 ]; then
		echo "  060 gate: no m68k ELF or archive in the payload (data-only package)"
		unset _gt_n
		return 0
	fi
	echo "  060 gate: $_gt_n m68k ELF/archive file(s) in the payload"
	unset _gt_n
	amix_gate_d4 "$1"
}

# amix_gate_pkg060 <datastream> -- the packagemanager's scanner on the rolled
# .pkg itself (what the catalog serves), run by amix_pkgroll last.
amix_gate_pkg060() {
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
