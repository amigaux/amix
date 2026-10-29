#!/bin/sh
# kbox.sh -- kbootset on the "running box" (docs/plan/stage-2.md S2-06), on
# the host: a kinfo record (docs/contracts/C2-1-kinfo.md) and raw disks are
# files under a directory that KBOOTSET_KINFO and KBOOTSET_DEVROOT point
# kbootset at.  Covered: finding the store through the loader record and
# the card table; through bootset's store= on the next run; by scanning
# every disk when the controller is missing from the card table (the A3000
# case); gate 9 (two UNI\0 slices on the boot disk) and gate 8 (stores on
# two disks); the facts from kinfo; mark-good's defaults from kinfo.
# Run from the repository root after `make tools` and store-roundtrip.sh.
set -e
B=${B:-build}
T=$B/kbox
rm -rf $T && mkdir -p $T/dev $T/root/etc/default $T/root/stand/k46 $T/root/stand/k30 $T/root/var/apkg/kpkg
R=$T/root
export KBOOTSET_DEVROOT=$T/dev KBOOTSET_KINFO=$T/kinfo

# disk.py: an RDB disk (RDSK at block 0; cylinders of 32 blocks of 512) with
# the given partitions, and a kinfo record
cat > $T/disk.py <<'EOF'
import struct, sys
def rdb(path, parts):            # parts: [(dostype, lowcyl, highcyl)]
    img = bytearray(64 * 512)
    r = bytearray(512); r[0:4] = b'RDSK'
    struct.pack_into('>I', r, 28, 1)                  # rdb_PartitionList: block 1
    struct.pack_into('>II', r, 68, 32, 1)             # sectors, heads
    img[0:512] = r
    for i, (dt, lo, hi) in enumerate(parts):
        p = bytearray(512); p[0:4] = b'PART'
        struct.pack_into('>I', p, 16, i + 2 if i + 1 < len(parts) else 0xffffffff)
        de = 128
        struct.pack_into('>I', p, de + 4, 128)        # de_SizeBlock (longs)
        struct.pack_into('>I', p, de + 12, 1)         # de_Surfaces
        struct.pack_into('>I', p, de + 20, 32)        # de_BlocksPerTrack
        struct.pack_into('>II', p, de + 36, lo, hi)   # de_LowCyl, de_HighCyl
        struct.pack_into('>I', p, de + 64, dt)        # de_DosType
        img[(i + 1) * 512:(i + 2) * 512] = p
    open(path, 'wb').write(img)
def kinfo(path, cards, axl1, fast=16777184, mods=(), safe=False):
    r = bytearray(540 + 32 * len(mods))
    struct.pack_into('>II', r, 0, 0x4b494631, (2 << 16) | len(r))
    struct.pack_into('>III', r, 12, 60, 46, 0x000f)
    r[24:30] = b'static'; r[48:63] = b'68060-261025-50'
    flags = 2
    if axl1:
        flags |= 1
        gen, choice, unit, start, base, did, rid = axl1[:7]
        a = 84
        struct.pack_into('>I', r, a, 0x41584c31)
        struct.pack_into('>IIIIII', r, a + 12, 1, choice, 60, 0xf, gen, 2)
        struct.pack_into('>IIIII', r, a + 44, unit, start, base, did, 0)
        struct.pack_into('>IIIII', r, a + 60, 1, rid, 0, 6, 1)
        r[a + 100:a + 103] = b'ufs'
        s = sum(struct.unpack('>31I', r[a:a + 124])) & 0xffffffff
        struct.pack_into('>I', r, a + 8, (-s) & 0xffffffff)
    if axl1 and len(axl1) > 7:                         # the boot device's name CRC
        struct.pack_into('>I', r, a + 40, axl1[7])
    if axl1 and len(axl1) > 8:                         # AXL1's flags (0x04 fallback, 0x02 menu)
        struct.pack_into('>I', r, a + 36, axl1[8])
    if axl1 and len(axl1) > 7:
        struct.pack_into('>I', r, a + 8, 0)
        s = sum(struct.unpack('>31I', r[a:a + 124])) & 0xffffffff
        struct.pack_into('>I', r, a + 8, (-s) & 0xffffffff)
    struct.pack_into('>I', r, 80, flags | (4 if safe else 0))
    struct.pack_into('>I', r, 460, len(cards))
    for i, (k, cid, base, fl) in enumerate(cards):
        struct.pack_into('>IIII', r, 464 + 16 * i, k, cid, base, fl)
    struct.pack_into('>II', r, 528, fast, 2097152)
    struct.pack_into('>I', r, 536, len(mods))
    for i, m in enumerate(mods):                       # name, address, size
        r[540 + 32 * i:540 + 32 * i + len(m)] = m.encode()
        struct.pack_into('>II', r, 540 + 32 * i + 24, 0x08300000 + 0x10000 * i, 4096)
    s = sum(struct.unpack('>%dI' % (len(r) // 4), r)) & 0xffffffff
    struct.pack_into('>I', r, 8, (-s) & 0xffffffff)
    open(path, 'wb').write(r)
if sys.argv[1] == 'rdb':
    rdb(sys.argv[2], [tuple(int(x, 0) for x in p.split(',')) for p in sys.argv[3:]])
else:
    cards = [tuple(int(x, 0) for x in c.split(',')) for c in sys.argv[4].split('/') if c]
    axl1 = tuple(int(x, 0) for x in sys.argv[3].split(',')) if sys.argv[3] != '-' else None
    mods = sys.argv[5].split(',') if len(sys.argv) > 5 and sys.argv[5] else ()
    kinfo(sys.argv[2], cards, axl1, mods=mods, safe=len(sys.argv) > 6 and sys.argv[6] == 'safe')
EOF
UNI1=0x554e4901 UNI0=0x554e4900 RESV=0x72657376
START=$((150 * 32 * 512))		# slice 3 starts at cylinder 150
python3 -I $T/disk.py rdb $T/dev/c6d0s0 $UNI1,10,99 $RESV,100,149 $UNI0,150,849
head -c $((700 * 32 * 512)) /dev/zero > $T/dev/c6d0s3
$B/kbootset --dev $T/dev/c6d0s3 create $((700 * 32 * 512)) $B/rt/boot2.bin >/dev/null
A4091=0x02025400
python3 -I $T/disk.py kinfo $T/kinfo 1,0,6,$START,0x40000000,$A4091,$A4091 0,$A4091,0x40000000,0

# 1. the loader record through the card table: no --dev needed
$B/kbootset -R $R status > $T/out
grep -q "booted: generation 1, by the primary loader; kernel 68060-261025-50, 68060" $T/out
grep -q "facts: line k46, boot zorro:0202:54, root zorro:0202:54, rootfs ufs, fast memory 16777184" $T/out
grep -q "^store=$T/dev/c6d0s3$" $R/etc/default/bootset
grep -q "^store-id=" $R/etc/default/bootset
# status prints the set id that bootset records
[ "$(sed -n 's/^store-id: //p' $T/out)" = "$(sed -n 's/^store-id=//p' $R/etc/default/bootset)" ]
# 2. the next run takes bootset's store= (the whole-disk node is not read)
mv $T/dev/c6d0s0 $T/c6d0s0.away
$B/kbootset -R $R status > /dev/null
mv $T/c6d0s0.away $T/dev/c6d0s0
# a different store under the same name is noticed: found again
cp $T/dev/c6d0s3 $T/s3.keep
$B/kbootset --dev $T/dev/c6d0s3 create $((700 * 32 * 512)) $B/rt/boot1.img --force >/dev/null
sed -i 's/^store-id=.*/store-id=00000001/' $R/etc/default/bootset
$B/kbootset -R $R status > /dev/null
! grep -q "^store-id=00000001$" $R/etc/default/bootset
cp $T/s3.keep $T/dev/c6d0s3

# 3. the facts come from kinfo: build needs no options
sha() { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }
head -c 500000 /dev/urandom > $R/stand/k46/unix
cat > $R/stand/k46/kabi <<EOF2
kabi=static
line=k46
pin=gcc-2.7.2.3-8949028
size=$(size $R/stand/k46/unix)
sha256=$(sha $R/stand/k46/unix)
loader-min=1
root=zorro:0202:54
rootfs=ufs
EOF2
cat > $R/var/apkg/kpkg/kernel-kd060a <<EOF2
name kernel-kd060a
kabi static
pin gcc-2.7.2.3-8949028
verified no
file /stand/k46/unix $(size $R/stand/k46/unix) $(sha $R/stand/k46/unix)
file /stand/k46/kabi $(size $R/stand/k46/kabi) $(sha $R/stand/k46/kabi)
EOF2
$B/kbootset -R $R build --root "sd id=02025400 base=40000000 unit=6 slice=1" | grep -q "generation 1 built"
$B/kbootset -R $R commit 2>/dev/null | grep -q "pristine"
$B/kbootset -R $R build | grep -q "generation 2 built"
# the same package as generation 1: --again, or commit would write nothing (C2-4 §3)
$B/kbootset -R $R commit --again 2>/dev/null | grep -q "generation 2 committed"
[ -d $R/var/kbootset ] && [ -z "$(cat $R/var/kbootset/journal 2>/dev/null)" ]	# made by kbootset
# 4. mark-good with no options: kinfo says generation 2 booted by the primary
python3 -I $T/disk.py kinfo $T/kinfo 2,0,6,$START,0x40000000,$A4091,$A4091 0,$A4091,0x40000000,0
$B/kbootset -R $R mark-good | grep -q "generation 2 is good and the default"

# 4a. the loader fell back from the default (AXL1 flag 0x04) to the
# pristine generation: mark-good verifies the default, generation 2, and
# its intact members keep it; a fallback the menu chose is not judged
python3 -I $T/disk.py kinfo $T/kinfo 1,0,6,$START,0x40000000,$A4091,$A4091,0,4 0,$A4091,0x40000000,0
$B/kbootset -R $R mark-good > $T/out
grep -q "generation 1 is pristine; nothing to mark; the loader passed over the default, generation 2, but its members verify: it stays the default" $T/out ||
	{ echo "kbox: the fallback boot did not verify the default" >&2; cat $T/out >&2; exit 1; }
python3 -I $T/disk.py kinfo $T/kinfo 1,0,6,$START,0x40000000,$A4091,$A4091,0,6 0,$A4091,0x40000000,0
$B/kbootset -R $R mark-good > $T/out
! grep -q "passed over" $T/out

# 4b. retry: the trial's boot ended in the base system's fsck-repair
# reboot; with the root read-only, retry gives its attempt back and the
# next loader run takes the trial again
$B/kbootset -R $R build | grep -q "generation 3 built"
# committed as apkg calls it, a named journal whose directory is missing
rm -rf $R/var/kbootset
$B/kbootset -R $R --journal $R/var/kbootset/journal commit --again 2>/dev/null | grep -q "generation 3 committed"
[ -d $R/var/kbootset ] && [ -z "$(cat $R/var/kbootset/journal 2>/dev/null)" ]
$B/axsim $(sed -n 's/^store=//p' $R/etc/default/bootset) 0 1 | grep -q "generation 3, kernel"
python3 -I $T/disk.py kinfo $T/kinfo 3,0,6,$START,0x40000000,$A4091,$A4091 0,$A4091,0x40000000,0
chmod a-w $R/etc/default $R/var/kbootset
$B/kbootset -R $R retry > $T/out
chmod u+w $R/etc/default $R/var/kbootset
grep -q "generation 3 gets its trial boot again" $T/out
$B/axsim $(sed -n 's/^store=//p' $R/etc/default/bootset) 0 1 | grep -q "generation 3, kernel"

# 4c. a kernel without kinfo (a 1.0 kernel): retry does nothing and says
# nothing, as bcheckrc expects; mark-good refuses and names --booted
set +e
KBOOTSET_KINFO=$T/no-kinfo $B/kbootset -R $R retry > $T/out; rc=$?
[ $rc -eq 0 ] && [ ! -s $T/out ] || { echo "kbox: retry without kinfo: $rc"; exit 1; }
KBOOTSET_KINFO=$T/no-kinfo $B/kbootset -R $R mark-good > $T/out; rc=$?
set -e
[ $rc -eq 3 ] && grep -q "which generation booted is unknown" $T/out

# 5. the controller missing from the card table (the A3000 case): the
# loader record maps to no card, so every disk is scanned
python3 -I $T/disk.py kinfo $T/kinfo 2,0,6,$START,0,0,0 ""
rm -f $R/etc/default/bootset
$B/kbootset -R $R status > $T/out
grep -q "^store=$T/dev/c6d0s3$" $R/etc/default/bootset

# 5b. the Z3660 shape (port evidence dlm-1): the BootNode names no
# ConfigDev, so AXL1's boot device is base 0 / id 0, and the card table
# holds only the Z3660 card: the scan finds the store, and the boot
# controller is the card of the disk it is on
Z3660=0x144b0100
python3 -I $T/disk.py kinfo $T/kinfo 2,0,6,$START,0,0,$Z3660 0,$Z3660,0x40000000,0
rm -f $R/etc/default/bootset
$B/kbootset -R $R status > $T/out
grep -q "facts: line k46, boot zorro:144b:01, root zorro:144b:01, rootfs ufs" $T/out

# 6. gate 9: a second UNI\0 slice on the boot disk
python3 -I $T/disk.py kinfo $T/kinfo 2,0,6,$START,0x40000000,$A4091,$A4091 0,$A4091,0x40000000,0
python3 -I $T/disk.py rdb $T/dev/c6d0s0 $UNI1,10,99 $RESV,100,149 $UNI0,150,849 $UNI0,850,900
rm -f $R/etc/default/bootset
set +e
$B/kbootset -R $R status > $T/out; rc=$?
set -e
[ $rc -eq 4 ] && grep -q "gate 9" $T/out
python3 -I $T/disk.py rdb $T/dev/c6d0s0 $UNI1,10,99 $RESV,100,149 $UNI0,150,849

# 6b. status lists the booted generation's modules, marked from kinfo's
# list of the loaded ones (C3-5 section 5)
Z64=0000000000000000000000000000000000000000000000000000000000000000
cat > $T/mods.spec <<EOF2
line k46
kabi k46.1.0
rootfs ufs
root sd id=02025400 base=40000000 unit=6 slice=1
kernel unix $R/stand/k46/unix
module z3660eth boot 100 path=/stand/gen/9/mod/z3660eth sha256=$Z64 match=always
module monsw demand 100 path=/stand/gen/9/mod/monsw sha256=$Z64 majors=c:52
module z3660rtg demand 100 path=/stand/gen/9/mod/z3660rtg sha256=$Z64 majors=c:49 depend=monsw
EOF2
g=$($B/kbootset -R $R commit --spec $T/mods.spec 2>/dev/null | sed -n 's/^kbootset: generation \([0-9]*\) committed.*/\1/p')
[ -n "$g" ] || { echo "kbox: the module generation was not committed"; exit 1; }
python3 -I $T/disk.py kinfo $T/kinfo $g,0,6,$START,0x40000000,$A4091,$A4091 0,$A4091,0x40000000,0 z3660eth,monsw
$B/kbootset -R $R status > $T/out
grep -qx "module z3660eth (boot): loaded" $T/out
grep -qx "module monsw (demand): loaded" $T/out
grep -qx "module z3660rtg (demand): not loaded (loads at the first open of its device)" $T/out
# 6b'. a safe boot (kinfo flag 0x4) names the safe set it keeps, the
# records marked safe=1, and says why the others did not load (C2-4 §11):
# a4091 ranked before the root's card loads, as N160 saw
sed -e 's|^module z3660eth boot \(.*\)$|module z3660eth boot \1 safe=1|' $T/mods.spec > $T/safe.spec
gs=$($B/kbootset -R $R commit --spec $T/safe.spec 2>/dev/null | sed -n 's/^kbootset: generation \([0-9]*\) committed.*/\1/p')
[ -n "$gs" ] || { echo "kbox: the safe generation was not committed"; exit 1; }
python3 -I $T/disk.py kinfo $T/kinfo $gs,0,6,$START,0x40000000,$A4091,$A4091 0,$A4091,0x40000000,0 z3660eth safe
$B/kbootset -R $R status > $T/out
grep -qx "modules: safe mode: only the safe set loads this boot (z3660eth)" $T/out ||
	{ echo "kbox: the safe set not named" >&2; grep -i "safe\|^module" $T/out >&2; exit 1; }
grep -qx "module z3660eth (boot): loaded" $T/out
grep -qx "module monsw (demand): not loaded (safe mode)" $T/out
grep -qx "module z3660rtg (demand): not loaded (safe mode)" $T/out
g=$($B/kbootset -R $R commit --spec $T/mods.spec 2>/dev/null | sed -n 's/^kbootset: generation \([0-9]*\) committed.*/\1/p')
python3 -I $T/disk.py kinfo $T/kinfo $g,0,6,$START,0x40000000,$A4091,$A4091 0,$A4091,0x40000000,0 "" safe
$B/kbootset -R $R status > $T/out
grep -qx "modules: safe mode: the safe set is empty; no module loads this boot" $T/out
python3 -I $T/disk.py kinfo $T/kinfo $g,0,6,$START,0x40000000,$A4091,$A4091 0,$A4091,0x40000000,0 z3660eth,monsw

# 6c. check reports the running box's disk nodes when an installed kernel
# is a four-card one (C2-4 §14), as one problem; a k30 sidecar, so the
# default generation's files keep their hashes
set +e
$B/kbootset -R $R check > $T/out; n0=$?
printf 'kabi=k30.1.2\nsdcards=4\n' > $R/stand/k30/kabi
$B/kbootset -R $R check > $T/out2
set -e
grep -qx "  nodes: 512 of the four-card set missing or wrong, 0 d1 nodes left: run kbootset nodes" $T/out2
p0=$(sed -n 's/^kbootset: check: \([0-9]*\) problem.*/\1/p' $T/out)
p1=$(sed -n 's/^kbootset: check: \([0-9]*\) problem.*/\1/p' $T/out2)
[ $((p1 - p0)) -eq 1 ] || { echo "kbox: check counted the nodes as $((p1 - p0)) problems"; exit 1; }
rm -f $R/stand/k30/kabi

# 6d. the Z3660 as one controller (C4-1 §5.1, S5-15).  An A4000 in 030
# mode: the window (id 4) and Gayle (id 2), both motherboard cards, and
# a boot disk the loader saw no board for.  The card whose disk at the
# boot unit holds a slice at AXL1's start is the boot card; with both,
# the boot device's name decides; the window's key is zorro:144b:01
crc() { python3 -I -c "import zlib, sys; print(zlib.crc32(sys.argv[1].encode()))" "$1"; }
WIN=0,4,0x10000000,1/1,2,0,1
python3 -I $T/disk.py kinfo $T/kinfo $g,0,6,$START,0,0,0 $WIN
$B/kbootset -R $R status > $T/out
grep -q "^facts: line k46, boot zorro:144b:01, root zorro:144b:01," $T/out ||
	{ echo "kbox: the window's disk not taken as the boot card" >&2; grep facts $T/out >&2; exit 1; }
cp $T/dev/c6d0s0 $T/dev/ced0s0		# Gayle's unit 6: the same RDB, so both answer
python3 -I $T/disk.py kinfo $T/kinfo $g,0,6,$START,0,0,0,$(crc z3660_scsi.device) $WIN
$B/kbootset -R $R status > $T/out
grep -q "^facts: line k46, boot zorro:144b:01, root (unknown)," $T/out ||
	{ echo "kbox: z3660_scsi.device did not pick the window" >&2; grep facts $T/out >&2; exit 1; }
python3 -I $T/disk.py kinfo $T/kinfo $g,0,6,$START,0,0,0,$(crc scsi.device) $WIN
$B/kbootset -R $R status > $T/out
grep -q "^facts: line k46, boot mobo:gayle," $T/out ||
	{ echo "kbox: scsi.device did not pick Gayle" >&2; grep facts $T/out >&2; exit 1; }
rm -f $T/dev/ced0s0
# the canonical Z3660 (id 144b0100, base 0, boot2's form of its boot
# vehicle) finds the AutoConfig'd card at its own base
python3 -I $T/disk.py kinfo $T/kinfo $g,0,6,$START,0,0x144b0100,0x144b0100 0,0x144b0100,0x10000000,0
$B/kbootset -R $R status > $T/out
grep -q "^facts: line k46, boot zorro:144b:01, root zorro:144b:01," $T/out ||
	{ echo "kbox: the canonical Z3660 did not find its card" >&2; grep facts $T/out >&2; exit 1; }

# 7. gate 8: stores on two disks, and no loader record to choose
cp $T/dev/c6d0s0 $T/dev/ced0s0
cp $T/dev/c6d0s3 $T/dev/ced0s3
python3 -I $T/disk.py kinfo $T/kinfo - ""
set +e
$B/kbootset -R $R status > $T/out; rc=$?
set -e
[ $rc -eq 4 ] && grep -q "gate 8 (boot disk): 2 disks hold a boot store" $T/out
echo "kbox: kinfo, finding the store (record, bootset, scan), gates 8 and 9, mark-good, a fallback boot's verdict, retry, status's modules, check's nodes, the Z3660 window's card, the safe set in status ok"
