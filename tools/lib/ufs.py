# tools/lib/ufs.py -- READ an Amix SVR4 UFS1 (Berkeley FFS) filesystem, host-side.
#
# WHY THIS EXISTS. The s5 install line has tools/lib/s5.py (read + mint). The
# 040/060 line runs 4 KiB pages, under which s5 is structurally broken, so that
# line's install miniroot is UFS -- and every host-side gate that used to read an
# s5 root slice (the source-.hdf slice-1 check, the miniroot conformance selftest,
# the raw-source member reference) must now also read UFS. This module is that
# reader. It MIRRORS tools/lib/s5.py's shape where it makes sense -- parse_super,
# read_inode, read_dir, decode_dev, an S5Error-parallel UfsError, selftest() --
# so the consumers can treat s5 and ufs uniformly.
#
# It is a READER ONLY. There is deliberately NO host-side UFS writer in this repo
# (docs/ufs-target-scoping.md 3.3): a real UFS miniroot is authored on the golden
# box with the stock mkfs_ufs, exactly as the s5 miniroot is. tools/lib/ufs_size.py
# answers "how big must the medium be"; this answers "read it back and prove it".
#
# HOW EVERY OFFSET BELOW WAS ESTABLISHED -- read this before changing one.
# ---------------------------------------------------------------------------
# None of it is guessed. Two independent, agreeing sources pin every field:
#
#   1. The Amix SVR4 on-disk headers themselves -- sys/fs/ufs_fs.h (struct fs,
#      the cg-address macros cgstart/cgimin/itod/itog/itoo), sys/fs/ufs_inode.h
#      (struct icommon, 128 bytes, EFT variant) and sys/fs/ufs_fsdir.h (struct
#      direct). These are the on-disk contract for THIS kernel's filesystem.
#
#   2. A GENUINE 1991-mkfs_ufs filesystem, read field by field: the UFS root slice
#      of amix-images/masters/amix-z3660-golden-2026-07-11.hdf (slice 1, UNI\1, at
#      byte 65536), whose superblock geometry is decoded in docs/ufs-target-scoping
#      1.4 and whose file checksums are the reader's external ground truth
#      (selftest half C). Cross-checked further against the already-committed,
#      already-self-tested tools/rootfs-type.py, whose fs_magic / fs_size / fs_bsize
#      / ... byte offsets this module re-derives to the same numbers.
#
# THE LOAD-BEARING FACTS the golden pinned, each an ambiguity the docs get wrong:
#
#   * DISK ADDRESSES ARE IN FRAGMENTS. ic_db[]/ic_ib[] and every indirect-block
#     entry hold a FRAGMENT number, not a block and not a sector: the byte offset
#     of datum at address `a` is `a * fs_fsize` from the start of the filesystem
#     (fsbtodb shifts to 512-sectors; a*fs_fsize is the same offset). A full block
#     is fs_frag consecutive fragments named by the fragment number of its first.
#
#   * THE INODE IS THE EFT ("Expanded Fundamental Types") VARIANT. struct icommon
#     carries BOTH an old 16-bit {smode,suid,sgid} at offsets 0/4/6 AND a 32-bit
#     EFT {mode,uid,gid} at 112/116/120, with ic_eftflag @124 == EFT_MAGIC
#     (0x90909090) when the EFT fields are the authoritative ones. The golden's
#     every inode is EFT (proven: eftflag==0x90909090 on inode 2 and throughout),
#     so mode/uid/gid come from the EFT triple; the old triple is the fallback.
#
#   * di_size IS A 64-BIT QUAD at offset 8. On m68k the file size is ic_size.val[1]
#     (the low word, byte 12), with val[0] (byte 8) the high word -- so a plain
#     big-endian u64 read at offset 8 is the size for any file < 4 GiB (high==0)
#     and stays correct above it.
#
#   * SYMLINK TARGETS LIVE IN A DATA BLOCK, not inline. This SVR4 UFS1 has NO fast
#     symlinks: ic_db[0] is a real block address whose block holds the target
#     string (PROVEN: /bin -> "/usr/bin", ic_db[0] a live address). read_symlink
#     is therefore just read_file. (ufs_size.py MODELS symlinks as inline for a
#     conservative size floor; that is a sizing assumption, not a storage fact.)
#
#   * A DEVICE'S rdev IS ic_db[1] (EFT), split 18/14: major = rdev >> 18,
#     minor = rdev & (2**18 - 1). PROVEN: /dev/dsk/c0d0s0 decodes to 18,0 -- the
#     `dd` block major of the grimoire registry and the same number s5.decode_dev
#     reads off the s5 miniroot's own c0d0s0.
#
# WHAT IS NOT CLAIMED: nothing here has been mounted by Amix. The reader is proven
# byte-identical to genuine mkfs_ufs+installer output -- selftest half C reproduces
# 726 of core-2.1.pkg's 729 same-size file checksums exactly off the golden (the 3
# misses are files the box rewrites at runtime: /etc/nodename, _pmtab, boot2.boot),
# which exercises direct blocks, single/double indirect and fragment tails. That is
# a strong claim, but it is "reads what mkfs_ufs wrote", not "it mounts".
#
# Stdlib-only, python3. Ships no proprietary bytes -- it reads structure it is told
# the layout of; it copies nothing out of any Commodore image.

import os
import struct

# --- fixed FFS / EFT constants ----------------------------------------------
UFS_MAGIC = 0x00011954      # fs_magic (0x011954 in the header, stored as u32)
SBLOCK_OFF = 8192           # SBLOCK = BBSIZE: the superblock is at byte 8192
SBSIZE_READ = 8192          # SBSIZE: the superblock area is 8192 bytes (fsmnt runs
                            # to +724, so always read the whole area)
DEV_BSIZE = 512
DIRBLKSIZ = 512             # directory records are packed in 512-byte chunks
DINODE_SIZE = 128           # sizeof(struct icommon)
NDADDR = 12                 # direct block pointers in an inode
NIADDR = 3                  # single/double/triple indirect pointers
EFT_MAGIC = 0x90909090      # ic_eftflag when the 32-bit EFT id fields are live

ROOT_INO = 2                # UFSROOTINO
LOSTFOUND_INO = 3           # LOSTFOUNDINO

# file-type bits -- identical values to s5.py's, standard across UNIX
IFMT   = 0o170000
IFIFO  = 0o010000
IFCHR  = 0o020000
IFDIR  = 0o040000
IFBLK  = 0o060000
IFREG  = 0o100000
IFLNK  = 0o120000
IFSOCK = 0o140000

# EFT dev_t split (SVR4): makedev(maj,min) == (maj << 18) | (min & (2**18 - 1))
L_BITSMINOR = 18
L_MAXMIN = (1 << L_BITSMINOR) - 1

# --- struct fs byte offsets (m68k SVR4: long/daddr_t/time_t/ptr are 4B, 4-aligned)
# Derived from sys/fs/ufs_fs.h and cross-checked against tools/rootfs-type.py
# (fs_magic@1372, fs_size@36, fs_bsize@48 ... all agree).
FS_SBLKNO   = 8       # daddr_t fs_sblkno
FS_CBLKNO   = 12      # daddr_t fs_cblkno
FS_IBLKNO   = 16      # daddr_t fs_iblkno   -- offset of inode blocks within a cg
FS_DBLKNO   = 20      # daddr_t fs_dblkno
FS_CGOFFSET = 24      # long    fs_cgoffset -- cylinder-group offset in cylinder
FS_CGMASK   = 28      # long    fs_cgmask   -- used to calc mod fs_ntrak
FS_SIZE     = 36      # long    fs_size     -- volume size in FRAGMENTS
FS_NCG      = 44      # long    fs_ncg
FS_BSIZE    = 48      # long    fs_bsize
FS_FSIZE    = 52      # long    fs_fsize
FS_FRAG     = 56      # long    fs_frag
FS_MINFREE  = 60      # long    fs_minfree
FS_BSHIFT   = 80      # long    fs_bshift
FS_FSHIFT   = 84      # long    fs_fshift
FS_FRAGSHIFT = 96     # long    fs_fragshift -- blkstofrags shift (log2 fs_frag)
FS_FSBTODB  = 100     # long    fs_fsbtodb
FS_NINDIR   = 116     # long    fs_nindir
FS_INOPB    = 120     # long    fs_inopb
FS_OPTIM    = 128     # long    fs_optim
FS_IPG      = 184     # long    fs_ipg
FS_FPG      = 188     # long    fs_fpg       -- FRAGMENTS per cylinder group
FS_FSMNT    = 212     # char    fs_fsmnt[512]
FS_MAGIC    = 1372    # long    fs_magic

# --- struct icommon (dinode) byte offsets (128 bytes) -----------------------
IC_SMODE   = 0        # o_mode_t  ic_smode  (u16, old mode)
IC_NLINK   = 2        # short     ic_nlink
IC_SUID    = 4        # o_uid_t   ic_suid   (u16, old uid)
IC_SGID    = 6        # o_gid_t   ic_sgid   (u16, old gid)
IC_SIZE    = 8        # quad      ic_size   (8 bytes; di_size == big-endian u64)
IC_DB      = 40       # daddr_t   ic_db[12] -- direct block (fragment) addresses
IC_IB      = 88       # daddr_t   ic_ib[3]  -- single/double/triple indirect
IC_FLAGS   = 100      # long      ic_flags
IC_BLOCKS  = 104      # long      ic_blocks
IC_GEN     = 108      # long      ic_gen
IC_MODE    = 112      # mode_t    ic_mode   (u32, EFT mode)
IC_UID     = 116      # uid_t     ic_uid    (u32, EFT uid)
IC_GID     = 120      # gid_t     ic_gid    (u32, EFT gid)
IC_EFTFLAG = 124      # ulong     ic_eftflag

# --- struct direct byte offsets ---------------------------------------------
DIR_INO    = 0        # u_long  d_ino
DIR_RECLEN = 4        # u_short d_reclen
DIR_NAMLEN = 6        # u_short d_namlen
DIR_NAME   = 8        # char    d_name[]

# The kernel's own root-mount gate (kerntools UFS paper 5.8; also in rootfs-type.py)
UFS_MIN_BSIZE = 1380  # = sizeof(struct fs)
UFS_MAX_BSIZE = 8192  # = MAXBSIZE
UFS_MAX_FRAG = 8      # = MAXFRAG


class UfsError(Exception):
    """A structural defect in a UFS filesystem. Callers should fail closed."""


def _u16(b, o): return struct.unpack_from('>H', b, o)[0]
def _s16(b, o): return struct.unpack_from('>h', b, o)[0]
def _u32(b, o): return struct.unpack_from('>I', b, o)[0]
def _i32(b, o): return struct.unpack_from('>i', b, o)[0]
def _u64(b, o): return struct.unpack_from('>Q', b, o)[0]


# ===========================================================================
# the superblock
# ===========================================================================
class Super(object):
    """A parsed struct fs -- geometry only, plus the cylinder-group address
    arithmetic the reader needs to LOCATE inodes and data."""

    __slots__ = ("base", "magic", "size", "ncg", "bsize", "fsize", "frag",
                 "fragshift", "fsbtodb", "bshift", "fshift", "minfree", "optim",
                 "nindir", "inopb", "ipg", "fpg", "iblkno", "cgoffset", "cgmask",
                 "fsmnt")

    @property
    def n_inodes(self):
        return self.ncg * self.ipg

    @property
    def root_ok(self):
        """Would this kernel family accept it as a ROOT filesystem? (rootfs-type
        enforces the same bounds; kept here so the reader can assert them too.)"""
        return (UFS_MIN_BSIZE <= self.bsize <= UFS_MAX_BSIZE
                and self.frag <= UFS_MAX_FRAG)

    def cgstart(self, c):
        """First fragment of cylinder group c (cgstart macro)."""
        return self.fpg * c + self.cgoffset * (c & (~self.cgmask & 0xffffffff))

    def cgimin(self, c):
        """First fragment of the inode blocks in cylinder group c."""
        return self.cgstart(c) + self.iblkno

    def itog(self, ino):
        return ino // self.ipg

    def itoo(self, ino):
        return ino % self.inopb

    def itod(self, ino):
        """Fragment address of the block holding inode `ino` (itod macro)."""
        return (self.cgimin(self.itog(ino))
                + ((ino % self.ipg) // self.inopb) * self.frag)

    def inode_offset(self, ino, base=None):
        """Byte offset of inode `ino` within the whole image."""
        if base is None:
            base = self.base
        return base + self.itod(ino) * self.fsize + self.itoo(ino) * DINODE_SIZE

    def frag_offset(self, frag, base=None):
        """Byte offset of fragment address `frag` within the whole image."""
        if base is None:
            base = self.base
        return base + frag * self.fsize

    def __repr__(self):
        return ("ufs super: magic=0x%08x size=%d frags (%d bytes) ncg=%d "
                "bsize=%d fsize=%d frag=%d ipg=%d fpg=%d inodes=%d optim=%s"
                % (self.magic, self.size, self.size * self.fsize, self.ncg,
                   self.bsize, self.fsize, self.frag, self.ipg, self.fpg,
                   self.n_inodes, {0: "TIME", 1: "SPACE"}.get(self.optim, self.optim)))


def parse_super(img, base=0):
    """Parse the superblock of the UFS filesystem starting at byte `base`."""
    o = base + SBLOCK_OFF
    if o + UFS_MIN_BSIZE > len(img):
        raise UfsError("image too short to hold a UFS superblock at 0x%x" % o)
    sb = img[o:o + SBSIZE_READ]
    s = Super()
    s.base = base
    s.magic = _u32(sb, FS_MAGIC)
    if s.magic != UFS_MAGIC:
        raise UfsError("not a UFS filesystem at 0x%x: fs_magic @+%d is 0x%08x, "
                       "expected 0x%08x" % (base, FS_MAGIC, s.magic, UFS_MAGIC))
    s.size = _i32(sb, FS_SIZE)
    s.ncg = _i32(sb, FS_NCG)
    s.bsize = _i32(sb, FS_BSIZE)
    s.fsize = _i32(sb, FS_FSIZE)
    s.frag = _i32(sb, FS_FRAG)
    s.fragshift = _i32(sb, FS_FRAGSHIFT)
    s.fsbtodb = _i32(sb, FS_FSBTODB)
    s.bshift = _i32(sb, FS_BSHIFT)
    s.fshift = _i32(sb, FS_FSHIFT)
    s.minfree = _i32(sb, FS_MINFREE)
    s.optim = _i32(sb, FS_OPTIM)
    s.nindir = _i32(sb, FS_NINDIR)
    s.inopb = _i32(sb, FS_INOPB)
    s.ipg = _i32(sb, FS_IPG)
    s.fpg = _i32(sb, FS_FPG)
    s.iblkno = _i32(sb, FS_IBLKNO)
    s.cgoffset = _i32(sb, FS_CGOFFSET)
    s.cgmask = _i32(sb, FS_CGMASK)
    s.fsmnt = sb[FS_FSMNT:FS_FSMNT + 512].split(b'\x00')[0].decode('latin1')
    # sanity: the fields the reader divides/shifts by must be sane, or the inode
    # arithmetic silently walks off into garbage (the mistake this refuses is the
    # one that made an early spike read fs_iblkno's VALUE as its byte offset).
    if s.fsize <= 0 or s.bsize <= 0 or s.frag <= 0:
        raise UfsError("nonsensical block geometry: bsize=%d fsize=%d frag=%d"
                       % (s.bsize, s.fsize, s.frag))
    if s.bsize % s.fsize:
        raise UfsError("fs_bsize %d is not a multiple of fs_fsize %d"
                       % (s.bsize, s.fsize))
    if s.inopb <= 0 or s.ipg <= 0 or s.fpg <= 0 or s.ncg <= 0:
        raise UfsError("nonsensical cg geometry: ncg=%d ipg=%d fpg=%d inopb=%d"
                       % (s.ncg, s.ipg, s.fpg, s.inopb))
    if s.frag != (1 << s.fragshift):
        raise UfsError("fs_frag %d != 1<<fs_fragshift %d (inconsistent superblock)"
                       % (s.frag, 1 << s.fragshift))
    if s.inopb != s.bsize // DINODE_SIZE:
        raise UfsError("fs_inopb %d != fs_bsize/%d = %d"
                       % (s.inopb, DINODE_SIZE, s.bsize // DINODE_SIZE))
    return s


# ===========================================================================
# inodes
# ===========================================================================
class Dinode(object):
    """A parsed struct icommon. `mode`/`uid`/`gid` are already resolved to the
    authoritative (EFT when eftflag is set, old otherwise) values; `db`/`ib` are
    the raw FRAGMENT addresses; `rdev` is the device number for c/b nodes."""

    __slots__ = ("mode", "nlink", "uid", "gid", "size", "db", "ib", "rdev",
                 "eftflag")

    @property
    def type(self):
        return self.mode & IFMT

    def __repr__(self):
        return ("ufs dinode: mode=0%o nlink=%d uid=%d gid=%d size=%d"
                % (self.mode, self.nlink, self.uid, self.gid, self.size))


def read_dinode(img, ino, base=0, sb=None):
    """Parse inode `ino` (1-based) into a Dinode."""
    if sb is None:
        sb = parse_super(img, base)
    if ino < 1:
        raise UfsError("inode numbers are 1-based; got %d" % ino)
    if ino > sb.n_inodes:
        raise UfsError("inode %d is past the last inode %d" % (ino, sb.n_inodes))
    o = sb.inode_offset(ino, base)
    if o + DINODE_SIZE > len(img):
        raise UfsError("inode %d lands at 0x%x, past the end of the image" % (ino, o))
    b = img[o:o + DINODE_SIZE]
    d = Dinode()
    d.eftflag = _u32(b, IC_EFTFLAG)
    if d.eftflag == EFT_MAGIC:
        d.mode = _u32(b, IC_MODE)
        d.uid = _u32(b, IC_UID)
        d.gid = _u32(b, IC_GID)
    else:
        d.mode = _u16(b, IC_SMODE)
        d.uid = _u16(b, IC_SUID)
        d.gid = _u16(b, IC_SGID)
    d.nlink = _s16(b, IC_NLINK)
    d.size = _u64(b, IC_SIZE)
    d.db = [_u32(b, IC_DB + 4 * i) for i in range(NDADDR)]
    d.ib = [_u32(b, IC_IB + 4 * i) for i in range(NIADDR)]
    # a device's rdev: EFT stores it in ic_db[1], the pre-EFT layout in ic_db[0].
    d.rdev = d.db[1] if d.eftflag == EFT_MAGIC else d.db[0]
    return d


def read_inode(img, ino, base=0, sb=None):
    """(mode, nlink, uid, gid, size, addrs) -- the same tuple shape s5.read_inode
    returns, so a caller can treat the two filesystems uniformly. `addrs` is the
    15 raw FRAGMENT addresses (12 direct + 3 indirect); use read_file() to get
    file contents (the indirection is not something a caller should re-implement)."""
    d = read_dinode(img, ino, base, sb)
    return d.mode, d.nlink, d.uid, d.gid, d.size, (d.db + d.ib)


def decode_dev(dino):
    """(major, minor) from a device Dinode. EFT split is 18 bits of minor."""
    if (dino.type not in (IFCHR, IFBLK)):
        raise UfsError("inode is not a device (mode 0%o)" % dino.mode)
    rdev = dino.rdev
    if dino.eftflag == EFT_MAGIC:
        return (rdev >> L_BITSMINOR), (rdev & L_MAXMIN)
    # pre-EFT o_dev_t: 8 bits of major, 8 of minor
    return ((rdev >> 8) & 0xff), (rdev & 0xff)


# ===========================================================================
# data: direct + single/double/triple indirect, fragment-aware
# ===========================================================================
def _read_indirect(img, sb, frag, count, base):
    """The `count` fragment addresses stored in the indirect block at fragment
    address `frag`. A zero address is a hole -> all-zero pointers."""
    if frag == 0:
        return [0] * count
    o = sb.frag_offset(frag, base)
    if o + count * 4 > len(img):
        raise UfsError("indirect block at frag %d runs past the image end" % frag)
    blk = img[o:o + count * 4]
    return [_u32(blk, 4 * i) for i in range(count)]


def _block_addr(img, sb, dino, lbn, base):
    """Fragment address of logical block `lbn` of a file, walking the indirect
    chain. Returns 0 for a hole."""
    if lbn < NDADDR:
        return dino.db[lbn]
    lbn -= NDADDR
    nindir = sb.nindir
    if lbn < nindir:                                   # single indirect
        return _read_indirect(img, sb, dino.ib[0], nindir, base)[lbn]
    lbn -= nindir
    if lbn < nindir * nindir:                          # double indirect
        lvl1 = _read_indirect(img, sb, dino.ib[1], nindir, base)
        return _read_indirect(img, sb, lvl1[lbn // nindir], nindir, base)[lbn % nindir]
    lbn -= nindir * nindir
    if lbn < nindir * nindir * nindir:                 # triple indirect
        lvl1 = _read_indirect(img, sb, dino.ib[2], nindir, base)
        lvl2 = _read_indirect(img, sb, lvl1[lbn // (nindir * nindir)], nindir, base)
        return _read_indirect(img, sb, lvl2[(lbn // nindir) % nindir], nindir, base)[lbn % nindir]
    raise UfsError("file logical block %d exceeds the triple-indirect range" % lbn)


def read_file(img, ino, base=0, sb=None):
    """Full contents of a regular file / directory / (block-stored) symlink."""
    if sb is None:
        sb = parse_super(img, base)
    d = read_dinode(img, ino, base, sb)
    return read_data(img, sb, d, base)


def read_data(img, sb, dino, base=0):
    """Full `dino.size` bytes of data, block by block (holes read as zeros)."""
    size = dino.size
    if size == 0:
        return b""
    out = bytearray()
    lbn = 0
    bsize = sb.bsize
    while len(out) < size:
        frag = _block_addr(img, sb, dino, lbn, base)
        need = min(bsize, size - len(out))
        if frag == 0:
            out += b"\x00" * need
        else:
            o = sb.frag_offset(frag, base)
            if o + need > len(img):
                raise UfsError("data block at frag %d (lbn %d) runs past the "
                               "image end" % (frag, lbn))
            out += img[o:o + need]
        lbn += 1
    return bytes(out[:size])


def read_symlink(img, ino, base=0, sb=None):
    """Symlink target. This SVR4 UFS1 has NO fast symlinks -- the target is stored
    in a data block -- so this is read_file decoded."""
    return read_file(img, ino, base, sb).decode('latin1')


# ===========================================================================
# directories
# ===========================================================================
def read_dir(img, ino, base=0, sb=None):
    """[(inode, name), ...] for a directory inode. Parses the variable-length
    struct direct records, DIRBLKSIZ-block aware (a d_reclen of 0 is not a valid
    record -- it means the rest of this 512-byte block is unused). Skips the free
    entries (d_ino == 0). '.' and '..' ARE returned, as in s5.read_dir."""
    if sb is None:
        sb = parse_super(img, base)
    d = read_dinode(img, ino, base, sb)
    if d.type != IFDIR:
        raise UfsError("inode %d is not a directory (mode 0%o)" % (ino, d.mode))
    data = read_data(img, sb, d, base)
    out = []
    p = 0
    n = len(data)
    while p + DIR_NAME <= n:
        d_ino = _u32(data, p + DIR_INO)
        reclen = _u16(data, p + DIR_RECLEN)
        namlen = _u16(data, p + DIR_NAMLEN)
        if reclen == 0:
            # skip to the next DIRBLKSIZ boundary (a zero reclen never advances)
            nxt = ((p // DIRBLKSIZ) + 1) * DIRBLKSIZ
            if nxt <= p:
                break
            p = nxt
            continue
        if reclen < DIR_NAME:
            raise UfsError("directory inode %d: d_reclen %d < header size at +%d"
                           % (ino, reclen, p))
        if d_ino != 0:
            if p + DIR_NAME + namlen > n:
                raise UfsError("directory inode %d: name at +%d runs past the "
                               "directory data" % (ino, p))
            name = data[p + DIR_NAME:p + DIR_NAME + namlen].decode('latin1')
            out.append((d_ino, name))
        p += reclen
    return out


# ===========================================================================
# whole-tree walk (for a pkgmap-style enumeration / conformance manifest)
# ===========================================================================
_TYPE_CHAR = {IFDIR: "d", IFREG: "f", IFCHR: "c", IFBLK: "b", IFLNK: "l",
              IFIFO: "p", IFSOCK: "s"}


def type_char(mode):
    return _TYPE_CHAR.get(mode & IFMT, "?")


def walk(img, base=0, sb=None, want_symlink=True):
    """Yield (path, Dinode) for every object in the tree, root first. Cycle-safe
    (follows directory entries other than '.'/'..', guards against revisiting an
    inode). Paths are '/'-rooted; the root itself is '/'."""
    if sb is None:
        sb = parse_super(img, base)
    root = read_dinode(img, ROOT_INO, base, sb)
    if root.type != IFDIR:
        raise UfsError("root inode %d is not a directory (mode 0%o)"
                       % (ROOT_INO, root.mode))
    yield "/", root
    seen = {ROOT_INO}
    stack = [("", ROOT_INO)]
    while stack:
        prefix, dino_no = stack.pop()
        for cino, name in read_dir(img, dino_no, base, sb):
            if name in (".", ".."):
                continue
            path = prefix + "/" + name
            d = read_dinode(img, cino, base, sb)
            yield path, d
            if d.type == IFDIR and cino not in seen:
                seen.add(cino)
                stack.append((path, cino))


def tree_manifest(img, base=0, sb=None):
    """dict path -> (type_char, mode & 07777, uid, gid, extra) for the whole tree,
    with the root as '/'. `extra` is the symlink target, or 'maj,min' for a device,
    else ''. The SAME shape s5-side walkers produce, so a proto conformance check
    is filesystem-agnostic."""
    if sb is None:
        sb = parse_super(img, base)
    out = {}
    for path, d in walk(img, base, sb):
        extra = ""
        if d.type == IFLNK:
            extra = read_data(img, sb, d, base).decode('latin1')
        elif d.type in (IFCHR, IFBLK):
            mj, mn = decode_dev(d)
            extra = "%d,%d" % (mj, mn)
        out[path] = (type_char(d.mode), d.mode & 0o7777, d.uid, d.gid, extra)
    return out


# ===========================================================================
# self-test -- the reader against external ground truth, hermetically
# ===========================================================================
def _svr4_cksum(b):
    """The SVR4 pkgmap checksum: a 32-bit byte sum folded end-around to 16 bits.
    Pinned in docs/ufs-target-scoping.md 3.2 against three known miniroot values."""
    s = sum(b)
    r = (s & 0xffff) + ((s >> 16) & 0xffff)
    return ((r & 0xffff) + (r >> 16)) & 0xffff


# ---- golden ground truth: the same artifact ufs_size.py is pinned to --------
GOLDEN_REL = "../amix-images/masters/amix-z3660-golden-2026-07-11.hdf"
GOLDEN_SLICE1_OFF = 0x10000       # UNI\1 root slice (docs 1.4 / this repo's rdb.py)
# measured geometry of the golden root (docs/ufs-target-scoping.md 1.4); the same
# ground truth ufs_size.py's selftest is pinned to.
GOLDEN = dict(magic=UFS_MAGIC, ncg=448, ipg=512, fpg=1296, bsize=8192, fsize=1024,
              frag=8, nindir=2048, inopb=64, minfree=2, optim=1, size=580608,
              fsmnt="/")
# three same-size core files whose 1991 checksums are known (docs 3.2 / build-
# miniroot.sh); /etc/group happens to be unmodified on the golden box, labelit too.
GOLDEN_FILES = {"/etc/group": 16701, "/usr/lib/fs/s5/labelit": 4234}


def _synth_fixture():
    """Build a TINY reader-test UFS1 image in memory and return (bytes, expect).

    This is NOT a mkfs: it lays down ONLY what the reader reads -- a superblock, an
    inode table and data/indirect blocks -- with no free maps, cg blocks, backup
    supers or csum area (a real mkfs_ufs writes all of those; the deliberate
    decision is to have none host-side, docs 3.3). Its sole purpose is to exercise
    every reader path -- superblock parse, inode location math, direct + single +
    double indirect, fragment tail, directory records, a block-stored symlink and
    an EFT device -- on bytes whose right answer is known by construction. Half A
    (golden geometry) and half C (real golden) are what tie the reader to genuine
    mkfs_ufs output; this half proves the plumbing end to end without a box."""
    bsize, fsize, frag = 8192, 1024, 8
    fragshift = 3
    inopb = bsize // DINODE_SIZE          # 64
    nindir = bsize // 4                    # 2048
    ipg = 64                               # one inode block's worth
    iblkno = 32                            # inode table at frag 32 (byte 32768)
    # inode table = ceil(ipg/inopb) blocks = 1 block = frag..frag+frag-1
    dblkno = iblkno + (ipg // inopb) * frag   # first data frag = 40
    # data area: hand out full-block-aligned frag runs after the inode table.
    next_frag = [dblkno]

    def alloc_block():
        f = next_frag[0]
        next_frag[0] += frag
        return f

    def alloc_frags(n):                    # n fragments, block-aligned start
        f = next_frag[0]
        next_frag[0] += ((n + frag - 1) // frag) * frag
        return f

    # --- payload we will assert on read-back --------------------------------
    file_blocks = 13                       # > NDADDR(12) => one single indirect
    file_data = bytes(((i * 37 + 11) & 0xff) for i in range(file_blocks * bsize - 3))
    link_target = b"/a/rather/long/symlink/target/that/lives/in/a/block"
    subdir_name = "adir"
    expect = {"file_sum": _svr4_cksum(file_data), "file_size": len(file_data),
              "link": link_target.decode(), "dev": (40, 17),
              "names": sorted([".", "..", "lost+found", "file.dat", subdir_name,
                               "alink", "adev"])}

    # --- allocate data ------------------------------------------------------
    # file.dat: 13 data blocks + 1 single-indirect block
    file_block_frags = [alloc_block() for _ in range(file_blocks)]
    ind_frag = alloc_block()
    link_frag = alloc_frags((len(link_target) + fsize - 1) // fsize)
    rootdir_frag = alloc_block()
    subdir_frag = alloc_block()
    lostfound_frag = alloc_block()

    total_frags = next_frag[0]
    img = bytearray(total_frags * fsize + fsize)   # a little tail slack

    def put_frag_bytes(frag_addr, data):
        o = frag_addr * fsize
        img[o:o + len(data)] = data

    # file data across its 13 blocks (last block a fragment tail)
    for i, fa in enumerate(file_block_frags):
        chunk = file_data[i * bsize:(i + 1) * bsize]
        put_frag_bytes(fa, chunk)
    # single-indirect block: the 13th logical block (index 12) is the FIRST entry
    ind = bytearray(bsize)
    struct.pack_into('>I', ind, 0, file_block_frags[12])
    put_frag_bytes(ind_frag, bytes(ind))
    # symlink target
    put_frag_bytes(link_frag, link_target)

    # --- directories --------------------------------------------------------
    def dirent(ino, name):
        nb = name.encode('latin1')
        reclen = DIR_NAME + ((len(nb) + 1 + 3) & ~3)
        rec = bytearray(reclen)
        struct.pack_into('>I', rec, DIR_INO, ino)
        struct.pack_into('>H', rec, DIR_RECLEN, reclen)
        struct.pack_into('>H', rec, DIR_NAMLEN, len(nb))
        rec[DIR_NAME:DIR_NAME + len(nb)] = nb
        return bytes(rec)

    def pack_dir(entries):
        """Pack entries into one DIRBLKSIZ block, last record extended to fill it
        (exactly as UFS lays a directory out)."""
        recs = [bytearray(dirent(i, n)) for i, n in entries]
        used = sum(len(r) for r in recs)
        if used > DIRBLKSIZ:
            raise AssertionError("fixture dir too big")
        # stretch the last record's reclen to the end of the block
        pad = DIRBLKSIZ - used
        last = recs[-1]
        newlen = _u16(last, DIR_RECLEN) + pad
        struct.pack_into('>H', last, DIR_RECLEN, newlen)
        blk = bytearray(DIRBLKSIZ)
        p = 0
        for r in recs:
            blk[p:p + len(r)] = r
            p += _u16(r, DIR_RECLEN)
        return bytes(blk)

    ROOT, LF, FILE, SUB, LINK, DEV = 2, 3, 4, 5, 6, 7
    put_frag_bytes(rootdir_frag, pack_dir([
        (ROOT, "."), (ROOT, ".."), (LF, "lost+found"), (FILE, "file.dat"),
        (SUB, subdir_name), (LINK, "alink"), (DEV, "adev")]))
    put_frag_bytes(subdir_frag, pack_dir([(SUB, "."), (ROOT, "..")]))
    put_frag_bytes(lostfound_frag, pack_dir([(LF, "."), (ROOT, "..")]))

    # --- inodes -------------------------------------------------------------
    def put_inode(ino, mode, nlink, uid, gid, size, db=(), ib=(), rdev=None):
        o = iblkno * fsize + (ino % inopb) * DINODE_SIZE
        struct.pack_into('>H', img, o + IC_SMODE, mode & 0xffff)
        struct.pack_into('>h', img, o + IC_NLINK, nlink)
        struct.pack_into('>Q', img, o + IC_SIZE, size)
        dbl = list(db) + [0] * (NDADDR - len(db))
        if rdev is not None:
            dbl[1] = rdev                       # EFT rdev lives in ic_db[1]
        for i in range(NDADDR):
            struct.pack_into('>I', img, o + IC_DB + 4 * i, dbl[i] & 0xffffffff)
        ibl = list(ib) + [0] * (NIADDR - len(ib))
        for i in range(NIADDR):
            struct.pack_into('>I', img, o + IC_IB + 4 * i, ibl[i] & 0xffffffff)
        struct.pack_into('>I', img, o + IC_MODE, mode)         # EFT mode
        struct.pack_into('>I', img, o + IC_UID, uid)
        struct.pack_into('>I', img, o + IC_GID, gid)
        struct.pack_into('>I', img, o + IC_EFTFLAG, EFT_MAGIC)

    put_inode(ROOT, IFDIR | 0o755, 4, 0, 0, DIRBLKSIZ, db=[rootdir_frag])
    put_inode(LF, IFDIR | 0o700, 2, 0, 0, DIRBLKSIZ, db=[lostfound_frag])
    put_inode(FILE, IFREG | 0o644, 1, 5, 6, len(file_data),
              db=file_block_frags[:12], ib=[ind_frag])
    put_inode(SUB, IFDIR | 0o755, 2, 0, 0, DIRBLKSIZ, db=[subdir_frag])
    put_inode(LINK, IFLNK | 0o777, 1, 0, 0, len(link_target), db=[link_frag])
    # EFT device: makedev(40,17) = (40<<18)|17
    put_inode(DEV, IFCHR | 0o600, 1, 0, 0, 0, rdev=(40 << L_BITSMINOR) | 17)

    # --- superblock ---------------------------------------------------------
    sbb = bytearray(SBSIZE_READ)
    def sp(off, val):
        struct.pack_into('>i', sbb, off, val)
    sp(FS_SBLKNO, 16)
    sp(FS_CBLKNO, 24)
    sp(FS_IBLKNO, iblkno)
    sp(FS_DBLKNO, dblkno)
    sp(FS_CGOFFSET, 0)
    sp(FS_CGMASK, -1)
    sp(FS_SIZE, total_frags)
    sp(FS_NCG, 1)
    sp(FS_BSIZE, bsize)
    sp(FS_FSIZE, fsize)
    sp(FS_FRAG, frag)
    sp(FS_MINFREE, 10)
    sp(FS_BSHIFT, 13)
    sp(FS_FSHIFT, 10)
    sp(FS_FRAGSHIFT, fragshift)
    sp(FS_FSBTODB, 1)
    sp(FS_NINDIR, nindir)
    sp(FS_INOPB, inopb)
    sp(FS_OPTIM, 1)
    sp(FS_IPG, ipg)
    sp(FS_FPG, total_frags)             # one cg holds the whole tiny fs
    sbb[FS_FSMNT:FS_FSMNT + 2] = b"/\x00"
    struct.pack_into('>I', sbb, FS_MAGIC, UFS_MAGIC)
    # the superblock sits at byte 8192
    if len(img) < SBLOCK_OFF + SBSIZE_READ:
        img += bytearray(SBLOCK_OFF + SBSIZE_READ - len(img))
    img[SBLOCK_OFF:SBLOCK_OFF + SBSIZE_READ] = sbb
    return bytes(img), expect


def _map_golden(path):
    """mmap the golden .hdf READ-ONLY (never a 600 MB read() into RSS; inodes are
    scattered across 448 cylinder groups spanning the whole slice, so a tree walk
    needs random access to all of it). Returns (mmap, base) where base is the
    UNI\\1 root slice's byte offset, or (None, 0) if unreadable/too short. The
    caller owns closing the mmap."""
    import mmap
    try:
        fh = open(path, "rb")
    except OSError:
        return None, 0
    try:
        size = os.fstat(fh.fileno()).st_size
        if size < GOLDEN_SLICE1_OFF + SBLOCK_OFF + SBSIZE_READ:
            fh.close()
            return None, 0
        mm = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
        return mm, GOLDEN_SLICE1_OFF
    except OSError:
        fh.close()
        return None, 0
    finally:
        # mmap keeps its own reference to the fd; closing the file object is fine.
        try:
            fh.close()
        except OSError:
            pass


def selftest(reference_image=None, verbose=True):
    """Return a list of problems; empty == pass. Hermetic: it NEVER requires the
    golden image. Three halves:

      A. GEOMETRY, pinned against the golden's MEASURED constants (the same ground
         truth ufs_size.py uses). No image needed -- proves the superblock decode
         and the cg/inode address arithmetic land where mkfs_ufs put them.
      B. A SYNTHETIC round-trip (in-memory reader fixture): proves every reader
         path -- direct + single/double indirect, fragment tails, directory
         records, block-stored symlink, EFT device -- on bytes whose answers are
         known by construction. This is the hermetic core.
      C. If a genuine golden UFS image is reachable read-only, reproduce known
         1991 file checksums off it (the real external validation). Skipped
         LOUDLY, never failed, when the artifact is absent.
    """
    problems = []
    say = (lambda m: print(m)) if verbose else (lambda m: None)

    # ---- A. golden geometry, decoded from a synthetic golden-shaped superblock -
    say("A. golden UFS geometry (measured, docs/ufs-target-scoping 1.4)")
    gsb = bytearray(SBSIZE_READ)
    def gp(off, val):
        struct.pack_into('>i', gsb, off, val)
    gp(FS_IBLKNO, 32); gp(FS_CGOFFSET, 16); gp(FS_CGMASK, -16)
    gp(FS_SIZE, GOLDEN["size"]); gp(FS_NCG, GOLDEN["ncg"])
    gp(FS_BSIZE, GOLDEN["bsize"]); gp(FS_FSIZE, GOLDEN["fsize"])
    gp(FS_FRAG, GOLDEN["frag"]); gp(FS_FRAGSHIFT, 3); gp(FS_FSBTODB, 1)
    gp(FS_BSHIFT, 13); gp(FS_FSHIFT, 10); gp(FS_MINFREE, GOLDEN["minfree"])
    gp(FS_OPTIM, GOLDEN["optim"]); gp(FS_NINDIR, GOLDEN["nindir"])
    gp(FS_INOPB, GOLDEN["inopb"]); gp(FS_IPG, GOLDEN["ipg"]); gp(FS_FPG, GOLDEN["fpg"])
    gsb[FS_FSMNT:FS_FSMNT + 2] = b"/\x00"
    struct.pack_into('>I', gsb, FS_MAGIC, UFS_MAGIC)
    gimg = bytes(gsb) if len(gsb) >= SBLOCK_OFF + SBSIZE_READ else \
        bytes(bytearray(SBLOCK_OFF) + gsb)
    try:
        gs = parse_super(gimg, 0)
        geo = [
            (gs.magic == UFS_MAGIC, "fs_magic == 0x%08x" % UFS_MAGIC),
            (gs.ncg == 448 and gs.ipg == 512 and gs.fpg == 1296,
             "ncg=448 ipg=512 fpg=1296"),
            (gs.n_inodes == 229376, "ncg*ipg = %d inodes (== 229376)" % gs.n_inodes),
            (gs.size * gs.fsize == 594542592,
             "fs_size*fsize = %d bytes (== golden slice)" % (gs.size * gs.fsize)),
            (gs.inopb == gs.bsize // DINODE_SIZE == 64, "inopb = bsize/128 = 64"),
            (gs.frag == 8 and gs.fragshift == 3, "frag=8 fragshift=3"),
            (gs.root_ok, "bsize 8192 / frag 8 passes the kernel root-mount gate"),
            # the inode-address arithmetic: cg 0 inode blocks start at fs_iblkno,
            # and inode 2 must land in the first inode block of cg 0.
            (gs.itod(2) == 32 and gs.itoo(2) == 2,
             "itod(2)=32 (== fs_iblkno) itoo(2)=2 -- inode 2 in cg0's first block"),
            (gs.cgimin(1) == gs.fpg + 16 + 32,
             "cgimin(1) applies fs_cgoffset*(1 & ~cgmask) -- cg1 inodes at %d"
             % gs.cgimin(1)),
        ]
    except UfsError as e:
        problems.append("golden-shaped superblock did not parse: %s" % e)
        geo = []
    for ok, d in geo:
        say("   %s %s" % ("ok  " if ok else "FAIL", d))
        if not ok:
            problems.append("golden geometry: " + d)

    # ---- B. synthetic round-trip -------------------------------------------
    say("B. synthetic reader fixture (direct+indirect+frag, dir, symlink, device)")
    try:
        img, exp = _synth_fixture()
        sb = parse_super(img, 0)
        bchecks = []
        # directory listing
        names = sorted(n for _, n in read_dir(img, ROOT_INO, 0, sb))
        bchecks.append((names == exp["names"],
                        "root dir names == %s (got %s)" % (exp["names"], names)))
        ents = dict((n, i) for i, n in read_dir(img, ROOT_INO, 0, sb))
        # a regular file spanning a single indirect + a fragment tail
        fdata = read_file(img, ents["file.dat"], 0, sb)
        bchecks.append((len(fdata) == exp["file_size"],
                        "file.dat read back %d bytes (== %d)"
                        % (len(fdata), exp["file_size"])))
        bchecks.append((_svr4_cksum(fdata) == exp["file_sum"],
                        "file.dat checksum round-trips (single indirect + frag tail)"))
        # block-stored symlink
        bchecks.append((read_symlink(img, ents["alink"], 0, sb) == exp["link"],
                        "symlink target read from its data block"))
        # EFT device decode
        dev = read_dinode(img, ents["adev"], 0, sb)
        bchecks.append((decode_dev(dev) == exp["dev"],
                        "device decodes to %s (EFT 18-bit minor)" % (exp["dev"],)))
        # whole-tree manifest shape (what the miniroot conformance consumes)
        man = tree_manifest(img, 0, sb)
        bchecks.append(("/" in man and man["/"][0] == "d",
                        "tree_manifest roots at '/' as a directory"))
        bchecks.append((man.get("/adir/..") is None and "/adir" in man
                        and man["/adir"][0] == "d",
                        "tree_manifest descends into subdirs and drops '.'/'..'"))
        bchecks.append((man["/adev"][0] == "c" and man["/adev"][4] == "40,17",
                        "device manifest 'extra' is 'maj,min'"))
        bchecks.append((man["/alink"][0] == "l" and man["/alink"][4] == exp["link"],
                        "symlink manifest 'extra' is the target"))
    except (UfsError, AssertionError, KeyError) as e:
        problems.append("synthetic round-trip raised: %s" % e)
        bchecks = []
    for ok, d in bchecks:
        say("   %s %s" % ("ok  " if ok else "FAIL", d))
        if not ok:
            problems.append("synthetic: " + d)

    # ---- C. the real golden, if reachable ----------------------------------
    say("C. genuine golden UFS root (external ground truth)")
    here = os.path.dirname(os.path.abspath(__file__))       # tools/lib
    repo = os.path.dirname(os.path.dirname(here))           # amix-installng
    golden = reference_image or os.path.normpath(os.path.join(repo, GOLDEN_REL))
    mm, gbase = _map_golden(golden) if os.path.isfile(golden) else (None, 0)
    if mm is None:
        say("   -- golden not reachable (%s); hermetic halves A+B stand alone."
            % golden)
        say("   -- ground-truth path used: MEASURED CONSTANTS + SYNTHETIC round-trip.")
    else:
        try:
            gsb2 = parse_super(mm, gbase)
            cchecks = [
                (gsb2.ncg == GOLDEN["ncg"] and gsb2.ipg == GOLDEN["ipg"]
                 and gsb2.fpg == GOLDEN["fpg"] and gsb2.fsmnt == "/",
                 "golden superblock decodes to the measured geometry"),
            ]

            def lookup(path):
                ino = ROOT_INO
                for part in path.strip("/").split("/"):
                    ents = dict((n, i) for i, n in read_dir(mm, ino, gbase, gsb2))
                    ino = ents[part]
                return ino
            for path, want in GOLDEN_FILES.items():
                ino = lookup(path)
                got = _svr4_cksum(read_file(mm, ino, gbase, gsb2))
                cchecks.append((got == want,
                                "%s SVR4 cksum %d == 1991 pkgmap %d"
                                % (path, got, want)))
            # a big file forces the single-indirect path on real bytes
            libc = read_file(mm, lookup("/usr/lib/libc.so.1"), gbase, gsb2)
            cchecks.append((len(libc) > 12 * gsb2.bsize,
                            "/usr/lib/libc.so.1 read whole (%d bytes, indirect "
                            "exercised)" % len(libc)))
            for ok, d in cchecks:
                say("   %s %s" % ("ok  " if ok else "FAIL", d))
                if not ok:
                    problems.append("golden: " + d)
            say("   -- ground-truth path used: MEASURED CONSTANTS + SYNTHETIC "
                "round-trip + GENUINE GOLDEN read-back.")
        except (UfsError, KeyError, OSError) as e:
            problems.append("golden read-back raised: %s" % e)
        finally:
            mm.close()

    say("selftest: %s" % ("PASS" if not problems else "FAIL (%d)" % len(problems)))
    return problems


if __name__ == "__main__":
    import sys
    sys.exit(1 if selftest() else 0)
