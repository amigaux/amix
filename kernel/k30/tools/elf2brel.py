#!/usr/bin/env python3
#
# elf2brel.py -- faithful, endian-explicit Python port of
#   amiga/boot/elf2brel.c  (Copyright (C) 1991 Commodore, patchlevel elf2brel.c_1.1)
#
# Converts a standard relocatable ELF kernel (ET_REL, e_type=0x1 -- the output of
# the top-level `ld -r -o unix ...` link) into the compact "brel" form the Amix
# boot loader (amiga/boot/rel.c, the ET_LOPROC / e_type=0xff00 path) consumes.
# The stock Amix on-box `amiga/boot/Makefile floppy:` target is literally
#     ./elf2brel < unix | compress | makeiblk
# so the boot floppy expects a brel kernel, NOT raw ET_REL -- a raw ET_REL kernel
# framed onto the floppy D245-Guru's during relocation because rel.c's ET_LOPROC
# branch (compactreloc) never runs for it.
#
# This is to elf2brel.c what tools/relsim.py is to amiga/boot/rel.c: a byte-for-byte
# faithful reimplementation.  It parses the big-endian m68k ELF with explicit
# struct.unpack('>...') rather than native byte order (elf2brel.c reads native
# structs because its 1991 build host was big-endian m68k; we must be explicit).
#
# WHAT THE TRANSFORM DOES (elf2brel.c header + verified against the code):
#   * Combine .text, .rodata, .data into one contiguous .text section written to
#     file; .bss is a zero-fill tail (NOT written -- its bytes are implied).
#   * ProcessSymtab: relocate every .text/.rodata/.data/.bss/COMMON symbol so its
#     st_value is an offset from the start of the combined section; allocate COMMON
#     symbols at the end (aligned); stamp etext/edata/end to their combined offsets
#     (shndx = combined .text, so the loader treats them as text-relative).
#   * GenRelocTable: fold .rela.text (+ .rela.rodata if present) + .rela.data into
#     ONE compact table.  Each compact entry is two 32-bit big-endian words:
#         nr_offset -- slot offset from the start of the combined section
#         nr_value  -- addend + referenced symbol's (combined-relative) value
#     The MSB (0x80000000) of nr_offset is HIJACKED as a flag: set => nr_value is an
#     absolute value (symbol was SHN_ABS); clear => nr_value is relative to the text
#     bind address (rel.c/compactreloc adds thdr->sh_addr).  rodata/data entry
#     offsets are bumped by textsize / textsize+rodatasize so they index into the
#     combined section.
#   * The reloc section's type becomes SHT_LOUSER (0x80000000) so normal tools skip
#     it; symtab + strtab are discarded.
#   * Emit: Elf32_Ehdr (e_type=ET_LOPROC=0xff00) + combined section + new shstrtab +
#     compact reloc table + exactly 4 section headers, in the byte layout
#     WriteElfFile() produces.  The loader hardcodes Shdrs+1 = combined text and
#     Shdrs+3 = compact reloc table, so that order is load-bearing.
#
# PC-RELATIVE RELOCATIONS -- STATICALLY APPLIED, NOT SKIPPED (the 040/060 kernel line):
#   The stock elf2brel.c knows exactly one relocation type, R_68K_32, and dies on anything
#   else -- which is correct for the 030 line (its kernels carry nothing else) and a hard
#   blocker for the 040/060 line, whose kernel carries 330 PC-relative records
#   (R_68K_PC16 223, R_68K_PC32 106, R_68K_PC8 1) out of 29 857.
#
#   Those 330 are all INTRA-.text: the record's r_offset is inside .text AND the symbol it
#   names is defined in .text.  A PC-relative displacement between two points of the same
#   section is INVARIANT under whole-image relocation -- S and P shift together, so S+A-P
#   does not depend on the load address.  It can therefore be resolved once, here, at
#   conversion time, and never mentioned to the loader again.
#
#   So this is an APPLY, not a skip.  The fields are RELA-style ZERO-FILLED in the input
#   (the addend lives in r_addend, not in the section data), so leaving them alone would
#   emit a kernel full of `bra.w 0` / `bsr.l 0` self-branches.  We compute S + A - P per
#   m68k ELF semantics -- P is the address of the FIELD, i.e. r_offset, and the assembler's
#   addend carries whatever bias the instruction's own reference point needs (the kernel's
#   single R_68K_PC8 is a BRA.B with A = -1, exactly the insn+2 reference point) -- WRITE it
#   into the section data at the field's natural width, and emit NO compact table entry.
#   The emitted brel therefore still contains R_68K_32 entries and nothing else, which is
#   what the stock rel.c can consume.
#
#   THREE THINGS THIS MUST NEVER DO QUIETLY, so all three are fatal:
#     * truncate an out-of-range PC16/PC8 displacement.  A truncated displacement is a
#       silent wild branch inside the kernel; a dead end here is very much the better
#       failure (the same reasoning as the 68040/68060 loader's rel.c patch).
#       The accepted ranges are rel.c's own: PC16 [-32768, 32767], PC8 [-128, 127].
#     * apply a PC-relative reloc that is NOT intra-.text (source or target outside .text).
#       That displacement is not invariant under load address, so no value written here can
#       be right.  Refused, never applied.
#     * double-apply.  A field that is already non-zero is only accepted when it already
#       holds exactly the computed displacement (idempotent re-conversion); any other
#       non-zero content is fatal, because we cannot tell a pre-biased field from a
#       corrupted one and adding to it would be a wild branch again.
#
#   And because the whole scheme rests on ".text does not move inside the combined
#   section", _assert_layout() re-reads the emitted image and requires it: the brel payload
#   must be the input's .text || .rodata || .data byte-for-byte, differing ONLY at the
#   displacement bytes this converter wrote -- no padding, no realignment, no reordering.
#
# ONE DELIBERATE DIVERGENCE FROM THE LITERAL C:
#   In GenRelocTable(), elf2brel.c leaves `nrodrel` UNINITIALIZED when there is no
#   .rela.rodata section (it is only assigned inside `if (i.i_rela_rodata > 0)`),
#   yet still uses it in `nrelcount = ntrel + nrodrel + ndrel`.  That is a latent
#   C bug that happens not to bite when .rela.rodata is always present (or the
#   stack happens to be zero).  Our cross-linked kernel has a .rodata section but
#   NO .rela.rodata, so we hit exactly that path.  The clear intent is "0 rodata
#   relocations", so we initialize nrodrel = 0.  This is the only place the port
#   does not mirror the C literally, and it mirrors the C's intent.
#
# USAGE:
#   elf2brel.py <in.elf> <out.brel>   # explicit file in/out (what build-cross-kernel.sh uses)
#   elf2brel.py <in.elf>              # in from file, brel to stdout
#   elf2brel.py                       # stdin -> stdout  (mirrors the on-box `elf2brel < unix`)
#   -v / --verbose : print a summary of sizes / counts / e_type to stderr
#
import sys, struct

# ---- ELF constants (elf.h / sys/elf_68K.h) --------------------------------
ET_REL      = 1
ET_LOPROC   = 0xff00        # the "brel" type stamped into e_type
SHT_LOUSER  = 0x80000000    # reloc section retyped to this so std tools ignore it
SHN_ABS     = 0xfff1
SHN_COMMON  = 0xfff2
R_68K_32    = 1             # the only relocation type the loader consumes from the table
R_68K_PC32  = 4             # PC-relative: statically applied here, never tabled
R_68K_PC16  = 5
R_68K_PC8   = 6
EHSIZE      = 52           # sizeof(Elf32_Ehdr)
SHSIZE      = 40           # sizeof(Elf32_Shdr)
SYMSIZE     = 16           # sizeof(Elf32_Sym)
RELASIZE    = 12           # sizeof(Elf32_Rela)
NRELSIZE    = 8            # sizeof(struct nrel) = two 32-bit words
MASK32      = 0xffffffff

# PC-relative field width in bytes, and the accepted displacement range per type.  The
# ranges are rel.c's, to the bit: boot2-040's relocsection COMPLAINs (dead end) outside
# [-32768,32767] for PC16 and [-128,127] for PC8, and does not range-check PC32 at all
# (a 32-bit displacement cannot overflow a 32-bit field).  Refusing what the loader would
# have accepted would be its own kind of wrong, so the numbers are copied, not tightened.
_PCREL_WIDTH = {R_68K_PC32: 4, R_68K_PC16: 2, R_68K_PC8: 1}
_PCREL_LIMIT = {R_68K_PC32: (-0x80000000, 0x7fffffff),
                R_68K_PC16: (-32768, 32767),
                R_68K_PC8:  (-128, 127)}
_PCREL_NAME  = {R_68K_PC32: 'R_68K_PC32', R_68K_PC16: 'R_68K_PC16', R_68K_PC8: 'R_68K_PC8'}


def sx32(v):
    """Interpret a 32-bit word (read unsigned) as signed -- r_addend is signed."""
    return v - 0x100000000 if v & 0x80000000 else v

# The new section-header string table WriteElfFile() emits, byte-for-byte:
#   static char newshstrtab[] = ".text\0.shstrtab\0.rel.boot\0\0";
# ".text\0"(6) + ".shstrtab\0"(10) + ".rel.boot\0"(10) + "\0"(explicit) + "\0"(C
# implicit terminator) = 28 bytes.
NEWSHSTRTAB = b'.text\x00.shstrtab\x00.rel.boot\x00\x00\x00'
TEXTSHOFF   = 0            # magic offsets into NEWSHSTRTAB (from the #defines)
SHSTRTABOFF = 6
RELBOOTOFF  = 16
assert len(NEWSHSTRTAB) == 28


def u16(b, o): return struct.unpack_from('>H', b, o)[0]
def u32(b, o): return struct.unpack_from('>I', b, o)[0]


class Elf2Brel:
    def __init__(self, data, whoami='elf2brel'):
        self.d = data
        self.whoami = whoami
        # PC-relative static-apply bookkeeping (all empty on the 030 line).
        self.pcrel_sites = []       # [(text offset, width)] -- the ONLY bytes we may change
        self.pcrel_applied = 0      # fields written
        self.pcrel_already = 0      # fields that already held the computed displacement
        self.pcrel_stats = {}       # reltype -> [count, min disp, max disp]

    def die(self, msg):
        sys.stderr.write('%s: %s\n' % (self.whoami, msg))
        sys.exit(1)

    # --- ReadElfFile(): slurp, verify, find sections BY NAME (as the C does) ---
    def read_elf(self):
        d = self.d
        if d[:4] != b'\x7fELF':
            self.die('input is not an ELF file')
        self.e_type = u16(d, 16)
        if self.e_type != ET_REL:
            self.die('input is not a relocatable file')
        self.e_shoff = u32(d, 32)
        self.e_shentsize = u16(d, 46)
        self.e_shnum = u16(d, 48)
        self.e_shstrndx = u16(d, 50)
        if self.e_shoff == 0 or self.e_shnum == 0:
            self.die('missing section header table!')

        # Parse every section header (endian-explicit).
        self.S = []
        for idx in range(self.e_shnum):
            o = self.e_shoff + idx * self.e_shentsize
            self.S.append(dict(
                name=u32(d, o + 0), type=u32(d, o + 4), flags=u32(d, o + 8),
                addr=u32(d, o + 12), offset=u32(d, o + 16), size=u32(d, o + 20),
                link=u32(d, o + 24), info=u32(d, o + 28),
                addralign=u32(d, o + 32), entsize=u32(d, o + 36)))

        # Section names live in the shstrtab (e_shstrndx).
        shstr_off = self.S[self.e_shstrndx]['offset']
        self.shstr = d[shstr_off:]

        # Brute-force name match, exactly as ReadElfFile() does (indices default 0
        # = "not found"; scan starts at 1 so the null section is never matched).
        self.i_text = self.i_rodata = self.i_data = self.i_bss = 0
        self.i_symtab = self.i_strtab = 0
        self.i_shstrtab = self.e_shstrndx
        self.i_rela_text = self.i_rela_rodata = self.i_rela_data = 0
        for idx in range(1, self.e_shnum):
            nm = self._sname(idx)
            if nm == '.text':          self.i_text = idx
            elif nm == '.rodata':      self.i_rodata = idx
            elif nm == '.data':        self.i_data = idx
            elif nm == '.bss':         self.i_bss = idx
            elif nm == '.symtab':      self.i_symtab = idx
            elif nm == '.strtab':      self.i_strtab = idx
            elif nm == '.rela.text':   self.i_rela_text = idx
            elif nm == '.rela.rodata': self.i_rela_rodata = idx
            elif nm == '.rela.data':   self.i_rela_data = idx

        # Fatal-error set mirrors ReadElfFile() exactly (.rodata + .rela.rodata are
        # the only optional ones).
        if self.i_text == 0:       self.die("missing '.text' section")
        if self.i_data == 0:       self.die("missing '.data' section")
        if self.i_bss == 0:        self.die("missing '.bss' section")
        if self.i_symtab == 0:     self.die("missing '.symtab' section")
        if self.i_strtab == 0:     self.die("missing '.strtab' section")
        if self.i_shstrtab == 0:   self.die("missing '.shstrtab' section")
        if self.i_rela_text == 0:  self.die("missing '.rela.text' section")
        if self.i_rela_data == 0:  self.die("missing '.rela.data' section")

        self.textsize   = self.S[self.i_text]['size']
        self.rodatasize = self.S[self.i_rodata]['size'] if self.i_rodata > 0 else 0
        self.datasize   = self.S[self.i_data]['size']
        self.bsssize    = self.S[self.i_bss]['size']

        # The section bytes, held twice: `text_in` is the input's .text, never touched, and
        # is what _assert_layout() holds the emitted payload against; `text_out` is the copy
        # PC-relative displacements are written into and the copy WriteElfFile emits.  On the
        # 030 line nothing is written and the two stay equal, so the output is bit-identical.
        t = self.S[self.i_text]
        if t['offset'] + self.textsize > len(d):
            self.die('.text (offset %d size %d) runs past the end of the %d-byte file'
                     % (t['offset'], self.textsize, len(d)))
        self.text_in  = bytes(d[t['offset']:t['offset'] + self.textsize])
        self.text_out = bytearray(self.text_in)

    def _sname(self, idx):
        n = self.S[idx]['name']
        e = self.shstr.find(b'\0', n)
        return self.shstr[n:e].decode('latin1')

    # --- symbol accessors over the raw symtab (with per-index overrides) -------
    def _load_symtab(self):
        d = self.d
        sh = self.S[self.i_symtab]
        self.nsyms = sh['size'] // sh['entsize']
        self.symoff = sh['offset']
        self.stroff = self.S[self.i_strtab]['offset']
        # Mutable per-symbol state (ProcessSymtab rewrites value + shndx).
        self.sym_value = [0] * self.nsyms
        self.sym_shndx = [0] * self.nsyms
        self.sym_size  = [0] * self.nsyms
        self.sym_name  = [0] * self.nsyms
        for k in range(self.nsyms):
            o = self.symoff + k * SYMSIZE
            self.sym_name[k]  = u32(d, o + 0)
            self.sym_value[k] = u32(d, o + 4)
            self.sym_size[k]  = u32(d, o + 8)
            self.sym_shndx[k] = u16(d, o + 14)
        # ProcessSymtab REWRITES value+shndx (every .rodata/.data/.bss/COMMON symbol comes
        # out claiming shndx == .text), so after it runs `shndx == i_text` no longer means
        # "defined in .text".  The PC-relative apply needs the input file's own answer to
        # that question -- an intra-.text test against the rewritten table would accept a
        # .data symbol -- so the pre-rewrite state is kept alongside.
        self.sym_shndx_in = list(self.sym_shndx)
        self.sym_value_in = list(self.sym_value)

    def _symname(self, k):
        n = self.sym_name[k]
        if not n:
            return ''
        e = self.d.find(b'\0', self.stroff + n)
        return self.d[self.stroff + n:e].decode('latin1')

    # --- ProcessSymtab(): make symbols combined-relative; place COMMON; specials --
    def process_symtab(self):
        self._load_symtab()
        it, ir, idt, ib = self.i_text, self.i_rodata, self.i_data, self.i_bss
        textsize, rodatasize, datasize = self.textsize, self.rodatasize, self.datasize

        # First pass: relocate defined symbols into the combined section; allocate
        # COMMON at the growing end (aligned to st_value, which for COMMON is the
        # required alignment); grow bsssize as COMMON accretes.
        end = (textsize + rodatasize + datasize + self.bsssize) & MASK32
        for k in range(self.nsyms):
            shndx = self.sym_shndx[k]
            if shndx == SHN_COMMON:
                self.sym_shndx[k] = it
                align = self.sym_value[k]
                end = (end + (align - 1)) & MASK32
                end = end & (~(align - 1) & MASK32)
                self.sym_value[k] = end
                end = (end + self.sym_size[k]) & MASK32
                self.bsssize = (end - textsize - rodatasize - datasize) & MASK32
            elif shndx == it:
                pass  # text symbols need no adjustment
            elif ir and shndx == ir:
                self.sym_shndx[k] = it
                self.sym_value[k] = (self.sym_value[k] + textsize) & MASK32
            elif shndx == idt:
                self.sym_shndx[k] = it
                self.sym_value[k] = (self.sym_value[k] + textsize + rodatasize) & MASK32
            elif shndx == ib:
                self.sym_shndx[k] = it
                self.sym_value[k] = (self.sym_value[k] + textsize + rodatasize + datasize) & MASK32

        # Second pass: the special symbols etext / edata / end.  Note the C sets
        # their shndx to i_text (NOT SHN_ABS) -- so any reloc against them is
        # text-relative, which is correct: rel.c/compactreloc adds the text bind
        # address, yielding the true end-of-text / end-of-data / end-of-bss vaddr.
        for k in range(self.nsyms):
            nm = self._symname(k)
            if nm == 'etext':
                self.sym_value[k] = textsize & MASK32
                self.sym_shndx[k] = it
            elif nm == 'edata':
                self.sym_value[k] = (textsize + rodatasize + datasize) & MASK32
                self.sym_shndx[k] = it
            elif nm == 'end':
                self.sym_value[k] = (textsize + rodatasize + datasize + self.bsssize) & MASK32
                self.sym_shndx[k] = it

    # --- the PC-relative static apply: resolve S+A-P into the section data now ---------
    def _apply_pcrel(self, r_offset, symidx, reltype, r_addend, src):
        """Write one intra-.text PC-relative displacement into text_out.  Returns nothing:
        an applied reloc is fully resolved and gets NO compact table entry.

        `src` names the section the relocation record applies to ('text'/'rodata'/'data').
        Every refusal below is a hard exit, never a warning -- see the header.
        """
        width = _PCREL_WIDTH[reltype]
        tname = _PCREL_NAME[reltype]
        if symidx >= self.nsyms:
            self.die('%s reloc at .%s+0x%x names sym[%d], past the end of .symtab (%d symbols)'
                     % (tname, src, r_offset, symidx, self.nsyms))
        sname = self._symname(symidx) or '<unnamed sym[%d]>' % symidx

        # (a) SOURCE must be inside .text.  A PC-relative field in .rodata/.data measures a
        #     distance we cannot pin down here: only .text-to-.text distances are invariant
        #     under whole-image relocation (both ends shift by the same bind address).
        if src != 'text':
            self.die('%s reloc at .%s+0x%x (sym %s): PC-relative relocation outside .text -- '
                     'S+A-P is not invariant under the load address, so it cannot be resolved '
                     'statically.  Refusing (this kernel needs a loader that relocates it).'
                     % (tname, src, r_offset, sname))
        if r_offset + width > self.textsize:
            self.die('%s reloc at .text+0x%x (sym %s): the %d-byte field runs past the end of '
                     '.text (%d bytes)' % (tname, r_offset, sname, width, self.textsize))

        # (b) TARGET must be defined in .text, by the INPUT file's section index.
        shndx_in = self.sym_shndx_in[symidx]
        if shndx_in != self.i_text:
            where = {SHN_ABS: 'SHN_ABS', SHN_COMMON: 'SHN_COMMON', 0: 'SHN_UNDEF'}.get(
                shndx_in, 'section %d (%s)' % (shndx_in, self._sname(shndx_in)
                                               if shndx_in < self.e_shnum else '?'))
            self.die('%s reloc at .text+0x%x names sym %s, which lives in %s, not .text -- '
                     'the displacement is not invariant under the load address.  Refusing.'
                     % (tname, r_offset, sname, where))

        # S + A - P, with P the address of the FIELD (r_offset).  Both S and P are .text
        # offsets here (sh_addr is 0 in an ET_REL), and .text keeps offset 0 in the combined
        # section, so the value computed now is the value the loaded image needs.
        S = self.sym_value_in[symidx]
        A = sx32(r_addend)
        disp = S + A - r_offset
        lo, hi = _PCREL_LIMIT[reltype]
        if disp < lo or disp > hi:
            self.die('%s reloc at .text+0x%x (sym %s, S=0x%x A=%d): displacement %d does not '
                     'fit [%d, %d].  Refusing rather than truncating -- a truncated '
                     'displacement is a silent wild branch inside the kernel.'
                     % (tname, r_offset, sname, S, A, disp, lo, hi))

        # The RELA field must be zero-filled (the addend is in r_addend, not in the data).
        # The one non-zero content we accept is a field that ALREADY holds exactly this
        # displacement -- re-converting an already-converted image is then a no-op instead
        # of a second application.  Anything else is fatal: we cannot distinguish an
        # assembler-biased field from a corrupted one, and guessing wrong is a wild branch.
        cur = int.from_bytes(self.text_out[r_offset:r_offset + width], 'big', signed=True)
        if cur == 0 or cur == disp:
            self.text_out[r_offset:r_offset + width] = disp.to_bytes(width, 'big', signed=True)
            if cur == disp and disp != 0:
                self.pcrel_already += 1
            else:
                self.pcrel_applied += 1
        else:
            self.die('%s reloc at .text+0x%x (sym %s): field is neither zero-filled nor the '
                     'computed displacement (holds %d, computed %d).  Refusing rather than '
                     'applying on top of it.' % (tname, r_offset, sname, cur, disp))

        self.pcrel_sites.append((r_offset, width))
        st = self.pcrel_stats.setdefault(reltype, [0, disp, disp])
        st[0] += 1
        st[1] = min(st[1], disp)
        st[2] = max(st[2], disp)

    # --- DoRelEntry(): one old Elf32_Rela -> one compact (nr_offset, nr_value) ---
    def _do_rel_entry(self, r_offset, r_info, r_addend, src='text'):
        """Returns the compact entry, or None when the reloc was resolved statically."""
        symidx = r_info >> 8            # ELF32_R_SYM
        reltype = r_info & 0xff         # ELF32_R_TYPE
        if reltype in _PCREL_WIDTH:
            # Applied into the section data; nothing is left for the loader to do.
            self._apply_pcrel(r_offset, symidx, reltype, r_addend, src)
            return None
        shndx = self.sym_shndx[symidx]
        if shndx != self.i_text and shndx != SHN_ABS:
            self.die('reloc uses unbound sym[%d]' % symidx)
        if reltype != R_68K_32:
            self.die('bad relocation type %u' % reltype)
        nr_offset = r_offset & MASK32
        nr_value = (r_addend + self.sym_value[symidx]) & MASK32
        if shndx == SHN_ABS:
            nr_offset |= 0x80000000     # hijack the MSB: value is absolute
        return nr_offset, nr_value

    # --- GenRelocTable(): fold .rela.text (+.rela.rodata) + .rela.data into one ---
    def gen_reloc_table(self):
        d = self.d
        st = self.S[self.i_rela_text]
        ntrel = st['size'] // st['entsize']
        # See the header note: nrodrel is initialized to 0 (the C leaves it
        # uninitialized when .rela.rodata is absent, which is a latent bug; 0 is
        # the intent and our kernel has no .rela.rodata).
        nrodrel = 0
        if self.i_rela_rodata > 0:
            sr = self.S[self.i_rela_rodata]
            nrodrel = sr['size'] // sr['entsize']
        sd = self.S[self.i_rela_data]
        ndrel = sd['size'] // sd['entsize']
        self.nrelin = ntrel + nrodrel + ndrel      # records read

        nrel = []
        # .rela.text -- offsets already index into the text portion.
        base = st['offset']
        for k in range(ntrel):
            o = base + k * RELASIZE
            e = self._do_rel_entry(u32(d, o), u32(d, o + 4), u32(d, o + 8), 'text')
            if e is not None:
                nrel.append(e)
        # .rela.rodata -- bump offset by textsize (rodata follows text).
        if nrodrel > 0:
            base = self.S[self.i_rela_rodata]['offset']
            for k in range(nrodrel):
                o = base + k * RELASIZE
                e = self._do_rel_entry(u32(d, o), u32(d, o + 4), u32(d, o + 8), 'rodata')
                if e is not None:
                    off, val = e
                    nrel.append(((off + self.textsize) & MASK32, val))
        # .rela.data -- bump offset by textsize + rodatasize (data follows rodata).
        base = sd['offset']
        for k in range(ndrel):
            o = base + k * RELASIZE
            e = self._do_rel_entry(u32(d, o), u32(d, o + 4), u32(d, o + 8), 'data')
            if e is not None:
                off, val = e
                nrel.append(((off + self.textsize + self.rodatasize) & MASK32, val))
        # nrelcount is what we EMIT, not what we read: a statically applied PC-relative
        # reloc leaves no entry behind.  (On the 030 line the two are equal, which is why
        # that line's output is unchanged to the byte.)
        self.nreltab = nrel
        self.nrelcount = len(nrel)

    # --- WriteElfFile(): assemble the brel byte image ------------------------
    def _orig_shdr_bytes(self, idx):
        """Original 40 raw bytes of section header <idx> (as elf2brel keeps the
        unmodified fields from the in-memory struct)."""
        o = self.e_shoff + idx * self.e_shentsize
        return bytearray(self.d[o:o + SHSIZE])

    def write_elf(self):
        textsize, rodatasize, datasize = self.textsize, self.rodatasize, self.datasize
        combined_size = (textsize + rodatasize + datasize) & MASK32

        # e_shoff = Ehdr + combined section + newshstrtab + compact reloc table.
        e_shoff = (EHSIZE + combined_size + len(NEWSHSTRTAB)
                   + self.nrelcount * NRELSIZE) & MASK32

        # -- Ehdr: copy the original 52 bytes, patch only the fields WriteElfFile
        #    touches (e_ident/e_machine/e_version/e_flags/e_ehsize/e_shentsize kept).
        eh = bytearray(self.d[0:EHSIZE])
        struct.pack_into('>H', eh, 16, ET_LOPROC)   # e_type
        struct.pack_into('>I', eh, 24, 0)           # e_entry
        struct.pack_into('>I', eh, 28, 0)           # e_phoff
        struct.pack_into('>I', eh, 32, e_shoff)     # e_shoff
        struct.pack_into('>H', eh, 42, 0)           # e_phentsize
        struct.pack_into('>H', eh, 44, 0)           # e_phnum
        struct.pack_into('>H', eh, 48, 4)           # e_shnum
        struct.pack_into('>H', eh, 50, 2)           # e_shstrndx

        # -- Section header 0: original null header, verbatim.
        sh0 = self._orig_shdr_bytes(0)

        # -- Section header 1: combined .text (keeps type/flags/addr/align/etc.).
        sh1 = self._orig_shdr_bytes(self.i_text)
        text_off = EHSIZE
        struct.pack_into('>I', sh1, 0, TEXTSHOFF)       # sh_name = ".text"
        struct.pack_into('>I', sh1, 16, text_off)       # sh_offset = 52
        struct.pack_into('>I', sh1, 20, combined_size)  # sh_size = text+rodata+data

        # -- Section header 2: the new shstrtab.
        sh2 = self._orig_shdr_bytes(self.i_shstrtab)
        shstr_off = (text_off + combined_size) & MASK32
        struct.pack_into('>I', sh2, 0, SHSTRTABOFF)         # sh_name = ".shstrtab"
        struct.pack_into('>I', sh2, 16, shstr_off)          # sh_offset
        struct.pack_into('>I', sh2, 20, len(NEWSHSTRTAB))   # sh_size = 28

        # -- Section header 3: the compact reloc table (retyped SHT_LOUSER).
        sh3 = self._orig_shdr_bytes(self.i_rela_text)
        rel_off = (shstr_off + len(NEWSHSTRTAB)) & MASK32
        struct.pack_into('>I', sh3, 0, RELBOOTOFF)                    # sh_name = ".rel.boot"
        struct.pack_into('>I', sh3, 4, SHT_LOUSER)                    # sh_type
        struct.pack_into('>I', sh3, 16, rel_off)                     # sh_offset
        struct.pack_into('>I', sh3, 24, 0)                          # sh_link
        struct.pack_into('>I', sh3, 28, 1)                          # sh_info
        struct.pack_into('>I', sh3, 20, self.nrelcount * NRELSIZE)  # sh_size
        struct.pack_into('>I', sh3, 36, NRELSIZE)                   # sh_entsize

        # -- Combined section bytes: text || rodata || data (bss is implied tail).
        #    .text comes from text_out -- the input's bytes with the PC-relative
        #    displacements written in (identical to the input on the 030 line).
        d = self.d
        parts = [bytes(eh), bytes(self.text_out)]
        if rodatasize > 0:
            r = self.S[self.i_rodata]
            parts.append(d[r['offset']:r['offset'] + rodatasize])
        dd = self.S[self.i_data]
        parts.append(d[dd['offset']:dd['offset'] + datasize])
        parts.append(NEWSHSTRTAB)
        # Compact reloc table: nrelcount * (nr_offset, nr_value), big-endian.
        relbuf = bytearray(self.nrelcount * NRELSIZE)
        p = 0
        for off, val in self.nreltab:
            struct.pack_into('>II', relbuf, p, off, val)
            p += NRELSIZE
        parts.append(bytes(relbuf))
        parts.extend([bytes(sh0), bytes(sh1), bytes(sh2), bytes(sh3)])
        return b''.join(parts)

    # --- the layout assertion the static apply rests on ----------------------
    def _assert_layout(self, out):
        """Re-read the emitted image and require that the brel payload is the INPUT's
        .text || .rodata || .data byte-for-byte, differing ONLY at the PC-relative fields
        this converter wrote.

        The static apply is only sound because .text keeps offset 0 in the combined section
        and is copied verbatim -- one byte of padding, realignment or reordering ahead of or
        inside it and every applied displacement is wrong by that much, silently.  The C
        does copy verbatim and so does this port, so this never fires; it exists so that a
        future edit which breaks the property cannot ship, and it is cheap (three slice
        compares over ~1 MB).  A failure here is an internal error, not bad input.
        """
        combined = (self.textsize + self.rodatasize + self.datasize) & MASK32

        # The emitted section header 1 must actually place the payload where we assume.
        e_shoff = u32(out, 32)
        sh1 = e_shoff + 1 * SHSIZE
        if len(out) < e_shoff + 4 * SHSIZE:
            self.die('INTERNAL: emitted image is shorter than its own section header table')
        if u32(out, sh1 + 16) != EHSIZE or u32(out, sh1 + 20) != combined:
            self.die('INTERNAL: combined section header says offset=%d size=%d, expected %d/%d'
                     % (u32(out, sh1 + 16), u32(out, sh1 + 20), EHSIZE, combined))

        # .text: input bytes everywhere except the fields we applied.
        expect = bytearray(self.text_in)
        for off, w in self.pcrel_sites:
            expect[off:off + w] = self.text_out[off:off + w]
        got = out[EHSIZE:EHSIZE + self.textsize]
        if got != bytes(expect):
            n = sum(1 for a, b in zip(got, expect) if a != b)
            self.die('INTERNAL: brel .text differs from the input .text outside the %d applied '
                     'PC-relative field(s) (%d byte(s) differ) -- the combined section is NOT '
                     'a verbatim copy, so every applied displacement is suspect'
                     % (len(self.pcrel_sites), n))

        # .rodata / .data: verbatim, and in that order, immediately after .text.
        pos = EHSIZE + self.textsize
        for idx, size, nm in ((self.i_rodata, self.rodatasize, '.rodata'),
                              (self.i_data, self.datasize, '.data')):
            if size == 0:
                continue
            s = self.S[idx]
            if out[pos:pos + size] != self.d[s['offset']:s['offset'] + size]:
                self.die('INTERNAL: brel %s payload is not a verbatim copy of the input' % nm)
            pos += size
        if pos != EHSIZE + combined:
            self.die('INTERNAL: combined payload ends at %d, expected %d'
                     % (pos, EHSIZE + combined))

        # And the table we emitted is exactly the entries we built -- no PC-relative
        # record may have leaked into it.
        if self.nrelcount != len(self.nreltab):
            self.die('INTERNAL: nrelcount %d != %d table entries'
                     % (self.nrelcount, len(self.nreltab)))
        if self.nrelcount + self.pcrel_applied + self.pcrel_already != self.nrelin:
            self.die('INTERNAL: %d records read, %d emitted + %d applied + %d already-applied'
                     % (self.nrelin, self.nrelcount, self.pcrel_applied, self.pcrel_already))

    def convert(self):
        self.read_elf()
        self.process_symtab()
        self.gen_reloc_table()
        out = self.write_elf()
        self._assert_layout(out)
        return out

    def pcrel_summary(self):
        """One-line description of the static apply, for -v (empty on the 030 line)."""
        if not self.pcrel_stats:
            return 'PC-relative relocations: none'
        per = ', '.join('%s %d [%d..%d]' % (_PCREL_NAME[t], c, lo, hi)
                        for t, (c, lo, hi) in sorted(self.pcrel_stats.items()))
        return ('PC-relative statically applied: %d (%s); %d field(s) already held the '
                'computed displacement; 0 emitted into the reloc table'
                % (self.pcrel_applied + self.pcrel_already, per, self.pcrel_already))


def main(argv):
    verbose = False
    args = []
    for a in argv[1:]:
        if a in ('-v', '--verbose'):
            verbose = True
        elif a in ('-h', '--help'):
            sys.stderr.write(
                'usage: elf2brel.py [-v] [<in.elf> [<out.brel>]]\n'
                '  no args        : stdin  -> stdout\n'
                '  <in>           : file   -> stdout\n'
                '  <in> <out>     : file   -> file\n')
            return 0
        elif a.startswith('-') and a != '-':
            # Fail closed.  Unknown `-`-leading args used to fall through into args[]
            # as if they were filenames, and only args[0]/args[1] are ever read.  So
            # `elf2brel.py <in> --dry-run <out>` wrote the brel to a file literally
            # NAMED "--dry-run", left <out> untouched, and exited 0 (verified).
            sys.stderr.write('elf2brel.py: unknown option: %s\n' % a)
            return 2
        else:
            args.append(a)

    if len(args) > 2:
        # Third-and-later positionals were silently discarded, so a shell glob that
        # expanded to more files than expected wrote only the 2nd one and exited 0.
        sys.stderr.write('elf2brel.py: too many arguments (want at most <in> <out>), got: %s\n'
                         % ' '.join(args))
        return 2

    if len(args) >= 1:
        with open(args[0], 'rb') as f:
            data = f.read()
    else:
        data = sys.stdin.buffer.read()

    conv = Elf2Brel(data, whoami='elf2brel.py')
    out = conv.convert()

    if len(args) >= 2:
        with open(args[1], 'wb') as f:
            f.write(out)
    else:
        sys.stdout.buffer.write(out)

    if verbose:
        sys.stderr.write(
            'elf2brel.py: e_type=0xff00  combined=%d (text=%d rodata=%d data=%d, '
            'bss-tail=%d)  reloc entries=%d  out=%d bytes\n' % (
                conv.textsize + conv.rodatasize + conv.datasize,
                conv.textsize, conv.rodatasize, conv.datasize, conv.bsssize,
                conv.nrelcount, len(out)))
        sys.stderr.write('elf2brel.py: %s\n' % conv.pcrel_summary())
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
