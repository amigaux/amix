#!/usr/bin/env python3
"""elf2brel-selftest.py -- prove tools/elf2brel.py's PC-relative static apply.

WHY THIS EXISTS.  The 030 line's kernels carry one relocation type (R_68K_32) and
elf2brel's job there is a pure repack: whatever it gets wrong, it gets wrong loudly (the
loader Gurus, `relsim` complains, the namelist gate refuses).  The 040/060 line changed
that.  Its kernel carries 330 PC-relative records, and elf2brel now RESOLVES them itself
-- computes S + A - P, writes the displacement into the section data, and tells the loader
nothing.  A wrong displacement there is not a Guru: it is a `bra` to the wrong address
inside the FPSP, i.e. a kernel that boots and then misbehaves arbitrarily.  There is no
downstream gate for it -- `relsim` reads RECORDS, and the records are gone by then.  So the
arithmetic, the refusals and the layout invariant have to be proven here, on synthetic ELFs
whose right answer is known by construction.

WHAT IT CHECKS

  applied      each width (PC8/PC16/PC32), positive and negative displacements, the
               field written at the right offset and the right width, byte-for-byte;
               the BRA.B `A = -1` reference-point shape the real kernel's single PC8
               record has; and a 68k `bsr.w` that objdump (if present) agrees points at
               the symbol.
  omitted      an applied PC-relative reloc leaves NO compact table entry, and every
               R_68K_32 record still does -- the emitted table is exactly the R_68K_32 set.
  refused      PC16/PC8 overflow (both signs, and the exact boundary on both sides);
               a PC-relative reloc whose SOURCE is outside .text (a record in .rela.data);
               whose TARGET is in .data / .bss / SHN_ABS / SHN_COMMON / SHN_UNDEF; and a
               field that runs off the end of .text.  Every one exits 1 and writes no file.
  prefilled    a zero field is applied; a field already holding exactly the computed
               displacement is accepted as already-applied and NOT added to a second time;
               any other non-zero content is fatal.
  layout       the brel payload is the input's .text || .rodata || .data byte-for-byte
               apart from the applied displacement bytes -- the invariant the whole
               static apply rests on.  Checked here against the INPUT, independently of
               elf2brel's own _assert_layout().
  030          a PC-relative-free kernel (the 030 shape) converts to a table containing
               every record it started with, and to text bytes identical to the input.
  grown        the 040/060 line's support.c probe injector's output (its
               kernel-support-probe-inject.py; skipped when that tool is not beside this
               one -- it is not part of kernel/k30): a .text grown by an appended tail of
               pre-resolved self-relative long branches with no relocation, a detour at the
               guess site, one R_68K_32 record fewer.  The layout invariant must hold as
               is: the detour and the tail ride into the payload verbatim, the table is
               exactly one entry shorter, every other applied field and entry unchanged.

  python3 tools/elf2brel-selftest.py [-v]

exit 0 = every case behaved; 1 = at least one did not.
"""
import importlib.util, io, os, shutil, struct, subprocess, sys, tempfile
from contextlib import redirect_stderr

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "elf2brel.py")

SHT_PROGBITS = 1; SHT_SYMTAB = 2; SHT_STRTAB = 3; SHT_RELA = 4; SHT_NOBITS = 8
SHF_WRITE = 1; SHF_ALLOC = 2; SHF_EXECINSTR = 4
SHN_UNDEF = 0; SHN_ABS = 0xfff1; SHN_COMMON = 0xfff2
R_68K_32 = 1; R_68K_PC32 = 4; R_68K_PC16 = 5; R_68K_PC8 = 6
EHSIZE = 52

# Section indices in the ELF _build() emits (fixed, so the cases can name them).
SEC_TEXT = 1; SEC_DATA = 2; SEC_BSS = 3


def load_tool():
    spec = importlib.util.spec_from_file_location("elf2brel", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------- the fixture --
def build(text=None, data=None, textrel=(), datarel=(), extra_syms=(), bsssize=32,
          zero_pcrel=True):
    """A minimal big-endian m68k ET_REL with the section shape elf2brel requires.

    Sections: NULL, .text, .data, .bss, .symtab, .strtab, .shstrtab, .rela.text,
    .rela.data -- indices 1..3 are the ones relocs name.

    Symbols (index -> where):
        0 <null>   1 t_zero (.text+0)     2 t_mid (.text+0x40)   3 t_hi (.text+0x100)
        4 d_sym (.data+0)                 5 b_sym (.bss+0)       6 a_sym (SHN_ABS)
        7 c_sym (SHN_COMMON)              8 u_sym (SHN_UNDEF)    9.. extra_syms
    `extra_syms` rows are (name, value, size, shndx).
    relocs are (r_offset, symidx, type, r_addend).
    """
    text = bytearray(b'\x4e\x71' * 256) if text is None else bytearray(text)   # NOPs
    data = bytearray(b'\x5a' * 64) if data is None else bytearray(data)

    # A real RELA object leaves the relocated field ZERO-FILLED (the addend lives in
    # r_addend), and the converter requires that.  The .text filler here is NOPs, so the
    # fixture has to zero the fields itself -- except where a case is deliberately testing
    # a pre-filled field.
    _W = {R_68K_PC32: 4, R_68K_PC16: 2, R_68K_PC8: 1}
    if zero_pcrel:
        for (off, si, ty, add) in textrel:
            if ty in _W and off + _W[ty] <= len(text):
                text[off:off + _W[ty]] = b'\0' * _W[ty]

    shnames = b'\0.text\0.data\0.bss\0.symtab\0.strtab\0.shstrtab\0.rela.text\0.rela.data\0'
    def shname(n): return shnames.index(b'\0' + n + b'\0') + 1

    syms = [(b'', 0, 0, 0, SHN_UNDEF),
            (b't_zero', 0x000, 4, 0x12, SEC_TEXT),
            (b't_mid',  0x040, 4, 0x12, SEC_TEXT),
            (b't_hi',   0x100, 4, 0x12, SEC_TEXT),
            (b'd_sym',  0x000, 4, 0x11, SEC_DATA),
            (b'b_sym',  0x000, 4, 0x11, SEC_BSS),
            (b'a_sym',  0x123, 0, 0x10, SHN_ABS),
            (b'c_sym',  4,     4, 0x11, SHN_COMMON),
            (b'u_sym',  0,     0, 0x10, SHN_UNDEF)]
    for (nm, val, sz, sx) in extra_syms:
        syms.append((nm, val, sz, 0x12, sx))

    strtab = b'\0'; stroff = {b'': 0}
    for row in syms:
        if row[0] and row[0] not in stroff:
            stroff[row[0]] = len(strtab); strtab += row[0] + b'\0'
    symtab = b''.join(struct.pack('>IIIBBH', stroff[n], v, sz, info, 0, sx)
                      for (n, v, sz, info, sx) in syms)

    def pack(rs):
        return b''.join(struct.pack('>IIi', off, (si << 8) | ty, add)
                        for (off, si, ty, add) in rs)
    rela_t = pack(textrel); rela_d = pack(datarel)

    body = [(b'.text', bytes(text)), (b'.data', bytes(data)), (b'.symtab', symtab),
            (b'.strtab', strtab), (b'.shstrtab', shnames),
            (b'.rela.text', rela_t), (b'.rela.data', rela_d)]
    off = EHSIZE; offs = {}; blob = b''
    for name, payload in body:
        offs[name] = off; blob += payload; off += len(payload)

    secs = [(0, 0, 0, 0, 0, 0, 0, 0),
            (shname(b'.text'), SHT_PROGBITS, SHF_ALLOC | SHF_EXECINSTR,
             offs[b'.text'], len(text), 0, 0, 0),
            (shname(b'.data'), SHT_PROGBITS, SHF_ALLOC | SHF_WRITE,
             offs[b'.data'], len(data), 0, 0, 0),
            (shname(b'.bss'), SHT_NOBITS, SHF_ALLOC | SHF_WRITE,
             offs[b'.data'] + len(data), bsssize, 0, 0, 0),
            (shname(b'.symtab'), SHT_SYMTAB, 0, offs[b'.symtab'], len(symtab), 5, 1, 16),
            (shname(b'.strtab'), SHT_STRTAB, 0, offs[b'.strtab'], len(strtab), 0, 0, 0),
            (shname(b'.shstrtab'), SHT_STRTAB, 0, offs[b'.shstrtab'], len(shnames), 0, 0, 0),
            (shname(b'.rela.text'), SHT_RELA, 0, offs[b'.rela.text'], len(rela_t), 4, 1, 12),
            (shname(b'.rela.data'), SHT_RELA, 0, offs[b'.rela.data'], len(rela_d), 4, 2, 12)]
    shoff = EHSIZE + len(blob)
    eh = bytearray(EHSIZE)
    eh[0:4] = b'\x7fELF'; eh[4] = 1; eh[5] = 2; eh[6] = 1
    struct.pack_into('>HHI', eh, 16, 1, 4, 1)                 # ET_REL, EM_68K, EV_CURRENT
    struct.pack_into('>III', eh, 24, 0, 0, shoff)
    struct.pack_into('>IHHHHHH', eh, 36, 0, EHSIZE, 0, 0, 40, len(secs), 6)
    sht = b''.join(struct.pack('>IIIIIIIIII', n, t, f, 0, o, sz, lk, inf, 4, es)
                   for (n, t, f, o, sz, lk, inf, es) in secs)
    return bytes(eh) + blob + sht, bytes(text), bytes(data)


# ------------------------------------------------------------------ the runner --
class Cases:
    def __init__(self, verbose=False):
        self.total = 0; self.fails = []; self.verbose = verbose

    def ok(self, name, cond, detail=""):
        self.total += 1
        if not cond:
            self.fails.append("%s%s" % (name, (": " + detail) if detail else ""))
        if self.verbose or not cond:
            print("    %-64s %s%s" % (name, "PASS" if cond else "FAIL",
                                      ("  " + detail) if detail and not cond else ""))

    def eq(self, name, got, want):
        self.ok(name, got == want, "got %r, want %r" % (got, want))


def convert(mod, blob):
    """Convert in-process.  Returns (out_bytes, conv) or raises Refused(message)."""
    err = io.StringIO()
    conv = mod.Elf2Brel(blob, whoami='elf2brel')
    try:
        with redirect_stderr(err):
            out = conv.convert()
    except SystemExit as e:
        raise Refused(err.getvalue().strip(), int(e.code or 0))
    return out, conv


class Refused(Exception):
    def __init__(self, msg, code):
        Exception.__init__(self, msg); self.msg = msg; self.code = code


def brel_table(out):
    """(entries, combined_offset, combined_size) read back out of an emitted brel."""
    shoff = struct.unpack_from('>I', out, 32)[0]
    def sh(i, f): return struct.unpack_from('>I', out, shoff + i * 40 + f)[0]
    n = sh(3, 20) // 8
    ents = [struct.unpack_from('>II', out, sh(3, 16) + k * 8) for k in range(n)]
    return ents, sh(1, 16), sh(1, 20)


def field(out, off, width):
    return int.from_bytes(out[EHSIZE + off:EHSIZE + off + width], 'big', signed=True)


# ------------------------------------------------------------------- the cases --
def case_applied(c, mod):
    """Each width, both signs: the displacement is written, and nothing is tabled."""
    print("\napplied displacements -- each width, positive and negative")
    # (name, type, width, r_offset, symidx, addend, expected displacement)
    #   sym values: t_zero=0x000, t_mid=0x040, t_hi=0x100
    rows = [
        ("PC32 forward",  R_68K_PC32, 4, 0x010, 3, 0,   0x100 - 0x010),
        ("PC32 backward", R_68K_PC32, 4, 0x110, 1, 0,   0x000 - 0x110),
        ("PC16 forward",  R_68K_PC16, 2, 0x020, 3, 0,   0x100 - 0x020),
        ("PC16 backward", R_68K_PC16, 2, 0x120, 2, 0,   0x040 - 0x120),
        ("PC8  forward",  R_68K_PC8,  1, 0x041, 2, -1,  0x040 - 1 - 0x041),
        ("PC8  backward", R_68K_PC8,  1, 0x061, 2, -1,  0x040 - 1 - 0x061),
        ("PC32 with a non-zero addend", R_68K_PC32, 4, 0x030, 2, 6, 0x040 + 6 - 0x030),
    ]
    for (name, ty, w, off, si, add, want) in rows:
        blob, text_in, _ = build(textrel=[(off, si, ty, add)])
        out, conv = convert(mod, blob)
        c.eq("%s: field at .text+0x%03x" % (name, off), field(out, off, w), want)
        c.eq("%s: no table entry" % name, len(brel_table(out)[0]), 0)
        c.eq("%s: applied count" % name, conv.pcrel_applied, 1)
        # every other byte of .text is the input's
        payload = out[EHSIZE:EHSIZE + len(text_in)]
        rest_ok = (payload[:off] == text_in[:off]
                   and payload[off + w:] == text_in[off + w:])
        c.ok("%s: rest of .text untouched" % name, rest_ok)

    # The real kernel's single PC8 record, reproduced exactly: BRA.B at X, displacement
    # byte at X+1, symbol 54 bytes back, A = -1 -> the CPU's insn+2 reference point.
    text = bytearray(b'\x4e\x71' * 256)
    text[0x40:0x42] = b'\x4e\x71'
    text[0x76:0x78] = b'\x60\x00'          # BRA.B, displacement byte at 0x77
    blob, text_in, _ = build(text=text, textrel=[(0x77, 2, R_68K_PC8, -1)])
    out, _ = convert(mod, blob)
    disp = field(out, 0x77, 1)
    c.eq("BRA.B shape: displacement byte", disp, 0x40 - 1 - 0x77)
    c.eq("BRA.B shape: CPU target (insn+2)+disp == symbol", 0x78 + disp, 0x40)
    c.eq("BRA.B shape: opcode byte untouched", out[EHSIZE + 0x76], 0x60)

    # objdump's opinion, when a m68k objdump happens to be installed: an independent
    # decoder must agree the emitted instruction branches to the symbol.
    objdump = shutil.which("m68k-linux-gnu-objdump") or shutil.which("m68k-elf-objdump")
    if objdump:
        text = bytearray(b'\x4e\x71' * 256)
        text[0x20:0x24] = b'\x61\x00\x00\x00'      # bsr.w, displacement word at 0x22
        blob, _, _ = build(text=text, textrel=[(0x22, 3, R_68K_PC16, 0)])
        out, _ = convert(mod, blob)
        with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as fh:
            fh.write(out[EHSIZE:EHSIZE + 0x200]); binpath = fh.name
        try:
            p = subprocess.run([objdump, "-D", "-b", "binary", "-m", "m68k:68040",
                                "--start-address=32", "--stop-address=36", binpath],
                               capture_output=True, text=True)
            line = [l for l in p.stdout.splitlines() if l.strip().startswith("20:")]
            c.ok("objdump decodes the emitted bsr.w as a branch to t_hi (0x100)",
                 bool(line) and "0x100" in line[0], (line[0].strip() if line else p.stdout[-80:]))
        finally:
            os.unlink(binpath)
    else:
        print("    (no m68k objdump on PATH -- decoder cross-check skipped)")


def case_boundaries(c, mod):
    """The exact accepted range, both sides, for PC16 and PC8 -- rel.c's numbers."""
    print("\nrange checks -- accepted at the boundary, refused one past it")
    #  disp = S + A - P, so with P fixed and S = t_zero = 0, A tunes the displacement.
    for (ty, w, lo, hi) in ((R_68K_PC16, 2, -32768, 32767), (R_68K_PC8, 1, -128, 127)):
        nm = {R_68K_PC16: 'PC16', R_68K_PC8: 'PC8'}[ty]
        P = 0x080
        for (label, disp, want_ok) in ((("%s max" % nm), hi, True),
                                       (("%s max+1" % nm), hi + 1, False),
                                       (("%s min" % nm), lo, True),
                                       (("%s min-1" % nm), lo - 1, False)):
            blob, _, _ = build(textrel=[(P, 1, ty, disp + P)])   # S=0 -> disp = A - P
            try:
                out, _ = convert(mod, blob)
                c.ok("%s (%d) accepted" % (label, disp), want_ok and field(out, P, w) == disp)
            except Refused as e:
                c.ok("%s (%d) refused" % (label, disp),
                     not want_ok and "does not fit" in e.msg and e.code == 1, e.msg[:70])


def case_not_intra_text(c, mod):
    """Anything not .text-to-.text is refused -- never applied, never tabled."""
    print("\nnon-intra-.text PC-relative relocations -- refused, never applied")
    # (a) SOURCE outside .text: a PC-relative record in .rela.data.
    blob, _, _ = build(datarel=[(0x10, 1, R_68K_PC32, 0)])
    try:
        convert(mod, blob)
        c.ok("PC-rel record in .rela.data refused", False, "converted instead")
    except Refused as e:
        c.ok("PC-rel record in .rela.data refused",
             "outside .text" in e.msg and e.code == 1, e.msg[:70])

    # (b) TARGET outside .text, one case per flavour of "not .text".
    for (label, si, needle) in (("target in .data", 4, "not .text"),
                                ("target in .bss", 5, "not .text"),
                                ("target SHN_ABS", 6, "SHN_ABS"),
                                ("target SHN_COMMON", 7, "SHN_COMMON"),
                                ("target SHN_UNDEF", 8, "SHN_UNDEF")):
        blob, _, _ = build(textrel=[(0x20, si, R_68K_PC32, 0)])
        try:
            convert(mod, blob)
            c.ok("%s refused" % label, False, "converted instead")
        except Refused as e:
            c.ok("%s refused" % label, needle in e.msg and e.code == 1, e.msg[:70])

    # (c) the field itself running off the end of .text.
    blob, text_in, _ = build(textrel=[(512 - 1, 1, R_68K_PC32, 0)])
    try:
        convert(mod, blob)
        c.ok("field running past the end of .text refused", False, "converted instead")
    except Refused as e:
        c.ok("field running past the end of .text refused",
             "past the end of .text" in e.msg and e.code == 1, e.msg[:70])

    # (d) an R_68K_32 record in .rela.data is of course still fine -- the refusals above
    #     must not have swallowed the ordinary case.
    blob, _, _ = build(datarel=[(0x10, 1, R_68K_32, 0)])
    out, conv = convert(mod, blob)
    c.eq("R_68K_32 in .rela.data still tabled", len(brel_table(out)[0]), 1)


def case_prefilled(c, mod):
    """Zero applies; already-correct is a no-op; anything else is fatal."""
    print("\nfield contents -- zero, already-applied, and neither")
    off, si, want = 0x020, 3, 0x100 - 0x020
    zero_blob, _, _ = build(textrel=[(off, si, R_68K_PC16, 0)])
    zero_out, zero_conv = convert(mod, zero_blob)
    c.eq("zero field: applied", zero_conv.pcrel_applied, 1)
    c.eq("zero field: displacement written", field(zero_out, off, 2), want)

    text = bytearray(b'\x4e\x71' * 256)
    text[off:off + 2] = want.to_bytes(2, 'big', signed=True)
    pre_blob, _, _ = build(text=text, textrel=[(off, si, R_68K_PC16, 0)], zero_pcrel=False)
    pre_out, pre_conv = convert(mod, pre_blob)
    c.eq("already-applied field: counted as already-held", pre_conv.pcrel_already, 1)
    c.eq("already-applied field: not applied again", pre_conv.pcrel_applied, 0)
    c.eq("already-applied field: value unchanged (no double-apply)",
         field(pre_out, off, 2), want)
    c.ok("already-applied input converts to the same brel as the zero-filled one",
         pre_out == zero_out)

    text[off:off + 2] = (want + 1).to_bytes(2, 'big', signed=True)
    bad_blob, _, _ = build(text=text, textrel=[(off, si, R_68K_PC16, 0)], zero_pcrel=False)
    try:
        convert(mod, bad_blob)
        c.ok("field holding something else refused", False, "converted instead")
    except Refused as e:
        c.ok("field holding something else refused",
             "neither zero-filled nor the computed displacement" in e.msg and e.code == 1,
             e.msg[:70])


def case_table_and_layout(c, mod):
    """The emitted table is exactly the R_68K_32 set; the payload is verbatim."""
    print("\ntable contents and .text layout")
    textrel = [(0x000, 1, R_68K_32, 0),          # tabled
               (0x010, 3, R_68K_PC32, 0),        # applied
               (0x020, 6, R_68K_32, 4),          # tabled, SHN_ABS -> MSB flag
               (0x030, 2, R_68K_PC16, 0),        # applied
               (0x038, 4, R_68K_32, 0)]          # tabled, .data symbol
    datarel = [(0x004, 1, R_68K_32, 0), (0x008, 5, R_68K_32, 0)]
    blob, text_in, data_in = build(textrel=textrel, datarel=datarel)
    out, conv = convert(mod, blob)
    ents, coff, csize = brel_table(out)
    c.eq("entries emitted == R_68K_32 records read", len(ents), 5)
    c.eq("PC-relative records applied", conv.pcrel_applied, 2)
    c.eq("combined section offset", coff, EHSIZE)
    c.eq("combined section size", csize, len(text_in) + len(data_in))
    offs = sorted(e[0] & 0x7fffffff for e in ents)
    c.eq("table offsets are the R_68K_32 sites (data bumped by textsize)",
         offs, sorted([0x000, 0x020, 0x038, len(text_in) + 0x004, len(text_in) + 0x008]))
    c.ok("no applied PC-relative offset appears in the table",
         not ({0x010, 0x030} & set(offs)))
    c.eq("SHN_ABS entry keeps the absolute-value flag",
         sum(1 for e in ents if e[0] & 0x80000000), 1)

    # layout: payload == input .text || .data, changed only at the two applied fields
    expect = bytearray(text_in)
    expect[0x010:0x014] = out[EHSIZE + 0x010:EHSIZE + 0x014]
    expect[0x030:0x032] = out[EHSIZE + 0x030:EHSIZE + 0x032]
    c.ok(".text payload == input .text outside the applied fields",
         out[EHSIZE:EHSIZE + len(text_in)] == bytes(expect))
    c.ok(".data payload == input .data, verbatim and immediately after .text",
         out[EHSIZE + len(text_in):EHSIZE + len(text_in) + len(data_in)] == data_in)

    # And the invariant must be enforced, not merely true: break the copy and require a
    # complaint.  (A future edit that pads or realigns .text is exactly this shape.)
    conv2 = mod.Elf2Brel(blob, whoami='elf2brel')
    conv2.read_elf(); conv2.process_symtab(); conv2.gen_reloc_table()
    bad = bytearray(conv2.write_elf())
    bad[EHSIZE + 0x100] ^= 0xff              # one byte, outside every applied field
    err = io.StringIO()
    try:
        with redirect_stderr(err):
            conv2._assert_layout(bytes(bad))
        c.ok("_assert_layout catches a payload byte that is not the input's", False,
             "no complaint")
    except SystemExit as e:
        c.ok("_assert_layout catches a payload byte that is not the input's",
             "differs from the input .text" in err.getvalue() and int(e.code or 0) == 1,
             err.getvalue().strip()[:70])


def case_030_shape(c, mod):
    """A PC-relative-free kernel: every record tabled, .text bit-identical."""
    print("\nthe 030 shape -- no PC-relative records at all")
    textrel = [(0x000, 1, R_68K_32, 0), (0x008, 2, R_68K_32, 0),
               (0x010, 6, R_68K_32, 0), (0x018, 7, R_68K_32, 0)]
    datarel = [(0x000, 3, R_68K_32, 0)]
    blob, text_in, data_in = build(textrel=textrel, datarel=datarel)
    out, conv = convert(mod, blob)
    ents, coff, csize = brel_table(out)
    c.eq("every record tabled", len(ents), 5)
    c.eq("nothing applied", conv.pcrel_applied + conv.pcrel_already, 0)
    c.ok(".text payload is bit-identical to the input",
         out[EHSIZE:EHSIZE + len(text_in)] == text_in)
    c.eq("e_type", struct.unpack_from('>H', out, 16)[0], 0xff00)
    c.eq("pcrel_summary() says nothing was applied",
         conv.pcrel_summary(), "PC-relative relocations: none")
    # An unknown (non-PC-relative) type must still be the hard error it always was.
    blob, _, _ = build(textrel=[(0x000, 1, 7, 0)])
    try:
        convert(mod, blob)
        c.ok("unknown relocation type still refused", False, "converted instead")
    except Refused as e:
        c.ok("unknown relocation type still refused",
             "bad relocation type 7" in e.msg and e.code == 1, e.msg[:70])


def case_grown_text(c, mod):
    """The 040/060 probe injector's grown .text converts with the layout invariant intact."""
    print("\ngrown .text -- the 040/060 probe injector's output")
    if not os.path.isfile(os.path.join(HERE, "kernel-support-probe-inject.py")):
        print("  SKIP: kernel-support-probe-inject.py is not beside this tool (the 040/060 line's)")
        return
    spec = importlib.util.spec_from_file_location(
        "inj", os.path.join(HERE, "kernel-support-probe-inject.py"))
    inj = importlib.util.module_from_spec(spec); spec.loader.exec_module(inj)
    stock = inj.synthetic_stock_kernel()
    grown, f = inj.inject(stock)
    out_s, conv_s = convert(mod, stock)
    out_g, conv_g = convert(mod, grown)
    ents_s, _, size_s = brel_table(out_s)
    ents_g, _, size_g = brel_table(out_g)
    g, pa, end_at = f["guess"], f["probe_at"], f["autocon"] + 0x24
    kg = inj.Kernel(grown); text_g = kg.bytes_of(kg.index(".text"))
    off = lambda e: e[0] & 0x7fffffff
    c.eq("combined section grew by the padded probe (124)", size_g - size_s, 124)
    c.eq("the table is exactly one entry shorter (the end record)", len(ents_s) - len(ents_g), 1)
    c.ok("the end record's slot is gone from the table", not any(off(e) == end_at for e in ents_g))
    c.eq("the same PC-relative fields applied (the detour and the tail carry none)",
         conv_g.pcrel_applied, conv_s.pcrel_applied)
    c.ok("the detour rides into the payload verbatim",
         out_g[EHSIZE + g:EHSIZE + g + 38] == text_g[g:g + 38])
    c.ok("the probe tail rides into the payload verbatim",
         out_g[EHSIZE + pa:EHSIZE + pa + 124] == text_g[pa:pa + 124])
    c.ok("no table entry covers the detour or the tail",
         not any(g <= off(e) < g + 38 or pa <= off(e) < pa + 124 for e in ents_g))
    c.ok(".text payload == the stock conversion's outside the guess site",
         out_g[EHSIZE:EHSIZE + g] == out_s[EHSIZE:EHSIZE + g]
         and out_g[EHSIZE + g + 38:EHSIZE + pa] == out_s[EHSIZE + g + 38:EHSIZE + pa])
    c.ok(".data payload verbatim, 124 further along",
         out_g[EHSIZE + pa + 124:EHSIZE + size_g] == out_s[EHSIZE + pa:EHSIZE + size_s])
    want = sorted(off(e) + (124 if off(e) >= pa else 0) for e in ents_s if off(e) != end_at)
    c.eq("every other entry present; .data entries bumped by 124",
         sorted(off(e) for e in ents_g), want)


def case_cli(c, mod):
    """The refusals must reach the command line: exit 1, and no output file left."""
    print("\ncommand line -- a refusal writes no artifact")
    td = tempfile.mkdtemp(prefix="elf2brel-selftest.")
    try:
        blob, _, _ = build(textrel=[(0x080, 1, R_68K_PC16, 100000 + 0x080)])
        src = os.path.join(td, "bad.elf"); dst = os.path.join(td, "bad.brel")
        with open(src, "wb") as fh:
            fh.write(blob)
        p = subprocess.run([sys.executable, TOOL, src, dst], capture_output=True, text=True)
        c.eq("overflowing kernel: exit status", p.returncode, 1)
        c.ok("overflowing kernel: says why", "does not fit" in p.stderr, p.stderr[:70])
        c.ok("overflowing kernel: no output file", not os.path.exists(dst))

        blob, _, _ = build(textrel=[(0x020, 3, R_68K_PC16, 0)])
        src = os.path.join(td, "good.elf"); dst = os.path.join(td, "good.brel")
        with open(src, "wb") as fh:
            fh.write(blob)
        p = subprocess.run([sys.executable, TOOL, "-v", src, dst], capture_output=True, text=True)
        c.eq("converting kernel: exit status", p.returncode, 0)
        c.ok("converting kernel: -v reports the static apply",
             "PC-relative statically applied: 1" in p.stderr, p.stderr[:70])
        c.ok("converting kernel: output written", os.path.exists(dst) and os.path.getsize(dst) > 0)
    finally:
        shutil.rmtree(td, ignore_errors=True)


def main(argv):
    verbose = "-v" in argv or "--verbose" in argv
    if [a for a in argv if a not in ("-v", "--verbose")]:
        sys.stderr.write("usage: elf2brel-selftest.py [-v]\n"); return 2
    mod = load_tool()
    c = Cases(verbose)
    for fn in (case_applied, case_boundaries, case_not_intra_text, case_prefilled,
               case_table_and_layout, case_030_shape, case_grown_text, case_cli):
        fn(c, mod)
    print("\n%s -- %d check(s), %d failure(s)%s"
          % ("SELFTEST PASS" if not c.fails else "SELFTEST FAIL",
             c.total, len(c.fails),
             "" if not c.fails else "\n  " + "\n  ".join(c.fails)))
    return 0 if not c.fails else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
