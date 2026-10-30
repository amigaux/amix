#!/usr/bin/env python3
"""kernel-support-probe-inject.py -- put the W-D7 support.c probe into an 040/060-line AMIX
kernel, host-side, after the relink: grow .text, detour autocon()'s RAM-size guess into the
appended probe, drop the one relocation the guess carried, and move nothing else.

    ./tools/kernel-support-probe-inject.py show   <kernel>
    ./tools/kernel-support-probe-inject.py inject <kernel> -o <out> [--force]
    ./tools/kernel-support-probe-inject.py verify <kernel>
    ./tools/kernel-support-probe-inject.py --selftest

WHAT IT FIXES.  Stock autocon() (amiga/kernel/support.c) does not probe for the A3000's
internal SCSI: it GUESSES the controller from the kernel's own BSS `end` being above
0x07000000.  Load the kernel lower (more Fast RAM) and the guess is false, the a3091 is never
registered and root is lost.  The 030 line fixes that at source (amix-a4091
support.c.patch); the 040/060 line is relinked from the stock binary and has no support.c to
patch, so the fix is this post-link edit.

WHAT IT WRITES.  Three edits, nothing else:
  1. the 38-byte guess at autocon+0x1c becomes `bra.l probe` + 16 x nop;
  2. the `R_68K_32 end` record at autocon+0x24 leaves .rela.text (the field it covered is
     now the middle of the bra.l displacement -- a loader that still applied it would
     corrupt the detour);
  3. the 122-byte probe, padded to 124, is appended to .text.  Its three exits are 32-bit
     PC-relative branches back into autocon (the table search at +0x42, the epilogue at
     +0xa0), resolved HERE, so the probe carries no relocation of its own.
Every later section's sh_offset and e_shoff move by the growth (+124 for the sections
between .text and .rela.text, +112 after it); no sh_addr changes (ET_REL, all 0), no symbol
moves (autocon keeps its address and size; the probe has no symbol).

THE SAFETY DISCIPLINE (kernel-cputype-stamp.py, kernel-rootdev-stamp.py, elf2brel.py):
assert the expected bytes before writing, refuse on any mismatch, re-read the output whole.
  * BEFORE: big-endian m68k ET_REL; `autocon` a unique GLOBAL FUNC in .text of size 0xac;
    the stock bne.w at +0x18, the 38 stock guess bytes at +0x1c, the table-search head at
    +0x42, the epilogue at +0xa0; EXACTLY one relocation inside the guess, `R_68K_32 end`
    at +0x24 with addend 0 (and the next record, `bootinfo` at +0x46, where stock puts it);
    .text 4-aligned in size; and the fingerprint 00dd0041 / 00dd0043 absent from the whole
    file (an already-injected kernel, or anything else carrying the ports, is refused).
  * AFTER: the output is re-parsed independently of the writer.  Every section but .text
    and .rela.text must be byte-identical to the input; every header field but the moved
    offsets and the two sizes identical; .text may differ ONLY at the guess site and the
    appended tail; .rela.text ONLY by the one removed record; the fingerprint reads 1/1.

THE PAYLOAD is frozen here by hash (GNU as -m68040 of the probe source).  A payload edit is a
new pin, never a silent swap.

exit 0 = pass, 1 = refusal / mismatch, 2 = usage or unreadable input.
"""
import argparse
import hashlib
import os
import struct
import sys

WHOAMI = "kernel-support-probe-inject"

# ---------------------------------------------------------------- the payload --
# 122 bytes.  Offsets that matter, all probe-relative:
#   +0x06 bne.l  -> TABLE      (field +0x08)
#   +0x24 moveal #0xDD0041,%a0 (immediate +0x26, the SASR fingerprint, once)
#   +0x2a moveal #0xDD0043,%a1 (immediate +0x2c, the SCMD fingerprint, once)
#   +0x66 beq.l  -> TABLE      (field +0x68)
#   +0x74 bra.l  -> EPILOGUE   (field +0x76)
PROBE_HEX = (
    "0c860202f00366fffffffff84281207c00dff0043010e9c005040c400001620000442f09207c00dd0041"
    "227c00dd004310bc000212bc005510bc000312bc00aa10bc00024e7110110c0000556600001410bc0003"
    "4e7110110c0000aa660000047201225f4a8167ffffffff9822bc00dd0000700160ffffffff8a")
PROBE = bytes.fromhex(PROBE_HEX)
PROBE_SHA256 = "6a5e077e9a8da9a475d96cfbda51b1910a6789f0e1a08b411d7128f41aea89ce"   # the low-nibble chipset gate
PROBE_SHA256_KT09 = "7b9b73012e11d878a85a508740c6186748841e938d2b9c8b466a05e0d1417871"   # the first payload (bits 8..14 >= 0x22), superseded
PROBE_HEX_KT09 = PROBE_HEX.replace("e9c005040c400001", "e9c004470c400021")
PROBE_PAD = 124                                   # 4-aligned append
NOP = b"\x4e\x71"

# The chipset gate, modelled on the probe's own three instructions at +0x16 (bfextu %d0{off:width},%d0),
# +0x1a (cmpiw #imm,%d0) and +0x1e (bhiw Ltest): skip = the extracted field > imm, unsigned.
# The Agnus/Alice ids in VPOSR bits 8..14 are 0x00/0x10 OCS, 0x20 PAL ECS, 0x30
# NTSC ECS, 0x22/0x23/0x32/0x33 AGA Alice -- the first payload's test ">= 0x22" took an NTSC A3000 (0x30) for
# AGA and skipped its WD probe; the corrected probe extracts the LOW NIBBLE (bits 8..11, bfextu
# {#20:#4}) and skips on >= 2.  The model asserts the opcodes so a payload with a different gate
# shape cannot be judged by mistake.
GATE_OFF = 0x16


def chipset_gate(probe, vposr):
    """True = the probe SKIPS (AGA), False = it probes the WD33C93; for one 16-bit VPOSR value."""
    bf = probe[GATE_OFF:GATE_OFF + 4]
    cmp = probe[GATE_OFF + 4:GATE_OFF + 8]
    br = probe[GATE_OFF + 8:GATE_OFF + 10]
    if bf[:2] != b"\xe9\xc0" or cmp[:2] != b"\x0c\x40" or br != b"\x62\x00":
        raise ValueError("the payload's chipset gate is not bfextu/cmpiw/bhiw at +0x%x" % GATE_OFF)
    ext = int.from_bytes(bf[2:], "big")
    off, width = (ext >> 6) & 0x1F, ext & 0x1F
    imm = int.from_bytes(cmp[2:], "big")
    d0 = vposr & 0xFFFF                       # movew %a0@,%d0: the low word; the field lies within it
    field = (d0 >> (32 - off - width)) & ((1 << width) - 1)
    return field > imm
BRA_L, BNE_L, BEQ_L = 0x60FF, 0x66FF, 0x67FF

# autocon()-relative facts (section 2 / 6a).
AUTOCON_SIZE = 0xAC
TABLE_OFF, EPILOGUE_OFF = 0x42, 0xA0
BNE_OFF, BNE_STOCK = 0x18, bytes.fromhex("66000028")
GUESS_OFF, GUESS_LEN = 0x1C, 38
GUESS_STOCK = bytes.fromhex(
    "2e3c07000000" "0c8700000000" "64000018" "0c860202f003" "6600000e" "22bc00dd0000" "7001" "60000060")
TABLE_HEAD = bytes.fromhex("428241f9")           # clr.l %d2; lea bootinfo,%a0 (field follows)
EPILOGUE_STOCK = bytes.fromhex("4cee04fcffe4" "2040" "4e5e" "4e75")
END_RELOC_OFF, BOOTINFO_RELOC_OFF = 0x24, 0x46
# (probe offset of the opcode word, opcode, autocon-relative target)
PROBE_EXITS = ((0x06, BNE_L, TABLE_OFF), (0x66, BEQ_L, TABLE_OFF), (0x74, BRA_L, EPILOGUE_OFF))
PROBE_PORTS = ((0x26, bytes.fromhex("00dd0041")), (0x2C, bytes.fromhex("00dd0043")))
WD7_PATTERNS = (("SASR 0xDD0041", bytes.fromhex("00dd0041")),
                ("SCMD 0xDD0043", bytes.fromhex("00dd0043")))

assert len(PROBE) == 122 and len(GUESS_STOCK) == GUESS_LEN
assert hashlib.sha256(PROBE).hexdigest() == PROBE_SHA256, "the probe payload is not the pinned bytes"
for _o, _op, _t in PROBE_EXITS:
    assert struct.unpack_from(">H", PROBE, _o)[0] == _op
for _o, _p in PROBE_PORTS:
    assert PROBE[_o:_o + 4] == _p and PROBE.count(_p) == 1

# ELF constants
ET_REL, EM_68K = 1, 4
SHT_NOBITS, SHT_RELA, SHT_SYMTAB = 8, 4, 2
STB_GLOBAL, STT_FUNC = 1, 2
R_68K_32 = 1
EHSIZE, SHSIZE, SYMSIZE, RELASIZE = 52, 40, 16, 12


class Refused(Exception):
    pass


def u16(b, o):
    return struct.unpack_from(">H", b, o)[0]


def u32(b, o):
    return struct.unpack_from(">I", b, o)[0]


def s32(b, o):
    return struct.unpack_from(">i", b, o)[0]


# ------------------------------------------------------------------- the ELF --

class Kernel(object):
    """A big-endian m68k ET_REL read whole; sections, symbols and the autocon site."""

    def __init__(self, data):
        self.d = data
        d = data
        if len(d) < EHSIZE or d[:4] != b"\x7fELF":
            raise Refused(["not an ELF file"])
        if d[4] != 1 or d[5] != 2:
            raise Refused(["not ELFCLASS32 big-endian"])
        if u16(d, 16) != ET_REL or u16(d, 18) != EM_68K:
            raise Refused(["not an m68k ET_REL (e_type %d e_machine %d)" % (u16(d, 16), u16(d, 18))])
        self.e_shoff, self.e_shentsize, self.e_shnum, self.e_shstrndx = (
            u32(d, 32), u16(d, 46), u16(d, 48), u16(d, 50))
        if self.e_shentsize != SHSIZE or self.e_shnum == 0 or \
                self.e_shoff + self.e_shnum * SHSIZE > len(d):
            raise Refused(["section header table missing or outside the file"])
        self.S = []
        for i in range(self.e_shnum):
            o = self.e_shoff + i * SHSIZE
            f = struct.unpack_from(">IIIIIIIIII", d, o)
            self.S.append(dict(name=f[0], type=f[1], flags=f[2], addr=f[3], offset=f[4],
                               size=f[5], link=f[6], info=f[7], addralign=f[8], entsize=f[9]))
        sh = self.S[self.e_shstrndx]
        shstr = d[sh["offset"]:sh["offset"] + sh["size"]]
        self.names = []
        for s in self.S:
            e = shstr.find(b"\0", s["name"])
            self.names.append(shstr[s["name"]:e].decode("latin1") if e >= 0 else "?")
        for s, nm in zip(self.S, self.names):
            if s["type"] != SHT_NOBITS and s["offset"] + s["size"] > len(d):
                raise Refused(["section %s runs past the end of the file" % nm])

    def index(self, name):
        hits = [i for i, n in enumerate(self.names) if n == name]
        if len(hits) != 1:
            raise Refused(["section %s: %d found, need exactly 1" % (name, len(hits))])
        return hits[0]

    def bytes_of(self, i):
        s = self.S[i]
        if s["type"] == SHT_NOBITS:
            return b""
        return self.d[s["offset"]:s["offset"] + s["size"]]

    def symbols(self):
        """[(name, value, size, bind, type, shndx)] from .symtab/.strtab."""
        i_sym = self.index(".symtab")
        st = self.S[i_sym]
        strt = self.S[st["link"]]
        strd = self.d[strt["offset"]:strt["offset"] + strt["size"]]
        symd = self.bytes_of(i_sym)
        out = []
        for k in range(len(symd) // SYMSIZE):
            n, v, sz, info, _other, sx = struct.unpack_from(">IIIBBH", symd, k * SYMSIZE)
            e = strd.find(b"\0", n)
            out.append((strd[n:e].decode("latin1"), v, sz, info >> 4, info & 0xF, sx))
        return out

    def relocs(self, name):
        """[(r_offset, symidx, type, addend)] of one RELA section, in file order."""
        rd = self.bytes_of(self.index(name))
        return [struct.unpack_from(">IIi", rd, k * RELASIZE)[0:1]
                + ((u32(rd, k * RELASIZE + 4) >> 8, u32(rd, k * RELASIZE + 4) & 0xFF,
                    s32(rd, k * RELASIZE + 8)))
                for k in range(len(rd) // RELASIZE)]

    # ----------------------------------------------------------- the site --

    def site(self):
        """Locate autocon() and return a dict of facts, or raise Refused(problems)."""
        bad = []
        i_text = self.index(".text")
        i_rela = self.index(".rela.text")
        i_sym = self.index(".symtab")
        rs = self.S[i_rela]
        if rs["type"] != SHT_RELA or rs["entsize"] != RELASIZE or rs["info"] != i_text \
                or rs["link"] != i_sym:
            bad.append(".rela.text is not a RELA section over .text linked to .symtab")
        syms = self.symbols()
        hits = [(k, s) for k, s in enumerate(syms) if s[0] == "autocon"]
        if len(hits) != 1:
            bad.append("symbol autocon: %d found, need exactly 1" % len(hits))
            raise Refused(bad)
        k, (_n, val, size, bind, typ, sx) = hits[0]
        if bind != STB_GLOBAL or typ != STT_FUNC or sx != i_text:
            bad.append("autocon is not a GLOBAL FUNC in .text (bind %d type %d shndx %d)"
                       % (bind, typ, sx))
        if size != AUTOCON_SIZE:
            bad.append("autocon size 0x%x, stock is 0x%x" % (size, AUTOCON_SIZE))
        text = self.bytes_of(i_text)
        if val + AUTOCON_SIZE > len(text):
            bad.append("autocon at .text+0x%x runs past .text" % val)
            raise Refused(bad)
        names = {"end": [], "bootinfo": []}
        for i, s in enumerate(syms):
            if s[0] in names:
                names[s[0]].append(i)
        facts = dict(i_text=i_text, i_rela=i_rela, i_sym=i_sym, autocon=val,
                     textsize=len(text), guess=val + GUESS_OFF,
                     table=val + TABLE_OFF, epilogue=val + EPILOGUE_OFF)
        # the stock bytes
        for label, off, want in (("bne.w at +0x18", BNE_OFF, BNE_STOCK),
                                 ("the 38 guess bytes at +0x1c", GUESS_OFF, GUESS_STOCK),
                                 ("the table-search head at +0x42", TABLE_OFF, TABLE_HEAD),
                                 ("the epilogue at +0xa0", EPILOGUE_OFF, EPILOGUE_STOCK)):
            got = text[val + off:val + off + len(want)]
            if got != want:
                bad.append("%s: read %s, stock is %s" % (label, got.hex(), want.hex()))
        # the relocations
        rel = self.relocs(".rela.text")
        inside = [(i, r) for i, r in enumerate(rel)
                  if val + GUESS_OFF <= r[0] < val + GUESS_OFF + GUESS_LEN]
        if len(inside) != 1:
            bad.append("%d relocation(s) inside the guess, stock has exactly 1 (R_68K_32 end)"
                       % len(inside))
        else:
            i, (off, si, ty, add) = inside[0]
            if off != val + END_RELOC_OFF or ty != R_68K_32 or add != 0 \
                    or si not in names["end"]:
                bad.append("the guess relocation is at +0x%x type %d sym #%d addend %d, stock "
                           "is R_68K_32 end at +0x%x addend 0"
                           % (off - val, ty, si, add, END_RELOC_OFF))
            facts["end_reloc_index"] = i
        binfo = [r for r in rel if r[0] == val + BOOTINFO_RELOC_OFF]
        if not (len(binfo) == 1 and binfo[0][2] == R_68K_32 and binfo[0][1] in names["bootinfo"]):
            bad.append("no R_68K_32 bootinfo record at +0x46 (the table search's lea): not "
                       "the stock autocon")
        if len(text) % 4:
            bad.append(".text size 0x%x is not 4-aligned; the probe would land misaligned"
                       % len(text))
        if len(text) + PROBE_PAD - (val + GUESS_OFF + 2) > 0x7FFFFFFF:
            bad.append("the detour displacement does not fit 32 bits")
        counts = [self.d.count(p) for _, p in WD7_PATTERNS]
        facts["wd7"] = counts
        if counts != [0, 0]:
            bad.append("fingerprint already present (SASR x%d, SCMD x%d): already injected, or "
                       "not a stock autocon kernel" % tuple(counts))
        if bad:
            raise Refused(bad)
        return facts


# ---------------------------------------------------------------- the probe --

def detour_bytes(guess_at, probe_at):
    """The 38 bytes that replace the guess: bra.l probe, then nops."""
    disp = probe_at - (guess_at + 2)
    return struct.pack(">Hi", BRA_L, disp) + NOP * ((GUESS_LEN - 6) // 2)


# Every payload this injector has ever pinned, by sha256: the K0 gates verify a family's declared
# `wd7_payload` byte for byte at the detour target, so an old payload is named, not mistaken.
PAYLOADS = {PROBE_SHA256: PROBE, PROBE_SHA256_KT09: bytes.fromhex(PROBE_HEX_KT09)}


def probe_bytes(probe_at, autocon, probe=None):
    """The padded probe with its three exits resolved for this placement."""
    p = bytearray(PROBE if probe is None else probe)
    for off, op, target in PROBE_EXITS:
        assert u16(p, off) == op
        struct.pack_into(">i", p, off + 2, (autocon + target) - (probe_at + off + 2))
    pad = PROBE_PAD - len(p)
    assert pad >= 0 and pad % 2 == 0
    return bytes(p) + NOP * (pad // 2)


# -------------------------------------------------------------- the rewrite --

def inject(data, probe=None):
    """Return (out_bytes, facts).  Raises Refused on any precondition failure."""
    k = Kernel(data)
    f = k.site()
    i_text, i_rela = f["i_text"], f["i_rela"]
    old_text = k.bytes_of(i_text)
    probe_at = f["textsize"]
    guess_at = f["guess"]
    new_text = (old_text[:guess_at] + detour_bytes(guess_at, probe_at)
                + old_text[guess_at + GUESS_LEN:] + probe_bytes(probe_at, f["autocon"], probe))
    assert len(new_text) == len(old_text) + PROBE_PAD
    old_rela = k.bytes_of(i_rela)
    r = f["end_reloc_index"] * RELASIZE
    new_rela = old_rela[:r] + old_rela[r + RELASIZE:]

    # Pieces of the file in file order: every section with bytes, and the header table.
    pieces = []
    for i, s in enumerate(k.S):
        if s["type"] != SHT_NOBITS and s["size"] > 0:
            pieces.append([s["offset"], s["size"], i])
    pieces.append([k.e_shoff, k.e_shnum * SHSIZE, "shdr"])
    pieces.sort()
    for a, b in zip(pieces, pieces[1:]):
        if a[0] + a[1] > b[0]:
            raise Refused(["sections overlap in the file (%r, %r): not rewritable" % (a, b)])
    if pieces[0][0] < EHSIZE:
        raise Refused(["a section overlaps the ELF header"])

    # New offsets: walk in file order, keeping every inter-piece gap verbatim.
    new_off = {}
    cur_old, cur_new = EHSIZE, EHSIZE
    for old_off, old_len, who in pieces:
        cur_new += old_off - cur_old                # the gap, copied as is
        new_off[who] = cur_new
        new_len = old_len + (PROBE_PAD if who == i_text else -RELASIZE if who == i_rela else 0)
        cur_old, cur_new = old_off + old_len, cur_new + new_len
    total_delta = cur_new - cur_old

    def shifted(old_offset):
        # A NOBITS section's sh_offset moves with the first piece at or after it.
        for old_off, _l, who in pieces:
            if old_off >= old_offset:
                return new_off[who] - old_off + old_offset
        return old_offset + total_delta

    hdrs = []
    for i, s in enumerate(k.S):
        h = dict(s)
        if s["type"] == SHT_NOBITS:
            h["offset"] = shifted(s["offset"]) if s["offset"] else 0
        elif i in new_off:
            h["offset"] = new_off[i]
        if i == i_text:
            h["size"] = len(new_text)
        if i == i_rela:
            h["size"] = len(new_rela)
        hdrs.append(h)
    shdr = b"".join(struct.pack(">IIIIIIIIII", h["name"], h["type"], h["flags"], h["addr"],
                                h["offset"], h["size"], h["link"], h["info"], h["addralign"],
                                h["entsize"]) for h in hdrs)
    eh = bytearray(data[:EHSIZE])
    struct.pack_into(">I", eh, 32, new_off["shdr"])

    out = bytearray(eh)
    cur_old = EHSIZE
    for old_off, old_len, who in pieces:
        out += data[cur_old:old_off]
        assert len(out) == new_off[who]
        if who == "shdr":
            out += shdr
        elif who == i_text:
            out += new_text
        elif who == i_rela:
            out += new_rela
        else:
            out += data[old_off:old_off + old_len]
        cur_old = old_off + old_len
    out += data[cur_old:]                         # anything after the last piece
    out = bytes(out)
    f.update(probe_at=probe_at, out_size=len(out), delta=len(out) - len(data),
             detour_disp=probe_at - (guess_at + 2))
    check_edit(data, out, f, probe)
    return out, f


def check_edit(old, new, f, probe=None):
    """Re-read both images independently and require the edit to be exactly the edit."""
    ko, kn = Kernel(old), Kernel(new)
    bad = []
    if kn.e_shnum != ko.e_shnum or kn.names != ko.names:
        bad.append("section count/names changed")
        raise Refused(bad)
    i_text, i_rela = f["i_text"], f["i_rela"]
    for i, (a, b) in enumerate(zip(ko.S, kn.S)):
        for key in ("name", "type", "flags", "addr", "link", "info", "addralign", "entsize"):
            if a[key] != b[key]:
                bad.append("section %s: %s changed" % (ko.names[i], key))
        want = a["size"] + (PROBE_PAD if i == i_text else -RELASIZE if i == i_rela else 0)
        if b["size"] != want:
            bad.append("section %s: size 0x%x, expected 0x%x" % (ko.names[i], b["size"], want))
        if i not in (i_text, i_rela) and ko.bytes_of(i) != kn.bytes_of(i):
            bad.append("section %s: bytes changed" % ko.names[i])
    if len(new) != len(old) + PROBE_PAD - RELASIZE:
        bad.append("file size %d, expected %d" % (len(new), len(old) + PROBE_PAD - RELASIZE))
    ot, nt = ko.bytes_of(i_text), kn.bytes_of(i_text)
    g, pa = f["guess"], f["probe_at"]
    if not (nt[:g] == ot[:g] and nt[g + GUESS_LEN:pa] == ot[g + GUESS_LEN:pa]):
        bad.append(".text differs outside the guess site and the appended tail")
    if nt[g:g + GUESS_LEN] != detour_bytes(g, pa):
        bad.append("the guess site is not the detour")
    if nt[pa:] != probe_bytes(pa, f["autocon"], probe):
        bad.append("the appended tail is not the probe")
    o_rel, n_rel = ko.relocs(".rela.text"), kn.relocs(".rela.text")
    r = f["end_reloc_index"]
    if n_rel != o_rel[:r] + o_rel[r + 1:]:
        bad.append(".rela.text is not the input minus the end record")
    if ko.relocs(".rela.data") != kn.relocs(".rela.data") if ".rela.data" in ko.names else False:
        bad.append(".rela.data changed")
    counts = [new.count(p) for _, p in WD7_PATTERNS]
    if counts != [1, 1]:
        bad.append("fingerprint after the edit reads SASR x%d SCMD x%d, not 1/1" % tuple(counts))
    if bad:
        raise Refused(["POST-CONDITION: " + b for b in bad])


# -------------------------------------------------------------- verification --

def locate_injected(data, probe=None):
    """On an injected kernel: follow the detour and check the probe (the pinned payload, or the
    one given).  Returns facts or raises Refused."""
    k = Kernel(data)
    i_text = k.index(".text")
    text = k.bytes_of(i_text)
    hits = [s for s in k.symbols() if s[0] == "autocon"]
    if len(hits) != 1 or hits[0][2] != AUTOCON_SIZE or hits[0][5] != i_text:
        raise Refused(["autocon: not a unique 0x%x-byte symbol in .text" % AUTOCON_SIZE])
    a = hits[0][1]
    g = a + GUESS_OFF
    if u16(text, g) != BRA_L:
        raise Refused(["autocon+0x1c is not a bra.l (reads %s): no detour" % text[g:g + 2].hex()])
    pa = g + 2 + s32(text, g + 2)
    bad = []
    if text[g:g + GUESS_LEN] != detour_bytes(g, pa):
        bad.append("the detour site is not bra.l + nops")
    if not (0 <= pa and pa + PROBE_PAD <= len(text)):
        bad.append("the detour points outside .text (.text+0x%x)" % pa)
    elif text[pa:pa + PROBE_PAD] != probe_bytes(pa, a, probe):
        bad.append("the bytes at .text+0x%x are not the %s probe with exits into this autocon"
                   % (pa, hashlib.sha256(PROBE if probe is None else probe).hexdigest()[:8]))
    rel = k.relocs(".rela.text")
    over = [r for r in rel if g <= r[0] < g + GUESS_LEN or pa <= r[0] < pa + PROBE_PAD]
    if over:
        bad.append("%d relocation(s) still cover the detour or the probe" % len(over))
    counts = [data.count(p) for _, p in WD7_PATTERNS]
    if counts != [1, 1]:
        bad.append("fingerprint reads SASR x%d SCMD x%d, not 1/1" % tuple(counts))
    if bad:
        raise Refused(bad)
    return dict(autocon=a, guess=g, probe_at=pa, textsize=len(text), wd7=counts)


# --------------------------------------------------------------------- CLI --

def _read(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError as e:
        sys.stderr.write("%s: %s\n" % (WHOAMI, e))
        sys.exit(2)


def _refused(problems):
    print("%s: REFUSED" % WHOAMI)
    for p in problems:
        print("  - %s" % p)
    return 1


def cmd_show(a):
    data = _read(a.kernel)
    print("%s: %s (%d bytes, sha256 %s)" % (WHOAMI, a.kernel, len(data),
                                              hashlib.sha256(data).hexdigest()[:16]))
    try:
        f = locate_injected(data)
        print("  state      : INJECTED -- autocon .text+0x%x, detour at +0x1c -> probe at "
              ".text+0x%x, fingerprint SASR x%d SCMD x%d" % (f["autocon"], f["probe_at"],
                                                             f["wd7"][0], f["wd7"][1]))
        return 0
    except Refused as e_inj:
        pass
    try:
        f = Kernel(data).site()
    except Refused as e:
        print("  state      : NEITHER stock nor injected")
        print("  as injected: %s" % "; ".join(e_inj.args[0]))
        print("  as stock   : %s" % "; ".join(e.args[0]))
        return 1
    print("  state      : STOCK (injectable)")
    print("  autocon    : .text+0x%x size 0x%x; guess at +0x1c (.text+0x%x), R_68K_32 end at "
          "+0x24 (record #%d)" % (f["autocon"], AUTOCON_SIZE, f["guess"], f["end_reloc_index"]))
    print("  .text      : 0x%x bytes; the probe would land at .text+0x%x (+%d, padded)"
          % (f["textsize"], f["textsize"], PROBE_PAD))
    print("  fingerprint: SASR x%d SCMD x%d" % tuple(f["wd7"]))
    return 0


def cmd_inject(a):
    data = _read(a.kernel)
    if os.path.exists(a.out) and not a.force:
        sys.stderr.write("%s: %s exists (use --force)\n" % (WHOAMI, a.out))
        return 2
    try:
        out, f = inject(data)
    except Refused as e:
        return _refused(e.args[0])
    tmp = a.out + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(out)
    os.replace(tmp, a.out)
    with open(a.out, "rb") as fh:
        back = fh.read()
    if back != out:
        os.unlink(a.out)
        return _refused(["the output re-read from disk is not what was written"])
    print("%s: %s -> %s" % (WHOAMI, a.kernel, a.out))
    print("  autocon    : .text+0x%x; guess at .text+0x%x -> bra.l %+d -> probe at .text+0x%x"
          % (f["autocon"], f["guess"], f["detour_disp"], f["probe_at"]))
    print("  relocation : R_68K_32 end (record #%d) removed from .rela.text"
          % f["end_reloc_index"])
    print("  .text      : 0x%x -> 0x%x (+%d); file %d -> %d (%+d)"
          % (f["textsize"], f["textsize"] + PROBE_PAD, PROBE_PAD, len(data), f["out_size"],
             f["delta"]))
    print("  fingerprint: SASR x1 SCMD x1")
    print("  identity   : sha256 %s" % hashlib.sha256(out).hexdigest())
    print("%s: PASS  post-condition held (every other section byte-identical)" % WHOAMI)
    return 0


def cmd_verify(a):
    data = _read(a.kernel)
    try:
        f = locate_injected(data)
    except Refused as e:
        return _refused(e.args[0])
    print("%s: PASS  %s carries the probe at .text+0x%x (autocon .text+0x%x), fingerprint 1/1"
          % (WHOAMI, a.kernel, f["probe_at"], f["autocon"]))
    return 0


# ----------------------------------------------------------------- selftest --

def synthetic_stock_kernel(text_len=0x400, autocon_at=0x120, stray=b"", shdr_last=False):
    """A minimal big-endian m68k ET_REL with a stock-shaped autocon(): the asserted
    fragments (bne.w, the guess, the table head, the epilogue) at their offsets, nops
    elsewhere.  File order mirrors the real kernel: .text .data [.bss] .comment .shstrtab
    SHDR .rela.text .rela.data .symtab .strtab (SHDR last with shdr_last=True).

    Symbols: 0 null, 1 autocon (GLOBAL FUNC 0xac), 2 end (GLOBAL UNDEF), 3 bootinfo
    (GLOBAL OBJECT .data), 4 t_other (GLOBAL FUNC .text+0x20), 5 edata (GLOBAL UNDEF).
    .rela.text: PC16 at 0x12 -> t_other (the bsr.w's field); R_68K_32 end at autocon+0x24; R_68K_32 bootinfo
    at autocon+0x46; R_68K_32 bootinfo at 0x300; R_68K_32 edata at 0x310.  .rela.data: one
    R_68K_32 autocon at 4.  `stray` is appended to .data (a fingerprint there must refuse).
    Returns bytes."""
    text = bytearray(NOP * (text_len // 2))
    a = autocon_at
    text[a:a + 4] = bytes.fromhex("4e56ffe4")                 # link %fp,#-28
    text[a + BNE_OFF:a + BNE_OFF + 4] = BNE_STOCK
    text[a + GUESS_OFF:a + GUESS_OFF + GUESS_LEN] = GUESS_STOCK
    text[a + TABLE_OFF:a + TABLE_OFF + 8] = TABLE_HEAD + b"\0\0\0\0"
    text[a + EPILOGUE_OFF:a + EPILOGUE_OFF + 12] = EPILOGUE_STOCK
    text[0x10:0x14] = bytes.fromhex("61000000")               # bsr.w (field zero)
    text[0x300:0x304] = b"\0\0\0\0"
    text[0x310:0x314] = b"\0\0\0\0"
    data = bytes(range(256)) * 2 + stray
    comment = b"@(#)synthetic kernel\0\0"     # 22 bytes: leaves a 3-byte pad before SHDR
    shnames = (b"\0.text\0.data\0.bss\0.comment\0.shstrtab\0.rela.text\0.rela.data\0"
               b".symtab\0.strtab\0")

    def shname(n):
        return shnames.index(b"\0" + n + b"\0") + 1
    SEC = dict(text=1, data=2, bss=3, comment=4, shstrtab=5, rela_text=6, rela_data=7,
               symtab=8, strtab=9)
    syms = [(b"", 0, 0, 0, 0, 0),
            (b"autocon", a, AUTOCON_SIZE, STB_GLOBAL, STT_FUNC, SEC["text"]),
            (b"end", 0, 0, STB_GLOBAL, 0, 0),
            (b"bootinfo", 0x40, 0x76c, STB_GLOBAL, 1, SEC["data"]),
            (b"t_other", 0x20, 8, STB_GLOBAL, STT_FUNC, SEC["text"]),
            (b"edata", 0, 0, STB_GLOBAL, 0, 0)]
    strtab = b"\0"
    stroff = {b"": 0}
    for row in syms:
        if row[0]:
            stroff[row[0]] = len(strtab)
            strtab += row[0] + b"\0"
    symtab = b"".join(struct.pack(">IIIBBH", stroff[n], v, sz, (b << 4) | t, 0, sx)
                      for (n, v, sz, b, t, sx) in syms)

    def pack(rs):
        return b"".join(struct.pack(">IIi", off, (si << 8) | ty, add) for (off, si, ty, add) in rs)
    rela_t = pack([(0x12, 4, 5, 0), (a + END_RELOC_OFF, 2, R_68K_32, 0),
                   (a + BOOTINFO_RELOC_OFF, 3, R_68K_32, 0), (0x300, 3, R_68K_32, 0),
                   (0x310, 5, R_68K_32, 0)])
    rela_d = pack([(4, 1, R_68K_32, 0)])

    order = [("text", bytes(text)), ("data", data), ("comment", comment),
             ("shstrtab", shnames), ("SHDR", None), ("rela_text", rela_t),
             ("rela_data", rela_d), ("symtab", symtab), ("strtab", strtab)]
    if shdr_last:
        order.remove(("SHDR", None))
        order.append(("SHDR", None))
    nsec = 10
    off = EHSIZE
    offs = {}
    blob = b""
    for who, payload in order:
        if who == "SHDR":
            pad = (-off) % 4                      # the real file aligns the table to 4
            blob += b"\0" * pad
            off += pad
            offs[who] = off
            blob += b"\0" * (nsec * SHSIZE)       # placeholder, filled below
            off += nsec * SHSIZE
        else:
            offs[who] = off
            blob += payload
            off += len(payload)
    bss_off = offs["data"] + len(data)
    secs = [(0, 0, 0, 0, 0, 0, 0, 0, 0),
            (shname(b".text"), 1, 6, offs["text"], len(text), 0, 0, 4, 0),
            (shname(b".data"), 1, 3, offs["data"], len(data), 0, 0, 4, 0),
            (shname(b".bss"), SHT_NOBITS, 3, bss_off, 0x40, 0, 0, 8, 0),
            (shname(b".comment"), 1, 0, offs["comment"], len(comment), 0, 0, 4, 0),
            (shname(b".shstrtab"), 3, 0, offs["shstrtab"], len(shnames), 0, 0, 1, 0),
            (shname(b".rela.text"), SHT_RELA, 0, offs["rela_text"], len(rela_t), SEC["symtab"],
             SEC["text"], 4, RELASIZE),
            (shname(b".rela.data"), SHT_RELA, 0, offs["rela_data"], len(rela_d), SEC["symtab"],
             SEC["data"], 4, RELASIZE),
            (shname(b".symtab"), SHT_SYMTAB, 0, offs["symtab"], len(symtab), SEC["strtab"], 1, 4,
             SYMSIZE),
            (shname(b".strtab"), 3, 0, offs["strtab"], len(strtab), 0, 0, 1, 0)]
    sht = b"".join(struct.pack(">IIIIIIIIII", n, t, f, 0, o, sz, lk, inf, al, es)
                   for (n, t, f, o, sz, lk, inf, al, es) in secs)
    blob = bytearray(blob)
    p = offs["SHDR"] - EHSIZE
    blob[p:p + len(sht)] = sht
    eh = bytearray(EHSIZE)
    eh[0:4] = b"\x7fELF"
    eh[4], eh[5], eh[6] = 1, 2, 1
    struct.pack_into(">HHI", eh, 16, ET_REL, EM_68K, 1)
    struct.pack_into(">III", eh, 24, 0, 0, offs["SHDR"])
    struct.pack_into(">IHHHHHH", eh, 36, 0, EHSIZE, 0, 0, SHSIZE, nsec, SEC["shstrtab"])
    return bytes(eh) + bytes(blob)


def selftest():
    import shutil
    import subprocess
    import tempfile
    fails = []
    total = [0]

    def ok(label, cond, detail=""):
        total[0] += 1
        print("  %-72s %s" % (label, "ok" if cond else "FAIL"))
        if not cond:
            fails.append(label)
            if detail:
                print("      " + detail)

    def refused(label, blob, needle):
        try:
            inject(blob)
            ok(label, False, "injected instead")
        except Refused as e:
            msg = "; ".join(e.args[0])
            ok(label, needle in msg, msg[:120])

    print("kernel-support-probe-inject selftest")
    print("payload")
    ok("the pinned payload hashes to %s" % PROBE_SHA256[:16],
       hashlib.sha256(PROBE).hexdigest() == PROBE_SHA256)
    ok("each port immediate occurs exactly once in the payload",
       all(PROBE.count(p) == 1 for _, p in WD7_PATTERNS))
    ok("the padded probe is 4-aligned", PROBE_PAD % 4 == 0 and PROBE_PAD >= len(PROBE))
    # the eight Agnus/Alice ids through the gate model (VPOSR bits 8..14 = id, LOF set or clear)
    ids_probe, ids_skip = (0x00, 0x10, 0x20, 0x30), (0x22, 0x23, 0x32, 0x33)
    for lof in (0, 0x8000):
        ok("gate probes on OCS/ECS ids %s (LOF %d)" % (["%#04x" % i for i in ids_probe], lof >> 15),
           all(chipset_gate(PROBE, (i << 8) | lof) is False for i in ids_probe))
        ok("gate skips on AGA Alice ids %s (LOF %d)" % (["%#04x" % i for i in ids_skip], lof >> 15),
           all(chipset_gate(PROBE, (i << 8) | lof) is True for i in ids_skip))
    old = bytes.fromhex(PROBE_HEX_KT09)
    ok("the first payload hashes to its recorded sha", hashlib.sha256(old).hexdigest() == PROBE_SHA256_KT09)
    ok("the first payload's defect is reproduced by the model: NTSC ECS 0x30 skipped, PAL ECS 0x20 probed",
       chipset_gate(old, 0x3000) is True and chipset_gate(old, 0x2000) is False)
    ok("the two payloads differ in exactly the gate's three bytes",
       [i for i in range(len(PROBE)) if PROBE[i] != old[i]] == [0x18, 0x19, 0x1d])
    try:
        chipset_gate(b"\0" * 0x30, 0)
        ok("a payload without the gate shape is refused by the model", False)
    except ValueError:
        ok("a payload without the gate shape is refused by the model", True)

    print("preconditions (a)")
    stock = synthetic_stock_kernel()
    k = Kernel(stock)
    try:
        f = k.site()
        ok("the stock fixture passes the site precondition", f["autocon"] == 0x120
           and f["end_reloc_index"] == 1 and f["wd7"] == [0, 0])
    except Refused as e:
        ok("the stock fixture passes the site precondition", False, "; ".join(e.args[0]))

    print("refusals (b)")
    b = bytearray(stock)
    b[EHSIZE + 0x120 + GUESS_OFF + 3] ^= 0x01                 # one guess byte
    refused("a guess byte that is not stock", bytes(b), "guess bytes")
    b = bytearray(stock)
    b[EHSIZE + 0x120 + BNE_OFF + 3] = 0x2a
    refused("a bne.w that is not stock", bytes(b), "bne.w")
    b = bytearray(stock)
    b[EHSIZE + 0x120 + EPILOGUE_OFF] = 0x4e
    refused("an epilogue that is not stock", bytes(b), "epilogue")
    b = bytearray(stock)
    b[EHSIZE + 0x120 + TABLE_OFF] = 0x42
    b[EHSIZE + 0x120 + TABLE_OFF + 1] = 0x83                  # clr.l %d3
    refused("a table-search head that is not stock", bytes(b), "table-search head")

    def with_rela(blob, edit):
        """Rewrite the fixture's .rela.text through `edit(list) -> list` (same length)."""
        kk = Kernel(blob)
        i = kk.index(".rela.text")
        rs = edit(kk.relocs(".rela.text"))
        assert len(rs) == len(kk.relocs(".rela.text"))
        out = bytearray(blob)
        o = kk.S[i]["offset"]
        for n, (off, si, ty, add) in enumerate(rs):
            struct.pack_into(">IIi", out, o + n * RELASIZE, off, (si << 8) | ty, add)
        return bytes(out)
    refused("the end record missing (moved out of the guess)", with_rela(
        stock, lambda rs: [rs[0], (0x200, 2, R_68K_32, 0)] + rs[2:]), "0 relocation(s) inside")
    refused("the end record at the wrong offset inside the guess", with_rela(
        stock, lambda rs: [rs[0], (0x120 + 0x20, 2, R_68K_32, 0)] + rs[2:]), "guess relocation is at")
    refused("the end record naming another symbol", with_rela(
        stock, lambda rs: [rs[0], (0x120 + 0x24, 5, R_68K_32, 0)] + rs[2:]), "guess relocation is at")
    refused("the end record with a non-zero addend", with_rela(
        stock, lambda rs: [rs[0], (0x120 + 0x24, 2, R_68K_32, 4)] + rs[2:]), "guess relocation is at")
    refused("a second relocation inside the guess", with_rela(
        stock, lambda rs: rs[:3] + [(0x120 + 0x30, 3, R_68K_32, 0)] + rs[4:]), "2 relocation(s) inside")
    refused("no bootinfo record at +0x46", with_rela(
        stock, lambda rs: rs[:2] + [(0x330, 3, R_68K_32, 0)] + rs[3:]), "bootinfo")
    b = bytearray(stock)
    kk = Kernel(stock)
    so = kk.S[kk.index(".symtab")]["offset"]
    struct.pack_into(">I", b, so + 1 * SYMSIZE + 8, 0xa8)     # autocon st_size
    refused("autocon of another size", bytes(b), "autocon size")
    b = bytearray(stock)
    b[so + 1 * SYMSIZE + 12] = 0x02                            # LOCAL FUNC
    refused("autocon not GLOBAL", bytes(b), "not a GLOBAL FUNC")
    b = bytearray(stock)
    st = kk.S[kk.index(".strtab")]["offset"]
    b[st + 1:st + 8] = b"autocom"
    refused("no autocon symbol at all", bytes(b), "autocon: 0 found")
    b = bytearray(stock)
    struct.pack_into(">H", b, 16, 2)                           # ET_EXEC
    refused("not an ET_REL", bytes(b), "not an m68k ET_REL")
    b = bytearray(stock)
    to = kk.S[kk.index(".text")]["offset"]
    struct.pack_into(">I", b, kk.e_shoff + 1 * SHSIZE + 20, 0x3fe)   # .text size odd
    refused(".text size not 4-aligned", bytes(b), "4-aligned")

    print("idempotency (c)")
    refused("a stock-shaped kernel with the fingerprint elsewhere (in .data)",
            synthetic_stock_kernel(stray=bytes.fromhex("00dd0041") + bytes.fromhex("00dd0043")),
            "fingerprint already present")
    out, f = inject(stock)
    refused("the injector's own output", out, "fingerprint already present")
    try:
        locate_injected(stock)
        ok("verify refuses the stock kernel", False, "accepted")
    except Refused as e:
        ok("verify refuses the stock kernel", "no detour" in "; ".join(e.args[0]))

    print("the edit (d, e, f, g)")
    ko, kn = Kernel(stock), Kernel(out)
    a = 0x120
    g = a + GUESS_OFF
    pa = f["probe_at"]
    ot, nt = ko.bytes_of(1), kn.bytes_of(1)
    ok("the probe lands at the input's .text end", pa == len(ot))
    ok(".text grew by exactly the padded probe", len(nt) == len(ot) + PROBE_PAD)
    ok("the guess site is bra.l + 16 nops",
       u16(nt, g) == BRA_L and nt[g + 6:g + GUESS_LEN] == NOP * 16)
    ok("the bra.l displacement reaches the probe", g + 2 + s32(nt, g + 2) == pa)
    tail = nt[pa:pa + len(PROBE)]
    ok("the tail is the payload outside the three exit fields",
       all(tail[i] == PROBE[i] for i in range(len(PROBE))
           if not any(o + 2 <= i < o + 6 for o, _, _ in PROBE_EXITS)))
    ok("bne.l at +0x06 exits to autocon+0x42",
       pa + 0x06 + 2 + s32(nt, pa + 0x08) == a + TABLE_OFF)
    ok("beq.l at +0x66 exits to autocon+0x42",
       pa + 0x66 + 2 + s32(nt, pa + 0x68) == a + TABLE_OFF)
    ok("bra.l at +0x74 exits to autocon+0xa0",
       pa + 0x74 + 2 + s32(nt, pa + 0x76) == a + EPILOGUE_OFF)
    ok("the pad after the probe is nops", nt[pa + len(PROBE):] == NOP)
    ok("(e) SASR/SCMD each exactly once in the whole file",
       [out.count(p) for _, p in WD7_PATTERNS] == [1, 1])
    ok("(e) the ports sit at the moveal immediates, probe+0x26 / +0x2c",
       nt[pa + 0x26:pa + 0x2a] == PROBE_PORTS[0][1] and nt[pa + 0x2c:pa + 0x30] == PROBE_PORTS[1][1])
    ok("(f) .text identical outside the guess site and the tail",
       nt[:g] == ot[:g] and nt[g + GUESS_LEN:pa] == ot[g + GUESS_LEN:pa])
    same = [ko.names[i] for i in range(ko.e_shnum) if i not in (1, 6)
            and ko.bytes_of(i) == kn.bytes_of(i)]
    ok("(f) every other section byte-identical (%d of %d)" % (len(same), ko.e_shnum - 2),
       len(same) == ko.e_shnum - 2)
    orl, nrl = ko.relocs(".rela.text"), kn.relocs(".rela.text")
    ok("(g) the end record is gone", not any(r[0] == a + END_RELOC_OFF for r in nrl))
    ok("(g) every other .rela.text record present, same order, same fields",
       nrl == orl[:1] + orl[2:])
    ok("(g) .rela.data untouched", ko.relocs(".rela.data") == kn.relocs(".rela.data"))
    ok("(g) no relocation covers the detour or the probe",
       not any(g <= r[0] < g + GUESS_LEN or pa <= r[0] < pa + PROBE_PAD for r in nrl))
    ok("symbols identical (autocon keeps address and size; the probe has none)",
       ko.symbols() == kn.symbols())
    moved = {ko.names[i]: kn.S[i]["offset"] - ko.S[i]["offset"] for i in range(1, ko.e_shnum)}
    ok("offsets: .text 0, then +124 up to .rela.text, +112 after it (bss follows .comment)",
       moved == {".text": 0, ".data": 124, ".bss": 124, ".comment": 124, ".shstrtab": 124,
                 ".rela.text": 124, ".rela.data": 112, ".symtab": 112, ".strtab": 112},
       repr(moved))
    ok("e_shoff moved with the table (+124)", kn.e_shoff == ko.e_shoff + 124)
    ok("sizes: only .text (+124) and .rela.text (-12) changed",
       all(kn.S[i]["size"] - ko.S[i]["size"] == {1: 124, 6: -12}.get(i, 0)
           for i in range(ko.e_shnum)))
    pad_o = ko.e_shoff - (ko.S[5]["offset"] + ko.S[5]["size"])
    pad_n = kn.e_shoff - (kn.S[5]["offset"] + kn.S[5]["size"])
    ok("the alignment pad before the header table is preserved (%d bytes)" % pad_o,
       pad_o == pad_n > 0 and stock[ko.e_shoff - pad_o:ko.e_shoff] == out[kn.e_shoff - pad_n:kn.e_shoff]
       and kn.e_shoff % 4 == 0)
    ok("file size = input + 124 - 12", len(out) == len(stock) + PROBE_PAD - RELASIZE)
    vf = locate_injected(out)
    ok("verify accepts the output and finds the probe where it was put",
       vf["probe_at"] == pa and vf["autocon"] == a)
    out2, f2 = inject(synthetic_stock_kernel(shdr_last=True))
    k2 = Kernel(out2)
    ok("a kernel with the header table last also re-lays out (e_shoff +112)",
       k2.e_shoff == Kernel(synthetic_stock_kernel(shdr_last=True)).e_shoff + 112
       and locate_injected(out2)["probe_at"] == f2["probe_at"])
    out3, _ = inject(synthetic_stock_kernel(text_len=0x1000, autocon_at=0x800))
    ok("autocon elsewhere in a larger .text: verify follows the detour",
       locate_injected(out3)["autocon"] == 0x800)

    # the post-condition must be enforced, not merely true
    class Tamper(Refused):
        pass
    try:
        bad = bytearray(out)
        bad[kn.S[2]["offset"] + 5] ^= 0xff                    # one .data byte
        check_edit(stock, bytes(bad), f)
        ok("check_edit catches a changed byte outside .text/.rela.text", False, "no complaint")
    except Refused as e:
        ok("check_edit catches a changed byte outside .text/.rela.text",
           any(".data: bytes changed" in p for p in e.args[0]))
    try:
        bad = bytearray(out)
        bad[kn.S[1]["offset"] + 0x30] ^= 0xff                 # a .text byte outside both ranges
        check_edit(stock, bytes(bad), f)
        ok("check_edit catches a .text byte outside the guess site and the tail", False)
    except Refused as e:
        ok("check_edit catches a .text byte outside the guess site and the tail",
           any("outside the guess site" in p for p in e.args[0]))

    objdump = shutil.which("m68k-linux-gnu-objdump")
    if objdump:
        td = tempfile.mkdtemp(prefix="probe-inject-selftest.")
        try:
            p = os.path.join(td, "k")
            with open(p, "wb") as fh:
                fh.write(out)
            lst = subprocess.run([objdump, "-d", "--start-address=0x%x" % g,
                                  "--stop-address=0x%x" % (pa + PROBE_PAD), p],
                                 capture_output=True, text=True).stdout
            ok("(d) objdump: the guess site decodes to bral into the probe",
               ("bral %x" % pa) in lst.replace("  ", " "), lst[:200])
            ok("(d) objdump: both port immediates decode as moveal in the tail",
               "moveal #14483521,%a0" in lst and "moveal #14483523,%a1" in lst)
            ok("(d) objdump: the tail's exits decode to autocon+0x42 / +0xa0",
               ("%x <autocon+0x42>" % (a + 0x42)) in lst and ("%x <autocon+0xa0>" % (a + 0xa0)) in lst,
               lst[-600:])
        finally:
            shutil.rmtree(td, ignore_errors=True)
    else:
        print("  (objdump not on PATH: the (d) disassembly checks skipped; bytes were compared)")

    print("command line")
    td = tempfile.mkdtemp(prefix="probe-inject-selftest.")
    try:
        src, dst = os.path.join(td, "stock"), os.path.join(td, "out")
        with open(src, "wb") as fh:
            fh.write(stock)
        me = os.path.abspath(__file__)
        r = subprocess.run([sys.executable, me, "show", src], capture_output=True, text=True)
        ok("show: STOCK (injectable), exit 0", r.returncode == 0 and "STOCK" in r.stdout)
        r = subprocess.run([sys.executable, me, "verify", src], capture_output=True, text=True)
        ok("verify on stock: exit 1, REFUSED", r.returncode == 1 and "REFUSED" in r.stdout)
        r = subprocess.run([sys.executable, me, "inject", src, "-o", dst], capture_output=True,
                           text=True)
        ok("inject: exit 0, PASS, output written",
           r.returncode == 0 and "PASS" in r.stdout and os.path.exists(dst)
           and open(dst, "rb").read() == out, r.stdout + r.stderr)
        r = subprocess.run([sys.executable, me, "inject", src, "-o", dst], capture_output=True,
                           text=True)
        ok("inject onto an existing -o without --force: exit 2", r.returncode == 2)
        r = subprocess.run([sys.executable, me, "inject", dst, "-o", dst + "2"],
                           capture_output=True, text=True)
        ok("inject of the injected output: exit 1, REFUSED, no file",
           r.returncode == 1 and "REFUSED" in r.stdout and not os.path.exists(dst + "2"))
        r = subprocess.run([sys.executable, me, "show", dst], capture_output=True, text=True)
        ok("show on the output: INJECTED, exit 0", r.returncode == 0 and "INJECTED" in r.stdout)
        r = subprocess.run([sys.executable, me, "verify", dst], capture_output=True, text=True)
        ok("verify on the output: exit 0, PASS", r.returncode == 0 and "PASS" in r.stdout)
        bad = os.path.join(td, "bad")
        with open(bad, "wb") as fh:
            fh.write(b"not an elf" * 20)
        r = subprocess.run([sys.executable, me, "inject", bad, "-o", bad + ".out"],
                           capture_output=True, text=True)
        ok("inject on junk: exit 1, no file", r.returncode == 1 and not os.path.exists(bad + ".out"))
    finally:
        shutil.rmtree(td, ignore_errors=True)

    print()
    if fails:
        print("%s: SELFTEST FAIL -- %d of %d: %s" % (WHOAMI, len(fails), total[0], "; ".join(fails)))
        return 1
    print("%s: SELFTEST PASS -- %d checks" % (WHOAMI, total[0]))
    return 0


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv[:1] == ["--selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(prog=WHOAMI, description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("show", help="locate autocon(); say whether the kernel is stock or injected")
    p.add_argument("kernel")
    p = sub.add_parser("inject", help="write the probe (asserts the stock bytes first)")
    p.add_argument("kernel")
    p.add_argument("-o", "--out", required=True)
    p.add_argument("--force", action="store_true", help="overwrite an existing -o output")
    p = sub.add_parser("verify", help="require the kernel to carry the probe, fingerprint 1/1")
    p.add_argument("kernel")
    a = ap.parse_args(argv)
    if not a.cmd:
        ap.print_usage(sys.stderr)
        return 2
    return dict(show=cmd_show, inject=cmd_inject, verify=cmd_verify)[a.cmd](a)


if __name__ == "__main__":
    sys.exit(main())
