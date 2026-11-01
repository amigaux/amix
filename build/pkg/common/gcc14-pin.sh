# gcc14-pin.sh -- the gcc14-cross-amix identity: the pinned commit, the
# sha256 of its cc1, libgcc.a, libamixc99.a, specs, amix_init.o, amix_initS.o
# and libamixrt.so.1, and the return-value
# ABI self-check.  Sourced, never executed: by gcc14-env.sh (TOOLCHAIN=gcc14
# recipes) and by dlm-src.sh before it builds amix-dlm's box binaries
# (kbootset, modadmin), which amix-dlm's Makefile links with the toolchain
# prefix directly.  One pin for both: a new toolchain is a re-pin HERE (and a
# re-mint of every gcc14 package and box binary).
#
#     . "$AMIX_PKG_COMMON/gcc14-pin.sh"
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
# Re-pinned 2026-10-30 to the build container's gcc14:
# toolchain/Containerfile builds the pin reproducibly, with the sysroot inside
# the prefix, and toolchain/gcc14-cross-amix.tree pins the whole tree.
# f40055b (2026-10-31; the public amigaux/gcc14-cross-amix, branch
# upstream-58130fe-plus) adds `gcc -shared`, libamixc99's __cxa_finalize for
# shared libraries, and library constructors run after the program's
# start-up: libamixc99.a and the specs change, cc1 and libgcc.a do not.
# feec32e (2026-11-01) patches gas to keep a PIC relocation against an
# exported symbol instead of folding it into its section: only the
# assembler changes, none of the four files pinned here.
# 3446533 (2026-11-01) adds libamixrt.so.1, the runtime a shared library
# NEEDs, run-after-start-up library constructors in amix_init.o (last in,
# first out) and amix_initS.o for -shared: the specs, libamixc99.a and both
# init objects change and libamixrt.so.1 is pinned too; cc1 and libgcc.a do
# not change.
# toolchain/extract-g14.sh puts it on the host, where it builds the same
# bytes as in the container. The earlier pin was a workstation build of the
# same commit; these four files differ from it by how they were built (see
# toolchain/README.md), not by source.
AMIX_GCC14_COMMIT=34465331d3ccdf4a320f684736b5df032971c206
AMIX_GCC14_PINS="\
libexec/gcc/m68k-elf/14.2.0/cc1 ff4241a6de847b321985f0dfe80d00f20d485f85cd4f947ee593836a96009182
lib/gcc/m68k-elf/14.2.0/libgcc.a bb531a7db3c28351864a4ceb6dbbc6785a4dddd75d985ad35050543be2d8244f
m68k-elf/lib/libamixc99.a 591306dca7eafd580e024f347124b5d6eb5d90537662f6f0e31c9ee9f5b768fe
lib/gcc/m68k-elf/14.2.0/specs d2f36ec2d67912727d5791b7912f690651fc68e4abbc9250532fa37c24d97398
m68k-elf/lib/amix_init.o 79c2de7fcd7fa7f8f9eb1dcbf5716558f81f3c8edeb5db554000217a69f8789e
m68k-elf/lib/amix_initS.o 22bfff2dd56bc7c2abe63e56ce9235731a6e5abddf54f0d8a79a0a6b1bc8fd26
m68k-elf/lib/amixrt/libamixrt.so.1 7d7c647e2737c7998711d5e90b314e048ebae3140cc5d4d9b816660680dd5880"

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
# flag: every GCC 14 USERLAND compile drops strict
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
			echo "       (gcc14-env.sh AMIX_ARCH_FLAGS)" >&2
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
