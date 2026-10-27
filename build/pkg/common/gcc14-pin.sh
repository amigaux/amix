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
AMIX_GCC14_COMMIT=cf461e38993100533fa6efe509ad0cbd2a735eea
AMIX_GCC14_PINS="\
libexec/gcc/m68k-elf/14.2.0/cc1 d4933e78be410d80a9e216af5ca52ee7db4e9810d36a324513c7a98f988aa57a
lib/gcc/m68k-elf/14.2.0/libgcc.a 5d81450797fbf1ada217e86a5b643d159ef79c3396274a67e016bb5c5388867f
m68k-elf/lib/libamixc99.a c73ccc172ce9dd23d818c3f0f71ae5724a3e946fa9d826d8e8e98b9266bf2ce3
lib/gcc/m68k-elf/14.2.0/specs 93f9574f191ca0074b8af25cbfc910bc5f608392586f2246d6af4ca9a2281f13"

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

# amix_g14_identity <prefix> -- both: the pins, then the self-check of the
# prefix's own compiler.
amix_g14_identity() {
	amix_g14_pincheck "$1" || return 1
	amix_g14_abi_selfcheck "$1/bin/m68k-elf-gcc" || return 1
}
