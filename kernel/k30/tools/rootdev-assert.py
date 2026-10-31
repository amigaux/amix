#!/usr/bin/env python3
# rootdev-assert.py -- read the baked-in `rootdev` back out of a linked Amix kernel and
# assert it is the root device the intended config declares.  Fail-closed backstop for the
# on-box native build (build-onbox-kernel.sh): if `make` ever rebuilds amiga/config/unix.o
# from the DEFAULT unix.c (the box's /stand/CONFIG rootdev) instead of the selected
# c6s1unix/c0s1unix/fd0unix, the kernel silently carries the WRONG root device and PANICs on
# the metal box at s5mountroot (`VOP_OPEN error 6` / `vfs_mountroot errno 30`).  This catches
# that on the HOST, before the image is ever laminated or deployed.
#
# Standalone, python3 stdlib only (like tools/relsim.py) -- it parses the ELF itself, no
# objdump/readelf.  The kernel is a big-endian (MSB) 32-bit m68k ET_REL object; `rootdev` is
# a 4-byte OBJECT symbol whose value is a compile-time constant (makedevice() folds to an
# integer literal, no relocation), so the stored bytes ARE the linked dev_t.
#
# Readback: find `rootdev` in .symtab -> (st_shndx, st_value, st_size); splice st_size
# big-endian bytes at st_value within section st_shndx's file image -> the dev_t.
#
# Expected values -- DERIVED from the config sources (amiga/config/<name>.c) + the kernel's
# own makedevice() bit layout in sys/sysmacros.h, NOT guessed:
#     #define makedevice(x,y)  ((x) << L_BITSMINOR) | ((y) & L_MAXMIN)
#     L_BITSMINOR = 18 , L_MAXMIN = 0x3ffff            (sys/sysmacros.h)
#   c6s1unix.c: rootdev = C6D0S1 = makedevice(18,22) = (18<<18)|22 = 0x00480016  (metal Z3660 HD, c6d0s1)
#   c0s1unix.c: rootdev = C0D0S1 = makedevice(18,16) = (18<<18)|16 = 0x00480010  (SCSI tgt0 s1, c0d0s1)
#   fd0unix.c : rootdev = FD0P   = makedevice(16, 8) = (16<<18)| 8 = 0x00400008  (floppy/install root)
#   unix.c    : rootdev = the -DROOTDEV compile macro -- a PLACEHOLDER with no fixed value,
#               so it is intentionally NOT in the table and fails closed (unknown config).
#
# THE TABLE IS NOT DEFINED HERE.  It is read from ../contracts/bootchain-v1.json
# (section `rootdev`), this repo's authoritative machine-readable description of the Amix
# boot chain, so the config<->dev_t mapping has exactly one home.  Fail closed if the
# contract cannot be read: a gate that cannot read its own definition must never pass.
#
# MINIROOT PAIRING.  The installer work needs a miniroot on TWO media -- a floppy
# (fd0unix) and a raw RDB slice 1 (c0s1unix / c6s1unix) -- each paired with a kernel built
# for that root device.  The contract records a `media` and a `miniroot` flag per config,
# and --media <floppy|scsi-slice> asserts the kernel's config is valid for the medium it is
# about to be written to.  That pairing is the thing that goes wrong silently: a floppy
# miniroot carrying a c6s1unix kernel is a perfectly valid kernel on the wrong medium.
#
# Usage:
#   rootdev-assert.py <kernel-elf> --config <c6s1unix|c0s1unix|fd0unix>
#   rootdev-assert.py <kernel-elf> --expect 0xHEX
#   rootdev-assert.py <kernel-elf> --config fd0unix --media floppy     # + medium pairing
#   rootdev-assert.py --list                                           # show the table
# Exit 0 + one PASS line on match; exit 1 + a metal-PANIC warning on mismatch or any error.
import sys, os, struct, argparse, json

CONTRACT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        os.pardir, "contracts", "bootchain-v1.json")


def load_contract(path=CONTRACT):
    try:
        with open(path, "rb") as fh:
            return json.load(fh)
    except (OSError, ValueError) as e:
        sys.stderr.write("rootdev-assert: FATAL -- cannot load the boot-chain contract\n"
                         "  %s\n  %s\n"
                         "  The config->rootdev table lives there; this gate refuses to run\n"
                         "  without it (fail closed).\n" % (path, e))
        sys.exit(1)


_C = load_contract()
_RD = _C["rootdev"]

L_BITSMINOR = _RD["L_BITSMINOR"]
L_MAXMIN    = int(_RD["L_MAXMIN"], 16)

# config name -> the linked dev_t its <name>.c source hardcodes (derivation in the header).
CONFIG_ROOTDEV = {k: int(v["rootdev"], 16) for k, v in _RD["configs"].items()}
CONFIG_META    = _RD["configs"]

SHT_SYMTAB = 2
SHT_NOBITS = 8
SHN_UNDEF  = 0
SHN_LORESERVE = 0xff00   # SHN_ABS/COMMON/etc. live at/above here -- not a real section

def u16(b, o): return struct.unpack_from(">H", b, o)[0]
def u32(b, o): return struct.unpack_from(">I", b, o)[0]


def fail(msg):
    sys.stderr.write("rootdev-assert: FATAL -- %s\n" % msg)
    sys.exit(1)


def read_rootdev(path):
    """Return (value, major, minor, size) for the `rootdev` symbol in an Amix kernel ELF."""
    try:
        d = open(path, "rb").read()
    except OSError as e:
        fail("cannot read %s: %s" % (path, e))
    if d[:4] != b"\x7fELF":
        fail("%s is not an ELF file" % path)
    if d[4] != 1:  # EI_CLASS
        fail("%s is not a 32-bit ELF (ELFCLASS != 32)" % path)
    if d[5] != 2:  # EI_DATA
        fail("%s is not big-endian (MSB) -- an Amix m68k kernel must be" % path)
    e_type    = u16(d, 16)
    e_machine = u16(d, 18)
    if e_type != 1:
        fail("%s is not ET_REL (e_type=%d) -- expected the relocatable kernel object" % (path, e_type))
    if e_machine != 4:
        fail("%s is not m68k (e_machine=%d, want 4)" % (path, e_machine))
    e_shoff     = u32(d, 32)
    e_shentsize = u16(d, 46)
    e_shnum     = u16(d, 48)
    if e_shoff == 0 or e_shnum == 0:
        fail("%s has no section headers" % path)

    # section headers
    sec = []
    for i in range(e_shnum):
        o = e_shoff + i * e_shentsize
        sec.append(dict(type=u32(d, o + 4), offset=u32(d, o + 16),
                        size=u32(d, o + 20), link=u32(d, o + 24),
                        entsize=u32(d, o + 36)))

    symtab = next((s for s in sec if s["type"] == SHT_SYMTAB), None)
    if symtab is None:
        fail("%s has no .symtab (stripped?) -- cannot locate rootdev" % path)
    esz = symtab["entsize"] or 16
    strtab = sec[symtab["link"]]
    strdata = d[strtab["offset"]:strtab["offset"] + strtab["size"]]

    def symname(st_name):
        end = strdata.find(b"\0", st_name)
        return strdata[st_name:end].decode("latin1")

    nsyms = symtab["size"] // esz
    for i in range(nsyms):
        o = symtab["offset"] + i * esz
        st_name  = u32(d, o)
        if st_name == 0:
            continue
        if symname(st_name) != "rootdev":
            continue
        st_value = u32(d, o + 4)
        st_size  = u32(d, o + 8)
        st_shndx = u16(d, o + 14)
        if st_shndx == SHN_UNDEF or st_shndx >= SHN_LORESERVE or st_shndx >= e_shnum:
            fail("rootdev symbol has no real section (st_shndx=0x%x) -- undefined/absolute" % st_shndx)
        host = sec[st_shndx]
        if host["type"] == SHT_NOBITS:
            fail("rootdev lives in a NOBITS section (.bss) -- uninitialised, cannot read its value")
        if st_size == 0:
            st_size = 4  # dev_t
        start = host["offset"] + st_value
        raw = d[start:start + st_size]
        if len(raw) != st_size:
            fail("rootdev bytes run past end of file (off=0x%x size=%d)" % (start, st_size))
        value = int.from_bytes(raw, "big")
        major = (value >> L_BITSMINOR) & 0xff
        minor = value & L_MAXMIN
        return value, major, minor, st_size
    fail("no 'rootdev' symbol in %s" % path)


def main():
    ap = argparse.ArgumentParser(
        description="Assert a linked Amix kernel's baked-in rootdev matches the intended config.")
    ap.add_argument("kernel", nargs="?",
                    help="the linked kernel ELF (ET_REL m68k), e.g. work/onbox-kernel/unix")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--config", help="config name: %s" % "|".join(sorted(CONFIG_ROOTDEV)))
    g.add_argument("--expect", help="expected rootdev as 0xHEX (or decimal)")
    ap.add_argument("--media", help="assert the config is valid for this root medium "
                                    "(%s)" % "|".join(sorted({m["media"] for m in CONFIG_META.values()})))
    ap.add_argument("--miniroot", action="store_true",
                    help="assert the config is usable as a miniroot root device")
    ap.add_argument("--list", action="store_true",
                    help="print the config table from the contract and exit")
    args = ap.parse_args()

    if args.list:
        print("rootdev-assert: config table  (contract v%s, section rootdev)" % _C["version"])
        for name in sorted(CONFIG_META):
            m = CONFIG_META[name]
            print("  %-9s rootdev=%s  major=%-3d minor=%-3d  media=%-11s miniroot=%-5s  %s"
                  % (name, m["rootdev"], m["major"], m["minor"], m["media"],
                     str(bool(m.get("miniroot"))).lower(), m["symbol"]))
        for name, why in _RD.get("excluded", {}).items():
            print("  %-9s EXCLUDED -- %s" % (name, why))
        return

    if args.kernel is None:
        fail("a kernel ELF is required (or use --list)")
    if args.config is None and args.expect is None:
        fail("one of --config or --expect is required (or use --list)")
    if args.media is not None and args.config is None:
        fail("--media needs --config (the medium is asserted against the config's pairing)")
    if args.miniroot and args.config is None:
        fail("--miniroot needs --config")

    if args.config is not None:
        if args.config not in CONFIG_ROOTDEV:
            fail("unknown --config '%s' (known: %s; plain 'unix' is a compile-macro placeholder "
                 "with no fixed rootdev)" % (args.config, "|".join(sorted(CONFIG_ROOTDEV))))
        want = CONFIG_ROOTDEV[args.config]
        label = args.config
        meta = CONFIG_META[args.config]
        # --- medium pairing: the right kernel on the WRONG medium is still a dead box ---
        if args.media is not None and args.media != meta["media"]:
            sys.stderr.write(
                "rootdev-assert: MEDIA MISMATCH -- config '%s' roots on %s, not %s\n"
                "  %s\n"
                "  A kernel whose rootdev names a device the boot medium does not present\n"
                "  PANICs at s5mountroot exactly like a wrong rootdev does (VOP_OPEN error 6\n"
                "  / vfs_mountroot errno 30).  Pair a '%s' miniroot with a config whose\n"
                "  media is '%s'.\n"
                % (args.config, meta["media"], args.media, meta["note"],
                   args.media, args.media))
            sys.exit(1)
        if args.miniroot and not meta.get("miniroot"):
            sys.stderr.write("rootdev-assert: config '%s' is not marked usable as a miniroot "
                             "root device in the contract\n" % args.config)
            sys.exit(1)
    else:
        try:
            want = int(args.expect, 0)
        except ValueError:
            fail("--expect '%s' is not an integer (use 0xHEX or decimal)" % args.expect)
        label = "expect"

    value, major, minor, size = read_rootdev(args.kernel)
    if value == want:
        print("rootdev-assert: PASS  rootdev = 0x%08x  (major=%d minor=%d, %d bytes)  [%s]"
              % (value, major, minor, size, label))
        if args.media is not None:
            print("rootdev-assert: PASS  media pairing: config '%s' roots on %s  [%s]"
                  % (args.config, CONFIG_META[args.config]["media"], args.media))
        if args.miniroot:
            print("rootdev-assert: PASS  config '%s' is a contract-approved miniroot root device"
                  % args.config)
        sys.exit(0)

    sys.stderr.write(
        "rootdev-assert: MISMATCH -- %s\n"
        "  linked rootdev = 0x%08x  (major=%d minor=%d)\n"
        "  expected       = 0x%08x  [%s]\n"
        "  A kernel with the wrong rootdev PANICs the metal box at s5mountroot\n"
        "  (VOP_OPEN error 6 / vfs_mountroot errno 30).  Likely cause: make rebuilt\n"
        "  amiga/config/unix.o from the default unix.c (/stand/CONFIG rootdev) instead\n"
        "  of the selected config.  Do NOT laminate or deploy this kernel.\n"
        % (args.kernel, value, major, minor, want, label))
    sys.exit(1)


if __name__ == "__main__":
    main()
