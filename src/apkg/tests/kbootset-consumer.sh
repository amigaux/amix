#!/bin/sh
# kbootset-consumer.sh - apkg's install record against its consumer.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# run-tests.sh proves the record apkg writes is C2-2 §2 to the byte and
# that the trigger speaks C2-4 to a mock.  This script closes the loop
# with the REAL reader: it builds kbootset from the sibling amix-dlm tree
# with its own Makefile (build dir redirected into tests/work, so the
# amix-dlm tree is only read), lays an empty boot store in
# an image, and lets apkg install a kernel-space package and call that
# kbootset through a wrapper that adds what a host build needs (--image,
# the box facts).  kbootset's gate 1 then compares every member with the
# `file` line apkg wrote; gate 2 compares the record's kabi with the
# kernel's sidecar.
#
# Not part of the run-tests.sh count: it needs the amix-dlm checkout, a
# host cc and zlib.  Without the checkout it says SKIP and exits 0; with it,
# a kbootset that does not build fails the script.
#
# Usage: sh tests/kbootset-consumer.sh [path-to-amix-dlm]

set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
DLM=${1:-$SRC/../../../amix-dlm}
WORK=$SRC/tests/work/kconsumer
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && { \
        echo "----- output -----"; echo "$2"; echo "------------------"; }; }

if [ ! -f "$DLM/Makefile" ] || [ ! -d "$DLM/kbootset" ]; then
    echo "SKIP: no amix-dlm tree (Makefile + kbootset/) at $DLM"; exit 0
fi
DLM=$(cd "$DLM" && pwd)
make -C "$SRC" host >/dev/null || { echo "host build failed"; exit 1; }
APKG=$SRC/apkg
rm -rf "$WORK"; mkdir -p "$WORK/bin" "$WORK/repo/pkgs/kernel" "$WORK/cache"

# kbootset is built by amix-dlm's own Makefile, so a source file it gains
# is picked up here too.  B= points its build directory into tests/work:
# nothing is written inside the amix-dlm tree.  Once the tree is there, a
# build that fails is a FAIL, never a SKIP.
make -C "$DLM" B="$WORK/dlm" "$WORK/dlm/kbootset" > "$WORK/kb.err" 2>&1 \
    && [ -x "$WORK/dlm/kbootset" ] \
    && ok "kbootset built by amix-dlm's Makefile at $(git -C "$DLM" log -1 --format=%h 2>/dev/null)" \
    || { bad "kbootset did not build from $DLM" "$(tail -20 "$WORK/kb.err")"
         echo "== kbootset consumer: $PASS passed, $FAIL failed =="; exit 1; }
cp "$WORK/dlm/kbootset" "$WORK/kbootset"
KB=$WORK/kbootset
IMG=$WORK/disk.img
T=$WORK/root                      # the -R target
mkdir -p "$T/var/kbootset" "$T/var/sadm/install" "$T/var/sadm/pkg"
head -c 8454144 /dev/zero > "$IMG"
head -c 20000 /dev/urandom > "$WORK/boot2.bin"
"$KB" --image "$IMG" --offset 65536 create 8388608 "$WORK/boot2.bin" >/dev/null \
    && ok "an empty boot store laid in the image" || bad "store create failed"

# --- a kernel package: /stand/k46/unix + its C2-3 sidecar ---
sha()  { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }
PIN=gcc-2.7.2.3-8949028
mkkernel() {   # mkkernel <dir> <sidecar kabi>
    mkdir -p "$1"
    head -c 700000 /dev/urandom > "$1/unix"
    cat > "$1/kabi" <<EOF
kabi=$2
family=KD060-A
line=k46
pin=$PIN
build=68060-260928-52
size=$(size "$1/unix")
sha256=$(sha "$1/unix")
loader-min=1
root=zorro:0202:54
rootfs=ufs
EOF
}
mkds() {       # mkds <out> <pkginst> <payload dir>   (tests/mkds.py)
    printf 'DIR /stand\nDIR /stand/k46\nCOPY /stand/k46/unix %s/unix\nCOPY /stand/k46/kabi %s/kabi\n' "$3" "$3" \
        | python3 "$SRC/tests/mkds.py" "$1" "$2" 1.0
}
mkkernel "$WORK/k1" static
mkds "$WORK/repo/pkgs/kernel/kernel-kd060a-1.1.0.pkg" KERNKD60 "$WORK/k1"
mkkernel "$WORK/k2" k46.1.0           # sidecar disagrees with the catalog
mkds "$WORK/repo/pkgs/kernel/kernel-kd060a-1.1.1.pkg" KERNKD60 "$WORK/k2"
mkkernel "$WORK/k3" static
mkds "$WORK/repo/pkgs/kernel/kernel-kd060a-1.1.2.pkg" KERNKD60 "$WORK/k3"
kl() { f=kernel/kernel-kd060a-$1.pkg
    printf '#kpkg kernel-kd060a %s role=kernel line=k46 kabi=static pin=%s size=%s sha256=%s file=%s\n' \
        "$1" $PIN "$(size "$WORK/repo/pkgs/$f")" "$(sha "$WORK/repo/pkgs/$f")" "$f"; }
mkcat() { printf '#apkg-catalog 1\n#ext kpkg 1\n%s\n#end kpkg\n' "$(kl "$1")" > "$WORK/repo/catalog"; }

# the pkgadd stand-in: copies the payload into the target and writes the
# SVR4 contents lines a real pkgadd -R writes (paths as the target sees them)
cat > "$WORK/bin/pkgadd" <<'EOF'
#!/bin/sh
T=; F=; I=
while [ $# -gt 0 ]; do
    case "$1" in -R) T=$2; shift 2 ;; -d) F=$2; shift 2 ;; -a) shift 2 ;;
    -n) shift ;; *) I=$1; shift ;; esac
done
C=$T/var/sadm/install/contents; touch $C
grep -v " $I\$" $C > $C.t; mv $C.t $C
mkdir -p $T/var/sadm/pkg/$I; echo "PKG=$I" > $T/var/sadm/pkg/$I/pkginfo
echo "/stand d none 0755 root sys $I" >> $C
echo "/stand/k46 d none 0755 root sys $I" >> $C
sed -n 's/^COPY //p' $F | while read p h; do
    mkdir -p $(dirname $T$p); cp $h $T$p
    echo "$p f none 0644 root sys $(wc -c < $T$p) 1 1 $I" >> $C; done
EOF
# kbootset as the box would see it, plus the host-build facts: apkg calls
# "<this> -R <t> --journal <j> build|commit"
cat > "$WORK/bin/kbootset" <<EOF
#!/bin/sh
n=\$#; i=0; opts=
for a; do i=\$((i + 1)); if [ \$i -eq \$n ]; then cmd=\$a; else opts="\$opts \$a"; fi; done
echo "kbootset\$opts \$cmd" >> $WORK/kb.log
if [ "\$cmd" = build ]; then
    exec $KB \$opts --image $IMG --offset 65536 build --line 46 \
        --bootdev zorro:0202:54 --rootdev zorro:0202:54 --rootfs ufs --mem 16777216 \
        --root "sd id=02025400 base=00000000 unit=6 slice=1"
fi
exec $KB \$opts --image $IMG --offset 65536 \$cmd
EOF
chmod +x "$WORK/bin/pkgadd" "$WORK/bin/kbootset"
cat > "$WORK/apkg.conf" <<EOF
repo=file://$WORK/repo
cachedir=$WORK/cache
pkgadd=$WORK/bin/pkgadd
pkgrm=/bin/false
admin=$WORK/admin
kbootset=$WORK/bin/kbootset
EOF
unset APKG_ROOT
A() { "$APKG" -c "$WORK/apkg.conf" -R "$T" "$@"; }

mkcat 1.1.0; A update >/dev/null 2>&1
OUT=$(A install kernel-kd060a 2>&1); rc=$?
[ $rc -eq 0 ] && ok "apkg installs the kernel and the real kbootset builds + commits (rc 0)" \
    || bad "first install through the real kbootset (rc=$rc)" "$OUT"
echo "$OUT" | grep -q "^apkg: generation 1 .*" \
    && ok "apkg repeats kbootset's last line: $(echo "$OUT" | grep '^apkg: generation')" \
    || bad "no generation line repeated" "$OUT"
grep -q "^file /stand/k46/unix $(size "$T/stand/k46/unix") $(sha "$T/stand/k46/unix")$" \
    "$T/var/apkg/kpkg/kernel-kd060a" && ok "the record gate 1 accepted names /stand/k46/unix by size and sha256" \
    || bad "record content" "$(cat "$T/var/apkg/kpkg/kernel-kd060a")"
"$KB" --image "$IMG" --offset 65536 status > "$WORK/st1" 2>&1
grep -q "generation 1 " "$WORK/st1" && ok "the store holds generation 1" \
    || bad "store after the first install" "$(cat "$WORK/st1")"

# gate 2: the record's kabi (the catalog's: static) against a sidecar that
# says k46.1.0 -> status 4, apkg exit 7, the gate's line passed on
mkcat 1.1.1; A update >/dev/null 2>&1
OUT=$(A upgrade kernel-kd060a 2>&1); rc=$?
[ $rc -eq 7 ] && echo "$OUT" | grep -q "refused at a gate (status 4): .*gate 2" && \
echo "$OUT" | grep -q "the committed generation is unchanged" \
    && ok "a real gate 2 refusal maps to apkg exit 7 and passes the gate's line on" \
    || bad "gate-2 mapping (rc=$rc)" "$OUT"
"$KB" --image "$IMG" --offset 65536 status > "$WORK/st2" 2>&1
cmp -s "$WORK/st1" "$WORK/st2" && ok "the refused build left the store as it was" \
    || bad "store changed after a refusal" "$(diff "$WORK/st1" "$WORK/st2")"

# gate 1: a member changed by hand after apkg recorded it
mkcat 1.1.2; A update >/dev/null 2>&1
OUT=$(A upgrade kernel-kd060a 2>&1); rc=$?
[ $rc -eq 0 ] && ok "the next good upgrade commits again (rc 0)" || bad "upgrade (rc=$rc)" "$OUT"
printf 'X' | dd of="$T/stand/k46/unix" bs=1 seek=1000 conv=notrunc 2>/dev/null
OUT=$("$WORK/bin/kbootset" -R "$T" --journal "$T/var/kbootset/journal" build 2>&1); rc=$?
[ $rc -eq 4 ] && echo "$OUT" | grep -q "gate 1" \
    && ok "kbootset gate 1 refuses a member that no longer matches apkg's record" \
    || bad "gate 1 against a hand-changed member (rc=$rc)" "$OUT"

echo
echo "== kbootset consumer: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
