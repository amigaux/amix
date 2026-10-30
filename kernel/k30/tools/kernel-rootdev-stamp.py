#!/usr/bin/env python3
"""kernel-rootdev-stamp.py -- write a destination SCSI id into an 040/060-line AMIX kernel,
host-side, by SYMBOL: rewriting `rootdev` and `swapfile.bo_name` and nothing else.

    ./tools/kernel-rootdev-stamp.py show   <kernel>
    ./tools/kernel-rootdev-stamp.py verify <kernel> --id N [--root-slice 1] [--swap-slice 2]
    ./tools/kernel-rootdev-stamp.py stamp  <kernel> --id N [-o <out>]
    ./tools/kernel-rootdev-stamp.py table  <kernel> [--ids 0-7] [--format json|pkginfo|text]
    ./tools/kernel-rootdev-stamp.py --selftest

WHY THIS EXISTS, AND WHY IT IS NOT kernel-rootdev-patch.py.  The 030 line ships a brel
whose .symtab elf2brel discarded, so kernel-rootdev-patch.py locates `rootdev`/`swapfile`
by the `/dev/dsk/c` ANCHOR (rootdev = anchor - 0x14) -- a derivation that rests on `rootdev`
being declared immediately before `swapfile` so the linker lays them adjacent.  On the
040/060 line that adjacency DOES NOT HOLD: four globals (dumpdev, char_special, do_sysdump,
no_interactive) sit between them, so the anchor lands 16 bytes past `rootdev`
(anchor - rootdev = 0x24 as measured, not 0x14).  The existing tool
correctly REFUSES that input.  But the 040/060 kernel is an ET_REL that RETAINS its full
.symtab (some 16 000 entries), so `rootdev`/`swapfile`/`rootfstype` are locatable by name
directly -- cleaner and exact.  This tool is the symbol-located sibling, the same way
kernel-cputype-stamp.py is the symbol-located stamp for `cputype` on this same line.

THE RULES ARE NOT DEFINED HERE.  The device-number encoding, the struct bootobj layout, the
minor encoding, the slice convention, the device-name shape, the per-id table schema, the
`rootfstype` semantics and the by-symbol site derivation are all read from
../contracts/bootchain-v1.json section `rootdev` (`.patch` + `.rootfstype` +
`.patch.site_derivation.by_symbol`), this repo's authoritative machine-readable description
of the boot chain, so the definition has exactly one home.  Fail closed if the contract
cannot be read or is missing a key: a gate that cannot read its own definition must never
pass.  The arithmetic (compose_dev, svr4-sum, BSD sum -r) is reimplemented independently
here -- the same independent-implementations-agree-on-vectors discipline the contract's
conformance_protocol prescribes -- and the selftest cross-checks it against the contract
vectors and coreutils `sum -r`.

THE SAFETY DISCIPLINE, borrowed from kernel-cputype-stamp.py.  A stamp is the ONLY mutation
of the kernel bytes, and it is proved from both ends:

  * BEFORE any write, the image must pass the full coherence gate -- a big-endian m68k
    ET_REL; `rootdev`/`swapfile`/`rootfstype` each a GLOBAL OBJECT in .data; the anchor a
    cross-check landing at swapfile + 0x10; no relocation over either written range or over
    rootfstype; the dev_t an sd root on card 0 or 1 (by_symbol.cards; the default and the
    installer convention is card 0; card 1 only on --card 1 for the PRE-PROBE families --
    kernels without the W-D7 probe, where the phantom A3000 controller sorts below the Z3660
    (K060, the rollback line)) with the convention slice; bo_name matching the HEX
    device-name shape (card 1 unit 6 = ced0s2) and AGREEING with rootdev's minor; bo_fstype/bo_flags/bo_offset/
    bo_vp zero; bo_size non-zero; and rootfstype EMPTY (see below).  A kernel whose root and
    swap fields do not already describe one coherent disk is the failure that PANICs a box
    at s5mountroot, and it is refused here at production time.
  * AFTER the write, the file is re-read from disk and compared WHOLE: it may differ from its
    input ONLY inside [rootdev, rootdev+4) and [bo_name, bo_name+128).  A writer that also
    truncated, padded or moved something else passes the narrow check and fails this one.

rootfstype IS ASSERTED, NEVER WRITTEN.  The 040/060 line is UFS-root, and every measured
build ships `rootfstype` empty -- vfs_mountroot then iterates vfssw and mounts ufs, exactly
as the metal-proven 030 UFS-root kernels do (the mechanism is stock 2.1c, byte-inherited;
none of the 12 override bindings touch it).  So there is nothing to write.  The stamp
ASSERTS it is empty, fail-closed, so a future non-empty value can never slip a wrong root
fstype past the gate; it is contract key `rootdev.rootfstype.stamp_needed: false`.

THE TABLE.  A stamp is deterministic: id N -> known bytes -> known `sum -r` / svr4-sum / md5
/ sha256.  `table` applies the stamp for every admissible id host-side and emits that per-id
table, the only reconciliation that keeps the downstream checksum gates fail-closed once a
stamped kernel is framed (computing the sums on the box would make every gate agree with
itself).  It is a BUILD ARTIFACT, per driver mix and per cputype; never a constant.

exit 0 = pass, 1 = refusal / mismatch (the fail-closed verdict), 2 = usage, unreadable
input, or an unreadable/incomplete contract.
"""
import argparse
import hashlib
import json
import os
import re
import struct
import sys

WHOAMI = "kernel-rootdev-stamp"
CONTRACT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        os.pardir, "contracts", "bootchain-v1.json")

# ELF constants, only the ones we index with.
ET_REL = 1
EM_68K = 4
SHT_PROGBITS = 1
SHT_SYMTAB = 2
SHT_RELA = 4
SHT_REL = 9
SHF_WRITE = 0x1
SHN_UNDEF = 0
SHN_LORESERVE = 0xff00
STB_GLOBAL = 1
STT_NOTYPE = 0
STT_OBJECT = 1
SHDR_SIZE = 40
SYMENT_SIZE = 16
RELOC_SLOT = 4                 # an R_68K_32 slot is 4 bytes wide -- overlap, not containment

ROOTDEV_SYM = "rootdev"
SWAPFILE_SYM = "swapfile"
ROOTFSTYPE_SYM = "rootfstype"


def die(msg, code=2):
    sys.stderr.write("%s: FATAL -- %s\n" % (WHOAMI, msg))
    sys.exit(code)


def refuse(msg, detail=""):
    sys.stderr.write("%s: REFUSED -- %s\n" % (WHOAMI, msg))
    if detail:
        for line in detail.rstrip("\n").split("\n"):
            sys.stderr.write("  %s\n" % line)
    sys.exit(1)


def u16(b, o):
    return struct.unpack_from(">H", b, o)[0]


def u32(b, o):
    return struct.unpack_from(">I", b, o)[0]


# ------------------------------------------------------------------ checksums --
# Reimplemented independently (not imported from kernel-rootdev-patch.py): the contract's
# conformance_protocol prescribes N independent implementations that AGREE on the vectors,
# not one module reaching sideways.  The selftest holds these to the contract vectors and to
# coreutils `sum -r`.

def sum_r(buf):
    """BSD `sum -r`: 16-bit rotate-then-add.  Returns (sum, 512-byte blocks).  What `sum -r`
    prints on the box and what updbootpart gate 5b pins /stand/unix against."""
    s = 0
    for c in buf:
        s = (s >> 1) + ((s & 1) << 15)
        s = (s + c) & 0xFFFF
    return s, (len(buf) + 511) // 512


def svr4_sum(buf):
    """SVR4 sum(1) per contract checksum.algorithm.  The & 0xFFFFFFFF is LOAD-BEARING: the C
    accumulator is a 32-bit unsigned long and WRAPS; Python ints do not."""
    s = sum(buf) & 0xFFFFFFFF
    t = (s >> 16) + (s & 0xFFFF)
    return (t >> 16) + (t & 0xFFFF)


# ------------------------------------------------------------------- contract --

def load_contract(path=CONTRACT):
    try:
        with open(path, "rb") as fh:
            return json.load(fh)
    except (OSError, ValueError) as e:
        die("cannot load the boot-chain contract\n"
            "  %s\n  %s\n"
            "  The rootdev rules live there; this tool refuses to run without them "
            "(fail closed)." % (path, e))


class Spec(object):
    """The rootdev rules, read out of the contract.  Nothing here is a literal."""

    def __init__(self, contract, path=CONTRACT):
        self.contract_path = path
        self.contract_version = contract.get("version")
        rd = self._req(contract, "rootdev", "the contract")
        p = self._req(rd, "patch", "contract section rootdev")

        self.L_BITSMINOR = self._req(rd, "L_BITSMINOR", "rootdev")
        self.L_MAXMIN = int(self._req(rd, "L_MAXMIN", "rootdev"), 16)

        # rootfstype: asserted, never written.  The tool reads the symbol name and the
        # stamp_needed flag from the contract so its behaviour follows the definition.
        rf = self._req(rd, "rootfstype", "rootdev")
        self.rootfstype_sym = self._req(rf, "symbol", "rootdev.rootfstype")
        self.rootfstype_stamp_needed = self._req(rf, "stamp_needed", "rootdev.rootfstype")

        a = self._req(p, "anchor", "rootdev.patch")
        self.anchor = self._req(a, "string", "rootdev.patch.anchor").encode("latin1")
        self.anchor_count = self._req(a, "occurrences_required", "rootdev.patch.anchor")
        self.forbidden = [s.encode("latin1") for s in a.get("forbidden_strings", [])]

        sd = self._req(p, "site_derivation", "rootdev.patch")
        self.rootdev_size = self._req(sd, "rootdev_size", "rootdev.patch.site_derivation")
        # the by_symbol block MUST exist -- a rule that lives in the tool instead of the
        # contract is how two rules start disagreeing.
        self.by_symbol = self._req(sd, "by_symbol", "rootdev.patch.site_derivation")

        bo = self._req(p, "bootobj", "rootdev.patch")
        self.bo_size_total = self._req(bo, "struct_size", "rootdev.patch.bootobj")
        f = self._req(bo, "fields", "rootdev.patch.bootobj")
        self.bo = {}
        for name in ("bo_fstype", "bo_name", "bo_flags", "bo_offset", "bo_size", "bo_vp"):
            fld = self._req(f, name, "rootdev.patch.bootobj.fields")
            self.bo[name] = (int(self._req(fld, "offset", name), 16),
                             self._req(fld, "size", name))

        me = self._req(p, "minor_encoding", "rootdev.patch")
        self.block_major = self._req(me, "block_major", "rootdev.patch.minor_encoding")

        dn = self._req(p, "device_name", "rootdev.patch")
        self._req(dn, "regex", "rootdev.patch.device_name")      # the anchor path's; card 0
        # by_symbol.cards: the fixed-order families (card 1 = the Z3660 behind the phantom
        # A3000 card 0).  The controller digit is ONE HEX digit; for card 0 hex == decimal.
        bc = self._req(self.by_symbol, "cards", "rootdev.patch.site_derivation.by_symbol")
        self.cards = tuple(self._req(bc, "values", "by_symbol.cards"))
        self.name_re = re.compile(self._req(bc, "regex", "by_symbol.cards").encode("latin1"))
        self.name_fmt = self._req(bc, "device_name_format", "by_symbol.cards")

        # rootdev.floppy: the 040/060 install floppy -- rootdev FD0P + bo_name /dev/fakeswap,
        # written from the sd-6 base only; bo_size never written.  Optional in the contract: absent = refused.
        fl = rd.get("floppy")
        self.floppy_rootdev = int(fl["rootdev"], 16) if fl else None
        self.floppy_bo_name = fl["bo_name"].encode("latin1") if fl else None

        cv = self._req(p, "convention", "rootdev.patch")
        self.def_root_slice = self._req(cv, "root_slice", "rootdev.patch.convention")
        self.def_swap_slice = self._req(cv, "swap_slice", "rootdev.patch.convention")
        self.card = self._req(cv, "card", "rootdev.patch.convention")

    @staticmethod
    def _req(d, key, where):
        if not isinstance(d, dict) or key not in d:
            die("the contract is incomplete: `%s` has no `%s`.\n"
                "  This tool reads every rule from contracts/bootchain-v1.json section\n"
                "  rootdev; a missing key means the definition and the implementation have\n"
                "  drifted apart.  Refusing to guess." % (where, key))
        return d[key]

    # -- the encoding, in both directions -------------------------------------
    def compose_minor(self, unit, slice_, card=None):
        card = self.card if card is None else card
        # C4-1 section 2.1: unit 0-2, card low bit 3, slice 4-6, card high bit 7
        return (card >> 1) << 7 | (slice_ << 4) | (card & 1) << 3 | unit

    def compose_dev(self, unit, slice_, card=None):
        return ((self.block_major << self.L_BITSMINOR)
                | (self.compose_minor(unit, slice_, card) & self.L_MAXMIN))

    def decode(self, dev):
        minor = dev & self.L_MAXMIN
        return dict(major=(dev >> self.L_BITSMINOR) & 0xFF, minor=minor,
                    unit=minor & 0o7, card=(minor >> 3) & 1 | (minor >> 6) & 2,
                    slice=(minor >> 4) & 0o7,
                    controller=8 * ((minor >> 3) & 1 | (minor >> 6) & 2) + (minor & 0o7))

    def device_name(self, unit, slice_, card=None):
        card = self.card if card is None else card
        return self.name_fmt % (8 * card + unit, slice_)

    def check_id(self, unit, root_slice, swap_slice, card=None):
        card = self.card if card is None else card
        bad = []
        if not isinstance(unit, int) or not 0 <= unit <= 7:
            bad.append("id %r is outside the SCSI target range 0-7 (sdunit is 3 bits)" % (unit,))
        if not 0 <= root_slice <= 7:
            bad.append("root slice %r is outside 0-7 (sdpart is 3 bits)" % (root_slice,))
        if not 0 <= swap_slice <= 7:
            bad.append("swap slice %r is outside 0-7 (sdpart is 3 bits)" % (swap_slice,))
        if card not in self.cards:
            bad.append("card %r is out of scope -- this line stamps cards %s only"
                       % (card, ", ".join(str(c) for c in self.cards)))
        return bad


# ---------------------------------------------------------------- ELF walk --

class Elf(object):
    """Just enough big-endian ELF32 to find a symbol's bytes and the relocations over them.
    Every structural surprise is a refusal, not an exception -- this runs as a gate."""

    def __init__(self, buf, path):
        self.buf = buf
        self.path = path
        if len(buf) < 52 or buf[:4] != b"\x7fELF":
            refuse("%s is not an ELF file" % path)
        if buf[4] != 1 or buf[5] != 2:
            refuse("%s is not big-endian ELF32 (EI_CLASS=%d EI_DATA=%d)" % (path, buf[4], buf[5]))
        self.e_type = u16(buf, 16)
        self.e_machine = u16(buf, 18)
        if self.e_machine != EM_68K:
            refuse("%s: e_machine %d, want %d (m68k)" % (path, self.e_machine, EM_68K))
        if self.e_type != ET_REL:
            refuse("%s: e_type 0x%x, want ET_REL (1) -- the 040/060 line is a relocatable link "
                   "that retains its .symtab; a brel (0xff00) has none and is located by anchor "
                   "with kernel-rootdev-patch.py instead" % (path, self.e_type))
        e_shoff = u32(buf, 32)
        e_shentsize, e_shnum, e_shstrndx = u16(buf, 46), u16(buf, 48), u16(buf, 50)
        if e_shentsize < SHDR_SIZE or e_shnum == 0:
            refuse("%s: unusable section header table (shentsize %d, shnum %d)"
                   % (path, e_shentsize, e_shnum))
        if not self._inside(e_shoff, e_shnum * e_shentsize):
            refuse("%s: section header table lies outside the file" % path)
        self.secs = []
        for i in range(e_shnum):
            b = e_shoff + i * e_shentsize
            self.secs.append(dict(idx=i, name=u32(buf, b), type=u32(buf, b + 4),
                                  flags=u32(buf, b + 8), addr=u32(buf, b + 12),
                                  off=u32(buf, b + 16), size=u32(buf, b + 20),
                                  link=u32(buf, b + 24), info=u32(buf, b + 28),
                                  entsize=u32(buf, b + 36)))
        if e_shstrndx >= e_shnum:
            refuse("%s: e_shstrndx %d out of range" % (path, e_shstrndx))
        self._name_sections(e_shstrndx)

    def _inside(self, off, size):
        return off >= 0 and size >= 0 and off + size <= len(self.buf)

    def _str(self, strtab, off):
        base = strtab["off"] + off
        if not self._inside(base, 1):
            refuse("%s: string offset %d outside the file" % (self.path, off))
        end = self.buf.find(b"\0", base)
        if end < 0:
            refuse("%s: unterminated string at %d" % (self.path, off))
        return self.buf[base:end].decode("latin1")

    def _name_sections(self, shstrndx):
        shstr = self.secs[shstrndx]
        if not self._inside(shstr["off"], shstr["size"]):
            refuse("%s: section name table lies outside the file" % self.path)
        for s in self.secs:
            s["nm"] = self._str(shstr, s["name"])

    def section(self, name):
        found = [s for s in self.secs if s["nm"] == name]
        if len(found) != 1:
            refuse("%s: expected exactly one `%s` section, found %d" % (self.path, name, len(found)))
        return found[0]

    def symtab(self):
        tabs = [s for s in self.secs if s["type"] == SHT_SYMTAB]
        if len(tabs) != 1:
            refuse("%s: expected exactly one SHT_SYMTAB, found %d -- the 040/060 line retains "
                   "its symbol table; an image without one cannot be located by symbol"
                   % (self.path, len(tabs)))
        st = tabs[0]
        ent = st["entsize"] or SYMENT_SIZE
        if ent < SYMENT_SIZE or not self._inside(st["off"], st["size"]):
            refuse("%s: unusable .symtab (entsize %d, size %d)" % (self.path, ent, st["size"]))
        if st["link"] >= len(self.secs):
            refuse("%s: .symtab sh_link %d out of range" % (self.path, st["link"]))
        return st, ent, self.secs[st["link"]]

    def global_defs(self, name):
        """Every GLOBAL, section-defined symbol with this name."""
        st, ent, strtab = self.symtab()
        out = []
        for i in range(st["size"] // ent):
            b = st["off"] + i * ent
            if self._str(strtab, u32(self.buf, b)) != name:
                continue
            st_info = self.buf[b + 12]
            st_shndx = u16(self.buf, b + 14)
            if (st_info >> 4) != STB_GLOBAL:
                continue
            if st_shndx == SHN_UNDEF or st_shndx >= SHN_LORESERVE:
                continue
            out.append(dict(value=u32(self.buf, b + 4), size=u32(self.buf, b + 8),
                            typ=st_info & 0xf, shndx=st_shndx))
        return out

    def reloc_hits(self, sec, ranges):
        """Relocation entries targeting `sec` whose 4-byte slot overlaps any (lo, hi) in
        `ranges` (section-relative addresses).  Overlap, not containment."""
        hits = []
        for s in self.secs:
            if s["type"] not in (SHT_RELA, SHT_REL):
                continue
            if s["info"] != sec["idx"]:
                continue
            ent = s["entsize"] or (12 if s["type"] == SHT_RELA else 8)
            if ent < 8 or not self._inside(s["off"], s["size"]):
                refuse("%s: unusable relocation section `%s`" % (self.path, s["nm"]))
            for i in range(s["size"] // ent):
                r_off = u32(self.buf, s["off"] + i * ent)
                for lo, hi in ranges:
                    if r_off < hi and r_off + RELOC_SLOT > lo:
                        hits.append((s["nm"], r_off))
                        break
        return hits


# ---------------------------------------------------------------- the image --

class SymbolKernel(object):
    """A symbol-located, contract-validated rootdev/swapfile/rootfstype site in a 040-line
    kernel.  Duck-compatible with build_table (identity/patched/rep/rootdev/...)."""

    def __init__(self, path, spec, data=None):
        self.path = path
        self.spec = spec
        self.rep = "et_rel"
        if data is None:
            try:
                with open(path, "rb") as fh:
                    data = fh.read()
            except OSError as e:
                die("cannot read %s: %s" % (path, e))
        self.data = data
        self._locate()
        self._decode()

    # -- locate the three symbols, cross-check the anchor, check relocations ---
    def _locate(self):
        sp = self.spec
        elf = Elf(self.data, self.path)
        self.elf = elf
        data = elf.section(".data")
        if data["type"] != SHT_PROGBITS or not (data["flags"] & SHF_WRITE):
            refuse("%s: `.data` is not a writable PROGBITS section (type %d flags 0x%x)"
                   % (self.path, data["type"], data["flags"]))
        self.data_sec = data

        def one(name, want_size):
            defs = elf.global_defs(name)
            if len(defs) != 1:
                refuse("%s: expected exactly one GLOBAL definition of `%s`, found %d"
                       % (self.path, name, len(defs)))
            d = defs[0]
            if d["shndx"] != data["idx"]:
                refuse("%s: `%s` is defined in section %d, not `.data` (%d)"
                       % (self.path, name, d["shndx"], data["idx"]))
            # size-0 NOTYPE (an undeclared .s global) or a properly declared OBJECT of the
            # expected size.  Anything else means the shape we reason about has changed.
            if not ((d["size"] == 0 and d["typ"] == STT_NOTYPE)
                    or (d["size"] == want_size and d["typ"] == STT_OBJECT)):
                refuse("%s: `%s` has st_type %d st_size %d -- expected size-0 NOTYPE or "
                       "size-%d OBJECT" % (self.path, name, d["typ"], d["size"], want_size))
            return d

        rootdev = one(ROOTDEV_SYM, sp.rootdev_size)
        swapfile = one(SWAPFILE_SYM, sp.bo_size_total)
        rootfstype = self._one_rootfstype(elf, data)

        def to_off(sym_value):
            return data["off"] + (sym_value - data["addr"])

        self.off_rootdev = to_off(rootdev["value"])
        self.off_swapfile = to_off(swapfile["value"])
        self.off_name = self.off_swapfile + sp.bo["bo_name"][0]
        self.off_rootfstype = to_off(rootfstype["value"])
        self.rootfstype_size = rootfstype["size"] or 1
        self.site_rootdev_addr = rootdev["value"]
        self.site_swapfile_addr = swapfile["value"]
        self.site_rootfstype_addr = rootfstype["value"]

        # every site must lie wholly inside .data.
        for lo, span, what in ((self.off_rootdev, sp.rootdev_size, "rootdev"),
                               (self.off_swapfile, sp.bo_size_total, "swapfile"),
                               (self.off_rootfstype, self.rootfstype_size, "rootfstype")):
            if not (data["off"] <= lo and lo + span <= data["off"] + data["size"]):
                refuse("%s: `%s` site 0x%x+%d is not wholly inside `.data`"
                       % (self.path, what, lo, span))
            if lo + span > len(self.data):
                refuse("%s: `%s` site runs past the end of the file" % (self.path, what))

        # the anchor is DEMOTED to a cross-check: it must occur exactly once, carry no
        # forbidden string, and land at exactly swapfile + bo_name.offset.
        d = self.data
        n = d.count(sp.anchor)
        fl_name = sp.floppy_bo_name
        if (n == 0 and fl_name is not None
                and d[self.off_rootdev:self.off_rootdev + sp.rootdev_size] == sp.floppy_rootdev.to_bytes(sp.rootdev_size, "big")):
            # contract rootdev.floppy: the cross-check on a FD0P kernel is the floppy pair itself -- no `/dev/dsk/c`
            # anchor at all, and the contract's bo_name exactly once, exactly at swapfile + bo_name.offset
            if d.count(fl_name) != 1 or d.find(fl_name) != self.off_name:
                refuse("FLOPPY: rootdev is FD0P but %r occurs %d time(s) (at 0x%x), not exactly once at bo_name 0x%x"
                       % (fl_name.decode("latin1"), d.count(fl_name), d.find(fl_name), self.off_name))
            for f in sp.forbidden:
                if f in d:
                    refuse("forbidden string %r is present" % f.decode("latin1"))
            self.anchor_off = self.off_name
        elif n != sp.anchor_count:
            refuse("anchor %r occurs %d time(s), the contract requires exactly %d"
                   % (sp.anchor.decode("latin1"), n, sp.anchor_count),
                   "the anchor is the cross-check on bo_name; more than one means this image\n"
                   "is not what the by_symbol rule describes")
        else:
            for f in sp.forbidden:
                if f in d:
                    refuse("forbidden string %r is present" % f.decode("latin1"))
            self.anchor_off = d.index(sp.anchor)
        if self.anchor_off != self.off_name:
            refuse("anchor %r is at 0x%x but the `swapfile` symbol puts bo_name at 0x%x"
                   % (sp.anchor.decode("latin1"), self.anchor_off, self.off_name),
                   "the symbol and the anchor cross-check disagree about where bo_name is -- "
                   "one of them is wrong and no byte may be written")

        # the relocation invariant, over the DISJOINT written ranges + rootfstype, expressed
        # in .data-section-relative addresses (r_offset is section-relative for .rela.data).
        base = data["addr"]
        rd_lo = self.site_rootdev_addr
        nm_lo = self.site_swapfile_addr + sp.bo["bo_name"][0]
        rf_lo = self.site_rootfstype_addr
        ranges = [(rd_lo - base, rd_lo - base + sp.rootdev_size),
                  (nm_lo - base, nm_lo - base + sp.bo["bo_name"][1]),
                  (rf_lo - base, rf_lo - base + self.rootfstype_size)]
        hits = elf.reloc_hits(data, ranges)
        if hits:
            refuse("%d relocation(s) overlap a written range or rootfstype" % len(hits),
                   "\n".join("  %s r_offset 0x%x" % h for h in hits) +
                   "\na relocated site is rewritten at load time -- stamping it would be theatre")
        self.reloc_scanned = self._count_data_relocs(data)

    def _one_rootfstype(self, elf, data):
        defs = elf.global_defs(self.spec.rootfstype_sym)
        if len(defs) != 1:
            refuse("%s: expected exactly one GLOBAL `%s`, found %d"
                   % (self.path, self.spec.rootfstype_sym, len(defs)))
        d = defs[0]
        if d["shndx"] != data["idx"]:
            refuse("%s: `%s` is not in `.data`" % (self.path, self.spec.rootfstype_sym))
        if not ((d["size"] == 0 and d["typ"] == STT_NOTYPE)
                or (d["size"] >= 1 and d["typ"] == STT_OBJECT)):
            refuse("%s: `%s` has st_type %d st_size %d -- expected a non-empty .data OBJECT "
                   "(a char[] fstype selector)"
                   % (self.path, self.spec.rootfstype_sym, d["typ"], d["size"]))
        return d

    def _count_data_relocs(self, sec):
        total = 0
        for s in self.elf.secs:
            if s["type"] in (SHT_RELA, SHT_REL) and s["info"] == sec["idx"]:
                ent = s["entsize"] or (12 if s["type"] == SHT_RELA else 8)
                total += s["size"] // ent
        return total

    # -- decode + coherence gate ----------------------------------------------
    def _decode(self):
        d, sp = self.data, self.spec
        self.rootdev = int.from_bytes(d[self.off_rootdev:self.off_rootdev + sp.rootdev_size], "big")
        self.dec = sp.decode(self.rootdev)
        self.bo_name_raw = d[self.off_name:self.off_name + sp.bo["bo_name"][1]]
        self.bo_size = u32(d, self.off_swapfile + sp.bo["bo_size"][0])
        self.rootfstype_raw = d[self.off_rootfstype:self.off_rootfstype + self.rootfstype_size]

        bad = []
        self.floppy = sp.floppy_rootdev is not None and self.rootdev == sp.floppy_rootdev
        if self.floppy:
            # contract rootdev.floppy: exactly FD0P + bo_name /dev/fakeswap (NUL-padded); the struct bootobj checks below
            # still apply (bo_size kept, bo_fstype empty, ...)
            name = self.bo_name_raw.split(b"\0", 1)[0]
            if name != sp.floppy_bo_name or self.bo_name_raw[len(name):].strip(b"\0"):
                bad.append("FLOPPY: rootdev is FD0P but swapfile.bo_name is %r, not the contract's %r (NUL-padded)"
                           % (self.bo_name_raw[:24], sp.floppy_bo_name))
        elif self.dec["major"] != sp.block_major:
            bad.append("rootdev major is %d, not the sd block major %d -- not an sd root"
                       % (self.dec["major"], sp.block_major))
        if not self.floppy and self.dec["card"] not in sp.cards:
            bad.append("rootdev names card %d; this line stamps cards %s only"
                       % (self.dec["card"], ", ".join(str(c) for c in sp.cards)))
        if not self.floppy and self.dec["slice"] != sp.def_root_slice:
            bad.append("rootdev slice %d, not the project root-slice convention %d"
                       % (self.dec["slice"], sp.def_root_slice))
        m = None if self.floppy else sp.name_re.match(self.bo_name_raw)
        if self.floppy:
            pass
        elif not m:
            bad.append("swapfile.bo_name %r does not match the contract device-name regex"
                       % self.bo_name_raw[:24])
        else:
            self.name_controller = int(m.group(1), 16)
            self.name_slice = int(m.group(2))
            tail = self.bo_name_raw[m.end():]
            if tail.strip(b"\0"):
                bad.append("the %d-byte bo_name field is not NUL-padded past the string "
                           "(%d non-NUL bytes follow)"
                           % (sp.bo["bo_name"][1], len(tail.strip(b"\0"))))
            if self.name_controller != self.dec["controller"]:
                bad.append("CONSISTENCY: bo_name says controller c%x but rootdev's minor says "
                           "c%x -- the two fields disagree about the id"
                           % (self.name_controller, self.dec["controller"]))
            if self.name_slice != sp.def_swap_slice:
                bad.append("swap slice %d, not the project swap-slice convention %d"
                           % (self.name_slice, sp.def_swap_slice))
        fstype_off, fstype_len = sp.bo["bo_fstype"]
        if d[self.off_swapfile + fstype_off:self.off_swapfile + fstype_off + fstype_len].strip(b"\0"):
            bad.append("bo_fstype is not empty -- every measured kernel leaves it NUL")
        for fname in ("bo_flags", "bo_offset", "bo_vp"):
            off = sp.bo[fname][0]
            if u32(d, self.off_swapfile + off) != 0:
                bad.append("%s is non-zero as stored -- unexpected struct bootobj state" % fname)
        if self.bo_size == 0:
            bad.append("bo_size (SWAPLEN) is 0 -- this swapfile carries no length")
        # rootfstype: asserted empty (contract rootdev.rootfstype).  The 040/060 line is
        # UFS-root by empty-selector iteration; a non-empty value would force a wrong fstype.
        if sp.rootfstype_stamp_needed:
            bad.append("contract says rootfstype IS stamped on this line, but this tool only "
                       "asserts it -- the definition and the implementation have drifted")
        if self.rootfstype_raw.strip(b"\0"):
            bad.append("rootfstype is NON-empty (%r) -- the 040/060 line mounts ufs by empty "
                       "selector; a forced fstype is refused" % self.rootfstype_raw.split(b"\0", 1)[0])

        if bad:
            refuse("%s fails the by_symbol coherence gate" % self.path,
                   "\n".join("- " + b for b in bad))

    # -- derived facts ---------------------------------------------------------
    @property
    def swap_device(self):
        return self.bo_name_raw.split(b"\0", 1)[0].decode("latin1")

    @property
    def root_device(self):
        if self.floppy:
            return "fd0 (FD0P)"
        return self.spec.device_name(self.dec["unit"], self.dec["slice"], self.dec["card"])

    def identity(self):
        s, blocks = sum_r(self.data)
        return dict(size=len(self.data), sum_r=s, sum_r_blocks=blocks,
                    svr4_sum=svr4_sum(self.data),
                    md5=hashlib.md5(self.data).hexdigest(),
                    sha256=hashlib.sha256(self.data).hexdigest())

    def patched(self, unit, root_slice, swap_slice, card=None):
        """The image bytes with the destination written in.  rootdev (4 B) + bo_name (128 B
        field).  rootfstype, bo_size and everything else are untouched."""
        sp = self.spec
        if self.floppy:
            refuse("%s carries FD0P (a floppy kernel): an id stamp is cut from the sd-6 base, never from a variant"
                   % self.path)
        bad = sp.check_id(unit, root_slice, swap_slice, card)
        if bad:
            refuse("destination outside the valid encoding", "\n".join("- " + b for b in bad))
        out = bytearray(self.data)
        dev = sp.compose_dev(unit, root_slice, card)
        out[self.off_rootdev:self.off_rootdev + sp.rootdev_size] = dev.to_bytes(sp.rootdev_size, "big")
        field = sp.bo["bo_name"][1]
        name = sp.device_name(unit, swap_slice, card).encode("latin1")
        if len(name) + 1 > field:
            refuse("swap device name %r does not fit the %d-byte bo_name field" % (name, field))
        out[self.off_name:self.off_name + field] = name + b"\0" * (field - len(name))
        return bytes(out), dev


# ------------------------------------------------------------------ commands --

    def patched_floppy(self):
        """contract rootdev.floppy: rootdev <- FD0P, bo_name <- /dev/fakeswap; from the UNSTAMPED sd-6 base only."""
        sp = self.spec
        if sp.floppy_rootdev is None:
            refuse("the contract has no rootdev.floppy section -- a floppy root is not defined")
        if self.floppy:
            refuse("%s already carries FD0P" % self.path)
        base = sp.compose_dev(6, sp.def_root_slice, 0)
        if self.rootdev != base or self.swap_device != sp.device_name(6, sp.def_swap_slice, 0):
            refuse("%s is not the unstamped sd-6 base (rootdev 0x%08x %s, swap %s): floppy kernels are stamped "
                   "from the base, never from a variant" % (self.path, self.rootdev, self.root_device, self.swap_device))
        field = sp.bo["bo_name"][1]
        out = bytearray(self.data)
        out[self.off_rootdev:self.off_rootdev + sp.rootdev_size] = sp.floppy_rootdev.to_bytes(sp.rootdev_size, "big")
        out[self.off_name:self.off_name + field] = sp.floppy_bo_name + b"\0" * (field - len(sp.floppy_bo_name))
        return bytes(out), sp.floppy_rootdev


def describe(img):
    sp = img.spec
    ident = img.identity()
    print("%s: %s" % (WHOAMI, img.path))
    print("  representation : et_rel (e_type 1), %d bytes" % ident["size"])
    print("  located BY SYMBOL (.symtab); anchor %r is the cross-check"
          % sp.anchor.decode("latin1"))
    print("  rootdev        : sym -> file 0x%x  = 0x%08x  major=%d minor=%d -> id %d card %d slice %d (%s)"
          % (img.off_rootdev, img.rootdev, img.dec["major"], img.dec["minor"],
             img.dec["unit"], img.dec["card"], img.dec["slice"], img.root_device))
    print("  swapfile       : sym -> file 0x%x  bo_name %r (anchor@0x%x)  bo_size %d blocks (NEVER stamped)"
          % (img.off_swapfile, img.swap_device, img.anchor_off, img.bo_size))
    print("  rootfstype     : sym -> file 0x%x  %d bytes  %s (ASSERTED empty -> ufs; NEVER stamped)"
          % (img.off_rootfstype, img.rootfstype_size,
             "empty" if not img.rootfstype_raw.strip(b"\0") else "NON-EMPTY"))
    print("  relocations    : %d over .data scanned, 0 overlap the written ranges or rootfstype"
          % img.reloc_scanned)
    print("  identity       : sum -r %05d %d   svr4-sum 0x%04x   md5 %s"
          % (ident["sum_r"], ident["sum_r_blocks"], ident["svr4_sum"], ident["md5"]))


def cmd_show(args, spec):
    img = SymbolKernel(args.kernel, spec)
    describe(img)
    print("%s: PASS  the image satisfies every by_symbol precondition (contract v%s)"
          % (WHOAMI, spec.contract_version))
    return 0


def cmd_verify(args, spec):
    img = SymbolKernel(args.kernel, spec)
    if args.floppy or img.floppy:
        if not (args.floppy and img.floppy):
            refuse("%s: %s" % (args.kernel, "carries FD0P -- verify it with --floppy" if img.floppy
                               else "--floppy asked, but the kernel carries rootdev 0x%08x (%s)"
                               % (img.rootdev, img.root_device)))
        ident = img.identity()
        if args.expect_sum_r is not None and ident["sum_r"] != args.expect_sum_r:
            refuse("sum -r is %d, expected %d -- not the same bytes" % (ident["sum_r"], args.expect_sum_r))
        print("%s: PASS  %s is a FLOPPY kernel: rootdev 0x%08x (fd0, FD0P), swap %s, bo_size %d (untouched), "
              "rootfstype empty (ufs)" % (WHOAMI, args.kernel, img.rootdev, img.swap_device, img.bo_size))
        print("%s: PASS  identity sum -r %05d %d   svr4-sum 0x%04x   md5 %s"
              % (WHOAMI, ident["sum_r"], ident["sum_r_blocks"], ident["svr4_sum"], ident["md5"]))
        return 0
    if args.id is None:
        die("verify needs --id (or --floppy)")
    bad = spec.check_id(args.id, args.root_slice, args.swap_slice, args.card)
    if bad:
        refuse("destination outside the valid encoding", "\n".join("- " + b for b in bad))
    want_dev = spec.compose_dev(args.id, args.root_slice, args.card)
    want_swap = spec.device_name(args.id, args.swap_slice, args.card)
    problems = []
    if img.rootdev != want_dev:
        problems.append("rootdev is 0x%08x (%s), expected 0x%08x (%s)"
                        % (img.rootdev, img.root_device, want_dev,
                           spec.device_name(args.id, args.root_slice, args.card)))
    if img.swap_device != want_swap:
        problems.append("swapfile.bo_name is %r, expected %r" % (img.swap_device, want_swap))
    if img.rootfstype_raw.strip(b"\0"):
        problems.append("rootfstype is non-empty -- the 040/060 line mounts ufs by empty selector")
    ident = img.identity()
    if args.expect_sum_r is not None and ident["sum_r"] != args.expect_sum_r:
        problems.append("sum -r is %d, expected %d -- not the same bytes"
                        % (ident["sum_r"], args.expect_sum_r))
    if problems:
        refuse("%s is not the kernel for destination id %d" % (args.kernel, args.id),
               "\n".join("- " + p for p in problems) +
               "\nA kernel whose rootdev does not name the disk it is installed on\n"
               "PANICs at s5mountroot (VOP_OPEN error 6 / vfs_mountroot errno 30).")
    print("%s: PASS  %s carries id %d  rootdev 0x%08x (%s), swap %s, rootfstype empty (ufs)"
          % (WHOAMI, args.kernel, args.id, img.rootdev, img.root_device, img.swap_device))
    print("%s: PASS  identity sum -r %05d %d   svr4-sum 0x%04x   md5 %s"
          % (WHOAMI, ident["sum_r"], ident["sum_r_blocks"], ident["svr4_sum"], ident["md5"]))
    return 0


def cmd_stamp(args, spec):
    img = SymbolKernel(args.kernel, spec)         # the coherence gate runs here (before write)
    if args.floppy:
        if args.id is not None or args.expect_current_id is not None:
            die("--floppy takes no --id / --expect-current-id: the input must be the unstamped sd-6 base")
        out, dev = img.patched_floppy()
    elif args.id is None:
        die("stamp needs --id (or --floppy)")
    if not args.floppy and args.expect_current_id is not None:
        want = spec.compose_dev(args.expect_current_id, img.dec["slice"])
        if img.rootdev != want:
            refuse("--expect-current-id %d: the input carries rootdev 0x%08x (%s), not 0x%08x"
                   % (args.expect_current_id, img.rootdev, img.root_device, want),
                   "every variant must be cut from the pristine base, never from another\n"
                   "variant -- this guard makes 'is this the base?' fail-closed")
    if not args.floppy:
        bad = spec.check_id(args.id, args.root_slice, args.swap_slice, args.card)
        if bad:
            refuse("destination outside the valid encoding", "\n".join("- " + b for b in bad))
        out, dev = img.patched(args.id, args.root_slice, args.swap_slice, args.card)
    dest = args.out or args.kernel
    if args.out and os.path.exists(args.out) and not args.force:
        die("%s already exists (use --force to overwrite)" % args.out)

    tmp = dest + ".rootdev-stamp.tmp"
    try:
        with open(tmp, "wb") as fh:
            fh.write(out)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, dest)
    except OSError as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        die("cannot write %s: %s" % (dest, e))

    # Re-read from disk and compare WHOLE.  The only bytes that may differ are the two
    # written ranges; a truncating/padding/rewriting bug fails here even if the fields read
    # back right.  Then re-locate + re-validate the target id is carried.
    try:
        with open(dest, "rb") as fh:
            back = fh.read()
    except OSError as e:
        die("cannot re-read %s: %s" % (dest, e))
    problems = []
    if len(back) != len(img.data):
        problems.append("file size changed: %d -> %d" % (len(img.data), len(back)))
    else:
        rd = (img.off_rootdev, img.off_rootdev + spec.rootdev_size)
        nm = (img.off_name, img.off_name + spec.bo["bo_name"][1])
        stray = [i for i in range(len(back))
                 if img.data[i] != back[i]
                 and not (rd[0] <= i < rd[1] or nm[0] <= i < nm[1])]
        if stray:
            problems.append("%d byte(s) outside the two written ranges changed: %s%s"
                            % (len(stray), ", ".join("0x%x" % s for s in stray[:8]),
                               " ..." if len(stray) > 8 else ""))
    if problems:
        refuse("the write did not land as intended in %s" % dest, "\n".join("  " + p for p in problems))
    back_img = SymbolKernel(dest, spec, data=back)
    want_swap = (spec.floppy_bo_name.decode("latin1") if args.floppy
                 else spec.device_name(args.id, args.swap_slice, args.card))
    if back_img.rootdev != dev or back_img.swap_device != want_swap or back_img.floppy != bool(args.floppy):
        refuse("read-back mismatch in %s: rootdev 0x%08x swap %s"
               % (dest, back_img.rootdev, back_img.swap_device))
    if back_img.rootfstype_raw.strip(b"\0"):
        refuse("read-back: rootfstype was disturbed in %s" % dest)

    changed = sum(1 for a, b in zip(img.data, out) if a != b)
    s, blocks = sum_r(out)
    print("%s: stamped %s -> %s   (BY SYMBOL)" % (WHOAMI, args.kernel, dest))
    if args.floppy:
        print("  FLOPPY (contract rootdev.floppy) -> rootdev 0x%08x (fd0, FD0P), swap %s   [%d byte(s) changed]"
              % (dev, want_swap, changed))
    else:
        print("  card %d id %d -> rootdev 0x%08x (%s), swap %s   [%d byte(s) changed]"
              % (args.card, args.id, dev, spec.device_name(args.id, args.root_slice, args.card),
                 spec.device_name(args.id, args.swap_slice, args.card), changed))
    print("  was: rootdev 0x%08x (%s), swap %s" % (img.rootdev, img.root_device, img.swap_device))
    print("  rootfstype untouched (empty -> ufs);  bo_size %d blocks untouched" % img.bo_size)
    print("  sum -r %05d %d   svr4-sum 0x%04x   md5 %s   sha256 %s"
          % (s, blocks, svr4_sum(out), hashlib.md5(out).hexdigest(),
             hashlib.sha256(out).hexdigest()[:16]))
    print("  NOTE: the boot-slice iblk checksum and any manifest/KSUM_R pin over this kernel "
          "move with it -- reframe and re-key from the per-id table, never by re-checksumming "
          "on the box.")
    return 0


def parse_ids(text):
    out = []
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part[1:]:
            a, b = part.split("-", 1)
            try:
                lo, hi = int(a), int(b)
            except ValueError:
                die("--ids: %r is not a range" % part)
            if hi < lo:
                die("--ids: range %r is inverted" % part)
            out.extend(range(lo, hi + 1))
        else:
            try:
                out.append(int(part))
            except ValueError:
                die("--ids: %r is not an id" % part)
    if not out:
        die("--ids selected nothing")
    seen, uniq = set(), []
    for i in out:
        if i not in seen:
            seen.add(i)
            uniq.append(i)
    return uniq


def build_table(img, spec, ids, root_slice, swap_slice, card=None):
    card = spec.card if card is None else card
    base = img.identity()
    rows = []
    for i in ids:
        out, dev = img.patched(i, root_slice, swap_slice, card)
        s, blocks = sum_r(out)
        rows.append(dict(id=i, rootdev="0x%08x" % dev,
                         root_device=spec.device_name(i, root_slice, card),
                         swap_device=spec.device_name(i, swap_slice, card),
                         size=len(out), sum_r=s, sum_r_blocks=blocks,
                         svr4_sum=svr4_sum(out), svr4_sum_hex="0x%04x" % svr4_sum(out),
                         md5=hashlib.md5(out).hexdigest(),
                         sha256=hashlib.sha256(out).hexdigest()))
    return dict(table="amix-rootdev-patch-table", schema_version=1,
                contract="amix-bootchain", contract_version=spec.contract_version,
                located_by="symbol (.symtab); 040/060 line",
                generated_by="amix kernel/k30 tools/kernel-rootdev-stamp.py",
                base=dict(file=os.path.basename(img.path), representation=img.rep,
                          rootdev="0x%08x" % img.rootdev, root_device=img.root_device,
                          swap_device=img.swap_device, bo_size=img.bo_size, **base),
                convention=dict(root_slice=root_slice, swap_slice=swap_slice, card=card),
                rows=rows)


def render_table(tab, fmt):
    if fmt == "json":
        return json.dumps(tab, indent=2, sort_keys=False) + "\n"
    if fmt == "pkginfo":
        lines = ["# %s v%d -- generated by %s (located by %s)"
                 % (tab["table"], tab["schema_version"], tab["generated_by"], tab["located_by"]),
                 "# base %s (%s), sum -r %d, md5 %s"
                 % (tab["base"]["file"], tab["base"]["representation"],
                    tab["base"]["sum_r"], tab["base"]["md5"]),
                 "# root slice %d, swap slice %d, card %d"
                 % (tab["convention"]["root_slice"], tab["convention"]["swap_slice"],
                    tab["convention"]["card"]),
                 "ROOTDEV_IDS=%s" % " ".join(str(r["id"]) for r in tab["rows"])]
        for r in tab["rows"]:
            lines.append("ROOTDEV_%d=%s" % (r["id"], r["rootdev"]))
            lines.append("KSUM_R_%d=%d" % (r["id"], r["sum_r"]))
            lines.append("KSVR4_%d=%d" % (r["id"], r["svr4_sum"]))
            lines.append("KMD5_%d=%s" % (r["id"], r["md5"]))
            lines.append("KSIZE_%d=%d" % (r["id"], r["size"]))
        return "\n".join(lines) + "\n"
    out = ["# per-id expected sums for %s (%s, by symbol), root s%d / swap s%d, card %d"
           % (tab["base"]["file"], tab["base"]["representation"],
              tab["convention"]["root_slice"], tab["convention"]["swap_slice"],
              tab["convention"]["card"]),
           "# BUILD ARTIFACT -- per driver mix and per cputype; a different build gives "
           "different sums.",
           "| id | rootdev | swap bo_name | sum -r | svr4-sum | md5 (12) |",
           "|---:|---|---|---:|---|---|"]
    for r in tab["rows"]:
        out.append("| %d | `%s` | `%s` | %d | `%s` | `%s` |"
                   % (r["id"], r["rootdev"], r["swap_device"], r["sum_r"],
                      r["svr4_sum_hex"], r["md5"][:12]))
    return "\n".join(out) + "\n"


def cmd_table(args, spec):
    img = SymbolKernel(args.kernel, spec)
    if img.floppy:
        refuse("%s carries FD0P: a floppy has no SCSI id, so there is no per-id table (contract rootdev.floppy)"
               % args.kernel)
    ids = parse_ids(args.ids)
    bad = []
    for i in ids:
        bad += ["id %d: %s" % (i, b)
                for b in spec.check_id(i, args.root_slice, args.swap_slice, args.card)]
    if bad:
        refuse("the requested id set is outside the valid encoding", "\n".join("- " + b for b in bad))
    tab = build_table(img, spec, ids, args.root_slice, args.swap_slice, args.card)
    text = render_table(tab, args.format)
    if args.out:
        if os.path.exists(args.out) and not args.force:
            die("%s already exists (use --force to overwrite)" % args.out)
        try:
            with open(args.out, "w") as fh:
                fh.write(text)
        except OSError as e:
            die("cannot write %s: %s" % (args.out, e))
        sys.stderr.write("%s: wrote %d row(s) -> %s\n" % (WHOAMI, len(tab["rows"]), args.out))
    else:
        sys.stdout.write(text)
    return 0


# ------------------------------------------------------------------ selftest --
# Hermetic: every fixture is a synthetic big-endian ELF32 ET_REL built here, so the suite
# needs no kernel, no toolchain and no work/ artifact.  It holds the by_symbol location, the
# coherence gate and its refusals, the rootfstype assertion, the both-ends write discipline,
# and the per-id sum determinism.
import subprocess
import tempfile


def _mkelf(rootdev=0x00480016, swap_name=b"/dev/dsk/c6d0s2", bo_size=61440,
           bo_fstype=b"", bo_flags=0, bo_offset=0, bo_vp=0,
           rootfstype=b"\0" * 15, rootfstype_size=15, rootfstype_type=STT_OBJECT,
           rootdev_size=4, rootdev_type=STT_OBJECT, swapfile_size=160, swapfile_type=STT_OBJECT,
           rootdev_bind=STB_GLOBAL, rootdev_shndx=None, drop_swapfile=False,
           drop_rootfstype=False, drop_symtab=False, dup_rootdev=False,
           reloc_at=None, gap_between=16, e_type=ET_REL, e_machine=EM_68K, little=False,
           second_anchor=False, no_anchor=False, forbidden_rdsk=False, cputype=None):
    """Build a minimal ET_REL: .text, .data (rootfstype, then rootdev, a gap, then swapfile),
    optional .rela.data, .symtab/.strtab.  Symbol values are .data-relative offsets.
    cputype=N adds the 040-line `cputype`/`pcr_boot` pair (size-0 NOTYPE, pcr_boot at +4
    holding the unwritten sentinel) in the tail after swapfile -- for check-chain-stamp.py."""
    endian = "<" if little else ">"
    names = [b"", b".text", b".data", b".shstrtab", b".symtab", b".strtab", b".rela.data"]
    shstr = b"\0".join(names) + b"\0"
    noff = {}
    p = 0
    for n in names:
        noff[n] = p
        p += len(n) + 1

    # .data layout: [pad][rootfstype][pad2][rootdev][gap][swapfile]
    rf_addr = 0x10
    rd_addr = rf_addr + max(rootfstype_size, 16) + 0x10
    sw_addr = rd_addr + rootdev_size + gap_between
    data = bytearray(sw_addr + 160 + 16)
    # rootfstype
    data[rf_addr:rf_addr + len(rootfstype)] = rootfstype
    # rootdev
    struct.pack_into(endian + "I", data, rd_addr, rootdev & 0xffffffff)
    # swapfile struct bootobj
    data[sw_addr + 0x00:sw_addr + 0x00 + len(bo_fstype)] = bo_fstype     # bo_fstype[16]
    nm = swap_name if not no_anchor else b"/dev/zzz/x0"
    data[sw_addr + 0x10:sw_addr + 0x10 + len(nm)] = nm                   # bo_name[128]
    struct.pack_into(endian + "I", data, sw_addr + 0x90, bo_flags & 0xffffffff)
    struct.pack_into(endian + "I", data, sw_addr + 0x94, bo_offset & 0xffffffff)
    struct.pack_into(endian + "I", data, sw_addr + 0x98, bo_size & 0xffffffff)
    struct.pack_into(endian + "I", data, sw_addr + 0x9c, bo_vp & 0xffffffff)
    if second_anchor:
        data[sw_addr + 0x10 + 0x40:sw_addr + 0x10 + 0x40 + 15] = b"/dev/dsk/c3d0s1"
    if forbidden_rdsk:
        data[0:16] = b"/dev/rdsk/c0d0s0"
    ct_addr = sw_addr + 160
    if cputype is not None:
        struct.pack_into(endian + "II", data, ct_addr, cputype & 0xffffffff, 0xFFFFFFFF)
    text = b"\x4e\x71" * 8

    symnames = [b"", ROOTDEV_SYM.encode(), SWAPFILE_SYM.encode(), ROOTFSTYPE_SYM.encode(),
                b"cputype", b"pcr_boot"]
    strtab = b"\0".join(symnames) + b"\0"
    soff = {}
    p = 0
    for n in symnames:
        soff[n] = p
        p += len(n) + 1

    DATA_IDX = 2
    syms = [(0, 0, 0, 0, 0, 0)]
    rd_shndx = DATA_IDX if rootdev_shndx is None else rootdev_shndx
    syms.append((soff[ROOTDEV_SYM.encode()], rd_addr, rootdev_size,
                 (rootdev_bind << 4) | rootdev_type, 0, rd_shndx))
    if dup_rootdev:
        syms.append((soff[ROOTDEV_SYM.encode()], rd_addr, rootdev_size,
                     (STB_GLOBAL << 4) | rootdev_type, 0, DATA_IDX))
    if not drop_swapfile:
        syms.append((soff[SWAPFILE_SYM.encode()], sw_addr, swapfile_size,
                     (STB_GLOBAL << 4) | swapfile_type, 0, DATA_IDX))
    if not drop_rootfstype:
        syms.append((soff[ROOTFSTYPE_SYM.encode()], rf_addr, rootfstype_size,
                     (STB_GLOBAL << 4) | rootfstype_type, 0, DATA_IDX))
    if cputype is not None:
        syms.append((soff[b"cputype"], ct_addr, 0, (STB_GLOBAL << 4) | STT_NOTYPE, 0, DATA_IDX))
        syms.append((soff[b"pcr_boot"], ct_addr + 4, 0, (STB_GLOBAL << 4) | STT_NOTYPE, 0,
                     DATA_IDX))
    symtab = b"".join(struct.pack(endian + "IIIBBH", *s) for s in syms)

    rela = b""
    if reloc_at is not None:
        rela = struct.pack(endian + "IIi", reloc_at, (1 << 8) | 1, 0)

    parts = []
    off = 52

    def place(blob):
        nonlocal off
        o = off
        parts.append(blob)
        off += len(blob)
        return o
    t_off = place(bytes(text))
    d_off = place(bytes(data))
    ss_off = place(shstr)
    sy_off = place(symtab)
    st_off = place(strtab)
    re_off = place(rela) if rela else 0

    sects = [
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
        (noff[b".text"], SHT_PROGBITS, 0x2 | 0x4, 0, t_off, len(text), 0, 0, 4, 0),
        (noff[b".data"], SHT_PROGBITS, 0x2 | SHF_WRITE, 0, d_off, len(data), 0, 0, 4, 0),
        (noff[b".shstrtab"], 3, 0, 0, ss_off, len(shstr), 0, 0, 1, 0),
    ]
    SHSTR_IDX = 3
    SYMTAB_IDX = 4
    if not drop_symtab:
        sects.append((noff[b".symtab"], SHT_SYMTAB, 0, 0, sy_off, len(symtab),
                      SYMTAB_IDX + 1, 1, 4, SYMENT_SIZE))
        sects.append((noff[b".strtab"], 3, 0, 0, st_off, len(strtab), 0, 0, 1, 0))
    if rela:
        sects.append((noff[b".rela.data"], SHT_RELA, 0, 0, re_off, len(rela),
                      SYMTAB_IDX, DATA_IDX, 4, 12))

    shoff = off
    ident = b"\x7fELF" + bytes([1, 1 if little else 2, 1, 0]) + b"\0" * 8
    eh = ident + struct.pack(endian + "HHIIIIIHHHHHH", e_type, e_machine, 1, 0, 0, shoff,
                             0, 52, 0, 0, SHDR_SIZE, len(sects), SHSTR_IDX)
    sh = b"".join(struct.pack(endian + "IIIIIIIIII", *s) for s in sects)
    return eh + b"".join(parts) + sh


def _run(args, cwd=None):
    me = os.path.abspath(__file__)
    r = subprocess.run([sys.executable, me] + args, capture_output=True, text=True, cwd=cwd)
    return r.returncode, r.stdout + r.stderr


def selftest():
    fails = []
    n = 0
    spec = Spec(load_contract(), CONTRACT)

    def case(label, want_rc, args, blob=None, check=None):
        nonlocal n
        n += 1
        with tempfile.TemporaryDirectory(prefix="rootdev-st-") as td:
            p = os.path.join(td, "unix-040")
            if blob is not None:
                with open(p, "wb") as fh:
                    fh.write(blob)
            a = [x.replace("@", p) for x in args]
            rc, out = _run(a)
            ok = rc == want_rc
            why = "" if ok else "rc=%d want %d" % (rc, want_rc)
            if ok and check is not None:
                msg = check(p, out)
                if msg:
                    ok, why = False, msg
            print("  %-60s %s%s" % (label, "ok" if ok else "FAIL", (" -- " + why) if why else ""))
            if not ok:
                fails.append(label)
                for line in out.strip().split("\n")[-6:]:
                    print("      | %s" % line)

    print("%s --selftest: by_symbol location, the coherence gate, the write discipline" % WHOAMI)
    print()
    print("the clean fixture and the site")
    base = _mkelf()

    def only_ranges_changed(want_id, want_root_slice=1, want_swap_slice=2, ref=None):
        # `ref` is the exact pre-stamp input; defaults to the clean base.  It matters for the
        # reloc-clear case, whose input carries an extra .rela.data section and so is longer.
        def check(p, out):
            src = base if ref is None else ref
            got = open(p, "rb").read()
            if len(got) != len(src):
                return "size changed %d -> %d" % (len(src), len(got))
            img0 = SymbolKernel("src", spec, data=src)
            rd = (img0.off_rootdev, img0.off_rootdev + spec.rootdev_size)
            nm = (img0.off_name, img0.off_name + spec.bo["bo_name"][1])
            stray = [i for i in range(len(src))
                     if src[i] != got[i] and not (rd[0] <= i < rd[1] or nm[0] <= i < nm[1])]
            if stray:
                return "bytes outside the two ranges changed: %s" % stray[:8]
            img1 = SymbolKernel("out", spec, data=got)
            if img1.rootdev != spec.compose_dev(want_id, want_root_slice):
                return "rootdev not the target id"
            if img1.swap_device != spec.device_name(want_id, want_swap_slice):
                return "swap device not the target"
            if img1.rootfstype_raw.strip(b"\0"):
                return "rootfstype disturbed"
            return ""
        return check

    case("show accepts the clean fixture, writes nothing", 0, ["show", "@"], blob=base,
         check=lambda p, o: "" if open(p, "rb").read() == base else "show wrote to the file")
    case("stamp id 3 writes ONLY rootdev + bo_name", 0,
         ["stamp", "@", "--id", "3"], blob=base, check=only_ranges_changed(3))
    case("stamp id 6 on the id-6 base is still a proved, verified write", 0,
         ["stamp", "@", "--id", "6"], blob=base, check=only_ranges_changed(6))
    case("stamp -o leaves the input untouched", 0,
         ["stamp", "@", "--id", "0", "-o", "@.out"], blob=base,
         check=lambda p, o: "" if open(p, "rb").read() == base else "input was modified")
    case("stamp --expect-current-id 6 passes on the id-6 base", 0,
         ["stamp", "@", "--id", "2", "--expect-current-id", "6"], blob=base,
         check=only_ranges_changed(2))

    def card1_check(want_id, src):
        def check(path, _o):
            got = open(path, "rb").read()
            img1 = SymbolKernel("out", spec, data=got)
            if img1.rootdev != spec.compose_dev(want_id, 1, 1):
                return "rootdev 0x%08x is not card 1 id %d" % (img1.rootdev, want_id)
            if img1.swap_device != "/dev/dsk/c%xd0s2" % (8 | want_id):
                return "swap device %r is not the hex card-1 node" % img1.swap_device
            if img1.root_device != "/dev/dsk/c%xd0s1" % (8 | want_id):
                return "root device %r is not the hex card-1 node" % img1.root_device
            if sum(1 for a, b in zip(src, got) if a != b) > 2:
                return "more than the rootdev byte and the controller digit changed"
            return ""
        return check

    card1 = _mkelf(rootdev=0x0048001e, swap_name=b"/dev/dsk/ced0s2")
    case("card 1 id 6 (ced0s1) is accepted as input -- the fixed-order families", 0,
         ["show", "@"], blob=card1)
    case("stamp --card 1 --id 6 writes rootdev 0x0048001e + ced0s2 (2 bytes vs the id-6 base)", 0,
         ["stamp", "@", "--id", "6", "--card", "1"], blob=base, check=card1_check(6, base))
    print("the floppy pair (contract rootdev.floppy)")
    fd0 = spec.floppy_rootdev; fdn = spec.floppy_bo_name

    def floppy_check(path, _o):
        got = open(path, "rb").read()
        if len(got) != len(base):
            return "size changed"
        img0 = SymbolKernel("src", spec, data=base)
        rd = (img0.off_rootdev, img0.off_rootdev + spec.rootdev_size)
        nm = (img0.off_name, img0.off_name + spec.bo["bo_name"][1])
        stray = [i for i in range(len(base)) if base[i] != got[i] and not (rd[0] <= i < rd[1] or nm[0] <= i < nm[1])]
        if stray:
            return "bytes outside the two ranges changed: %s" % stray[:8]
        img1 = SymbolKernel("out", spec, data=got)
        if not img1.floppy or img1.rootdev != fd0 or img1.swap_device != fdn.decode():
            return "not the floppy pair: rootdev 0x%08x swap %s" % (img1.rootdev, img1.swap_device)
        if img1.bo_size != img0.bo_size:
            return "bo_size was written (%d -> %d)" % (img0.bo_size, img1.bo_size)
        return ""
    floppy = _mkelf(rootdev=fd0, swap_name=fdn)
    case("stamp --floppy from the sd-6 base writes ONLY rootdev + bo_name (bo_size kept)", 0,
         ["stamp", "@", "--floppy"], blob=base, check=floppy_check)
    case("verify --floppy accepts the floppy pair", 0, ["verify", "@", "--floppy"], blob=floppy)
    case("show reads a floppy kernel", 0, ["show", "@"], blob=floppy)
    case("REFUSED: stamp --floppy from an id-5 variant (base only)", 1,
         ["stamp", "@", "--floppy"], blob=_mkelf(rootdev=0x00480015, swap_name=b"/dev/dsk/c5d0s2"))
    case("REFUSED: stamp --floppy on a floppy kernel", 1, ["stamp", "@", "--floppy"], blob=floppy)
    case("REFUSED: an id stamp cut from a floppy kernel", 1, ["stamp", "@", "--id", "6"], blob=floppy)
    case("REFUSED: a per-id table from a floppy kernel", 1, ["table", "@"], blob=floppy)
    case("REFUSED: verify --id on a floppy kernel (say --floppy)", 1, ["verify", "@", "--id", "6"], blob=floppy)
    case("REFUSED: verify --floppy on an sd kernel", 1, ["verify", "@", "--floppy"], blob=base)
    case("REFUSED: FD0P with a bo_name that is not the contract's", 1,
         ["show", "@"], blob=_mkelf(rootdev=fd0, swap_name=b"/dev/fakeswaq"))
    case("REFUSED: --floppy together with --id", 2, ["stamp", "@", "--floppy", "--id", "6"], blob=base)
    case("stamp --card 1 --id 0 writes c8d0s2", 0,
         ["stamp", "@", "--id", "0", "--card", "1"], blob=base,
         check=lambda p, o: "" if b"/dev/dsk/c8d0s2\0" in open(p, "rb").read() else "no c8d0s2")
    case("stamp --card 0 --id 6 from a card-1 image returns to the card-0 bytes", 0,
         ["stamp", "@", "--id", "6", "--card", "0"], blob=card1,
         check=lambda p, o: "" if open(p, "rb").read() == base else "not the card-0 base bytes")

    print()
    print("REFUSALS -- the coherence gate")
    case("a non-empty rootfstype (forced fstype) is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(rootfstype=b"ufs\0" + b"\0" * 11))
    case("bo_name/rootdev id disagreement is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(swap_name=b"/dev/dsk/c3d0s2"))  # name c3, rootdev c6
    case("rootdev major != sd block major is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(rootdev=0x00400016))
    case("card 1 with a DECIMAL controller name (c14) is refused -- the node is ced0s2", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(rootdev=0x0048001e, swap_name=b"/dev/dsk/c14d0s2"))
    case("card 1 rootdev with a card-0 swap name (c6) is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(rootdev=0x0048001e, swap_name=b"/dev/dsk/c6d0s2"))
    case("--card 2 is refused (sdcard is one bit)", 1,
         ["stamp", "@", "--id", "3", "--card", "2"], blob=base)
    case("bo_size zero is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(bo_size=0))
    case("non-zero bo_flags is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(bo_flags=1))
    case("non-empty bo_fstype is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(bo_fstype=b"ufs\0"))
    case("a bo_name not matching the device-name shape is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(swap_name=b"/dev/dsk/c6XXs2", no_anchor=False))
    case("--expect-current-id 0 on the id-6 base is refused", 1,
         ["stamp", "@", "--id", "3", "--expect-current-id", "0"], blob=base)

    print()
    print("REFUSALS -- the anchor cross-check and the symbol shape")
    case("no `/dev/dsk/c` anchor at all is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(no_anchor=True))
    case("a second anchor occurrence is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(second_anchor=True))
    case("a forbidden /dev/rdsk/c string is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(forbidden_rdsk=True))
    case("rootdev symbol absent (no symtab) is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(drop_symtab=True))
    case("swapfile symbol absent is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(drop_swapfile=True))
    case("rootfstype symbol absent is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(drop_rootfstype=True))
    case("two GLOBAL rootdev defs are refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(dup_rootdev=True))
    case("rootdev defined outside .data is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(rootdev_shndx=1))
    case("rootdev not GLOBAL is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(rootdev_bind=0))
    case("rootdev wrong size/type is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(rootdev_size=8, rootdev_type=STT_OBJECT))

    print()
    print("REFUSALS -- the relocation invariant (disjoint ranges)")
    # rd_addr with defaults: rf_addr=0x10, rf_size=15 -> max(15,16)=16, rd_addr=0x10+16+0x10=0x30
    rd_addr = 0x10 + 16 + 0x10
    sw_addr = rd_addr + 4 + 16
    nm_addr = sw_addr + 0x10
    rf_addr = 0x10
    case("a relocation over rootdev is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(reloc_at=rd_addr))
    case("a relocation over bo_name is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(reloc_at=nm_addr))
    case("a relocation over rootfstype is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(reloc_at=rf_addr))
    _reloc_clear = _mkelf(reloc_at=rd_addr - 4)
    case("a relocation just clear of rootdev is accepted", 0,
         ["stamp", "@", "--id", "3"], blob=_reloc_clear,
         check=only_ranges_changed(3, ref=_reloc_clear))

    print()
    print("REFUSALS -- representation and structure")
    case("a brel (e_type 0xff00) is refused (no symtab to locate by)", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(e_type=0xff00))
    case("a non-m68k ELF is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(e_machine=3))
    case("little-endian ELF is refused", 1,
         ["stamp", "@", "--id", "3"], blob=_mkelf(little=True))
    case("a non-ELF file is refused", 1,
         ["stamp", "@", "--id", "3"], blob=b"not an elf" * 8)
    case("a truncated ELF is refused", 1,
         ["stamp", "@", "--id", "3"], blob=base[:40])

    print()
    print("verify + the id encoding")
    case("verify accepts the id it carries (6)", 0, ["verify", "@", "--id", "6"], blob=base)
    case("verify rejects a different id", 1, ["verify", "@", "--id", "3"], blob=base)
    case("verify --id 8 is refused (target range 0-7)", 1, ["verify", "@", "--id", "8"], blob=base)
    case("stamp --id 8 is refused", 1, ["stamp", "@", "--id", "8"], blob=base)
    case("stamp --root-slice 8 is refused", 1,
         ["stamp", "@", "--id", "3", "--root-slice", "8"], blob=base)

    print()
    print("the per-id table -- determinism and the encoding")
    def table_ok(p, out):
        try:
            t = json.loads(out)
        except ValueError:
            return "table did not emit JSON"
        rows = {r["id"]: r for r in t["rows"]}
        if set(rows) != set(range(8)):
            return "ids != 0-7"
        for i in range(8):
            if rows[i]["rootdev"] != "0x%08x" % spec.compose_dev(i, 1):
                return "id %d rootdev wrong" % i
        # determinism: id 6 row must equal the base identity (same bytes)
        img0 = SymbolKernel("base", spec, data=base)
        b = img0.identity()
        if rows[6]["sum_r"] != b["sum_r"] or rows[6]["sha256"] != b["sha256"]:
            return "id-6 row is not the base identity"
        return ""
    case("table 0-7 is deterministic and matches compose_dev", 0,
         ["table", "@", "--format", "json"], blob=base, check=table_ok)

    print()
    print("checksums agree with an independent route")
    # sum_r vs coreutils `sum -r`; svr4_sum vs the contract vectors.
    def gen_vector(g):
        k = g["kind"]
        if k == "empty":
            return b""
        if k == "hex":
            return bytes.fromhex(g["data"])
        if k == "repeat":
            return bytes([g["byte"]]) * g["count"]
        if k == "range":
            return bytes((g["start"] + i) & 0xff for i in range(g["count"]))
        if k == "cycle":
            pat = bytes(g["pattern"])
            return (pat * (g["count"] // len(pat) + 1))[:g["count"]]
        raise ValueError(k)

    def sumr_agrees():
        n2 = 0
        blob = bytes(range(256)) * 37 + b"\x9d\x1f\x00"
        with tempfile.NamedTemporaryFile(delete=False) as fh:
            fh.write(blob)
            path = fh.name
        try:
            r = subprocess.run(["sum", "-r", path], capture_output=True, text=True)
            mine = sum_r(blob)[0]
            return "" if (r.stdout.split() and int(r.stdout.split()[0]) == mine) \
                else "sum -r disagrees: mine %d coreutils %s" % (mine, r.stdout.split()[:1])
        finally:
            os.unlink(path)

    def svr4_agrees():
        try:
            V = json.load(open(os.path.join(os.path.dirname(CONTRACT),
                                            "bootchain-vectors", "svr4-sum.json")))
        except (OSError, ValueError) as e:
            return "cannot read svr4-sum vectors: %s" % e
        checked = 0
        for v in V.get("vectors", []):
            if "gen" not in v or "sum" not in v:
                continue
            buf = gen_vector(v["gen"])
            if svr4_sum(buf) != v["sum"]:
                return "vector %s: svr4_sum %d != expected %d" % (v.get("name"), svr4_sum(buf), v["sum"])
            checked += 1
        return "" if checked else "no svr4-sum vectors were checked"

    n += 1
    msg = sumr_agrees()
    print("  %-60s %s%s" % ("sum -r agrees with coreutils `sum -r`", "ok" if not msg else "FAIL",
                            "" if not msg else " -- " + msg))
    if msg:
        fails.append("sum_r vs coreutils")
    n += 1
    msg = svr4_agrees()
    print("  %-60s %s%s" % ("svr4-sum agrees with the contract vectors", "ok" if not msg else "FAIL",
                            "" if not msg else " -- " + msg))
    if msg:
        fails.append("svr4_sum vs vectors")

    print()
    print("arg validation")
    case("no subcommand is a usage error", 2, [], blob=base)
    case("unknown subcommand is a usage error", 2, ["frobnicate", "@"], blob=base)
    case("stamp without --id is a usage error", 2, ["stamp", "@"], blob=base)
    case("verify without --id is a usage error", 2, ["verify", "@"], blob=base)
    case("a missing file is reported, not tracebacked", 2, ["show", "@-does-not-exist"], blob=base)

    print()
    print("the C4-1 encoding (amix-dlm C4-1 section 2.1-2.2): four cards, one- or two-digit names")
    for card, unit, sl, minor, name in ((0, 6, 1, 0x16, "/dev/dsk/c6d0s1"), (1, 6, 1, 0x1e, "/dev/dsk/ced0s1"),
                                        (2, 0, 1, 0x90, "/dev/dsk/c10d0s1"), (3, 6, 2, 0xae, "/dev/dsk/c1ed0s2")):
        n += 1
        got_minor = spec.compose_minor(unit, sl, card)
        dec = spec.decode(spec.compose_dev(unit, sl, card))
        got_name = spec.device_name(unit, sl, card)
        m = spec.name_re.match(got_name.encode("latin1") + b"\0")
        ok = (got_minor == minor and (dec["card"], dec["unit"], dec["slice"]) == (card, unit, sl)
              and dec["controller"] == 8 * card + unit and got_name == name
              and m is not None and int(m.group(1), 16) == 8 * card + unit)
        label = "card %d unit %d slice %d: minor 0x%02x, %s" % (card, unit, sl, minor, name)
        print("  %-60s %s" % (label, "ok" if ok else "FAIL -- minor 0x%02x %r %r" % (got_minor, dec, got_name)))
        if not ok:
            fails.append(label)

    print()
    if fails:
        print("%s SELFTEST FAIL -- %d/%d case(s) failed: %s"
              % (WHOAMI, len(fails), n, ", ".join(fails)))
        return 1
    print("%s: SELFTEST PASS -- %d/%d cases" % (WHOAMI, n, n))
    return 0


# ---------------------------------------------------------------------- main --

def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["--selftest"]:
        return selftest()

    ap = argparse.ArgumentParser(
        prog="kernel-rootdev-stamp.py",
        description="Write a destination SCSI id into an 040/060-line Amix kernel BY SYMBOL "
                    "(rootdev + swapfile.bo_name), per contracts/bootchain-v1.json rootdev.")
    ap.add_argument("--selftest", action="store_true", help="run the hermetic selftest and exit")
    ap.add_argument("--contract", default=CONTRACT,
                    help="path to the boot-chain contract (redirects the DEFINITION only)")
    sub = ap.add_subparsers(dest="cmd")

    def with_dest(p, id_required=True):
        p.add_argument("--id", type=int, required=id_required, help="destination SCSI target id, 0-7")
        p.add_argument("--root-slice", type=int, default=None)
        p.add_argument("--swap-slice", type=int, default=None)
        p.add_argument("--card", type=int, default=None,
                       help="card 0 (default, the contract convention) or 1 (fixed-order families)")

    p = sub.add_parser("show", help="locate + validate the site by symbol, print what it says")
    p.add_argument("kernel")

    p = sub.add_parser("verify", help="assert the image already carries a destination")
    p.add_argument("kernel")
    with_dest(p, id_required=False)
    p.add_argument("--floppy", action="store_true", help="assert the contract's rootdev.floppy pair instead of an id")
    p.add_argument("--expect-sum-r", type=int, default=None, help="additionally pin `sum -r`")

    p = sub.add_parser("stamp", help="write the destination (asserts coherence, re-reads after)")
    p.add_argument("kernel")
    with_dest(p, id_required=False)
    p.add_argument("--floppy", action="store_true",
                   help="contract rootdev.floppy: rootdev FD0P + bo_name /dev/fakeswap, from the unstamped sd-6 base "
                        "(the 040/060 install floppy; no --id)")
    p.add_argument("-o", "--out", help="write here instead of in place")
    p.add_argument("--force", action="store_true", help="overwrite an existing -o output")
    p.add_argument("--expect-current-id", type=int, default=None,
                   help="assert the INPUT currently carries this id first (cut-from-base guard)")

    p = sub.add_parser("table", help="emit the per-id expected-sum table")
    p.add_argument("kernel")
    p.add_argument("--ids", default="0-7", help="id set, e.g. 0-7 or 0,5,6")
    p.add_argument("--root-slice", type=int, default=None)
    p.add_argument("--swap-slice", type=int, default=None)
    p.add_argument("--card", type=int, default=None, help="card 0 (default) or 1")
    p.add_argument("--format", choices=("json", "pkginfo", "text"), default="json")
    p.add_argument("-o", "--out", help="write to a file instead of stdout")
    p.add_argument("--force", action="store_true")

    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    if not args.cmd:
        ap.print_usage(sys.stderr)
        return 2

    spec = Spec(load_contract(args.contract), args.contract)
    if getattr(args, "root_slice", None) is None:
        args.root_slice = spec.def_root_slice
    if getattr(args, "swap_slice", None) is None:
        args.swap_slice = spec.def_swap_slice
    if getattr(args, "card", None) is None:
        args.card = spec.card
    return {"show": cmd_show, "verify": cmd_verify,
            "stamp": cmd_stamp, "table": cmd_table}[args.cmd](args, spec)


if __name__ == "__main__":
    sys.exit(main())
