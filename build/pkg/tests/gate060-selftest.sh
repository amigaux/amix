#!/bin/sh
#
# gate060-selftest.sh -- prove the 68060 build gate fires, end to end.
#
#     sh build/pkg/tests/gate060-selftest.sh
#
# The gate (build/pkg/common/gates.sh D4, strict since 2026-10-05) has three
# layers; each is exercised here against probes built through the real
# wrapper, and each must REJECT a 68060-unsafe artifact and PASS a safe one:
#
#   1. amix-env.sh       refuses AMIX_MUL64=keep, exports AMIX_SCAN060=1
#   2. amix_gate_d4      both encoding scanners, on a file/archive/dir
#                        (its own selftest runs first: keep vs expand probes,
#                        the wrapper's AMIX_SCAN060 post-check, scan060's own)
#   3. amix_pkgroll      the whole staged payload, before pkgmk: a package
#                        whose payload carries one 64-bit multiply in an
#                        executable or in an archive member is NOT rolled
#
#   4. amix_pkgroll    the rolled datastream, with userland/pkgtools/tools/repo/scan060.py
#                        (the scanner of record for linked files and .pkg)
#
# Exit 0 and "gate060-selftest: PASS" last, or non-zero on the first miss.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
AMIX_TOP=$(cd "$HERE/../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1793303717}	# the roll stamps every time with it
export AMIX_PREFIX=/opt/amix

T=$(mktemp -d "${TMPDIR:-/tmp}/gate060.XXXXXX")
trap 'rm -rf "$T"' EXIT

fail() { echo "gate060-selftest: FAIL -- $*" >&2; exit 1; }
n=0
ok() { n=$((n + 1)); echo "  ok $n  $*"; }

# --- 1. the environment ------------------------------------------------------
if (AMIX_MUL64=keep; export AMIX_MUL64; . "$AMIX_PKG_COMMON/amix-env.sh") >/dev/null 2>&1; then
	fail "amix-env.sh accepted AMIX_MUL64=keep"
fi
ok "amix-env.sh refuses AMIX_MUL64=keep"

unset AMIX_MUL64 AMIX_SCAN060
. "$AMIX_PKG_COMMON/amix-env.sh"
. "$AMIX_PKG_COMMON/gates.sh"
. "$AMIX_PKG_COMMON/pkgroll.sh"
[ "$AMIX_SCAN060" = 1 ] && [ "$AMIX_MUL64" = expand ] || fail "amix-env.sh did not export AMIX_SCAN060=1 / AMIX_MUL64=expand"
ok "amix-env.sh exports AMIX_MUL64=expand AMIX_SCAN060=1"
echo "  scan060 objdump: $(amix_scan060_objdump)"

# --- 2. amix_gate_d4 and its selftest ----------------------------------------
amix_gate_d4_selftest "$T/st" || fail "amix_gate_d4_selftest"
ok "amix_gate_d4_selftest"

cat > "$T/prog.c" <<'EOF'
long long bad(long a, long *p) { return (long long)a * *p; }
unsigned imm(unsigned x) { return x / 10; }
int main(int argc, char **argv) { long v = argc; return (int)(bad(argc, &v) + imm(argc)); }
EOF
cat > "$T/lib.c" <<'EOF'
unsigned per_mille(unsigned x) { return x % 1000; }
EOF
cat > "$T/ok.c" <<'EOF'
int main(void) { return 0; }
EOF
build() {	# build <mode> <dir>: prog (executable) + liblib.a, through the wrapper
	mkdir -p "$2"
	AMIX_MUL64=$1 AMIX_SCAN060=0 "$CC" $AMIX_CFLAGS -o "$2/prog" "$T/prog.c" >/dev/null
	AMIX_MUL64=$1 AMIX_SCAN060=0 "$CC" $AMIX_CFLAGS -c "$T/lib.c" -o "$2/lib.o" >/dev/null
	"$AR" rc "$2/liblib.a" "$2/lib.o"; rm -f "$2/lib.o"
}
build keep "$T/keep"
build expand "$T/expand"
"$CC" $AMIX_CFLAGS -o "$T/ok" "$T/ok.c" >/dev/null

for f in "$T/keep/prog" "$T/keep/liblib.a" "$T/keep"; do
	if amix_gate_d4 "$f" >/dev/null 2>&1; then fail "amix_gate_d4 passed $f"; fi
done
ok "amix_gate_d4 rejects a keep executable, a keep archive, and their directory"
for f in "$T/expand/prog" "$T/expand/liblib.a" "$T/expand" "$T/ok"; do
	amix_gate_d4 "$f" >/dev/null 2>&1 || fail "amix_gate_d4 rejected $f"
done
ok "amix_gate_d4 passes the expanded executable, archive and directory"

# --- 3. amix_pkgroll refuses to roll an unsafe payload ------------------------
roll() {	# roll <tag> <payload-dir>: a two-file package through amix_pkgroll
	w="$T/roll-$1"; r="$T/root-$1"
	mkdir -p "$w" "$r/opt/amix/bin" "$r/opt/amix/lib"
	cp "$2/prog" "$r/opt/amix/bin/prog"
	cp "$2/liblib.a" "$r/opt/amix/lib/liblib.a"
	printf 'PKG=g060t\nNAME=gate test\nARCH=Amiga\nVERSION=1\nCATEGORY=test\nCLASSES=none\nPSTAMP=gate060\n' > "$w/pkginfo"
	printf 'i pkginfo\nd none /opt 0755 root sys\nd none /opt/amix 0755 root sys\nd none /opt/amix/bin 0755 root sys\nd none /opt/amix/lib 0755 root sys\nf none /opt/amix/bin/prog 0755 root sys\nf none /opt/amix/lib/liblib.a 0644 root sys\n' > "$w/prototype"
	( amix_pkgroll "$w" "$r" g060t 1 "$T/out-$1.pkg" ) > "$T/roll-$1.log" 2>&1
}
if roll keep "$T/keep"; then fail "amix_pkgroll rolled a payload with 64-bit multiplies"; fi
[ ! -f "$T/out-keep.pkg" ] || fail "amix_pkgroll left a datastream for the unsafe payload"
grep -q '68060 gate' "$T/roll-keep.log" || fail "amix_pkgroll failed, but not at the 68060 gate"
ok "amix_pkgroll refuses the keep payload, no datastream written"

# only the ARCHIVE unsafe: the member must still be seen
mkdir -p "$T/mixed"; cp "$T/expand/prog" "$T/mixed/prog"; cp "$T/keep/liblib.a" "$T/mixed/liblib.a"
if roll mixed "$T/mixed"; then fail "amix_pkgroll rolled a payload whose archive member has a 64-bit multiply"; fi
ok "amix_pkgroll refuses a payload whose only hit is an archive member"

# the datastream layer on its own: with the tree gate disabled in a subshell,
# the packagemanager's scanner on the rolled .pkg must still refuse it
if ( amix_gate_060_tree() { return 0; }; roll dsonly "$T/keep" ); then
	fail "the datastream gate passed a .pkg with 64-bit multiplies"
fi
[ ! -f "$T/out-dsonly.pkg" ] || fail "the datastream gate left the unsafe .pkg behind"
grep -q '060 FAIL datastream' "$T/roll-dsonly.log" || fail "dsonly roll failed, but not at the datastream gate"
ok "with the tree gate off, the datastream gate (scan060.py) refuses and removes the .pkg"

roll expand "$T/expand" || { cat "$T/roll-expand.log" >&2; fail "amix_pkgroll refused the safe payload"; }
[ -f "$T/out-expand.pkg" ] || fail "amix_pkgroll wrote no datastream for the safe payload"
ok "amix_pkgroll rolls the expanded payload"

# a data-only payload (stock /etc defaults): both gates pass it
w="$T/roll-data"; r="$T/root-data"
mkdir -p "$w" "$r/etc"
echo "id:2:initdefault:" > "$r/etc/inittab"
printf 'PKG=g060d\nNAME=gate test\nARCH=Amiga\nVERSION=1\nCATEGORY=test\nCLASSES=none\nPSTAMP=gate060\n' > "$w/pkginfo"
printf 'i pkginfo\nf none /etc/inittab 0664 root sys\n' > "$w/prototype"
( amix_pkgroll "$w" "$r" g060d 1 "$T/out-data.pkg" ) > "$T/roll-data.log" 2>&1 ||
	{ cat "$T/roll-data.log" >&2; fail "amix_pkgroll refused a data-only payload"; }
grep -q 'datastream out-data.pkg -- no m68k ELF or archive (data-only package)' "$T/roll-data.log" ||
	fail "the datastream gate did not pass the data-only .pkg as data-only"
ok "amix_pkgroll rolls a data-only payload; the datastream gate passes it as data-only"

# --- 4. the VERSION/name agreement --------------------------------------------
if ( amix_pkgroll "$T/roll-expand" "$T/root-expand" g060t 2 "$T/out-v2.pkg" ) >/dev/null 2>&1; then
	fail "amix_pkgroll rolled a datastream whose name disagrees with pkginfo VERSION"
fi
ok "amix_pkgroll refuses a version that disagrees with pkginfo"

echo "gate060-selftest: PASS ($n checks)"
