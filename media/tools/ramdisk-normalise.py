#!/usr/bin/env python3
"""ramdisk-normalise.py IMAGE --epoch SECONDS --out FILE -- a RAM disk's filesystem with nothing of its build left in it.

A RAM disk is made on a running box, on a slice nobody clears, so two builds of the same tree differ in time stamps
and in what free space last held. This writes every inode, superblock and group time as the epoch, zeroes free space and
free inodes, and clears the kernel address fs_csp the last unmount left in a ufs superblock. Files, modes, owners and
block allocation are not touched: the whole tree is read before and after and must match.

ufs and s5, found by their magic. A filesystem that is not marked clean is refused: fsck first.
Exit 0 written, 1 the tree changed (nothing written), 2 it could not look. --selftest for the self-test.
"""
import argparse, os, struct, sys, tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, os.path.join(HERE, "lib"))
# ufs.py is amix's tools/lib (one copy, shared with the release check)
sys.path.insert(1, os.path.join(HERE, "..", "..", "tools", "lib"))
import s5, ufs

FS_OKAY = 0x7c269d38
UFS_SB = 8192
UFS_TIME, UFS_STATE, UFS_CSP = 32, 132, 728
CG_TIME, CG_NDBLK, CG_MAGIC_OFF, CG_MAP = 8, 20, 980, 984
CG_MAGIC = 0x090255
UI_ATIME, UI_MTIME, UI_CTIME = 16, 24, 32


class Refused(Exception):
    pass


def _put_times_ufs(b, o, epoch):
    for f in (UI_ATIME, UI_MTIME, UI_CTIME):
        struct.pack_into(">II", b, o + f, epoch, 0)


def normalise_ufs(b, epoch):
    sb = ufs.parse_super(bytes(b[:UFS_SB + 8192]))
    t, st = struct.unpack_from(">II", b, UFS_SB + UFS_TIME)[0], struct.unpack_from(">I", b, UFS_SB + UFS_STATE)[0]
    if (t + st) & 0xffffffff != FS_OKAY:
        raise Refused("ufs: not marked clean (time %d, state 0x%x): fsck it first" % (t, st))
    sblkno, cblkno = struct.unpack_from(">ii", b, UFS_SB + 8)
    for n in range(sb.n_inodes):
        o = sb.inode_offset(n)
        if struct.unpack_from(">H", b, o)[0] == 0:
            b[o:o + ufs.DINODE_SIZE] = bytes(ufs.DINODE_SIZE)
        else:
            _put_times_ufs(b, o, epoch)
    state = (FS_OKAY - epoch) & 0xffffffff
    struct.pack_into(">I", b, UFS_SB + UFS_TIME, epoch)
    struct.pack_into(">I", b, UFS_SB + UFS_STATE, state)
    struct.pack_into(">I", b, UFS_SB + UFS_CSP, 0)
    for g in range(sb.ncg):
        start = sb.cgstart(g) * sb.fsize
        cg = start + cblkno * sb.fsize
        if struct.unpack_from(">I", b, cg + CG_MAGIC_OFF)[0] != CG_MAGIC:
            raise Refused("ufs: group %d has no cg magic at %d" % (g, cg + CG_MAGIC_OFF))
        struct.pack_into(">I", b, cg + CG_TIME, epoch)
        # every group has its superblock copy, the first group's too
        sc = start + sblkno * sb.fsize
        struct.pack_into(">I", b, sc + UFS_TIME, epoch)
        struct.pack_into(">I", b, sc + UFS_STATE, state)
        ndblk = struct.unpack_from(">I", b, cg + CG_NDBLK)[0]
        base = sb.fpg * g * sb.fsize
        for i in range(ndblk):
            if b[cg + CG_MAP + i // 8] & (1 << (i % 8)):
                f = base + i * sb.fsize
                b[f:f + sb.fsize] = bytes(sb.fsize)
    return "ufs"


def normalise_s5(b, epoch):
    sb = s5.parse_super(bytes(b[:4096]))
    o = s5.SUPER_OFF
    t, st = struct.unpack_from(">II", b, o + s5.SB_TIME)[0], struct.unpack_from(">I", b, o + s5.SB_STATE)[0]
    if (t + st) & 0xffffffff != FS_OKAY:
        raise Refused("s5: not marked clean (time %d, state 0x%x): fsck it first" % (t, st))
    struct.pack_into(">I", b, o + s5.SB_TIME, epoch)
    struct.pack_into(">I", b, o + s5.SB_STATE, (FS_OKAY - epoch) & 0xffffffff)
    for n in range(1, sb.n_inodes + 1):
        i = s5.inode_offset(None, n)
        if struct.unpack_from(">H", b, i)[0] == 0:
            b[i:i + s5.INODE_SIZE] = bytes(s5.INODE_SIZE)
        else:
            struct.pack_into(">III", b, i + s5.DI_ATIME, epoch, epoch, epoch)
    img = bytes(b)
    keep = {}      # a chain block keeps its counter and its entries, the rest of it is free space
    for src, nfree, _ in s5._freelist_levels(img, sb):
        if src is not None:
            keep[src] = 4 + nfree * 4
    for blk in s5.walk_freelist(img, sb):
        if blk == 0:
            continue
        o = blk * s5.BSIZE
        k = keep.get(blk, 0)
        b[o + k:o + s5.BSIZE] = bytes(s5.BSIZE - k)
    for blk, k in keep.items():
        o = blk * s5.BSIZE
        b[o + k:o + s5.BSIZE] = bytes(s5.BSIZE - k)
    return "s5"


def tree_of(img):
    """Everything a file is, apart from its times: for the before-and-after check."""
    if struct.unpack_from(">I", img, UFS_SB + ufs.FS_MAGIC)[0] == ufs.UFS_MAGIC:
        sb = ufs.parse_super(img)
        out = {}
        man = ufs.tree_manifest(img, sb=sb)
        for p, d in ufs.walk(img, sb=sb):
            out[p] = (man[p], ufs.read_data(img, sb, d) if d.type == ufs.IFREG else b"")
        return out
    sb = s5.parse_super(img)
    out = {}
    for n in range(1, sb.n_inodes + 1):
        mode, nlink, uid, gid, size, addrs = s5.read_inode(img, n)
        if mode:
            data = b"".join(img[a * s5.BSIZE:a * s5.BSIZE + s5.BSIZE] for a in addrs[:10] if a)
            out[n] = (mode, nlink, uid, gid, size, tuple(addrs), data[:size])
    return out


def normalise(data, epoch):
    """The normalised bytes, or raises Refused."""
    if epoch <= 0:
        raise Refused("no epoch")
    b = bytearray(data)
    before = tree_of(data)
    if not before:
        raise Refused("no file in the image")
    if struct.unpack_from(">I", data, UFS_SB + ufs.FS_MAGIC)[0] == ufs.UFS_MAGIC:
        normalise_ufs(b, epoch)
    else:
        normalise_s5(b, epoch)
    out = bytes(b)
    if tree_of(out) != before:
        raise ValueError("the tree changed")
    return out


def selftest():
    bad = 0

    def ok(c, what):
        nonlocal bad
        if not c:
            print("  FAIL", what)
            bad += 1

    def refused(data, what, epoch=700000000):
        try:
            normalise(data, epoch)
        except (Refused, s5.S5Error, ufs.UfsError):
            return
        ok(False, what + ": not refused")

    # s5: two builds, other times, other leftovers in free blocks
    def s5_build(t, junk):
        b = bytearray(s5.mkfs_s5(880, fs_time=t))
        sb = s5.parse_super(bytes(b))
        chain = {src for src, _, _ in s5._freelist_levels(bytes(b), sb) if src is not None}
        for blk in s5.walk_freelist(bytes(b), sb)[:8]:
            if blk not in chain and blk:
                b[blk * s5.BSIZE:(blk + 1) * s5.BSIZE] = junk * s5.BSIZE
        return bytes(b)

    a, c = s5_build(700000000, b"A"), s5_build(700123456, b"B")
    ok(a != c, "s5: the two builds differ")
    na, nc = normalise(a, 690000000), normalise(c, 690000000)
    ok(na == nc, "s5: two builds normalise to the same bytes")
    ok(b"AAAA" not in na and b"BBBB" not in nc, "s5: free blocks zeroed")
    ok(normalise(na, 690000000) == na, "s5: normalising twice changes nothing")
    sb = s5.parse_super(na)
    ok((sb.time, (sb.time + sb.state) & 0xffffffff) == (690000000, FS_OKAY), "s5: time and clean state")
    ok(s5.walk_freelist(na, sb) == s5.walk_freelist(a, s5.parse_super(a)), "s5: the free list intact")
    d = bytearray(a)
    struct.pack_into(">I", d, s5.SUPER_OFF + s5.SB_STATE, 0)
    refused(bytes(d), "s5: not clean")

    # ufs: the reader's fixture, given a group and a clean mark, with free frags
    img, _ = ufs._synth_fixture()
    u = bytearray(img)
    sb = ufs.parse_super(bytes(u))
    sblkno, cblkno = struct.unpack_from(">ii", u, UFS_SB + 8)
    cg = cblkno * sb.fsize
    frags = len(u) // sb.fsize
    u += bytes(sb.fsize * 16)
    used = frags
    struct.pack_into(">I", u, cg + CG_MAGIC_OFF, CG_MAGIC)
    struct.pack_into(">I", u, cg + CG_NDBLK, used + 16)
    for i in range(used, used + 16):
        u[cg + CG_MAP + i // 8] |= 1 << (i % 8)

    def u_build(t, junk):
        v = bytearray(u)
        struct.pack_into(">I", v, UFS_SB + UFS_TIME, t)
        struct.pack_into(">I", v, UFS_SB + UFS_STATE, (FS_OKAY - t) & 0xffffffff)
        struct.pack_into(">I", v, UFS_SB + UFS_CSP, t)
        struct.pack_into(">I", v, cg + CG_TIME, t)
        v[used * sb.fsize:(used + 16) * sb.fsize] = junk * (16 * sb.fsize)
        for n in range(sb.n_inodes):
            o = sb.inode_offset(n)
            if struct.unpack_from(">H", v, o)[0]:
                struct.pack_into(">III", v, o + UI_ATIME, t, 0, t)
        return bytes(v)

    a, c = u_build(700000000, b"A"), u_build(700123456, b"B")
    ok(a != c, "ufs: the two builds differ")
    na, nc = normalise(a, 690000000), normalise(c, 690000000)
    ok(na == nc, "ufs: two builds normalise to the same bytes")
    ok(b"AAAA" not in na[used * sb.fsize:], "ufs: free frags zeroed")
    ok(normalise(na, 690000000) == na, "ufs: normalising twice changes nothing")
    ok(struct.unpack_from(">I", na, UFS_SB + UFS_CSP)[0] == 0, "ufs: fs_csp cleared")
    ok(tree_of(na) == tree_of(a), "ufs: the tree the same")
    d = bytearray(a)
    struct.pack_into(">I", d, UFS_SB + UFS_STATE, 0)
    refused(bytes(d), "ufs: not clean")
    d = bytearray(a)
    struct.pack_into(">I", d, cg + CG_MAGIC_OFF, 0)
    refused(bytes(d), "ufs: no group magic")
    refused(a, "no epoch", 0)
    refused(bytes(65536), "neither filesystem")
    print("ramdisk-normalise --selftest: %s" % ("FAIL" if bad else "PASS"))
    return 1 if bad else 0


def main():
    if sys.argv[1:] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("image")
    ap.add_argument("--epoch", type=int, required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    try:
        with open(a.image, "rb") as f:
            data = f.read()
        out = normalise(data, a.epoch)
    except ValueError as e:
        print("ramdisk-normalise: STOP: %s" % e, file=sys.stderr)
        return 1
    except (Refused, OSError, s5.S5Error, ufs.UfsError, struct.error) as e:
        print("ramdisk-normalise: STOP, could not look: %s" % e, file=sys.stderr)
        return 2
    t = a.out + ".new"
    with open(t, "wb") as f:
        f.write(out)
    os.replace(t, a.out)
    print("ramdisk-normalise: %s: %d bytes changed, written %s" % (os.path.basename(a.image), sum(x != y for x, y in zip(data, out)), a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
