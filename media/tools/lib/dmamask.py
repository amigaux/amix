# tools/lib/dmamask.py -- THE table: each disk controller's DosEnvec Mask.
#
# Why it matters: the loaders take their DMA buffers by the boot partition's
# DosEnvec, as FFS does (amix-dlm a6a1511/053c417, spec 10 sections 3.1/3.2). boot1
# allocates de_BufMemType memory and falls back to chip when the block's end lies
# beyond de_Mask; boot2 reads straight into any destination the Mask allows. So
# the Mask must say what the boot controller's DMA can really reach. The rule
# (2026-10-28, matching the kernel's DMA reach contract,
# amix-dlm core/plat/k30/line.c DMA_REACH 0x08000000 and C4-5; C4-2 / an open question:
# Zorro III DMA cannot reach the Z3660's DDR at $08000000+):
#
#   Zorro III DMA (A4091, A4092)            0x07FFFFFE  chip + motherboard fast
#   motherboard DMA (A3000 SDMAC)           0x07FFFFFE  the same reach, held to it
#   24-bit Zorro II DMA (A2091, A2090)      0x00FFFFFE
#   A4000T onboard 53C710                   0xFFFFFFFC  reaches the Z3660 DDR (proven)
#                                                       and must NOT use chip: it
#                                                       hangs the A4000T with the
#                                                       Z3660 (stage c, 2026-10-28)
#   PIO / emulated (Gayle IDE, Z3660 piscsi) 0xFFFFFFFC
#   an unknown controller                   0x07FFFFFE  conservative, and a warning
#
# de_BufMemType stays 0 (MEMF_PUBLIC) everywhere.
#
# Every RDB this repo writes takes its Mask from here: the host builders through
# tools/dmamask.py, the on-box installer through the medium's /install/dmamask
# (tools/dmamask.py medium, staged by tools/build-install-iso.sh). No literal Mask
# anywhere else. The controller names are tools/sdnames.py's SD_BOARDS names.
#
# Stdlib-only, python3.

import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rdb  # noqa: E402

# name -> (Mask, class, why). Order is the order the medium table is written in.
TABLE = (
    ("a4091",     0x07FFFFFE, "zorro3-dma", "Zorro III DMA; never the Z3660 DDR at $08000000+"),
    ("a4092",     0x07FFFFFE, "zorro3-dma", "Zorro III DMA; never the Z3660 DDR at $08000000+"),
    ("a3000",     0x07FFFFFE, "mobo-dma",   "A3000 SDMAC; held to the kernel's DMA reach"),
    ("a2091",     0x00FFFFFE, "zorro2-dma", "24-bit Zorro II DMA"),
    ("a2090",     0x00FFFFFE, "zorro2-dma", "24-bit Zorro II DMA"),
    ("a4000t",    0xFFFFFFFC, "a4kt710",    "A4000T onboard 53C710: reaches the Z3660 DDR, hangs in chip"),
    ("gayle",     0xFFFFFFFC, "pio",        "Gayle IDE, PIO"),
    ("buddha",    0xFFFFFFFC, "pio",        "Buddha IDE, PIO"),
    ("catweasel", 0xFFFFFFFC, "pio",        "Catweasel Z-II IDE, PIO"),
    ("z3660scsi", 0xFFFFFFFC, "emulated",   "Z3660 piscsi mailbox, no bus DMA"),
)
ALIASES = {"a4kt710": "a4000t"}
UNKNOWN_MASK = 0x07FFFFFE
BUFMEMTYPE = 0                      # MEMF_PUBLIC

DE_BUFMEMTYPE = 12                  # DosEnvec longword indices
DE_MAXTRANSFER = 13
DE_MASK = 14
_PB_DE = 128
_PB_CHKSUM = 8


def canon(hba):
    h = (hba or "").strip().lower()
    return ALIASES.get(h, h)


def mask_for(hba):
    """(mask, known) for a controller name; an unknown or empty name -> UNKNOWN_MASK, False."""
    h = canon(hba)
    for name, mask, _cls, _why in TABLE:
        if name == h:
            return mask, True
    return UNKNOWN_MASK, False


def unknown_warning(hba, what="disk"):
    return ("dmamask: WARNING: %s controller %r is not in the DMA table -- Mask 0x%08X "
            "(conservative: chip + motherboard fast). Name it (tools/lib/dmamask.py TABLE)."
            % (what, hba or "", UNKNOWN_MASK))


# --- profiles ----------------------------------------------------------------
def read_profile(path):
    kv = {}
    for line in open(path, encoding="latin-1"):
        m = re.match(r'^([A-Z][A-Z0-9_]*)=(.*)$', line.rstrip("\n"))
        if m:
            kv[m.group(1)] = m.group(2).strip().strip('"')
    return kv


def _card(cid):
    try:
        return int(cid, 16) // 8
    except (TypeError, ValueError):
        return None


def profile_hba(kv, role):
    """The controller a profile's disk hangs off: role 'target' (TARGET_HBA) or 'src'.

    The source disk: SRC_HBA when the profile names it; else TARGET_HBA when the
    source sits on the target's card; else the card's entry in SD_BOARDS (base
    order, the two-card numbering). "" when none of these says.
    """
    if role == "target":
        return kv.get("TARGET_HBA", "")
    if role != "src":
        raise ValueError("role must be target or src")
    if kv.get("SRC_HBA"):
        return kv["SRC_HBA"]
    sc, tc = _card(kv.get("SRC_SCSI_ID")), _card(kv.get("TARGET_SCSI_ID"))
    if sc is not None and sc == tc and kv.get("TARGET_HBA"):
        return kv["TARGET_HBA"]
    boards = kv.get("SD_BOARDS", "").split()
    if sc is not None and sc < len(boards):
        return boards[sc]
    return ""


# --- reading and checking an image --------------------------------------------
def _u32(b, o):
    return struct.unpack('>I', b[o:o + 4])[0]


def part_fields(img):
    """[(slot, name, bufmemtype, maxtransfer, mask, dostype, part_block, checksum_ok)]."""
    _rblk, slices = rdb.read_rdb(img)
    out = []
    for s in slices:
        pb = img[s.part_block * 512:(s.part_block + 1) * 512]
        de = lambda i: _u32(pb, _PB_DE + 4 * i)
        out.append((s.slot, s.name, de(DE_BUFMEMTYPE), de(DE_MAXTRANSFER), de(DE_MASK),
                    s.dostype, s.part_block, rdb.block_checksum_ok(pb)))
    return out


def format_fields(fields):
    return "\n".join("    slice %d %-12s bufmemtype 0x%x maxtransfer 0x%x mask 0x%08X dostype 0x%08x "
                     "(PART block %d, checksum %s)"
                     % (sl, nm, bm, mt, mk, dt, pb, "ok" if ck else "BAD")
                     for sl, nm, bm, mt, mk, dt, pb, ck in fields)


def check_image(img, want_mask):
    """Problems (empty == conforming): every PART's Mask == want, BufMemType == 0,
    every PART checksum closes."""
    problems = []
    try:
        fields = part_fields(img)
    except rdb.RdbError as e:
        return ["RDB unreadable: %s" % e], []
    for sl, nm, bm, _mt, mk, _dt, pb, ck in fields:
        if mk != want_mask:
            problems.append("slice %d %r: Mask 0x%08X, the table says 0x%08X" % (sl, nm, mk, want_mask))
        if bm != BUFMEMTYPE:
            problems.append("slice %d %r: BufMemType 0x%x, expected 0x%x (MEMF_PUBLIC)" % (sl, nm, bm, BUFMEMTYPE))
        if not ck:
            problems.append("slice %d %r: PART block %d checksum does not close" % (sl, nm, pb))
    return problems, fields


def set_mask(img, mask):
    """Patch every PART's Mask in a bytearray image and re-close its checksum
    (the self-test's synthetic fixtures; the builders pass the Mask to rdbtool)."""
    _rblk, slices = rdb.read_rdb(bytes(img))
    for s in slices:
        o = s.part_block * 512
        struct.pack_into('>I', img, o + _PB_DE + 4 * DE_MASK, mask)
        struct.pack_into('>I', img, o + _PB_CHKSUM, 0)
        n = _u32(img, o + 4)
        tot = sum(struct.unpack('>%dI' % n, bytes(img[o:o + 4 * n]))) & 0xFFFFFFFF
        struct.pack_into('>I', img, o + _PB_CHKSUM, (-tot) & 0xFFFFFFFF)
    return img


# --- the on-box table ----------------------------------------------------------
def medium_rows():
    """The medium's /install/dmamask: '<name> <b0> <b1> <b2> <b3> <hex>' per controller,
    then '* ...' for an unknown one. Decimal bytes, no comments: the 1991 sh reads it
    with `read` and does its arithmetic with expr."""
    rows = []
    for name, mask, _cls, _why in TABLE:
        b = struct.pack('>I', mask)
        rows.append("%s %d %d %d %d 0x%08X" % ((name,) + tuple(b) + (mask,)))
    for alias, name in sorted(ALIASES.items()):
        mask = mask_for(name)[0]
        b = struct.pack('>I', mask)
        rows.append("%s %d %d %d %d 0x%08X" % ((alias,) + tuple(b) + (mask,)))
    b = struct.pack('>I', UNKNOWN_MASK)
    rows.append("* %d %d %d %d 0x%08X" % (tuple(b) + (UNKNOWN_MASK,)))
    return "\n".join(rows) + "\n"


# --- a synthetic RDB (the self-tests' fixture: no rdbtool, no media) ----------
def synth_rdb(mask, nparts=3, cyls=40, rdsk_block=0, bufmemtype=BUFMEMTYPE):
    """A small image with an RDSK and `nparts` PART blocks (root, swap, boot) whose
    DosEnvec carries `mask`, every checksum closed -- the shape /etc/rdb and rdbtool write."""
    img = bytearray(cyls * 64 * 512)

    def close(o):
        struct.pack_into('>I', img, o + 8, 0)
        n = _u32(img, o + 4)
        tot = sum(struct.unpack('>%dI' % n, bytes(img[o:o + 4 * n]))) & 0xFFFFFFFF
        struct.pack_into('>I', img, o + 8, (-tot) & 0xFFFFFFFF)

    o = rdsk_block * 512
    img[o:o + 4] = b'RDSK'
    struct.pack_into('>I', img, o + 4, 64)
    struct.pack_into('>I', img, o + 16, 512)
    struct.pack_into('>I', img, o + 28, rdsk_block + 1)          # rdb_PartitionList
    struct.pack_into('>I', img, o + 64, cyls)
    struct.pack_into('>I', img, o + 68, 64)
    struct.pack_into('>I', img, o + 72, 1)
    close(o)
    names = (("UNIX_Root", rdb.DT_ROOT), ("UNIX_Swap", rdb.DT_SWAP), ("UNIX_Boot", rdb.DT_BOOT),
             ("Extra", rdb.DT_ROOT))
    low = 2
    for i in range(nparts):
        blk = rdsk_block + 1 + i
        o = blk * 512
        img[o:o + 4] = b'PART'
        struct.pack_into('>I', img, o + 4, 64)
        struct.pack_into('>I', img, o + 12, 7)
        struct.pack_into('>I', img, o + 16, blk + 1 if i + 1 < nparts else 0xFFFFFFFF)
        nm, dt = names[i]
        struct.pack_into('>I', img, o + 20, 1 if dt == rdb.DT_BOOT else 2)
        img[o + 36] = len(nm)
        img[o + 37:o + 37 + len(nm)] = nm.encode()
        de = (16, 128, 0, 1, 1, 64, 2, 0, 0, low, low + 9, 30, bufmemtype, 0xFFFFFF, mask,
              2 if dt == rdb.DT_BOOT else 0, dt)
        struct.pack_into('>17I', img, o + _PB_DE, *de)
        low += 10
        close(o)
    return img
