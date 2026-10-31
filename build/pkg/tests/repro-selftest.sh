#!/bin/sh
#
# repro-selftest.sh -- prove a rolled .pkg is the same bytes however it is
# rolled.
#
#     sh build/pkg/tests/repro-selftest.sh
#
# One recipe (a gcc14 program that prints its __FILE__, a data file and a
# conffile, so the datastream has install/ scripts too) is built and rolled by pkgbuild.sh from two
# copies of build/ at different paths, seconds apart, under umasks 022 and
# 077, with the second build tree on another filesystem (/dev/shm when it is
# one) so the spool's directory order, inodes and device differ. The two
# .pkg must be byte-identical; their headers must carry the package's epoch
# (package.sh SOURCE_EPOCH, whatever SOURCE_DATE_EPOCH the environment has)
# and uid 0 only; the heirloom reader must unpack the payload unchanged; and
# another SOURCE_EPOCH must give other bytes, so the epoch is the only time
# in them. Needs the toolchains (run it in the build container, or with GCA and
# G14 found as layout.sh finds them). Exit 0 and "repro-selftest: PASS" last.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
AMIX_TOP=$(cd "$HERE/../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
EP=1793303717			# the recipe's SOURCE_EPOCH
export SOURCE_DATE_EPOCH=1111111111	# the environment's, which the roll must not use
export GCA G14 AMIX_PKGMGR AMIX_PKGMK AMIX_PKGTRANS AMIX_PM_SCAN060 AMIX_SYSTEM

T=$(mktemp -d "${TMPDIR:-/tmp}/repro.XXXXXX")
S=
trap '[ -n "${REPRO_KEEP:-}" ] || rm -rf "$T" ${S:+"$S"}' EXIT
if [ -d /dev/shm ] && [ -w /dev/shm ] && [ "$(stat -f -c %T /dev/shm)" != "$(stat -f -c %T "$T")" ]; then
	S=$(mktemp -d /dev/shm/repro.XXXXXX)
else
	S=$(mktemp -d "$T/other.XXXXXX")
fi

fail() { echo "repro-selftest: FAIL -- $*" >&2; exit 1; }
n=0
ok() { n=$((n + 1)); echo "  ok $n  $*"; }

# two checkouts: build/ and the pins, at different paths
checkout() {
	mkdir -p "$1/toolchain" "$1/userland/packages"
	cp -R "$AMIX_TOP/build" "$1/build"
	rm -rf "$1/build/out"
	cp "$AMIX_TOP"/toolchain/*.pin "$1/toolchain/"
	r="$1/userland/packages/rtest"
	mkdir -p "$r/src"
	cat > "$r/package.sh" <<'EOF'
NAME=rtest
PKG=rtest
VERSION=1.0
PKGREV=1
SUMMARY="the reproducibility test package"
DESC="A program, a data file and a conffile, rolled twice."
CATEGORY=utility
SET=extra
LICENSE=MIT
STYLE=hooks
CONFFILES=/etc/rtest.conf
SOURCE_EPOCH=1793303717
EOF
	cat > "$r/build.sh" <<'EOF'
build() {
	# by absolute path, as a VPATH build does: __FILE__ names the build tree
	echo "$CC $AMIX_CFLAGS -c $PWD/rtest.c" >> "$BUILD/make.log"
	$CC $AMIX_CFLAGS -c "$PWD/rtest.c"
	$CC $AMIX_CFLAGS -o rtest rtest.o
}
stage() {
	mkdir -p "$DEST/opt/amix/bin" "$DEST/opt/amix/share/rtest" "$DEST/etc" "$DEST/opt/amix/man/1"
	cp rtest "$DEST/opt/amix/bin/rtest"
	for f in b a c; do echo "$f" > "$DEST/opt/amix/share/rtest/$f"; done
	echo "level=1" > "$DEST/etc/rtest.conf"
	printf '.TH RTEST 1\n.SH NAME\nrtest \\- a test\n' > "$DEST/opt/amix/man/1/rtest"
	cp "$DEST/opt/amix/man/1/rtest" "$DEST/opt/amix/man/1/rtest.conf"
}
EOF
	printf '#include <stdio.h>\nint main(void) { puts(__FILE__); return 0; }\n' > "$r/src/rtest.c"
	cat > "$r/prototype" <<'EOF'
i pkginfo
d none /etc 0755 root sys
f none /etc/rtest.conf 0644 root sys
d none /opt 0755 root sys
d none /opt/amix 0755 root sys
d none /opt/amix/bin 0755 root sys
f none /opt/amix/bin/rtest 0755 root bin
d none /opt/amix/man 0755 root bin
d none /opt/amix/man/1 0755 root bin
f none /opt/amix/man/1/rtest 0644 root bin
f none /opt/amix/man/1/rtest.conf 0644 root bin
d none /opt/amix/share 0755 root sys
d none /opt/amix/share/rtest 0755 root sys
f none /opt/amix/share/rtest/c 0644 root bin
f none /opt/amix/share/rtest/a 0644 root bin
f none /opt/amix/share/rtest/b 0644 root bin
EOF
}
A="$T/one/amix"
B="$S/a/much/longer/path/amix"
checkout "$A"
checkout "$B"

roll() {	# roll <checkout> <umask> <build root> <log>
	( umask "$2"; AMIX_BUILD_ROOT="$3" AMIX_GCC14_BUILD_ROOT="$3" \
		sh "$1/build/pkg/pkgbuild.sh" "$1/userland/packages/rtest" ) > "$4" 2>&1 ||
		{ tail -30 "$4" >&2; fail "pkgbuild.sh failed in $1"; }
}
roll "$A" 022 "$A/out/pkg" "$T/one.log"
pa="$A/out/pkg/pkg/rtest-1.0-1.pkg"
[ -f "$pa" ] || fail "no $pa"
ok "rolled from $A, umask 022"
sleep 2
roll "$B" 077 "$B/out/pkg" "$T/two.log"
pb="$B/out/pkg/pkg/rtest-1.0-1.pkg"
ok "rolled again 2 s later from $B, umask 077, on $(stat -f -c %T "$S")"

grep -q '/build/rtest/work/rtest-1.0/rtest\.c' "$A/out/pkg/rtest/dest/opt/amix/bin/rtest" ||
	fail "the program's __FILE__ is not the remapped /build/rtest/work/rtest-1.0/rtest.c"
grep -qF "$A" "$A/out/pkg/rtest/dest/opt/amix/bin/rtest" && fail "the program names its checkout, $A"
ok "the compiler remaps the build tree: __FILE__ is /build/rtest/work/rtest-1.0/rtest.c in both"
cmp "$pa" "$pb" || fail "the two rolls differ"
ok "the two .pkg are byte-identical: $(stat -c%s "$pa") bytes, md5 $(md5sum "$pa" | cut -c1-32)"

python3 -I - "$pa" "$EP" <<'EOF' || fail "a header carries more than the epoch and uid 0"
import sys
buf = open(sys.argv[1], "rb").read()
epoch = int(sys.argv[2])
end = buf.find(b"# end of header\n")
off, bad, seen = (end + 16 + 511) // 512 * 512, [], []
while off < len(buf) and buf[off:off + 6] == b"070701":
    while True:
        v = [int(buf[off + 6 + 8 * i: off + 14 + 8 * i], 16) for i in range(13)]
        name = buf[off + 110: off + 110 + v[11] - 1].decode()
        data = (off + 110 + v[11] + 3) // 4 * 4
        off = (data + v[6] + 3) // 4 * 4
        if name == "TRAILER!!!":
            break
        seen.append(name)
        if v[2] or v[3] or v[7] or v[8] or v[5] != epoch:
            bad.append(name)
    off = (off + 511) // 512 * 512
if bad or not seen:
    print("bad headers:", bad)
    sys.exit(1)
root = [s for s in seen if s.startswith("root/opt/amix/share/rtest/")]
if root != sorted(root):
    print("payload members not in sorted order:", root)
    sys.exit(1)
EOF
ok "every newc header: uid, gid, dev 0, mtime $EP (the recipe's, not the environment's); members sorted"

x="$T/unpack"; mkdir -p "$x"
"$AMIX_PKGTRANS" "$pa" "$x" rtest > "$T/unpack.log" 2>&1 || { cat "$T/unpack.log" >&2; fail "pkgtrans cannot unpack it"; }
for f in opt/amix/bin/rtest opt/amix/share/rtest/a etc/rtest.conf; do
	cmp -s "$x/rtest/root/$f" "$A/out/pkg/rtest/dest/$f" || fail "unpacked $f differs from the staged file"
done
[ -f "$x/rtest/install/i.conffile" ] || fail "no install/i.conffile in the datastream"
awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[fei]$/ { if ($NF != e) bad = 1 } END { exit bad }' e="$EP" \
	"$x/rtest/pkgmap" || fail "pkgmap's modtime column is not the epoch"
ok "the heirloom reader unpacks it: payload as staged, install/ scripts, pkgmap at the epoch"

rm -f "$pb"
sed -i "s/^SOURCE_EPOCH=$EP\$/SOURCE_EPOCH=$((EP + 86400))/" "$B/userland/packages/rtest/package.sh"
roll "$B" 022 "$B/out/pkg" "$T/three.log"
cmp -s "$pa" "$pb" && fail "another SOURCE_EPOCH gave the same bytes"
ok "another SOURCE_EPOCH gives other bytes: the epoch is the only time in them"

echo "repro-selftest: PASS ($n checks)"
