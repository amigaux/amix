#!/usr/bin/env python3
"""scan060-g14.py -- the 68060 instruction scan for GCC 14 output, with the
switch tables sized from the code rather than guessed from the data.

    scan060-g14.py [--objdump PATH] [--explain HITFILE] <elf>...

Exit 0 clean, 1 a 68060-unimplemented instruction, 2 unreadable input,
3 untrustworthy (a table could not be sized, or the decoder lost sync).

WHY THIS EXISTS.  GCC 14 compiles a switch into

    cmpib #32,%d6 ; bhiw default          (or moveq #N,%dY; cmpl %dX,%dY; bcs)
    movew %pc@(T,%d0:l),%d0               (or moveaw ...,%a5 / movew %a0@(0,%d0:l))
    jmp   %pc@(T,%d0:w)

with a table of N+1 signed word offsets at T -- and, unlike gcc 2.7, it puts
case code BEFORE the table as often as after it (negative offsets) and it
indexes through an address register too.  A linear objdump decodes the table
as code (movep, bset, `mulsl` noise).  amix-packagemanager's scan060.py sizes a
table from the smallest POSITIVE offset, the gcc 2.7 layout; on GCC 14 output
it reads past the table into code, takes an instruction word for an offset,
and reports the rest of the table as movep and 64-bit mulsl: 15 such hits on
the first gcc14 grep, none of them code.  This tool sizes each table from its
bound check instead (N+1 entries, exactly what the hardware can index),
verifies every entry lands on an even address inside the same function and
outside the table, and refuses to give a verdict on any table it cannot size
(exit 3) -- an unsized table is the case where a real instruction could hide.
One shape has no bound to read: a constant index (`moveq #K', a switch whose
value GCC knew), which can only take entry K.  That table is sized from its
own entries, up to the nearest case, and named in a NOTE as a known limit.
An index from `bfextu <ea>,<off>,<width>,%dI' takes 2^width entries, exactly.
And a table whose index is only provably a byte or a word (an and-mask, or a
zero-extended byte or word load: 2^k entries at most) but whose 2^k words do
not all land on code -- GCC knew a narrower range from an outer test -- is
sized from its own entries too, and only when that run of entries ends on a
word that cannot be one (odd, outside the function, back into the table, or
at the first case), never at the cap: a NOTE names it as trusted by shape.
For that rule alone, one instruction may sit between the table load and the
jmp (between_insn), when it changes no control flow, writes neither the
index nor the jmp's register, and no branch lands on it or on the jmp.
Any other table it cannot size stays untrustworthy.

Then, like scan060.py, it re-disassembles only the code BETWEEN tables, so the
stream re-synchronises after each one, and scans that listing by ENCODING:
MUL.L/DIV.L with extension bit 10 (the 64-bit forms), and the movep, cmp2,
chk2 and cas2 the 68060 also lacks.  Every function label must fall on an
instruction start in the final listing, or the verdict is "untrustworthy".

Known stock data in .text: a few stock archive members that programs link
keep tables in .text as local symbols (crypt(3)'s DES tables in libc's
crypt.o and libcrypt.a's des_crypt.o; libelf.a's xlate.o, whose x32 is 52
function pointers).  KNOWN_STOCK_DATA names each member by
its archive in the sysroot ($AMIX_SYSROOT), its sha256 and those symbols.  A
member whose sha256 differs is a problem.  Otherwise its .text is looked for
in the program, its relocated bytes masked, and where it is found exactly,
each listed symbol's range (to the member's next symbol) is data, like a
sized table, and a NOTE says so.  Without AMIX_SYSROOT none is applied, and a
NOTE says that too, once per run.
A sized STT_OBJECT symbol inside an executable section is data the same way
(values-Xa.o's _lib_version, in every program the period toolchain links),
with a NOTE.  objdump runs with -D on each executable section, by objdump's
own name for it, never -d, and only that section's listing is read, never
.debug_* or another section that is not code:
-d prints a data symbol's range as a hex dump up to the next symbol, which in
a stripped program can be the rest of .text, and the dump's lines would be
read as instructions.

--explain HITFILE: read scan060.py's output and say, for every hit address it
lists, whether it lies inside a table sized here (data, not code), at an odd
address, or inside an instruction of the re-synced listing (a decode out of
sync, either way).  Exit 1 if
any hit is unexplained.  This is how the gcc14 gate keeps scan060.py as an
independent decoder instead of dropping it.

MIT, amix-packages.
"""
import bisect
import hashlib
import os
import re
import struct
import subprocess
import sys

LINE = re.compile(r"^\s*([0-9a-f]+):\s+((?:[0-9a-f]{4} )+)\s*(\S+)\s*(.*)$")
LABEL = re.compile(r"^([0-9a-f]+) <([^>]+)>:\s*$")
# The index register can be any data or address register -- including %a6,
# which objdump names %fp and GCC 14 -O2 uses as a general register (patch
# 2.5.9's quotearg, 2026-10-27: an %fp-indexed table read as a movep).
DISPATCH = re.compile(r"^%pc@\(([0-9a-f]+)\b[^,)]*,%([da][0-7]|fp|sp):w\)$")
PC_INDEXED = re.compile(r"^%pc@\([0-9a-f]+\b[^,)]*,%[a-z0-9]+:[wl]\)$")
BOUND_CMP = re.compile(r"^#(-?\d+),(\S+)$")                # cmp[i]{b,w,l} #N,<ea>
MOVEQ = re.compile(r"^#(-?\d+),%(d[0-7])$")
CMPL_REG = re.compile(r"^%(d[0-7]),%(d[0-7])$")            # cmpl %dX,%dY
MNEM_OTHER = re.compile(r"^(movep|cmp2|chk2|cas2)")
COND_BRANCH = re.compile(r"^b(hi|ls|cc|cs|ne|eq|vc|vs|pl|mi|ge|lt|gt|le)[bswl]?$")
LOOKBACK = 16

# Stock archive members (relative to the sysroot) whose named local symbols in
# .text are data, not code.
KNOWN_STOCK_DATA = (
    ("usr/ccs/lib/libc.so", "crypt.o",
     "4af415c472ab5916313b324b61478159f485a73f0c4bd095c868dc03b4219d58",
     ("IP", "FP", "PC1_C", "PC1_D", "shifts", "PC2_C", "PC2_D", "e2")),
    ("usr/lib/libcrypt.a", "des_crypt.o",
     "57ab906ac374ea2c78fb25a5b6814bf0f2da30499b33845a8f08cab45fd4c195",
     ("IP", "FP", "PC1_C", "PC1_D", "shifts", "PC2_C", "PC2_D", "e2", "S", "P")),
    ("usr/ccs/lib/libelf.a", "xlate.o",
     "1b0a1ad79581ed7556096138c0a457d0fafbc2dbef64dec8789756a6be6bd0ad",
     ("x32", "fmsize", "mtype")),
)


def die(msg, code=2):
    sys.stderr.write("scan060-g14: %s\n" % msg)
    sys.exit(code)


def exec_sections(data):
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 2:
        die("not an ELF32 big-endian file")
    shoff = struct.unpack(">I", data[32:36])[0]
    shentsize, shnum = struct.unpack(">HH", data[46:50])
    out = []
    for i in range(shnum):
        sh = data[shoff + i * shentsize: shoff + (i + 1) * shentsize]
        _n, typ, flags, addr, off, size = struct.unpack(">IIIIII", sh[:24])
        if typ == 1 and flags & 0x4 and size:
            out.append((addr, off, size))
    return out


HEADER = re.compile(r"^\s*\d+ (\S*)\s+([0-9a-f]+)\s+([0-9a-f]+)\s+[0-9a-f]+\s+[0-9a-f]+\s+2\*\*\d+\s*$")


def exec_section_names(tool, path, secs):
    """The name objdump gives each of exec_sections' sections, in the same
    order, from objdump -h by address and size: BFD's name, not the section
    header's.  A section whose sh_name is 0 has an empty name there even
    when the string table does not start with a NUL (a period kernel's
    .text: its string table starts ".text")."""
    r = subprocess.run([tool, "-h", path], capture_output=True, text=True, errors="replace")
    if r.returncode != 0:
        die("objdump -h failed on %s: %s" % (path, r.stderr.strip()[:200]))
    bfd = {}
    for line in r.stdout.splitlines():
        m = HEADER.match(line)
        if m:
            bfd.setdefault((int(m.group(3), 16), int(m.group(2), 16)), m.group(1))
    names = []
    for sa, _o, sz in secs:
        if (sa, sz) not in bfd:
            die("%s: objdump -h lists no section at 0x%x of 0x%x bytes" % (path, sa, sz))
        names.append(bfd[(sa, sz)])
    return names


def objdump(tool, path, sec, lo, hi):
    """-D of section sec over [lo, hi): every word is decoded as code,
    whatever symbol type covers it (-d dumps a data symbol's range as hex
    instead; data_objects).  Only sec's own listing is kept: an address
    range alone also selects the non-alloc sections at address 0
    (.debug_*), which -D would decode too.  -j names sec where objdump can
    (an empty name it cannot)."""
    cmd = [tool, "-D", "--start-address=0x%x" % lo, "--stop-address=0x%x" % hi]
    if sec:
        cmd[1:1] = ["-j", sec]
    r = subprocess.run(cmd + [path], capture_output=True, text=True, errors="replace")
    if r.returncode != 0:
        die("objdump failed on %s: %s" % (path, r.stderr.strip()[:200]))
    out, keep = [], False
    for line in r.stdout.splitlines(True):
        if line.startswith("Disassembly of section "):
            keep = line.rstrip("\n") == "Disassembly of section %s:" % sec
        if keep:
            out.append(line)
    return "".join(out)


def parse(listing):
    """-> (insns [(addr, words, mnem, ops)], labels {addr: name})"""
    insns, labels = [], {}
    for raw in listing.splitlines():
        m = LABEL.match(raw)
        if m:
            labels[int(m.group(1), 16)] = m.group(2)
            continue
        m = LINE.match(raw)
        if m:
            insns.append((int(m.group(1), 16), m.group(2).split(), m.group(3), m.group(4).strip()))
    return insns, labels


def sized_symbols(data, stt):
    """{(start, end): name} of every symbol of type stt with a size, from
    .symtab and .dynsym."""
    shoff = struct.unpack(">I", data[32:36])[0]
    shentsize, shnum = struct.unpack(">HH", data[46:50])
    shdrs = [struct.unpack(">10I", data[shoff + i * shentsize: shoff + i * shentsize + 40])
             for i in range(shnum)]
    out = {}
    for _n, typ, _f, _a, off, size, link, _i, _al, ent in shdrs:
        if typ not in (2, 11) or ent < 16:              # SHT_SYMTAB, SHT_DYNSYM
            continue
        stroff = shdrs[link][4] if link < shnum else 0
        for k in range(size // ent):
            nm, val, sz, info = struct.unpack(">IIIB", data[off + k * ent: off + k * ent + 13])
            if info & 0xf == stt and sz:
                end = data.find(b"\0", stroff + nm)
                out[(val, val + sz)] = data[stroff + nm:end].decode("latin1") if stroff and end > 0 else "?"
    return out


def func_symbols(data):
    """(start, end) of every STT_FUNC symbol with a size."""
    return set(sized_symbols(data, 2))


def data_objects(data, secs):
    """{(start, end): name} of every sized STT_OBJECT symbol inside an
    executable section: data the linker placed in .text, such as
    values-Xa.o's _lib_version, which libc.so.1 reads and so stays in a
    stripped program's .dynsym.  objdump -d prints such a symbol's range as
    a hex dump up to the next symbol, which in a stripped program can be
    the rest of .text; its 8-word lines then pass for instructions."""
    return {r: n for r, n in sized_symbols(data, 1).items()
            if any(sa <= r[0] and r[1] <= sa + sz for sa, _o, sz in secs)}


def ar_member(path, name):
    """The bytes of member NAME of the ar archive at PATH, or None."""
    d = open(path, "rb").read()
    if d[:8] != b"!<arch>\n":
        return None
    o = 8
    while o + 60 <= len(d):
        h = d[o:o + 60]
        size = int(h[48:58].decode().strip() or 0)
        if h[:16].decode("latin-1").strip().rstrip("/") == name:
            return d[o + 60:o + 60 + size]
        o += 60 + size + (size & 1)
    return None


def member_text(obj):
    """(.text bytes, set of relocated byte offsets, {symbol: (start, end)})
    of a relocatable ELF32 big-endian object; each symbol in .text runs to
    the next symbol or the section's end."""
    shoff = struct.unpack(">I", obj[32:36])[0]
    shentsize, shnum, shstrndx = struct.unpack(">HHH", obj[46:52])
    sh = [struct.unpack(">10I", obj[shoff + i * shentsize: shoff + i * shentsize + 40]) for i in range(shnum)]
    names = sh[shstrndx]

    def nm(off, tab):
        e = obj.index(b"\0", tab[4] + off)
        return obj[tab[4] + off:e].decode("latin-1")
    ti = [i for i, s in enumerate(sh) if nm(s[0], names) == ".text"][0]
    text = obj[sh[ti][4]:sh[ti][4] + sh[ti][5]]
    masked = set()
    syms = []
    for s in sh:
        if s[1] == 4 and s[7] == ti:                    # SHT_RELA for .text
            for k in range(s[5] // 12):
                r = struct.unpack(">I", obj[s[4] + 12 * k: s[4] + 12 * k + 4])[0]
                masked.update(range(r, r + 4))
        if s[1] == 2:                                   # SHT_SYMTAB
            strtab = sh[s[6]]
            for k in range(s[5] // 16):
                n, val, _sz, _info, _oth, shndx = struct.unpack(">IIIBBH", obj[s[4] + 16 * k: s[4] + 16 * k + 16])
                if shndx == ti and n:
                    syms.append((val, nm(n, strtab)))
    starts = sorted(set(v for v, _n in syms)) + [len(text)]
    ranges = {}
    for v, n in syms:
        ranges[n] = (v, min(x for x in starts if x > v) if v < len(text) else v)
    return text, masked, ranges


def find_text(data, secs, text, masked):
    """Program addresses where TEXT appears in an executable section, the
    bytes at MASKED offsets (relocated) not compared."""
    anchor, a_off, run = b"", 0, 0
    for i in range(len(text) + 1):
        if i < len(text) and i not in masked:
            run += 1
            continue
        if run > len(anchor):
            anchor, a_off = text[i - run:i], i - run
        run = 0
    if len(anchor) < 16:
        return []
    found = []
    for sa, so, sz in secs:
        sec = data[so:so + sz]
        f = sec.find(anchor)
        while f >= 0:
            base = f - a_off
            if base >= 0 and base + len(text) <= sz and all(
                    sec[base + i] == text[i] for i in range(len(text)) if i not in masked):
                found.append(sa + base)
            f = sec.find(anchor, f + 1)
    return found


def known_data(data, secs, sysroot):
    """-> ([(start, end)], [notes], [problems]) for KNOWN_STOCK_DATA in a
    program."""
    ranges, notes, problems = [], [], []
    for archive, member, want, symbols in KNOWN_STOCK_DATA:
        path = os.path.join(sysroot, archive)
        obj = ar_member(path, member) if os.path.isfile(path) else None
        if obj is None:
            continue
        got = hashlib.sha256(obj).hexdigest()
        if got != want:
            problems.append("known stock member %s(%s) has sha256 %s, not the listed %s"
                            % (archive, member, got[:16], want[:16]))
            continue
        text, masked, syms = member_text(obj)
        for base in find_text(data, secs, text, masked):
            for s in symbols:
                if s in syms:
                    ranges.append((base + syms[s][0], base + syms[s][1]))
            notes.append("known stock data at 0x%08x: %s(%s) %s, sha256 %s"
                         % (base, os.path.basename(archive), member, " ".join(symbols), want[:16]))
    return ranges, notes, problems


def function_bounds(labels, secs, data=None):
    """sorted function starts and ends + section ends, for 'which function is
    this in'.  An executable's are its labels; a shared object's (ET_DYN) are
    its STT_FUNC symbols, start and start + size: PIC code loads a switch
    table's base from the GOT, so the table's local label lands in the symbol
    table and, taken as a label, would end the function in the middle
    (libX11.so, libXt.so, 2026-10-31)."""
    ends = {sa + sz for sa, _o, sz in secs} | {sa for sa, _o, _s in secs}
    if data is not None and struct.unpack(">H", data[16:18])[0] == 3:
        return sorted(ends | {b for f in func_symbols(data) for b in f})
    return sorted(set(labels) | ends)


def enclosing(pts, a):
    lo, hi = None, None
    for p in pts:
        if p <= a:
            lo = p
        elif hi is None:
            hi = p
            break
    return lo, hi


def word_at(data, secs, a):
    for sa, so, sz in secs:
        if sa <= a and a + 2 <= sa + sz:
            return struct.unpack(">h", data[so + a - sa: so + a - sa + 2])[0]
    return None


def got_context(data):
    """For a file with a dynamic section: (the GOT's address, DT_PLTGOT, the
    value %a5 holds in PIC code; {slot address: addend} of its
    R_68K_RELATIVE relocations, a slot with more than one relocation left
    out); else None.  Read from the section headers."""
    shoff = struct.unpack(">I", data[32:36])[0]
    shentsize, shnum = struct.unpack(">HH", data[46:50])
    got, slots, seen = None, {}, set()
    for i in range(shnum):
        sh = data[shoff + i * shentsize: shoff + (i + 1) * shentsize]
        _n, typ, _f, _a, off, size, _l, _i, _al, ent = struct.unpack(">IIIIIIIIII", sh[:40])
        if typ == 6:                                    # SHT_DYNAMIC
            for k in range(0, size - 7, 8):
                tag, val = struct.unpack(">II", data[off + k: off + k + 8])
                if tag == 3:                            # DT_PLTGOT
                    got = val
        elif typ == 4 and ent == 12:                    # SHT_RELA
            for k in range(0, size - 11, 12):
                r_off, info, add = struct.unpack(">IIi", data[off + k: off + k + 12])
                if r_off in seen:
                    slots.pop(r_off, None)
                    continue
                seen.add(r_off)
                if info & 0xff == 22:                   # R_68K_RELATIVE
                    slots[r_off] = add & 0xffffffff
    return (got, slots) if got is not None else None


def uword_at(data, secs, a):
    w = word_at(data, secs, a)
    return None if w is None else w & 0xffff


def got_load(data, secs, a):
    """(N, displacement) of the `moveal %a5@(d),%aN' at a, read from its
    words (objdump prints a d16 in decimal and a full-format base
    displacement in hex, on a line of its own): mode 5, or mode 6 in the
    full format with no index and no memory indirection, its base
    displacement a word or a long; else None."""
    op = uword_at(data, secs, a)
    if op is None or op & 0xf1ff not in (0x206d, 0x2075):
        return None
    n = (op >> 9) & 7
    if op & 0x38 == 0x28:
        d = word_at(data, secs, a + 2)
        return None if d is None else (n, d)
    ext = uword_at(data, secs, a + 2)
    if ext is None or ext & 0x1ff not in (0x160, 0x170):
        return None
    hi = word_at(data, secs, a + 4)
    if hi is None:
        return None
    if ext & 0x1ff == 0x160:
        return n, hi
    lo = uword_at(data, secs, a + 6)
    return None if lo is None else (n, (hi << 16) | lo)


def a5_is_got(insns, p, got, fstart):
    """Whether %a5 holds the GOT at insns[p]: the last write to it before
    p, within the function, is `lea %pc@(G),%a5' with G the GOT; a restore
    just before an rts (a return path laid out in between) aside."""
    for q in range(p - 1, max(0, p - 1024) - 1, -1):
        a, _w, mn, ops = insns[q]
        if a < fstart:
            return False
        if mn == "lea":
            m = re.match(r"^%pc@\(([0-9a-f]+)\b[^)]*\),%a5$", ops)
            if m:
                return int(m.group(1), 16) == got
        if writes_reg(mn, ops, "a5"):
            if q + 1 < p and insns[q + 1][2] == "rts" and (mn.startswith("moveml") or ops == "%sp@+,%a5"):
                continue
            return False
    return False


def moveq_value(insns, j, reg):
    """The constant in %reg at insns[j], if the last write to it before j is a
    moveq #N,%reg within a few instructions; else None.  A compare or test
    names the register without writing it (perl 5.8.9's Perl_pv_uni_display:
    `moveq #6,%d7 ; cmpl %d0,%d7 ; ... ; cmpl %d1,%d7 ; bcs')."""
    for k in range(j - 1, max(0, j - 6) - 1, -1):
        mn, ops = insns[k][2], insns[k][3]
        if mn.startswith(("cmp", "tst", "btst")):
            continue
        if ops.endswith("," + reg) or ops == reg:
            m = MOVEQ.match(ops) if mn == "moveq" else None
            return int(m.group(1)) if m and m.group(2) == reg[1:] else None
    return None


def bound_of(insns, j, br):
    """(N+1, <ea>) when the compare at insns[j], read with the branch br,
    bounds <ea> by one of bound_for's three unbiased forms; else None."""
    mn, ops = insns[j][2], insns[j][3]
    m = BOUND_CMP.match(ops)
    if m and br.startswith("bhi"):
        n = int(m.group(1))
        if mn.endswith("b"):
            n &= 0xff
        elif mn.endswith("w"):
            n &= 0xffff
        return n + 1, m.group(2)
    m = re.match(r"^(.+),%(d[0-7])$", ops)
    if m and br.startswith("bcs"):
        n = moveq_value(insns, j, "%" + m.group(2))
        if n is not None:
            return n + 1, m.group(1)
    m = re.match(r"^%(d[0-7]),(\S+)$", ops)
    if m and br.startswith("bhi"):
        n = moveq_value(insns, j, "%" + m.group(1))
        if n is not None and n >= 0:
            return n + 1, m.group(2)
    return None


def bound_for(insns, idx, got=None):
    """Entry count (N+1) from the unsigned bound check before the dispatch at
    insns[idx].  The forms met in GCC 14 output and in the stock archive
    members it links (libgen's regcmp/advance):
        cmp[i]{b,w,l} #N,<ea>      ; bhi default     (ea > N)
        moveq #N,%dY ; cmpl <ea>,%dY ; bcs default   (N < ea)
        moveq #N,%dY ; cmpl %dY,<ea> ; bhi default   (ea > N)
    <ea> may be a memory operand, which objdump prints with its symbol
    (`cmpl 8003db14 <subcommand_option>,%d6': tar 1.14, 2026-10-27).
    The compare may be cmpa against an address register: the stock AT&T
    compiler's `moveq #8,%d1 ; cmpal %d1,%a0 ; bhiw' in libc.so's static
    getutx.o (_getutxid), linked by coreutils who/users/pinky, 2026-10-29.
    And a biased one, on the index before the bias is added (vim 9.1,
    2026-10-31):
        movel %dS,%dI ; addql #K,%dI ; moveq #-K,%dY ; cmpl %dS,%dY ; bhi default
    lets through only dS in [-K, -1], so dI = dS + K indexes K entries;
    accepted only when the dispatch's index register is that dI.
    The bound branch may follow other conditional branches after the compare
    (they leave the block and change no flag; std::ctype<char>::is in
    libstdc++.a, CDE 2.5.3, 2026-11-19):
        moveq #64,%d0 ; cmpl %d1,%d0 ; bltw out ; bcsw out ; addl %d1,%d1 ;
        movew %a2@(0,%d1:l),%d0 ; jmp %pc@(T,%d0:w)
    accepted only when the compared operand is the dispatch's index register
    and the table load's base is T (interleaved_ok).  In a shared object
    (libstdc++.so.6, 276ef49, 2026-11-22) the base comes from the GOT,
    `lea %pc@(GOT),%a5 ; ... ; moveal %a5@(d),%a2', its slot GOT+d an
    R_68K_RELATIVE to T (got: got_context, and the function's start).
    And a mask bounding the
    index gives way to a smaller bound on the ways into the dispatch block
    (masked_entry_bound: d_special_name, libiberty's demangler in
    libstdc++.a, `cmpib #53,%d0 ; bls block', block `andil #255,%d0').
    """
    lo = max(0, idx - LOOKBACK)
    block = None
    for j in range(idx - 1, lo - 1, -1):
        _a, _w, mn, ops = insns[j]
        if mn.startswith(("rts", "jmp", "bra")):
            block = j + 1                           # left the dispatch block
            break
        if not re.match(r"^cmp[ai]?[bwl]$", mn) or j + 1 >= idx:
            continue
        br = insns[j + 1][2]
        r = bound_of(insns, j, br)
        if r is not None:
            return r[0]
        k = j + 1
        while COND_BRANCH.match(insns[k][2]) and k + 1 < idx and COND_BRANCH.match(insns[k + 1][2]):
            k += 1
            r = bound_of(insns, j, insns[k][2])
            if r is not None and interleaved_ok(insns, k, idx, r[1], r[0], got):
                return r[0]
        m = re.match(r"^%(d[0-7]),%(d[0-7])$", ops)
        if m and br.startswith("bhi"):
            n = moveq_value(insns, j, "%" + m.group(2))
            if n is not None and n < 0 and biased_index(insns, j, idx, m.group(1), -n):
                return -n
    # no compare bounds it: a bit field extracted into the index, else a
    # mask in the block, else the ways into the block
    n = bitfield_bound(insns, idx, block if block is not None else lo)
    if n is not None:
        return n
    for j in range(idx - 1, (block if block is not None else lo) - 1, -1):
        n = mask_bound(insns, j)
        if n is not None:
            e = masked_entry_bound(insns, block, idx, n) if block is not None else None
            return e if e is not None and e < n else n
    if block is not None:
        return entry_bound(insns, block, idx)
    return None


def index_register(insns, idx):
    """The data register the dispatch at insns[idx] indexes its table with:
    the `movew %pc@(T,%dI:l),...' just before it."""
    if idx < 1 or insns[idx - 1][2] != "movew":
        return None
    m = re.match(r"^%pc@\([0-9a-f]+\b[^,)]*,%(d[0-7]):l\)", insns[idx - 1][3])
    return m.group(1) if m else None


def load_index(insns, idx):
    """(index register, base) of the table load just before the dispatch at
    insns[idx]: `movew %pc@(T,%dI:l),...' (base None) or `movew
    %aN@(0,%dI:l),...' (base aN); else None."""
    if idx < 1 or insns[idx - 1][2] not in ("movew", "moveaw"):
        return None
    m = re.match(r"^(?:%pc@\([0-9a-f]+\b[^,)]*|%(a[0-7]|fp)@\(0),%(d[0-7]):l\),", insns[idx - 1][3])
    return (m.group(2), m.group(1)) if m else None


FLOW = re.compile(r"^(b(ra|sr)|jmp|jsr|rt[sedr]|trap|db|illegal|stop|chk)")


def between_insn(insns, idx):
    """The one instruction between the table load and the dispatch at
    insns[idx], when there is exactly one: `movew %pc@(T,%dI:l),%dJ ; <insn>
    ; jmp %pc@(T,%dJ:w)' (libstdc++'s std::__facet_shims::__time_get<char>,
    CDE 2.5.3, 2026-11-19: `moveal %a0@,%a1' in between).  It may change no
    control flow and write neither %dI nor %dJ, and no branch may land on it
    or on the jmp (past the load).  -> its index in insns, else None."""
    if idx < 2 or load_index(insns, idx) is not None or insns[idx - 2][2] != "movew":
        return None
    m = re.match(r"^%pc@\(([0-9a-f]+)\b[^,)]*,%(d[0-7]):l\),%(d[0-7])$", insns[idx - 2][3])
    d = DISPATCH.match(insns[idx][3])
    if not m or not d or int(m.group(1), 16) != int(d.group(1), 16) or m.group(3) != d.group(2):
        return None
    mn, ops = insns[idx - 1][2], insns[idx - 1][3]
    if FLOW.match(mn) or COND_BRANCH.match(mn) or writes_reg(mn, ops, m.group(2)) \
            or writes_reg(mn, ops, m.group(3)):
        return None
    landing_on = {"%x" % insns[idx - 1][0], "%x" % insns[idx][0]}
    for _a, _w, bmn, bops in insns:
        if (COND_BRANCH.match(bmn) or FLOW.match(bmn)) and bops.split(" ")[0] in landing_on:
            return None
    return idx - 1


def writes_reg(mn, ops, reg):
    """Whether an instruction writes %reg: its destination, an exg, a
    moveml into a list naming it, or a post-increment or pre-decrement
    through it."""
    r = "%" + reg
    if mn.startswith(("cmp", "tst", "btst", "pea", "jsr", "bsr", "jmp")) or COND_BRANCH.match(mn) \
            or mn.startswith("bra"):
        return False
    if r + "@+" in ops or r + "@-" in ops:
        return True
    if mn == "exg":
        return r in ops.split(",")
    if mn.startswith("moveml"):
        dst = ops.rsplit(",", 1)[-1]
        return "@" not in dst and reg in reglist(dst)
    return ops.endswith("," + r) or ops == r


def reglist(text):
    """The registers of a moveml list such as %d2-%d6/%a2-%a4."""
    out = set()
    for part in text.split("/"):
        m = re.match(r"^%([da])([0-7])(?:-%([da])([0-7]))?$", part)
        if not m:
            continue
        if m.group(3) is None:
            out.add(m.group(1) + m.group(2))
            continue
        lo, hi = int(m.group(2)) + (8 if m.group(1) == "a" else 0), int(m.group(4)) + (8 if m.group(3) == "a" else 0)
        out.update(("d" if v < 8 else "a") + str(v % 8) for v in range(lo, hi + 1))
    return out


def interleaved_ok(insns, k, idx, ea, n, got=None):
    """For a bound branch at insns[k] that follows other conditional
    branches: the compared operand is the dispatch's index register %dI,
    nothing writes it between the branch and the dispatch but its doubling,
    and a table loaded through %aN reads T itself: `moveal #T,%aN' within
    LOOKBACK, or in a shared object `moveal %a5@(d),%aN' with %a5 the GOT
    (a5_is_got) and the slot GOT+d an R_68K_RELATIVE to T (got: data,
    sections, got_context and the function's start), no branch from before
    it into the code that reaches the
    dispatch from it, and nothing in that code writing %aN (the restore
    before an rts aside, and the table's own words)."""
    li = load_index(insns, idx)
    if li is None or ea != "%" + li[0]:
        return False
    reg, base = li
    for p in range(k + 1, idx - 1):
        mn, ops = insns[p][2], insns[p][3]
        if writes_reg(mn, ops, reg) and not (p == idx - 2 and mn == "addl" and ops == "%%%s,%%%s" % (reg, reg)):
            return False
    if base is None:
        return True
    base = "a6" if base == "fp" else base
    t = int(DISPATCH.match(insns[idx][3]).group(1), 16)
    mv = None
    for p in range(idx - 2, max(0, idx - LOOKBACK) - 1, -1):
        mn, ops = insns[p][2], insns[p][3]
        if mn == "moveal" and re.match(r"^#(-?\d+),%" + base + "$", ops):
            if int(ops[1:ops.index(",")]) & 0xffffffff != t:
                return False
            mv = p
            break
        if mn == "moveal" and ops.startswith("%a5@(") and ops.endswith(",%" + base) and got is not None:
            data, secs, (gaddr, slots), fstart = got
            gl = got_load(data, secs, insns[p][0])
            if gl is None or "a%d" % gl[0] != base or slots.get((gaddr + gl[1]) & 0xffffffff) != t \
                    or not a5_is_got(insns, p, gaddr, fstart):
                return False
            mv = p
            break
        if writes_reg(mn, ops, base):
            return False
    if mv is None:
        return False
    # the region that can reach the dispatch without passing the moveal: from
    # the moveal on, grown to every branch back into it until none is left
    # (a stripped program has no function ends to stop at); no branch from
    # before the moveal may enter it, and nothing in it may write %aN
    brs = []
    for p, (a, _w, mn, ops) in enumerate(insns):
        if COND_BRANCH.match(mn) or mn.startswith(("bra", "jmp")):
            m = re.match(r"^([0-9a-f]+)\b", ops)
            if m:
                brs.append((p, int(m.group(1), 16)))
    lo_a, hi_p = insns[mv][0], idx
    while True:
        far = hi_p
        for p, tgt in brs:
            if lo_a < tgt <= insns[hi_p][0]:
                if p < mv:
                    return False
                far = max(far, p)
        if far == hi_p:
            break
        hi_p = far
    for p in range(mv + 1, hi_p + 1):
        a, _w, mn, ops = insns[p]
        if t <= a < t + 2 * n:
            continue
        if writes_reg(mn, ops, base) and not (mn.startswith("moveml") and p + 1 < len(insns)
                                              and insns[p + 1][2] == "rts"):
            return False
    return True


def masked_entry_bound(insns, block, idx, mask):
    """Entry count when a dispatch block at insns[block], its index masked
    to `mask' entries, is entered only by branches each bounded on that
    index: `cmp[i]{b,w,l} #N,%dI ; bls block', the compare at least as wide
    as the mask (a byte compare bounds only an index masked to a byte), %dI
    the index register at the block's start (through the block's doubling,
    masks and copies).  The largest N+1, else None."""
    reg = index_register(insns, idx)
    if reg is None:
        return None
    for p in range(idx - 2, block - 1, -1):
        mn, ops = insns[p][2], insns[p][3]
        if not writes_reg(mn, ops, reg):
            continue
        if (mn == "addl" and ops == "%%%s,%%%s" % (reg, reg)) or mask_bound(insns, p) is not None:
            continue
        m = re.match(r"^%(d[0-7]),%" + reg + "$", ops)
        if mn == "movel" and m:
            reg = m.group(1)
            continue
        return None
    target = "%x" % insns[block][0]
    found = []
    for k, (_a, _w, mn, ops) in enumerate(insns):
        if not (COND_BRANCH.match(mn) or mn.startswith(("bra", "bsr", "jmp"))):
            continue
        if ops.split(" ")[0] != target:
            continue
        if k == 0 or not mn.startswith("bls"):
            return None
        pmn, pops = insns[k - 1][2], insns[k - 1][3]
        m = BOUND_CMP.match(pops)
        if not re.match(r"^cmpi?[bwl]$", pmn) or not m or m.group(2) != "%" + reg:
            return None
        width = {"b": 0xff, "w": 0xffff, "l": 0xffffffff}[pmn[-1]]
        if mask > width + 1:
            return None
        found.append((int(m.group(1)) & width) + 1)
    return max(found) if found else None


def index_def(insns, idx, stop):
    """The instruction that gives the dispatch at insns[idx] its index: walk
    back from the table load over the doubling (`addl %dI,%dI'), and-masks
    into %dI and register copies into it, to the first other write of the
    register.  -> (position, register, [mask entry counts]) or None."""
    reg = index_register(insns, idx)
    if reg is None:
        return None
    masks = []
    for p in range(idx - 2, stop - 1, -1):
        mn, ops = insns[p][2], insns[p][3]
        if mn.startswith(("rts", "jmp", "bra")):
            return None
        if mn.startswith(("cmp", "tst", "btst")) or not ops.endswith(",%" + reg):
            continue
        if mn == "addl" and ops == "%%%s,%%%s" % (reg, reg):
            continue
        n = mask_bound(insns, p)
        if n is not None:
            masks.append(n)
            continue
        m = re.match(r"^%([da][0-7]|fp),%" + reg + "$", ops)
        if mn == "movel" and m:
            reg = m.group(1)
            continue
        return p, reg, masks
    return None


def bitfield_bound(insns, idx, stop):
    """2^width when the index is `bfextu <ea>,<off>,<width>,%dI' (zero-extended,
    0 .. 2^width - 1; python 3.11's incrementalnewlinedecoder_newlines_get:
    `bfextu %a1@(16),2,3,%d0 ; andil #255,%d0'), a mask after it narrowing it
    further; else None.  objdump prints a literal width as a bare number."""
    d = index_def(insns, idx, stop)
    if d is None:
        return None
    p, reg, masks = d
    if insns[p][2] != "bfextu":
        return None
    m = re.match(r"^.+,(?:\d+|%d[0-7]),(\d+),%" + reg + "$", insns[p][3])
    if not m or not 1 <= int(m.group(1)) <= 16:
        return None
    return min([1 << int(m.group(1))] + masks)


def width_bound(insns, idx, stop):
    """The most entries the index can take when it is provably a byte or a
    word: an and-mask into it (2^k), or a zero-extended byte or word load
    (`moveq #0,%dI' or `clrl %dI', then `moveb/movew <ea>,%dI'); else None."""
    d = index_def(insns, idx, stop)
    if d is None:
        return None
    p, reg, masks = d
    if masks:
        return min(masks)
    mn = insns[p][2]
    if mn not in ("moveb", "movew") or not reg.startswith("d"):
        return None
    for q in range(p - 1, max(stop, p - 6) - 1, -1):
        qm, qo = insns[q][2], insns[q][3]
        if qm.startswith(("cmp", "tst", "btst")) or not (qo.endswith(",%" + reg) or qo == "%" + reg):
            continue
        if (qm == "moveq" and qo == "#0,%" + reg) or (qm == "clrl" and qo == "%" + reg):
            return 256 if mn == "moveb" else 65536
        return None
    return None


def biased_index(insns, j, idx, src, k):
    """Whether the dispatch at insns[idx] indexes with %src + K: an
    `addql #K,%dI' (or `addl #K') into its index register %dI before the
    compare at insns[j], %dI copied from %src just before that unless it is
    %src, and nothing else writing %dI up to the dispatch but its doubling."""
    reg = index_register(insns, idx)
    if reg is None:
        return False
    add = "#%d,%%%s" % (k, reg)
    for p in range(idx - 2, max(0, j - LOOKBACK) - 1, -1):
        mn, ops = insns[p][2], insns[p][3]
        if p < j and mn in ("addql", "addl") and ops == add:
            if reg == src:
                return True
            for q in range(p - 1, max(0, p - 6) - 1, -1):
                if insns[q][2] == "movel" and insns[q][3] == "%%%s,%%%s" % (src, reg):
                    return True
                if insns[q][3].endswith(",%" + reg):
                    return False
            return False
        if ops.endswith(",%" + reg) and not mn.startswith(("cmp", "tst")) \
                and not (p == idx - 2 and mn == "addl" and ops == "%%%s,%%%s" % (reg, reg)):
            return False
    return False


def constant_index(insns, idx):
    """K when the dispatch at insns[idx] can only take entry K: `moveq #K,%dI ;
    addl %dI,%dI ; movew %pc@(T,%dI:l),... ; jmp' (a switch whose value GCC
    knew, vim 9.1, 2026-10-31), else None."""
    reg = index_register(insns, idx)
    if reg is None or idx < 2 or insns[idx - 2][2] != "addl" \
            or insns[idx - 2][3] != "%%%s,%%%s" % (reg, reg):
        return None
    return moveq_value(insns, idx - 2, "%" + reg)


def entries_run(data, secs, t, fstart, fend, cap=4096):
    """Entry count of a table at t sized from its own words: the longest run
    of entries landing on an even address of the function past the table,
    ending where the nearest case begins.  A known limit: a code word just
    after the table that also reads as such an entry is taken for one.
    -> (count, why the run ended: case, odd, outside, into or cap)."""
    n, lowest = 0, None
    while n < cap:
        if lowest is not None and t + 2 * n >= lowest:
            return n, "case"
        w = word_at(data, secs, t + 2 * n)
        if w is None:
            return n, "outside"
        tgt = t + w
        if tgt & 1:
            return n, "odd"
        if not (fstart <= tgt < fend):
            return n, "outside"
        if tgt <= t + 2 * n:
            return n, "into"
        lowest = tgt if lowest is None else min(lowest, tgt)
        n += 1
    return n, "cap"


def entries_bound(data, secs, t, fstart, fend):
    return entries_run(data, secs, t, fstart, fend)[0]


def mask_bound(insns, j):
    """Entry count M+1 when insns[j] masks a data register with M = 2^k - 1:
    `andi{b,w,l} #M,%dX', or `andl %dA,%dB' after a moveq #M into either --
    switch (x & 7), e.g. Duff's device (perl 5.8.9's sdbm, Perl_ck_fun)."""
    mn, ops = insns[j][2], insns[j][3]
    if not re.match(r"^andi?[bwl]$", mn):
        return None
    m = re.match(r"^#(\d+),%d[0-7]$", ops)
    if m:
        n = int(m.group(1))
    else:
        m = re.match(r"^%(d[0-7]),%(d[0-7])$", ops)
        if not m:
            return None
        n = moveq_value(insns, j, "%" + m.group(1))
        if n is None:
            n = moveq_value(insns, j, "%" + m.group(2))
    if n is None or n < 0 or (n + 1) & n:
        return None
    return n + 1


def entry_bound(insns, start, idx):
    """Entry count for a dispatch block at insns[start] that is entered only by
    branches: each must be a bounded conditional one --
        cmp[i]{b,w,l} #N,<ea> ; bls block       (ea <= N)
        moveq #N,%dY ; cmpl <ea>,%dY ; bcc block (N >= ea)
        moveq #N,%dY ; cmpl %dY,<ea> ; bls block (ea <= N)
    (perl 5.8.9's Perl_ref: `cmpiw #15,%d1 ; blsw' far above the block)."""
    if start >= idx:
        return None
    target = "%x" % insns[start][0]
    found = set()
    for k, (_a, _w, mn, ops) in enumerate(insns):
        if not re.match(r"^b(ra|sr|hi|ls|cc|cs|ne|eq|vc|vs|pl|mi|ge|lt|gt|le)[bswl]?$", mn):
            continue
        if ops.split(" ")[0] != target:
            continue
        if k == 0 or not mn.startswith(("bls", "bcc")):
            return None                             # an unbounded way in
        pmn, pops = insns[k - 1][2], insns[k - 1][3]
        if not re.match(r"^cmp[ai]?[bwl]$", pmn):
            return None
        n = None
        m = BOUND_CMP.match(pops)
        if m and mn.startswith("bls"):
            n = int(m.group(1))
            if pmn.endswith("b"):
                n &= 0xff
            elif pmn.endswith("w"):
                n &= 0xffff
        m = re.match(r"^(.+),%(d[0-7])$", pops)
        if n is None and m and mn.startswith("bcc"):
            n = moveq_value(insns, k - 1, "%" + m.group(2))
        m = re.match(r"^%(d[0-7]),(\S+)$", pops)
        if n is None and m and mn.startswith("bls"):
            n = moveq_value(insns, k - 1, "%" + m.group(1))
        if n is None:
            return None
        found.add(n + 1)
    return found.pop() if len(found) == 1 else None


def find_tables(insns, labels, data, secs, pts, gotc=None):
    """-> ({(start, end)}, [problems], [notes]); gotc: got_context"""
    tables, problems, notes = set(), [], []
    for idx, (a, words, mn, ops) in enumerate(insns):
        if mn != "jmp" or not words or words[0] != "4efb":
            continue
        m = DISPATCH.match(ops)
        if not m:
            if PC_INDEXED.match(ops):                # a dispatch this tool cannot read
                problems.append("dispatch at 0x%08x: unrecognised indexed jmp '%s'" % (a, ops))
            continue                                 # PLT stubs: %pc@(...)@(0)
        t = int(m.group(1), 16)
        if not (a < t <= a + 64):
            problems.append("dispatch at 0x%08x: table 0x%08x not just after it" % (a, t))
            continue
        # the offsets loaded from a table elsewhere (python 3.11, 2026-10-31:
        # `movew @(800cb792,%d5:l:2),%d0 ; jmp %pc@(800cb842,%d0:w)'): the
        # words after the jmp are no offsets, so no bound may size them
        if idx > 0 and insns[idx - 1][2] in ("movew", "moveaw"):
            m = re.match(r"^@\(([0-9a-f]+),", insns[idx - 1][3])
            if m:
                problems.append("dispatch at 0x%08x: offsets loaded from 0x%08x, not the table at 0x%08x "
                                "after the jmp (a two-level dispatch)" % (a, int(m.group(1), 16) & 0xffffffff, t))
                continue
        n = bound_for(insns, idx, (data, secs, gotc, enclosing(pts, a)[0] or 0) if gotc else None)
        k = constant_index(insns, idx) if n is None else None
        if k is not None and k >= 0:
            fstart, fend = enclosing(pts, a)
            n = entries_bound(data, secs, t, fstart, fend)
            if n <= k:
                problems.append("dispatch at 0x%08x: constant index #%d, but its table at 0x%08x "
                                "has only %d entr%s landing on code" % (a, k, t, n, "y" if n == 1 else "ies"))
                continue
            notes.append("dispatch at 0x%08x: constant index #%d; table at 0x%08x sized from its own "
                         "entries (%d), a known limit" % (a, k, t, n))
        fstart, fend = enclosing(pts, a)
        bad = landing(data, secs, t, n, fstart, fend) if n is not None and 0 < n <= 4096 else None
        if bad is None or bad:
            # the index only provably a byte or a word: sized from its own
            # entries, when the run ends on a word that cannot be an entry
            # (never over a compare's bound: there every index can be taken)
            hm = width_bound(insns, idx, max(0, idx - LOOKBACK))
            via = ""
            mid = between_insn(insns, idx) if hm is None else None
            if mid is not None:
                # the index read as if that instruction were not there
                view = insns[:mid] + insns[mid + 1:]
                hm = width_bound(view, idx - 1, max(0, idx - 1 - LOOKBACK))
                via = "; `%s %s' between the table load and the jmp" % (insns[mid][2], insns[mid][3])
            if hm is not None and n in (None, hm):
                ne, why = entries_run(data, secs, t, fstart, fend, cap=hm)
                if why == "cap" and not landing(data, secs, t, ne, fstart, fend):
                    n, bad = ne, []                  # every index the width allows lands
                elif why != "cap" and ne > 0 and not landing(data, secs, t, ne, fstart, fend):
                    notes.append("dispatch at 0x%08x: no bound check, the index at most %d; table at "
                                 "0x%08x sized from its own entries (%d, the run ending %s), trusted by shape%s"
                                 % (a, hm, t, ne, RUN_END[why], via))
                    n, bad = ne, []
                else:
                    problems.append("dispatch at 0x%08x: the index at most %d, but table 0x%08x is no run "
                                    "of entries ending on a word that cannot be one (%d, %s)"
                                    % (a, hm, t, ne, why))
                    continue
        if bad is None:
            problems.append("dispatch at 0x%08x: no bound check found, table at 0x%08x unsized" % (a, t))
            continue
        end = t + 2 * n
        if bad:
            problems.append("dispatch at 0x%08x: table 0x%08x x%d has %d entr%s not landing on code "
                            "in the function (first: #%d)" % (a, t, n, len(bad),
                                                               "y" if len(bad) == 1 else "ies", bad[0]))
            continue
        tables.add((a + 4, end))                      # dispatch tail + table
    return tables, problems, notes


RUN_END = dict(case="at the first case", odd="on an odd word", outside="on a word leading outside the function",
               into="on a word leading back into the table")


def landing(data, secs, t, n, fstart, fend):
    """The entries of an n-entry table at t that do not land on an even
    address of the function outside the table."""
    end, bad = t + 2 * n, []
    for k in range(n):
        w = word_at(data, secs, t + 2 * k)
        tgt = t + (w if w is not None else 0)
        if w is None or tgt & 1 or not (fstart <= tgt < fend) or t <= tgt < end:
            bad.append(k)
    return bad


def dispatch_of(problem):
    """The dispatch address a find_tables problem names, else None."""
    m = re.match(r"^dispatch at 0x([0-9a-f]+):", problem)
    return int(m.group(1), 16) if m else None


def resync_listing(tool, path, secs, names, skip):
    out = ""
    for (sa, _so, sz), sec in zip(secs, names):
        lo, hi = sa, sa + sz
        for s, e in sorted(r for r in skip if sa <= r[0] < hi):
            if s > lo:
                out += objdump(tool, path, sec, lo, s)
            lo = max(lo, e)
        if lo < hi:
            out += objdump(tool, path, sec, lo, hi)
    return out


def scan(tool, path):
    data = open(path, "rb").read()
    secs = exec_sections(data)
    names = exec_section_names(tool, path, secs)
    listing = resync_listing(tool, path, secs, names, set())
    if "Disassembly of section" not in listing:
        die("%s: objdump produced no disassembly" % path)
    insns, labels = parse(listing)
    if not insns:
        die("%s: objdump's listing holds no instruction" % path)
    pts = function_bounds(labels, secs, data)
    sysroot = os.environ.get("AMIX_SYSROOT", "")
    known, knotes, kproblems = known_data(data, secs, sysroot) if sysroot else ([], [], [])
    objs = data_objects(data, secs)
    known = set(known) | set(objs)
    knotes += ["data object in .text at 0x%08x: %s, %d bytes" % (s, objs[(s, e)], e - s)
               for s, e in sorted(objs)]
    gotc = got_context(data)
    skip, problems, notes = find_tables(insns, labels, data, secs, pts, gotc)
    skip |= known
    problems += kproblems
    for _round in range(6):
        if not skip:
            break
        listing = resync_listing(tool, path, secs, names, skip)
        insns, _l = parse(listing)
        new, more, more_notes = find_tables(insns, labels, data, secs, pts, gotc)
        problems = sorted(set(problems) | set(more))
        notes = sorted(set(notes) | set(more_notes))
        if not (new - skip):
            break
        skip |= new
    # A problem an earlier round met at a dispatch that a later, re-synced
    # round sized is stale: the first table's data had swallowed the next
    # dispatch's bound check (diffutils 2.8.1 groups_letter_value, two
    # back-to-back switches, 2026-10-29).
    sized = {s - 4 for s, _e in skip}
    problems = [p for p in problems if dispatch_of(p) not in sized]
    # sync: every label inside a code region (not a table) must start an insn
    starts = {i[0] for i in insns}
    desync = []
    for la, name in sorted(labels.items()):
        if not any(sa <= la < sa + sz for sa, _o, sz in secs):
            continue
        if any(s <= la < e for s, e in skip):
            continue
        if la not in starts:
            desync.append("%s at 0x%08x" % (name, la))
    hits, total_long = [], 0
    for a, words, mn, ops in insns:
        op = int(words[0], 16)
        if (op & 0xff80) == 0x4c00 and len(words) >= 2:
            total_long += 1
            if int(words[1], 16) & 0x0400:
                hits.append("0x%08x %s %s -- 64-bit %s" % (a, mn, ops, "divide" if op & 0x40 else "product"))
        elif MNEM_OTHER.match(mn):
            hits.append("0x%08x %s %s -- not implemented on the 68060" % (a, mn, ops))
    sized = {s for s, _e in skip}
    notes = [n for n in notes if int(re.match(r"^dispatch at 0x([0-9a-f]+)", n).group(1), 16) + 4 in sized]
    return dict(insns=len(insns), tables=sorted(skip), starts=sorted(starts), problems=problems,
                desync=desync, hits=hits, total_long=total_long, notes=notes + knotes,
                known=len(known))


def explain(tables, hitfile, starts):
    """-> (all hit addresses, in-table, odd, mid, unexplained), or None when
    the hit lines read are not as many as scan060.py's HITS lines count.  A hit is
    data if it lies inside a sized table; it is a decode artifact if its
    address is odd (every 680x0 instruction starts on an even address, so a
    decode starting at an odd one is out of sync by construction), or if it
    lies inside an instruction of this tool's re-synced listing, not at its
    start: between two instruction starts at most 22 bytes apart (the
    longest 680x0 instruction) with no table between them.  scan060.py
    sizes a table up to its smallest positive offset, or not at all when
    every offset is negative; it then decodes the last entries and the code
    after them as one instruction and lands inside the next (CDE 2.5.3's
    dtwm: `0068 01d8 23ef' read as an oriw, then the 0588 inside `movel
    %sp@(36),0x803b0588' as a movepw)."""
    # scan060.py's hit lines, `      <addr> <sym> <mnem> <ops>  -- <why>': the
    # address as objdump prints it, any width (a shared object is linked at 0:
    # 22c51 in libXaw.so.6.1, 2026-11-22); its `HITS <n>' lines say how many
    addrs, said = [], 0
    for raw in open(hitfile, errors="replace"):
        m = re.match(r"^\s+([0-9a-f]+) <[^>]*> \S.*  -- ", raw)
        if m:
            addrs.append(int(m.group(1), 16))
        m = re.match(r"^\s+HITS\s+(\d+)\s", raw)
        if m:
            said += int(m.group(1))
    if said != len(addrs):
        return None
    intab = [a for a in addrs if any(s <= a < e for s, e in tables)]
    odd = [a for a in addrs if a & 1 and a not in intab]
    mid = []
    for a in addrs:
        if a in intab or a in odd:
            continue
        i = bisect.bisect_left(starts, a)
        if i == 0 or i == len(starts) or starts[i] == a:
            continue
        s, n = starts[i - 1], starts[i]
        if n - s <= 22 and not any(t < n and s < e for t, e in tables):
            mid.append(a)
    unexplained = [a for a in addrs if a not in intab and a not in odd and a not in mid]
    return addrs, intab, odd, mid, unexplained


def main(argv):
    tool = os.environ.get("OBJDUMP") or "m68k-elf-objdump"
    hitfile = None
    args = argv[1:]
    while args and args[0].startswith("--"):
        if args[0] == "--objdump" and len(args) > 1:
            tool, args = args[1], args[2:]
        elif args[0] == "--explain" and len(args) > 1:
            hitfile, args = args[1], args[2:]
        else:
            die("usage: scan060-g14.py [--objdump PATH] [--explain HITFILE] <elf>...")
    if not args:
        die("usage: scan060-g14.py [--objdump PATH] [--explain HITFILE] <elf>...")
    # said once per run: without the sysroot's archives the stock data GCC 14
    # programs carry in .text (KNOWN_STOCK_DATA) reads as code, so hits in
    # such a run may be that data
    sysroot = os.environ.get("AMIX_SYSROOT", "")
    if not sysroot or not os.path.isdir(os.path.join(sysroot, "usr", "lib")):
        print("  NOTE %s: known stock data in .text not applied (KNOWN_STOCK_DATA, "
              "e.g. libcrypt.a's des_crypt.o tables); set AMIX_SYSROOT=$(m68k-elf-gcc "
              "-print-sysroot)" % ("no AMIX_SYSROOT" if not sysroot
                                   else "AMIX_SYSROOT=%s has no usr/lib" % sysroot))
    rc = 0
    for path in args:
        r = scan(tool, path)
        name = os.path.basename(path)
        if hitfile is not None:
            if r["problems"] or r["desync"]:
                print("  UNTRUSTWORTHY %s: cannot explain scan060.py hits -- %s"
                      % (name, "; ".join(r["problems"] + r["desync"])[:300]))
                rc = max(rc, 3)
                continue
            ex = explain(r["tables"], hitfile, r["starts"])
            if ex is None:
                print("  UNTRUSTWORTHY %s: %s's hit lines are not as many as its HITS lines count"
                      % (name, hitfile))
                rc = max(rc, 3)
                continue
            addrs, intab, odd, mid, unexplained = ex
            if not addrs:
                print("  UNTRUSTWORTHY %s: %s names no hit to explain" % (name, hitfile))
                rc = max(rc, 3)
            elif unexplained:
                print("  UNEXPLAINED %s: %d of %d scan060.py hit(s) at an even address outside every sized table: %s"
                      % (name, len(unexplained), len(addrs), " ".join("%08x" % a for a in unexplained)))
                rc = max(rc, 1)
            else:
                print("  explained %s: %d scan060.py hit(s) -- %d inside the %d sized switch tables and known "
                      "stock data ranges (data), %d at odd addresses (decode out of sync)%s"
                      % (name, len(addrs), len(intab), len(r["tables"]), len(odd),
                         ", %d inside an instruction of the re-synced listing (decode out of sync)" % len(mid)
                         if mid else ""))
            continue
        if r["problems"] or r["desync"]:
            print("  UNTRUSTWORTHY %s:" % name)
            for p in r["problems"] + ["decoder off-boundary at label " + d for d in r["desync"][:8]]:
                print("    " + p)
            rc = max(rc, 3)
            continue
        if r["hits"]:
            print("  HITS %d %s (%d insns, %d switch tables sized):" % (len(r["hits"]), name, r["insns"], len(r["tables"]) - r["known"]))
            for h in r["hits"]:
                print("    " + h)
            rc = max(rc, 1)
            continue
        print("  CLEAN %s (%d insns, %d switch tables sized, %d long mul/div, none 64-bit; no movep/cmp2/chk2/cas2)"
              % (name, r["insns"], len(r["tables"]) - r["known"], r["total_long"]))
        for n in r["notes"]:
            print("    NOTE " + n)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
