#!/usr/bin/env python3
"""patch-ufs-fp.py -- BLIZZARD F2-M1: take the FP out of mkfs_ufs and fsck_ufs.

The stock Amix 2.1 ufs tools execute floating point in exactly two places, both of
them display-only, and both fatal on a 68060 with no FPU (BLIZZARD census):

  /etc/fs/ufs/mkfs   9 FP instructions feeding "\\t%.1fMb in %d cyl groups
                     (%d c/g, %.2fMb/g, %d i/g)\\n" -- printed BEFORE any filesystem
                     is written, so no ufs target can be created at all.
  /etc/fs/ufs/fsck   4 FP instructions feeding "(%d frags, %d blocks, %.1f%%
                     fragmentation)\\n" -- printed AFTER all repairs but UPSTREAM of
                     everything that marks the filesystem clean, so a dirty root can
                     never be recovered in place.

This rewrites both expressions in exact integer arithmetic that renders the same
columns to the same precision.  Nothing else changes: no byte outside the sites
listed below moves, no section moves, no file grows.  The full design, the
measurement it rests on and the pre-registered acceptance are in
docs/blizzard-f2m1.md.

The same patch applies to the miniroot members (/bin/mkfs_ufs, /bin/fsck_ufs on the
stock root floppy) and to the installed ones (/etc/fs/ufs/{mkfs,fsck}): their mapped
images are byte-identical, only the ELF header's e_shoff/e_shnum differ.

The patched binaries are derived Commodore bytes -- never commit them.  What is
committed is this tool, the assembly in tools/blizzard-f2m1/, and the old-byte
signatures it asserts.

usage:
  patch-ufs-fp.py --check FILE...              report state, write nothing
  patch-ufs-fp.py FILE...                      patch in place (idempotent)
  patch-ufs-fp.py -o OUT FILE                  patch to a new file
  patch-ufs-fp.py --s5 IMAGE [--check] PATH... patch members inside an s5 image
                                               (length-preserving, so the inode,
                                               the size and the block list are
                                               untouched)
  patch-ufs-fp.py --ufs IMAGE [--slice N] [--check] PATH...
                                               the same, inside a ufs filesystem --
                                               this is how the INSTALLED tree's
                                               /etc/fs/ufs/{mkfs,fsck} get patched,
                                               because they arrive from the CD's
                                               core package unpatched and pkgadd
                                               checksums the package
  patch-ufs-fp.py --self-test                  hermetic gate on the ufs locator and
                                               the in-place write-back

The --ufs mode is NOT a host-side UFS writer (docs/ufs-target-scoping.md 3.3 records
the decision not to have one): it allocates nothing and rewrites no metadata, it
overwrites N bytes with N bytes in fragments mkfs_ufs already assigned, and it
REFUSES a hole rather than filling one. The attested tree digest is unaffected --
altroot_attest.py hashes size, never content.
"""

import argparse
import hashlib
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

# --------------------------------------------------------------------------- #
# The two replacement code blocks.  Source: tools/blizzard-f2m1/{fsck,mkfs}.s,
# assembled with m68k-linux-gnu-as -m68020 and linked at the block's own address
# (the mkfs block contains PC-relative operands, so it is position-DEPENDENT).
# Only 32-bit MULU.L/DIVU.L/DIVUL.L are used: the 68060 leaves the 64-bit forms to
# the 060SP, and this AMIX kernel's u_trap table stops at vector 55, so their
# vector-61 trap becomes a bare SIGKILL.  Measured, not assumed.
# --------------------------------------------------------------------------- #

# fsck_ufs @ 0x800018c2 (file 0x018c2), 50 bytes -- the FP window, 48 B of code
# plus a 2-byte pad.  32-bit MULU.L/DIVU.L/DIVUL.L ONLY: the 68060 does not
# implement the 64-bit forms and their vector-61 trap is an un-tabled SIGKILL on
# this AMIX kernel (measured on the bench, docs/blizzard-f2m1.md 5.1).
#   moveq   #125,%d0
#   mulu.l  -4(%a6),%d0            d0 = 125 * n_ffree
#   lsl.l   #4,%d0                 d0 = 2000 * n_ffree
#   divu.l  0x80012c4c,%d0         d0 = floor(2000*n / fs_dsize)
#   addq.l  #1,%d0
#   lsr.l   #1,%d0                 = round(1000*n/D) == tenths of a percent
#   divul.l #10,%d1:%d0            d0 = whole, d1 = tenth
#   move.l  %d1,-(%sp) / move.l %d0,-(%sp)
#   move.l  -12(%a6),-(%sp)        n_bfree
#   move.l  -4(%a6),-(%sp)         n_ffree
#   pea     0x8000b3e2             the relocated format string
#   nop
FSCK_CODE_NEW = bytes.fromhex(
    "707d"
    "4c2e0000fffc"
    "e988"
    "4c79000080012c4c"
    "5280"
    "e288"
    "4c7c00010000000a"
    "2f01" "2f00"
    "2f2efff4"
    "2f2efffc"
    "48798000b3e2"
    "4e71"
)

FSCK_CODE_OLD = bytes.fromhex(
    "7064"                      # moveq  #100,%d0
    "4c2e0800fffc"              # mulsl  %fp@(-4),%d0
    "f2004000"                  # fmovel %d0,%fp0            <-- the kill
    "f239408080012c4c"          # fmovel sblk+0x38,%fp1
    "f2000424"                  # fsgldivx %fp1,%fp0
    "f2277400"                  # fmoved %fp0,%sp@-
    "201f" "221f" "2f01" "2f00" # the no-op hi/lo re-push
    "2f2efff4"
    "2f2efffc"
    "48798000b3e4"
)

# mkfs_ufs @ 0x80002068 (file 0x02068), 130 bytes.  The FP window alone (78 B) is
# too small for the replacement (86 B); the 8 missing bytes are recovered from the
# four instructions immediately before it by re-encoding absolute operands as
# PC-relative -- same instruction, same semantics, shorter encoding.  Nothing
# branches or points into this range (verified over the whole mapped image).
MKFS_CODE_NEW = bytes.fromhex(
    "2f28fdd4" "2f28fdd0" "2f28fddc"    # the printf #1 args, unchanged
    "47fa4966"                          # lea    (0x4966,%pc),%a3   -> 0x800069dc
    "2a28fd50"
    "4c3a580549d8"                      # muls.l (0x49d8,%pc),%d5   -> 0x80006a58
    "2f05"
    "2f39800489dc"
    "487a3ca8"                          # pea    (0x3ca8,%pc)       -> 0x80005d34
    "45fae7fc"                          # lea    (0xe7fc,%pc),%a2   -> printf@plt
    "4e92"                              # jsr    (%a2)              printf #1
    "2f2b00b8"                          # fs_ipg
    "202b00bc"                          # fs_fpg
    "4c2b00000034"                      # mulu.l 52(%a3),%d0        * fs_fsize
    "4c7c000000001388"                  # divu.l #5000,%d0
    "5280" "e288"                       # = round(bytes/10000) == hundredths of Mb
    "4c7c000100000064"                  # divul.l #100,%d1:%d0
    "2f01" "2f00"
    "2f2b00b4"                          # fs_cpg
    "2f2b002c"                          # fs_ncg
    "202b0024"                          # fs_size
    "4c2b00000034"                      # mulu.l 52(%a3),%d0        * fs_fsize
    "4c7c00000000c350"                  # divu.l #50000,%d0
    "5280" "e288"                       # = round(bytes/100000) == tenths of Mb
    "4c7c00010000000a"                  # divul.l #10,%d1:%d0
    "2f01" "2f00"
    "487a3c87"                          # pea    (0x3c87,%pc)       -> 0x80005d6d
    "4e92"                              # jsr    (%a2)              printf #2
)

MKFS_CODE_OLD = bytes.fromhex(
    "2f28fdd4" "2f28fdd0" "2f28fddc"
    "47f9800069dc"
    "2a28fd50"
    "4c39580580006a58"
    "2f05"
    "2f39800489dc"
    "487980005d34"
    "45f98000088c"
    "4e92"
    "2f2b00b8"
    "f22b408000bc"                      # fmovel %a3@(188),%fp1     <-- the kill
    "f22b40000034"
    "f20000a7"
    "f23c54a33eb0c6f7a0b5ed8d"
    "f2277480"
    "2f2b00b4"
    "2f2b002c"
    "f22b40800024"
    "f20000a7"
    "f23c54a33eb0c6f7a0b5ed8d"
    "f2277480"
    "487980005d6d"
    "4e92"
)

FSCK_FMT_NEW = b"(%d frags, %d blocks, %d.%d%% fragmentation)\n\0"
MKFS_FMT_NEW = b"\t%d.%dMb in %d cyl groups (%d c/g, %d.%02dMb/g, %d i/g)\n\0"


def _fsck_strzone(old):
    """0x093e2, 47 B: LC%33 ("\\n\\0") + the 45-byte format.  LC%33 is repointed to
    the identical "\\n\\0" at 0x8000b3c4, which frees the byte the new format needs."""
    if old != b"\n\0(%d frags, %d blocks, %.1f%% fragmentation)\n\0":
        raise ValueError("fsck string zone is not the stock one")
    new = FSCK_FMT_NEW + b"\0"
    assert len(new) == len(old) == 47
    return new


def _mkfs_strzone(old):
    """0x03d6d, 101 B: geometry format (53) + "super-block backups ..." (39) +
    "\\n\\0" (2) + " %d,\\0" (5) + "\\n\\0" (2).  Both "\\n\\0" are repointed to the one
    at 0x80005d32, and the two survivors slide down by 4 -- copied out of the old
    bytes rather than retyped, so they stay byte-faithful."""
    fmt, sbb, nl1, pct, nl2 = old[:53], old[53:92], old[92:94], old[94:99], old[99:101]
    if not fmt.startswith(b"\t%.1fMb in ") or not sbb.startswith(b"super-block backups"):
        raise ValueError("mkfs string zone is not the stock one")
    if nl1 != b"\n\0" or nl2 != b"\n\0" or pct != b" %d,\0":
        raise ValueError("mkfs string zone layout is not the stock one")
    new = MKFS_FMT_NEW + sbb + pct
    assert len(new) == len(old) == 101
    return new


def _ptr(old_addr, new_addr):
    """A `pea <abs.l>` whose operand is retargeted; the opcode is asserted too."""
    return (bytes.fromhex("4879") + old_addr.to_bytes(4, "big"),
            bytes.fromhex("4879") + new_addr.to_bytes(4, "big"))


# Each edit: (name, file offset, old bytes, new bytes-or-callable(old)).
FSCK_EDITS = [
    ("F1 pea LC%33 -> the identical \\n at 0x8000b3c4", 0x018B4, *_ptr(0x8000B3E2, 0x8000B3C4)),
    ("F2 format string, relocated 2 B down and grown by 1", 0x093E2, None, _fsck_strzone),
    ("F3 checkfilesys: 4 FP instructions -> integer", 0x018C2, FSCK_CODE_OLD, FSCK_CODE_NEW),
]

MKFS_EDITS = [
    ("M1 banner block: 9 FP instructions -> integer", 0x02068, MKFS_CODE_OLD, MKFS_CODE_NEW),
    ("M2 string zone, recompacted", 0x03D6D, None, _mkfs_strzone),
    ("M3 pea 'super-block backups' +4", 0x020EE, *_ptr(0x80005DA2, 0x80005DA6)),
    ("M4 pea \\n -> the one at 0x80005d32", 0x0211C, *_ptr(0x80005DC9, 0x80005D32)),
    ("M5 pea ' %d,' +2", 0x02158, *_ptr(0x80005DCB, 0x80005DCD)),
    ("M6 pea \\n -> the one at 0x80005d32", 0x02172, *_ptr(0x80005DD0, 0x80005D32)),
]

# Signature: a byte range that is present in the stock binary and unique to it, used
# to tell the two recipes apart before anything is asserted or written.
RECIPES = {
    "mkfs_ufs": dict(edits=MKFS_EDITS, sig_off=0x02068, sig_old=MKFS_CODE_OLD[:16],
                     sig_new=MKFS_CODE_NEW[:16], zone=(0x03D6D, 101)),
    "fsck_ufs": dict(edits=FSCK_EDITS, sig_off=0x018C2, sig_old=FSCK_CODE_OLD[:16],
                     sig_new=FSCK_CODE_NEW[:16], zone=(0x093E2, 47)),
}


class Refused(Exception):
    pass


def identify(buf):
    for name, r in RECIPES.items():
        if len(buf) < r["zone"][0] + r["zone"][1]:
            continue
        seg = bytes(buf[r["sig_off"]:r["sig_off"] + 16])
        if seg == r["sig_old"]:
            return name, "stock"
        if seg == r["sig_new"]:
            return name, "patched"
    raise Refused("not a stock or patched Amix 2.1 mkfs_ufs/fsck_ufs "
                  "(no known signature at 0x02068 or 0x018c2)")


def resolve(recipe, buf):
    """Turn the recipe into concrete (name, off, old, new) triples for this buffer.

    The string-zone edits derive their bytes from whatever is in the file, so they
    are resolved against the ORIGINAL zone: if the zone is already the patched one,
    the derivation is skipped and the edit reports as already applied."""
    r = RECIPES[recipe]
    out = []
    for name, off, old, new in r["edits"]:
        if callable(new):
            n = r["zone"][1]
            cur = bytes(buf[off:off + n])
            try:
                new_bytes = new(cur)
                old_bytes = cur
            except ValueError:
                # Not the stock zone -- the only other thing it may legally be is the
                # already-patched zone, which we reconstruct from this file's own
                # surviving strings so the comparison stays byte-exact.
                new_bytes = old_bytes = None
            out.append((name, off, old_bytes, new_bytes))
        else:
            out.append((name, off, old, new))
    return out


def apply(buf, recipe, write=True):
    """Returns a list of (name, state) with state in stock|patched.  Raises Refused
    on any site that is neither."""
    report = []
    for name, off, old, new in resolve(recipe, buf):
        cur = bytes(buf[off:off + (len(old) if old else 0)]) if old else None
        if old is not None and cur == old:
            if write:
                buf[off:off + len(new)] = new
            report.append((name, "patched" if write else "stock"))
            continue
        # Already patched?  Compare against the new bytes for fixed edits; for a
        # derived zone, re-derive the expected patched bytes from the stock recipe
        # is impossible, so match the invariant tail instead.
        if old is None:
            n = RECIPES[recipe]["zone"][1]
            cur = bytes(buf[off:off + n])
            if _looks_patched_zone(recipe, cur):
                report.append((name, "already patched"))
                continue
            raise Refused("site '%s' at 0x%05x is neither stock nor patched" % (name, off))
        cur = bytes(buf[off:off + len(new)])
        if cur == new:
            report.append((name, "already patched"))
            continue
        raise Refused("site '%s' at 0x%05x is neither stock nor patched "
                      "(found %s)" % (name, off, cur.hex()))
    return report


def _looks_patched_zone(recipe, cur):
    if recipe == "fsck_ufs":
        return cur.startswith(FSCK_FMT_NEW)
    return cur.startswith(MKFS_FMT_NEW)


def sha(b):
    return hashlib.sha256(bytes(b)).hexdigest()


def do_file(path, check, out=None):
    buf = bytearray(open(path, "rb").read())
    recipe, state = identify(buf)
    before = sha(buf)
    print("%s: %s (%s), sha256 %s" % (path, recipe, state, before))
    rep = apply(buf, recipe, write=not check)
    for name, st in rep:
        print("    %-52s %s" % (name, st))
    if check:
        return 0
    dest = out or path
    with open(dest, "wb") as f:
        f.write(buf)
    print("    wrote %s, sha256 %s" % (dest, sha(buf)))
    return 0


# --------------------------------------------------------------------------- #
# s5 in-place member patching.  The patch preserves length, so the member's inode,
# size and block list are all untouched -- only the data blocks' bytes change.
# --------------------------------------------------------------------------- #

def s5_locate(img, path):
    import s5
    ino = s5.ROOT_INO
    for comp in [c for c in path.split("/") if c]:
        ents = dict((n, i) for i, n in s5.read_dir(img, ino))
        if comp not in ents:
            raise Refused("s5: no such path component %r in %s" % (comp, path))
        ino = ents[comp]
    mode, nlink, uid, gid, size, addrs = s5.read_inode(img, ino)
    B = s5.BSIZE
    blocks = list(addrs[:10])
    if addrs[10]:
        import struct
        ib = img[addrs[10] * B:(addrs[10] + 1) * B]
        blocks += [struct.unpack(">I", ib[i:i + 4])[0] for i in range(0, B, 4)]
    if addrs[11] or addrs[12]:
        raise Refused("s5: %s uses double/triple indirect blocks (unsupported)" % path)
    need = (size + B - 1) // B
    return ino, size, blocks[:need]


def do_s5(image, paths, check):
    import s5
    img = bytearray(open(image, "rb").read())
    B = s5.BSIZE
    for path in paths:
        ino, size, blocks = s5_locate(img, path)
        data = bytearray()
        for b in blocks:
            data += img[b * B:(b + 1) * B]
        data = data[:size]
        recipe, state = identify(data)
        print("%s!%s: %s (%s), %d B, inode %d, sha256 %s"
              % (image, path, recipe, state, size, ino, sha(data)))
        rep = apply(data, recipe, write=not check)
        for name, st in rep:
            print("    %-52s %s" % (name, st))
        if check:
            continue
        assert len(data) == size, "patch changed the member length"
        for i, b in enumerate(blocks):
            chunk = bytes(data[i * B:(i + 1) * B])
            img[b * B:b * B + len(chunk)] = chunk
        print("    member sha256 %s" % sha(data))
    if not check:
        with open(image, "wb") as f:
            f.write(img)
        print("wrote %s, sha256 %s" % (image, sha(img)))
    return 0


# --------------------------------------------------------------------------- #
# ufs in-place member patching -- the INSTALLED tree's copies.
#
# Same law as --s5, and it is the law that makes this possible at all: the patch
# preserves every length, so the member's inode, its size and its block list are
# untouched and only the bytes already inside its allocated fragments change.
#
# ★ THIS IS NOT A HOST-SIDE UFS WRITER, and the distinction is load-bearing:
# docs/ufs-target-scoping.md 3.3 records the deliberate decision not to have one.
# A writer allocates, frees, grows files and rewrites metadata. This allocates
# nothing, frees nothing, moves nothing and writes no metadata -- it overwrites
# N bytes with N bytes in fragments the 1991 mkfs_ufs already assigned. A hole is
# REFUSED rather than filled, because filling one WOULD be an allocation.
#
# Why it has to exist: the installed tree's /etc/fs/ufs/{mkfs,fsck} come from the
# CD's core package, so they land unpatched on every target, and the BLIZZARD work
# wired MINIROOT_FP_PATCH into the miniroot ONLY. On an FPU-less 68060 that means
# a shipped image cannot fsck its own root -- exactly the failure the patch exists
# to prevent. There is no host-side path to those two files other than this one:
# they live inside the target's ufs root, and the alternative (a live box + FTP)
# needs the very box the image is being built for.
#
# ★ THE ATTESTED DIGEST DOES NOT MOVE, by construction. altroot_attest.py's record
# is  path \0 ftype \0 mode \0 uid \0 gid \0 size \0 linktarget \0 rdev  -- there
# is no checksum and no content hash in it (FIELDS in that tool), and `size` is
# what this patch preserves. So a patched image still attests at its set's
# reference digest. What DOES notice is pkgchk(1M), which compares the contents
# DB's own cksum: those two paths will report a checksum mismatch, which is the
# same declared exception miniroot.proto already carries for the miniroot pair.
# --------------------------------------------------------------------------- #

def ufs_locate(img, sb, base, path):
    """(ino, size, extents) for a regular file inside a ufs filesystem.

    `extents` is [(byte_offset, length), ...] in logical order -- exactly the
    windows ufs.read_data() reads. Gathering them therefore reproduces the file
    byte for byte, and scattering the same lengths back writes it.
    """
    import ufs
    ino = ufs.ROOT_INO
    walked = ""
    for comp in [c for c in path.split("/") if c]:
        d = ufs.read_dinode(img, ino, base, sb)
        if d.type != ufs.IFDIR:
            raise Refused("ufs: %s is not a directory, so %s cannot be resolved"
                          % (walked or "/", path))
        ents = dict((n, i) for i, n in ufs.read_dir(img, ino, base, sb))
        if comp not in ents:
            raise Refused("ufs: no such path component %r in %s" % (comp, path))
        ino = ents[comp]
        walked += "/" + comp
    d = ufs.read_dinode(img, ino, base, sb)
    if d.type != ufs.IFREG:
        raise Refused("ufs: %s is not a regular file (mode 0%o)" % (path, d.mode))
    extents, got, lbn = [], 0, 0
    while got < d.size:
        frag = ufs._block_addr(img, sb, d, lbn, base)
        need = min(sb.bsize, d.size - got)
        if frag == 0:
            raise Refused("ufs: %s has a HOLE at logical block %d -- writing it "
                          "would be an allocation, and this is not a writer" % (path, lbn))
        off = sb.frag_offset(frag, base)
        if off + need > len(img):
            raise Refused("ufs: %s logical block %d runs past the image end" % (path, lbn))
        extents.append((off, need))
        got += need
        lbn += 1
    return ino, d.size, extents


def _ufs_base(image, slice_no):
    """Byte offset of the ufs filesystem: 0 for a bare slice image, else the
    RDB slice's own offset. Reuses this repo's rdb.py rather than re-deriving it."""
    if slice_no is None:
        return 0
    from rdb import read_rdb
    with open(image, "rb") as fh:
        img = fh.read(1 << 20)
    _, slices = read_rdb(img)
    if slice_no < 1 or slice_no > len(slices):
        raise Refused("ufs: no slice %d (the RDB has %d)" % (slice_no, len(slices)))
    return slices[slice_no - 1].byte_offset


def do_ufs(image, slice_no, paths, check):
    import mmap
    import ufs
    base = _ufs_base(image, slice_no)
    access = mmap.ACCESS_READ if check else mmap.ACCESS_WRITE
    with open(image, "rb" if check else "r+b") as fh:
        with mmap.mmap(fh.fileno(), 0, access=access) as img:
            sb = ufs.parse_super(img, base)
            if sb.magic != ufs.UFS_MAGIC:
                raise Refused("ufs: no UFS superblock at offset %d of %s "
                              "(magic 0x%08x)" % (base, image, sb.magic))
            print("%s: ufs at +%d, bsize %d, fsize %d, %d cyl groups"
                  % (image, base, sb.bsize, sb.fsize, sb.ncg))
            for path in paths:
                ino, size, extents = ufs_locate(img, sb, base, path)
                data = bytearray()
                for off, need in extents:
                    data += img[off:off + need]
                recipe, state = identify(data)
                print("%s!%s: %s (%s), %d B, inode %d, sha256 %s"
                      % (image, path, recipe, state, size, ino, sha(data)))
                rep = apply(data, recipe, write=not check)
                for name, st in rep:
                    print("    %-52s %s" % (name, st))
                if check:
                    continue
                if len(data) != size:
                    raise Refused("ufs: the patch changed %s from %d to %d bytes -- "
                                  "refusing, this mode can only overwrite in place"
                                  % (path, size, len(data)))
                p = 0
                for off, need in extents:
                    img[off:off + need] = bytes(data[p:p + need])
                    p += need
                print("    member sha256 %s (inode, size and block list untouched)"
                      % sha(data))
            if not check:
                img.flush()
    return 0


# --------------------------------------------------------------------------- #
# self-test -- hermetic. Proves the ufs extent mapping and the write-back on a
# SYNTHETIC filesystem, and proves each refusal fires. No proprietary bytes: the
# fixture is ufs.py's own reader-test image, and the payload is bytes this test
# makes up. The FP recipes themselves are covered by tools/blizzard-f2m1/oracle.py
# and seq.S (host pre-gates) plus the two-rig metal gates in docs/blizzard-f2m1.md;
# what has never had a gate is THIS code -- the locator and the scatter-write.
# --------------------------------------------------------------------------- #

def _selftest():
    import mmap
    import tempfile
    import ufs

    fails = []

    def ok(cond, what):
        print("  %-64s %s" % (what, "ok" if cond else "FAIL"))
        if not cond:
            fails.append(what)

    def refuses(fn, what):
        try:
            fn()
        except (Refused, ufs.UfsError):
            ok(True, what)
            return
        except Exception as e:                       # noqa: BLE001 - report it
            ok(False, "%s (raised %r, wanted a refusal)" % (what, e))
            return
        ok(False, "%s (no refusal)" % what)

    raw, _expect = ufs._synth_fixture()
    with tempfile.NamedTemporaryFile(suffix=".ufs", delete=False) as tf:
        tf.write(raw)
        img_path = tf.name
    try:
        original = bytes(raw)
        with open(img_path, "r+b") as fh:
            with mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_WRITE) as img:
                sb = ufs.parse_super(img, 0)

                # 1. the locator agrees with the trusted reader, byte for byte
                ino, size, extents = ufs_locate(img, sb, 0, "/file.dat")
                gathered = b"".join(bytes(img[o:o + n]) for o, n in extents)
                truth = ufs.read_file(img, ino, 0, sb)
                ok(gathered == truth,
                   "gathering the located extents reproduces read_file() exactly")
                ok(sum(n for _, n in extents) == size,
                   "the extents cover exactly the inode's size (%d B)" % size)
                ok(len(extents) > ufs.NDADDR,
                   "the fixture file spans the single-indirect boundary (%d blocks)"
                   % len(extents))
                ok(extents[-1][1] < sb.bsize,
                   "the last extent is a partial fragment tail (%d B)" % extents[-1][1])

                # 2. a same-length scatter-write round-trips through the reader.
                #    Touch the FIRST byte of every extent -- that is one write per
                #    direct block, per indirect block and in the tail, so a
                #    mis-mapped extent cannot hide behind a correct neighbour.
                mutated = bytearray(truth)
                p = 0
                for _, n in extents:
                    mutated[p] ^= 0xA5
                    p += n
                p = 0
                for off, n in extents:
                    img[off:off + n] = bytes(mutated[p:p + n])
                    p += n
                ok(ufs.read_file(img, ino, 0, sb) == bytes(mutated),
                   "a same-length scatter-write reads back exactly as written")

                # 3. and it wrote NOWHERE else
                after = bytes(img[:])
                diffs = [i for i in range(len(original)) if original[i] != after[i]]
                ok(len(diffs) == len(extents),
                   "exactly %d bytes changed -- one per extent, no collateral writes"
                   % len(extents))
                ok(all(any(o <= i < o + n for o, n in extents) for i in diffs),
                   "every changed byte lies inside a located extent")

                # 4. restore, and prove the image is bit-identical again
                p = 0
                for off, n in extents:
                    img[off:off + n] = bytes(truth[p:p + n])
                    p += n
                ok(bytes(img[:]) == original,
                   "restoring the original bytes returns the image bit-identical")

                # 5. the refusals
                refuses(lambda: ufs_locate(img, sb, 0, "/nosuchfile"),
                        "REFUSES a path that does not exist")
                refuses(lambda: ufs_locate(img, sb, 0, "/lost+found"),
                        "REFUSES a directory (not a regular file)")
                refuses(lambda: ufs_locate(img, sb, 0, "/file.dat/x"),
                        "REFUSES descending through a non-directory")
                refuses(lambda: ufs_locate(img, sb, 0, "/adev"),
                        "REFUSES a device node")

                # 6. a hole must be refused, not filled: blank one direct pointer
                d = ufs.read_dinode(img, ino, 0, sb)
                hole_at = sb.inode_offset(ino, 0) + ufs.IC_DB + 4 * 3
                saved = bytes(img[hole_at:hole_at + 4])
                img[hole_at:hole_at + 4] = b"\0\0\0\0"
                refuses(lambda: ufs_locate(img, sb, 0, "/file.dat"),
                        "REFUSES a file with a HOLE rather than allocating")
                img[hole_at:hole_at + 4] = saved
                ok(bytes(img[:]) == original,
                   "the hole probe left the image bit-identical")
                ok(d.size == size, "the inode's size never moved")
    finally:
        os.unlink(img_path)

    print("")
    if fails:
        print("patch-ufs-fp selftest: %d FAILED" % len(fails))
        for f in fails:
            print("  - %s" % f)
        return 1
    print("patch-ufs-fp selftest: all checks passed")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="report only, write nothing")
    ap.add_argument("-o", "--output", help="write the patched file here instead of in place")
    ap.add_argument("--s5", metavar="IMAGE", help="patch members inside this s5 image")
    ap.add_argument("--ufs", metavar="IMAGE",
                    help="patch members inside this ufs image (the INSTALLED tree)")
    ap.add_argument("--slice", type=int, default=None, metavar="N",
                    help="with --ufs: the RDB slice holding the filesystem "
                         "(default: treat the image as a bare slice)")
    ap.add_argument("--self-test", action="store_true",
                    help="hermetic self-test of the ufs locator and write-back")
    ap.add_argument("paths", nargs="*",
                    help="files, or member paths when --s5 / --ufs is given")
    a = ap.parse_args()
    if a.self_test:
        return _selftest()
    if not a.paths:
        ap.error("no paths given")
    if a.s5 and a.ufs:
        ap.error("--s5 and --ufs are alternatives")
    if a.slice is not None and not a.ufs:
        ap.error("--slice only means something with --ufs")
    try:
        if a.s5:
            return do_s5(a.s5, a.paths, a.check)
        if a.ufs:
            return do_ufs(a.ufs, a.slice, a.paths, a.check)
        if a.output and len(a.paths) != 1:
            ap.error("-o takes exactly one input file")
        rc = 0
        for p in a.paths:
            rc |= do_file(p, a.check, a.output)
        return rc
    except Refused as e:
        print("REFUSED: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
