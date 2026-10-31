#!/bin/sh
#
# gate-gcc14-selftest.sh -- prove the TOOLCHAIN=gcc14 gates can FAIL.
#
#     sh build/pkg/tests/gate-gcc14-selftest.sh
#
# The gcc14 counterpart of gate060-selftest.sh (which stays the period
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
#   - scan060-g14.py sizes the mask-, entry- and compare-interleaved-bounded
#     switch tables of perl 5.8.9, and still catches a movep after each
#   - scan060-g14.py sizes a switch table dispatched through %a6 (objdump's
#     %fp; GCC 14 -O2 uses it as a general register) and one bound-checked
#     against a memory operand, instead of reading them as code, and still
#     reports a real movep after either;
#   - amix-env.sh refuses gcc14 for a recipe that has not opted in;
#   - the toolchain pin refuses a prefix that is not the pinned one, and the
#     return-value ABI self-check (pointer in %a0 and %d0, struct via %a0)
#     passes the pinned compiler and rejects the pre-fix one;
#   - dlm-src.sh's check before amix-dlm's box builds (kbootset, modadmin)
#     uses the same pins: it refuses that prefix and passes the real one;
#   - -mno-strict-align (owner decision 2026-10-27) is enforced: amix-env.sh
#     refuses flags without it or ending in -mstrict-align, the -S probe
#     rejects a compiler that still splits an unaligned load, and
#     amix_gate_g14_strict rejects make-log compile lines without it.
# Exit 0 only if every check holds.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
AMIX_TOP=$(cd "$HERE/../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1793303717}	# the roll stamps every time with it
export AMIX_PREFIX=/opt/amix

T=$(mktemp -d "${TMPDIR:-/tmp}/gate-g14.XXXXXX")
trap 'rm -rf "$T"' EXIT

fail() { echo "gate-gcc14-selftest: FAIL -- $*" >&2; exit 1; }
n=0
ok() { n=$((n + 1)); echo "  ok $n  $*"; }

if (TOOLCHAIN=gcc14; export TOOLCHAIN; unset AMIX_RECIPE_TOOLCHAINS; . "$AMIX_PKG_COMMON/amix-env.sh") >/dev/null 2>&1; then
	fail "amix-env.sh accepted TOOLCHAIN=gcc14 for a recipe that did not opt in"
fi
ok "amix-env.sh refuses gcc14 unless the recipe declares it"

TOOLCHAIN=gcc14
AMIX_RECIPE_TOOLCHAINS="period gcc14"
export TOOLCHAIN
. "$AMIX_PKG_COMMON/amix-env.sh"
. "$AMIX_PKG_COMMON/gates.sh"
. "$AMIX_PKG_COMMON/pkgroll.sh"
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
#   bias the bound check on the index before a bias is added (vim 9.1):
#        `movel %d1,%d0; addql #4,%d0; moveq #-4,%d2; cmpl %d1,%d2; bhi',
#        so d1 in [-4,-1] indexes 4 entries;
#   const a constant index, `moveq #2,%d0' (vim 9.1, a switch GCC knew the
#        value of): sized from its own entries, a NOTE;
#   badbias the bias added into another register than the index: unsized.
# And the index without a bound check (python 3.11, 2026-10-31):
#   bf    `bfextu 8(%sp){#2:#3},%d0 ; andil #255,%d0': exactly 8 entries;
#   bfreg the width in a register: unsized;
#   mask  `andil #255,%d0' only, 4 entries then an odd word: sized from
#         its own entries, trusted by shape (a NOTE);
#   load  `moveq #0,%d0 ; moveb 11(%sp),%d0', the same;
#   sload `moveb 11(%sp),%d0', no zero-extension: unsized;
#   zero  the mask, but the first table word is odd: no run, unsized;
#   cmpmask `cmpb #7,%d0 ; bhi' and the mask: the compare's 8 entries
#         stand, the four that do not land are reported;
#   twolevel the offsets loaded from another table, `movew @(swt,%d0:l:2)':
#         refused even with a bound check.
sw_probe() {	# sw_probe <name> <shape: fp mem bias const badbias bf bfreg mask load sload zero cmpmask twolevel> <extra asm string or empty>
	{
		printf '%s\n' 'int sw_sel;'
		printf '%s\n' '__asm__(".text\n.globl swp\n.type swp,@function\nswp:\n"'
		if [ "$2" = fp ]; then
			printf '%s\n' '	"\tmove.l 4(%sp),%d1\n\tmove.l %a6,-(%sp)\n"'
			printf '%s\n' '	"\tcmp.b #3,%d1\n\tbhi.w 9f\n"'
			printf '%s\n' '	"\tclr.l %d0\n\tmove.b %d1,%d0\n\tadd.l %d0,%d0\n\tmove.l %d0,%a6\n"'
			printf '%s\n' '	"\t.word 0x3c7b,0xe806\n"'	# moveaw %pc@(T,%a6:l),%a6
			printf '%s\n' '	"\t.word 0x4efb,0xe002\n"'	# jmp %pc@(T,%a6:w)
		elif [ "$2" = mem ]; then
			printf '%s\n' '	"\tmove.l %a6,-(%sp)\n"'
			printf '%s\n' '	"\tmoveq #3,%d1\n\tcmp.l sw_sel,%d1\n\tbcs.w 9f\n"'
			printf '%s\n' '	"\tmove.l sw_sel,%d0\n\tadd.l %d0,%d0\n"'
			printf '%s\n' '	"\t.word 0x303b,0x0806\n"'	# movew %pc@(T,%d0:l),%d0
			printf '%s\n' '	"\t.word 0x4efb,0x0002\n"'	# jmp %pc@(T,%d0:w)
		elif [ "$2" = const ]; then
			printf '%s\n' '	"\tmove.l %a6,-(%sp)\n"'
			printf '%s\n' '	"\tmoveq #2,%d0\n\tadd.l %d0,%d0\n"'
			printf '%s\n' '	"\t.word 0x303b,0x0806\n"'	# movew %pc@(T,%d0:l),%d0
			printf '%s\n' '	"\t.word 0x4efb,0x0002\n"'	# jmp %pc@(T,%d0:w)
		elif [ "$2" = twolevel ]; then
			printf '%s\n' '	"\tmove.l 4(%sp),%d0\n\tmove.l %a6,-(%sp)\n\tcmp.l #3,%d0\n\tbhi.w 9f\n"'
			printf '%s\n' '	"\t.word 0x3030,0x0bb0\n\t.long swt\n"'	# movew @(swt,%d0:l:2),%d0
			printf '%s\n' '	"\t.word 0x4efb,0x0002\n"'	# jmp %pc@(T,%d0:w)
		elif [ "$2" != bias ] && [ "$2" != badbias ]; then	# no bound check
			printf '%s\n' '	"\tmove.l %a6,-(%sp)\n"'
			case "$2" in
			bf) printf '%s\n' '	"\tbfextu 8(%sp){#2:#3},%d0\n\tandi.l #255,%d0\n"' ;;
			bfreg) printf '%s\n' '	"\tmoveq #3,%d1\n\tbfextu 8(%sp){#2:%d1},%d0\n"' ;;
			mask|zero) printf '%s\n' '	"\tmove.l 8(%sp),%d0\n\tandi.l #255,%d0\n"' ;;
			cmpmask) printf '%s\n' '	"\tmove.l 8(%sp),%d0\n\tcmp.b #7,%d0\n\tbhi.w 9f\n\tandi.l #255,%d0\n"' ;;
			load) printf '%s\n' '	"\tmoveq #0,%d0\n\tmove.b 11(%sp),%d0\n"' ;;
			sload) printf '%s\n' '	"\tmove.b 11(%sp),%d0\n"' ;;
			esac
			printf '%s\n' '	"\tadd.l %d0,%d0\n"'
			printf '%s\n' '	"\t.word 0x303b,0x0806\n"'	# movew %pc@(T,%d0:l),%d0
			printf '%s\n' '	"\t.word 0x4efb,0x0002\n"'	# jmp %pc@(T,%d0:w)
		else	# bias, badbias
			printf '%s\n' '	"\tmove.l 4(%sp),%d1\n\tmove.l %a6,-(%sp)\n\tmove.l %d1,%d0\n"'
			if [ "$2" = bias ]; then
				printf '%s\n' '	"\taddq.l #4,%d0\n"'
			else
				printf '%s\n' '	"\taddq.l #4,%d1\n"'
			fi
			printf '%s\n' '	"\tmoveq #-4,%d2\n\tcmp.l %d1,%d2\n\tbhi.w 9f\n\tadd.l %d0,%d0\n"'
			printf '%s\n' '	"\t.word 0x303b,0x0806\n"'	# movew %pc@(T,%d0:l),%d0
			printf '%s\n' '	"\t.word 0x4efb,0x0002\n"'	# jmp %pc@(T,%d0:w)
		fi
		case "$2" in
		bf) printf '%s\n' '	"\t.word 0x074c,0x0056,0x0056,0x0056,0x0056,0x0056,0x0056,0x0056\n"' ;;
		zero) printf '%s\n' '	"\t.word 0x4e71,0x074c,0x0056,0x0056,0x0056\n"' ;;
		*) printf '%s\n' '	"\t.word 0x074c,0x0056,0x0056,0x0056\n"' ;;
		esac
		[ -z "$3" ] || printf '\t%s\n' "$3"
		printf '%s\n' '	"\t.fill 0x400,2,0x4e71\n"'
		printf '%s\n' '	"9:\tmove.l (%sp)+,%a6\n\trts\n.size swp,.-swp\n"'
		printf '%s\n' '	".data\nswt:\t.word 4,4,4,4\n.text\n");'
		printf '%s\n' 'int swp(int);'
		printf '%s\n' 'int main(int c, char **v) { sw_sel = c; return swp(c); }'
	} > "$T/$1.c"
	$CC $AMIX_CFLAGS -o "$T/$1" "$T/$1.c" || fail "the switch probe $1 did not build"
}
G14S="$AMIX_PKG_COMMON/gcc14/scan060-g14.py"
for shape in fp mem bias const; do
	sw_probe "sw-$shape" "$shape" ''
	# a constant-index table is sized from its words: the movep follows a
	# word that is no entry (a nop, odd), as gcc's case code does
	if [ "$shape" = const ]; then mv='"\t.word 0x4e71,0x074c,0x0056\n"'; else mv='"\t.word 0x074c,0x0056\n"'; fi
	sw_probe "sw-$shape-movep" "$shape" "$mv"
	out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-$shape") || fail "scan060-g14.py on the $shape switch: $out"
	echo "$out" | grep ' 1 switch tables sized' >/dev/null || fail "scan060-g14.py did not size the $shape table: $out"
	if [ "$shape" = const ]; then
		echo "$out" | grep 'NOTE dispatch at .*constant index #2; .*sized from its own entries (4), a known limit' >/dev/null ||
			fail "scan060-g14.py gave no known-limit NOTE for the constant index: $out"
	fi
	if out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-$shape-movep"); then
		fail "scan060-g14.py passed a real movep after the $shape table: $out"
	fi
	echo "$out" | grep 'HITS 1 .*1 switch tables sized' >/dev/null || fail "scan060-g14.py on the $shape movep probe: $out"
done
sw_probe sw-badbias badbias ''
if out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-badbias"); then
	fail "scan060-g14.py sized a table whose bias is added to another register: $out"
fi
echo "$out" | grep 'UNTRUSTWORTHY.*' >/dev/null || fail "scan060-g14.py on the badbias probe: $out"
ok "scan060-g14.py sizes %fp-indexed, memory-bounded, biased and constant-index switch tables (a NOTE), still catches a real movep after each; a bias on another register stays unsized"

# tables without a bound check: a bit field's width sizes one exactly; an
# index provably a byte (mask, zero-extended load) sizes one from its own
# entries when the run ends on a word that cannot be one (a NOTE); and the
# negatives stay untrustworthy
for shape in bf mask load; do
	sw_probe "sw-w-$shape" "$shape" ''
	if [ "$shape" = bf ]; then mv='"\t.word 0x074c,0x0056\n"'; else mv='"\t.word 0x4e71,0x074c,0x0056\n"'; fi
	sw_probe "sw-w-$shape-movep" "$shape" "$mv"
	out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-w-$shape") || fail "scan060-g14.py on the $shape switch: $out"
	echo "$out" | grep ' 1 switch tables sized' >/dev/null || fail "scan060-g14.py did not size the $shape table: $out"
	if [ "$shape" = bf ]; then
		if echo "$out" | grep NOTE >/dev/null; then fail "scan060-g14.py gave a NOTE for the exact bit field table: $out"; fi
	else
		echo "$out" | grep 'NOTE dispatch at .*the index at most 256; .*sized from its own entries (4, the run ending on an odd word), trusted by shape' >/dev/null ||
			fail "scan060-g14.py gave no trusted-by-shape NOTE for the $shape table: $out"
	fi
	if out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-w-$shape-movep"); then
		fail "scan060-g14.py passed a real movep after the $shape table: $out"
	fi
	echo "$out" | grep 'HITS 1 .*1 switch tables sized' >/dev/null || fail "scan060-g14.py on the $shape movep probe: $out"
done
for shape in bfreg sload zero cmpmask twolevel; do
	sw_probe "sw-w-$shape" "$shape" ''
	if out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-w-$shape"); then
		fail "scan060-g14.py sized the $shape table: $out"
	fi
	case "$shape" in
	bfreg|sload) want='no bound check found' ;;
	zero) want='the index at most 256, but table .* is no run of entries' ;;
	cmpmask) want='x8 has 4 entries not landing' ;;
	twolevel) want='offsets loaded from .*a two-level dispatch' ;;
	esac
	echo "$out" | grep UNTRUSTWORTHY >/dev/null && echo "$out" | grep "$want" >/dev/null ||
		fail "scan060-g14.py on the $shape probe, not '$want': $out"
done
# the D4 gate lists the trusted-by-shape table under its verdict
d4=$(amix_gate_d4 "$T/sw-w-load" 2>&1)
echo "$d4" | grep "D4 note $T/sw-w-load -- 1 switch table(s) sized from their own entries" >/dev/null &&
	echo "$d4" | grep "  sw-w-load: dispatch at .*trusted by shape" >/dev/null ||
	fail "amix_gate_d4 did not list the trusted-by-shape table: $d4"
ok "scan060-g14.py sizes a bfextu-indexed table exactly, a byte-indexed one from its own entries (a NOTE), catches a movep after each; a register width, an unextended byte, a run of no entries, a compare's bound and a two-level dispatch stay untrustworthy; the D4 gate lists the NOTE"

# Two dispatches back to back (diffutils 2.8.1 groups_letter_value,
# 2026-10-29), bytes and table words copied from the real binary: the linear
# decode of the first table runs on as `oril #...' through the second
# dispatch's `addib #-101,%d1', so its bound check is only seen after the
# re-sync, and the first round's "unsized" verdict must not outlive it.
b2b_probe() {	# b2b_probe <name> <extra asm string or empty>
	{
		printf '%s\n' '__asm__(".text\n.globl swp\n.type swp,@function\nswp:\n"'
		printf '%s\n' '	"\tmove.l 4(%sp),%d1\n\tmove.b %d1,%d0\n"'
		printf '%s\n' '	"\tadd.b #-69,%d0\n\tcmp.b #9,%d0\n\tbhi.w 9f\n"'
		printf '%s\n' '	"\tand.l #255,%d0\n\tadd.l %d0,%d0\n"'
		printf '%s\n' '	"\t.word 0x303b,0x0806\n\t.word 0x4efb,0x0002\n"'
		printf '%s\n' '	"\t.word 0x0044,0x005a,0x0014,0x0014,0x0014,0x0014,0x0014,0x006e,0x0084,0x0098\n"'
		printf '%s\n' '	"\t.word 0x0601,0xff9b,0x0c01,0x0009\n\tbhi.w 9f\n"'	# addib #-101,%d1; cmpib #9,%d1
		printf '%s\n' '	"\tand.l #255,%d1\n\tadd.l %d1,%d1\n"'
		printf '%s\n' '	"\t.word 0x303b,0x1806\n\t.word 0x4efb,0x0002\n"'
		printf '%s\n' '	"\t.word 0x0018,0x002e,0x0076,0x0076,0x0076,0x0076,0x0076,0x0042,0x0058,0x006c\n"'
		[ -z "$2" ] || printf '\t%s\n' "$2"
		printf '%s\n' '	"\t.fill 0x400,2,0x4e71\n"'
		printf '%s\n' '	"9:\trts\n.size swp,.-swp\n");'
		printf '%s\n' 'int swp(int);'
		printf '%s\n' 'int main(int c, char **v) { return swp(c); }'
	} > "$T/$1.c"
	$CC $AMIX_CFLAGS -o "$T/$1" "$T/$1.c" || fail "the switch probe $1 did not build"
}
b2b_probe sw-b2b ''
b2b_probe sw-b2b-movep '"\t.word 0x074c,0x0056\n"'
out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-b2b") || fail "scan060-g14.py on back-to-back switches: $out"
echo "$out" | grep ' 2 switch tables sized' >/dev/null || fail "scan060-g14.py did not size both back-to-back tables: $out"
if out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-b2b-movep"); then
	fail "scan060-g14.py passed a real movep after back-to-back tables: $out"
fi
echo "$out" | grep 'HITS 1 .*2 switch tables sized' >/dev/null || fail "scan060-g14.py on the back-to-back movep probe: $out"
ok "scan060-g14.py sizes back-to-back switch tables whose bound check the first decode swallowed, still catches a movep"

# The stock AT&T compiler's switch (libc.so's static getutx.o, _getutxid,
# linked by coreutils who/users/pinky, 2026-10-29), bytes copied from the
# real binary: the bound check is cmpa (`moveq #8,%d1; cmpal %d1,%a0; bhiw'),
# the index load a full-format `movew %pc@(T,%a0:l:2),%d1', and an
# `illegal' word plus the entry count sit between the jmp and the table.
att_probe() {	# att_probe <name> <extra asm string or empty>
	{
		printf '%s\n' '__asm__(".text\n.globl swp\n.type swp,@function\nswp:\n"'
		printf '%s\n' '	"\tmove.l 4(%sp),%a0\n\tmoveq #8,%d1\n\tcmpa.l %d1,%a0\n\tbhi.w 9f\n"'
		printf '%s\n' '	"\t.word 0x323b,0x8b30,0x0000,0x000e\n"'	# movew %pc@(T,%a0:l:2),%d1
		printf '%s\n' '	"\t.word 0x4efb,0x1006\n\t.word 0x4afc,0x0009\n"'	# jmp %pc@(T,%d1:w); illegal; 9
		printf '%s\n' '	"\t.word 0x008a,0x0012,0x0012,0x0012,0x0012,0x0026,0x0026,0x0026,0x0026\n"'
		[ -z "$2" ] || printf '\t%s\n' "$2"
		printf '%s\n' '	"\t.fill 0x400,2,0x4e71\n"'
		printf '%s\n' '	"9:\trts\n.size swp,.-swp\n");'
		printf '%s\n' 'int swp(int);'
		printf '%s\n' 'int main(int c, char **v) { return swp(c); }'
	} > "$T/$1.c"
	$CC $AMIX_CFLAGS -o "$T/$1" "$T/$1.c" || fail "the switch probe $1 did not build"
}
att_probe sw-att ''
att_probe sw-att-movep '"\t.word 0x074c,0x0056\n"'
out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-att") || fail "scan060-g14.py on the AT&T cmpa switch: $out"
echo "$out" | grep ' 1 switch tables sized' >/dev/null || fail "scan060-g14.py did not size the AT&T cmpa table: $out"
if out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-att-movep"); then
	fail "scan060-g14.py passed a real movep after the AT&T cmpa table: $out"
fi
echo "$out" | grep 'HITS 1 .*1 switch tables sized' >/dev/null || fail "scan060-g14.py on the AT&T movep probe: $out"
ok "scan060-g14.py sizes the stock AT&T compiler's cmpa-bounded switch table, still catches a movep"

# Three more shapes from perl 5.8.9 (2026-10-30), each dispatched the GCC 14
# way (`addl %d1,%d1; movew %pc@(T,%d1:l),%d1; jmp %pc@(T,%d1:w)'):
#   mask   switch (x & 3) -- `moveq #3,%d0; andl %d0,%d1', no compare at all
#          (sdbm's Duff's device, Perl_ck_fun);
#   entry  the dispatch block is only entered by `cmpiw #3,%d1; blsw' above
#          an rts (Perl_ref);
#   cmpmid the bound `moveq #2,%d7; ...; cmpl %d1,%d7; bcs' with another
#          compare of %d7 in between (Perl_pv_uni_display).
shape_probe() {	# shape_probe <name> <prologue asm> <entries> <extra asm or empty>
	{
		printf '%s\n' '__asm__(".text\n.globl swp\n.type swp,@function\nswp:\n"'
		printf '\t%s\n' "$2"
		printf '%s\n' '	"\t.word 0xd281,0x323b,0x1806,0x4efb,0x1002\n"'
		printf '\t"\\t.word %s\\n"\n' "$3"
		[ -z "$4" ] || printf '\t%s\n' "$4"
		printf '%s\n' '	"\t.fill 0x400,2,0x4e71\n"'
		printf '%s\n' '	"9:\trts\n.size swp,.-swp\n");'
		printf '%s\n' 'int swp(int);'
		printf '%s\n' 'int main(int c, char **v) { return swp(c); }'
	} > "$T/$1.c"
	$CC $AMIX_CFLAGS -o "$T/$1" "$T/$1.c" || fail "the switch probe $1 did not build"
}
for shape in mask entry cmpmid; do
	case $shape in
	mask)   pro='"\tmove.l 4(%sp),%d1\n\tmoveq #3,%d0\n\tand.l %d0,%d1\n"'; ent='0x0040,0x0040,0x0040,0x0040' ;;
	entry)  pro='"\tmove.l 4(%sp),%d1\n\tcmp.w #3,%d1\n\tbls.w 1f\n\trts\n1:\n"'; ent='0x0040,0x0040,0x0040,0x0040' ;;
	cmpmid) pro='"\tmove.l 4(%sp),%d0\n\tmoveq #2,%d7\n\tcmp.l %d0,%d7\n\tbcc.w 9f\n\tmove.l %d0,%d1\n\tsubq.l #3,%d1\n\tcmp.l %d1,%d7\n\tbcs.w 9f\n"'; ent='0x0040,0x0040,0x0040' ;;
	esac
	shape_probe "sw-$shape" "$pro" "$ent" ''
	shape_probe "sw-$shape-movep" "$pro" "$ent" '"\t.word 0x074c,0x0056\n"'
	out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-$shape") || fail "scan060-g14.py on the $shape switch: $out"
	echo "$out" | grep ' 1 switch tables sized' >/dev/null || fail "scan060-g14.py did not size the $shape table: $out"
	if out=$(python3 "$G14S" --objdump "$OBJDUMP" "$T/sw-$shape-movep"); then
		fail "scan060-g14.py passed a real movep after the $shape table: $out"
	fi
	echo "$out" | grep 'HITS 1 .*1 switch tables sized' >/dev/null || fail "scan060-g14.py on the $shape movep probe: $out"
done
ok "scan060-g14.py sizes mask-bounded, entry-bounded and compare-interleaved switch tables, still catches a movep after each"

# The toolchain identity (gcc14-env.sh): a prefix whose specs differ from the
# pin by one byte is refused before anything builds; the return-value ABI
# self-check passes the pinned compiler.  Where a pre-fix control compiler is
# at hand (AMIX_G14_E316F1B, default the gcc14-cross-amix checkout beside the
# main working tree, build/prefix-e316f1b: pointers in %d0 only, small
# structs in registers), the self-check must reject that compiler too.
FP="$T/fakeprefix"
cp -as "$AMIX_GCC14_PREFIX" "$FP"
rm "$FP/lib/gcc/m68k-elf/14.2.0/specs"
{ cat "$AMIX_GCC14_PREFIX/lib/gcc/m68k-elf/14.2.0/specs"; echo; } > "$FP/lib/gcc/m68k-elf/14.2.0/specs"
if (AMIX_GCC14_PREFIX="$FP"; export AMIX_GCC14_PREFIX; . "$AMIX_PKG_COMMON/amix-env.sh") > "$T/pin.log" 2>&1; then
	fail "amix-env.sh accepted a prefix whose specs differ from the pin"
fi
grep 'not the pinned toolchain' "$T/pin.log" >/dev/null && grep 'specs:' "$T/pin.log" >/dev/null ||
	{ cat "$T/pin.log" >&2; fail "the pin refusal does not name specs"; }
amix_g14_abi_selfcheck "$AMIX_GCC14_CC" >/dev/null 2>&1 || fail "the ABI self-check rejected the pinned compiler"
if [ -z "${AMIX_G14_E316F1B:-}" ]; then
	_g=$(git -C "$AMIX_TOP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
		AMIX_G14_E316F1B=$(dirname "$(dirname "$_g")")/gcc14-cross-amix/build/prefix-e316f1b
fi
OLDCC="${AMIX_G14_E316F1B:-}/bin/m68k-elf-gcc"
if [ -x "$OLDCC" ]; then
	if amix_g14_abi_selfcheck "$OLDCC" >/dev/null 2>&1; then fail "the ABI self-check passed the e316f1b compiler"; fi
	ok "toolchain pin refuses a one-byte specs change; ABI self-check passes the pinned prefix, rejects e316f1b"
else
	ok "toolchain pin refuses a one-byte specs change; ABI self-check passes the pinned prefix (no e316f1b control prefix to reject)"
fi

# The same identity guards amix-dlm's box binaries (kbootset, modadmin), which
# its Makefile links with the prefix directly: dlm-src.sh's check refuses a
# build dir whose prefix is the one-byte-specs copy, and passes the real one.
mkdir -p "$T/fakebuild"; ln -s "$FP" "$T/fakebuild/prefix"; ln -s "$AMIX_GCC14_ROOT/build/sysroot" "$T/fakebuild/sysroot"
if (AMIX_G14_BUILD="$T/fakebuild"; . "$AMIX_PKG_COMMON/dlm-src.sh"; amix_dlm_g14_check) > "$T/dlmpin.log" 2>&1; then
	fail "dlm-src.sh's box check accepted a prefix whose specs differ from the pin"
fi
grep 'not the pinned toolchain' "$T/dlmpin.log" >/dev/null && grep 'specs:' "$T/dlmpin.log" >/dev/null ||
	{ cat "$T/dlmpin.log" >&2; fail "dlm-src.sh's refusal does not name specs"; }
(AMIX_G14_BUILD="$AMIX_GCC14_ROOT/build"; . "$AMIX_PKG_COMMON/dlm-src.sh"; amix_dlm_g14_check) > "$T/dlmpin-ok.log" 2>&1 ||
	{ cat "$T/dlmpin-ok.log" >&2; fail "dlm-src.sh's box check refused the pinned toolchain"; }
ok "dlm-src.sh's box-build check (kbootset, modadmin) refuses the one-byte specs change, passes the pinned prefix"

# -mno-strict-align (owner decision 2026-10-27): the flag sets that lack it, or
# override it later, are refused by amix-env.sh; a compiler that still splits
# an unaligned load (a wrapper appending -mstrict-align) fails the -S probe;
# the make-log half of amix_gate_g14_strict rejects a compile line without it
# and a log with no compile line.
case " $AMIX_ARCH_FLAGS " in *" -mno-strict-align "*) ;; *) fail "AMIX_ARCH_FLAGS '$AMIX_ARCH_FLAGS' lacks -mno-strict-align" ;; esac
amix_g14_align_check "$CC" "$AMIX_ARCH_FLAGS" "$AMIX_CFLAGS" >/dev/null 2>&1 || fail "the align check rejected the recipe flags"
if (AMIX_ARCH_FLAGS=-m68020-60; unset AMIX_CFLAGS; export AMIX_ARCH_FLAGS; . "$AMIX_PKG_COMMON/amix-env.sh") > "$T/al1.log" 2>&1; then
	fail "amix-env.sh accepted AMIX_ARCH_FLAGS without -mno-strict-align"
fi
grep 'does not end with -mno-strict-align' "$T/al1.log" >/dev/null || { cat "$T/al1.log" >&2; fail "al1 refused, but not by the align check"; }
if (AMIX_CFLAGS="$AMIX_ARCH_FLAGS -O2 -mstrict-align"; export AMIX_CFLAGS; . "$AMIX_PKG_COMMON/amix-env.sh") > "$T/al2.log" 2>&1; then
	fail "amix-env.sh accepted AMIX_CFLAGS ending in -mstrict-align"
fi
grep 'does not end with -mno-strict-align' "$T/al2.log" >/dev/null || { cat "$T/al2.log" >&2; fail "al2 refused, but not by the align check"; }
printf '#!/bin/sh\nexec %s "$@" -mstrict-align\n' "$AMIX_GCC14_CC" > "$T/strictcc"; chmod +x "$T/strictcc"
if amix_g14_align_check "$T/strictcc $AMIX_PREDEFS" "$AMIX_ARCH_FLAGS" "$AMIX_CFLAGS" > "$T/al3.log" 2>&1; then
	fail "the align check passed a compiler that keeps strict alignment"
fi
grep 'still splits an unaligned load' "$T/al3.log" >/dev/null || { cat "$T/al3.log" >&2; fail "al3 refused, but not by the -S probe"; }
G="$AMIX_GCC14_CC $AMIX_PREDEFS"
printf '%s -I. %s -c a.c\n%s -o prog a.o\n' "$G" "$AMIX_CFLAGS" "$G" > "$T/good.log"
printf '%s -I. %s -c a.c\n%s -I. -m68020-60 -O2 -c b.c\nif %s %s -mstrict-align -MT c.o -c -o c.o c.c; \\\n' \
	"$G" "$AMIX_CFLAGS" "$G" "$G" "$AMIX_CFLAGS" > "$T/bad.log"
printf 'make: Nothing to be done for `all'"'"'.\n' > "$T/none.log"
amix_gate_g14_strict "$T/good.log" >/dev/null 2>&1 || fail "the strict gate rejected a log whose compile lines carry -mno-strict-align"
if amix_gate_g14_strict "$T/bad.log" > "$T/al4.log" 2>&1; then fail "the strict gate passed compile lines without -mno-strict-align"; fi
grep '2 of 3 gcc14 compile lines lack' "$T/al4.log" >/dev/null || { cat "$T/al4.log" >&2; fail "the strict gate miscounted the bad log"; }
if amix_gate_g14_strict "$T/none.log" >/dev/null 2>&1; then fail "the strict gate passed a log with no compile line"; fi
ok "-mno-strict-align: env refuses flags without it or overriding it, -S probe rejects a strict compiler, make-log gate counts 2/3 bad and refuses an empty log"

# amix-decls.h: what the AMIX headers never declare, so an implicit
# declaration (an error under gcc14) never reaches a link: readv/writev
# (libc.so.1), cbrt (libm.a), copysign and isinf as gcc's builtins
cat > "$T/decls.c" <<'EOF'
#include <sys/types.h>
#include <sys/uio.h>
#include <math.h>
int f(double x, float y, long double z, int fd, struct iovec *v) {
	return readv(fd, v, 1) + writev(fd, v, 1) + isinf(x) + isinf(y) + isinf(z)
	    + isnan(x) + (int)copysign(cbrt(x), -1.0);
}
EOF
if $CC $AMIX_CFLAGS -Werror=implicit-function-declaration -c "$T/decls.c" -o "$T/nodecls.o" > "$T/nodecls.log" 2>&1; then
	fail "the decls probe compiled without amix-decls.h: it tests nothing"
fi
$CC $AMIX_CFLAGS -Werror=implicit-function-declaration -include "$AMIX_GCC14_DECLS" -c "$T/decls.c" -o "$T/decls.o" > "$T/decls.log" 2>&1 ||
	{ cat "$T/decls.log" >&2; fail "amix-decls.h does not declare readv, writev, cbrt, copysign and isinf"; }
_und=$("$NM" -u "$T/decls.o" | awk '{print $NF}' | LC_ALL=C sort | tr '\n' ' ')
[ "$_und" = "cbrt readv writev " ] || fail "the decls probe leaves '$_und' undefined, not cbrt readv writev (isinf, isnan and copysign inline)"
ok "amix-decls.h declares readv, writev, cbrt, copysign and isinf; isinf and copysign expand inline, the rest are the sysroot's"

echo "gate-gcc14-selftest: PASS ($n checks)"
