#!/usr/bin/env python3
"""kernel-cputype-stamp.py -- stamp the 68040/68060 CPU class into an 040-line AMIX kernel.

    ./tools/kernel-cputype-stamp.py show   <kernel>
    ./tools/kernel-cputype-stamp.py stamp  <kernel> --cputype {40|60} [-o <out>]
    ./tools/kernel-cputype-stamp.py verify <kernel> --cputype {40|60}
    ./tools/kernel-cputype-stamp.py --selftest

WHY THIS EXISTS.  The 040/060 kernel line carries a `cputype` global (40 = 68040, the
built-in default; 60 = 68060) and every CPU-gated path in it dispatches on that word:
`ptest040` executes `ptestr`/`movec %mmusr` -- instructions the 68060 does not implement --
whenever it reads 40, so a 68060 booted on a kernel left at 40 takes a hard trap at the
first user page fault.  Nothing in the kernel ever writes the word.  Upstream it is poked
by an AmigaOS-resident loader (`unix_boot040`); our chain has no AmigaOS in it and
`boot2-040` cannot source the answer either -- AttnFlags bit 7 (AFB_68060) is set only by
68060.library/SetPatch, so on a native boot the bit that would distinguish the two CPUs is
simply not set.  Until the kernel learns to probe for itself, the 040 and the 060 are two
STAMPED IMAGES of one link, and this is the stamp.

THE OFF-BY-FOUR TRAP, which is the whole reason this is a tool and not a `dd`.

`cputype` is a size-0 NOTYPE GLOBAL in `.data` (src/cputype060.s declares `.globl cputype`
with no `.type`/`.size`), and the very next long is `pcr_boot` -- the 68060 Processor
Configuration Register as captured at boot, whose 0xFFFFFFFF value is a SENTINEL meaning
"never read".  A writer that resolves the symbol and then writes four bytes at the wrong
end of it destroys the only thing that distinguishes "PCR not measured" from "PCR measured
as zero", and destroys it silently: the kernel still boots, the diagnostic just lies
forever after.  Because the symbol has no size, nothing in the ELF stops that write.

So the site is proved from BOTH longs before a byte is written:

    [site]     must read 0x00000028   -- cputype, at its built-in default of 40
    [site + 4] must read 0xFFFFFFFF   -- the pcr_boot sentinel, unwritten

and `pcr_boot` must additionally RESOLVE, as a symbol, to exactly site + 4.  Any deviation
is a refusal.  The pair is what makes the site self-identifying; either half alone is a
coincidence.  A consequence worth stating: this refuses to re-stamp an already-stamped
image (its first long no longer reads 40).  That is deliberate -- every variant is stamped
from the pristine base, never from another variant, so a mis-stamp cannot propagate.

HOW THE SITE IS FOUND.  By SYMBOL, never by a hardcoded offset.  The 040-line kernel is an
ET_REL that retains its full `.symtab` (some 16 000 entries), so the
lookup is exact; the resulting file offset is an OUTPUT of
this tool and moves with every relink.  It is never an input.

WHAT IT NEVER TOUCHES.  `pcr_boot`, and every other byte in the file.  The post-write check
is not "the word reads back" but "the file differs from its input in exactly the four bytes
at the site" -- a whole-image comparison, so a truncating or re-writing bug cannot pass.

exit 0 = pass, 1 = refusal / mismatch (the fail-closed verdict), 2 = usage or unreadable
input.
"""
import argparse
import hashlib
import os
import struct
import subprocess
import sys
import tempfile

WHOAMI = "kernel-cputype-stamp"

# ELF constants, only the ones we index with.
ET_REL = 1
EM_68K = 4
SHT_PROGBITS = 1
SHT_SYMTAB = 2
SHT_RELA = 4
SHT_REL = 9
SHF_WRITE = 0x1
SHF_ALLOC = 0x2
SHN_UNDEF = 0
SHN_LORESERVE = 0xff00
STB_GLOBAL = 1
STT_NOTYPE = 0
STT_OBJECT = 1
SHDR_SIZE = 40
SYMENT_SIZE = 16
RELOC_SLOT = 4                 # an R_68K_32 slot is 4 bytes wide -- overlap, not containment

CPUTYPE_SYM = "cputype"
SENTINEL_SYM = "pcr_boot"
SENTINEL_DELTA = 4             # pcr_boot sits immediately after cputype
CPUTYPE_DEFAULT = 40           # the built-in default the base link must still carry
SENTINEL_UNWRITTEN = 0xFFFFFFFF
VALID_CPUTYPES = (40, 60)
SITE_SPAN = 8                  # cputype (4) + pcr_boot (4): the range we prove and protect


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


# ------------------------------------------------------------------- ELF walk --

class Elf(object):
    """Just enough big-endian ELF32 to find a symbol's bytes and the relocations over them.

    Every structural surprise is a refusal rather than an exception: this runs as a gate,
    and a traceback is not a verdict."""

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
            refuse("%s: e_type 0x%x, want ET_REL (1) -- the 040 line is a relocatable link;"
                   " a brel has no .symtab and this tool locates by symbol only"
                   % (path, self.e_type))
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
            refuse("%s: expected exactly one `%s` section, found %d"
                   % (self.path, name, len(found)))
        return found[0]

    def symtab(self):
        tabs = [s for s in self.secs if s["type"] == SHT_SYMTAB]
        if len(tabs) != 1:
            refuse("%s: expected exactly one SHT_SYMTAB, found %d -- the 040 line retains its"
                   " symbol table; an image without one cannot be located by symbol"
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
            st_name = u32(self.buf, b)
            st_value = u32(self.buf, b + 4)
            st_size = u32(self.buf, b + 8)
            st_info = self.buf[b + 12]
            st_shndx = u16(self.buf, b + 14)
            if self._str(strtab, st_name) != name:
                continue
            if (st_info >> 4) != STB_GLOBAL:
                continue
            if st_shndx == SHN_UNDEF or st_shndx >= SHN_LORESERVE:
                continue
            out.append(dict(value=st_value, size=st_size, typ=st_info & 0xf, shndx=st_shndx))
        return out

    def reloc_hits(self, sec, lo, hi):
        """Relocation entries targeting `sec` whose 4-byte slot overlaps [lo, hi).

        Overlap, not containment: a relocation whose slot starts one byte before the range
        still rewrites bytes inside it at load time."""
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
                if r_off < hi and r_off + RELOC_SLOT > lo:
                    hits.append((s["nm"], r_off))
        return hits


# ------------------------------------------------------------------- the site --

def locate(buf, path):
    """Resolve the cputype site, or refuse.  Returns a dict of facts, nothing written."""
    elf = Elf(buf, path)
    data = elf.section(".data")
    if data["type"] != SHT_PROGBITS or not (data["flags"] & SHF_WRITE):
        refuse("%s: `.data` is not a writable PROGBITS section (type %d flags 0x%x)"
               % (path, data["type"], data["flags"]))

    def one(name):
        defs = elf.global_defs(name)
        if len(defs) != 1:
            refuse("%s: expected exactly one GLOBAL definition of `%s`, found %d"
                   % (path, name, len(defs)),
                   "the 040 line defines it once, in src/cputype060.s")
        d = defs[0]
        if d["shndx"] != data["idx"]:
            refuse("%s: `%s` is defined in section %d, not `.data` (%d)"
                   % (path, name, d["shndx"], data["idx"]))
        # Today the symbols are size-0 NOTYPE (no .type/.size in the .s).  A future upstream
        # that declares them properly gives size-4 OBJECT.  Anything else means the shape we
        # reason about has changed, and the whole point here is not to guess.
        if not ((d["size"] == 0 and d["typ"] == STT_NOTYPE)
                or (d["size"] == 4 and d["typ"] == STT_OBJECT)):
            refuse("%s: `%s` has st_type %d st_size %d -- expected size-0 NOTYPE (today's"
                   " src/cputype060.s) or size-4 OBJECT (a properly declared successor)"
                   % (path, name, d["typ"], d["size"]))
        return d

    cpu = one(CPUTYPE_SYM)
    sen = one(SENTINEL_SYM)
    if sen["value"] != cpu["value"] + SENTINEL_DELTA:
        refuse("%s: `%s` resolves to +0x%x from `%s`, expected +0x%x"
               % (path, SENTINEL_SYM, sen["value"] - cpu["value"], CPUTYPE_SYM, SENTINEL_DELTA),
               "the sentinel's adjacency is half of what identifies the site; if the two have"
               "\nbeen separated, the off-by-four this tool exists to refuse is no longer the"
               "\nfailure mode it was written against -- re-derive before writing anything")

    off = data["off"] + (cpu["value"] - data["addr"])
    if not (data["off"] <= off and off + SITE_SPAN <= data["off"] + data["size"]):
        refuse("%s: the site 0x%x+%d does not lie wholly inside `.data` [0x%x, 0x%x)"
               % (path, off, SITE_SPAN, data["off"], data["off"] + data["size"]))
    if off + SITE_SPAN > len(buf):
        refuse("%s: the site 0x%x+%d lies past the end of the file" % (path, off, SITE_SPAN))

    hits = elf.reloc_hits(data, cpu["value"], cpu["value"] + SITE_SPAN)
    if hits:
        refuse("%s: %d relocation(s) overlap [%s, %s+8)" % (path, len(hits), CPUTYPE_SYM,
                                                            CPUTYPE_SYM),
               "\n".join("  %s r_offset 0x%x" % h for h in hits) +
               "\na relocated site is rewritten at load time, so a stored byte there is not the"
               "\nvalue the kernel runs with -- patching it would be theatre")

    return dict(path=path, off=off, addr=cpu["value"], data_off=data["off"],
                data_addr=data["addr"], cputype=u32(buf, off), sentinel=u32(buf, off + 4),
                cputype_size=cpu["size"], cputype_type=cpu["typ"], relocs=len(hits))


def assert_pristine(site):
    """The both-longs assertion.  Nothing may be written until this passes."""
    bad = []
    if site["cputype"] != CPUTYPE_DEFAULT:
        bad.append("  cputype  @0x%08x reads 0x%08x, expected 0x%08x (%d, the built-in default)"
                   % (site["off"], site["cputype"], CPUTYPE_DEFAULT, CPUTYPE_DEFAULT))
    if site["sentinel"] != SENTINEL_UNWRITTEN:
        bad.append("  %-8s @0x%08x reads 0x%08x, expected 0x%08x (the unwritten sentinel)"
                   % (SENTINEL_SYM, site["off"] + 4, site["sentinel"], SENTINEL_UNWRITTEN))
    if bad:
        refuse("%s: the site does not read as a pristine base link" % site["path"],
               "\n".join(bad) +
               "\n\nBOTH longs must match before a byte is written.  Either this image has"
               "\nalready been stamped -- stamp every variant from the pristine base, never"
               "\nfrom another variant -- or the site moved and the symbol now names something"
               "\nelse.  Rebuild, or re-derive; do not override.")


# --------------------------------------------------------------------- output --

def sha256(buf):
    return hashlib.sha256(buf).hexdigest()


def print_site(site, buf):
    print("%s: %s" % (WHOAMI, site["path"]))
    print("  size          %d bytes   sha256 %s" % (len(buf), sha256(buf)))
    print("  .data         file offset 0x%08x  sh_addr 0x%08x"
          % (site["data_off"], site["data_addr"]))
    print("  %-13s sh_addr+0x%08x -> file offset 0x%08x  (st_type %d, st_size %d)"
          % (CPUTYPE_SYM, site["addr"], site["off"], site["cputype_type"], site["cputype_size"]))
    print("  cputype       0x%08x  (%d)%s"
          % (site["cputype"], site["cputype"],
             "" if site["cputype"] in VALID_CPUTYPES else "   <- NOT a valid CPU class"))
    print("  %-13s 0x%08x  %s" % (SENTINEL_SYM, site["sentinel"],
                                  "UNWRITTEN (sentinel intact)"
                                  if site["sentinel"] == SENTINEL_UNWRITTEN
                                  else "*** NOT the sentinel ***"))
    print("  relocations   %d overlapping the 8-byte site" % site["relocs"])


# ------------------------------------------------------------------- commands --

def cmd_show(path):
    buf = read_file(path)
    print_site(locate(buf, path), buf)
    return 0


def cmd_verify(path, want):
    buf = read_file(path)
    site = locate(buf, path)
    bad = []
    if site["cputype"] != want:
        bad.append("  cputype  @0x%08x reads %d, expected %d"
                   % (site["off"], site["cputype"], want))
    if site["sentinel"] != SENTINEL_UNWRITTEN:
        bad.append("  %s @0x%08x reads 0x%08x, expected 0x%08x -- the sentinel was overwritten"
                   % (SENTINEL_SYM, site["off"] + 4, site["sentinel"], SENTINEL_UNWRITTEN))
    if bad:
        refuse("%s: not a cputype-%d image" % (path, want), "\n".join(bad))
    print("%s: OK  %s  cputype=%d  %s=0x%08x (sentinel intact)  sha256 %s"
          % (WHOAMI, path, want, SENTINEL_SYM, site["sentinel"], sha256(buf)))
    return 0


def cmd_stamp(path, want, out):
    buf = read_file(path)
    site = locate(buf, path)
    assert_pristine(site)

    off = site["off"]
    new = bytearray(buf)
    struct.pack_into(">I", new, off, want)
    new = bytes(new)

    dest = out or path
    tmp = dest + ".cputype-stamp.tmp"
    try:
        with open(tmp, "wb") as fh:
            fh.write(new)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, dest)
    except OSError as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        die("cannot write %s: %s" % (dest, e))

    # Re-read from disk.  The check is a WHOLE-IMAGE comparison, not "the word reads back":
    # a writer that also truncated, padded or rewrote something else would pass the narrow
    # check and fail this one.
    back = read_file(dest)
    site2 = locate(back, dest)
    diff = [i for i in range(min(len(buf), len(back))) if buf[i] != back[i]]
    problems = []
    if len(back) != len(buf):
        problems.append("  file size changed: %d -> %d" % (len(buf), len(back)))
    stray = [d for d in diff if not (off <= d < off + 4)]
    if stray:
        problems.append("  %d byte(s) outside the site changed: %s%s -- the only bytes this"
                        " tool may move are [0x%x, 0x%x)"
                        % (len(stray), ", ".join("0x%x" % d for d in stray[:8]),
                           " ..." if len(stray) > 8 else "", off, off + 4))
    if site2["cputype"] != want:
        problems.append("  cputype reads back %d, wrote %d" % (site2["cputype"], want))
    if site2["sentinel"] != SENTINEL_UNWRITTEN:
        problems.append("  %s reads back 0x%08x -- the sentinel was disturbed"
                        % (SENTINEL_SYM, site2["sentinel"]))
    if problems:
        refuse("%s: the write did not land as intended" % dest, "\n".join(problems))

    print("%s: stamped %s" % (WHOAMI, dest))
    print("  cputype  @0x%08x  %d -> %d   (4 bytes, and only those 4)"
          % (off, CPUTYPE_DEFAULT, want))
    print("  %-8s @0x%08x  0x%08x  untouched" % (SENTINEL_SYM, off + 4, site2["sentinel"]))
    print("  sha256   %s  ->  %s" % (sha256(buf), sha256(back)))
    return 0


def read_file(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError as e:
        die("cannot read %s: %s" % (path, e))


# ------------------------------------------------------------------ selftest --
#
# Hermetic: every fixture is a synthetic big-endian ELF32 ET_REL built here, so the suite
# needs no kernel, no toolchain and no work/ artifact.  It exists to hold the ONE assertion
# this tool is for -- both longs, checked before any write -- plus the refusals around it.

def _mkelf(cputype=CPUTYPE_DEFAULT, sentinel=SENTINEL_UNWRITTEN, sentinel_delta=4,
           cputype_bind=STB_GLOBAL, cputype_shndx=None, cputype_size=0,
           cputype_type=STT_NOTYPE, drop_sentinel=False, drop_symtab=False,
           reloc_at=None, e_type=ET_REL, e_machine=EM_68K, little=False,
           dup_cputype=False, pad=0x40):
    """Build a minimal ELF: .text, .data (holding the site), optional .rela.data, .symtab."""
    names = [b"", b".text", b".data", b".shstrtab", b".symtab", b".strtab", b".rela.data"]
    shstr = b"\0".join(names) + b"\0"
    noff = {}
    p = 0
    for n in names:
        noff[n] = p
        p += len(n) + 1

    site_addr = 0x20                      # where cputype sits inside .data
    data = bytearray(pad + 16)
    struct.pack_into(">I", data, site_addr, cputype & 0xffffffff)
    struct.pack_into(">I", data, site_addr + 4, sentinel & 0xffffffff)
    text = b"\x4e\x71" * 8

    symnames = [b"", CPUTYPE_SYM.encode(), SENTINEL_SYM.encode()]
    strtab = b"\0".join(symnames) + b"\0"
    soff = {}
    p = 0
    for n in symnames:
        soff[n] = p
        p += len(n) + 1

    DATA_IDX = 2
    shndx = DATA_IDX if cputype_shndx is None else cputype_shndx
    syms = [(0, 0, 0, 0, 0, 0)]           # the mandatory null symbol
    syms.append((soff[CPUTYPE_SYM.encode()], site_addr, cputype_size,
                 (cputype_bind << 4) | cputype_type, 0, shndx))
    if dup_cputype:
        syms.append((soff[CPUTYPE_SYM.encode()], site_addr + 8, cputype_size,
                     (STB_GLOBAL << 4) | cputype_type, 0, DATA_IDX))
    if not drop_sentinel:
        syms.append((soff[SENTINEL_SYM.encode()], site_addr + sentinel_delta, 0,
                     (STB_GLOBAL << 4) | STT_NOTYPE, 0, DATA_IDX))
    endian = "<" if little else ">"
    symtab = b"".join(struct.pack(endian + "IIIBBH", *s) for s in syms)

    rela = b""
    if reloc_at is not None:
        rela = struct.pack(endian + "IIi", reloc_at, (1 << 8) | 1, 0)

    # Lay the payloads out, then the section header table last.
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
        (noff[b".text"], SHT_PROGBITS, SHF_ALLOC | 0x4, 0, t_off, len(text), 0, 0, 4, 0),
        (noff[b".data"], SHT_PROGBITS, SHF_ALLOC | SHF_WRITE, 0, d_off, len(data), 0, 0, 4, 0),
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

    def case(label, want_rc, args, path=None, blob=None, check=None):
        nonlocal n
        n += 1
        with tempfile.TemporaryDirectory(prefix="cputype-st-") as td:
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
            print("  %-58s %s%s" % (label, "ok" if ok else "FAIL", (" -- " + why) if why else ""))
            if not ok:
                fails.append(label)
                for line in out.strip().split("\n")[-6:]:
                    print("      | %s" % line)

    print("%s --selftest: the both-longs assertion, its refusals, and arg validation" % WHOAMI)
    print()
    print("the site and the assertion")

    base = _mkelf()

    def only_site_changed(want):
        def check(p, out):
            got = open(p, "rb").read()
            if len(got) != len(base):
                return "size changed %d -> %d" % (len(base), len(got))
            site = locate(got, p)
            stray = [i for i in range(len(base))
                     if base[i] != got[i] and not (site["off"] <= i < site["off"] + 4)]
            if stray:
                return "bytes outside the site changed: %s" % stray[:8]
            if u32(got, site["off"]) != want:
                return "cputype reads %d, want %d" % (u32(got, site["off"]), want)
            if u32(got, site["off"] + 4) != SENTINEL_UNWRITTEN:
                return "sentinel disturbed: 0x%08x" % u32(got, site["off"] + 4)
            return ""
        return check

    case("stamp 60 writes 4 bytes and only those 4", 0,
         ["stamp", "@", "--cputype", "60"], blob=base, check=only_site_changed(60))
    case("stamp 40 on the default is still a proved, verified write", 0,
         ["stamp", "@", "--cputype", "40"], blob=base, check=only_site_changed(40))
    case("stamp -o leaves the input untouched", 0,
         ["stamp", "@", "--cputype", "60", "-o", "@.out"], blob=base,
         check=lambda p, o: "" if open(p, "rb").read() == base else "input was modified")
    case("show reports the site without writing", 0, ["show", "@"], blob=base,
         check=lambda p, o: "" if open(p, "rb").read() == base else "show wrote to the file")

    print()
    print("REFUSALS -- the off-by-four trap and its neighbours")
    case("cputype long already 60 (a re-stamp) is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(cputype=60))
    case("cputype long garbage is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(cputype=0x2f646576))
    case("sentinel already written (off-by-four victim) is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(sentinel=0x04300000))
    case("sentinel zeroed is refused (zero != unmeasured)", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(sentinel=0))
    case("pcr_boot not adjacent (+8) is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(sentinel_delta=8))
    case("pcr_boot symbol absent is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(drop_sentinel=True))
    case("cputype not GLOBAL is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(cputype_bind=0))
    case("two GLOBAL cputype definitions are refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(dup_cputype=True))
    case("cputype defined outside .data is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(cputype_shndx=1))
    case("cputype with an unexpected type/size is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(cputype_size=8, cputype_type=STT_OBJECT))
    case("size-4 OBJECT (a properly declared successor) is accepted", 0,
         ["stamp", "@", "--cputype", "60"],
         blob=_mkelf(cputype_size=4, cputype_type=STT_OBJECT))
    case("no .symtab is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(drop_symtab=True))
    case("a relocation over cputype is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(reloc_at=0x20))
    case("a relocation over pcr_boot is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(reloc_at=0x24))
    case("a relocation overlapping the site by one byte is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(reloc_at=0x1d))
    case("a relocation just clear of the site is accepted", 0,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(reloc_at=0x1c))
    case("little-endian ELF is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(little=True))
    case("a non-m68k ELF is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(e_machine=3))
    case("a non-ET_REL ELF is refused (a brel has no symtab to locate by)", 1,
         ["stamp", "@", "--cputype", "60"], blob=_mkelf(e_type=0xff00))
    case("a non-ELF file is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=b"not an elf at all" * 8)
    case("a truncated ELF is refused", 1,
         ["stamp", "@", "--cputype", "60"], blob=base[:40])

    print()
    print("verify")
    case("verify accepts the value it was stamped with", 0,
         ["verify", "@", "--cputype", "40"], blob=base)
    case("verify rejects the other CPU class", 1,
         ["verify", "@", "--cputype", "60"], blob=base)
    case("verify rejects a disturbed sentinel even when cputype is right", 1,
         ["verify", "@", "--cputype", "40"], blob=_mkelf(sentinel=0))

    print()
    print("arg validation")
    case("no arguments is a usage error", 2, ["show"], blob=base)
    case("unknown subcommand is a usage error", 2, ["frobnicate", "@"], blob=base)
    case("--cputype 30 is refused (not a CPU class this line has)", 2,
         ["stamp", "@", "--cputype", "30"], blob=base)
    case("--cputype 0x28 is refused (decimal 40/60 only)", 2,
         ["stamp", "@", "--cputype", "0x28"], blob=base)
    case("stamp without --cputype is a usage error", 2, ["stamp", "@"], blob=base)
    case("verify without --cputype is a usage error", 2, ["verify", "@"], blob=base)
    case("a missing file is reported, not tracebacked", 2,
         ["show", "@-does-not-exist"], blob=base)

    print()
    if fails:
        print("%s SELFTEST FAIL -- %d/%d case(s) failed: %s"
              % (WHOAMI, len(fails), n, ", ".join(fails)))
        return 1
    print("%s: SELFTEST PASS -- %d/%d cases" % (WHOAMI, n, n))
    return 0


# ---------------------------------------------------------------------- main --

def cputype_arg(s):
    if s not in ("40", "60"):
        raise argparse.ArgumentTypeError(
            "must be 40 or 60 (decimal); the 040 line has exactly these two CPU classes")
    return int(s)


def main(argv):
    ap = argparse.ArgumentParser(
        prog="kernel-cputype-stamp.py",
        description="Stamp the 68040/68060 CPU class into an 040-line AMIX kernel.")
    ap.add_argument("--selftest", action="store_true",
                    help="run the hermetic selftest and exit")
    sub = ap.add_subparsers(dest="cmd")

    p = sub.add_parser("show", help="print the located site and both longs")
    p.add_argument("kernel")

    p = sub.add_parser("stamp", help="write the CPU class (asserts both longs first)")
    p.add_argument("kernel")
    p.add_argument("--cputype", type=cputype_arg, required=True)
    p.add_argument("-o", "--out", help="write here instead of in place")

    p = sub.add_parser("verify", help="require the image to carry this CPU class")
    p.add_argument("kernel")
    p.add_argument("--cputype", type=cputype_arg, required=True)

    if argv[1:2] == ["--selftest"]:
        return selftest()
    args = ap.parse_args(argv[1:])
    if args.selftest:
        return selftest()
    if not args.cmd:
        ap.print_usage(sys.stderr)
        return 2
    if args.cmd == "show":
        return cmd_show(args.kernel)
    if args.cmd == "stamp":
        return cmd_stamp(args.kernel, args.cputype, args.out)
    if args.cmd == "verify":
        return cmd_verify(args.kernel, args.cputype)
    ap.print_usage(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
