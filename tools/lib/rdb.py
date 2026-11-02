# tools/lib/rdb.py -- read an Amix RDB the way the Amix SCSI driver reads it.
#
# THE ONE RULE THIS FILE EXISTS TO ENCODE
# ---------------------------------------
# The Amix SCSI disk driver amiga/alien/sdpart.c assigns
#
#       slice N  =  the Nth PART block in the RDB PartitionList, 1-based
#
# (slice 0 is the whole unmapped device). Nothing else determines the slice
# number. In particular the DosType's 4th byte is NOT the slice number: the BOOT
# partition is 'UNI\0' (0x554e4900) and yet lives at slice 3, because the stock
# installer adds Root, then Swap, then Boot, in that order.
#
# Therefore THE PARTITION LIST ORDER *IS* THE SLICE MAP, and the swap partition
# is STRUCTURALLY LOAD-BEARING even on media that never swaps: remove it and the
# boot partition silently becomes slice 2, so every c0d0s3 reference on the
# medium (and in the kernel's rootdev) points at the wrong extent. Do not
# "clean up" the swap entry, do not reorder, do not omit.
#
# Confirmed against a genuine Commodore-installed disk -- the RDB of
# ../amix-images/masters/amix-z3660-metal-golden-2026-07-15.hdf reads:
#       slice 1 'UNIX_Root' dostype 0x554e4901
#       slice 2 'UNIX_Swap' dostype 0x72657376
#       slice 3 'UNIX_Boot' dostype 0x554e4900  flags bootable
# and against the stock install script recovered from floppies/orig/amix_21_root.adf,
# which adds them in exactly that sequence:
#       /etc/rdb -a $DISK UNIX_Root $OFFSET $ROOTLEN
#       /etc/rdb -a $DISK UNIX_Swap $OFFSET $SWAPLEN
#       /etc/rdb -a $DISK UNIX_Boot $OFFSET $BOOTLEN
#
# GEOMETRY. A partition's byte offset comes from its OWN Disk-Environment vector,
# never from a constant and never from the RDB header's geometry:
#       byte_off = DE_LowCyl * (DE_Surfaces * DE_BlocksPerTrack) * (DE_SizeBlock * 4)
# The RDB-level heads/sectors usually agree, and read_rdb() NOTES on stderr when
# they do not -- but it never REFUSES on that ground: the DE vector is the
# authority, it is what sdpart.c uses, and byte_offset below computes from it.
# (A hard raise here would fail-close on images sdpart.c reads without complaint,
# and read_rdb has no signature-scan fallback the way build-source-hdf.sh does --
# mkroot's read-back gate and write-bootchain's donor walk would simply stop.)
# Hardcoding an offset observed in one image is a bug waiting for a
# differently-sized disk: the UNI\0 boot slice sits at 0x6110000 in the 100 MB
# metal golden and at 0x25510600 in the 600 MB one.
#
# SCOPE. Read-only, structural. This module does not author RDBs (tools/mkroot.sh
# drives rdbtool for that) and knows nothing about boot chains or filesystems.
#
# INDEPENDENCE. ../amix-kerntools/tools/bootchain-verify.py contains its OWN
# PartitionList walk. That duplication is deliberate and is the whole point of the
# round-trip gate: our builders locate the boot slice with THIS code, and the
# sibling's verifier then locates it again with its own. A slice-map defect that
# this file gets wrong would have to be got wrong identically over there to slip
# through. Never "de-duplicate" the two.
#
# Stdlib-only, python3. Ships no proprietary bytes.

import struct
import sys

# --- DosTypes we care about (RDB-level; not part of the boot-chain contract) ---
DT_ROOT = 0x554e4901        # 'UNI\1' -- a UNIX root/filesystem slice
DT_BOOT = 0x554e4900        # 'UNI\0' -- the bootable bootstrap slice
DT_SWAP = 0x72657376        # 'resv'  -- swap / reserved
DT_DATA = 0x44415441        # 'DATA'  -- a raw, non-filesystem data slice

FLAG_BOOTABLE = 1           # PART pb_Flags bit 0
FLAG_NOMOUNT  = 2           # PART pb_Flags bit 1 (set => do NOT automount)

# PART block field offsets (big-endian, 512-byte block)
_PB_NEXT   = 16             # pb_Next            (block number of the next PART)
_PB_FLAGS  = 20             # pb_Flags
_PB_NAME   = 36             # pb_DriveName, a BSTR: length byte then chars
_PB_DE     = 128            # start of the DosEnvec (DE_*) longword array

# DosEnvec indices (longwords from _PB_DE)
DE_SIZEBLOCK      = 1       # block size in LONGWORDS (128 => 512 bytes)
DE_SURFACES       = 3
DE_BLOCKSPERTRACK = 5
DE_LOWCYL         = 9
DE_HIGHCYL        = 10
DE_DOSTYPE        = 16

MAX_PARTS = 16              # sdpart.c stops long before this; a loop guard


class RdbError(Exception):
    """Structural defect in an RDB. Callers should fail closed on it."""


class Slice(object):
    """One PART block, presented as the driver sees it."""

    __slots__ = ("slot", "name", "dostype", "flags", "low_cyl", "high_cyl",
                 "cyl_blocks", "block_bytes", "part_block")

    def __init__(self, slot, name, dostype, flags, low_cyl, high_cyl,
                 cyl_blocks, block_bytes, part_block):
        self.slot = slot                  # 1-based slice number == list position
        self.name = name
        self.dostype = dostype
        self.flags = flags
        self.low_cyl = low_cyl
        self.high_cyl = high_cyl
        self.cyl_blocks = cyl_blocks      # surfaces * blocks_per_track
        self.block_bytes = block_bytes    # size_block * 4
        self.part_block = part_block      # where this PART block itself lives

    @property
    def byte_offset(self):
        """First byte of the slice, from this partition's OWN DE geometry."""
        return self.low_cyl * self.cyl_blocks * self.block_bytes

    @property
    def byte_size(self):
        """Extent in bytes; LowCyl..HighCyl is INCLUSIVE."""
        return (self.high_cyl - self.low_cyl + 1) * self.cyl_blocks * self.block_bytes

    @property
    def bootable(self):
        return bool(self.flags & FLAG_BOOTABLE)

    @property
    def automount(self):
        return not (self.flags & FLAG_NOMOUNT)

    def dostype_str(self):
        b = struct.pack('>I', self.dostype)
        return "".join(chr(c) if 32 <= c < 127 else "\\%d" % c for c in b)

    def __repr__(self):
        return ("slice %d: %-12r dostype=0x%08x (%s) flags=0x%x cyl %d..%d "
                "base=0x%x size=%d"
                % (self.slot, self.name, self.dostype, self.dostype_str(),
                   self.flags, self.low_cyl, self.high_cyl,
                   self.byte_offset, self.byte_size))


def _u32(b, o):
    return struct.unpack('>I', b[o:o+4])[0]


def find_rdsk(img, limit=64):
    """Block number of the RDSK header, or None.

    READING scans: images in the wild carry it at block 2 (everything the stock
    `/etc/rdb -c -L 2` authored onto a blank disk -- the metal goldens, the demo
    cards), so scan, exactly as sdpart.c and kerntools' rdb-verify.sh do. What we
    PRODUCE is pinned by check_rdsk_location() below: block 0.
    """
    for b in range(limit):
        if img[b*512:b*512+4] == b'RDSK':
            return b
    return None


def read_rdb(img):
    """Walk the PartitionList and return (rdsk_block, [Slice, ...]).

    The returned list is IN PARTITIONLIST ORDER, which is the slice map: index i
    holds slice i+1. Raises RdbError on any structural defect -- a partial or
    guessed slice map is worse than none, because it silently mislabels extents.
    """
    rblk = find_rdsk(img)
    if rblk is None:
        raise RdbError("no RDSK block in the first 64 blocks (not an Amix RDB image?)")
    rdb = img[rblk*512:(rblk+1)*512]

    rdb_secs = _u32(rdb, 68)          # rdb_Sectors
    rdb_heads = _u32(rdb, 72)         # rdb_Heads
    rdb_cylblk = rdb_heads * rdb_secs

    slices = []
    a = _u32(rdb, 28)                 # rdb_PartitionList
    seen = set()
    slot = 1
    while a != 0xffffffff and slot <= MAX_PARTS:
        if a in seen:
            raise RdbError("PartitionList loops at block %d -- corrupt RDB" % a)
        seen.add(a)
        if (a + 1) * 512 > len(img):
            raise RdbError("PartitionList block %d is past the end of the image "
                           "(%d bytes) -- truncated RDB" % (a, len(img)))
        pb = img[a*512:(a+1)*512]
        if pb[:4] != b'PART':
            raise RdbError("PartitionList entry %d (block %d) is not a PART block "
                           "(got %r)" % (slot, a, pb[:4]))

        de = lambda i: _u32(pb, _PB_DE + i*4)
        block_bytes = de(DE_SIZEBLOCK) * 4
        cyl_blocks = de(DE_SURFACES) * de(DE_BLOCKSPERTRACK)
        if block_bytes == 0 or cyl_blocks == 0:
            raise RdbError("slice %d has degenerate geometry "
                           "(block_bytes=%d cyl_blocks=%d)"
                           % (slot, block_bytes, cyl_blocks))
        if rdb_cylblk and cyl_blocks != rdb_cylblk:
            # NOT fatal -- the DE vector is the authority and sdpart.c uses it, so
            # byte_offset below is already correct. A mismatch only means the two
            # geometries in the image disagree about what a cylinder is; it is
            # worth surfacing (a differently-authored donor, say) but refusing here
            # would hard-fail a legitimate image that the driver reads fine, and
            # this module's callers (mkroot's read-back gate, write-bootchain's
            # donor walk) have no fallback. Note it and carry on with the DE vector.
            sys.stderr.write("rdb: note: slice %d DE geometry (%d blocks/cyl) "
                             "disagrees with the RDSK header (%d blocks/cyl); using "
                             "the DE vector, as sdpart.c does\n"
                             % (slot, cyl_blocks, rdb_cylblk))

        nl = pb[_PB_NAME]
        name = pb[_PB_NAME+1:_PB_NAME+1+nl].decode('latin1')

        slices.append(Slice(slot, name, de(DE_DOSTYPE), _u32(pb, _PB_FLAGS),
                            de(DE_LOWCYL), de(DE_HIGHCYL),
                            cyl_blocks, block_bytes, a))
        slot += 1
        a = _u32(pb, _PB_NEXT)

    if not slices:
        raise RdbError("RDB has an empty PartitionList -- no slices at all")
    return rblk, slices


def find_boot_slice(img):
    """The UNI\\0 boot Slice, or None. First match in PartitionList order."""
    _, slices = read_rdb(img)
    for s in slices:
        if s.dostype == DT_BOOT:
            return s
    return None


# ----------------------------------------------------------------------------
# WHERE THE RDSK BLOCK LIVES -- the production policy (2026-09-26)
# ----------------------------------------------------------------------------
# Every medium this repo PRODUCES carries its RDSK at block 0 (LBA 0).
#
# Why: stock Z3660 firmware (upstream piscsi_parse_rdb) reads the image in 64 KB
# strides and tests the first 4 bytes of each read, so it can only ever find an
# RDB at byte 0 (Z3660 docs/rdb-location-policy.md s.2). An RDSK at block 2 --
# the stock Amix `/etc/rdb -c -L 2` placement -- is "No RDB found" there; only
# the fork firmware's blocks-1..15 scan finds it. Blocks 0-1 carry nothing on an
# Amix disk (the boot chain is in the UNI\0 slice, located through the RDB),
# and every other reader -- Kickstart, sdpart.c, /etc/rdb, find_rdsk() above --
# scans 0..15, so block 0 boots everywhere block 2 does.
#
# The gate is positional AND exclusive: RDSK at block 0, no second RDSK anywhere
# in 1..15 (a stale copy -- the 2026-08-25 F4-M2 workaround left one -- makes the
# answer depend on who scans how), and a closing checksum.
RDSK_BLOCK_DEFAULT = 0       # what we produce
RDSK_BLOCK_LEGACY = 2        # stock `/etc/rdb -c -L 2` on a blank disk
RDB_LOCATION_LIMIT = 16      # the RDB spec's own scan limit (blocks 0..15)


def rdsk_blocks(img, limit=RDB_LOCATION_LIMIT):
    """Every block in 0..limit-1 whose first four bytes are the RDSK magic."""
    return [b for b in range(limit) if img[b*512:b*512+4] == b'RDSK']


def block_checksum_ok(block):
    """Standard RDB block checksum: the first SummedLongs longwords sum to 0."""
    n = _u32(block, 4)
    if n < 2 or n * 4 > len(block):
        return False
    return (sum(struct.unpack('>%dI' % n, block[:n*4])) & 0xffffffff) == 0


def check_rdsk_location(img, want=RDSK_BLOCK_DEFAULT):
    """Problems with WHERE the RDSK lives; empty list == conforming.

    Every rule is evaluated so the caller gets the whole diagnosis at once."""
    problems = []
    found = rdsk_blocks(img)
    if not found:
        return ["no RDSK block in blocks 0..%d" % (RDB_LOCATION_LIMIT - 1)]
    if found[0] != want:
        why = (" -- stock Z3660 firmware finds an RDB ONLY at block 0 (64 KB-stride "
               "scan); re-lay it with tools/relay-rdb-lba0.py" if want == 0 else "")
        problems.append("RDSK is at block %d, expected block %d%s"
                        % (found[0], want, why))
    if len(found) > 1:
        problems.append("more than one RDSK in blocks 0..%d (at %s) -- a stale copy "
                        "makes the partition authority depend on who scans how"
                        % (RDB_LOCATION_LIMIT - 1, found))
    for b in found:
        if not block_checksum_ok(img[b*512:(b+1)*512]):
            problems.append("RDSK at block %d: checksum does not close" % b)
    return problems


# ----------------------------------------------------------------------------
# The slice-map contract check
# ----------------------------------------------------------------------------
# EXPECTED_MAP is the stock Amix install layout, in the stock install script's
# own order. It is a positional assertion, not a set membership test: checking
# only that "a boot partition exists somewhere" is exactly the mistake this
# module exists to prevent.
EXPECTED_MAP = (
    (1, DT_ROOT, "root filesystem"),
    (2, DT_SWAP, "swap  -- STRUCTURAL: without it BOOT lands on slice 2"),
    (3, DT_BOOT, "bootstrap (UNI\\0, bootable)"),
)


def check_slice_map(slices, expected=EXPECTED_MAP, require_bootable=True):
    """Return a list of human-readable problems; empty list == conforming.

    Positional, in PartitionList order. Every rule is evaluated (we never stop at
    the first failure) so a caller gets the whole diagnosis at once.
    """
    problems = []
    by_slot = {s.slot: s for s in slices}

    if len(slices) < len(expected):
        problems.append("only %d partition(s); the Amix slice map needs at least %d "
                        "(root, swap, boot)" % (len(slices), len(expected)))

    for slot, want_dt, what in expected:
        s = by_slot.get(slot)
        if s is None:
            problems.append("slice %d missing -- expected %s (DosType 0x%08x)"
                            % (slot, what, want_dt))
            continue
        if s.dostype != want_dt:
            extra = ""
            if want_dt == DT_SWAP and s.dostype == DT_BOOT:
                extra = ("  <-- BOOT has landed on slice 2. The swap placeholder is "
                         "missing or the partitions were added in the wrong order; "
                         "the swap entry is what pushes BOOT to slice 3.")
            problems.append("slice %d is DosType 0x%08x (%s), expected 0x%08x -- %s%s"
                            % (slot, s.dostype, s.dostype_str(), want_dt, what, extra))

    boot = by_slot.get(3)
    if require_bootable and boot is not None and boot.dostype == DT_BOOT \
            and not boot.bootable:
        problems.append("slice 3 is UNI\\0 but its bootable flag is clear -- the "
                        "Kickstart 2.04 boot menu will not offer it")
    return problems


def format_map(slices):
    """The slice map, rendered the way sdpart.c would number it."""
    out = ["  slice map (sdpart.c order == PartitionList order):"]
    for s in slices:
        out.append("    " + repr(s))
    return "\n".join(out)
