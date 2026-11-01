#!/usr/bin/env python3
"""ramdisk-image-check.py -- a RAM-disk image against its generation (S5-33; b1f564f4).

  tools/ramdisk-image-check.py [--zen0] SPEC IMAGE ufs|s5 [SPEC IMAGE ufs|s5 ...]

SPEC is the generation spec kbootset media wrote (gen-k46.spec / gen-k30.spec, a floppy
pair's V1.spec), IMAGE the line's RAM-disk image (tools/build-ramdisk-miniroot.sh): ufs on
k46, s5 on k30. Every boot- or demand-class record (`module NAME boot|demand SIZE path=P
sha256=S ...`) must find P in the image holding exactly the bytes S names: the core loads a
boot-class one from the RAM-disk root after `modadmin -B` (C3-5 section 5), a demand-class one
at its first use (cdfs, fs=cdfs, at the first mount of the disc). Since catalog b1f564f4 the kernels carry no
built-in ufs or s5: on k30 the kernel package's ufs is such a record (s5 is the promoted
root), and without it the miniroot cannot mount the ufs target. A ufs image's block size
must be at least 4096 (the k46 ufs module refuses a smaller one at mount, S5-13).
--zen0 (the netinstall images): /dev/zen0 must also be c 51,0 (the z3660eth package's node,
C3-5 section 1.2), and the image's installer must carry /install/dmamask, the DosEnvec Mask
table install.sh stamps the target with (tools/dmamask.py medium; without it the target keeps
/etc/rdb's 0xFFFFFFFC on any controller). Exit 0 when every image passes, 1 otherwise; one line per finding.
"""
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import dmamask  # noqa: E402
import s5   # noqa: E402
import ufs  # noqa: E402


def s5_file(img, ino):
    """Direct and single-indirect 1 KiB blocks: enough for a boot module (< 266 KiB)."""
    _, _, _, _, size, a = s5.read_inode(img, ino)
    if size > (10 + 256) * 1024:
        raise SystemExit("ramdisk-image-check: inode %d is %d bytes, past single indirect" % (ino, size))
    blks = list(a[:10])
    if size > 10 * 1024:
        ib = a[10]
        blks += [struct.unpack(">I", img[ib * 1024 + 4 * i:ib * 1024 + 4 * i + 4])[0] for i in range(256)]
    out = bytearray()
    for b in blks:
        if len(out) >= size:
            break
        out += img[b * 1024:(b + 1) * 1024] if b else b"\0" * 1024
    return bytes(out[:size])


def s5_lookup(img, path):
    ino = 2
    for c in path.strip("/").split("/"):
        ino = dict((n, i) for i, n in s5.read_dir(img, ino)).get(c)
        if not ino:
            return None
    return ino


def reader(img, fs):
    """(get(path) -> bytes or None, dev(path) -> (major, minor) of a char node or None)"""
    if fs == "ufs":
        sb = ufs.parse_super(img)
        tree = dict(ufs.walk(img, 0, sb))

        def get(p):
            d = tree.get(p)
            return ufs.read_data(img, sb, d) if d is not None and d.type == ufs.IFREG else None

        def dev(p):
            d = tree.get(p)
            return ufs.decode_dev(d) if d is not None and d.type == ufs.IFCHR else None
        return get, dev

    def get(p):
        i = s5_lookup(img, p)
        return s5_file(img, i) if i else None

    def dev(p):
        i = s5_lookup(img, p)
        if not i:
            return None
        n = s5.read_inode(img, i)
        return s5.decode_dev(n[5]) if n[0] & 0o170000 == 0o020000 else None
    return get, dev


def main(args):
    zen0 = bool(args) and args[0] == "--zen0"
    if zen0:
        args = args[1:]
    if not args or len(args) % 3:
        print(__doc__.strip().splitlines()[2].strip())
        return 2
    bad = 0
    for spec, image, fs in zip(args[0::3], args[1::3], args[2::3]):
        if fs not in ("ufs", "s5"):
            print("ramdisk-image-check: %s: filesystem %r is not ufs or s5" % (image, fs))
            return 2
        img = open(image, "rb").read()
        if fs == "ufs":
            bs = ufs.parse_super(img).bsize
            if bs < 4096:
                print("ramdisk-image-check: %s: ufs block size %d, under 4096 (k46 refuses it)" % (image, bs))
                bad = 1
            else:
                print("ramdisk-image-check: %s: ufs block size %d" % (os.path.basename(image), bs))
        get, dev = reader(img, fs)
        recs = [l.split() for l in open(spec) if l.startswith("module ") and len(l.split()) > 2
                and l.split()[2] in ("boot", "demand")]
        if not recs:
            print("ramdisk-image-check: %s records no boot- or demand-class module" % spec)
            bad = 1
        for r in recs:
            kv = dict(x.split("=", 1) for x in r[4:] if "=" in x)
            data = get(kv.get("path", ""))
            if data is None or hashlib.sha256(data).hexdigest() != kv.get("sha256"):
                print("ramdisk-image-check: %s: %s is not the %s its generation records (sha256 %s)"
                      % (image, kv.get("path"), r[1], kv.get("sha256", "?")[:16]))
                bad = 1
            else:
                print("ramdisk-image-check: %s: %s module %s at %s, sha256 %s"
                      % (os.path.basename(image), r[2], r[1], kv["path"], kv["sha256"][:16]))
        if not zen0:
            continue
        z = dev("/dev/zen0")
        if z != (51, 0):
            print("ramdisk-image-check: %s: /dev/zen0 is %s, not c 51,0" % (image, z))
            bad = 1
        else:
            print("ramdisk-image-check: %s: /dev/zen0 c 51,0" % os.path.basename(image))
        t = get("/install/dmamask")
        if t != dmamask.medium_rows().encode():
            print("ramdisk-image-check: %s: /install/dmamask is %s, not tools/dmamask.py medium's table"
                  % (image, "absent" if t is None else "different"))
            bad = 1
        else:
            print("ramdisk-image-check: %s: /install/dmamask = the medium table (%d rows)"
                  % (os.path.basename(image), t.count(b"\n")))
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
