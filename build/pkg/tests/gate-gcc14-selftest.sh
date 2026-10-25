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
#   - amix-env.sh refuses gcc14 for a recipe that has not opted in.
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

echo "gate-gcc14-selftest: PASS ($n checks)"
