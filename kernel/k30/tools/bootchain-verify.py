#!/usr/bin/env python3
# tools/bootchain-verify.py <image> [--profile bootpart|floppy]
#                                   [--identity <key> | --boot2-sha <hex>]
#
# The PERMANENT, fail-closed boot-chain gate. Run host-side against a BUILT golden
# image, AFTER rdb-verify.sh, to prove the on-disk second-stage loader (boot2) is the
# metal-proven flags-based loader -- NOT the foreign install-media loader that D245s.
#
# THE LAYOUT AND THE CHECKSUM ARE NOT DEFINED HERE. They are read from
# ../contracts/bootchain-v1.json, which is this repo's authoritative, machine-readable
# description of the Amix boot chain. Sibling repos (amix-installng, grimoire-amix)
# implement the SAME contract independently and prove conformance against the shared
# vectors in contracts/bootchain-vectors/ -- see tools/bootchain-conform.py.
#
# We share the DEFINITION, not the code, on purpose: these are independently-versioned
# repos with no package manager and no vendoring story, so a cross-repo import would
# make a consumer unbuildable whenever the sibling is absent or on a different commit.
# Two independent implementations that must agree on real vectors is also strictly
# stronger than one shared module -- a shared module that is wrong is wrong on both
# sides at once, and agrees with itself.
#
# WHY THIS GATE EXISTS -- the D245/RELA trap:
#   A from-scratch base image can ship a FOREIGN /stand/boot2.boot copied from the Amix
#   2.1 install media. That install-media boot2 (8192 B, sha256 prefix 5ab360b1) is
#   NAME-based: it resolves the kernel by segment names (.kvsysseg/.kvsegmap/.kvsegu/
#   .uvblock) and CANNOT relocate this project's standard FLAGS-based ET_REL kernels. On
#   metal it fires Alert('RELA'|AT_DeadEnd) -> the D245 4C41 Guru at boot, before the
#   kernel ever executes. The PROVEN loader (flags-based, matches the sysroot boot2.c/
#   rel.c) is 8192 B, sha256 f287ff3a...; the pipeline now installs it during lamination.
#   reltest/relsim validate rel.c SOURCE semantics, so they green a kernel regardless of
#   which loader is on disk -- this gate closes that blind spot by checking the LOADER.
#
# WHICH PROVEN LOADER. The contract names more than one metal-proven
#   identity: `good` (f287ff3a) for the 030 line -- the contract's default_identity and
#   what this gate still expects when the caller names nothing -- and `good_040`
#   (fd7dacf6) for the 68040/68060 line. This gate pins exactly ONE identity per run.
#   It deliberately does NOT accept "any proven loader" by default: an 040 loader sitting
#   in an 030 golden is precisely the wrong-loader condition this gate exists to catch,
#   and a set-membership test would green it. Name the other one with `--identity
#   good_040` (or a literal `--boot2-sha`). When the on-disk blob turns out to be a
#   different PROVEN identity, the FAIL says so by name instead of calling it unknown --
#   see the contract's boot2_identities.unknown_policy.
#
# PROFILES (the disk and floppy paths genuinely differ; conflating them is a known trap):
#   bootpart (default) -- an RDB UNI\0 boot slice. Kernel stored UNCOMPRESSED and
#                         byte-identical; ib_fullsize = 0; offsets FIXED.
#   floppy             -- an 880 KB boot floppy. Kernel LZW-compressed (compress -b16);
#                         ib_fullsize = decompressed size; the checksum covers the
#                         COMPRESSED stream. Offsets are DISCOVERED, not fixed.
#
#   The two profiles are MUTUALLY EXCLUSIVE on ib_fullsize and each rejects the other's
#   convention, in both directions. Do not "helpfully" relax either side.
#
#   A BOOT FLOPPY HAS NO boot2 STAGE. Its layout is the donor bootblock + bootstrap
#   verbatim across 0x0..0x2800, then the compressed kernel at 0x2800 with its IBLK at
#   0x2600. The boot1|IBLK|boot2|IBLK|kernel walk is the BOOTPART layout and ONLY that.
#   So --boot2-sha is a bootpart-only flag and is REFUSED (exit 2) on the floppy profile;
#   the contract is not missing a floppy boot2 map, a floppy has no boot2 to map. This is
#   a design statement, not an omission: do not add one.
#
# CHECKS (ALL must pass for exit 0; every check is evaluated so the diagnosis is complete
# -- this tool never stops at the first failure).
#
# Exit 0 = PASS. Nonzero = a boot-chain defect (with a specific diagnosis); on a non-RDB
# file it fails cleanly with a message (never a traceback). stdlib-only, python3.
#
#   python3 tools/bootchain-verify.py golden.hdf
#   python3 tools/bootchain-verify.py boot.adf --profile floppy
import sys, os, struct, hashlib, json

CONTRACT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        os.pardir, "contracts", "bootchain-v1.json")

BOOT_DT = 0x554e4900                 # 'UNI\0' -- the boot slice DosType (RDB-level, not
                                     # part of the boot-chain contract; see does_not_cover)


def load_contract(path=CONTRACT):
    """Load the authoritative boot-chain contract. Fail closed if it is missing/broken --
    a gate that cannot read its own definition must never silently pass."""
    try:
        with open(path, "rb") as fh:
            return json.load(fh)
    except (OSError, ValueError) as e:
        sys.stderr.write("bootchain-verify: FATAL -- cannot load the boot-chain contract\n"
                         "  %s\n  %s\n"
                         "  This gate reads its layout + checksum definition from that file and\n"
                         "  refuses to run without it (fail closed).\n" % (path, e))
        sys.exit(2)


def proven_identities(c):
    """{sha256_lower: identity_key} for every metal-proven boot2 the contract names.

    boot2_identities.proven is READ, never inferred by iterating the object's keys:
    `size`, `note`, `known_foreign`, `unknown_policy` and the policy keys share that
    object, and a key-iterating reader would classify them as loaders. Fail closed --
    a gate that cannot read its own definition must never silently pass."""
    try:
        ids = c["boot2_identities"]
        return {ids[k]["sha256"].lower(): k for k in ids["proven"]}
    except (KeyError, TypeError, AttributeError) as e:
        sys.stderr.write("bootchain-verify: FATAL -- contract boot2_identities.proven is "
                         "missing or malformed (%s)\n" % e)
        sys.exit(2)


def u32(b, o):
    return struct.unpack('>I', b[o:o+4])[0]


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def chksum(mem):
    """svr4-sum, per contract checksum.algorithm (usr/sys/amiga/boot/chksum.c).

    The & 0xFFFFFFFF is LOAD-BEARING: the C accumulator is a 32-bit `unsigned long` and
    WRAPS. Python ints do not, so without the mask this diverges from the real algorithm
    for any buffer whose byte total reaches 2**32 (~16 MiB of 0xFF).

    This mask was once missing here, invisibly: every buffer ever checksummed was a ~2 MB
    kernel, three orders of magnitude below the threshold. It becomes reachable on a
    miniroot or a whole-slice image. Do not "simplify" this line away. Vector ff-16843010
    pins it."""
    s = 0
    for byte in mem:
        s += byte
    s &= 0xFFFFFFFF
    temp = (s >> 16) + (s & 0xFFFF)
    return (temp >> 16) + (temp & 0xFFFF)


def off(spec):
    """Parse an offset/size that the contract may express as hex string or int."""
    return int(spec, 16) if isinstance(spec, str) else spec


def find_rdsk(img):
    # scan the first 64 blocks, exactly as sdpart.c / rdb-verify.sh do
    for b in range(64):
        if img[b*512:b*512+4] == b'RDSK':
            return b
    return None


def find_boot_slice(img):
    # walk the RDB PartitionList (sdpart.c order) and return the UNI\0 boot slice's
    # byte offset, computed from that partition's Disk-Environment geometry.
    rblk = find_rdsk(img)
    if rblk is None:
        return None, "no RDSK block in the first 64 blocks (not an Amix RDB image?)"
    rdb = img[rblk*512:(rblk+1)*512]
    a = u32(rdb, 28)                 # rdb_PartitionList
    slot = 1
    seen = set()
    while a != 0xffffffff and a < 0xffffffff and slot < 16:
        if a in seen:
            return None, "PartitionList loops at block %d -- corrupt RDB" % a
        seen.add(a)
        if (a + 1) * 512 > len(img):
            return None, "PartitionList block %d past end of image -- truncated RDB" % a
        pb = img[a*512:(a+1)*512]
        if pb[:4] != b'PART':
            return None, "PartitionList entry %d (block %d) is not a PART block" % (slot, a)
        de = lambda i: u32(pb, 128 + i*4)     # DE_* array starts at PART offset 128
        size_block = de(1)                    # DE_SizeBlock (longwords per block)
        surfaces   = de(3)                    # DE_Surfaces
        blks_track = de(5)                    # DE_BlocksPerTrack
        low_cyl    = de(9)                    # DE_LowCyl
        dostype    = de(16)                   # DE_DosType
        if dostype == BOOT_DT:
            cylblk    = surfaces * blks_track
            blk_bytes = size_block * 4        # longwords -> bytes
            byte_off  = low_cyl * cylblk * blk_bytes
            if cylblk == 0 or blk_bytes == 0:
                return None, "boot slice %d has degenerate geometry (cylblk=%d blkbytes=%d)" % (slot, cylblk, blk_bytes)
            return byte_off, None
        slot += 1
        a = u32(pb, 16)                       # pb_Next
    return None, "no UNI\\0 boot slice (DosType 0x554e4900) in the PartitionList"


# ======================================================================================
# profile: bootpart -- the fixed-offset RDB boot slice
# ======================================================================================
def verify_bootpart(img, img_path, c, expect_boot2_sha, identity=None):
    ib = c["infoblock"]["fields"]
    F_SIZE = off(ib["ib_size"]["offset"])
    F_FULL = off(ib["ib_fullsize"]["offset"])
    F_CHK  = off(ib["ib_chksum"]["offset"])
    IBSZ   = c["infoblock"]["struct_size"]
    MAGIC  = c["infoblock"]["magic"].encode("ascii")

    p = c["profiles"]["bootpart"]
    m = p["map"]
    OFF_BOOT1   = off(m["boot1"]["offset"])
    OFF_IBLK_B2 = off(m["iblk_boot2"]["offset"])
    OFF_BOOT2   = off(m["boot2"]["offset"])
    OFF_IBLK_K  = off(m["iblk_unix"]["offset"])
    OFF_KERNEL  = off(m["unix"]["offset"])
    BOOT1_SIZE  = m["boot1"]["size"]
    BOOT2_SIZE  = p["plausibility"]["boot2_size"]
    KERNEL_MIN  = p["plausibility"]["kernel_min_size"]
    FOREIGN     = c["boot2_identities"]["known_foreign"]

    # The bootpart kernel is stored UNCOMPRESSED, so its ib_fullsize must be 0. Sourced
    # from the contract (profiles.bootpart.kernel_ib_fullsize), never a literal -- the
    # contract already carries this value. Fail closed if it is not a number: the floppy
    # profile states its kernel_ib_fullsize prosaically ("the DECOMPRESSED size ..."), so
    # a mis-keyed lookup lands on a string, and a gate must never compare against prose.
    EXPECT_FULL = p["kernel_ib_fullsize"]
    if isinstance(EXPECT_FULL, bool) or not isinstance(EXPECT_FULL, int):
        sys.stderr.write("bootchain-verify: FATAL -- contract profiles.bootpart."
                         "kernel_ib_fullsize is %r, expected an integer\n" % (EXPECT_FULL,))
        sys.exit(2)

    so, err = find_boot_slice(img)
    if so is None:
        print("bootchain-verify: FAIL -- %s" % err)
        return 1
    print("bootchain-verify: UNI\\0 boot slice @ byte 0x%x (LBA %d)" % (so, so // 512))

    problems = []

    # --- boot1 : informational only (boot1 is stock, not gated) ----------------------
    boot1 = img[so+OFF_BOOT1:so+OFF_BOOT1+BOOT1_SIZE]
    print("  boot1  @ %-7s sha256=%s  [informational]" % ("+0x%03x" % OFF_BOOT1, sha256(boot1)))

    # --- iblk(boot2) -----------------------------------------------------------------
    ib2 = img[so+OFF_IBLK_B2:so+OFF_IBLK_B2+IBSZ]
    ib2_magic = ib2[:4]
    ib2_size  = u32(ib2, F_SIZE)
    ib2_chk   = u32(ib2, F_CHK)
    boot2_for_chk = img[so+OFF_BOOT2:so+OFF_BOOT2+(ib2_size if 0 < ib2_size <= (len(img)-so-OFF_BOOT2) else 0)]
    recomputed = chksum(boot2_for_chk) if boot2_for_chk else -1
    print("  iblk   @ %-7s magic=%r ib_size=%d ib_chksum=0x%x  (recompute over boot2=0x%x)"
          % ("+0x%03x" % OFF_IBLK_B2, ib2_magic, ib2_size, ib2_chk, recomputed))
    if ib2_magic != MAGIC:
        problems.append("iblk(boot2) @ +0x%03x has no IBLK magic (got %r)" % (OFF_IBLK_B2, ib2_magic))
    if ib2_size != BOOT2_SIZE:
        problems.append("iblk(boot2).ib_size = %d, expected %d (the proven boot2 is 8192 B)" % (ib2_size, BOOT2_SIZE))
    if recomputed != ib2_chk:
        problems.append("iblk(boot2).ib_chksum = 0x%x but recompute over the on-disk boot2 = 0x%x "
                        "(boot2 swapped without restamping the iblk?)" % (ib2_chk, recomputed))

    # --- boot2 : the load-bearing check ----------------------------------------------
    boot2 = img[so+OFF_BOOT2:so+OFF_BOOT2+BOOT2_SIZE]
    b2_sha = sha256(boot2)
    print("  boot2  @ %-7s sha256=%s" % ("+0x%03x" % OFF_BOOT2, b2_sha))
    if b2_sha != expect_boot2_sha:
        # A DIFFERENT PROVEN IDENTITY is its own fault, with its own fix: the image
        # carries a loader we have booted, just not the one asked for. Diagnosing that
        # as "unknown loader" would send the reader hunting a corruption that is not
        # there -- contract boot2_identities.unknown_policy.
        other = proven_identities(c).get(b2_sha)
        hit = next((f for f in FOREIGN if b2_sha.startswith(f["sha256_prefix"])), None)
        if other is not None:
            print("  *** this boot2 IS a contract-proven loader -- `%s` -- but this run "
                  "expected %s." % (other, expect_boot2_sha[:8] + "..."))
            print("      Proven is not interchangeable: the identities belong to "
                  "different kernel lines")
            print("      (contract boot2_identities.consumer_policy). Re-run with "
                  "--identity %s if that" % other)
            print("      is the chain you meant to check.")
            problems.append("boot2 is the proven `%s` loader, not the expected %s -- "
                            "wrong loader for this chain (not a corruption)"
                            % (other, expect_boot2_sha[:8] + "..."))
        elif hit is not None:
            print("  *** KNOWN-FOREIGN boot2: this is the Amix 2.1 install-media loader (sha %s...) that" % hit["sha256_prefix"])
            print("      D245s on metal -- it is NAME-based and cannot relocate flags-based ET_REL kernels")
            print("      (Alert 'RELA'|AT_DeadEnd = the D245 4C41 Guru).")
            problems.append("boot2 is the KNOWN-FOREIGN install-media loader (sha prefix %s) -- D245/RELA on metal"
                            % hit["sha256_prefix"])
        else:
            problems.append("boot2 sha256 = %s, expected %s (unknown loader -- not the proven flags-based boot2)"
                            % (b2_sha, expect_boot2_sha))

    # --- iblk(unix) ------------------------------------------------------------------
    ibk = img[so+OFF_IBLK_K:so+OFF_IBLK_K+IBSZ]
    ibk_magic = ibk[:4]
    ibk_size  = u32(ibk, F_SIZE)
    ibk_full  = u32(ibk, F_FULL)
    ibk_chk   = u32(ibk, F_CHK)
    kfits     = 0 < ibk_size <= (len(img) - so - OFF_KERNEL)
    krecomp   = chksum(img[so+OFF_KERNEL:so+OFF_KERNEL+ibk_size]) if kfits else -1
    print("  iblk   @ %-7s magic=%r ib_size=%d ib_fullsize=%d ib_chksum=0x%x  "
          "(kernel payload; recompute over unix=0x%x)"
          % ("+0x%03x" % OFF_IBLK_K, ibk_magic, ibk_size, ibk_full, ibk_chk, krecomp))
    if ibk_magic != MAGIC:
        problems.append("iblk(unix) @ +0x%03x has no IBLK magic (got %r)" % (OFF_IBLK_K, ibk_magic))
    else:
        fits = (so + OFF_KERNEL + ibk_size) <= len(img)
        if not (KERNEL_MIN <= ibk_size and fits):
            problems.append("iblk(unix).ib_size = %d is not a plausible kernel (want >= %d and fitting in the image)"
                            % (ibk_size, KERNEL_MIN))

        # --- bootpart-specific semantics: ib_fullsize MUST be 0 here ------------------
        # The mirror image of the floppy profile's "ib_fullsize = 0" rejection. boot2.c
        # branches on exactly this field -- `if (ib_fullsize > 0) decompress(...)` -- so a
        # nonzero value here orders the loader to LZW-decompress a stream that was never
        # compressed. The kernel is intact and every other check greens; the box dies at
        # boot. That is precisely the failure class this gate exists to catch.
        if ibk_full != EXPECT_FULL:
            problems.append("iblk(unix).ib_fullsize = %d on the bootpart profile, must be %d -- a nonzero "
                            "value is the FLOPPY convention (LZW-compressed kernel) appearing on a BOOTPART "
                            "image, where the kernel is stored uncompressed. boot2 decompresses whenever this "
                            "field is > 0, so it would try to decompress an uncompressed kernel."
                            % (ibk_full, EXPECT_FULL))

        # --- the kernel descriptor must describe the kernel actually stored -----------
        # Symmetric with both iblk(boot2) above and the floppy profile's kernel IBLK: a
        # descriptor whose ib_chksum does not match its own payload means the payload was
        # swapped without restamping. boot2.c recomputes this sum and warns on mismatch.
        if kfits and krecomp != ibk_chk:
            problems.append("iblk(unix).ib_chksum = 0x%x but recompute over the on-disk kernel = 0x%x "
                            "(kernel swapped without restamping the iblk?)" % (ibk_chk, krecomp))

    # --- unix ELF magic --------------------------------------------------------------
    kmagic = img[so+OFF_KERNEL:so+OFF_KERNEL+4]
    print("  unix   @ %-7s magic=%s  (want 7f454c46)" % ("+0x%03x" % OFF_KERNEL, kmagic.hex()))
    if kmagic != b'\x7fELF':
        problems.append("no ELF magic (7f454c46) at +0x%03x -- the kernel is not where the boot chain expects it" % OFF_KERNEL)

    return report(problems, expect_boot2_sha, identity=identity)


# ======================================================================================
# profile: floppy -- discovered offsets, LZW-compressed kernel, checksum over the .Z
# ======================================================================================
def verify_floppy(img, img_path, c, expect_boot2_sha):
    ib = c["infoblock"]["fields"]
    F_SIZE = off(ib["ib_size"]["offset"])
    F_FULL = off(ib["ib_fullsize"]["offset"])
    F_CHK  = off(ib["ib_chksum"]["offset"])
    MAGIC  = c["infoblock"]["magic"].encode("ascii")

    p    = c["profiles"]["floppy"]
    pl   = p["plausibility"]
    disc = p["discovery"]
    SIZE = p["medium_size"]
    ZMAGIC = bytes.fromhex(p["compression"]["stream_magic"])
    SCAN_LIMIT = 0x2800          # per contract: IBLK is scanned within the first 0x2800 B
    ZSCAN_FROM = 0x800           # per contract: the .Z magic is sought at/after 0x800

    problems = []

    print("bootchain-verify: floppy profile (medium_size=%d, kernel LZW %s)"
          % (SIZE, p["compression"]["command"]))
    if len(img) != SIZE:
        problems.append("image is %d bytes, expected %d (an 880 KB DD floppy)" % (len(img), SIZE))

    # --- discover the compressed payload (the .Z stream magic) -----------------------
    zoff = img.find(ZMAGIC, ZSCAN_FROM)
    if zoff < 0:
        print("  payload: no LZW stream magic %s at/after 0x%x" % (ZMAGIC.hex(), ZSCAN_FROM))
        problems.append("no compressed kernel: LZW stream magic %s not found at/after 0x%x "
                        "(is this a boot floppy at all?)" % (ZMAGIC.hex(), ZSCAN_FROM))
        return report(problems, expect_boot2_sha, profile="floppy")
    print("  payload@ +0x%04x .Z stream magic %s  (compressed kernel)" % (zoff, ZMAGIC.hex()))

    # --- discover the genuine IBLK ---------------------------------------------------
    # Several byte sequences spell IBLK by coincidence. Per the contract, a candidate is
    # genuine only when its OWN ib_chksum matches svr4-sum over its OWN declared ib_size
    # bytes of the payload; plausibility is the fallback, and is reported as such.
    verified, plausible = [], []
    i = 0
    while True:
        j = img.find(MAGIC, i, SCAN_LIMIT)
        if j < 0:
            break
        i = j + 1
        if j + 0x14 > len(img):
            continue
        comp = u32(img, j + F_SIZE)
        full = u32(img, j + F_FULL)
        chk  = u32(img, j + F_CHK) & 0xFFFF
        if not (0 < comp <= SIZE - zoff):
            continue
        if not (pl["fullsize_min"] < full < pl["fullsize_max"]):
            continue
        plausible.append((j, comp, full, chk))
        if zoff + comp <= len(img) and chksum(img[zoff:zoff+comp]) == chk:
            verified.append((j, comp, full, chk))

    sel = verified or plausible
    if not sel:
        print("  iblk   : no genuine IBLK descriptor in the first 0x%x bytes" % SCAN_LIMIT)
        problems.append("no IBLK descriptor found in the first 0x%x bytes (neither checksum-verified "
                        "nor field-plausible) -- not a recognisable Amix boot floppy" % SCAN_LIMIT)
        return report(problems, expect_boot2_sha, profile="floppy")

    j, comp, full, chk = sel[0]
    how = "checksum-verified" if verified else "plausibility-only"
    recomputed = chksum(img[zoff:zoff+comp]) if zoff + comp <= len(img) else -1
    print("  iblk   @ +0x%04x magic=%r ib_size=%d ib_fullsize=%d ib_chksum=0x%x  (%s; recompute over .Z=0x%x)"
          % (j, MAGIC, comp, full, chk, how, recomputed))

    if not verified:
        problems.append("iblk @ +0x%04x is plausibility-only: its ib_chksum = 0x%x does not match "
                        "svr4-sum over its own %d-byte compressed stream = 0x%x (stale descriptor -- "
                        "the bootstrap will read the wrong length and report a decompression overrun)"
                        % (j, chk, comp, recomputed))

    # --- floppy-specific semantics: ib_fullsize MUST be nonzero here ------------------
    if full == 0:
        problems.append("ib_fullsize = 0 on the floppy profile -- that is the BOOTPART convention "
                        "(uncompressed kernel). A floppy stores an LZW-compressed kernel and must "
                        "carry the decompressed size here.")
    if full <= comp:
        problems.append("ib_fullsize = %d <= ib_size = %d -- the payload is supposed to be compressed, "
                        "so the decompressed size must exceed the stored size" % (full, comp))
    if zoff + comp > SIZE:
        problems.append("payload runs past the end of the medium: 0x%x + %d > %d" % (zoff, comp, SIZE))

    return report(problems, expect_boot2_sha, profile="floppy")


def report(problems, expect_boot2_sha, profile="bootpart", identity=None):
    print()
    if problems:
        print("bootchain-verify: FAIL -- %d problem(s):" % len(problems))
        for p in problems:
            print("   - " + p)
        return 1
    if profile == "floppy":
        print("bootchain-verify: PASS -- intact floppy boot chain (compressed kernel, checksum matches the .Z stream)")
        return 0
    print("bootchain-verify: PASS -- proven flags-based boot2 (%ssha %s...) + intact boot chain"
          % ("`%s`, " % identity if identity else "", expect_boot2_sha[:8]))
    return 0


USAGE = ("usage: bootchain-verify.py <image> [--profile bootpart|floppy]\n"
         "                           [--identity <key> | --boot2-sha <hex>]\n"
         "       --identity names a contract boot2 identity (--list-identities prints them;\n"
         "       default: the contract's default_identity, `good`). --boot2-sha states a\n"
         "       literal hash instead. Both are bootpart-only (a floppy has no boot2 stage).")


def main():
    args = sys.argv[1:]
    img_path = None
    profile = "bootpart"
    expect_boot2_sha = None
    boot2_sha_given = False
    identity = None
    list_identities = False
    i = 0
    while i < len(args):
        a = args[i]
        if a == '--boot2-sha':
            if i + 1 >= len(args):
                print("bootchain-verify: --boot2-sha needs a hex sha256", file=sys.stderr)
                return 2
            expect_boot2_sha = args[i+1].lower()
            boot2_sha_given = True
            i += 2
        elif a == '--identity':
            if i + 1 >= len(args):
                print("bootchain-verify: --identity needs a contract identity key",
                      file=sys.stderr)
                return 2
            identity = args[i+1]
            i += 2
        elif a == '--list-identities':
            list_identities = True
            i += 1
        elif a == '--profile':
            if i + 1 >= len(args):
                print("bootchain-verify: --profile needs a name (bootpart|floppy)", file=sys.stderr)
                return 2
            profile = args[i+1]
            i += 2
        elif a in ('-h', '--help'):
            print(USAGE)
            return 0
        elif a.startswith('-'):
            print("bootchain-verify: unknown option: %s" % a, file=sys.stderr)
            return 2
        else:
            if img_path is not None:
                print("bootchain-verify: unexpected extra argument: %s" % a, file=sys.stderr)
                return 2
            img_path = a
            i += 1

    # --list-identities is an inspection mode, not a check: it needs the contract and
    # nothing else, so it is answered before the image is demanded.
    if list_identities:
        c = load_contract()
        ids = c["boot2_identities"]
        print("bootchain-verify: proven boot2 identities in the contract")
        for k in ids["proven"]:
            print("  %-10s %s  %s" % (k, ids[k]["sha256"], ids[k].get("line", "")))
        print("  (default: %s)" % ids["default_identity"])
        return 0

    # --identity and --boot2-sha both answer "which hash must the on-disk loader have",
    # one by contract name and one as a literal. Honouring one and dropping the other
    # would report on an identity the caller did not name -- the same accept-and-ignore
    # defect the floppy guard below refuses.
    if identity is not None and boot2_sha_given:
        print("bootchain-verify: --identity and --boot2-sha are mutually exclusive.\n"
              "  Both state the expected loader hash -- one by contract name, one as a\n"
              "  literal. Refusing rather than silently picking one.", file=sys.stderr)
        return 2

    if img_path is None:
        print(USAGE, file=sys.stderr)
        return 2
    if not os.path.isfile(img_path):
        print("bootchain-verify: no such image: %s" % img_path, file=sys.stderr)
        return 2

    c = load_contract()
    if profile not in c["profiles"]:
        print("bootchain-verify: unknown --profile '%s' (contract v%s defines: %s)"
              % (profile, c["version"], "|".join(sorted(c["profiles"]))), file=sys.stderr)
        return 2
    # --boot2-sha is meaningful ONLY on the bootpart profile. A boot floppy genuinely has
    # no boot2 stage to identify (see PROFILES above), so there is nothing here for the
    # flag to check. Accepting it and quietly proceeding would be the accept-and-ignore
    # defect: an argument the tool cannot honour, swallowed in silence, exit 0. This is
    # deliberately NOT reported as an unknown option, which would imply a typo -- the flag
    # is spelled correctly and simply does not apply to this profile.
    if profile == "floppy" and (boot2_sha_given or identity is not None):
        flag = "--boot2-sha" if boot2_sha_given else "--identity"
        print("bootchain-verify: %s does not apply to the floppy profile.\n"
              "  A boot floppy has no boot2 stage: its layout is the donor bootblock and\n"
              "  bootstrap verbatim across 0x0..0x2800, then the LZW-compressed kernel at\n"
              "  0x2800 described by the IBLK at 0x2600. The boot1|IBLK|boot2|IBLK|kernel\n"
              "  walk is the BOOTPART layout and only that, so there is no second-stage\n"
              "  loader here to identify and this flag would be silently inert.\n"
              "  Drop %s, or use --profile bootpart." % (flag, flag), file=sys.stderr)
        return 2

    # WHICH identity: a literal --boot2-sha, else the named --identity, else the
    # contract's default_identity. Exactly one hash is pinned either way -- this gate
    # never accepts "any proven loader" (see WHICH PROVEN LOADER at the top).
    if expect_boot2_sha is None:
        ids = c["boot2_identities"]
        if identity is None:
            identity = ids["default_identity"]
        cands = ids.get("candidate", [])
        if identity in cands:
            print("bootchain-verify: identity '%s' is a CANDIDATE (emulator-observed, not "
                  "metal-proven; contract boot2_identities.candidate_note)" % identity)
        elif identity not in proven_identities(c).values():
            print("bootchain-verify: '%s' is not a proven identity in the contract.\n"
                  "  boot2_identities.proven names: %s\n"
                  "  (or state a literal hash with --boot2-sha <hex> for a loader the\n"
                  "  contract does not name.)"
                  % (identity, ", ".join(ids["proven"])), file=sys.stderr)
            return 2
        expect_boot2_sha = ids[identity]["sha256"].lower()

    with open(img_path, 'rb') as fh:
        img = fh.read()

    print("bootchain-verify: %s (%d bytes)" % (img_path, len(img)))
    if profile != "floppy":
        print("bootchain-verify: expecting boot2 %s"
              % ("identity `%s` (sha %s...)" % (identity, expect_boot2_sha[:8])
                 if identity else
                 "sha %s... (literal --boot2-sha)" % expect_boot2_sha[:8]))

    if profile == "floppy":
        return verify_floppy(img, img_path, c, expect_boot2_sha)
    return verify_bootpart(img, img_path, c, expect_boot2_sha, identity)


if __name__ == '__main__':
    sys.exit(main())
