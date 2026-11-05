# tools/lib/s5.py -- read and MINT an Amix s5 (System V) filesystem, host-side.
#
# WHY THIS EXISTS. tools/mkroot.sh has to hand `pkgadd -R` a mounted target root,
# which means the target slice needs a real filesystem before anything on a box
# is involved. Amix's own mkfs_s5 runs on the box; this is the host-side
# equivalent, so a target disk can be built from a blank file.
#
# HOW EVERY CONSTANT BELOW WAS ESTABLISHED -- read this before changing one.
# ------------------------------------------------------------------------
# None of this is guessed and none of it is copied from a Linux/V7 header. Every
# layout fact was READ OUT OF A GENUINE COMMODORE-MADE s5 FILESYSTEM --
# floppies/orig/amix_21_root.adf, the Amix 2.1 install miniroot, which is real
# mkfs_s5 output -- and each one is pinned by a check in selftest() that fails if
# the reader ever stops agreeing with that artifact.
#
# Two of those checks are the load-bearing ones, because each independently
# resolves an ambiguity that the documentation gets wrong in both directions:
#
#   1. s_isize IS THE BLOCK NUMBER OF THE FIRST DATA BLOCK -- not the count of
#      i-list blocks, and not that count plus two. The i-list occupies blocks
#      2 .. s_isize-1, so it holds (s_isize - 2) * BSIZE / 64 inodes.
#      PROOF: the miniroot has s_isize=18 and s_tinode=59. Counting inodes with
#      di_mode == 0 gives 59 only for first_data == 18 (74 for 19, 87 for 20).
#      Independently, its lost+found directory's data block IS block 18.
#
#   2. THE FREE-LIST CHAIN BLOCK'S COUNTER IS A 32-BIT int, NOT the 16-bit short
#      that the superblock uses for the same quantity. struct filsys has
#      `short s_nfree`, but struct fblk has `int df_nfree`, so a chain block is
#      { df_nfree: 4 bytes, df_free[50]: 4 bytes each } and reading its count as
#      a short silently yields 0 -- which terminates the walk at the first chain
#      block and undercounts free space without erroring.
#      PROOF: walking the miniroot with a 32-bit df_nfree totals exactly 72 free
#      blocks == its s_tfree. With a 16-bit read the walk stops at 23.
#
# STRUCT OFFSETS. struct filsys is 512 bytes and m68k SVR4 aligns `long` to 4, so
# there is padding after s_isize, after s_nfree and after s_tinode. That padding
# is not cosmetic -- it is what puts s_magic at +504 and s_type at +508, which is
# where tools/s5-setdev.py and every other reader in this family find them
# (superblock at byte 0x200 => magic at 0x3f8). Every offset below is asserted
# against the miniroot in selftest().
#
# WHAT IS NOT VERIFIED HERE, and must not be claimed to be:
#   * Nothing in this module has been mounted by Amix. It is proven to be
#     structurally identical, field by field, to a genuine mkfs_s5 filesystem;
#     that is a strong claim but it is not "it mounts". The first box/emulator
#     run is the real test.
#   * s_state. SVR4 marks a clean filesystem with s_state = FsOKAY - s_time. The
#     miniroot does NOT satisfy that relation for any constant tried, which is
#     expected -- it is a captured ACTIVE root filesystem, not a cleanly
#     unmounted one, so its s_state is the mounted-dirty value. We therefore
#     write the documented clean value and cannot cross-check it against the
#     artifact. Worst case if the constant is wrong: Amix fscks a fresh empty
#     filesystem on first mount. That is a nuisance, not corruption.
#
# Stdlib-only, python3. Ships no proprietary bytes -- it writes filesystem
# metadata it computes, and copies nothing out of any Commodore image.

import struct
import time

# --- geometry ---------------------------------------------------------------
BSIZE = 1024                  # s_type == 2 => 1024-byte logical blocks
INODE_SIZE = 64
INODES_PER_BLOCK = BSIZE // INODE_SIZE          # 16

# THE SUPERBLOCK IS AT BYTE 512, NOT AT LOGICAL BLOCK 1. On a 1024-byte-block s5
# the superblock still lives at the second 512-BYTE sector, i.e. inside logical
# block 0, right behind the 512-byte boot area. Logical block 1 (bytes
# 1024..2047) is unused and reads as zeros; the i-list starts at logical block 2
# (byte 2048). Computing the superblock as `1 * BSIZE` gives 1024 and lands in
# that dead block -- it parses as all-zeros and reports "not an s5 filesystem",
# which is at least loud, but the same slip in a WRITER would silently produce a
# filesystem with no superblock where the kernel looks.
# PROOF: in the miniroot, bytes 0..511 are zero, 512..1023 carry the superblock
# (magic at 512+504 == 0x3f8), and 1024..2047 are zero.
SUPER_OFF = 512               # byte offset of struct filsys, not a block index
ILIST_START_BLK = 2           # the i-list DOES start at a logical block

S5_MAGIC = 0xfd187e20
S5_TYPE_1K = 2                # s_type: 1 => 512-byte blocks, 2 => 1024-byte

NICFREE = 50                  # entries in s_free[] / df_free[]
NICINOD = 100                 # entries in s_inode[]

# SVR4 clean-filesystem marker: a clean fs has s_state == FsOKAY - s_time.
FS_OKAY = 0x7c269d38

# --- struct filsys offsets (512 bytes, big-endian, longs 4-byte aligned) ----
SB_ISIZE   = 0     # ushort   s_isize   -- block number of the FIRST DATA BLOCK
SB_FSIZE   = 4     # long     s_fsize   -- total size of the volume, in blocks
SB_NFREE   = 8     # short    s_nfree   -- valid entries in s_free[]
SB_FREE    = 12    # long     s_free[NICFREE]
SB_NINODE  = 212   # short    s_ninode  -- valid entries in s_inode[]
SB_INODE   = 214   # ushort   s_inode[NICINOD]
SB_FLOCK   = 414   # char
SB_ILOCK   = 415   # char
SB_FMOD    = 416   # char
SB_RONLY   = 417   # char
SB_TIME    = 420   # long     s_time
SB_DINFO   = 424   # short    s_dinfo[4]
SB_TFREE   = 432   # long     s_tfree   -- total free blocks
SB_TINODE  = 436   # ushort   s_tinode  -- total free inodes
SB_FNAME   = 440   # char     s_fname[6]
SB_FPACK   = 446   # char     s_fpack[6]
SB_FILL    = 452   # long     s_fill[12]
SB_STATE   = 500   # long     s_state
SB_MAGIC   = 504   # long     s_magic
SB_TYPE    = 508   # long     s_type
SB_SIZE    = 512

# --- struct fblk (a free-list chain block) ----------------------------------
FB_NFREE = 0       # int      df_nfree  -- 32 BITS HERE, unlike s_nfree
FB_FREE  = 4       # long     df_free[NICFREE]

# --- struct dinode (64 bytes) -----------------------------------------------
DI_MODE  = 0       # ushort
DI_NLINK = 2       # short
DI_UID   = 4       # ushort
DI_GID   = 6       # ushort
DI_SIZE  = 8       # long
DI_ADDR  = 12      # char di_addr[40] -- 13 L3 (3-byte) block numbers + 1 pad
DI_ATIME = 52      # long
DI_MTIME = 56      # long
DI_CTIME = 60      # long
DI_ADDR_LEN = 40
DI_NADDR = 13      # 10 direct, 1 single, 1 double, 1 triple indirect

IFMT  = 0xF000
IFDIR = 0x4000
IFCHR = 0x2000
IFBLK = 0x6000
IFREG = 0x8000

# --- device special files: where the dev_t lives in di_addr -----------------
# A char/block special file has no data blocks, so the kernel reuses di_addr to
# carry the device number. It does NOT store a packed 16-bit dev there; it uses
# four of the L3 slots, and the MAJOR is the THIRD one:
#
#     di_addr L3[0] (bytes  0..2 ) = minor
#     di_addr L3[1] (bytes  3..5 ) = 0x000001   (constant)
#     di_addr L3[2] (bytes  6..8 ) = major
#     di_addr L3[3] (bytes  9..11) = minor      (duplicate)
#     di_addr L3[4..12]            = 0
#
# OBSERVED, not specified -- but observed twice over, independently: this is the
# layout tools/s5-setdev.py derived from the genuine 1991 Commodore
# amix_21_root.adf in 2026-07, and re-reading all 124 device nodes of that stock
# ADF *and* of both of our on-box-authored miniroots (fd0 and slice1) finds zero
# deviations from it. It also decodes to the numbers the kernel itself reports:
# /dev/fakeswap comes out 19,0 and `swap -l` on the running miniroot says dev
# 19,0; /dev/dsk/* come out block major 18 and /dev/rdsk/* char major 40, which
# are `dd`'s two majors in the grimoire major-number registry.
#
# The historical bug this constant set retires: reading the major out of the
# HIGH BYTE of L3[0] (i.e. treating L3[0] as a packed major<<8|minor o_dev_t).
# Every minor in a stock miniroot is < 256, so that spelling returned the right
# minor and major 0 for EVERY node -- a decode that is wrong everywhere yet
# never self-inconsistent -- which is why it survived from the first miniroot
# work (where the proto and its reader were written together) until the set-matrix work.
DEV_MINOR_L3 = 0   # L3 slot holding the minor
DEV_CONST_L3 = 1   # L3 slot holding the constant 1
DEV_MAJOR_L3 = 2   # L3 slot holding the major
DEV_MINOR2_L3 = 3  # L3 slot holding the duplicated minor
DEV_CONST_VALUE = 1

DIRENT_SIZE = 16   # { ino: 2 bytes big-endian, name: 14 bytes NUL-padded }
DIRSIZ = 14

ROOT_INO = 2
LOSTFOUND_INO = 3

# ★ AN s5 FILESYSTEM CANNOT HOLD MORE THAN 65535 INODES, and that is SPEC, not
# policy: an inode number is SIXTEEN BITS everywhere it is written down. A
# directory entry is `{ ino: 2 bytes big-endian, name: 14 }` (DIRENT_SIZE), the
# superblock's free-inode cache is `ushort s_inode[NICINOD]`, and the free-inode
# count `s_tinode` is a ushort too. So inode 65536 has no way to be referenced,
# cached or counted.
#
# The set-matrix work walked into this from the other end. The `full` package set needs ~304 MB
# installed, which does not fit the canonical 100 MB bench target, so the new
# large-set matrix cells mkroot'd a 400 MB one -- and mkfs_s5 died with a bare
#     struct.error: 'H' format requires 0 <= number <= 65535
# out of the free-inode-cache pack. The nblocks/4 rule had asked for 94,208
# inodes on a 367 MB root. The rule SATURATES here instead: a 288 MB root is
# where nblocks/4 reaches the ceiling, and every larger filesystem gets the same
# 65,520 (the largest whole i-list block count that fits, 4095 blocks x 16).
#
# 65,520 is not a tight budget for this distribution: the whole 30-package `full`
# set declares 28,965 objects across its pkgmaps (which double-counts every
# directory shared between packages), so a full install lands comfortably inside
# half the ceiling. A workload that genuinely needed more inodes would need a
# different filesystem, not a different constant.
MAX_INODES = 65520

# Modes mirrored from the genuine Amix mkfs_s5 output (the miniroot): its root
# and lost+found directories are both 040777. We copy the artifact rather than
# impose a tidier 0755, because the artifact is the only ground truth available
# and the distribution's own root package sets / to its intended mode anyway.
ROOT_MODE = IFDIR | 0o777
LOSTFOUND_MODE = IFDIR | 0o777

# lost+found is preallocated with empty slots so fsck can relink orphans without
# having to extend a directory on a damaged filesystem. The genuine miniroot's
# lost+found is 608 bytes == 38 slots; we use the same number.
LOSTFOUND_SLOTS = 38

# Inode 1 is RESERVED, historically for bad-block accounting. Real mkfs_s5 leaves
# it non-free but unlinked, and so do we: the miniroot's inode 1 reads exactly
# mode=0100000 (IFREG, no permission bits), nlink=0, size=0. Leaving it mode 0
# would make it look free and let the kernel hand it out.
RESERVED_INO_MODE = IFREG
RESERVED_INO_NLINK = 0


class S5Error(Exception):
    """A structural defect in an s5 filesystem. Callers should fail closed."""


def _u16(b, o): return struct.unpack('>H', b[o:o+2])[0]
def _s16(b, o): return struct.unpack('>h', b[o:o+2])[0]
def _u32(b, o): return struct.unpack('>I', b[o:o+4])[0]


def _l3(b, o):
    """A 3-byte big-endian block number, as stored in di_addr."""
    return (b[o] << 16) | (b[o+1] << 8) | b[o+2]


def _put_l3(buf, o, v):
    if not 0 <= v < (1 << 24):
        raise S5Error("block number %d does not fit in an L3 di_addr entry" % v)
    buf[o] = (v >> 16) & 0xff
    buf[o+1] = (v >> 8) & 0xff
    buf[o+2] = v & 0xff


# ===========================================================================
# reading
# ===========================================================================
class Super(object):
    """A parsed struct filsys."""

    __slots__ = ("isize", "fsize", "nfree", "free", "ninode", "inode",
                 "time", "tfree", "tinode", "state", "magic", "type")

    @property
    def first_data_block(self):
        """s_isize IS this. See the header note -- this is the ambiguity that
        two independent counts on the genuine miniroot resolved."""
        return self.isize

    @property
    def ilist_blocks(self):
        return self.isize - ILIST_START_BLK

    @property
    def n_inodes(self):
        return self.ilist_blocks * INODES_PER_BLOCK

    def __repr__(self):
        return ("s5 super: isize=%d (first data block) fsize=%d blocks "
                "inodes=%d tfree=%d tinode=%d type=%d magic=0x%08x"
                % (self.isize, self.fsize, self.n_inodes, self.tfree,
                   self.tinode, self.type, self.magic))


def parse_super(img, base=0):
    """Parse the superblock of the s5 filesystem starting at byte `base`."""
    o = base + SUPER_OFF
    if o + SB_SIZE > len(img):
        raise S5Error("image is too short to contain a superblock at 0x%x" % o)
    sb = img[o:o+SB_SIZE]
    s = Super()
    s.magic = _u32(sb, SB_MAGIC)
    if s.magic != S5_MAGIC:
        raise S5Error("not an s5 filesystem at 0x%x: magic @+0x%x is 0x%08x, "
                      "expected 0x%08x" % (base, SB_MAGIC, s.magic, S5_MAGIC))
    s.type = _u32(sb, SB_TYPE)
    if s.type != S5_TYPE_1K:
        raise S5Error("s_type=%d; this module only handles type 2 (%d-byte "
                      "logical blocks)" % (s.type, BSIZE))
    s.isize = _u16(sb, SB_ISIZE)
    s.fsize = _u32(sb, SB_FSIZE)
    s.nfree = _s16(sb, SB_NFREE)
    s.free = [_u32(sb, SB_FREE + 4*i) for i in range(NICFREE)]
    s.ninode = _s16(sb, SB_NINODE)
    s.inode = [_u16(sb, SB_INODE + 2*i) for i in range(NICINOD)]
    s.time = _u32(sb, SB_TIME)
    s.tfree = _u32(sb, SB_TFREE)
    s.tinode = _u16(sb, SB_TINODE)
    s.state = _u32(sb, SB_STATE)
    if s.isize < ILIST_START_BLK + 1:
        raise S5Error("s_isize=%d leaves no room for an i-list" % s.isize)
    if s.fsize <= s.isize:
        raise S5Error("s_fsize=%d <= s_isize=%d: no data blocks" % (s.fsize, s.isize))
    return s


def _freelist_levels(img, sb, base=0):
    """Yield (src_block, nfree, entries) for each level of the free-list chain.

    src_block is None for the superblock level and the chain-block number for
    every level below it (each reached via the previous level's entries[0] link).
    entries is the nfree-long slice of free[] at that level; the chain block's
    counter is a 32-bit int (see the header), NOT the 16-bit s_nfree.

    Enforces the structure genuine mkfs_s5 writes and the box's fsck expects, and
    raises S5Error on any deviation, because a partial or mis-shaped free list is
    worse than none:

      * a counter outside [0, NICFREE];
      * a LINK that points at a block whose df_nfree reads 0 -- i.e. an
        unallocated zero block, not a written chain block. The genuine list
        terminates on a df_free[0] == 0 sentinel INSIDE a real chain block; a
        chain that instead runs off its last link into zero space is the
        missing-sentinel defect fsck reports as "BAD FREE LIST";
      * a loop, a runaway chain, or a chain block past the end of the image.
    """
    nfree = sb.nfree
    free = list(sb.free)
    src = None                       # None => superblock level
    visited = set()
    guard = 0
    while True:
        if not 0 <= nfree <= NICFREE:
            where = "the superblock" if src is None else "chain block %d" % src
            raise S5Error("free-list counter %d in %s is out of range [0,%d]"
                          % (nfree, where, NICFREE))
        if src is not None and nfree == 0:
            raise S5Error("free-list link points at block %d, which is not a "
                          "written chain block (df_nfree=0) -- the chain ran off "
                          "into unallocated space; the df_free[0]==0 sentinel that "
                          "genuine mkfs_s5 writes is missing (BAD FREE LIST)" % src)
        entries = free[:nfree]
        yield src, nfree, entries
        nxt = entries[0] if entries else 0
        if nxt == 0:
            return                   # genuine terminator: sentinel reached
        if nxt in visited:
            raise S5Error("free-list chain loops at block %d" % nxt)
        visited.add(nxt)
        guard += 1
        if guard > sb.fsize:
            raise S5Error("free-list chain does not terminate")
        o = base + nxt * BSIZE
        if o + FB_FREE + 4*NICFREE > len(img):
            raise S5Error("free-list chain block %d is past the end of the image" % nxt)
        blk = img[o:o + BSIZE]
        nfree = _u32(blk, FB_NFREE)          # 32-bit -- NOT a short
        free = [_u32(blk, FB_FREE + 4*i) for i in range(NICFREE)]
        src = nxt


def walk_freelist(img, sb, base=0):
    """Every free block, following the chain. Returns a sorted list.

    Walks with _freelist_levels (so it enforces the genuine sentinel structure)
    and additionally rejects a block number outside the data area or a repeat --
    a free list that hands out an i-list block corrupts the filesystem, so this
    refuses to report a partial answer.
    """
    seen = []
    seen_set = set()
    for _src, _nfree, entries in _freelist_levels(img, sb, base):
        for b in entries:
            if b == 0:
                continue
            if not (sb.isize <= b < sb.fsize):
                raise S5Error("free-list block %d is outside the data area "
                              "[%d,%d)" % (b, sb.isize, sb.fsize))
            if b in seen_set:
                raise S5Error("free-list block %d appears twice" % b)
            seen_set.add(b)
            seen.append(b)
    return sorted(seen)


def freelist_shape(img, sb, base=0):
    """Structural summary of the free-list chain, for cross-checking a minted
    filesystem against genuine mkfs_s5 output.

    Returns (n_chain_blocks, chain_nfrees, terminated_by_sentinel):
      * n_chain_blocks         -- chain blocks below the superblock;
      * chain_nfrees           -- each chain block's df_nfree, in walk order
                                  (genuine mkfs_s5 writes every one FULL, == NICFREE);
      * terminated_by_sentinel -- True iff the last level ends on a df_free[0]==0
                                  (or empty) terminator. Always True when the walk
                                  completes: _freelist_levels raises rather than
                                  return on the sentinel-less shape.

    Raises S5Error on the same defects as _freelist_levels.
    """
    chain_nfrees = []
    last_entries = []
    for src, nfree, entries in _freelist_levels(img, sb, base):
        if src is not None:
            chain_nfrees.append(nfree)
        last_entries = entries
    terminated = (not last_entries) or (last_entries[0] == 0)
    return len(chain_nfrees), chain_nfrees, terminated


def inode_offset(sb_or_none, n, base=0):
    """Byte offset of inode n (1-based). The i-list always starts at block 2."""
    if n < 1:
        raise S5Error("inode numbers are 1-based; got %d" % n)
    return base + ILIST_START_BLK * BSIZE + (n - 1) * INODE_SIZE


def read_inode(img, n, base=0):
    """(mode, nlink, uid, gid, size, [block numbers])."""
    o = inode_offset(None, n, base)
    mode = _u16(img, o + DI_MODE)
    nlink = _s16(img, o + DI_NLINK)
    uid = _u16(img, o + DI_UID)
    gid = _u16(img, o + DI_GID)
    size = _u32(img, o + DI_SIZE)
    addrs = [_l3(img, o + DI_ADDR + 3*i) for i in range(DI_NADDR)]
    return mode, nlink, uid, gid, size, addrs


def decode_dev(addrs):
    """(major, minor) from an inode's decoded di_addr L3 list.

    FAIL-CLOSED. Raises S5Error unless the whole di_addr matches the layout
    documented at DEV_MAJOR_L3 -- the constant 1 in slot 1, the duplicated minor
    in slot 3, and nothing at all in slots 4..12. A device node that does not
    look like every device node we have ever read must not be quietly decoded
    into plausible-looking numbers; that is precisely how the previous spelling
    reported major 0 for the whole /dev tree without ever tripping a check.
    """
    if len(addrs) < 4:
        raise S5Error("di_addr has %d L3 slots; a device node needs at least 4"
                      % len(addrs))
    minor = addrs[DEV_MINOR_L3]
    major = addrs[DEV_MAJOR_L3]
    if addrs[DEV_CONST_L3] != DEV_CONST_VALUE:
        raise S5Error("device di_addr[%d] is %d, expected the constant %d "
                      "(di_addr=%s) -- this is not the device layout this "
                      "module knows" % (DEV_CONST_L3, addrs[DEV_CONST_L3],
                                        DEV_CONST_VALUE, addrs[:5]))
    if addrs[DEV_MINOR2_L3] != minor:
        raise S5Error("device di_addr[%d]=%d does not repeat the minor "
                      "di_addr[%d]=%d (di_addr=%s)"
                      % (DEV_MINOR2_L3, addrs[DEV_MINOR2_L3],
                         DEV_MINOR_L3, minor, addrs[:5]))
    tail = [a for a in addrs[4:] if a != 0]
    if tail:
        raise S5Error("device di_addr has nonzero slots past the dev_t: %s"
                      % (addrs[:8],))
    return major, minor


def count_free_inodes(img, sb, base=0):
    """Inodes with di_mode == 0. This is what s_tinode counts."""
    n = 0
    for i in range(1, sb.n_inodes + 1):
        if _u16(img, inode_offset(sb, i, base) + DI_MODE) == 0:
            n += 1
    return n


def read_dir(img, ino, base=0):
    """[(inode, name), ...] for a directory inode. Direct blocks only -- fresh
    filesystems never need more, and this is a verification helper, not a
    general-purpose s5 client."""
    mode, _, _, _, size, addrs = read_inode(img, ino, base)
    if (mode & IFMT) != IFDIR:
        raise S5Error("inode %d is not a directory (mode 0%o)" % (ino, mode))
    out = []
    got = 0
    for b in addrs[:10]:
        if got >= size:
            break
        if b == 0:
            got += BSIZE
            continue
        blk = img[base + b*BSIZE: base + (b+1)*BSIZE]
        end = min(BSIZE, size - got)
        for e in range(0, end, DIRENT_SIZE):
            num = _u16(blk, e)
            name = blk[e+2:e+DIRENT_SIZE].split(b'\x00')[0].decode('latin1')
            if num != 0:
                out.append((num, name))
        got += BSIZE
    return out


# ===========================================================================
# minting
# ===========================================================================
def default_inode_count(nblocks):
    """One inode per 4 logical blocks, rounded up to a whole i-list block, and
    SATURATED at MAX_INODES.

    POLICY, NOT SPEC, for the ratio. The traditional mkfs default is nblocks/4;
    no Amix document pins it, and the miniroot (880 blocks, 256 inodes) was
    clearly made with an explicit count rather than this rule, so do not treat
    matching it as a correctness condition. Override with mkfs_s5(..., ninodes=N)
    when the workload is known.

    The CEILING, unlike the ratio, is spec: see MAX_INODES.
    """
    n = max(INODES_PER_BLOCK, nblocks // 4)
    blocks = (n + INODES_PER_BLOCK - 1) // INODES_PER_BLOCK
    return min(blocks * INODES_PER_BLOCK, MAX_INODES)


def _dirent(ino, name):
    nb = name.encode('ascii')
    if len(nb) > DIRSIZ:
        raise S5Error("directory name %r exceeds %d bytes" % (name, DIRSIZ))
    return struct.pack('>H', ino) + nb + b'\x00' * (DIRSIZ - len(nb))


def mkfs_s5(nblocks, ninodes=None, fs_time=None, fname=b"", fpack=b""):
    """Mint a fresh, empty s5 filesystem of `nblocks` 1024-byte logical blocks.

    Returns exactly nblocks * BSIZE bytes: block 0 boot (zeros), block 1
    superblock, blocks 2..isize-1 i-list, isize.. data. Contains only `/` and
    `/lost+found`.

    Block allocation mirrors the genuine artifact: lost+found takes the FIRST
    data block and the root directory the second, which is the order observed in
    the miniroot (lost+found at block 18 == s_isize, root at 19).
    """
    if nblocks < 64:
        raise S5Error("refusing to make a %d-block s5 filesystem -- too small to "
                      "hold an i-list plus a root directory" % nblocks)
    if ninodes is None:
        ninodes = default_inode_count(nblocks)
    ilist_blocks = (ninodes + INODES_PER_BLOCK - 1) // INODES_PER_BLOCK
    ninodes = ilist_blocks * INODES_PER_BLOCK
    # FAIL CLOSED, and say what the limit IS. An explicit over-large count used
    # to die inside struct.pack_into with `'H' format requires 0 <= number <=
    # 65535` from the free-inode cache -- a true message about the wrong thing.
    if ninodes > MAX_INODES:
        raise S5Error("%d inodes exceeds the s5 maximum of %d: an inode number "
                      "is 16 bits in a directory entry, in s_inode[] and in "
                      "s_tinode, so inode %d could never be referenced"
                      % (ninodes, MAX_INODES, MAX_INODES + 1))
    isize = ILIST_START_BLK + ilist_blocks          # == first data block
    if isize + 2 >= nblocks:
        raise S5Error("i-list of %d blocks leaves no room for data in %d blocks"
                      % (ilist_blocks, nblocks))
    if fs_time is None:
        fs_time = int(time.time())

    img = bytearray(nblocks * BSIZE)

    lf_block = isize            # lost+found data block
    root_block = isize + 1      # root directory data block

    # --- directory contents -------------------------------------------------
    root_ents = (_dirent(ROOT_INO, ".")
                 + _dirent(ROOT_INO, "..")
                 + _dirent(LOSTFOUND_INO, "lost+found"))
    root_size = len(root_ents)
    img[root_block*BSIZE: root_block*BSIZE + root_size] = root_ents

    lf_ents = _dirent(LOSTFOUND_INO, ".") + _dirent(ROOT_INO, "..")
    lf_size = LOSTFOUND_SLOTS * DIRENT_SIZE     # rest stays zero == free slots
    if lf_size > BSIZE:
        raise S5Error("lost+found preallocation exceeds one block")
    img[lf_block*BSIZE: lf_block*BSIZE + len(lf_ents)] = lf_ents

    # --- inodes -------------------------------------------------------------
    def put_inode(n, mode, nlink, size, blocks):
        o = ILIST_START_BLK * BSIZE + (n - 1) * INODE_SIZE
        struct.pack_into('>HhHHI', img, o, mode, nlink, 0, 0, size)
        for i, b in enumerate(blocks):
            _put_l3(img, o + DI_ADDR + 3*i, b)
        struct.pack_into('>III', img, o + DI_ATIME, fs_time, fs_time, fs_time)

    put_inode(1, RESERVED_INO_MODE, RESERVED_INO_NLINK, 0, [])
    # root nlink = '.' + '..' + lost+found's '..' = 3
    put_inode(ROOT_INO, ROOT_MODE, 3, root_size, [root_block])
    put_inode(LOSTFOUND_INO, LOSTFOUND_MODE, 2, lf_size, [lf_block])

    # --- free inode cache ---------------------------------------------------
    # ialloc pops s_inode[--s_ninode], so store DESCENDING to hand out ascending.
    free_inos = list(range(LOSTFOUND_INO + 1, ninodes + 1))
    cached = sorted(free_inos, reverse=True)[:NICINOD]
    tinode = len(free_inos)

    # --- free block list ----------------------------------------------------
    # Replay the kernel's own free() over the data blocks in DESCENDING order, so
    # that alloc() -- which pops the last entry -- returns them ascending. Doing
    # it by simulation rather than by hand-chunking is what makes the produced
    # chain provably the shape the kernel expects to consume.
    #
    # SEED THE SENTINEL, exactly as genuine mkfs_s5 does: start s_nfree = 1 with
    # s_free[0] = 0. Block 0 is the TERMINATOR -- placed here, never by a free(),
    # so it is not counted in s_tfree. Because the first free() that fills the
    # array to NICFREE spills THIS seeded array (0 at the bottom) into a chain
    # block, the DEEPEST chain block ends up carrying df_free[0] == 0 -- the same
    # sentinel the genuine miniroot has (block 830: df_nfree=50, df_free[0]=0),
    # and the same thing the box's fsck walks the list expecting to find.
    # Starting at s_nfree = 0 (no sentinel) is the bug this fixes: the chain then
    # runs off its last real link into an unallocated zero block instead of a
    # written terminator, and fsck reports "BAD FREE LIST / BAD FREEBLK COUNT"
    # and salvages on first mount. See walk_freelist / _freelist_levels, which
    # now refuse the sentinel-less shape.
    s_nfree = 1
    s_free = [0] * NICFREE          # s_free[0] == 0 is that sentinel

    def do_free(bno):
        nonlocal s_nfree
        if s_nfree >= NICFREE:
            # spill the current chunk into the block being freed
            o = bno * BSIZE
            struct.pack_into('>I', img, o + FB_NFREE, s_nfree)
            for i in range(NICFREE):
                struct.pack_into('>I', img, o + FB_FREE + 4*i, s_free[i])
            s_nfree = 0
        s_free[s_nfree] = bno
        s_nfree += 1

    tfree = 0
    for b in range(nblocks - 1, root_block, -1):
        do_free(b)
        tfree += 1

    # --- superblock ---------------------------------------------------------
    o = SUPER_OFF
    struct.pack_into('>H', img, o + SB_ISIZE, isize)
    struct.pack_into('>I', img, o + SB_FSIZE, nblocks)
    struct.pack_into('>h', img, o + SB_NFREE, s_nfree)
    for i in range(NICFREE):
        struct.pack_into('>I', img, o + SB_FREE + 4*i, s_free[i])
    struct.pack_into('>h', img, o + SB_NINODE, len(cached))
    for i, ino in enumerate(cached):
        struct.pack_into('>H', img, o + SB_INODE + 2*i, ino)
    struct.pack_into('>I', img, o + SB_TIME, fs_time)
    struct.pack_into('>I', img, o + SB_TFREE, tfree)
    struct.pack_into('>H', img, o + SB_TINODE, tinode)
    img[o + SB_FNAME: o + SB_FNAME + 6] = (fname + b'\x00' * 6)[:6]
    img[o + SB_FPACK: o + SB_FPACK + 6] = (fpack + b'\x00' * 6)[:6]
    struct.pack_into('>I', img, o + SB_STATE, (FS_OKAY - fs_time) & 0xFFFFFFFF)
    struct.pack_into('>I', img, o + SB_MAGIC, S5_MAGIC)
    struct.pack_into('>I', img, o + SB_TYPE, S5_TYPE_1K)

    return bytes(img)


# ===========================================================================
# self-test -- the reader against the genuine artifact, then the writer
# against the reader
# ===========================================================================
def selftest(reference_image=None, verbose=True):
    """Return a list of problems; empty == pass.

    Two halves, and the order matters:

      A. If a genuine Amix-made s5 filesystem is available, prove the READER
         against it. This is the only part with external ground truth, and it is
         what pins s_isize's meaning and the 32-bit df_nfree.
      B. Prove the WRITER by minting filesystems and reading them back with the
         reader half A just validated.

    Half B alone would be circular. Half A is skipped (loudly, and reported as a
    problem) when the reference image is absent, because a self-consistent writer
    is not evidence of anything.
    """
    problems = []
    say = (lambda m: print(m)) if verbose else (lambda m: None)

    # ---- A. reader vs. the genuine artifact --------------------------------
    if reference_image is None:
        problems.append("no reference s5 image supplied -- the reader was NOT "
                        "validated against genuine mkfs_s5 output, so the writer "
                        "checks below are self-referential")
    else:
        say("  reference: %s" % reference_image)
        with open(reference_image, 'rb') as fh:
            ref = fh.read()
        sb = parse_super(ref)
        say("    %r" % sb)

        # fsize must describe the whole medium
        if sb.fsize * BSIZE != len(ref):
            problems.append("reference s_fsize=%d blocks (%d bytes) != image size %d"
                            % (sb.fsize, sb.fsize * BSIZE, len(ref)))

        # PIN 1: s_isize == first data block, proven by the inode count.
        nfree_i = count_free_inodes(ref, sb)
        if nfree_i != sb.tinode:
            problems.append("reference free-inode count %d != s_tinode %d -- the "
                            "i-list sizing derived from s_isize is wrong "
                            "(s_isize is NOT the first data block after all)"
                            % (nfree_i, sb.tinode))
        else:
            say("    PIN s_isize==first-data-block: free inodes %d == s_tinode %d"
                % (nfree_i, sb.tinode))

        # PIN 2: 32-bit df_nfree, proven by the free-block total.
        try:
            free_blocks = walk_freelist(ref, sb)
        except S5Error as e:
            problems.append("reference free-list walk failed: %s" % e)
            free_blocks = []
        if len(free_blocks) != sb.tfree:
            problems.append("reference free-list walk found %d blocks != s_tfree %d "
                            "-- df_nfree is not being read as a 32-bit int"
                            % (len(free_blocks), sb.tfree))
        else:
            say("    PIN 32-bit df_nfree: free-list walk %d blocks == s_tfree %d"
                % (len(free_blocks), sb.tfree))

        # PIN 3: the genuine free-list chain is SENTINEL-TERMINATED -- it ends on
        # a df_free[0]==0 inside a real chain block (each written FULL, df_nfree
        # == NICFREE), never by running off its last link into a zero block. This
        # is the exact shape the box's fsck expects and the shape mkfs_s5's writer
        # (half B) must reproduce; capture it so the writer can be held to it.
        try:
            ref_nchain, ref_nfrees, ref_term = freelist_shape(ref, sb)
        except S5Error as e:
            problems.append("reference free-list is not sentinel-terminated: %s" % e)
            ref_nchain, ref_nfrees, ref_term = -1, [], False
        ref_full = bool(ref_nfrees) and all(n == NICFREE for n in ref_nfrees)
        if not (ref_term and ref_full):
            problems.append("reference free-list shape is not genuine mkfs_s5 shape "
                            "(chain df_nfree=%r, terminated=%s)" % (ref_nfrees, ref_term))
        else:
            say("    PIN sentinel: %d chain block(s), each df_nfree==%d, df_free[0]==0 "
                "terminator" % (ref_nchain, NICFREE))

        # the root directory must be reachable and self-consistent
        try:
            ents = dict((n, i) for i, n in read_dir(ref, ROOT_INO))
            if "." not in ents or ".." not in ents:
                problems.append("reference root directory lacks '.' or '..'")
            elif ents["."] != ROOT_INO:
                problems.append("reference root '.' points to inode %d, not %d"
                                % (ents["."], ROOT_INO))
            else:
                say("    root dir: %d entries, '.'->%d" % (len(ents), ents["."]))
        except S5Error as e:
            problems.append("reference root directory unreadable: %s" % e)

        # inode 1 must be reserved, not free
        m1 = read_inode(ref, 1)[0]
        if m1 == 0:
            problems.append("reference inode 1 is free (mode 0); expected the "
                            "reserved marker")
        else:
            say("    inode 1 reserved: mode=0%o" % m1)

    # ---- B. writer vs. the reader ------------------------------------------
    for nblocks in (128, 880, 4096, 65536):
        try:
            fs = mkfs_s5(nblocks, fs_time=700000000)
        except S5Error as e:
            problems.append("mkfs_s5(%d) raised: %s" % (nblocks, e))
            continue
        if len(fs) != nblocks * BSIZE:
            problems.append("mkfs_s5(%d) produced %d bytes, expected %d"
                            % (nblocks, len(fs), nblocks * BSIZE))
            continue
        try:
            sb = parse_super(fs)
        except S5Error as e:
            problems.append("mkfs_s5(%d) output does not parse: %s" % (nblocks, e))
            continue

        checks = []
        checks.append((sb.fsize == nblocks,
                       "s_fsize %d == %d" % (sb.fsize, nblocks)))

        try:
            free_blocks = walk_freelist(fs, sb)
        except S5Error as e:
            problems.append("mkfs_s5(%d): free-list walk failed: %s" % (nblocks, e))
            free_blocks = []
        checks.append((len(free_blocks) == sb.tfree,
                       "free-list walk %d == s_tfree %d" % (len(free_blocks), sb.tfree)))
        # STRUCTURE: the minted chain must be the genuine sentinel-terminated shape
        # (half A's PIN 3), each chain block written FULL -- not merely a set of
        # blocks the tolerant old reader happened to total correctly.
        try:
            nchain, nfrees, term = freelist_shape(fs, sb)
        except S5Error as e:
            problems.append("mkfs_s5(%d): free-list shape walk failed: %s" % (nblocks, e))
            nchain, nfrees, term = 0, [], False
        checks.append((term and bool(nfrees) and all(n == NICFREE for n in nfrees),
                       "free list sentinel-terminated (%d chain block(s), each "
                       "df_nfree==%d)" % (nchain, NICFREE)))
        # data blocks are: isize..fsize-1 minus the two directory blocks
        expect_free = set(range(sb.isize, sb.fsize)) - {sb.isize, sb.isize + 1}
        checks.append((set(free_blocks) == expect_free,
                       "free set == every data block except the two directory blocks"))
        checks.append((all(sb.isize <= b < sb.fsize for b in free_blocks),
                       "no free-list entry lands in the i-list or the superblock"))

        nfree_i = count_free_inodes(fs, sb)
        checks.append((nfree_i == sb.tinode,
                       "free inodes %d == s_tinode %d" % (nfree_i, sb.tinode)))
        checks.append((read_inode(fs, 1)[0] != 0, "inode 1 reserved, not free"))

        try:
            root = dict((n, i) for i, n in read_dir(fs, ROOT_INO))
            checks.append((root.get(".") == ROOT_INO, "root '.' -> 2"))
            checks.append((root.get("..") == ROOT_INO, "root '..' -> 2"))
            checks.append((root.get("lost+found") == LOSTFOUND_INO,
                           "root has lost+found -> 3"))
            lf = dict((n, i) for i, n in read_dir(fs, LOSTFOUND_INO))
            checks.append((lf.get(".") == LOSTFOUND_INO, "lost+found '.' -> 3"))
            checks.append((lf.get("..") == ROOT_INO, "lost+found '..' -> 2"))
        except S5Error as e:
            problems.append("mkfs_s5(%d): directory readback failed: %s" % (nblocks, e))

        checks.append((sb.state == ((FS_OKAY - sb.time) & 0xFFFFFFFF),
                       "s_state == FsOKAY - s_time (clean)"))

        bad = [d for ok, d in checks if not ok]
        say("    mkfs_s5(%d blocks): %d/%d checks ok%s"
            % (nblocks, len(checks) - len(bad), len(checks),
               "" if not bad else "  FAILED: " + "; ".join(bad)))
        for d in bad:
            problems.append("mkfs_s5(%d): %s" % (nblocks, d))

    # a SENTINEL-LESS free list -- the pre-fix shape -- must be REFUSED, not
    # silently walked. Take a good filesystem and overwrite the deepest chain
    # block's df_free[0]==0 terminator with a link into a plain (zero) data
    # block, reproducing a chain that runs off its end instead of terminating on
    # a written sentinel. That is exactly what the box's fsck reports as BAD FREE
    # LIST; the reader must now raise where the old tolerant walk accepted it.
    neg = bytearray(mkfs_s5(880, fs_time=700000000))
    neg_sb = parse_super(bytes(neg))
    deepest = list(_freelist_levels(bytes(neg), neg_sb))[-1][0]
    if deepest is None:
        problems.append("sentinel-less negative: minted fs has no chain block to "
                        "corrupt -- the fixture assumption is wrong")
    else:
        # neg_sb.fsize-1 is freed first, never a spill target => a zero data block
        struct.pack_into('>I', neg, deepest * BSIZE + FB_FREE, neg_sb.fsize - 1)
        try:
            walk_freelist(bytes(neg), neg_sb)
            problems.append("sentinel-less free list was ACCEPTED -- walk_freelist "
                            "no longer catches the missing-terminator defect (BAD "
                            "FREE LIST on the box)")
            say("    sentinel-less free list WRONGLY accepted")
        except S5Error:
            say("    sentinel-less free list correctly refused (missing terminator)")

    # too-small must be refused, not silently produced
    try:
        mkfs_s5(8)
        problems.append("mkfs_s5(8) should have been refused as too small")
    except S5Error:
        say("    mkfs_s5(8 blocks) correctly refused")

    # ---- the 16-bit inode ceiling -------------------------------------
    # An inode number is 16 bits in a directory entry, in s_inode[] and in
    # s_tinode, so a filesystem cannot hold more than 65535 of them. The
    # nblocks/4 rule crosses that at a ~288 MB root, and the FULL package set
    # needs a ~367 MB one -- which is how this was found: mkfs_s5 died inside
    # struct.pack_into with a true message about the wrong thing.
    knee = MAX_INODES * 4          # the block count where the rule reaches the cap
    checks = [
        (default_inode_count(80896) == 20224,
         "the canonical 100 MB bench root is UNCHANGED at 20224 inodes (the cap "
         "must not move any filesystem this project has already minted)"),
        (default_inode_count(knee - 4 * INODES_PER_BLOCK) < MAX_INODES,
         "just below the knee the rule is still the rule"),
        (default_inode_count(knee) == MAX_INODES, "at the knee it reaches the cap"),
        (default_inode_count(knee * 10) == MAX_INODES,
         "far above the knee it SATURATES rather than overflowing"),
        (MAX_INODES % INODES_PER_BLOCK == 0,
         "the cap is a whole number of i-list blocks"),
        (MAX_INODES <= 0xFFFF,
         "the cap fits the 16-bit inode number a directory entry carries"),
    ]
    for ok, d in checks:
        if not ok:
            problems.append("inode ceiling: %s" % d)
    say("    inode ceiling: %d/%d checks ok (MAX_INODES=%d)"
        % (sum(1 for ok, _ in checks if ok), len(checks), MAX_INODES))
    # an EXPLICIT over-large count must be refused, and by this module rather
    # than by struct
    try:
        mkfs_s5(400000, ninodes=MAX_INODES + INODES_PER_BLOCK)
        problems.append("mkfs_s5 accepted more than MAX_INODES inodes")
        say("    over-large explicit inode count WRONGLY accepted")
    except S5Error:
        say("    over-large explicit inode count correctly refused")
    # and a filesystem at the ceiling must actually mint and read back
    # 375,808 blocks is the s5 root of a 400 MB target -- the size the large-set
    # rig used when this ceiling was FOUND (2026-08-11). The rig has since gone
    # ufs and grown to 512 MB, so the number is now a MEASURED HISTORICAL CASE
    # rather than a live rig's geometry, and it is kept exactly as measured: the
    # saturation it demonstrates starts at a 288 MB root and holds for every
    # larger filesystem, so re-pinning it to today's rig would prove no more and
    # would quietly discard the case the bug was actually caught on.
    big = mkfs_s5(375808, fs_time=700000000)
    bsb = parse_super(big)
    if bsb.n_inodes != MAX_INODES:
        problems.append("a 375808-block fs minted %d inodes, expected the cap %d"
                        % (bsb.n_inodes, MAX_INODES))
    elif count_free_inodes(big, bsb) != bsb.tinode:
        problems.append("a 375808-block fs disagrees with its own s_tinode")
    else:
        say("    375808-block fs (the 400 MB s5 root this was caught on): %d "
            "inodes, %d free blocks, s_tinode agrees" % (bsb.n_inodes, bsb.tfree))

    return problems
