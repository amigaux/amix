# gcc14-pin.sh -- the gcc14-cross-amix identity: the pinned commit, the
# sha256 of its cc1, libgcc.a, libamixc99.a and specs, and the return-value
# ABI self-check.  Sourced, never executed: by gcc14-env.sh (TOOLCHAIN=gcc14
# recipes) and by dlm-src.sh before it builds amix-dlm's box binaries
# (kbootset, modadmin), which amix-dlm's Makefile links with the toolchain
# prefix directly.  One pin for both: a new toolchain is a re-pin HERE (and a
# re-mint of every gcc14 package and box binary).
#
#     . "$AMIX_REPO_ROOT/recipes/common/gcc14-pin.sh"
#     amix_g14_identity <prefix> || exit 1
#         the prefix's pinned files, then the ABI self-check of its
#         bin/m68k-elf-gcc; prints why and returns 1 on any difference
#
# cf461e3 fixed two return-value ABI defects: pointers come back in %a0 AND
# %d0, and every struct is returned in memory through %a0 (AMIX cc, gcc 2.7
# and libc -- div()/ldiv() -- do both).  Before it, GCC 14 code handed
# garbage pointers to period-compiled callers and read garbage from libc's
# div()/ldiv().  amix_g14_abi_selfcheck re-proves both from the compiler's
# own -S output on every build, so a re-pin can never quietly bring the
# defect back.

case "${0##*/}" in
gcc14-pin.sh)
	echo "[FAIL] gcc14-pin.sh is sourced, not executed" >&2
	exit 1
	;;
esac

# path-in-prefix<SPACE>sha256, at gcc14-cross-amix AMIX_GCC14_COMMIT.
# Re-pinned 2026-10-29 (owner Y3) to the public amigaux/gcc14-cross-amix,
# branch upstream-58130fe-plus at b51ff39: Antti's 58130fe plus the
# m68020-60 runtime fix.  cc1 is unchanged; specs now default to
# -mno-strict-align, and libgcc.a / libamixc99.a were rebuilt under it
# (word-pair stack reads become one move.l).  Compiled objects are
# identical with our flags; linked binaries differ only in runtime members
# (evidence in Amigaux/tmp/2026-10-29-g14-repin/).  The cf461e3 prefix is
# kept as gcc14-cross-amix/build/prefix-cf461e3.
AMIX_GCC14_COMMIT=b51ff39c500adadca629d7caf2a1d20a00fced03
AMIX_GCC14_PINS="\
libexec/gcc/m68k-elf/14.2.0/cc1 9635f67e59103c2867638910849e410d19bfd9c10a1b52093f9e58e515496bff
lib/gcc/m68k-elf/14.2.0/libgcc.a 62d061c006cb5652892fde3ccb095bfc211ddd45c5600e8f65539327db20ddfd
m68k-elf/lib/libamixc99.a fa1e42d4e97bb8b540b9d9ae9d42ebbdeac77f49881e31d6115c93c277dfa601
lib/gcc/m68k-elf/14.2.0/specs 45f4685908f349b6c1a67e010feb8a83a1bdfc7ba7b5960f636ab6c4ffd3de5d"

# amix_g14_pincheck <prefix> -- every pinned file of <prefix> by sha256.
amix_g14_pincheck() {
	_gp_bad=$(echo "$AMIX_GCC14_PINS" | while read _gp_p _gp_want; do
		_gp_got=$(sha256sum "$1/$_gp_p" 2>/dev/null | cut -d' ' -f1)
		[ "$_gp_got" = "$_gp_want" ] || echo "$_gp_p: ${_gp_got:-missing}, pinned $_gp_want"
	done)
	if [ -n "$_gp_bad" ]; then
		echo "[FAIL] TOOLCHAIN=gcc14: $1 is not the pinned toolchain" >&2
		echo "       (gcc14-cross-amix $AMIX_GCC14_COMMIT, gcc14-pin.sh AMIX_GCC14_PINS):" >&2
		echo "$_gp_bad" | sed 's/^/         /' >&2
		unset _gp_bad
		return 1
	fi
	unset _gp_bad
	return 0
}

# amix_g14_abi_selfcheck <cc> -- the return-value ABI, read from <cc>'s own
# -S output: a pointer return must set %a0 and %d0, a struct return (even a
# 4-byte one) must store through %a0.  The pre-cf461e3 compiler fails both.
amix_g14_abi_selfcheck() {
	_ga_s=$(printf 'char *p(char *s){return s+1;}\n' |
		$1 -m68020-60 -O2 -S -o - -x c - 2>&1 | sed -n '/^p:/,/rts/p')
	_ga_t=$(printf 'struct i1 { int a; };\nstruct i1 r(int x){struct i1 v = { x }; return v;}\n' |
		$1 -m68020-60 -O2 -S -o - -x c - 2>&1 | sed -n '/^r:/,/rts/p')
	_ga_rc=0
	case "$_ga_s" in *%a0*) ;; *) _ga_rc=1 ;; esac
	case "$_ga_s" in *%d0*) ;; *) _ga_rc=1 ;; esac
	case "$_ga_t" in *'(%a0)'*) ;; *) _ga_rc=1 ;; esac
	if [ $_ga_rc -ne 0 ]; then
		echo "[FAIL] $1: the return-value ABI is not AMIX's (pointer in %a0 and %d0, struct via (%a0)):" >&2
		printf '%s\n%s\n' "$_ga_s" "$_ga_t" | sed 's/^/         /' >&2
	fi
	unset _ga_s _ga_t
	return $_ga_rc
}

# amix_g14_align_check <cc> <arch flags> <cflags> -- the userland alignment
# flag (owner decision 2026-10-27): every GCC 14 USERLAND compile drops strict
# alignment.  GCC 14's m68k-elf default is strict: it reads an unaligned int
# (and even a stacked pointer argument) a byte or word at a time; on a real
# 68LC060 Dhrystone ran 1.60x faster with -mno-strict-align.  The 68020
# through 68060 all do unaligned data accesses in hardware, and the flag
# changes no layout or calling convention (that is -malign-int, kept).
# Checked here: in both flag sets the LAST alignment option is
# -mno-strict-align, and <cc> <cflags> really compiles an unaligned 4-byte
# load to one move.l (no byte moves).  gcc14-env.sh runs it on every gcc14
# recipe build; amix_gate_g14_strict checks every compile line of a make log.
# Not part of amix_g14_identity: the box builds dlm-src.sh checks are
# kernel-space tooling with their own flags.
amix_g14_align_check() {
	_gal_rc=0
	for _gal_set in "$2" "$3"; do
		_gal_last=$(for _gal_w in $_gal_set; do
			case "$_gal_w" in -mstrict-align|-mno-strict-align) echo "$_gal_w" ;; esac
		done | tail -1)
		[ "$_gal_last" = -mno-strict-align ] || {
			echo "[FAIL] TOOLCHAIN=gcc14: '$_gal_set' does not end with -mno-strict-align" >&2
			echo "       (gcc14-env.sh AMIX_ARCH_FLAGS; owner decision 2026-10-27)" >&2
			_gal_rc=1
		}
	done
	if [ $_gal_rc -eq 0 ]; then
		_gal_s=$(printf 'int u(const char *p){int x; __builtin_memcpy(&x, p + 1, 4); return x;}\n' |
			$1 $3 -S -o - -x c - 2>&1 | sed -n '/^u:/,/rts/p')
		case "$_gal_s" in *'move.l 1(%a0),%d0'*) ;; *) _gal_rc=1 ;; esac
		case "$_gal_s" in *move.b*) _gal_rc=1 ;; esac
		[ $_gal_rc -eq 0 ] || {
			echo "[FAIL] TOOLCHAIN=gcc14: $1 $3 still splits an unaligned load (strict alignment):" >&2
			echo "$_gal_s" | sed 's/^/         /' >&2
		}
	fi
	unset _gal_set _gal_last _gal_w _gal_s
	return $_gal_rc
}

# amix_g14_identity <prefix> -- both: the pins, then the self-check of the
# prefix's own compiler.
amix_g14_identity() {
	amix_g14_pincheck "$1" || return 1
	amix_g14_abi_selfcheck "$1/bin/m68k-elf-gcc" || return 1
}
