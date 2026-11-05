#!/usr/bin/env python3
"""known-bad-scan.py -- refuse a 1.1 artefact that carries a known-bad module (tools/known-bad-modules.txt).

    tools/known-bad-scan.py ARTEFACT...          exit 0 clean, 1 a hit, 2 usage or no list
    tools/known-bad-scan.py --self-test

ARTEFACT is a directory (every file in it is hashed), an ISO (every file in it, read with xorriso, is
hashed), or any other file: an image, an hdf, an adf. A file whose own sha256 is listed is a hit; an
image is also searched for the listed module's bytes: its 512-byte pieces, each of which a ufs or FFS
disk keeps whole inside one block, wherever the blocks lie; nine in ten of them found is a hit, so a
module inside a disk or an uncompressed package is found without mounting or unpacking it, and a later
build of the same driver (which shares a few pieces) is not. The bytes are read from
build/pins/known-bad/<sha256>.bin; a listed module without its bytes is checked by hash only, and the
report says so. A deflated store (the floppy pair) is not searched by bytes: its generation is the CD
boot tree's, which the media build checks file by file.
"""
import hashlib
import mmap
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
LIST = os.path.join(HERE, "known-bad-modules.txt")
BYTES = os.path.join(REPO, "build", "pins", "known-bad")


def load(listfile=LIST, bytesdir=BYTES):
    bad = {}
    for line in open(listfile, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        sha, size, why = line.split(None, 2)
        b = None
        p = os.path.join(bytesdir, sha + ".bin")
        if os.path.isfile(p):
            b = open(p, "rb").read()
            if hashlib.sha256(b).hexdigest() != sha:
                sys.exit("known-bad-scan: %s does not hash to its name" % p)
        bad[sha] = (int(size), why, b)
    return bad


def sha_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for blk in iter(lambda: fh.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def scan_tree(root, bad, label):
    hits = []
    sizes = {v[0] for v in bad.values()}
    for r, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(r, f)
            if os.path.isfile(p) and not os.path.islink(p) and os.path.getsize(p) in sizes:
                h = sha_file(p)
                if h in bad:
                    hits.append("%s: %s is %s" % (label, os.path.relpath(p, root), bad[h][1].split(":")[0]))
    return hits


def pieces_of(b):
    """the module's 512-byte pieces at 512-byte offsets: a ufs fragment (1 KiB) and an FFS block (512 B) both
    start on such an offset, so each piece lies whole inside one block of any disk holding the file; a piece of
    one repeated byte says nothing and is left out"""
    return [b[o:o + 512] for o in range(0, len(b) - 511, 512) if b[o:o + 512].count(b[o:o + 1]) != 512]


def scan_bytes(p, bad, need=0.9):
    """a hit: at least `need` of the module's pieces are in the file (a near relative, such as the next build of
    the same driver, shares a few pieces, not most)"""
    hits = []
    if os.path.getsize(p) == 0:
        return hits
    with open(p, "rb") as fh:
        m = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
        try:
            for sha, (_, why, b) in bad.items():
                if not b:
                    continue
                ps = pieces_of(b)
                n = miss = 0
                for x in ps:   # stop once a hit is out of reach: a clean disk costs a few passes, not one per piece
                    if m.find(x) >= 0:
                        n += 1
                    else:
                        miss += 1
                        if miss > len(ps) - need * len(ps):
                            break
                if ps and n >= need * len(ps):
                    hits.append("%s: carries %s (%d of its %d 512-byte pieces)" % (p, why.split(":")[0], n, len(ps)))
        finally:
            m.close()
    return hits


def cannot_look(bad, arts=()):
    """Why a CLEAN from here would prove nothing, or None: an empty list, a listed module without its bytes (only a
    whole-file hash could then match, a disk image would pass), an artefact that is missing or empty."""
    if not bad:
        return "the known-bad list is empty"
    nobytes = [s[:16] for s, v in bad.items() if not v[2]]
    if nobytes:
        return "no bytes for %s under build/pins: a module inside a disk image would not be found" % " ".join(nobytes)
    for a in arts:
        if os.path.isdir(a):
            if not any(fs for _, _, fs in os.walk(a)):
                return "no file in " + a
        elif not os.path.isfile(a) or not os.path.getsize(a):
            return "missing or empty: " + a
    return None


def scan(art, bad):
    if os.path.isdir(art):
        return scan_tree(art, bad, art)
    hits = []
    if art.lower().endswith(".iso"):
        d = tempfile.mkdtemp(prefix="knownbad.")
        try:
            r = subprocess.run(["xorriso", "-osirrox", "on", "-indev", art, "-extract", "/", d],
                               capture_output=True, text=True)
            if r.returncode != 0:
                return ["%s: xorriso could not read it" % art]
            if not any(fs for _, _, fs in os.walk(d)):
                return ["%s: no file came out of it: not an ISO, or an empty one" % art]
            hits += scan_tree(d, bad, art)
        finally:
            subprocess.run(["chmod", "-R", "u+w", d])
            shutil.rmtree(d, ignore_errors=True)
    else:
        h = sha_file(art)
        if h in bad:
            hits.append("%s is itself %s" % (art, bad[h][1].split(":")[0]))
    hits += scan_bytes(art, bad)
    return hits


def selftest():
    t = tempfile.mkdtemp()
    ok = True
    try:
        mod = os.urandom(14006)
        sha = hashlib.sha256(mod).hexdigest()
        os.makedirs(os.path.join(t, "pins"))
        open(os.path.join(t, "pins", sha + ".bin"), "wb").write(mod)
        open(os.path.join(t, "list"), "w").write("%s 14006 zbad: test\n" % sha)
        bad = load(os.path.join(t, "list"), os.path.join(t, "pins"))
        tree = os.path.join(t, "tree", "BOOT", "K46")
        os.makedirs(tree)
        open(os.path.join(tree, "G1M06.BIN"), "wb").write(mod)
        img = os.path.join(t, "disk.img")
        with open(img, "wb") as fh:
            fh.write(os.urandom(300000) + mod + os.urandom(300000))
        clean = os.path.join(t, "clean.img")
        kin = bytearray(mod)
        for o in range(700, len(kin), 1500):
            kin[o] ^= 0xff
        open(clean, "wb").write(os.urandom(300000) + bytes(kin) + os.urandom(300000))
        frag = os.path.join(t, "frag.img")
        blocks = [mod[o:o + 1024] for o in range(0, len(mod), 1024)]
        with open(frag, "wb") as fh:
            for i, bl in enumerate(reversed(blocks)):
                fh.write(os.urandom(1024 * (i + 1)) + bl)
        for what, got, want in (("a tree holding the module", bool(scan(os.path.join(t, "tree"), bad)), True),
                                ("a disk image holding its bytes", bool(scan(img, bad)), True),
                                ("a disk holding it in scattered fragments", bool(scan(frag, bad)), True),
                                ("a disk holding a near relative", bool(scan(clean, bad)), False)):
            good = got == want
            ok &= good
            print("  %s %s -> %s" % ("ok  " if good else "FAIL", what, "HIT" if got else "clean"))
        # could not look: never CLEAN
        nb = {sha: (14006, "zbad: test", None)}
        empty = os.path.join(t, "empty.iso")
        open(empty, "wb").close()
        for what, got in (("an empty list", cannot_look({})), ("a module without its bytes", cannot_look(nb)),
                          ("an empty medium", cannot_look(bad, [empty])),
                          ("a missing medium", cannot_look(bad, [os.path.join(t, "absent")])),
                          ("an empty tree", (os.makedirs(os.path.join(t, "e")), cannot_look(bad, [os.path.join(t, "e")]))[1])):
            ok &= bool(got)
            print("  %s %s -> %s" % ("ok  " if got else "FAIL", what, "stops" if got else "CLEAN"))
        junk = os.path.join(t, "junk.iso")
        open(junk, "wb").write(b"not an iso" * 100)
        got = bool(scan(junk, bad))
        ok &= got
        print("  %s a file that is no ISO -> %s" % ("ok  " if got else "FAIL", "reported" if got else "clean"))
    finally:
        shutil.rmtree(t)
    print("known-bad-scan selftest: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv):
    if argv == ["--self-test"]:
        return selftest()
    if not argv:
        print(__doc__)
        return 2
    if not os.path.isfile(LIST):
        print("known-bad-scan: no %s" % LIST)
        return 2
    bad = load()
    why = cannot_look(bad, argv)
    if why:
        print("known-bad-scan: STOP, could not look: " + why)
        return 2
    hits = []
    for a in argv:
        hits += scan(a, bad)
    for h in hits:
        print("HIT " + h)
    print("known-bad-scan: %d artefact(s), %d known-bad module(s): %s"
          % (len(argv), len(bad), "CLEAN" if not hits else "%d HIT(S)" % len(hits)))
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
