#!/bin/sh
#
# gate-gcc14-selftest.sh -- prove the TOOLCHAIN=gcc14 gates can FAIL.
#
#     sh tools/gate-gcc14-selftest.sh
#
# The gcc14 counterpart of tools/gate060-selftest.sh (which stays the period
# toolchain's).  Builds small probes with gcc14-cross-amix and checks that:
#   - the 68060 gate (awk scanner, check-68060-safe.py, scan060-g14.py with
#     scan060.py cross-examined) rejects -m68020 code -- a 64-bit multiply in
#     an executable, an archive and their directory -- and passes the same
#     source built with the recipe flags;
#   - amix_pkgroll refuses an unsafe payload, and the datastream gate alone
#     (tree gate stubbed out) refuses and removes the .pkg;
#   - the NEEDED gate rejects a host path in DT_NEEDED;
#   - the ll-printf gate rejects printf("%lld") and accepts it once reviewed;
#   - the FPU gate rejects the 040/060-only FPU forms -mcpu=68060 emits (an
#     executable, an archive, and amix_pkgroll's payload) and passes the same
#     source built with the recipe flags (-m68020-60);
#   - scan060-g14.py sizes a switch table dispatched through %a6 (objdump's
#     %fp; GCC 14 -O2 uses it as a general register) and one bound-checked
#     against a memory operand, instead of reading them as code, and still
#     reports a real movep after either;
#   - amix-env.sh refuses gcc14 for a recipe that has not opted in;
#   - the toolchain pin refuses a prefix that is not cf461e3's, and the
#     return-value ABI self-check (pointer in %a0 and %d0, struct via %a0)
#     passes the pinned compiler and rejects the pre-fix one;
#   - dlm-src.sh's check before amix-dlm's box builds (kbootset, modadmin)
#     uses the same pins: it refuses that prefix and passes the real one.
# Exit 0 only if every check holds.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
export AMIX_PREFIX=/opt/amix

T=$(mktemp -d "${TMPDIR:-/tmp}/gate-g14.XXXXXX")
trap 'rm -rf "$T"' EXIT

fail() { echo "gate-gcc14-selftest: FAIL -- $*" >&2; exit 1; }
n=0
ok() { n=$((n + 1)); echo "  ok $n  $*"; }

if (TOOLCHAIN=gcc14; export TOOLCHAIN; unset AMIX_RECIPE_TOOLCHAINS; . "$REPO/recipes/common/amix-env.sh") >/dev/null 2>&1; then
	fail "amix-env.sh accepted TOOLCHAIN=gcc14 for a recipe that did not opt in"
fi
ok "amix-env.sh refuses gcc14 unless the recipe declares it"

TOOLCHAIN=gcc14
AMIX_RECIPE_TOOLCHAINS="period gcc14"
export TOOLCHAIN
. "$REPO/recipes/common/amix-env.sh"
. "$REPO/recipes/common/gates.sh"
. "$REPO/recipes/common/pkgroll.sh"
[ "$AMIX_TOOLCHAIN" = gcc14 ] || fail "AMIX_TOOLCHAIN is '$AMIX_TOOLCHAIN'"
ok "amix-env.sh selected gcc14: $AMIX_GCC14_CC, sysroot $AMIX_SYSROOT"

amix_gate_d4_selftest "$T/st" || fail "amix_gate_d4_selftest"
ok "amix_gate_d4_selftest (gcc14)"

cat > "$T/prog.c" <<'EOF'
long long bad(long a, long *p) { return (long long)a * *p; }
unsigned imm(unsigned x) { return x / 10; }
int main(int argc, char **argv) { long v = argc; return (int)(bad(argc, &v) + imm(argc)); }
EOF
cat > "$T/lib.c" <<'EOF'
unsigned per_mille(unsigned x) { return x % 1000; }
EOF
build() {	# build <cpu flags> <dir>
	mkdir -p "$2"
	$CC $1 -O2 -o "$2/prog" "$T/prog.c"
	$CC $1 -O2 -c "$T/lib.c" -o "$2/lib.o"
	"$AR" rc "$2/liblib.a" "$2/lib.o"; rm -f "$2/lib.o"
}
build -m68020 "$T/keep"
build "$AMIX_ARCH_FLAGS" "$T/expand"

for f in "$T/keep/prog" "$T/keep/liblib.a" "$T/keep"; do
	if amix_gate_d4 "$f" >/dev/null 2>&1; then fail "amix_gate_d4 passed $f"; fi
done
ok "amix_gate_d4 rejects a -m68020 executable, archive, and their directory"
for f in "$T/expand/prog" "$T/expand/liblib.a" "$T/expand"; do
	amix_gate_d4 "$f" >/dev/null 2>&1 || fail "amix_gate_d4 rejected $f"
done
ok "amix_gate_d4 passes the $AMIX_ARCH_FLAGS executable, archive and directory"

roll() {	# roll <tag> <payload-dir>
	w="$T/roll-$1"; r="$T/root-$1"
	mkdir -p "$w" "$r/opt/amix/bin" "$r/opt/amix/lib"
	cp "$2/prog" "$r/opt/amix/bin/prog"
	cp "$2/liblib.a" "$r/opt/amix/lib/liblib.a"
	printf 'PKG=g14t\nNAME=gate test\nARCH=Amiga\nVERSION=1\nCATEGORY=test\nCLASSES=none\nPSTAMP=gate14\n' > "$w/pkginfo"
	printf 'i pkginfo\nd none /opt 0755 root sys\nd none /opt/amix 0755 root sys\nd none /opt/amix/bin 0755 root sys\nd none /opt/amix/lib 0755 root sys\nf none /opt/amix/bin/prog 0755 root sys\nf none /opt/amix/lib/liblib.a 0644 root sys\n' > "$w/prototype"
	( amix_pkgroll "$w" "$r" g14t 1 "$T/out-$1.pkg" ) > "$T/roll-$1.log" 2>&1
}
if roll keep "$T/keep"; then fail "amix_pkgroll rolled a payload with 64-bit multiplies"; fi
[ ! -f "$T/out-keep.pkg" ] || fail "amix_pkgroll left a datastream for the unsafe payload"
grep '68060 gate' "$T/roll-keep.log" >/dev/null || fail "amix_pkgroll failed, but not at the 68060 gate"
ok "amix_pkgroll refuses the -m68020 payload, no datastream written"

if ( amix_gate_060_tree() { return 0; }; roll dsonly "$T/keep" ); then
	fail "the gcc14 datastream gate passed a .pkg with 64-bit multiplies"
fi
[ ! -f "$T/out-dsonly.pkg" ] || fail "the datastream gate left the unsafe .pkg behind"
grep '060 FAIL datastream\|68060 gate' "$T/roll-dsonly.log" >/dev/null || fail "dsonly roll failed, but not at the datastream gate"
ok "with the tree gate stubbed, the gcc14 datastream gate refuses and removes the .pkg"

roll expand "$T/expand" || { cat "$T/roll-expand.log" >&2; fail "amix_pkgroll refused the safe payload"; }
[ -f "$T/out-expand.pkg" ] || fail "amix_pkgroll wrote no datastream for the safe payload"
ok "amix_pkgroll rolls the $AMIX_ARCH_FLAGS payload"

# NEEDED: a library named by its host path records that path (libnsl.so has
# no SONAME) -- the apkg 0.1 trap; -lnsl records the bare name.
printf 'char *inet_ntoa(); int main(void) { return inet_ntoa == 0; }\n' > "$T/nsl.c"
$CC $AMIX_CFLAGS -o "$T/nsl-path" "$T/nsl.c" "$AMIX_SYSROOT/usr/lib/libnsl.so" 2>/dev/null
$CC $AMIX_CFLAGS -o "$T/nsl-bare" "$T/nsl.c" -lnsl 2>/dev/null
if amix_gate_g14_needed "$T/nsl-path" >/dev/null 2>&1; then fail "NEEDED gate passed a host-path DT_NEEDED"; fi
amix_gate_g14_needed "$T/nsl-bare" >/dev/null 2>&1 || fail "NEEDED gate rejected bare libnsl.so"
ok "NEEDED gate rejects a host path, passes the bare name"

# ll printf: libc printf prints ll as l.
printf '#include <stdio.h>\nint main(int c, char **v) { printf("%%lld\\n", (long long)c); return 0; }\n' > "$T/ll.c"
printf '#include <stdio.h>\nint main(int c, char **v) { char b[32]; snprintf(b, sizeof b, "%%lld", (long long)c); puts(b); return 0; }\n' > "$T/llsn.c"
$CC $AMIX_CFLAGS -o "$T/ll" "$T/ll.c"
$CC $AMIX_CFLAGS -o "$T/llsn" "$T/llsn.c"
if amix_gate_g14_llprintf "$T/ll" >/dev/null 2>&1; then fail "ll-printf gate passed printf(\"%lld\")"; fi
AMIX_LL_PRINTF_REVIEWED="selftest" amix_gate_g14_llprintf "$T/ll" >/dev/null 2>&1 || fail "ll-printf gate ignored AMIX_LL_PRINTF_REVIEWED"
amix_gate_g14_llprintf "$T/llsn" >/dev/null 2>&1 || fail "ll-printf gate rejected snprintf-only use"
ok "ll-printf gate rejects printf(\"%lld\"), honours a review, passes snprintf-only"

# FPU: -mcpu=68060 emits fdmul/fdadd for double arithmetic, which a
# 68881/68882 lacks (SIGSYS on the 030 golden row); the recipe flags do not.
printf 'double fma2(double a, double b) { return a * b + a; }\nint main(int c, char **v) { return (int)fma2(c, 1.5); }\n' > "$T/fp.c"
mkdir -p "$T/fp060" "$T/fpok"
$CC -mcpu=68060 -O2 -o "$T/fp060/prog" "$T/fp.c"
$CC -mcpu=68060 -O2 -c "$T/fp.c" -o "$T/fp060/fp.o"; "$AR" rc "$T/fp060/libfp.a" "$T/fp060/fp.o"; rm -f "$T/fp060/fp.o"
$CC $AMIX_ARCH_FLAGS -O2 -o "$T/fpok/prog" "$T/fp.c"
$CC $AMIX_ARCH_FLAGS -O2 -c "$T/fp.c" -o "$T/fpok/fp.o"; "$AR" rc "$T/fpok/libfp.a" "$T/fpok/fp.o"; rm -f "$T/fpok/fp.o"
for f in "$T/fp060/prog" "$T/fp060/libfp.a"; do
	if amix_gate_g14_fpu "$f" >/dev/null 2>&1; then fail "FPU gate passed the -mcpu=68060 $f"; fi
done
amix_gate_g14_fpu "$T/fp060/prog" 2>&1 | grep -q '<fma2>' || fail "FPU gate did not name the symbol (fma2)"
for f in "$T/fpok/prog" "$T/fpok/libfp.a"; do
	amix_gate_g14_fpu "$f" >/dev/null 2>&1 || fail "FPU gate rejected the $AMIX_ARCH_FLAGS $f"
done
ok "FPU gate rejects -mcpu=68060 fd*/fs* forms (executable, archive; names <fma2>), passes $AMIX_ARCH_FLAGS"
cp "$T/fp060/libfp.a" "$T/fp060/liblib.a"
if roll fp060 "$T/fp060"; then fail "amix_pkgroll rolled a payload with 040/060-only FPU forms"; fi
[ ! -f "$T/out-fp060.pkg" ] || fail "amix_pkgroll left a datastream for the fd*-form payload"
grep 'FPU FAIL' "$T/roll-fp060.log" >/dev/null || fail "amix_pkgroll failed, but not at the FPU gate"
ok "amix_pkgroll refuses a payload with 040/060-only FPU forms, no datastream written"

# scan060-g14.py: two switch shapes GCC 14 emitted that the first version of
# the tool could not read (2026-10-27).  The dispatch words and tables are
# copied from the real binaries; entry #0 (0x074c 0x0056) decodes as
# movepl %a4@(86),%d3 when the table is read as code.
#   fp   indexed through %a6, which objdump names %fp (patch 2.5.9 quotearg):
#        the table was not recognised at all and read as a movep;
#   mem  bound-checked against a MEMORY operand, `moveq #3,%d1; cmpl sw_sel,%d1;
#        bcs' (tar 1.14 main/start_header): the table was left unsized.
sw_probe() {	# sw_probe <name> fp|mem <extra asm string or empty>
	{
		printf '%s\n' 'int sw_sel;'
		printf '%s\n' '__asm__(".text\n.globl swp\n.type swp,@function\nswp:\n"'
		if [ "$2" = fp ]; then
			printf '%s\n' '	"\tmove.l 4(%sp),%d1\n\tmove.l %a6,-(%sp)\n"'
			printf '%s\n' '	"\tcmp.b #3,%d1\n\tbhi.w 9f\n"'
			printf '%s\n' '	"\tclr.l %d0\n\tmove.b %d1,%d0\n\tadd.l %d0,%d0\n\tmove.l %d0,%a6\n"'
			printf '%s\n' '	"\t.word 0x3c7b,0xe806\n"'	# moveaw %pc@(T,%a6:l),%a6
			printf '%s\n' '	"\t.word 0x4efb,0xe002\n"'	# jmp %pc@(T,%a6:w)
		else
			printf '%s\n' '	"\tmove.l %a6,-(%sp)\n"'
			printf '%s\n' '	"\tmoveq #3,%d1\n\tcmp.l sw_sel,%d1\n\tbcs.w 9f\n"'
			printf '%s\n' '	"\tmove.l sw_sel,%d0\n\tadd.l %d0,%d0\n"'
			printf '%s\n' '	"\t.word 0x303b,0x0806\n"'	# movew %pc@(T,%d0:l),%d0
			printf '%s\n' '	"\t.word 0x4efb,0x0002\n"'	# jmp %pc@(T,%d0:w)
		fi
		printf '%s\n' '	"\t.word 0x074c,0x0056,0x0056,0x0056\n"'
		[ -z "$3" ] || printf '\t%s\n' "$3"
		printf '%s\n' '	"\t.fill 0x400,2,0x4e71\n"'
		printf '%s\n' '	"9:\tmove.l (%sp)+,%a6\n\trts\n.size swp,.-swp\n");'
		printf '%s\n' 'int swp(int);'
		printf '%s\n' 'int main(int c, char **v) { sw_sel = c; return swp(c); }'
	} > "$T/$1.c"
	$CC $AMIX_CFLAGS -o "$T/$1" "$T/$1.c" || fail "the switch probe $1 did not build"
}
G14S="$REPO/recipes/common/gcc14/scan060-g14.py"
for shape in fp mem; do
	sw_probe "sw-$shape" "$shape" ''
	sw_probe "sw-$shape-movep" "$shape" '"\t.word 0x074c,0x0056\n"'
	out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-$shape") || fail "scan060-g14.py on the $shape switch: $out"
	echo "$out" | grep ' 1 switch tables sized' >/dev/null || fail "scan060-g14.py did not size the $shape table: $out"
	if out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-$shape-movep"); then
		fail "scan060-g14.py passed a real movep after the $shape table: $out"
	fi
	echo "$out" | grep 'HITS 1 .*1 switch tables sized' >/dev/null || fail "scan060-g14.py on the $shape movep probe: $out"
done
ok "scan060-g14.py sizes %fp-indexed and memory-bounded switch tables, still catches a real movep after each"

# The toolchain identity (gcc14-env.sh): a prefix whose specs differ from the
# pin by one byte is refused before anything builds; the return-value ABI
# self-check passes the pinned compiler.  Where gcc14-cross-amix still keeps
# the pre-fix control prefix (build/prefix-e316f1b: pointers in %d0 only,
# small structs in registers), the self-check must reject that compiler too.
FP="$T/fakeprefix"
cp -as "$AMIX_GCC14_PREFIX" "$FP"
rm "$FP/lib/gcc/m68k-elf/14.2.0/specs"
{ cat "$AMIX_GCC14_PREFIX/lib/gcc/m68k-elf/14.2.0/specs"; echo; } > "$FP/lib/gcc/m68k-elf/14.2.0/specs"
if (AMIX_GCC14_PREFIX="$FP"; export AMIX_GCC14_PREFIX; . "$REPO/recipes/common/amix-env.sh") > "$T/pin.log" 2>&1; then
	fail "amix-env.sh accepted a prefix whose specs differ from the pin"
fi
grep 'not the pinned toolchain' "$T/pin.log" >/dev/null && grep 'specs:' "$T/pin.log" >/dev/null ||
	{ cat "$T/pin.log" >&2; fail "the pin refusal does not name specs"; }
amix_g14_abi_selfcheck "$AMIX_GCC14_CC" >/dev/null 2>&1 || fail "the ABI self-check rejected the pinned compiler"
OLDCC="$AMIX_GCC14_ROOT/build/prefix-e316f1b/bin/m68k-elf-gcc"
if [ -x "$OLDCC" ]; then
	if amix_g14_abi_selfcheck "$OLDCC" >/dev/null 2>&1; then fail "the ABI self-check passed the e316f1b compiler"; fi
	ok "toolchain pin refuses a one-byte specs change; ABI self-check passes cf461e3, rejects e316f1b"
else
	ok "toolchain pin refuses a one-byte specs change; ABI self-check passes cf461e3 (no e316f1b control prefix to reject)"
fi

# The same identity guards amix-dlm's box binaries (kbootset, modadmin), which
# its Makefile links with the prefix directly: dlm-src.sh's check refuses a
# build dir whose prefix is the one-byte-specs copy, and passes the real one.
mkdir -p "$T/fakebuild"; ln -s "$FP" "$T/fakebuild/prefix"; ln -s "$AMIX_GCC14_ROOT/build/sysroot" "$T/fakebuild/sysroot"
if (AMIX_G14_BUILD="$T/fakebuild"; . "$REPO/recipes/common/dlm-src.sh"; amix_dlm_g14_check) > "$T/dlmpin.log" 2>&1; then
	fail "dlm-src.sh's box check accepted a prefix whose specs differ from the pin"
fi
grep 'not the pinned toolchain' "$T/dlmpin.log" >/dev/null && grep 'specs:' "$T/dlmpin.log" >/dev/null ||
	{ cat "$T/dlmpin.log" >&2; fail "dlm-src.sh's refusal does not name specs"; }
(AMIX_G14_BUILD="$AMIX_GCC14_ROOT/build"; . "$REPO/recipes/common/dlm-src.sh"; amix_dlm_g14_check) > "$T/dlmpin-ok.log" 2>&1 ||
	{ cat "$T/dlmpin-ok.log" >&2; fail "dlm-src.sh's box check refused the pinned toolchain"; }
ok "dlm-src.sh's box-build check (kbootset, modadmin) refuses the one-byte specs change, passes cf461e3"

echo "gate-gcc14-selftest: PASS ($n checks)"
